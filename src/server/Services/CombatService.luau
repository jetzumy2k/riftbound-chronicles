--!strict
--[[
	CombatService (Layer 4) — server-authoritative combat (Phase 6).

	Owns every combat entity (player characters and server NPCs such as
	training dummies): HP, Focus, combat tag, protection, defeat.

	  - All numbers come from shared Logic/CombatMath and profile/server stats.
	    No remote accepts damage, healing, HP or death. Clients only send
	    `BasicAttack(target?)` intents.
	  - Every hit is validated: attacker alive and off cooldown, target exists
	    and is hostile (race, safe zones recomputed now, protection), range with
	    bounded lag compensation, line of sight for ranged attacks.
	  - Authoritative HP lives here; Humanoid.Health is a display mirror
	    (never below 1 while alive so the engine never "kills" a character on
	    its own). Defeat exists only when this service says so.
	  - Defeat (SECURITY_MODEL §5A.1): stylised, non-graphic; after
	    DefeatDelaySeconds the player respawns at their race's safe zone with
	    spawn protection. Deaths the server did not cause (client reset,
	    void fall) are resolved by combat state: while combat-tagged they count
	    as a defeat credited to the last attacker; otherwise they are a
	    rate-limited reset.
	  - Regen: CLAUDE.md §5 HP regen out of combat (D-04), fast regen in safe
	    zones (proposed D-29), Focus regen (D-23).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local BasicAttacks = require(Shared.Definitions.BasicAttacks)
local CombatMath = require(Shared.Logic.CombatMath)
local StatFormulas = require(Shared.Logic.StatFormulas)
local Log = require(Shared.Util.Log)
local Signal = require(Shared.Util.Signal)

local AuditLogService = require(script.Parent.AuditLogService)
local ConfigurationService = require(script.Parent.ConfigurationService)
local NetService = require(script.Parent.NetService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local LevelService = require(script.Parent.LevelService)
local StatsService = require(script.Parent.StatsService)
local JobService = require(script.Parent.JobService)
local SafeZoneService = require(script.Parent.SafeZoneService)

local TICK_SECONDS = 0.25
local AUTO_TARGET_CONE = 0.35 -- dot product: ~70 degrees either side of facing
local NPC_RESET_SECONDS = 3

local log = Log.new("CombatService")

export type Entity = {
	kind: "Player" | "Npc",
	player: Player?,
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	name: string,
	level: number,
	race: string?,
	hp: number,
	maxHp: number,
	focus: number,
	attack: number,
	defense: number,
	critChancePct: number,
	critMultiplier: number,
	regenPct: number,
	defeated: boolean,
	protectedUntil: number,
	lastHostileAt: number,
	lastAttacker: Entity?,
	nextAttackAt: number,
	lastResetAt: number,
}

local CombatService = {
	-- (entity, attacker?, reason) once an entity is defeated. Handlers must not yield.
	Defeated = Signal.new(),
	-- (player) when a defeated/reset player should respawn at home (TravelService).
	RespawnRequested = Signal.new(),
}

local BLOCKED_NOTICE_SECONDS = 1.5

-- Player-facing reasons an attack did nothing (client maps keys to text).
local BLOCK_TEXT_KEYS: { [string]: string } = {
	safeZone = "combat.blocked.safeZone",
	protected = "combat.blocked.protected",
	sameRace = "combat.blocked.sameRace",
	outOfRange = "combat.blocked.outOfRange",
	lineOfSight = "combat.blocked.lineOfSight",
	noTarget = "combat.blocked.noTarget",
}

local entitiesByModel: { [Model]: Entity } = {}
local lastNoticeAt: { [Player]: number } = {}
local entityByPlayer: { [Player]: Entity } = {}
local rng = Random.new()

local function combatConfig(): any
	return ConfigurationService:Get("Combat")
end

local function now(): number
	return os.clock()
end

local function inSafeZone(entity: Entity): boolean
	return SafeZoneService:GetZoneAt(entity.root.Position) ~= nil
end

local function isProtected(entity: Entity): boolean
	return now() < entity.protectedUntil
end

local function inCombat(entity: Entity): boolean
	return now() - entity.lastHostileAt < combatConfig().TagSeconds
end

--------------------------------------------------------------------------------
-- Mirroring (display only)
--------------------------------------------------------------------------------

local function mirror(entity: Entity)
	local model = entity.model
	local hp = math.floor(entity.hp + 0.5)
	if model:GetAttribute("HP") ~= hp then
		model:SetAttribute("HP", hp)
	end
	local maxHp = math.floor(entity.maxHp + 0.5)
	if model:GetAttribute("MaxHP") ~= maxHp then
		model:SetAttribute("MaxHP", maxHp)
	end
	local focus = math.floor(entity.focus)
	if model:GetAttribute("Focus") ~= focus then
		model:SetAttribute("Focus", focus)
	end
	model:SetAttribute("Defeated", entity.defeated)
	model:SetAttribute("Protected", isProtected(entity))

	local humanoid = entity.humanoid
	if humanoid.Parent then
		humanoid.MaxHealth = math.max(entity.maxHp, 1)
		humanoid.Health = if entity.defeated then 1 else math.clamp(entity.hp, 1, entity.maxHp)
	end
end

local function broadcast(target: Entity, payload: { [string]: any })
	local radius = combatConfig().RelevanceRadius
	local recipients = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and (root.Position - target.root.Position).Magnitude <= radius then
			table.insert(recipients, player)
		end
	end
	if #recipients > 0 then
		NetService:FireClients("CombatEvent", recipients, payload)
	end
end

--------------------------------------------------------------------------------
-- Stats
--------------------------------------------------------------------------------

local function applyStats(entity: Entity, stats: StatFormulas.BaseStats, level: number, keepRatio: boolean)
	local ratio = if keepRatio and entity.maxHp > 0 then entity.hp / entity.maxHp else 1
	entity.level = level
	entity.maxHp = stats.MaxHP
	entity.hp = math.clamp(stats.MaxHP * ratio, 0, stats.MaxHP)
	entity.attack = stats.Attack
	entity.defense = stats.Defense
	entity.critChancePct = stats.CritChancePct
	entity.critMultiplier = stats.CritMultiplier
	entity.regenPct = stats.HPRegenPct
end

local function newEntity(
	kind: "Player" | "Npc",
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	name: string
): Entity
	return {
		kind = kind,
		player = nil,
		model = model,
		humanoid = humanoid,
		root = root,
		name = name,
		level = 0,
		race = nil,
		hp = 1,
		maxHp = 1,
		focus = 0,
		attack = 0,
		defense = 0,
		critChancePct = 0,
		critMultiplier = 1,
		regenPct = 0,
		defeated = false,
		protectedUntil = 0,
		lastHostileAt = -math.huge,
		lastAttacker = nil,
		nextAttackAt = 0,
		lastResetAt = -math.huge,
	}
end

--------------------------------------------------------------------------------
-- Defeat
--------------------------------------------------------------------------------

local defeat: (entity: Entity, attacker: Entity?, reason: string) -> ()

local function requestRespawn(entity: Entity)
	local player = entity.player
	if player and player.Parent == Players then
		CombatService.RespawnRequested:Fire(player)
	end
end

function defeat(entity: Entity, attacker: Entity?, reason: string)
	if entity.defeated then
		return
	end
	entity.defeated = true
	entity.hp = 0
	entity.humanoid.WalkSpeed = 0
	entity.humanoid.JumpPower = 0
	mirror(entity)
	broadcast(entity, { kind = "Defeat", target = entity.model })
	log:Info("%s defeated by %s (%s)", entity.name, if attacker then attacker.name else "nothing", reason)
	CombatService.Defeated:Fire(entity, attacker, reason)

	if entity.kind == "Npc" then
		task.delay(NPC_RESET_SECONDS, function()
			if entitiesByModel[entity.model] == entity then
				entity.defeated = false
				entity.hp = entity.maxHp
				entity.lastAttacker = nil
				mirror(entity)
				broadcast(entity, { kind = "Revive", target = entity.model })
			end
		end)
	else
		task.delay(combatConfig().DefeatDelaySeconds, requestRespawn, entity)
	end
end

local function applyDamage(target: Entity, amount: number, attacker: Entity, crit: boolean)
	local t = now()
	target.hp = math.max(0, target.hp - amount)
	target.lastHostileAt = t
	target.lastAttacker = attacker
	attacker.lastHostileAt = t
	mirror(target)
	broadcast(target, { kind = "Damage", target = target.model, amount = amount, crit = crit })
	if target.hp <= 0 then
		defeat(target, attacker, "Combat")
	end
end

-- The character died without CombatService deciding it (reset, void, exploit).
local function onUnsanctionedDeath(entity: Entity)
	if entity.defeated then
		return
	end
	local player = entity.player
	if inCombat(entity) then
		defeat(entity, entity.lastAttacker, "CombatReset")
		return
	end
	local t = now()
	if player and t - entity.lastResetAt < combatConfig().ResetCooldownSeconds then
		AuditLogService:Security(player, "ResetSpam", "reset again within cooldown")
	end
	entity.lastResetAt = t
	entity.defeated = true
	mirror(entity)
	task.delay(1, requestRespawn, entity)
end

--------------------------------------------------------------------------------
-- Player entities
--------------------------------------------------------------------------------

local function removeEntity(model: Model)
	local entity = entitiesByModel[model]
	if entity == nil then
		return
	end
	entitiesByModel[model] = nil
	if entity.player and entityByPlayer[entity.player] == entity then
		entityByPlayer[entity.player] = nil
	end
end

local function setupCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	local stats = StatsService:GetBaseStats(player)
	local data = PlayerDataService:GetData(player)
	if
		humanoid == nil
		or not humanoid:IsA("Humanoid")
		or root == nil
		or not root:IsA("BasePart")
		or stats == nil
		or data == nil
		or player.Character ~= character
	then
		return
	end

	humanoid.BreakJointsOnDeath = false
	local entity = newEntity("Player", character, humanoid, root, player.Name)
	entity.player = player
	entity.race = data.Race
	applyStats(entity, stats, data.Level, false)
	entity.focus = combatConfig().FocusMax
	entity.protectedUntil = now() + combatConfig().SpawnProtectSeconds

	if entityByPlayer[player] then
		removeEntity(entityByPlayer[player].model)
	end
	entitiesByModel[character] = entity
	entityByPlayer[player] = entity
	mirror(entity)

	humanoid.Died:Connect(function()
		onUnsanctionedDeath(entity)
	end)
	character.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			removeEntity(character)
		end
	end)
end

--------------------------------------------------------------------------------
-- Attacks
--------------------------------------------------------------------------------

local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Include

local function hasLineOfSight(from: Vector3, to: Vector3): boolean
	local world = Workspace:FindFirstChild("RC_World")
	if world == nil then
		return true
	end
	raycastParams.FilterDescendantsInstances = { world }
	local direction = to - from
	return Workspace:Raycast(from, direction, raycastParams) == nil
end

local function harmFacts(attacker: Entity, target: Entity): CombatMath.HarmFacts
	return {
		sameEntity = attacker == target,
		attackerIsPlayer = attacker.kind == "Player",
		targetIsPlayer = target.kind == "Player",
		attackerRace = attacker.race,
		targetRace = target.race,
		attackerInSafeZone = inSafeZone(attacker),
		targetInSafeZone = inSafeZone(target),
		attackerDefeated = attacker.defeated,
		targetDefeated = target.defeated,
		targetProtected = isProtected(target),
	}
end

-- Nearest hostile entity in front of the attacker within range.
local function autoTarget(attacker: Entity, range: number): Entity?
	local best: Entity? = nil
	local bestDistance = math.huge
	local origin = attacker.root.Position
	local facing = attacker.root.CFrame.LookVector
	for _, candidate in entitiesByModel do
		if candidate == attacker or candidate.defeated then
			continue
		end
		local offset = candidate.root.Position - origin
		local distance = offset.Magnitude
		if distance > range + combatConfig().RangeToleranceStuds or distance >= bestDistance then
			continue
		end
		local flat = Vector3.new(offset.X, 0, offset.Z)
		if flat.Magnitude > 0.5 and flat.Unit:Dot(facing) < AUTO_TARGET_CONE then
			continue
		end
		if CombatMath.canHarm(harmFacts(attacker, candidate)) then
			best = candidate
			bestDistance = distance
		end
	end
	return best
end

-- Tells the attacker why nothing happened, at most once per BLOCKED_NOTICE_SECONDS.
local function notifyBlocked(player: Player, reason: string)
	local key = BLOCK_TEXT_KEYS[reason]
	if key == nil then
		return
	end
	local t = now()
	if t - (lastNoticeAt[player] or -math.huge) < BLOCKED_NOTICE_SECONDS then
		return
	end
	lastNoticeAt[player] = t
	NetService:FireClient("Notify", player, { kind = "Warning", textKey = key })
end

local function onBasicAttack(player: Player, targetModel: Model?)
	local attacker = entityByPlayer[player]
	if attacker == nil or attacker.defeated then
		return
	end
	local attack = BasicAttacks.forJob(JobService:GetJob(player))
	if attack == nil then
		return
	end
	local t = now()
	if t < attacker.nextAttackAt then
		return -- cooldown is server-tracked; early presses are simply ignored
	end
	attacker.nextAttackAt = t + attack.cooldown
	-- Attacking ends spawn / exit protection immediately.
	attacker.protectedUntil = 0

	local target = if targetModel then entitiesByModel[targetModel] else autoTarget(attacker, attack.range)
	if target == nil then
		notifyBlocked(player, if inSafeZone(attacker) then "safeZone" else "noTarget")
		return
	end

	local allowed, reason = CombatMath.canHarm(harmFacts(attacker, target))
	if not allowed then
		log:Debug("%s -> %s blocked: %s", attacker.name, target.name, tostring(reason))
		notifyBlocked(player, reason or "")
		return
	end

	local config = combatConfig()
	local distance = (target.root.Position - attacker.root.Position).Magnitude
	local targetSpeed = target.root.AssemblyLinearVelocity.Magnitude
	if not CombatMath.withinRange(distance, attack.range, player:GetNetworkPing(), targetSpeed, config) then
		-- Clicking a far target is normal; only impossible distances are suspicious.
		if distance > attack.range * 2 + config.RangeToleranceStuds then
			AuditLogService:Security(player, "OutOfRange", `{attack.name} at {math.floor(distance)} studs`)
		end
		notifyBlocked(player, "outOfRange")
		return
	end
	if attack.style ~= "Melee" then
		local head = attacker.model:FindFirstChild("Head")
		local from = if head and head:IsA("BasePart") then head.Position else attacker.root.Position
		if not hasLineOfSight(from, target.root.Position) then
			notifyBlocked(player, "lineOfSight")
			return
		end
	end

	local amount, crit = CombatMath.damage({
		attack = attacker.attack,
		attackerLevel = attacker.level,
		coefficient = attack.coefficient,
		critChancePct = attacker.critChancePct,
		critMultiplier = attacker.critMultiplier,
		roll = rng:NextNumber(),
		defense = target.defense,
	}, config)
	applyDamage(target, amount, attacker, crit)
end

--------------------------------------------------------------------------------
-- Regeneration tick
--------------------------------------------------------------------------------

local function tick(dt: number)
	local config = combatConfig()
	local t = now()
	for _, entity in entitiesByModel do
		if entity.defeated then
			continue
		end
		local before = entity.hp
		if entity.kind == "Npc" then
			if t - entity.lastHostileAt > NPC_RESET_SECONDS then
				entity.hp = entity.maxHp
			end
		elseif inSafeZone(entity) then
			entity.hp += entity.maxHp * config.SafeZoneRegenPctPerSecond / 100 * dt
		elseif t - entity.lastHostileAt >= config.RegenDelaySeconds then
			entity.hp += CombatMath.regen(entity.maxHp, entity.regenPct, dt)
		end
		entity.hp = math.min(entity.hp, entity.maxHp)
		entity.focus = math.min(config.FocusMax, entity.focus + config.FocusRegenPerSecond * dt)
		if entity.hp ~= before or entity.kind == "Player" then
			mirror(entity)
		end
	end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function CombatService:Init()
	NetService:RegisterStateCheck("Alive", function(player)
		local entity = entityByPlayer[player]
		return entity ~= nil and not entity.defeated
	end)
	NetService:Handle("BasicAttack", onBasicAttack)

	LevelService.LevelChanged:Connect(function(player, level)
		local entity = entityByPlayer[player]
		local stats = StatsService:GetBaseStats(player)
		if entity and stats then
			applyStats(entity, stats, level, true)
			mirror(entity)
		end
	end)

	SafeZoneService.ZoneChanged:Connect(function(player, oldZone, newZone)
		local entity = entityByPlayer[player]
		if entity and oldZone ~= nil and newZone == nil then
			-- Exit bubble: no ambush right at the safe-zone edge.
			entity.protectedUntil = math.max(entity.protectedUntil, now() + combatConfig().ExitBubbleSeconds)
		end
	end)
end

function CombatService:Start()
	local function watch(player: Player)
		player.CharacterAdded:Connect(function(character)
			task.spawn(setupCharacter, player, character)
		end)
		if player.Character then
			task.spawn(setupCharacter, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		local entity = entityByPlayer[player]
		if entity then
			if inCombat(entity) and entity.lastAttacker then
				log:Info("%s left while in combat", entity.name)
			end
			removeEntity(entity.model)
		end
		lastNoticeAt[player] = nil
	end)

	task.spawn(function()
		while true do
			local dt = task.wait(TICK_SECONDS)
			tick(dt)
		end
	end)
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

export type NpcSpec = {
	name: string,
	level: number,
	maxHp: number,
}

--[[
	Registers a server-owned NPC (training dummy now, mobs in Phase 9).
	The model must have a Humanoid and a HumanoidRootPart.
]]
function CombatService:RegisterNpc(model: Model, spec: NpcSpec): boolean
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or root == nil or not root:IsA("BasePart") then
		return false
	end
	local entity = newEntity("Npc", model, humanoid, root, spec.name)
	applyStats(entity, StatFormulas.forLevel(spec.level), spec.level, false)
	entity.maxHp = spec.maxHp
	entity.hp = spec.maxHp
	entitiesByModel[model] = entity
	humanoid.BreakJointsOnDeath = false
	mirror(entity)
	return true
end

function CombatService:GetEntity(model: Model): Entity?
	return entitiesByModel[model]
end

function CombatService:GetPlayerEntity(player: Player): Entity?
	return entityByPlayer[player]
end

return CombatService
