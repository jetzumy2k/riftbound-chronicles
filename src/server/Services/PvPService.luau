--!strict
--[[
	PvPService (Layer 5) — war zone access and PvP records (Phases 12-13;
	CLAUDE.md §13-§14, PLAN.md D-16, SECURITY_MODEL T-15, T-17, T-18).

	Portals (walk-through, resolved on the server; no remote or prompt):
	  - The capital "Desert Rift" / "Jungle Rift" gates take you to your
	    realm's camp in that zone (D-41, D-43). They check
	    reach, level (D-16; Studio uses PvP.StudioMinLevel), not being
	    combat-tagged, and not being inside a dungeon run.
	  - Each realm arrives in its own camp (opposite edges); the camp's
	    "Return Home" portal sends you to your capital, never while
	    combat-tagged. The 4 Hz sweep moves anyone of the other realm who
	    steps inside a camp back out past its ring (T-17 anti-spawn-camping);
	    the camp's own realm moves freely. Everything between (the Desert
	    oasis, the Jungle waterfall pool) is open PvP ground.
	Zone state:
	  - A 4 Hz sweep publishes the "WarZone" player attribute (zone id or
	    nil) for the HUD badge and the music/lighting.
	PvP records (profile PvPStats):
	  - A player defeated by a player of the other realm: +1 Defeats for
	    the victim; +1 Victories for the attacker if the credit rules allow
	    it (Logic/PvPRules.creditVictory: victims just out of spawn
	    protection, repeat victims, low-level victims, daily cap); both +1
	    Participations.
	  - A credited victory pays PvP.MarksPerVictory PvP Marks and grants the
	    victory titles its count has reached (PvPRules.VICTORY_TITLES, D-76;
	    titles earned before are granted again on load if missing).
	  - Leaving the game while combat-tagged by a player counts as a defeat.
	Field creatures: camps from WorldLayout.WarZones (levels 25-30, D-49)
	respawn after PvP.CampRespawnSeconds; kill EXP is shared with the
	killer's party / union nearby (D-32, D-48).
	Bosses (D-49): five per zone, levels 30-50, with BossService abilities
	and enrage (Logic/BossBalance tiers); each returns PvP.BossRespawnMinutes
	after it falls (Studio: StudioBossRespawnSeconds). A billboard over each
	boss's post shows "awake" or its countdown; phase / enrage warnings go
	to the players near it.
	Loot (Phase 14, D-76, LootService): a boss pays everyone who earned it
	once per spawn (WarZoneBoss: 80% Rare / 20% Mythical, plus
	PvP.MarksPerBoss PvP Marks); a field creature rolls the WarZoneMob stone
	table (30% Perfect / 70% Enhancement Stone, given a drop) per helper.
	Defeat itself (no loss, back to your own capital) is CombatService +
	TravelService: nothing here changes items or EXP.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local WarZoneTerrain = require(Shared.Logic.WarZoneTerrain)
local QuestRules = require(Shared.Logic.QuestRules)
local QuestDefinitions = require(Shared.Definitions.QuestDefinitions)
local Signal = require(Shared.Util.Signal)
local PvPRules = require(Shared.Logic.PvPRules)
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
local DungeonService = require(script.Parent.DungeonService)
local BossService = require(script.Parent.BossService)
local PartyService = require(script.Parent.PartyService)
local LootService = require(script.Parent.LootService)
local EventService = require(script.Parent.EventService)
local DungeonRules = require(Shared.Logic.DungeonRules)
local AntiExploitService = require(script.Parent.AntiExploitService)

local SWEEP_SECONDS = 0.25
-- Phase / enrage warnings reach players this close to a war-zone boss.
local BOSS_ANNOUNCE_RADIUS = 160

local log = Log.new("PvPService")

local PvPService = {
	-- (player, zoneId) walked out through their camp's Return portal (quests).
	ReturnedHome = Signal.new(),
	-- (attacker, victim) a PvP victory was credited (event contests, D-92).
	VictoryCredited = Signal.new(),
}

-- Quest unlocks apply on live servers (and in Studio if configured, D-73).
local function questGated(): boolean
	return not RunService:IsStudio() or ConfigurationService:Get("Quests").GatesInStudio
end

local function config(): any
	return ConfigurationService:Get("PvP")
end

local function minLevel(): number
	return if RunService:IsStudio() then config().StudioMinLevel else config().MinLevel
end

local function notify(player: Player, kind: string, key: string, params: { [string]: string }?)
	NetService:FireClient("Notify", player, { kind = kind, textKey = key, params = params })
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Checks the shared portal rules for `player` at `portal`; tells them why not.
local function mayTravel(player: Player, portal: BasePart, needsLevel: boolean): boolean
	local root = rootOf(player)
	if root == nil then
		return false
	end
	local ok, reason = PvPRules.canUsePortal({
		distance = (root.Position - portal.Position).Magnitude,
		reach = config().PortalReach,
		level = LevelService:GetLevel(player) or 0,
		minLevel = if needsLevel then minLevel() else 0,
		combatTagged = CombatService:IsInCombat(player),
		defeated = CombatService:IsDefeated(player),
	})
	if not ok then
		if reason == "inCombat" then
			notify(player, "Warning", "pvp.portal.inCombat")
		elseif reason == "level" then
			notify(player, "Warning", "pvp.portal.level", { level = tostring(minLevel()) })
		end
		return false
	end
	return true
end

-- Inside your own realm's camp, facing the desert.
local function arrivalCFrame(zone: WorldLayout.WarZone, race: string): CFrame?
	local rng = Random.new()
	local p = WorldLayout.basePoint(zone, race, 12, rng:NextNumber(-6, 6))
	if p == nil then
		return nil
	end
	local position = Vector3.new(p[1], p[2] + 4, p[3])
	local c = zone.center
	return CFrame.lookAt(position, Vector3.new(c[1], position.Y, c[3]))
end

local function enterZone(player: Player, zone: WorldLayout.WarZone, gate: BasePart, gateRace: string)
	local data = PlayerDataService:GetData(player)
	if data == nil or data.Race ~= gateRace then
		return
	end
	if DungeonService:IsInRun(player) then
		notify(player, "Warning", "dungeon.inRun")
		return
	end
	-- D-16 / D-73: the war-zone gates also need Quest 4 (The Broken Gate).
	if not QuestRules.unlocked(data, "PortalAccess", questGated()) then
		notify(player, "Warning", "quest.locked.portal")
		return
	end
	if not mayTravel(player, gate, true) then
		return
	end
	local arrival = arrivalCFrame(zone, gateRace)
	if arrival == nil then
		return
	end
	AuditLogService:Audit({ actorUserId = player.UserId, action = "EnterWarZone", target = zone.id })
	notify(player, "Warning", "pvp.entered", { zone = zone.name })
	TravelService:Teleport(player, arrival)
end

local function returnHome(player: Player, portal: BasePart, portalRace: string)
	local data = PlayerDataService:GetData(player)
	if data == nil or data.Race ~= portalRace or not mayTravel(player, portal, false) then
		return
	end
	local home = TravelService:GetHomeCFrame(player)
	if home then
		local zoneId = player:GetAttribute("WarZone")
		TravelService:Teleport(player, home)
		if type(zoneId) == "string" then
			PvPService.ReturnedHome:Fire(player, zoneId)
		end
	end
end

--------------------------------------------------------------------------------
-- PvP records
--------------------------------------------------------------------------------

-- Boss spawns defeated on this server (claim ids "B:<server>:<n>:<boss>:L").
local bossCounter = 0
-- Every war-zone boss post (admin "respawn now").
local bossSlots: { MobService.CampSlot } = {}

local function addMarks(player: Player, amount: number, source: string)
	local data = PlayerDataService:GetData(player)
	if data == nil or amount <= 0 then
		return
	end
	-- PvP Arena Rush (D-92): Marks multiplied while it runs.
	amount = math.floor(amount * EventService:Factor("Marks", player) + 0.5)
	data.Wallet.PvPMarks += amount
	AuditLogService:Audit({
		actorUserId = player.UserId,
		action = "PvPMarks",
		target = source,
		details = { amount = amount, total = data.Wallet.PvPMarks },
	})
	notify(player, "Info", "pvp.marks", { amount = tostring(amount) })
end

-- Grants the victory titles `data` has earned but doesn't own yet.
local function grantVictoryTitles(player: Player, data: any)
	for _, title in PvPRules.titlesFor(data.PvPStats.Victories) do
		if data.Titles[title] ~= true then
			data.Titles[title] = true
			AuditLogService:Audit({ actorUserId = player.UserId, action = "TitleGranted", target = title })
			notify(player, "Info", "quest.title", { title = QuestDefinitions.Titles[title] })
		end
	end
end

local function recordDefeat(victim: Player, attacker: Player?, protectionEndedAgo: number?)
	local victimData = PlayerDataService:GetData(victim)
	if victimData then
		victimData.PvPStats.Defeats += 1
		victimData.PvPStats.Participations += 1
	end
	if attacker == nil or attacker.Parent ~= Players then
		return
	end
	local data = PlayerDataService:GetData(attacker)
	if data == nil then
		return
	end
	local stats = data.PvPStats
	stats.Participations += 1
	local now = os.time()
	local today = PvPRules.day(now)
	if stats.DailyCredit.Day ~= today then
		stats.DailyCredit = { Day = today, Count = 0 }
	end
	-- Forget victims outside the repeat window (keeps the profile small).
	local window = config().RepeatVictimMinutes * 60
	for key, at in stats.RecentVictims do
		if now - at >= window then
			stats.RecentVictims[key] = nil
		end
	end
	local key = tostring(victim.UserId)
	local last = stats.RecentVictims[key]
	local credited, reason = PvPRules.creditVictory({
		attackerLevel = LevelService:GetLevel(attacker) or 0,
		victimLevel = LevelService:GetLevel(victim) or 0,
		levelGap = config().LevelGap,
		sinceLastCredit = if last then now - last else nil,
		protectionEndedAgo = protectionEndedAgo,
		freshSpawnSeconds = config().FreshSpawnGraceSeconds,
		repeatWindowSeconds = window,
		creditsToday = stats.DailyCredit.Count,
		dailyCap = config().DailyCreditCap,
	})
	if credited then
		stats.Victories += 1
		stats.DailyCredit.Count += 1
		stats.RecentVictims[key] = now
		AuditLogService:Audit({
			actorUserId = attacker.UserId,
			action = "PvPVictory",
			target = tostring(victim.UserId),
			details = { victories = stats.Victories },
		})
		notify(attacker, "Info", "pvp.victory", { name = victim.DisplayName })
		addMarks(attacker, config().MarksPerVictory, "victory")
		grantVictoryTitles(attacker, data)
		PvPService.VictoryCredited:Fire(attacker, victim)
	else
		log:Debug("no victory credit %d -> %d: %s", attacker.UserId, victim.UserId, tostring(reason))
	end
	PlayerDataService:PushSnapshot(attacker)
end

local function onDefeated(entity: CombatService.Entity, attacker: CombatService.Entity?)
	local victim = entity.player
	if victim == nil or attacker == nil or attacker.player == nil or attacker.race == entity.race then
		return
	end
	recordDefeat(victim, attacker.player, CombatService:ProtectionEndedAgo(entity))
	PlayerDataService:PushSnapshot(victim)
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

local function openGate(race: string, zone: WorldLayout.WarZone)
	local gate = WorldService:GetGate(race, zone.id)
	if gate == nil then
		log:Warn("no %s gate in the %s capital", zone.id, race)
		return
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
		enterZone(player, zone, gate, race)
	end)
end

-- Seconds between "this is the other realm's camp" notices per player.
local CAMP_NOTICE_SECONDS = 4
local lastCampNotice: { [Player]: number } = {}

-- Moves `player` out of the other realm's camp `base`, straight back past
-- its ring (T-17).
local function pushOutOfCamp(
	player: Player,
	root: BasePart,
	zone: WorldLayout.WarZone,
	race: string,
	base: WorldLayout.Base
)
	local centre = WorldLayout.basePoint(zone, race, 0, 0)
	if centre == nil then
		return
	end
	local c = Vector3.new(centre[1], root.Position.Y, centre[3])
	local away = Vector3.new(root.Position.X - c.X, 0, root.Position.Z - c.Z)
	if away.Magnitude < 1 then
		-- Dead centre: push toward the zone centre.
		away = Vector3.new(zone.center[1] - c.X, 0, zone.center[3] - c.Z)
	end
	local target = c + away.Unit * (base.radius + 8)
	local ground = WarZoneTerrain.groundY(zone, target.X, target.Z)
	local position = Vector3.new(target.X, ground + 4, target.Z)
	local character = player.Character
	if character then
		AntiExploitService:GrantGrace(player, 2)
		character:PivotTo(CFrame.lookAt(position, position + away.Unit))
	end
	local now = os.clock()
	if now - (lastCampNotice[player] or -math.huge) >= CAMP_NOTICE_SECONDS then
		lastCampNotice[player] = now
		notify(player, "Warning", "pvp.enemyCamp")
	end
end

local function sweep()
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		local zone = if root then WorldLayout.warZoneAt(root.Position.X, root.Position.Z) else nil
		local id = if zone then zone.id else nil
		if player:GetAttribute("WarZone") ~= id then
			player:SetAttribute("WarZone", id)
		end
		if zone == nil or root == nil then
			continue
		end
		local data = PlayerDataService:GetData(player)
		local race = data and data.Race
		for baseRace, base in zone.bases do
			if baseRace == race then
				continue
			end
			local dx = root.Position.X - (zone.center[1] + base.x)
			local dz = root.Position.Z - (zone.center[3] + base.z)
			if dx * dx + dz * dz <= (base.radius + 1) ^ 2 then
				pushOutOfCamp(player, root, zone, baseRace, base)
			end
		end
	end
end

function PvPService:Init()
	-- Phase 23 audit (D-102): forget leavers' notice times.
	Players.PlayerRemoving:Connect(function(player)
		lastCampNotice[player] = nil
	end)
	CombatService.Defeated:Connect(onDefeated)
	CombatService.CombatLogged:Connect(function(entity: CombatService.Entity, attacker: CombatService.Entity?)
		local victim = entity.player
		if victim and attacker and attacker.player and attacker.race ~= entity.race then
			recordDefeat(victim, attacker.player, CombatService:ProtectionEndedAgo(entity))
		end
	end)
end

local groupRecipients = MobService.groupRecipients(function(player)
	return PartyService:GetGroupMembers(player)
end)

local function bossRespawnSeconds(): number
	local c = config()
	return if RunService:IsStudio() then c.StudioBossRespawnSeconds else c.BossRespawnMinutes * 60
end

-- "12m 05s" / "45s".
local function formatDuration(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local m, s = seconds // 60, seconds % 60
	return if m > 0 then string.format("%dm %02ds", m, s) else `{s}s`
end

-- Boss loot + Marks for everyone who earned it (once per spawn), then the
-- boss's adds go and its ability loop stops.
local function bossLoot(mob: MobService.Mob, boss: BossService.Boss, recipients: { Player }?)
	bossCounter += 1
	local spawnId = DungeonRules.runId(game.JobId, bossCounter)
	LootService:DropFor(
		recipients or {},
		"WarZoneBoss",
		mob.level,
		`PvPBoss:{mob.enemy.id}`,
		`B:{spawnId}:{mob.enemy.id}:L`,
		{
			capGap = true,
			onClaim = function(player)
				addMarks(player, config().MarksPerBoss, `boss:{mob.enemy.id}`)
			end,
		}
	)
	for _, add in boss.adds do
		MobService:Despawn(add)
	end
	BossService:Detach(mob)
end

-- Announces `key` to players within reach of `position`.
local function announcerAt(position: Vector3): (key: string, params: { [string]: string }?) -> ()
	return function(key: string, params: { [string]: string }?)
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if
				root
				and root:IsA("BasePart")
				and (root.Position - position).Magnitude <= BOSS_ANNOUNCE_RADIUS
			then
				NetService:FireClient("Notify", player, { kind = "Warning", textKey = key, params = params })
			end
		end
	end
end

-- Event bosses (D-91: invasions, the world boss): no respawn.
local eventBosses: { [MobService.Mob]: BossService.Boss } = {}

-- One war-zone boss: a camp of one that runs BossService while alive.
local function spawnBoss(
	zone: WorldLayout.WarZone,
	spec: WorldLayout.ZoneBoss,
	groundAt: (number, number) -> number
)
	local c = zone.center
	local position = Vector3.new(c[1] + spec.x, c[2], c[3] + spec.z)
	local attached: { [MobService.Mob]: BossService.Boss } = {}
	local announce = announcerAt(position)
	local eventZone = if zone.id == "DesertRift" then "Desert" else "Jungle"
	local slots = MobService:SpawnCamp(spec.enemy, position, 1, zone.id, groundAt, {
		-- Boss Frenzy (D-91) shortens the wait while it runs.
		respawnSeconds = function()
			return bossRespawnSeconds() * EventService:Factor("BossRespawn", nil, eventZone)
		end,
		xpRecipients = groupRecipients,
		onSpawn = function(mob)
			local boss = BossService:Attach(mob, spec.enemy, zone.id, announce)
			if boss then
				attached[mob] = boss
			end
		end,
	})
	local slot = slots[1]
	table.insert(bossSlots, slot)
	-- Status billboard over the boss's post.
	local holder = Instance.new("Part")
	holder.Name = `BossPost_{spec.enemy}`
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.new(1, 1, 1)
	holder.Position = Vector3.new(position.X, groundAt(position.X, position.Z) + 30, position.Z)
	holder.Parent = Workspace
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(300, 34)
	gui.MaxDistance = 220
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.TextSize = 16
	label.FontFace = Font.fromEnum(Enum.Font.GothamBold)
	label.TextColor3 = Color3.fromRGB(255, 226, 160)
	label.TextStrokeTransparency = 0.25
	label.Parent = gui
	gui.Parent = holder
	MobService.MobDefeated:Connect(function(mob, _contributors, recipients: { Player }?)
		local boss = attached[mob]
		if boss then
			attached[mob] = nil
			bossLoot(mob, boss, recipients)
			log:Info(
				"%s defeated in the %s; returns in %s",
				mob.enemy.name,
				zone.name,
				formatDuration(bossRespawnSeconds())
			)
		end
	end)
	local displayName = spec.enemy
	task.spawn(function()
		while holder.Parent do
			local mob = slot and slot.mob
			if mob and not mob.dead then
				displayName = mob.enemy.name
				label.Text = `{displayName} · Lv {mob.level}: awake`
			elseif slot and slot.respawnAt then
				label.Text = `{displayName}: returns in {formatDuration(slot.respawnAt - os.clock())}`
			end
			task.wait(1)
		end
	end)
end

--[[
	Live events (D-91): a boss `enemyId` at (x, z) relative to war zone
	`zoneId`'s centre, with its abilities, war-zone boss loot and Marks; it
	never respawns. Returns the mob (nil if it couldn't spawn).
]]
function PvPService:SpawnEventBoss(zoneId: string, enemyId: string, x: number, z: number): MobService.Mob?
	local zone = (WorldLayout.WarZones :: any)[zoneId] :: WorldLayout.WarZone?
	if zone == nil then
		return nil
	end
	local c = zone.center
	local px, pz = c[1] + x, c[3] + z
	local ground = Vector3.new(px, WarZoneTerrain.groundY(zone, px, pz), pz)
	local mob =
		MobService:Spawn(enemyId, CFrame.new(ground), { owner = zone.id, xpRecipients = groupRecipients })
	if mob == nil then
		return nil
	end
	local boss = BossService:Attach(mob, enemyId, zone.id, announcerAt(ground))
	if boss then
		eventBosses[mob] = boss
	end
	return mob
end

-- Removes an event boss still standing when its event ends (and its adds).
function PvPService:DespawnEventBoss(mob: MobService.Mob)
	local boss = eventBosses[mob]
	eventBosses[mob] = nil
	if boss then
		for _, add in boss.adds do
			MobService:Despawn(add)
		end
		BossService:Detach(mob)
	end
	MobService:Despawn(mob)
end

-- War-zone creatures (D-91 invasions): `enemyId` at `level` around (x, z)
-- relative to the zone centre; they pay stones like the zone's own.
function PvPService:SpawnEventCreature(
	zoneId: string,
	enemyId: string,
	level: number,
	x: number,
	z: number
): MobService.Mob?
	local zone = (WorldLayout.WarZones :: any)[zoneId] :: WorldLayout.WarZone?
	if zone == nil then
		return nil
	end
	local c = zone.center
	local px, pz = c[1] + x, c[3] + z
	local ground = Vector3.new(px, WarZoneTerrain.groundY(zone, px, pz), pz)
	return MobService:Spawn(
		enemyId,
		CFrame.new(ground),
		{ owner = zone.id, level = level, xpRecipients = groupRecipients }
	)
end

-- Admin (bosses.manage): brings every fallen war-zone boss back now.
function PvPService:RespawnBosses(): number
	local count = 0
	for _, slot in bossSlots do
		if MobService:RespawnSlotNow(slot) then
			count += 1
		end
	end
	return count
end

-- Admin (player.edit): grants victory titles after Victories was changed.
function PvPService:RefreshTitles(player: Player)
	local data = PlayerDataService:GetData(player)
	if data then
		grantVictoryTitles(player, data)
	end
end

function PvPService:Start()
	-- Field creature stones (bosses pay their own loot above).
	local zoneIds: { [string]: boolean } = {}
	for _, zone in WorldLayout.WarZones :: { [string]: WorldLayout.WarZone } do
		zoneIds[zone.id] = true
	end
	MobService.MobDefeated:Connect(function(mob, _contributors, recipients: { Player }?)
		local eventBoss = eventBosses[mob]
		if eventBoss then
			eventBosses[mob] = nil
			bossLoot(mob, eventBoss, recipients)
		end
		if zoneIds[mob.owner] and mob.model:GetAttribute("RC_Boss") == nil then
			LootService:DropStonesFor(recipients or {}, "WarZoneMob", mob.level, `WarZone:{mob.enemy.id}`)
		end
	end)
	PlayerDataService.ProfileLoaded:Connect(function(player, data)
		grantVictoryTitles(player, data)
	end)
	for _, zone in WorldLayout.WarZones :: { [string]: WorldLayout.WarZone } do
		for race in WorldLayout.Realms :: { [string]: any } do
			openGate(race, zone)
		end
		for race in zone.bases do
			local portal = WorldService:GetReturnPortal(zone.id, race)
			if portal then
				TravelService:AddWalkPortal(portal, function(player)
					returnHome(player, portal, race)
				end)
			end
		end
		-- Field creature camps.
		local c = zone.center
		local function groundAt(x: number, z: number): number
			return WarZoneTerrain.groundY(zone, x, z)
		end
		for _, camp in zone.camps do
			MobService:SpawnCamp(
				camp.enemy,
				Vector3.new(c[1] + camp.x, c[2], c[3] + camp.z),
				camp.count,
				zone.id,
				groundAt,
				{
					respawnSeconds = function()
						return config().CampRespawnSeconds
					end,
					xpRecipients = groupRecipients,
					level = camp.level,
				}
			)
		end
		for _, boss in zone.bosses do
			spawnBoss(zone, boss, groundAt)
		end
	end
	task.spawn(function()
		while true do
			task.wait(SWEEP_SECONDS)
			sweep()
		end
	end)
	log:Info("war zones open (min level %d%s)", minLevel(), if RunService:IsStudio() then ", Studio" else "")
end

return PvPService
