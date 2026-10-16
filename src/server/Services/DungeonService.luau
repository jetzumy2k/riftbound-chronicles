--!strict
--[[
	DungeonService (Layer 5) — instanced dungeon runs for parties
	(PLAN.md Phase 9, D-32, D-38, D-39; SECURITY_MODEL T-12, T-15, T-31).

	Entering:
	  The "Rift Dungeons" gate in each capital has a ProximityPrompt (Roblox
	  resolves it on the server, so entering needs no remote).
	  - Solo players enter alone.
	  - In a party, only the leader opens the dungeon; members of the same
	    realm standing within Dungeon.GateJoinRadius of the gate come along.
	  - While the party's run is on, any member can enter through the gate
	    later (or again) and arrives next to the party leader.

	Run:
	  - A free slot (WorldLayout.DungeonSlots, ≤ Dungeon.MaxSlots) gets a
	    clone of the map template; members are teleported in by TravelService.
	  - Rooms activate one at a time (enemy HP scaled by party size);
	    defeating them all opens the next door.
	  - The last room's boss runs on BossService; if no member is alive in the
	    boss room for Dungeon.WipeResetSeconds, the boss resets.
	  - Defeat (D-39): a member respawns next to the party leader (or another
	    living member if the leader is down). If the whole party is down, the
	    run ends and everyone respawns in front of the dungeon gate; the
	    party stays together and can go straight back in.
	  - Clear: every member present claims "D:<runId>" once (idempotent,
	    DATA_MODEL §4.2) for the clear EXP, then returns after
	    Dungeon.ClearReturnSeconds (or via the exit portal / Leave).
	  - Kill EXP is shared among members near the kill (D-32).
	  - Leaving or disconnecting removes you from the run; an empty run's
	    instance is destroyed.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local DungeonDefinitions = require(Shared.Definitions.DungeonDefinitions)
local DungeonRules = require(Shared.Logic.DungeonRules)
local PartyRules = require(Shared.Logic.PartyRules)
local WorldLayout = require(Shared.Definitions.WorldLayout)
local Log = require(Shared.Util.Log)

local AuditLogService = require(script.Parent.AuditLogService)
local ConfigurationService = require(script.Parent.ConfigurationService)
local NetService = require(script.Parent.NetService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local LevelService = require(script.Parent.LevelService)
local CombatService = require(script.Parent.CombatService)
local WorldService = require(script.Parent.WorldService)
local TravelService = require(script.Parent.TravelService)
local MobService = require(script.Parent.MobService)
local BossService = require(script.Parent.BossService)
local PartyService = require(script.Parent.PartyService)
local DungeonBuilder = require(script.Parent.Parent.World.DungeonBuilder)

local DUNGEON_ID = "RiftHollow" -- the one dungeon behind the capital gates (Phase 9)
local GATE_ID = "Dungeons"
local GATE_REACH = 24
local GATE_FRONT = 16
local TICK_SECONDS = 1

local log = Log.new("DungeonService")

type Run = {
	id: string,
	dungeon: DungeonDefinitions.Dungeon,
	slot: number,
	origin: CFrame,
	map: Model,
	-- The party that owns the run (nil = a solo run).
	party: PartyService.Party?,
	solo: Player?,
	members: { [Player]: boolean },
	race: string,
	room: number,
	roomMobs: { [MobService.Mob]: boolean },
	roomGoal: number,
	roomDefeated: number,
	boss: BossService.Boss?,
	bossName: string?,
	emptyBossRoomSince: number?,
	state: "Active" | "Cleared" | "Failed",
	clearedAt: number?,
	clearXp: number,
}

local DungeonService = {}

local template: Model? = nil
local folder: Folder
local runs: { [string]: Run } = {}
local runByPlayer: { [Player]: Run } = {}
local runByParty: { [PartyService.Party]: Run } = {}
local slots: { [number]: Run } = {}
-- Where each player of a wiped party respawns (in front of the gate).
local wipeTargets: { [Player]: CFrame } = {}
local counter = 0

local function config(): any
	return ConfigurationService:Get("Dungeon")
end

local function notify(player: Player, kind: string, key: string, params: { [string]: string }?)
	NetService:FireClient("Notify", player, { kind = kind, textKey = key, params = params })
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function alive(player: Player): boolean
	return player.Parent == Players and rootOf(player) ~= nil and not CombatService:IsDefeated(player)
end

local function memberCount(run: Run): number
	local n = 0
	for _ in run.members do
		n += 1
	end
	return n
end

local function leaderOf(run: Run): Player?
	if run.party then
		return run.party.leader
	end
	return run.solo
end

-- In front of the race's dungeon gate, facing away from it.
local function gateFrontCFrame(race: string): CFrame?
	local realm = WorldLayout.realmFor(race)
	if realm == nil then
		return nil
	end
	local point, facing = WorldLayout.gateFront(realm, GATE_ID, GATE_FRONT)
	if point == nil or facing == nil then
		return nil
	end
	local p = Vector3.new(point[1], point[2] + 4, point[3])
	return CFrame.lookAt(p, p + Vector3.new(facing[1], 0, facing[3]))
end

--------------------------------------------------------------------------------
-- State pushes (display only)
--------------------------------------------------------------------------------

local function sendNone(player: Player)
	NetService:FireClient("DungeonState", player, { phase = "None" })
end

local function pushRun(run: Run, only: Player?)
	local roomDef = run.dungeon.rooms[run.room]
	local bossHp = if run.boss then CombatService:HpFraction(run.boss.mob.model) else nil
	local leader = leaderOf(run)
	for player in run.members do
		if only and player ~= only then
			continue
		end
		NetService:FireClient("DungeonState", player, {
			phase = run.state,
			dungeon = run.dungeon.name,
			room = roomDef.name,
			objective = if run.state == "Cleared"
				then "Dungeon cleared! Leave through the portal."
				else roomDef.objective,
			progress = run.roomDefeated,
			goal = run.roomGoal,
			roomIndex = run.room,
			roomCount = #run.dungeon.rooms,
			members = memberCount(run),
			maxMembers = run.dungeon.maxParty,
			leader = if leader then leader.DisplayName else nil,
			xp = if run.state == "Cleared" then run.clearXp else nil,
			bossName = if run.boss and run.state == "Active" then run.bossName else nil,
			bossHp = if run.state == "Active" then bossHp else nil,
			countdown = if run.state == "Cleared" and run.clearedAt
				then math.max(0, run.clearedAt + config().ClearReturnSeconds - os.clock())
				else nil,
		})
	end
end

--------------------------------------------------------------------------------
-- Map helpers
--------------------------------------------------------------------------------

local function mapPart(run: Run, name: string): BasePart?
	local part = run.map:FindFirstChild(name, true)
	return if part and part:IsA("BasePart") then part else nil
end

local function arrivalCFrame(run: Run, index: number): CFrame
	local arrival = mapPart(run, "Arrival")
	local base = if arrival then arrival.Position else run.origin.Position + Vector3.new(0, 3, 4)
	local p = base + Vector3.new((index - 1) * 4, 1, 0)
	return CFrame.lookAt(p, p + run.origin.LookVector)
end

-- Next to `ally` (a living run member), a few studs behind them.
local function besideCFrame(ally: Player): CFrame?
	local root = rootOf(ally)
	if root == nil then
		return nil
	end
	local behind = root.CFrame * CFrame.new(math.random(-3, 3), 1, 5)
	return CFrame.lookAt(behind.Position, behind.Position + root.CFrame.LookVector)
end

local function openDoor(run: Run, roomIndex: number)
	local door = mapPart(run, `Door_{roomIndex}`)
	if door then
		door.CanCollide = false
		TweenService:Create(door, TweenInfo.new(0.8), { Transparency = 1 }):Play()
	end
end

--------------------------------------------------------------------------------
-- Run lifecycle
--------------------------------------------------------------------------------

local endRun: (run: Run, reason: string) -> ()

local function xpRecipientsFor(run: Run): (mob: MobService.Mob) -> { Player }
	return function(mob)
		local radius = config().XpShareRadius
		local out = {}
		for player in run.members do
			local root = rootOf(player)
			if
				root
				and not CombatService:IsDefeated(player)
				and (root.Position - mob.root.Position).Magnitude <= radius
			then
				table.insert(out, player)
			end
		end
		return out
	end
end

local function activateRoom(run: Run, index: number)
	run.room = index
	run.roomMobs = {}
	run.roomDefeated = 0
	run.emptyBossRoomSince = nil
	local roomDef = run.dungeon.rooms[index]
	local hpScale = DungeonRules.partyHpScale(math.max(1, memberCount(run)), config().PartyHpPerExtraMember)
	local recipients = xpRecipientsFor(run)
	for _, spawn in roomDef.spawns do
		local at = run.origin * DungeonBuilder.spawnCFrame(run.dungeon, index, spawn.x, spawn.z)
		local mob = MobService:Spawn(
			spawn.enemy,
			at,
			{ owner = run.id, hpScale = hpScale, xpRecipients = recipients }
		)
		if mob then
			run.roomMobs[mob] = true
			if roomDef.boss then
				run.boss = BossService:Attach(mob, roomDef.boss, run.id, function(key)
					for player in run.members do
						notify(player, "Warning", key)
					end
				end)
				run.bossName = mob.enemy.name
			end
		end
	end
	local goal = 0
	for _ in run.roomMobs do
		goal += 1
	end
	run.roomGoal = goal
	pushRun(run)
end

local function grantClear(run: Run, player: Player)
	local xp = run.clearXp
	local status = (PlayerDataService :: any):ClaimReward(player, `D:{run.id}`, function(_data: any)
		LevelService:GrantXP(player, xp, `Dungeon:{run.dungeon.id}`)
	end)
	if status == "granted" then
		notify(player, "Info", "dungeon.cleared", { xp = tostring(xp) })
	end
end

local function clearRun(run: Run)
	if run.state ~= "Active" then
		return
	end
	run.state = "Cleared"
	run.clearedAt = os.clock()
	if run.boss then
		for _, add in run.boss.adds do
			MobService:Despawn(add)
		end
		BossService:Detach(run.boss.mob)
	end
	for player in run.members do
		grantClear(run, player)
	end
	log:Info("run %s cleared by %d players", run.id, memberCount(run))
	pushRun(run)
end

local function onMobDefeated(mob: MobService.Mob)
	local run = runs[mob.owner]
	if run == nil or run.state ~= "Active" or not run.roomMobs[mob] then
		return
	end
	run.roomMobs[mob] = nil
	run.roomDefeated += 1
	if next(run.roomMobs) ~= nil then
		pushRun(run)
		return
	end
	if run.room >= #run.dungeon.rooms then
		clearRun(run)
		return
	end
	for player in run.members do
		notify(player, "Info", "dungeon.roomCleared")
	end
	openDoor(run, run.room + 1)
	activateRoom(run, run.room + 1)
end

-- Takes `player` out of the run. Living players are moved out to the gate.
local function removeMember(run: Run, player: Player, moveOut: boolean)
	if run.members[player] == nil then
		return
	end
	run.members[player] = nil
	runByPlayer[player] = nil
	if player.Parent == Players then
		sendNone(player)
	end
	if moveOut and alive(player) then
		local outside = gateFrontCFrame(run.race) or TravelService:GetHomeCFrame(player)
		if outside then
			task.spawn(TravelService.Teleport, TravelService, player, outside)
		end
	end
	if memberCount(run) == 0 then
		endRun(run, "empty")
	else
		pushRun(run)
	end
end

function endRun(run: Run, reason: string)
	if runs[run.id] ~= run then
		return
	end
	runs[run.id] = nil
	slots[run.slot] = nil
	if run.party and runByParty[run.party] == run then
		runByParty[run.party] = nil
	end
	for player in table.clone(run.members) do
		removeMember(run, player, true)
	end
	if run.boss then
		BossService:Detach(run.boss.mob)
	end
	MobService:DespawnOwner(run.id)
	run.map:Destroy()
	local active = 0
	for _ in runs do
		active += 1
	end
	log:Info("run %s ended (%s); %d active runs", run.id, reason, active)
end

-- The whole party is down: everyone comes back in front of the gate.
local function wipe(run: Run)
	if run.state ~= "Active" then
		return
	end
	run.state = "Failed"
	local outside = gateFrontCFrame(run.race)
	for player in run.members do
		if outside then
			wipeTargets[player] = outside
		end
		notify(player, "Warning", "dungeon.wiped")
		runByPlayer[player] = nil
		sendNone(player)
	end
	run.members = {}
	endRun(run, "wiped")
end

local function startRun(race: string, players: { Player }, party: PartyService.Party?)
	local dungeon = DungeonDefinitions.get(DUNGEON_ID) :: DungeonDefinitions.Dungeon
	local slot: number? = nil
	for i = 1, math.min(config().MaxSlots, WorldLayout.DungeonSlots.maxSlots) do
		if slots[i] == nil then
			slot = i
			break
		end
	end
	if slot == nil or template == nil then
		for _, player in players do
			notify(player, "Warning", "dungeon.busy")
		end
		return
	end

	counter += 1
	local server = if game.JobId ~= "" then game.JobId else HttpService:GenerateGUID(false)
	local o = WorldLayout.dungeonSlotOrigin(slot)
	local origin = CFrame.new(o[1], o[2], o[3])
	local map = (template :: Model):Clone()
	map.Name = `Run_{slot}`
	map:PivotTo(origin * CFrame.new(0, 0.5, 0))
	map.Parent = folder

	local run: Run = {
		id = DungeonRules.runId(server, counter),
		dungeon = dungeon,
		slot = slot,
		origin = origin,
		map = map,
		party = party,
		solo = if party then nil else players[1],
		members = {},
		race = race,
		room = 1,
		roomMobs = {},
		roomGoal = 0,
		roomDefeated = 0,
		boss = nil,
		bossName = nil,
		emptyBossRoomSince = nil,
		state = "Active",
		clearedAt = nil,
		clearXp = dungeon.clearXp,
	}
	runs[run.id] = run
	slots[slot] = run
	if party then
		runByParty[party] = run
	end
	for _, player in players do
		run.members[player] = true
		runByPlayer[player] = run
	end

	-- Exit portal: leave any time.
	local exit = mapPart(run, "Exit")
	if exit then
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Leave dungeon"
		prompt.ObjectText = dungeon.name
		prompt.HoldDuration = 0.4
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt.Parent = exit
		prompt.Triggered:Connect(function(player)
			if runByPlayer[player] == run then
				removeMember(run, player, true)
			end
		end)
	end

	activateRoom(run, 1)
	for index, player in players do
		task.spawn(TravelService.Teleport, TravelService, player, arrivalCFrame(run, index))
	end
	AuditLogService:Audit({
		actorUserId = 0,
		action = "DungeonStart",
		target = run.id,
		details = { slot = slot, players = #players, party = party ~= nil },
	})
	log:Info("run %s started in slot %d with %d players", run.id, slot, #players)
end

-- A party member enters the party's ongoing run (late, or again).
local function joinRun(run: Run, player: Player)
	local returning = run.members[player] == true
	run.members[player] = true
	runByPlayer[player] = run
	log:Info("user=%d %s run %s", player.UserId, if returning then "re-entered" else "joined", run.id)
	local leader = leaderOf(run)
	local target = if leader
			and leader ~= player
			and run.members[leader]
			and alive(leader)
		then besideCFrame(leader)
		else nil
	if target == nil then
		for other in run.members do
			if other ~= player and alive(other) then
				target = besideCFrame(other)
				break
			end
		end
	end
	task.spawn(TravelService.Teleport, TravelService, player, target or arrivalCFrame(run, 1))
	if not returning then
		for member in run.members do
			if member ~= player then
				notify(member, "Info", "dungeon.memberJoined", { name = player.DisplayName })
			end
		end
	end
	pushRun(run)
end

--------------------------------------------------------------------------------
-- Gate
--------------------------------------------------------------------------------

local function onGate(player: Player, gateRace: string, gate: BasePart)
	local data = PlayerDataService:GetData(player)
	local root = rootOf(player)
	local dungeon = DungeonDefinitions.get(DUNGEON_ID) :: DungeonDefinitions.Dungeon
	if data == nil or root == nil or CombatService:IsDefeated(player) then
		return
	end
	if not config().Enabled then
		notify(player, "Warning", "dungeon.disabled")
		return
	end
	-- Only your own capital's gate, from right next to it (T-15).
	if data.Race ~= gateRace or (root.Position - gate.Position).Magnitude > GATE_REACH then
		return
	end
	local current = runByPlayer[player]
	if current then
		if current.state == "Active" then
			-- The server still counts you in the run but you are out here
			-- (e.g. a respawn that didn't land inside): straight back in.
			joinRun(current, player)
			return
		end
		-- Cleared or failed run you are no longer in: let go of it.
		removeMember(current, player, false)
	end
	local level = LevelService:GetLevel(player) or 0
	if level < dungeon.minLevel then
		notify(player, "Warning", "dungeon.level", { level = tostring(dungeon.minLevel) })
		return
	end

	local party = PartyService:GetParty(player)
	if party then
		local ongoing = runByParty[party]
		if ongoing and ongoing.state == "Active" then
			joinRun(ongoing, player)
			return
		end
		if party.leader ~= player then
			notify(player, "Warning", "dungeon.leaderOnly")
			return
		end
	end

	-- Leader (or solo player) opens the dungeon; nearby members come along.
	local entering = { player }
	if party then
		local radius = config().GateJoinRadius
		for _, member in party.members do
			if member == player then
				continue
			end
			local memberRoot = rootOf(member)
			local near = memberRoot and (memberRoot.Position - gate.Position).Magnitude <= radius
			local memberLevel = LevelService:GetLevel(member) or 0
			if near and alive(member) and runByPlayer[member] == nil and memberLevel >= dungeon.minLevel then
				table.insert(entering, member)
			else
				notify(member, "Info", "dungeon.partyEntered", { name = player.DisplayName })
			end
		end
	end
	local ok = DungeonRules.canEnter(level, #entering, dungeon.minLevel, dungeon.maxParty)
	if not ok then
		notify(player, "Warning", "dungeon.full")
		return
	end
	startRun(gateRace, entering, party)
end

--------------------------------------------------------------------------------
-- Ticking: boss resets, cleared returns
--------------------------------------------------------------------------------

local function livingMembersInRoom(run: Run, index: number): number
	local volume = mapPart(run, `Room_{index}`)
	if volume == nil then
		return 0
	end
	local n = 0
	for player in run.members do
		local root = rootOf(player)
		if root and not CombatService:IsDefeated(player) then
			local p = volume.CFrame:PointToObjectSpace(root.Position)
			local half = volume.Size / 2
			if math.abs(p.X) <= half.X and math.abs(p.Y) <= half.Y + 10 and math.abs(p.Z) <= half.Z then
				n += 1
			end
		end
	end
	return n
end

local function tickRun(run: Run, now: number)
	if memberCount(run) == 0 then
		endRun(run, "empty")
		return
	end
	if run.state == "Cleared" then
		if run.clearedAt and now - run.clearedAt >= config().ClearReturnSeconds then
			endRun(run, "cleared")
		else
			pushRun(run)
		end
		return
	end
	local boss = run.boss
	if boss and boss.engaged then
		if livingMembersInRoom(run, run.room) == 0 then
			run.emptyBossRoomSince = run.emptyBossRoomSince or now
			if now - (run.emptyBossRoomSince :: number) >= config().WipeResetSeconds then
				run.emptyBossRoomSince = nil
				BossService:Reset(boss)
				for player in run.members do
					notify(player, "Warning", "dungeon.bossReset")
				end
			end
		else
			run.emptyBossRoomSince = nil
		end
		pushRun(run)
	end
end

--------------------------------------------------------------------------------
-- Defeat and respawns (D-39)
--------------------------------------------------------------------------------

local function onDefeated(entity: CombatService.Entity)
	local player = entity.player
	local run = if player then runByPlayer[player] else nil
	if run == nil or run.state ~= "Active" then
		return
	end
	for member in run.members do
		if alive(member) then
			return -- someone is still standing
		end
	end
	wipe(run)
end

local function resolveRespawn(player: Player): CFrame?
	local wiped = wipeTargets[player]
	if wiped then
		wipeTargets[player] = nil
		log:Info("user=%d respawns at the gate after a wipe", player.UserId)
		return wiped
	end
	local run = runByPlayer[player]
	if run == nil then
		return nil
	end
	local leader = leaderOf(run)
	local leaderAlive = leader ~= nil and leader ~= player and run.members[leader] == true and alive(leader)
	local ally: Player? = nil
	for member in run.members do
		if member ~= player and alive(member) then
			ally = member
			break
		end
	end
	local choice = PartyRules.respawnChoice(leaderAlive, ally ~= nil)
	log:Info("user=%d respawn in run %s: %s", player.UserId, run.id, choice)
	local target = if choice == "Leader"
		then besideCFrame(leader :: Player)
		elseif choice == "Ally" then besideCFrame(ally :: Player)
		else nil
	if target then
		notify(player, "Info", "dungeon.respawnAlly")
		task.defer(pushRun, run, player)
		return target
	end
	-- Nobody to return to: out in front of the gate.
	task.defer(removeMember, run, player, false)
	return gateFrontCFrame(run.race)
end

local function onLeave(player: Player)
	local run = runByPlayer[player]
	if run then
		removeMember(run, player, true)
	end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

local function openGates()
	local dungeon = DungeonDefinitions.get(DUNGEON_ID) :: DungeonDefinitions.Dungeon
	for race in WorldLayout.Realms :: { [string]: any } do
		local gate = WorldService:GetGate(race, GATE_ID)
		if gate == nil then
			log:Warn("no %s gate in the %s capital", GATE_ID, race)
			continue
		end
		-- Unseal the gate built by CapitalBuilder.
		local gateModel = gate.Parent
		local barrier = gateModel and gateModel:FindFirstChild("SealedBarrier")
		if barrier then
			barrier:Destroy()
		end
		for _, child in gate:GetChildren() do
			if child:IsA("BillboardGui") then
				child:Destroy()
			elseif child:IsA("PointLight") then
				child.Brightness = 2.5
			end
		end
		gate.Transparency = 0.15
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = `Enter {dungeon.name}`
		prompt.ObjectText = `Rift Dungeons · Lv {dungeon.minLevel}+ · party leader enters`
		prompt.HoldDuration = 0.3
		prompt.MaxActivationDistance = 16
		prompt.RequiresLineOfSight = false
		prompt.Parent = gate
		prompt.Triggered:Connect(function(player)
			onGate(player, race, gate)
		end)
	end
end

function DungeonService:Init()
	NetService:Handle("DungeonLeave", onLeave)
	MobService.MobDefeated:Connect(onMobDefeated)
	CombatService.Defeated:Connect(onDefeated)
	TravelService:SetRespawnResolver(resolveRespawn)
	PartyService:SetDungeonCheck(function(party)
		local run = runByParty[party]
		return run ~= nil and run.state == "Active"
	end)
	-- Leaving the party mid-run also leaves the run.
	PartyService.MemberLeft:Connect(function(party, player)
		local run = runByPlayer[player]
		if run and run.party == party then
			removeMember(run, player, true)
		end
	end)
end

function DungeonService:Start()
	local storage = Instance.new("Folder")
	storage.Name = "RC_DungeonTemplates"
	local dungeon = DungeonDefinitions.get(DUNGEON_ID) :: DungeonDefinitions.Dungeon
	local built = DungeonBuilder.build(dungeon)
	built.Parent = storage
	storage.Parent = ServerStorage
	template = built

	local existing = Workspace:FindFirstChild("RC_Dungeons")
	if existing then
		existing:Destroy()
	end
	local created = Instance.new("Folder")
	created.Name = "RC_Dungeons"
	created.Parent = Workspace
	folder = created

	openGates()
	Players.PlayerRemoving:Connect(function(player)
		wipeTargets[player] = nil
		local run = runByPlayer[player]
		if run then
			removeMember(run, player, false)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(TICK_SECONDS)
			local now = os.clock()
			for _, run in runs do
				local ok, err = pcall(tickRun :: any, run, now)
				if not ok then
					log:Error("run %s tick failed: %s", run.id, tostring(err))
				end
			end
		end
	end)
	log:Info("dungeons ready (%s, %d slots)", dungeon.name, config().MaxSlots)
end

function DungeonService:IsInRun(player: Player): boolean
	return runByPlayer[player] ~= nil
end

return DungeonService
