--!strict
--[[
	DungeonService (Layer 5) — persistent dungeons, one per realm
	(PLAN.md Phase 9, D-32, D-39, D-42, D-47; SECURITY_MODEL T-12, T-15).

	Map:
	  Each realm has its own copy of Rift Hollow, built once at server start
	  in a reserved slot far from the world (WorldLayout.DungeonSlots: slot 1
	  Angels, slot 2 Devils). Every player of that realm shares it; parties
	  and unions fight together inside. No PvP inside (one realm per copy).
	Floors (D-47):
	  1-3  landing, 7 rooms and a floor boss's lair (creatures 1-10 / 11-20 /
	       21-30; Cerberus, Chimera, Basilisk)
	  4    the Hall of Thirty (30 mini-boss chambers, 31-40) and Typhon's
	       Sanctum (the level-40 Dungeon Boss)
	  Every floor is open to every level and nothing is locked (creator
	  review 2026-10-17): each landing has a "Leave Dungeon" portal (and "Up"
	  on floors 2-4) and the "Down" portal at the back of each lair always
	  works. The way there is guarded: rooms full of creature packs, guards
	  around the lair, and the floor boss in front of the portal.
	Entering / leaving:
	  The capital "Rift Dungeons" gate (walk-through portal resolved on the
	  server, so no remote) takes you to floor 1's landing; you need the
	  dungeon's minLevel and must be within reach of the gate. Portals and
	  the tracker's Leave button act only for players inside that copy.
	Creatures (MobService camps; respawn per class):
	  Mob / MiniBoss / FloorBoss / Boss (config Dungeon.*; Studio uses short
	  boss timers). Bosses run BossService abilities and enrage; an engaged
	  boss resets if no living player is in its room for WipeResetSeconds.
	Rewards:
	  Kill EXP is shared among the killer's party / union members nearby
	  (D-32, D-48). Each boss spawn also gives everyone who damaged it a
	  one-time bonus, claimed as "B:<spawnId>:<enemy>" (idempotent).
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
local PORTAL_REACH = 20
local TICK_SECONDS = 1
local SLOT_BY_RACE: { [string]: number } = { Angel = 1, Devil = 2 }

local log = Log.new("DungeonService")

type Floor = DungeonDefinitions.Floor
type RespawnClass = DungeonDefinitions.RespawnClass

type BossCamp = {
	class: RespawnClass,
	floor: number,
	room: number,
	slot: MobService.CampSlot,
	label: TextLabel?,
	boss: BossService.Boss?,
	emptySince: number?,
}

type Copy = {
	race: string,
	dungeon: DungeonDefinitions.Dungeon,
	origin: CFrame,
	map: Model,
	owner: string,
	bosses: { BossCamp },
}

local DungeonService = {}

local copies: { [string]: Copy } = {}
-- Who is inside which copy (by position, refreshed every tick).
local copyOfPlayer: { [Player]: Copy } = {}
local floorOfPlayer: { [Player]: number } = {}
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

local function respawnSeconds(class: RespawnClass): number
	local c = config()
	local studio = RunService:IsStudio()
	if class == "Boss" then
		return if studio then c.StudioBossRespawnSeconds else c.BossRespawnHours * 3600
	elseif class == "FloorBoss" then
		return if studio then c.StudioFloorBossRespawnSeconds else c.FloorBossRespawnMinutes * 60
	elseif class == "MiniBoss" then
		return if studio then c.StudioMiniBossRespawnSeconds else c.MiniBossRespawnMinutes * 60
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

-- World CFrame at floor-frame point (x, z) on `floorIndex`, facing deeper.
local function floorPoint(copy: Copy, floorIndex: number, x: number, z: number, facingBack: boolean?): CFrame
	local floor = copy.dungeon.floors[floorIndex]
	local local_ = DungeonBuilder.pointCFrame(floor, x, z)
	local p = (copy.origin * local_).Position + Vector3.new(math.random(-4, 4), 4, 0)
	local look = copy.origin.LookVector * (if facingBack then -1 else 1)
	return CFrame.lookAt(p, p + Vector3.new(look.X, 0, look.Z))
end

local function arrivalCFrame(copy: Copy, floorIndex: number): CFrame
	local floor = copy.dungeon.floors[floorIndex]
	return floorPoint(copy, floorIndex, floor.arrival[1], floor.arrival[2])
end

-- The floor and room a world position is in (nil outside the copy).
local function locate(copy: Copy, position: Vector3): (number?, number?)
	local p = copy.origin:PointToObjectSpace(position)
	if math.abs(p.Y) > 200 then
		return nil, nil
	end
	local floorIndex, fx = DungeonDefinitions.floorAt(copy.dungeon, p.X, -p.Z, 40)
	if floorIndex == nil then
		return nil, nil
	end
	return floorIndex, DungeonDefinitions.roomAt(copy.dungeon.floors[floorIndex], fx, -p.Z)
end

local function copyAt(position: Vector3): Copy?
	for _, copy in copies do
		if (locate(copy, position)) ~= nil then
			return copy
		end
	end
	return nil
end

local function enemyName(id: string): string
	local enemy = EnemyDefinitions.get(id)
	return if enemy then enemy.name else id
end

local function campAlive(camp: BossCamp): boolean
	local mob = camp.slot.mob
	return mob ~= nil and not mob.dead
end

--------------------------------------------------------------------------------
-- Tracker (display only)
--------------------------------------------------------------------------------

local function bossStatus(camp: BossCamp, now: number): string
	local display = enemyName(camp.slot.enemy)
	if campAlive(camp) then
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
	local floorIndex, roomIndex = nil, nil
	if root then
		floorIndex, roomIndex = locate(copy, root.Position)
	end
	floorIndex = floorIndex or floorOfPlayer[player] or 1
	local floor = copy.dungeon.floors[floorIndex :: number]
	local room = if roomIndex then floor.rooms[roomIndex] else nil
	local minis, miniAwake, mini = 0, 0, ""
	local bossText = ""
	local engaged: BossCamp? = nil
	for _, camp in copy.bosses do
		if camp.floor ~= floorIndex then
			continue
		end
		if camp.class == "MiniBoss" then
			minis += 1
			miniAwake += if campAlive(camp) then 1 else 0
			mini = bossStatus(camp, now)
		else
			bossText = bossStatus(camp, now)
		end
		local b = camp.boss
		if b and b.engaged and not b.mob.dead and camp.room == roomIndex then
			engaged = camp
		end
	end
	if minis > 1 then
		mini = `Mini bosses awake: {miniAwake} / {minis}`
	end
	local party = PartyService:GetParty(player)
	local active = engaged and engaged.boss
	NetService:FireClient("DungeonState", player, {
		phase = "Inside",
		dungeon = copy.dungeon.name,
		floor = floorIndex,
		floorCount = #copy.dungeon.floors,
		floorName = floor.name,
		levels = `{floor.levels[1]}-{floor.levels[2]}`,
		room = if room then room.name else "Passage",
		roomIndex = roomIndex,
		roomCount = #floor.rooms,
		miniBoss = mini,
		bossStatus = bossText,
		members = #PartyService:GetGroupMembers(player),
		leader = if party then party.leader.DisplayName else nil,
		bossName = if active then active.mob.enemy.name else nil,
		bossHp = if active then CombatService:HpFraction(active.mob.model) else nil,
		enraged = if active then active.enraged else nil,
	})
end

--------------------------------------------------------------------------------
-- Creatures
--------------------------------------------------------------------------------

-- D-32 / D-48: the killer's party (or union) members near the kill share its EXP.
local groupRecipients = MobService.groupRecipients(function(player)
	return PartyService:GetGroupMembers(player)
end)

local function grantBossBonus(mob: MobService.Mob, class: RespawnClass, copy: Copy)
	local xp = copy.dungeon.bonusXp[class] or 0
	if xp <= 0 then
		return
	end
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

-- Tells everyone on that floor of the copy.
local function announcer(copy: Copy, floorIndex: number): (key: string, params: { [string]: string }?) -> ()
	return function(key, params)
		for player, inside in copyOfPlayer do
			if inside == copy and floorOfPlayer[player] == floorIndex then
				notify(player, "Warning", key, params)
			end
		end
	end
end

local function spawnCamps(copy: Copy)
	local floorY = copy.origin.Position.Y
	local function groundAt(_x: number, _z: number): number
		return floorY
	end
	for floorIndex, floor in copy.dungeon.floors do
		for roomIndex, room in floor.rooms do
			for _, camp in room.camps do
				local at = copy.origin * DungeonBuilder.campCFrame(floor, room, camp.x, camp.z)
				local class: RespawnClass = camp.class
				local bossDef = DungeonDefinitions.boss(camp.enemy)
				local bossCamp: BossCamp? = nil
				local slots =
					MobService:SpawnCamp(camp.enemy, at.Position, camp.count, copy.owner, groundAt, {
						respawnSeconds = function()
							return respawnSeconds(class)
						end,
						xpRecipients = groupRecipients,
						level = camp.level,
						onSpawn = function(mob)
							if bossDef and bossCamp then
								bossCamp.boss = BossService:Attach(
									mob,
									bossDef.id,
									copy.owner,
									announcer(copy, floorIndex)
								)
							end
						end,
					})
				if class ~= "Mob" then
					for _, slot in slots do
						local entry: BossCamp = {
							class = class,
							floor = floorIndex,
							room = roomIndex,
							slot = slot,
							label = nil,
							boss = nil,
							emptySince = nil,
						}
						table.insert(copy.bosses, entry)
						bossCamp = entry
						-- The first spawn happened before the entry existed.
						if bossDef and slot.mob and not slot.mob.dead then
							entry.boss = BossService:Attach(
								slot.mob,
								bossDef.id,
								copy.owner,
								announcer(copy, floorIndex)
							)
						end
					end
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
			if camp.slot.mob == mob or (camp.boss and camp.boss.mob == mob) then
				grantBossBonus(mob, camp.class, copy)
				local boss = camp.boss
				if boss and boss.mob == mob then
					for _, add in boss.adds do
						MobService:Despawn(add)
					end
					BossService:Detach(mob)
					camp.boss = nil
				end
				camp.emptySince = nil
				return
			end
		end
	end
end

-- Billboards over the bosses' posts with their status / countdown.
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
		holder.CFrame = camp.slot.at + Vector3.new(0, if camp.class == "MiniBoss" then 16 else 26, 0)
		holder.Parent = copy.map
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(280, 34)
		gui.MaxDistance = if camp.class == "MiniBoss" then 80 else 140
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
-- Entering, leaving and moving between floors
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
	TravelService:Teleport(player, arrivalCFrame(copy, 1))
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

-- A portal on `floorIndex` was used: only by a living player of this copy
-- standing at it (T-15).
local function atPortal(player: Player, copy: Copy, surface: BasePart): boolean
	local root = rootOf(player)
	return root ~= nil
		and alive(player)
		and copyOfPlayer[player] == copy
		and (root.Position - surface.Position).Magnitude <= PORTAL_REACH
end

local function goDown(player: Player, copy: Copy, floorIndex: number, surface: BasePart)
	if not atPortal(player, copy, surface) then
		return
	end
	local next = copy.dungeon.floors[floorIndex + 1]
	if next == nil then
		notify(player, "Warning", "dungeon.noFloor")
		return
	end
	TravelService:Teleport(player, arrivalCFrame(copy, floorIndex + 1))
end

local function goUp(player: Player, copy: Copy, floorIndex: number, surface: BasePart)
	if not atPortal(player, copy, surface) then
		return
	end
	local above = copy.dungeon.floors[floorIndex - 1]
	if above == nil or above.downPortal == nil then
		notify(player, "Warning", "dungeon.noFloor")
		return
	end
	-- In front of the floor above's way down (its lair).
	local p = above.downPortal
	TravelService:Teleport(player, floorPoint(copy, floorIndex - 1, p[1], p[2] - 18, true))
end

local function wirePortals(copy: Copy)
	for floorIndex in copy.dungeon.floors do
		local leaveSurface = mapPart(copy, `Leave_{floorIndex}`)
		if leaveSurface then
			TravelService:AddWalkPortal(leaveSurface, function(player)
				if atPortal(player, copy, leaveSurface) then
					leave(player)
				end
			end)
		end
		local up = mapPart(copy, `Up_{floorIndex}`)
		if up then
			TravelService:AddWalkPortal(up, function(player)
				goUp(player, copy, floorIndex, up)
			end)
		end
		local down = mapPart(copy, `Down_{floorIndex}`)
		if down then
			local nextFloor = copy.dungeon.floors[floorIndex + 1]
			TravelService:AddWalkPortal(down, function(player)
				goDown(player, copy, floorIndex, down)
			end)
			local gui = Instance.new("BillboardGui")
			gui.Size = UDim2.fromOffset(300, 46)
			gui.StudsOffset = Vector3.new(0, 14, 0)
			gui.MaxDistance = 120
			gui.LightInfluence = 0
			local label = Instance.new("TextLabel")
			label.BackgroundTransparency = 1
			label.Size = UDim2.fromScale(1, 1)
			label.TextSize = 16
			label.FontFace = Font.fromEnum(Enum.Font.GothamBold)
			label.TextColor3 = Color3.fromRGB(150, 255, 170)
			label.TextStrokeTransparency = 0.25
			label.Text = if nextFloor
				then `Floor {floorIndex + 1}: {nextFloor.name} (Lv {nextFloor.levels[1]}-{nextFloor.levels[2]})`
				else ""
			label.Parent = gui
			gui.Parent = down
		end
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
	floorOfPlayer[player] = nil
	return gateFrontCFrame(copy.race)
end

--------------------------------------------------------------------------------
-- Ticking
--------------------------------------------------------------------------------

local function livingPlayersInRoom(copy: Copy, floorIndex: number, roomIndex: number): number
	local n = 0
	for player, inside in copyOfPlayer do
		local root = rootOf(player)
		if inside == copy and root and alive(player) then
			local f, r = locate(copy, root.Position)
			if f == floorIndex and r == roomIndex then
				n += 1
			end
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
		if copy and root then
			local floorIndex = locate(copy, root.Position)
			if floorIndex and floorIndex ~= floorOfPlayer[player] then
				floorOfPlayer[player] = floorIndex
				local floor = copy.dungeon.floors[floorIndex]
				notify(player, "Info", "dungeon.floor", {
					floor = tostring(floorIndex),
					name = floor.name,
					levels = `{floor.levels[1]}-{floor.levels[2]}`,
				})
			end
		elseif copy == nil then
			floorOfPlayer[player] = nil
		end
		if copy or was then
			pushState(player, copy)
		end
	end
	local wipeSeconds = config().WipeResetSeconds
	for _, copy in copies do
		for _, camp in copy.bosses do
			if camp.label then
				camp.label.Text = bossStatus(camp, now)
			end
			-- An engaged boss with nobody left alive in its room resets.
			local boss = camp.boss
			if boss and boss.engaged and not boss.mob.dead then
				if livingPlayersInRoom(copy, camp.floor, camp.room) == 0 then
					camp.emptySince = camp.emptySince or now
					if now - (camp.emptySince :: number) >= wipeSeconds then
						camp.emptySince = nil
						BossService:Reset(boss)
						log:Info(
							"%s in the %s dungeon reset (no one left in its room)",
							boss.def.id,
							copy.race
						)
					end
				else
					camp.emptySince = nil
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

local function openGates()
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
		-- Walk through the gate to enter (no prompt).
		TravelService:AddWalkPortal(gate, function(player)
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
	}
	copies[race] = copy
	wirePortals(copy)
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
		floorOfPlayer[player] = nil
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
	local bossCount = 0
	for _, copy in copies do
		bossCount = #copy.bosses
	end
	log:Info("dungeons ready (%s: %d floors, %d bosses per realm)", dungeon.name, #dungeon.floors, bossCount)
end

-- Whether the player is inside a dungeon.
function DungeonService:IsInRun(player: Player): boolean
	return copyOfPlayer[player] ~= nil
end

return DungeonService
