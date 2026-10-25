--!strict
--[[
	CombatService (Layer 4) — server-authoritative combat (Phase 6).

	Owns every combat entity (player characters and server NPCs such as
	training dummies): HP, Focus, combat tag, protection, defeat.

	  - All numbers come from shared Logic/CombatMath and profile/server stats.
	    No remote accepts damage, healing, HP or death. Clients only send
	    `BasicAttack(target?)` intents.
	  - Basic attacks are 3-step combos (BasicAttacks, Logic/ComboMath): the
	    server decides the step from its own timing. Damage lands on the
	    clip's Hit frame (plus projectile travel time) and the target is
	    re-validated at that moment (D-36).
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
	    zones (D-29), rest regen out of combat with no creature near (D-46),
	    Focus regen (D-23).
	  - Statuses (Phase 5 skills, D-45) live on the entity with an expiry:
	    Stun, Freeze, Root, Slow, Silence, Mark, Weaken, Poison, Burn, Guard,
	    Harden, Empower, Haste, Regen, Shield, Taunt. Attack is scaled by
	    Empower / Weaken, Defense by Harden; every hit goes through Mark /
	    Guard / Shield (Logic/SkillRules.incoming). Poison / Burn damage and
	    Regen healing tick once a second, credited to whoever applied them.
	    A player can't be stunned / frozen again for
	    `Skills.ControlImmunitySeconds` after one ends. Statuses are mirrored
	    as model attributes for display (Stunned, Frozen, ..., Shield) and
	    announced with `StatusChanged` so MovementService / MobService apply
	    the speed effects. SkillService calls the skill primitives (Strike,
	    HealTarget, ApplyStatus, ...).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local BasicAttacks = require(Shared.Definitions.BasicAttacks)
local CombatMath = require(Shared.Logic.CombatMath)
local PvPRules = require(Shared.Logic.PvPRules)
local ComboMath = require(Shared.Logic.ComboMath)
local SkillRules = require(Shared.Logic.SkillRules)
local StatFormulas = require(Shared.Logic.StatFormulas)
local Log = require(Shared.Util.Log)
local Signal = require(Shared.Util.Signal)

local AuditLogService = require(script.Parent.AuditLogService)
local ConfigurationService = require(script.Parent.ConfigurationService)
local NetService = require(script.Parent.NetService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local EventService = require(script.Parent.EventService)
local LevelService = require(script.Parent.LevelService)
local StatsService = require(script.Parent.StatsService)
local JobService = require(script.Parent.JobService)
local SafeZoneService = require(script.Parent.SafeZoneService)
local AntiExploitService = require(script.Parent.AntiExploitService)

local TICK_SECONDS = 0.25
-- Rest regen re-checks (creature distance) this often per player.
local REST_CHECK_SECONDS = 0.5
local AUTO_TARGET_CONE = 0.35 -- dot product: ~70 degrees either side of facing
local NPC_RESET_SECONDS = 3
-- Combo presses may arrive this much early (network jitter).
local COMBO_SLACK = 0.1
-- Extra reach a melee hit keeps between the swing and its Hit frame.
local MELEE_FOLLOW_STUDS = 6
-- Client lunge duration (CombatController); used for the speed allowance.
local LUNGE_SECONDS = 0.14

local log = Log.new("CombatService")

-- Client status visuals find every combat entity by this tag.
local COMBATANT_TAG = "RC_Combatant"

export type StatusKind =
	"Stun"
	| "Freeze"
	| "Root"
	| "Slow"
	| "Silence"
	| "Mark"
	| "Weaken"
	| "Poison"
	| "Burn"
	| "Guard"
	| "Harden"
	| "Empower"
	| "Haste"
	| "Regen"
	| "Shield"
	| "Taunt"
--[[
	`value`: percent (Slow / Mark / Weaken / Guard / Harden / Empower /
	Haste) or Shield points left. `perTick`: damage (Poison / Burn) or
	healing (Regen) every second. `source`: who applied it (credit, taunt).
]]
export type Status =
	{ untilAt: number, value: number, source: Entity?, perTick: number?, nextTickAt: number? }

-- Display attribute per status (boolean, except Shield which carries points).
local STATUS_ATTRIBUTES: { [string]: string } = {
	Stun = "Stunned",
	Freeze = "Frozen",
	Root = "Rooted",
	Slow = "Slowed",
	Silence = "Silenced",
	Mark = "Marked",
	Weaken = "Weakened",
	Poison = "Poisoned",
	Burn = "Burning",
	Guard = "Guarded",
	Harden = "Hardened",
	Empower = "Empowered",
	Haste = "Hasted",
	Regen = "Regenerating",
	Shield = "Shield",
	Taunt = "Taunted",
}
-- Over-time statuses tick once per second.
local TICK_SECONDS_DOT = 1

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
	-- Players: gear bonuses (Phase 7, D-64; percent).
	skillPowerPct: number,
	healingPowerPct: number,
	mitigationPct: number,
	focusEfficiencyPct: number,
	defeated: boolean,
	protectedUntil: number,
	lastHostileAt: number,
	lastAttacker: Entity?,
	combo: ComboMath.State,
	lastResetAt: number,
	-- Damage dealt to this entity by each player (EXP credit for NPCs).
	contributors: { [Player]: number },
	-- NPCs: revive in place after defeat (training dummies) and regenerate
	-- out of combat. Mobs turn both off; MobService owns their lifecycle.
	autoRevive: boolean,
	regen: boolean,
	statuses: { [string]: Status },
	-- Bosses: immune to crowd control (Taunt still works).
	controlImmune: boolean,
	-- Players: no new stun / freeze until then (after one ends).
	ccImmuneUntil: number,
	-- Basic attacks wait until then (a skill's cast animation is playing).
	attackLockUntil: number,
	-- NPCs: outgoing damage multiplier (an enraged boss, D-47).
	outgoingScale: number,
	-- Players: resting (out of combat, no creature near) and when to re-check.
	resting: boolean,
	restCheckAt: number,
}

local CombatService = {
	-- (entity, attacker?, reason) once an entity is defeated. Handlers must not yield.
	Defeated = Signal.new(),
	-- (player) when a defeated/reset player should respawn at home (TravelService).
	RespawnRequested = Signal.new(),
	-- (entity, lastAttacker) a player left the game while combat-tagged.
	CombatLogged = Signal.new(),
	-- (entity) a status started or ended (speed effects). Handlers must not yield.
	StatusChanged = Signal.new(),
	-- (model, amount, crit) a creature took a hit and is still standing
	-- (MobService: stagger, enrage). Handlers must not yield.
	NpcHurt = Signal.new(),
	-- (attackerPlayer, victimPlayer) a player hurt a player (quests, D-73).
	-- Handlers must not yield.
	PlayerHit = Signal.new(),
}

-- "Why didn't my attack do anything?" toasts: at most this often per player.
local BLOCKED_NOTICE_SECONDS = 5

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

-- The live status of `kind` (nil once expired).
local function statusOf(entity: Entity, kind: string): Status?
	local status = entity.statuses[kind]
	if status and now() < status.untilAt then
		return status
	end
	return nil
end

-- Stunned or frozen: can't move, attack or cast.
local function isStunned(entity: Entity): boolean
	return statusOf(entity, "Stun") ~= nil or statusOf(entity, "Freeze") ~= nil
end

local function isSilenced(entity: Entity): boolean
	return statusOf(entity, "Silence") ~= nil
end

local function statusValue(entity: Entity, kind: string): number
	local status = statusOf(entity, kind)
	return if status then status.value else 0
end

-- Attack after Empower / Weaken; Defense after Harden.
local function attackOf(entity: Entity, base: number): number
	return base
		* entity.outgoingScale
		* SkillRules.attackScale(statusValue(entity, "Empower"), statusValue(entity, "Weaken"))
end

local function defenseOf(entity: Entity): number
	return entity.defense * (1 + statusValue(entity, "Harden") / 100)
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

-- Status attributes (display only; the server reads `entity.statuses`).
local function mirrorStatuses(entity: Entity)
	local model = entity.model
	for kind, attribute in STATUS_ATTRIBUTES do
		local status = statusOf(entity, kind)
		local value: any = nil
		if status then
			value = if kind == "Shield" then math.floor(status.value) else true
		end
		if model:GetAttribute(attribute) ~= value then
			model:SetAttribute(attribute, value)
		end
	end
end

local function broadcast(target: Entity, payload: { [string]: any }, exclude: Player?)
	local radius = combatConfig().RelevanceRadius
	local recipients = {}
	for _, player in Players:GetPlayers() do
		if player == exclude then
			continue
		end
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
	-- Gear extras (players; StatsService:GetStats). Creatures have none.
	local extras = stats :: any
	entity.skillPowerPct = extras.SkillPowerPct or 0
	entity.healingPowerPct = extras.HealingPowerPct or 0
	entity.mitigationPct = extras.MitigationPct or 0
	entity.focusEfficiencyPct = extras.FocusEfficiencyPct or 0
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
		skillPowerPct = 0,
		healingPowerPct = 0,
		mitigationPct = 0,
		focusEfficiencyPct = 0,
		defeated = false,
		protectedUntil = 0,
		lastHostileAt = -math.huge,
		lastAttacker = nil,
		combo = ComboMath.new(),
		lastResetAt = -math.huge,
		contributors = {},
		autoRevive = true,
		regen = true,
		statuses = {},
		controlImmune = false,
		ccImmuneUntil = -math.huge,
		attackLockUntil = -math.huge,
		outgoingScale = 1,
		resting = false,
		restCheckAt = 0,
	}
end

local function clearStatuses(entity: Entity)
	if next(entity.statuses) == nil then
		return
	end
	entity.statuses = {}
	mirrorStatuses(entity)
	CombatService.StatusChanged:Fire(entity)
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
	clearStatuses(entity)
	entity.humanoid.WalkSpeed = 0
	entity.humanoid.JumpPower = 0
	mirror(entity)
	broadcast(entity, { kind = "Defeat", target = entity.model })
	log:Info("%s defeated by %s (%s)", entity.name, if attacker then attacker.name else "nothing", reason)
	CombatService.Defeated:Fire(entity, attacker, reason)

	if entity.kind == "Npc" and entity.autoRevive then
		task.delay(NPC_RESET_SECONDS, function()
			if entitiesByModel[entity.model] == entity then
				entity.defeated = false
				entity.hp = entity.maxHp
				entity.lastAttacker = nil
				entity.contributors = {}
				mirror(entity)
				broadcast(entity, { kind = "Revive", target = entity.model })
			end
		end)
	else
		task.delay(combatConfig().DefeatDelaySeconds, requestRespawn, entity)
	end
end

export type HitExtra = { skill: string?, combo: string?, tick: string? }

local function applyDamage(
	target: Entity,
	rawAmount: number,
	attacker: Entity,
	crit: boolean,
	heavy: boolean?,
	extra: HitExtra?
)
	local t = now()
	-- Gear damage reduction (D-64), then Mark / Guard scale the hit, then a
	-- shield soaks up what it can.
	if target.mitigationPct > 0 then
		rawAmount = math.max(1, rawAmount * (1 - target.mitigationPct / 100))
	end
	local mark, guard, shield =
		statusOf(target, "Mark"), statusOf(target, "Guard"), statusOf(target, "Shield")
	local amount, absorbed, shieldLeft = SkillRules.incoming(
		rawAmount,
		if mark then mark.value else 0,
		if guard then guard.value else 0,
		if shield then shield.value else 0
	)
	if shield then
		shield.value = shieldLeft
		if shieldLeft <= 0 then
			target.statuses["Shield"] = nil
		end
		mirrorStatuses(target)
	end
	target.hp = math.max(0, target.hp - amount)
	target.lastHostileAt = t
	target.lastAttacker = attacker
	attacker.lastHostileAt = t
	local credited = attacker.player
	if credited then
		target.contributors[credited] = (target.contributors[credited] or 0) + amount
		if target.player and amount > 0 then
			CombatService.PlayerHit:Fire(credited, target.player)
		end
	end
	mirror(target)
	broadcast(target, {
		kind = "Damage",
		target = target.model,
		amount = amount,
		crit = crit,
		source = attacker.model,
		heavy = heavy == true,
		absorbed = if absorbed > 0 then absorbed else nil,
		skill = extra and extra.skill,
		combo = extra and extra.combo,
		tick = extra and extra.tick,
	})
	if target.hp <= 0 then
		defeat(target, attacker, "Combat")
	elseif target.kind == "Npc" and amount > 0 then
		CombatService.NpcHurt:Fire(target.model, amount, crit)
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
	local stats = StatsService:GetStats(player)
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
	CollectionService:AddTag(character, COMBATANT_TAG)

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

-- Attack stat and level a player uses against `target`. D-16: against a
-- lower-level player you fight at min(own, theirs + gap).
local function offense(attacker: Entity, target: Entity): (number, number)
	if attacker.kind == "Player" and target.kind == "Player" then
		local pvp = ConfigurationService:Get("PvP")
		local effective = PvPRules.normalizedLevel(attacker.level, target.level, pvp.LevelGap)
		if effective < attacker.level then
			-- Scale the whole Attack (gear included, D-64) down to that level.
			local ratio = StatFormulas.forLevel(effective).Attack
				/ StatFormulas.forLevel(attacker.level).Attack
			return attacker.attack * ratio, effective
		end
	end
	return attacker.attack, attacker.level
end

-- Computes and applies one hit (callers have validated it).
local function strike(
	attacker: Entity,
	target: Entity,
	coefficient: number,
	critBonusPct: number,
	heavy: boolean?,
	extra: HitExtra?
)
	local attackStat, attackLevel = offense(attacker, target)
	local amount, crit = CombatMath.damage({
		attack = attackOf(attacker, attackStat),
		attackerLevel = attackLevel,
		coefficient = coefficient,
		critChancePct = attacker.critChancePct + critBonusPct,
		critMultiplier = attacker.critMultiplier,
		roll = rng:NextNumber(),
		defense = defenseOf(target),
	}, combatConfig())
	applyDamage(target, amount, attacker, crit, heavy, extra)
end

-- Damage one over-time tick deals (no crit), worked out when it is applied.
local function tickDamage(attacker: Entity, target: Entity, coefficient: number): number
	local attackStat, attackLevel = offense(attacker, target)
	local amount = CombatMath.damage({
		attack = attackOf(attacker, attackStat),
		attackerLevel = attackLevel,
		coefficient = coefficient,
		critChancePct = 0,
		critMultiplier = 1,
		roll = 1,
		defense = defenseOf(target),
	}, combatConfig())
	return amount
end

local function healAmount(healer: Entity, coefficient: number, allowCrit: boolean): (number, boolean)
	return CombatMath.heal({
		attack = attackOf(healer, healer.attack),
		attackerLevel = healer.level,
		-- Gear Healing Power (D-64): heals, shields and regeneration; live
		-- events (Healing Festival, D-89).
		coefficient = coefficient * (1 + healer.healingPowerPct / 100) * (if healer.player
			then EventService:Factor("Healing", healer.player)
			else 1),
		critChancePct = if allowCrit then healer.critChancePct else 0,
		critMultiplier = healer.critMultiplier,
		roll = if allowCrit then rng:NextNumber() else 1,
	}, combatConfig())
end

-- The hit lands (Hit frame / projectile arrival): re-check, then damage.
local function landHit(
	attacker: Entity,
	target: Entity,
	attack: BasicAttacks.BasicAttack,
	step: BasicAttacks.ComboStep
)
	if
		entitiesByModel[attacker.model] ~= attacker
		or entitiesByModel[target.model] ~= target
		or attacker.defeated
		or target.defeated
	then
		return
	end
	-- Safe zones and protection may have changed while the swing / arrow flew.
	if not CombatMath.canHarm(harmFacts(attacker, target)) then
		return
	end
	local config = combatConfig()
	if attack.style == "Melee" then
		local distance = (target.root.Position - attacker.root.Position).Magnitude
		if distance > attack.range + config.RangeToleranceStuds + MELEE_FOLLOW_STUDS then
			return -- the target stepped out of the swing
		end
	end
	strike(attacker, target, step.coefficient, 0, step.heavy)
end

local function onBasicAttack(player: Player, targetModel: Model?)
	local attacker = entityByPlayer[player]
	if attacker == nil or attacker.defeated or isStunned(attacker) then
		return
	end
	-- A skill's cast is still playing out (small slack for network jitter).
	if now() < attacker.attackLockUntil - COMBO_SLACK then
		return
	end
	local attack = BasicAttacks.forJob(JobService:GetJob(player))
	if attack == nil then
		return
	end
	local t = now()
	-- The server decides the combo step from its own clock; early presses
	-- are simply ignored.
	local stepIndex = ComboMath.resolve(attacker.combo, t, attack.steps, COMBO_SLACK)
	if stepIndex == nil then
		return
	end
	ComboMath.commit(attacker.combo, t, attack.steps, stepIndex, attack.finisherCooldown)
	local step = attack.steps[stepIndex]
	-- Attacking ends spawn / exit protection immediately.
	attacker.protectedUntil = 0
	if step.lunge then
		-- The client may step in toward its target during the swing.
		AntiExploitService:GrantSpeedAllowance(player, step.lunge / LUNGE_SECONDS, LUNGE_SECONDS + 0.5)
	end
	local target = if targetModel then entitiesByModel[targetModel] else autoTarget(attacker, attack.range)
	-- Everyone nearby (attacker included, for aim / projectile VFX) sees the
	-- swing or cast; the attacker's client already started it locally.
	broadcast(attacker, {
		kind = "Attack",
		target = attacker.model,
		action = step.clip,
		step = stepIndex,
		aim = if target then target.model else nil,
	})
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

	local travel = if step.projectileSpeed then distance / step.projectileSpeed else 0
	task.delay(BasicAttacks.hitTime(step) + travel, landHit, attacker, target, attack, step)
end

--------------------------------------------------------------------------------
-- Regeneration tick
--------------------------------------------------------------------------------

-- A live creature that fights back (mob / boss, not a training dummy) near `entity`.
local function creatureNear(entity: Entity, radius: number): boolean
	local position = entity.root.Position
	for _, other in entitiesByModel do
		if
			other.kind == "Npc"
			and not other.autoRevive
			and not other.defeated
			and (other.root.Position - position).Magnitude <= radius
		then
			return true
		end
	end
	return false
end

-- Rest regen (creator review 2026-10-17): out of combat for a moment with no
-- creature nearby, players recover RestRegenPctPerSecond of max HP per
-- second anywhere: dungeons, forest, desert, war zones. Re-checked twice a
-- second; the HUD shows "resting" from the model attribute.
local function updateResting(entity: Entity, t: number, config: any)
	if t < entity.restCheckAt then
		return
	end
	entity.restCheckAt = t + REST_CHECK_SECONDS
	local resting = t - entity.lastHostileAt >= config.RegenDelaySeconds
		and entity.hp < entity.maxHp
		and not creatureNear(entity, config.RestCreatureRadius)
	if resting ~= entity.resting then
		entity.resting = resting
		entity.model:SetAttribute("Resting", if resting then true else nil)
	end
end

local function tick(dt: number)
	local config = combatConfig()
	local t = now()
	for _, entity in entitiesByModel do
		if entity.defeated then
			continue
		end
		-- Over-time ticks first (the last one lands exactly at the expiry).
		for kind, status in entity.statuses do
			local perTick, nextTickAt = status.perTick, status.nextTickAt
			if perTick and nextTickAt and t >= nextTickAt and nextTickAt <= status.untilAt + 0.01 then
				status.nextTickAt = nextTickAt + TICK_SECONDS_DOT
				if kind == "Regen" then
					local before = entity.hp
					entity.hp = math.min(entity.maxHp, entity.hp + perTick)
					local healed = math.floor(entity.hp - before + 0.5)
					if healed > 0 then
						mirror(entity)
						broadcast(
							entity,
							{ kind = "Heal", target = entity.model, amount = healed, tick = "Regen" }
						)
					end
				else
					applyDamage(entity, perTick, status.source or entity, false, false, { tick = kind })
					if entity.defeated then
						break
					end
				end
			end
		end
		if entity.defeated then
			continue
		end
		-- Expire statuses. A player who was stunned or frozen can't be again
		-- for a moment (no chain-stunning, D-45).
		local expired = false
		for kind, status in entity.statuses do
			if t >= status.untilAt then
				entity.statuses[kind] = nil
				expired = true
				if (kind == "Stun" or kind == "Freeze") and entity.kind == "Player" then
					entity.ccImmuneUntil = t + ConfigurationService:Get("Skills").ControlImmunitySeconds
				end
			end
		end
		if expired then
			mirrorStatuses(entity)
			CombatService.StatusChanged:Fire(entity)
		end
		local before = entity.hp
		if entity.kind == "Npc" then
			if entity.regen and t - entity.lastHostileAt > NPC_RESET_SECONDS then
				entity.hp = entity.maxHp
			end
		elseif inSafeZone(entity) then
			entity.hp += entity.maxHp * config.SafeZoneRegenPctPerSecond / 100 * dt
		elseif t - entity.lastHostileAt >= config.RegenDelaySeconds then
			updateResting(entity, t, config)
			local pct = entity.regenPct + (if entity.resting then config.RestRegenPctPerSecond else 0)
			entity.hp += CombatMath.regen(entity.maxHp, pct, dt)
		end
		if entity.resting and (t - entity.lastHostileAt < config.RegenDelaySeconds or inSafeZone(entity)) then
			-- Fighting again (or the safe zone's own regen took over).
			entity.resting = false
			entity.model:SetAttribute("Resting", nil)
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
		local stats = StatsService:GetStats(player)
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
				CombatService.CombatLogged:Fire(entity, entity.lastAttacker)
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
	-- Multipliers on the level's base Attack / Defense (default 1).
	attackScale: number?,
	defenseScale: number?,
	-- Default true (training dummies). Mobs pass false: MobService owns them.
	autoRevive: boolean?,
	regen: boolean?,
}

--[[
	Registers a server-owned NPC (training dummies, mobs, bosses).
	The model must have a Humanoid and a HumanoidRootPart.
]]
function CombatService:RegisterNpc(model: Model, spec: NpcSpec): boolean
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or root == nil or not root:IsA("BasePart") then
		return false
	end
	local entity = newEntity("Npc", model, humanoid, root, spec.name)
	applyStats(entity, StatFormulas.forCreatureLevel(spec.level), spec.level, false)
	entity.maxHp = spec.maxHp
	entity.hp = spec.maxHp
	entity.attack *= spec.attackScale or 1
	entity.defense *= spec.defenseScale or 1
	entity.autoRevive = spec.autoRevive ~= false
	entity.regen = spec.regen ~= false
	entitiesByModel[model] = entity
	humanoid.BreakJointsOnDeath = false
	mirror(entity)
	model:SetAttribute("Level", spec.level) -- target frame (display)
	CollectionService:AddTag(model, COMBATANT_TAG)
	return true
end

-- Forgets an NPC (despawned mob). Its model is the caller's to destroy.
function CombatService:UnregisterNpc(model: Model)
	local entity = entitiesByModel[model]
	if entity and entity.kind == "Npc" then
		entitiesByModel[model] = nil
	end
end

-- Full HP and no credit (a mob that leashed home, a boss reset after a wipe).
function CombatService:RestoreNpc(model: Model)
	local entity = entitiesByModel[model]
	if entity == nil or entity.kind ~= "Npc" or entity.defeated then
		return
	end
	entity.hp = entity.maxHp
	entity.contributors = {}
	entity.lastAttacker = nil
	mirror(entity)
end

-- Players who damaged this entity, with the damage each dealt.
function CombatService:GetContributors(model: Model): { [Player]: number }
	local entity = entitiesByModel[model]
	return if entity then table.clone(entity.contributors) else {}
end

-- Whether `attacker` may harm `target` right now (safe zones, protection, races).
function CombatService:CanHarm(attackerModel: Model, targetModel: Model): boolean
	local attacker = entitiesByModel[attackerModel]
	local target = entitiesByModel[targetModel]
	if attacker == nil or target == nil then
		return false
	end
	return (CombatMath.canHarm(harmFacts(attacker, target)))
end

--[[
	An NPC's attack lands on `targetModel` (server-internal; MobService /
	DungeonService). Re-validates harm rules and, if `range` is given, reach.
	Returns true if damage was dealt.
]]
function CombatService:NpcStrike(
	attackerModel: Model,
	targetModel: Model,
	coefficient: number,
	range: number?,
	heavy: boolean?
): boolean
	local attacker = entitiesByModel[attackerModel]
	local target = entitiesByModel[targetModel]
	if attacker == nil or target == nil or attacker.kind ~= "Npc" or isStunned(attacker) then
		return false
	end
	if not CombatMath.canHarm(harmFacts(attacker, target)) then
		return false
	end
	local config = combatConfig()
	if range then
		local distance = (target.root.Position - attacker.root.Position).Magnitude
		if distance > range + config.RangeToleranceStuds then
			return false
		end
	end
	local amount, crit = CombatMath.damage({
		attack = attackOf(attacker, attacker.attack),
		attackerLevel = attacker.level,
		coefficient = coefficient,
		critChancePct = attacker.critChancePct,
		critMultiplier = attacker.critMultiplier,
		roll = rng:NextNumber(),
		defense = defenseOf(target),
	}, config)
	applyDamage(target, amount, attacker, crit, heavy)
	return true
end

-- Sends a combat feedback event to players near `model` (display only).
function CombatService:Broadcast(model: Model, payload: { [string]: any })
	local entity = entitiesByModel[model]
	if entity then
		broadcast(entity, payload)
	end
end

-- Alive player entities (mob targeting).
function CombatService:LivePlayers(): { Entity }
	local out = {}
	for _, entity in entityByPlayer do
		if not entity.defeated and entity.root.Parent then
			table.insert(out, entity)
		end
	end
	return out
end

-- HP fraction 0..1 of any entity (1 if unknown).
function CombatService:HpFraction(model: Model): number
	local entity = entitiesByModel[model]
	if entity == nil or entity.maxHp <= 0 then
		return 1
	end
	return entity.hp / entity.maxHp
end

-- Current Focus of a player's combat entity (0 if none).
function CombatService:GetFocus(player: Player): number
	local entity = entityByPlayer[player]
	return if entity then entity.focus else 0
end

--[[
	Spends Focus. Returns false (and spends nothing) if the player has less
	than `amount` or is defeated.
]]
function CombatService:SpendFocus(player: Player, amount: number): boolean
	local entity = entityByPlayer[player]
	if entity == nil or entity.defeated or entity.focus < amount then
		return false
	end
	entity.focus -= amount
	return true
end

-- A skill's Focus cost for this player after gear Focus Efficiency (D-64).
function CombatService:FocusCost(player: Player, base: number): number
	local entity = entityByPlayer[player]
	local efficiency = if entity then entity.focusEfficiencyPct else 0
	return base * (1 - efficiency / 100)
end

--[[
	Re-reads a player's stats (gear changed, D-64), keeping their health
	fraction so equipping never heals or hurts.
]]
function CombatService:RefreshStats(player: Player)
	local entity = entityByPlayer[player]
	local stats = StatsService:GetStats(player)
	if entity and stats and not entity.defeated then
		applyStats(entity, stats, entity.level, true)
		mirror(entity)
	end
end

-- Heals a player by `pct` of their max HP (a potion). Returns HP restored.
function CombatService:RestoreHpPct(player: Player, pct: number): number
	local entity = entityByPlayer[player]
	if entity == nil or entity.defeated then
		return 0
	end
	local before = entity.hp
	entity.hp = math.min(entity.maxHp, entity.hp + entity.maxHp * pct / 100)
	mirror(entity)
	local healed = math.floor(entity.hp - before + 0.5)
	if healed > 0 then
		broadcast(entity, { kind = "Heal", target = entity.model, amount = healed, crit = false })
	end
	return healed
end

-- Whether the player is combat-tagged (hostile action within Combat.TagSeconds).
function CombatService:IsInCombat(player: Player): boolean
	local entity = entityByPlayer[player]
	return entity ~= nil and inCombat(entity)
end

function CombatService:IsDefeated(player: Player): boolean
	local entity = entityByPlayer[player]
	return entity == nil or entity.defeated
end

-- Seconds since `entity`'s spawn protection ended (negative while still
-- protected). Attacking ends protection at once, so it reads long ago then.
function CombatService:ProtectionEndedAgo(entity: Entity): number
	return now() - entity.protectedUntil
end

function CombatService:GetEntity(model: Model): Entity?
	return entitiesByModel[model]
end

function CombatService:GetPlayerEntity(player: Player): Entity?
	return entityByPlayer[player]
end

--------------------------------------------------------------------------------
-- Skill primitives (SkillService, Phase 5). Server-internal: every caller
-- has already validated the cast; these re-check what may have changed
-- while the spell was in the air.
--------------------------------------------------------------------------------

function CombatService:IsStunned(entity: Entity): boolean
	return isStunned(entity)
end

function CombatService:IsSilenced(entity: Entity): boolean
	return isSilenced(entity)
end

function CombatService:HasStatus(entity: Entity, kind: string): boolean
	return statusOf(entity, kind) ~= nil
end

-- Removes one status (a combo that consumes it).
function CombatService:ConsumeStatus(entity: Entity, kind: string)
	if entity.statuses[kind] then
		entity.statuses[kind] = nil
		mirrorStatuses(entity)
		CombatService.StatusChanged:Fire(entity)
	end
end

function CombatService:InSafeZone(entity: Entity): boolean
	return inSafeZone(entity)
end

function CombatService:IsEntityInCombat(entity: Entity): boolean
	return inCombat(entity)
end

-- Whether `attacker` may harm `target` right now, with the reason if not.
function CombatService:HarmCheck(attacker: Entity, target: Entity): (boolean, string?)
	return CombatMath.canHarm(harmFacts(attacker, target))
end

-- Whether `helper` may heal / shield / buff / cleanse `target` (SkillRules.canHelp).
function CombatService:HelpCheck(helper: Entity, target: Entity): (boolean, string?)
	return SkillRules.canHelp({
		helperIsPlayer = helper.kind == "Player",
		targetIsPlayer = target.kind == "Player",
		helperRace = helper.race,
		targetRace = target.race,
		helperDefeated = helper.defeated,
		targetDefeated = target.defeated,
		helperInSafeZone = inSafeZone(helper),
		targetInSafeZone = inSafeZone(target),
		targetInCombat = inCombat(target),
	})
end

-- Nearest hostile in front of `attacker` within `range` (casts without a target).
function CombatService:AutoTarget(attacker: Entity, range: number): Entity?
	return autoTarget(attacker, range)
end

function CombatService:HasLineOfSight(from: Vector3, to: Vector3): boolean
	return hasLineOfSight(from, to)
end

-- Living entities within `radius` of `center` (area skills), nearest first.
function CombatService:EntitiesNear(center: Vector3, radius: number): { Entity }
	local out = {}
	for _, entity in entitiesByModel do
		if not entity.defeated and (entity.root.Position - center).Magnitude <= radius then
			table.insert(out, entity)
		end
	end
	table.sort(out, function(a, b)
		return (a.root.Position - center).Magnitude < (b.root.Position - center).Magnitude
	end)
	return out
end

-- One skill hit (re-validates harm). Returns true if damage was dealt.
function CombatService:Strike(
	attacker: Entity,
	target: Entity,
	coefficient: number,
	critBonusPct: number?,
	heavy: boolean?,
	extra: HitExtra?
): boolean
	if entitiesByModel[attacker.model] ~= attacker or entitiesByModel[target.model] ~= target then
		return false
	end
	if not CombatMath.canHarm(harmFacts(attacker, target)) then
		return false
	end
	-- Gear Skill Power (D-64) strengthens skills, not basic attacks.
	strike(
		attacker,
		target,
		coefficient * (1 + attacker.skillPowerPct / 100),
		critBonusPct or 0,
		heavy,
		extra
	)
	return true
end

-- Heals `target` by coefficient x the healer's Attack (re-validates help rules).
function CombatService:HealTarget(
	healer: Entity,
	target: Entity,
	coefficient: number,
	skill: string?
): boolean
	if entitiesByModel[healer.model] ~= healer or entitiesByModel[target.model] ~= target then
		return false
	end
	if not (CombatService:HelpCheck(healer, target)) then
		return false
	end
	local amount, crit = healAmount(healer, coefficient, true)
	local before = target.hp
	target.hp = math.min(target.maxHp, target.hp + amount)
	-- Supporting someone who is fighting pulls you into that fight.
	if inCombat(target) then
		healer.lastHostileAt = math.max(healer.lastHostileAt, target.lastHostileAt)
	end
	mirror(target)
	local healed = math.floor(target.hp - before + 0.5)
	if healed > 0 then
		broadcast(
			target,
			{ kind = "Heal", target = target.model, amount = healed, crit = crit, skill = skill }
		)
	end
	return true
end

-- Shield points worth coefficient x the caster's Attack (no crit).
function CombatService:ShieldAmount(caster: Entity, coefficient: number): number
	return (healAmount(caster, coefficient, false))
end

-- Healing per Regen tick worth coefficient x the caster's Attack (no crit).
function CombatService:RegenAmount(caster: Entity, coefficient: number): number
	return (healAmount(caster, coefficient, false))
end

-- Damage per Poison / Burn tick from `attacker` to `target` (no crit).
function CombatService:TickDamage(attacker: Entity, target: Entity, coefficient: number): number
	return tickDamage(attacker, target, coefficient * (1 + attacker.skillPowerPct / 100))
end

--[[
	Puts status `kind` on `target` for `seconds` (refreshes; keeps the
	stronger value). Crowd control goes through SkillRules.controlSeconds
	(boss immunity, PvP scale) and a player's short immunity after a stun /
	freeze. `perTick` is the damage / healing per second for Poison, Burn
	and Regen. Returns the seconds applied (0 = no effect).
]]
function CombatService:ApplyStatus(
	target: Entity,
	kind: StatusKind,
	seconds: number,
	value: number?,
	source: Entity?,
	perTick: number?
): number
	if target.defeated or entitiesByModel[target.model] ~= target or seconds <= 0 then
		return 0
	end
	local targetIsPlayer = target.player ~= nil
	local t = now()
	local isTaunt = kind == "Taunt"
	local stunLike = kind == "Stun" or kind == "Freeze"
	if isTaunt or (SkillRules.CONTROL :: any)[kind] then
		if isTaunt and targetIsPlayer then
			return 0
		end
		if stunLike and targetIsPlayer and t < target.ccImmuneUntil then
			return 0
		end
		local pvp = source ~= nil and source.player ~= nil and targetIsPlayer
		seconds = SkillRules.controlSeconds(
			kind,
			seconds,
			target.controlImmune,
			pvp,
			ConfigurationService:Get("Skills").PvPControlScale
		)
		if seconds <= 0 then
			return 0
		end
	end
	local untilAt = t + seconds
	local existing = statusOf(target, kind)
	if existing then
		existing.untilAt = math.max(existing.untilAt, untilAt)
		existing.value = math.max(existing.value, value or 0)
		if perTick then
			existing.perTick = math.max(existing.perTick or 0, perTick)
			existing.source = source
		end
		if kind == "Taunt" then
			existing.source = source
			existing.untilAt = untilAt
		end
	else
		target.statuses[kind] = {
			untilAt = untilAt,
			value = value or 0,
			source = source,
			perTick = perTick,
			nextTickAt = if perTick then t + TICK_SECONDS_DOT else nil,
		}
	end
	mirrorStatuses(target)
	CombatService.StatusChanged:Fire(target)
	return seconds
end

-- Removes every hindrance (SkillRules.CLEANSED).
function CombatService:Cleanse(target: Entity)
	local changed = false
	for _, kind in SkillRules.CLEANSED do
		if target.statuses[kind] then
			target.statuses[kind] = nil
			changed = true
		end
	end
	if changed then
		mirrorStatuses(target)
		CombatService.StatusChanged:Fire(target)
	end
end

export type Control = { stunned: boolean, rooted: boolean, speedScale: number, taunter: Model? }

-- Movement effects on an entity (MobService, MovementService).
function CombatService:ControlOf(entity: Entity): Control
	local stunned = isStunned(entity)
	local rooted = statusOf(entity, "Root") ~= nil
	local taunt = statusOf(entity, "Taunt")
	local taunter = taunt and taunt.source
	local scale = (1 + statusValue(entity, "Haste") / 100) * (1 - statusValue(entity, "Slow") / 100)
	return {
		stunned = stunned,
		rooted = rooted,
		speedScale = if stunned or rooted then 0 else math.clamp(scale, 0.1, 2),
		taunter = if taunter
				and not taunter.defeated
				and entitiesByModel[taunter.model] == taunter
			then taunter.model
			else nil,
	}
end

function CombatService:ControlOfModel(model: Model): Control?
	local entity = entitiesByModel[model]
	return if entity then CombatService:ControlOf(entity) else nil
end

-- Bosses: immune to crowd control.
function CombatService:SetControlImmune(model: Model, immune: boolean)
	local entity = entitiesByModel[model]
	if entity then
		entity.controlImmune = immune
	end
end

-- Multiplies an NPC's outgoing damage (1 = normal; an enraged boss).
function CombatService:SetOutgoingScale(model: Model, scale: number)
	local entity = entitiesByModel[model]
	if entity and entity.kind == "Npc" then
		entity.outgoingScale = math.max(scale, 0)
		model:SetAttribute("Enraged", if scale > 1 then true else nil)
	end
end

-- After a skill cast: no basic attacks until the cast animation is done,
-- spawn protection ends for hostile skills, the combo chain restarts.
function CombatService:CastStarted(entity: Entity, lockSeconds: number, hostile: boolean)
	entity.attackLockUntil = now() + lockSeconds
	entity.combo = ComboMath.new()
	if hostile then
		entity.protectedUntil = 0
	end
end

return CombatService
