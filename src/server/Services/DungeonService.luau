--!strict
--[[
	DungeonService (Layer 5) — persistent dungeons, one per realm
	(PLAN.md Phase 9, D-32, D-39, D-42; SECURITY_MODEL T-12, T-15).

	Map:
	  Each realm has its own copy of Rift Hollow, built once at server start
	  in a reserved slot far from the world (WorldLayout.DungeonSlots: slot 1
	  Angels, slot 2 Devils). Every player of that realm shares it; parties
	  fight together inside. There is no PvP inside (one realm per copy).
	Entering / leaving:
	  The capital "Rift Dungeons" gate (ProximityPrompt resolved on the
	  server, so no remote) takes you to your realm's dungeon entrance; you
	  need DungeonDefinitions minLevel and must be within reach of the gate.
	  The exit portal at the entrance or the tracker's Leave button returns
	  you in front of the gate.
	Creatures (MobService camps):
	  Mob       respawns Dungeon.MobRespawnSeconds after falling
	  MiniBoss  respawns after Dungeon.MiniBossRespawnMinutes
	  Boss      respawns after Dungeon.BossRespawnHours (BossService abilities)
	  In Studio the boss timers use the short Studio* values for testing.
	  An engaged boss resets if no living player is in its room for
	  Dungeon.WipeResetSeconds.
	Rewards:
	  Kill EXP is shared among the killer's party members nearby (D-32).
	  Each MiniBoss / Boss spawn also gives everyone who damaged it a one-time
	  bonus, claimed as "B:<spawnId>:<enemy>" (idempotent, DATA_MODEL §4.2).
	Defeat (D-39):
	  Inside a dungeon you respawn next to your party leader, or another
	  living party member, in the same dungeon; otherwise outside the gate.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local DungeonDefinitions = require(Shared.Definitions.DungeonDefinitions)
local EnemyDefinitions = require(Shared.Definitions.EnemyDefinitions)
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

local DUNGEON_ID = "RiftHollow" -- the dungeon behind the capital gates
local GATE_ID = "Dungeons"
local GATE_REACH = 24
local GATE_FRONT = 16
local TICK_SECONDS = 1
local SLOT_BY_RACE: { [string]: number } = { Angel = 1, Devil = 2 }

local log = Log.new("DungeonService")

type BossCamp = {
	class: "MiniBoss" | "Boss",
	room: number,
	slot: MobService.CampSlot,
	label: TextLabel?,
}

type Copy = {
	race: string,
	dungeon: DungeonDefinitions.Dungeon,
	origin: CFrame,
	map: Model,
	owner: string,
	bosses: { BossCamp },
	activeBoss: BossService.Boss?,
	emptyBossRoomSince: number?,
}

local DungeonService = {}

local copies: { [string]: Copy } = {}
-- Who is inside which copy (by position, refreshed every tick).
local copyOfPlayer: { [Player]: Copy } = {}
local counter = 0
local serverId = ""

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

local function respawnSeconds(class: DungeonDefinitions.RespawnClass): number
	local c = config()
	if class == "Boss" then
		return if RunService:IsStudio() then c.StudioBossRespawnSeconds else c.BossRespawnHours * 3600
	elseif class == "MiniBoss" then
		return if RunService:IsStudio() then c.StudioMiniBossRespawnSeconds else c.MiniBossRespawnMinutes * 60
	end
	return c.MobRespawnSeconds
end

-- "2h 41m", "12m 05s", "45s".
local function formatDuration(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local h, m, s = seconds // 3600, (seconds % 3600) // 60, seconds % 60
	if h > 0 then
		return string.format("%dh %02dm", h, m)
	elseif m > 0 then
		return string.format("%dm %02ds", m, s)
	end
	return `{s}s`
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

local function mapPart(copy: Copy, name: string): BasePart?
	local part = copy.map:FindFirstChild(name, true)
	return if part and part:IsA("BasePart") then part else nil
end

local function entranceCFrame(copy: Copy): CFrame
	local arrival = mapPart(copy, "Arrival")
	local base = if arrival then arrival.Position else copy.origin.Position + Vector3.new(0, 3, 4)
	local p = base + Vector3.new(math.random(-5, 5), 1, 0)
	return CFrame.lookAt(p, p + copy.origin.LookVector)
end

-- The copy a world position is inside (by slot bounds), if any.
local function copyAt(position: Vector3): Copy?
	for _, copy in copies do
		local p = copy.origin:PointToObjectSpace(position)
		local length = DungeonDefinitions.length(copy.dungeon)
		if p.Z <= 40 and p.Z >= -(length + 40) and math.abs(p.X) <= 200 and math.abs(p.Y) <= 200 then
			return copy
		end
	end
	return nil
end

-- Room index the player stands in (nil in a corridor).
local function roomOf(copy: Copy, position: Vector3): number?
	local p = copy.origin:PointToObjectSpace(position)
	return DungeonDefinitions.roomAt(copy.dungeon, -p.Z)
end

--------------------------------------------------------------------------------
-- Tracker (display only)
--------------------------------------------------------------------------------

local function bossStatus(camp: BossCamp, now: number): string
	local mob = camp.slot.mob
	local name = camp.slot.enemy
	local enemy = EnemyDefinitions.get(name)
	local display = if enemy then enemy.name else name
	if mob and not mob.dead then
		return `{display}: awake`
	end
	local at = camp.slot.respawnAt
	return if at then `{display}: returns in {formatDuration(at - now)}` else `{display}: …`
end

local function pushState(player: Player, copy: Copy?)
	if copy == nil then
		NetService:FireClient("DungeonState", player, { phase = "None" })
		return
	end
	local now = os.clock()
	local root = rootOf(player)
	local roomIndex = if root then roomOf(copy, root.Position) else nil
	local room = if roomIndex then copy.dungeon.rooms[roomIndex] else nil
	local mini, boss = "", ""
	for _, camp in copy.bosses do
		if camp.class == "MiniBoss" then
			mini = bossStatus(camp, now)
		else
			boss = bossStatus(camp, now)
		end
	end
	local active = copy.activeBoss
	local engaged = active and active.engaged and not active.mob.dead
	local party = PartyService:GetParty(player)
	NetService:FireClient("DungeonState", player, {
		phase = "Inside",
		dungeon = copy.dungeon.name,
		room = if room then room.name else "Passage",
		roomIndex = roomIndex,
		roomCount = #copy.dungeon.rooms,
		miniBoss = mini,
		bossStatus = boss,
		members = if party then #party.members else 1,
		leader = if party then party.leader.DisplayName else nil,
		bossName = if engaged then (active :: BossService.Boss).mob.enemy.name else nil,
		bossHp = if engaged then CombatService:HpFraction((active :: BossService.Boss).mob.model) else nil,
	})
end

--------------------------------------------------------------------------------
-- Creatures
--------------------------------------------------------------------------------

-- D-32: the killer's party members near the kill share its EXP.
local function partyRecipients(mob: MobService.Mob): { Player }
	local radius = config().XpShareRadius
	local seen: { [Player]: boolean } = {}
	local out = {}
	local function consider(player: Player)
		if seen[player] then
			return
		end
		seen[player] = true
		local root = rootOf(player)
		if
			root
			and not CombatService:IsDefeated(player)
			and (root.Position - mob.root.Position).Magnitude <= radius
		then
			table.insert(out, player)
		end
	end
	for player in CombatService:GetContributors(mob.model) do
		if player.Parent == Players then
			consider(player)
			for _, member in PartyService:GetMembers(player) do
				consider(member)
			end
		end
	end
	return out
end

local function grantBossBonus(mob: MobService.Mob, class: "MiniBoss" | "Boss", copy: Copy)
	local xp = if class == "Boss" then copy.dungeon.bossBonusXp else copy.dungeon.miniBossBonusXp
	counter += 1
	local spawnId = DungeonRules.runId(serverId, counter)
	for player in CombatService:GetContributors(mob.model) do
		if player.Parent ~= Players then
			continue
		end
		local status = (PlayerDataService :: any):ClaimReward(
			player,
			`B:{spawnId}:{mob.enemy.id}`,
			function(_data: any)
				LevelService:GrantXP(player, xp, `Boss:{mob.enemy.id}`)
			end
		)
		if status == "granted" then
			notify(player, "Info", "dungeon.bossDefeated", { name = mob.enemy.name, xp = tostring(xp) })
		end
	end
	log:Info(
		"%s defeated in the %s dungeon; returns in %s",
		mob.enemy.name,
		copy.race,
		formatDuration(respawnSeconds(class))
	)
end

local function spawnCamps(copy: Copy)
	local floorY = copy.origin.Position.Y
	local function groundAt(_x: number, _z: number): number
		return floorY
	end
	for index, room in copy.dungeon.rooms do
		for _, camp in room.camps do
			local at = copy.origin * DungeonBuilder.spawnCFrame(copy.dungeon, index, camp.x, camp.z)
			local class: DungeonDefinitions.RespawnClass = camp.class :: any
			local slots = MobService:SpawnCamp(camp.enemy, at.Position, camp.count, copy.owner, groundAt, {
				respawnSeconds = function()
					return respawnSeconds(class)
				end,
				xpRecipients = partyRecipients,
				onSpawn = function(mob)
					if class == "Boss" and room.boss then
						copy.activeBoss = BossService:Attach(mob, room.boss, copy.owner, function(key)
							for player, inside in copyOfPlayer do
								if inside == copy then
									notify(player, "Warning", key)
								end
							end
						end)
					end
				end,
			})
			if class ~= "Mob" then
				for _, slot in slots do
					table.insert(
						copy.bosses,
						{ class = class :: any, room = index, slot = slot, label = nil }
					)
				end
			end
		end
	end
end

local function onMobDefeated(mob: MobService.Mob)
	for _, copy in copies do
		if mob.owner ~= copy.owner then
			continue
		end
		for _, camp in copy.bosses do
			if
				camp.slot.mob == mob
				or (camp.slot.mob == nil and camp.slot.enemy == mob.enemy.id and camp.slot.respawnAt)
			then
				grantBossBonus(mob, camp.class, copy)
				if camp.class == "Boss" and copy.activeBoss and copy.activeBoss.mob == mob then
					for _, add in copy.activeBoss.adds do
						MobService:Despawn(add)
					end
					BossService:Detach(mob)
					copy.activeBoss = nil
				end
				return
			end
		end
	end
end

-- Altar billboards over the bosses' posts with their status / countdown.
local function buildAltars(copy: Copy)
	for _, camp in copy.bosses do
		local holder = Instance.new("Part")
		holder.Name = `Altar_{camp.slot.enemy}`
		holder.Anchored = true
		holder.CanCollide = false
		holder.CanQuery = false
		holder.CanTouch = false
		holder.Transparency = 1
		holder.Size = Vector3.new(1, 1, 1)
		holder.CFrame = camp.slot.at + Vector3.new(0, if camp.class == "Boss" then 26 else 16, 0)
		holder.Parent = copy.map
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(260, 34)
		gui.MaxDistance = 140
		gui.LightInfluence = 0
		gui.AlwaysOnTop = false
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.TextSize = 16
		label.FontFace = Font.fromEnum(Enum.Font.GothamBold)
		label.TextColor3 = Color3.fromRGB(255, 226, 160)
		label.TextStrokeTransparency = 0.25
		label.Text = ""
		label.Parent = gui
		gui.Parent = holder
		camp.label = label
	end
end

--------------------------------------------------------------------------------
-- Entering and leaving
--------------------------------------------------------------------------------

local function onGate(player: Player, gateRace: string, gate: BasePart)
	local data = PlayerDataService:GetData(player)
	local root = rootOf(player)
	local copy = copies[gateRace]
	if data == nil or root == nil or copy == nil or CombatService:IsDefeated(player) then
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
	local level = LevelService:GetLevel(player) or 0
	if level < copy.dungeon.minLevel then
		notify(player, "Warning", "dungeon.level", { level = tostring(copy.dungeon.minLevel) })
		return
	end
	AuditLogService:Audit({
		actorUserId = player.UserId,
		action = "EnterDungeon",
		target = `{copy.dungeon.id}:{gateRace}`,
	})
	TravelService:Teleport(player, entranceCFrame(copy))
end

local function leave(player: Player)
	local copy = copyOfPlayer[player]
	if copy == nil or not alive(player) then
		return
	end
	local outside = gateFrontCFrame(copy.race) or TravelService:GetHomeCFrame(player)
	if outside then
		TravelService:Teleport(player, outside)
	end
end

-- Next to `ally`, a few studs behind them.
local function besideCFrame(ally: Player): CFrame?
	local root = rootOf(ally)
	if root == nil then
		return nil
	end
	local behind = root.CFrame * CFrame.new(math.random(-3, 3), 1, 5)
	return CFrame.lookAt(behind.Position, behind.Position + root.CFrame.LookVector)
end

-- D-39: defeated inside a dungeon -> beside your leader / a party member in
-- the same dungeon, else outside the gate.
local function resolveRespawn(player: Player): CFrame?
	local copy = copyOfPlayer[player]
	if copy == nil then
		return nil
	end
	local party = PartyService:GetParty(player)
	local leader = if party then party.leader else nil
	local leaderAlive = leader ~= nil and leader ~= player and copyOfPlayer[leader] == copy and alive(leader)
	local ally: Player? = nil
	if party then
		for _, member in party.members do
			if member ~= player and copyOfPlayer[member] == copy and alive(member) then
				ally = member
				break
			end
		end
	end
	local choice = PartyRules.respawnChoice(leaderAlive, ally ~= nil)
	log:Info("user=%d respawn in the %s dungeon: %s", player.UserId, copy.race, choice)
	local target = if choice == "Leader"
		then besideCFrame(leader :: Player)
		elseif choice == "Ally" then besideCFrame(ally :: Player)
		else nil
	if target then
		notify(player, "Info", "dungeon.respawnAlly")
		return target
	end
	copyOfPlayer[player] = nil
	return gateFrontCFrame(copy.race)
end

--------------------------------------------------------------------------------
-- Ticking
--------------------------------------------------------------------------------

local function livingPlayersInRoom(copy: Copy, index: number): number
	local n = 0
	for player, inside in copyOfPlayer do
		local root = rootOf(player)
		if inside == copy and root and alive(player) and roomOf(copy, root.Position) == index then
			n += 1
		end
	end
	return n
end

local function tick(now: number)
	-- Who is where (defeated players keep their copy until they respawn).
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		local was = copyOfPlayer[player]
		local copy = if root then copyAt(root.Position) else nil
		if copy == nil and was and CombatService:IsDefeated(player) then
			copy = was
		end
		copyOfPlayer[player] = copy :: any
		if copy or was then
			pushState(player, copy)
		end
	end
	for _, copy in copies do
		for _, camp in copy.bosses do
			if camp.label then
				camp.label.Text = bossStatus(camp, now)
			end
		end
		local boss = copy.activeBoss
		if boss and boss.engaged and not boss.mob.dead then
			local index = nil
			for _, camp in copy.bosses do
				if camp.class == "Boss" then
					index = camp.room
				end
			end
			if index and livingPlayersInRoom(copy, index) == 0 then
				copy.emptyBossRoomSince = copy.emptyBossRoomSince or now
				if now - (copy.emptyBossRoomSince :: number) >= config().WipeResetSeconds then
					copy.emptyBossRoomSince = nil
					BossService:Reset(boss)
					log:Info("the %s dungeon's boss reset (no one left in its room)", copy.race)
				end
			else
				copy.emptyBossRoomSince = nil
			end
		end
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
		prompt.ObjectText = `Rift Dungeons · Lv {dungeon.minLevel}+`
		prompt.HoldDuration = 0.3
		prompt.MaxActivationDistance = 16
		prompt.RequiresLineOfSight = false
		prompt.Parent = gate
		prompt.Triggered:Connect(function(player)
			onGate(player, race, gate)
		end)
	end
end

local function buildCopy(folder: Folder, race: string, dungeon: DungeonDefinitions.Dungeon)
	local o = WorldLayout.dungeonSlotOrigin(SLOT_BY_RACE[race])
	local origin = CFrame.new(o[1], o[2], o[3])
	local map = DungeonBuilder.build(dungeon)
	map.Name = `{dungeon.id}_{race}`
	map:PivotTo(origin * CFrame.new(0, 0.5, 0))
	map.Parent = folder
	local copy: Copy = {
		race = race,
		dungeon = dungeon,
		origin = origin,
		map = map,
		owner = `dungeon:{race}`,
		bosses = {},
		activeBoss = nil,
		emptyBossRoomSince = nil,
	}
	copies[race] = copy
	local exit = mapPart(copy, "Exit")
	if exit then
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Leave dungeon"
		prompt.ObjectText = dungeon.name
		prompt.HoldDuration = 0.4
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt.Parent = exit
		prompt.Triggered:Connect(leave)
	end
	spawnCamps(copy)
	buildAltars(copy)
end

function DungeonService:Init()
	NetService:Handle("DungeonLeave", leave)
	MobService.MobDefeated:Connect(onMobDefeated)
	TravelService:SetRespawnResolver(resolveRespawn)
	serverId = if game.JobId ~= "" then game.JobId else HttpService:GenerateGUID(false)
end

function DungeonService:Start()
	local dungeon = DungeonDefinitions.get(DUNGEON_ID) :: DungeonDefinitions.Dungeon
	local existing = Workspace:FindFirstChild("RC_Dungeons")
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "RC_Dungeons"
	folder.Parent = Workspace
	for race in SLOT_BY_RACE do
		buildCopy(folder, race, dungeon)
	end
	openGates()
	Players.PlayerRemoving:Connect(function(player)
		copyOfPlayer[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(TICK_SECONDS)
			local ok, err = pcall(tick :: any, os.clock())
			if not ok then
				log:Error("tick failed: %s", tostring(err))
			end
		end
	end)
	log:Info("dungeons ready (%s, one per realm)", dungeon.name)
end

-- Whether the player is inside a dungeon.
function DungeonService:IsInRun(player: Player): boolean
	return copyOfPlayer[player] ~= nil
end

return DungeonService
