--!strict
--[[
	PvPService (Layer 5) — war zone access and PvP records (Phases 12-13;
	CLAUDE.md §13-§14, PLAN.md D-16, SECURITY_MODEL T-15, T-17, T-18).

	Portals (ProximityPrompts resolved on the server; no remote):
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
	    it (Logic/PvPRules.creditVictory: repeat victims, low-level victims,
	    daily cap); both +1 Participations.
	  - Leaving the game while combat-tagged by a player counts as a defeat.
	Field creatures: camps from WorldLayout.WarZones (levels 25-30, D-49)
	respawn after PvP.CampRespawnSeconds; kill EXP is shared with the
	killer's party / union nearby (D-32, D-48).
	Bosses (D-49): five per zone, levels 30-50, with BossService abilities
	and enrage (Logic/BossBalance tiers); each returns PvP.BossRespawnMinutes
	after it falls (Studio: StudioBossRespawnSeconds). A billboard over each
	boss's post shows "awake" or its countdown; phase / enrage warnings go
	to the players near it. Boss loot is Phase 14.
	Defeat itself (no loss, back to your own capital) is CombatService +
	TravelService: nothing here changes items or EXP.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local WarZoneTerrain = require(Shared.Logic.WarZoneTerrain)
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
local AntiExploitService = require(script.Parent.AntiExploitService)

local SWEEP_SECONDS = 0.25
-- Phase / enrage warnings reach players this close to a war-zone boss.
local BOSS_ANNOUNCE_RADIUS = 160

local log = Log.new("PvPService")

local PvPService = {}

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
		TravelService:Teleport(player, home)
	end
end

--------------------------------------------------------------------------------
-- PvP records
--------------------------------------------------------------------------------

local function recordDefeat(victim: Player, attacker: Player?)
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
		repeatWindowSeconds = window,
		creditsToday = stats.DailyCredit.Count,
		dailyCap = config().DailyCreditCap,
	})
	if credited then
		stats.Victories += 1
		stats.DailyCredit.Count += 1
		stats.RecentVictims[key] = now
		notify(attacker, "Info", "pvp.victory", { name = victim.DisplayName })
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
	recordDefeat(victim, attacker.player)
	PlayerDataService:PushSnapshot(victim)
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

local function prompt(parent: BasePart, action: string, object: string): ProximityPrompt
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = object
	p.HoldDuration = 0.4
	p.MaxActivationDistance = 16
	p.RequiresLineOfSight = false
	p.Parent = parent
	return p
end

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
	prompt(gate, `Enter {zone.name}`, `War zone · PvP · Lv {minLevel()}+`).Triggered:Connect(
		function(player)
			enterZone(player, zone, gate, race)
		end
	)
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
	CombatService.Defeated:Connect(onDefeated)
	CombatService.CombatLogged:Connect(function(entity: CombatService.Entity, attacker: CombatService.Entity?)
		local victim = entity.player
		if victim and attacker and attacker.player and attacker.race ~= entity.race then
			recordDefeat(victim, attacker.player)
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

-- One war-zone boss: a camp of one that runs BossService while alive.
local function spawnBoss(
	zone: WorldLayout.WarZone,
	spec: WorldLayout.ZoneBoss,
	groundAt: (number, number) -> number
)
	local c = zone.center
	local position = Vector3.new(c[1] + spec.x, c[2], c[3] + spec.z)
	local attached: { [MobService.Mob]: BossService.Boss } = {}
	local function announce(key: string, params: { [string]: string }?)
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
	local slots = MobService:SpawnCamp(spec.enemy, position, 1, zone.id, groundAt, {
		respawnSeconds = bossRespawnSeconds,
		xpRecipients = groupRecipients,
		onSpawn = function(mob)
			local boss = BossService:Attach(mob, spec.enemy, zone.id, announce)
			if boss then
				attached[mob] = boss
			end
		end,
	})
	local slot = slots[1]
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
	MobService.MobDefeated:Connect(function(mob)
		local boss = attached[mob]
		if boss then
			attached[mob] = nil
			for _, add in boss.adds do
				MobService:Despawn(add)
			end
			BossService:Detach(mob)
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

function PvPService:Start()
	for _, zone in WorldLayout.WarZones :: { [string]: WorldLayout.WarZone } do
		for race in WorldLayout.Realms :: { [string]: any } do
			openGate(race, zone)
		end
		for race in zone.bases do
			local portal = WorldService:GetReturnPortal(zone.id, race)
			if portal then
				prompt(portal, "Return home", `{zone.name} · {race} camp`).Triggered:Connect(function(player)
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
