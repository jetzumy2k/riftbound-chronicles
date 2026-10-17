--!strict
--[[
	SkillService (Layer 4) — server-authoritative skill trees and skills
	(Phase 5, CLAUDE.md §6-7, PLAN.md D-45, SECURITY_MODEL T-02/T-03/T-04).

	  - Skill tree: every character earns 1 skill point at level 0 plus 1 per
	    level. `LearnSkill(id)` spends one point to learn a skill or raise its
	    rank (Logic/SkillRules.canLearn: own job, level for the tier, the
	    skill above it learned, a free point, below max rank).
	    `ResetSkills()` refunds every point, only in a safe zone and out of
	    combat. Studio play-tests may learn at any level and get bonus
	    points (`Skills.StudioUnlockAll` / `StudioBonusPoints`, never live).
	  - Skill bar: `SetLoadout(regular[≤3], special?)` replaces the 3 + 1 bar
	    after SkillRules.validateLoadout (learned, own job, slot type, no
	    duplicates). Newly learned skills fill empty slots; the player's own
	    choices never move.
	  - Casting: `SkillCast(id, target?)` is an intent. The server re-checks
	    the bar (equipped, learned, job), stun / freeze / silence, its own
	    cooldown clock and a global cooldown, and Focus, then resolves the
	    target itself (hostility / ally rules, range with bounded lag
	    compensation, line of sight) before spending Focus. Every number comes
	    from SkillDefinitions at the skill's rank; effects land at the clip's
	    Hit frame plus projectile travel and re-check harm / help rules then.
	  - Combos: a skill whose combo condition holds on the target (e.g. a
	    frozen enemy hit by Frost Bolt) deals bonus damage and may consume
	    the status; the hit is broadcast with the combo name.
	  - The caster always gets `SkillCooldown(skill, readyIn)` back, so a
	    rejected cast clears the client's predicted cooldown sweep.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local CombatMath = require(Shared.Logic.CombatMath)
local SkillDefinitions = require(Shared.Definitions.SkillDefinitions)
local SkillRules = require(Shared.Logic.SkillRules)
local Log = require(Shared.Util.Log)

local AuditLogService = require(script.Parent.AuditLogService)
local ConfigurationService = require(script.Parent.ConfigurationService)
local NetService = require(script.Parent.NetService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local LevelService = require(script.Parent.LevelService)
local JobService = require(script.Parent.JobService)
local AntiExploitService = require(script.Parent.AntiExploitService)
local CombatService = require(script.Parent.CombatService)

type Entity = CombatService.Entity
type Skill = SkillDefinitions.Skill
type Effect = SkillDefinitions.Effect

-- Extra reach a melee skill keeps between the cast and its Hit frame.
local MELEE_FOLLOW_STUDS = 6
-- "Why didn't my skill work?" toasts: at most this often per reason.
local NOTICE_SECONDS = 2
-- Area skills without a target land this far ahead of the caster (at most).
local AREA_AHEAD_STUDS = 20

local log = Log.new("SkillService")

local SkillService = {}

local cooldowns: { [Player]: { [string]: number } } = {}
local globalReady: { [Player]: number } = {}
local lastNotice: { [Player]: { [string]: number } } = {}

-- Player-facing reasons an action did nothing (client maps keys to text).
local REASON_KEYS: { [string]: string } = {
	cooldown = "skill.cooldown",
	busy = "skill.cooldown",
	noFocus = "skill.noFocus",
	stunned = "skill.stunned",
	silenced = "skill.silenced",
	notEquipped = "skill.notEquipped",
	notLearned = "skill.notLearned",
	notAlly = "skill.notAlly",
	noTarget = "combat.blocked.noTarget",
	outOfRange = "combat.blocked.outOfRange",
	lineOfSight = "combat.blocked.lineOfSight",
	safeZone = "combat.blocked.safeZone",
	protected = "combat.blocked.protected",
	sameRace = "combat.blocked.sameRace",
	-- Learning
	locked = "skill.learn.locked",
	requires = "skill.learn.requires",
	noPoints = "skill.learn.noPoints",
	maxRank = "skill.learn.maxRank",
	rankLocked = "skill.learn.rankLocked",
}

local function skillsConfig(): any
	return ConfigurationService:Get("Skills")
end

local function isStudio(): boolean
	return RunService:IsStudio()
end

local function unlockAll(): boolean
	return isStudio() and skillsConfig().StudioUnlockAll == true
end

local function bonusPoints(): number
	return if isStudio() then skillsConfig().StudioBonusPoints else 0
end

local function loadoutOf(data: { [string]: any }): SkillRules.Loadout
	local equipped = data.EquippedSkills
	return { Regular = equipped.Regular, Special = equipped.Special }
end

local function notify(player: Player, reason: string?, params: { [string]: string }?)
	local key = reason and REASON_KEYS[reason]
	if key == nil then
		return
	end
	local seen = lastNotice[player] or {}
	lastNotice[player] = seen
	local t = os.clock()
	if t - (seen[key] or -math.huge) < NOTICE_SECONDS then
		return
	end
	seen[key] = t
	NetService:FireClient("Notify", player, { kind = "Warning", textKey = key, params = params })
end

local function sendCooldown(player: Player, id: string)
	local readyAt = cooldowns[player] and cooldowns[player][id]
	NetService:FireClient("SkillCooldown", player, {
		skill = id,
		readyIn = math.clamp((readyAt or 0) - os.clock(), 0, 600),
	})
end

--------------------------------------------------------------------------------
-- Skill tree and bar
--------------------------------------------------------------------------------

-- Saves the bar if it changed. Returns true if it did.
local function setLoadout(data: { [string]: any }, loadout: SkillRules.Loadout): boolean
	local current = loadoutOf(data)
	if
		loadout.Special == current.Special
		and table.concat(loadout.Regular, ",") == table.concat(current.Regular, ",")
	then
		return false
	end
	data.EquippedSkills = { Regular = table.clone(loadout.Regular), Special = loadout.Special }
	return true
end

-- On load: skills / ranks the level doesn't open are dropped, a tree that
-- spent more points than the level allows (config change, tampered save) is
-- refunded; the bar is pruned and filled.
local function repair(player: Player)
	local data = PlayerDataService:GetData(player)
	if data == nil or data.Job == nil then
		return
	end
	local fitted, trimmed = SkillRules.fitToLevel(data.OwnedSkills, data.Level, unlockAll())
	if trimmed then
		log:Info("user=%d skills trimmed to level %d", player.UserId, data.Level)
		data.OwnedSkills = fitted
	end
	if SkillRules.available(data.OwnedSkills, data.Level, bonusPoints()) < 0 then
		AuditLogService:Security(player, "SkillPointsOverspent", `spent {SkillRules.spent(data.OwnedSkills)}`)
		data.OwnedSkills = {}
	end
	local pruned = SkillRules.prune(data.Job, data.OwnedSkills, loadoutOf(data))
	local changed = setLoadout(data, SkillRules.autoFill(data.Job, data.OwnedSkills, pruned))
	if changed then
		PlayerDataService:PushSnapshot(player)
	end
end

local function onLearn(player: Player, id: string)
	local data = PlayerDataService:GetData(player)
	if data == nil then
		return
	end
	local ok, reason =
		SkillRules.canLearn(data.Job, data.OwnedSkills, data.Level, bonusPoints(), unlockAll(), id)
	local skill = SkillDefinitions.get(id)
	if not ok or skill == nil then
		if reason == "wrongJob" or reason == "noJob" then
			AuditLogService:Security(player, "LearnNotAllowed", `{id}: {tostring(reason)}`)
		end
		notify(
			player,
			reason,
			if skill and reason == "locked"
				then { level = tostring(skill.unlockLevel) }
				elseif skill and reason == "rankLocked" then {
					rank = tostring(SkillRules.rankOf(data.OwnedSkills, skill.id) + 1),
					level = tostring(SkillRules.rankLevel(SkillRules.rankOf(data.OwnedSkills, skill.id) + 1)),
				}
				elseif skill and reason == "requires" then {
					name = (SkillDefinitions.get(skill.requires) :: Skill).name,
				}
				else nil
		)
		PlayerDataService:PushSnapshot(player) -- resync the tree view
		return
	end
	-- Synchronous commit: one point, one rank.
	local rank = SkillRules.rankOf(data.OwnedSkills, id) + 1
	data.OwnedSkills[id] = rank
	if rank == 1 then
		setLoadout(data, SkillRules.autoFill(data.Job, data.OwnedSkills, loadoutOf(data)))
	end
	log:Info("user=%d learned %s rank %d", player.UserId, id, rank)
	NetService:FireClient("Notify", player, {
		kind = "Info",
		textKey = if rank == 1 then "skill.learn.learned" else "skill.learn.ranked",
		params = { name = skill.name, rank = tostring(rank) },
	})
	PlayerDataService:PushSnapshot(player)
end

local function onReset(player: Player)
	local data = PlayerDataService:GetData(player)
	local entity = CombatService:GetPlayerEntity(player)
	if data == nil then
		return
	end
	if skillsConfig().ResetNeedsSafeZone then
		if
			entity == nil
			or not CombatService:InSafeZone(entity)
			or CombatService:IsEntityInCombat(entity)
		then
			NetService:FireClient("Notify", player, { kind = "Warning", textKey = "skill.reset.safeZone" })
			return
		end
	end
	data.OwnedSkills = {}
	data.EquippedSkills = { Regular = {} }
	log:Info("user=%d reset the skill tree", player.UserId)
	NetService:FireClient("Notify", player, { kind = "Info", textKey = "skill.reset.done" })
	PlayerDataService:PushSnapshot(player)
end

local function onSetLoadout(player: Player, regular: { string }, special: string?)
	local data = PlayerDataService:GetData(player)
	if data == nil then
		return
	end
	local ok, reason = SkillRules.validateLoadout(data.Job, data.OwnedSkills, regular, special)
	if not ok then
		-- The UI only offers learned skills in matching slots; a forged request.
		AuditLogService:Security(player, "InvalidLoadout", `{tostring(reason)}`)
		NetService:FireClient("Notify", player, { kind = "Warning", textKey = "skill.loadoutInvalid" })
		PlayerDataService:PushSnapshot(player)
		return
	end
	setLoadout(data, { Regular = regular, Special = special })
	PlayerDataService:PushSnapshot(player)
end

--------------------------------------------------------------------------------
-- Targeting
--------------------------------------------------------------------------------

type Resolved = {
	target: Entity?,
	center: Vector3?,
	travel: number,
}

-- Range check with bounded lag compensation; logs impossible distances.
local function inRange(player: Player, caster: Entity, target: Entity, skill: Skill): (boolean, number)
	local combat = ConfigurationService:Get("Combat")
	local distance = (target.root.Position - caster.root.Position).Magnitude
	local speed = target.root.AssemblyLinearVelocity.Magnitude
	if CombatMath.withinRange(distance, skill.range, player:GetNetworkPing(), speed, combat) then
		return true, distance
	end
	if distance > skill.range * 2 + combat.RangeToleranceStuds + 10 then
		AuditLogService:Security(player, "SkillOutOfRange", `{skill.id} at {math.floor(distance)} studs`)
	end
	return false, distance
end

local function clearSight(caster: Entity, target: Entity): boolean
	local head = caster.model:FindFirstChild("Head")
	local from = if head and head:IsA("BasePart") then head.Position else caster.root.Position
	return CombatService:HasLineOfSight(from, target.root.Position)
end

-- A hostile target the skill may hit, or nil (the player is told why).
local function resolveEnemy(
	player: Player,
	caster: Entity,
	skill: Skill,
	hint: Model?,
	quiet: boolean
): (Entity?, number)
	local target = if hint
		then CombatService:GetEntity(hint)
		else CombatService:AutoTarget(caster, skill.range)
	if target == nil then
		if not quiet then
			notify(player, if CombatService:InSafeZone(caster) then "safeZone" else "noTarget")
		end
		return nil, 0
	end
	local allowed, reason = CombatService:HarmCheck(caster, target)
	if not allowed then
		if not quiet then
			notify(player, reason)
		end
		return nil, 0
	end
	local ok, distance = inRange(player, caster, target, skill)
	if not ok then
		if not quiet then
			notify(player, "outOfRange")
		end
		return nil, 0
	end
	if not skill.melee and not clearSight(caster, target) then
		if not quiet then
			notify(player, "lineOfSight")
		end
		return nil, 0
	end
	return target, distance
end

local function resolve(player: Player, caster: Entity, skill: Skill, hint: Model?): Resolved?
	local target = skill.target
	if target == "Enemy" then
		local enemy, distance = resolveEnemy(player, caster, skill, hint, false)
		if enemy == nil then
			return nil
		end
		local travel = if skill.projectileSpeed then distance / skill.projectileSpeed else 0
		return { target = enemy, travel = travel }
	elseif target == "Ally" then
		local ally = (if hint then CombatService:GetEntity(hint) else nil) or caster
		local allowed, reason = CombatService:HelpCheck(caster, ally)
		if not allowed then
			notify(player, if reason == "safeZone" then "safeZone" else "notAlly")
			return nil
		end
		if ally ~= caster then
			if not (inRange(player, caster, ally, skill)) then
				notify(player, "outOfRange")
				return nil
			end
			if not clearSight(caster, ally) then
				notify(player, "lineOfSight")
				return nil
			end
		end
		return { target = ally, travel = 0 }
	elseif target == "Self" or target == "Dash" then
		return { target = caster, travel = 0 }
	elseif target == "SelfArea" then
		return { center = caster.root.Position, travel = 0 }
	elseif target == "EnemyArea" then
		-- On the target if there is a valid one in range, else ahead of you.
		local enemy = resolveEnemy(player, caster, skill, hint, true)
		if enemy then
			return { target = enemy, center = enemy.root.Position, travel = 0 }
		end
		if CombatService:InSafeZone(caster) then
			notify(player, "safeZone")
			return nil
		end
		local ahead = math.min(skill.range * 0.5, AREA_AHEAD_STUDS)
		return { center = caster.root.Position + caster.root.CFrame.LookVector * ahead, travel = 0 }
	end
	return nil
end

--------------------------------------------------------------------------------
-- Effects
--------------------------------------------------------------------------------

local function isAlive(entity: Entity): boolean
	return not entity.defeated and CombatService:GetEntity(entity.model) == entity
end

-- One non-damage effect (already scaled to the rank) on one target.
local function applyEffect(caster: Entity, target: Entity, e: Effect, skillId: string)
	local kind = e.kind
	if kind == "Heal" then
		CombatService:HealTarget(caster, target, e.coefficient or 1, skillId)
	elseif kind == "Shield" then
		CombatService:ApplyStatus(
			target,
			"Shield",
			e.seconds or 5,
			CombatService:ShieldAmount(caster, e.coefficient or 1),
			caster
		)
	elseif kind == "Poison" or kind == "Burn" then
		local perTick = CombatService:TickDamage(caster, target, e.coefficient or 0.1)
		CombatService:ApplyStatus(target, kind, e.seconds or 4, 0, caster, perTick)
	elseif kind == "Regen" then
		local perTick = CombatService:RegenAmount(caster, e.coefficient or 0.1)
		CombatService:ApplyStatus(target, "Regen", e.seconds or 5, 0, caster, perTick)
	elseif
		kind == "Guard"
		or kind == "Harden"
		or kind == "Empower"
		or kind == "Haste"
		or kind == "Slow"
		or kind == "Mark"
		or kind == "Weaken"
	then
		CombatService:ApplyStatus(target, kind, e.seconds or 3, e.pct or 0, caster)
	elseif kind == "Stun" or kind == "Freeze" or kind == "Root" or kind == "Silence" or kind == "Taunt" then
		CombatService:ApplyStatus(target, kind, e.seconds or 1, nil, caster)
	elseif kind == "Cleanse" then
		CombatService:Cleanse(target)
	end
end

-- The skill's target effects on one target at `rank`. A hostile skill whose
-- hit doesn't land (target became protected / safe) applies nothing else.
local function applyEffects(caster: Entity, target: Entity, skill: Skill, rank: number)
	local combo = skill.combo
	local comboOn = combo ~= nil
		and SkillDefinitions.isHostile(skill)
		and SkillRules.comboApplies(combo, function(kind)
			return CombatService:HasStatus(target, kind)
		end, CombatService:HpFraction(target.model))
	for _, raw in skill.effects do
		if raw.self then
			continue
		end
		local e = SkillRules.effectAtRank(raw, rank)
		if e.kind == "Damage" then
			local coefficient = (e.coefficient or 1)
				* (if comboOn and combo then 1 + combo.bonusPct / 100 else 1)
			local dealt =
				CombatService:Strike(caster, target, coefficient, e.critBonusPct, e.heavy or comboOn, {
					skill = skill.id,
					combo = if comboOn and combo then combo.name else nil,
				})
			if not dealt then
				return
			end
			if comboOn and combo and combo.consume and combo.status then
				CombatService:ConsumeStatus(target, combo.status)
			end
		else
			applyEffect(caster, target, e, skill.id)
		end
	end
end

-- Effects marked `self` land on the caster once per cast.
local function applySelf(caster: Entity, skill: Skill, rank: number)
	for _, raw in skill.effects do
		if raw.self and isAlive(caster) then
			applyEffect(caster, caster, SkillRules.effectAtRank(raw, rank), skill.id)
		end
	end
end

-- Whether the skill affects `target` (hostile skills: enemies; support: allies).
local function affects(caster: Entity, target: Entity, hostile: boolean): boolean
	if hostile then
		return target ~= caster and (CombatService:HarmCheck(caster, target))
	end
	return (CombatService:HelpCheck(caster, target))
end

local function landSingle(caster: Entity, target: Entity, skill: Skill, rank: number)
	if not isAlive(caster) or not isAlive(target) then
		return
	end
	if skill.melee then
		local combat = ConfigurationService:Get("Combat")
		local distance = (target.root.Position - caster.root.Position).Magnitude
		if distance > skill.range + combat.RangeToleranceStuds + MELEE_FOLLOW_STUDS then
			return -- the target stepped out of reach
		end
	end
	if target ~= caster and not affects(caster, target, SkillDefinitions.isHostile(skill)) then
		return
	end
	applyEffects(caster, target, skill, rank)
end

local function landArea(caster: Entity, skill: Skill, rank: number, fixedCenter: Vector3?)
	if not isAlive(caster) then
		return
	end
	-- Self-centred areas follow the caster; targeted ones stay where they fell.
	local center = fixedCenter or caster.root.Position
	local hostile = SkillDefinitions.isHostile(skill)
	local limit = math.min(skill.maxTargets or 8, skillsConfig().MaxAreaTargets)
	local count = 0
	for _, entity in CombatService:EntitiesNear(center, skill.radius or 8) do
		if count >= limit then
			break
		end
		if affects(caster, entity, hostile) then
			applyEffects(caster, entity, skill, rank)
			count += 1
		end
	end
end

--------------------------------------------------------------------------------
-- Casting
--------------------------------------------------------------------------------

local function onCast(player: Player, id: string, hint: Model?)
	local caster = CombatService:GetPlayerEntity(player)
	local data = PlayerDataService:GetData(player)
	local skill = SkillDefinitions.get(id)
	if caster == nil or caster.defeated or data == nil or skill == nil then
		return
	end
	local t = os.clock()
	local config = skillsConfig()
	local playerCooldowns = cooldowns[player] or {}
	cooldowns[player] = playerCooldowns

	local ok, reason = SkillRules.canCast(id, {
		job = data.Job,
		owned = data.OwnedSkills,
		loadout = loadoutOf(data),
		now = t,
		readyAt = playerCooldowns[id],
		globalReadyAt = globalReady[player] or -math.huge,
		focus = caster.focus,
		stunned = CombatService:IsStunned(caster),
		silenced = CombatService:IsSilenced(caster),
		slack = config.CooldownSlackSeconds,
	})
	if not ok then
		if reason == "notLearned" or reason == "notEquipped" then
			-- The skill bar only offers equipped skills; a forged request.
			AuditLogService:Security(player, "SkillNotAllowed", `{id}: {tostring(reason)}`)
		end
		notify(player, reason)
		sendCooldown(player, id)
		return
	end

	local resolved = resolve(player, caster, skill, hint)
	if resolved == nil or not CombatService:SpendFocus(player, skill.focusCost) then
		sendCooldown(player, id)
		return
	end

	-- Committed.
	local rank = SkillRules.rankOf(data.OwnedSkills, id)
	playerCooldowns[id] = t + skill.cooldown
	globalReady[player] = t + config.GlobalCooldownSeconds
	CombatService:CastStarted(caster, SkillDefinitions.recovery(skill), SkillDefinitions.isHostile(skill))
	sendCooldown(player, id)

	local dash = SkillDefinitions.effect(skill, "Dash")
	if dash then
		-- The client moves itself; the movement validator allows the burst.
		local seconds = dash.seconds or 0.25
		AntiExploitService:GrantSpeedAllowance(player, (dash.studs or 10) / seconds, seconds + 0.5)
	end

	local aim = resolved.target
	CombatService:Broadcast(caster.model, {
		kind = "Skill",
		target = caster.model,
		skill = id,
		aim = if aim and aim ~= caster then aim.model else nil,
		point = if skill.target == "EnemyArea" then resolved.center else nil,
	})
	log:Debug("%s cast %s (rank %d)", player.Name, id, rank)

	local landAt = SkillDefinitions.hitTime(skill) + resolved.travel
	local waves = skill.waves or 1
	local gap = skill.waveGap or 0
	if dash then
		applySelf(caster, skill, rank)
	else
		task.delay(landAt, applySelf, caster, skill, rank)
	end
	if skill.target == "SelfArea" or skill.target == "EnemyArea" then
		local center = if skill.target == "EnemyArea" then resolved.center else nil
		for wave = 1, waves do
			task.delay(landAt + (wave - 1) * gap, landArea, caster, skill, rank, center)
		end
	elseif aim and not dash then
		for wave = 1, waves do
			task.delay(landAt + (wave - 1) * gap, landSingle, caster, aim, skill, rank)
		end
	end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function SkillService:Init()
	NetService:Handle("SkillCast", onCast)
	NetService:Handle("SetLoadout", onSetLoadout)
	NetService:Handle("LearnSkill", onLearn)
	NetService:Handle("ResetSkills", onReset)
	PlayerDataService.ProfileLoaded:Connect(function(player)
		repair(player)
	end)
	JobService.JobChosen:Connect(function(player)
		NetService:FireClient("Notify", player, { kind = "Info", textKey = "skill.learn.firstPoint" })
	end)
	LevelService.LevelChanged:Connect(function(player, level, oldLevel)
		if level <= oldLevel then
			return
		end
		local data = PlayerDataService:GetData(player)
		local opened = SkillRules.unlockedBetween(data and data.Job, oldLevel, level)
		local step = SkillRules.RANK_LEVEL_STEP
		local newCap = 1 + level // step
		local rankOpened = newCap > 1 + oldLevel // step and newCap <= SkillDefinitions.REGULAR_MAX_RANK
		if #opened > 0 then
			local names = {}
			for index = 1, math.min(#opened, 3) do
				table.insert(names, opened[index].name)
			end
			NetService:FireClient("Notify", player, {
				kind = "Info",
				textKey = "skill.learn.unlocked",
				params = { points = tostring(level - oldLevel), names = table.concat(names, ", ") },
			})
		else
			NetService:FireClient("Notify", player, {
				kind = "Info",
				textKey = "skill.learn.newPoints",
				params = { points = tostring(level - oldLevel) },
			})
		end
		if rankOpened then
			NetService:FireClient("Notify", player, {
				kind = "Info",
				textKey = "skill.learn.rankOpen",
				params = { rank = tostring(newCap) },
			})
		end
	end)
end

function SkillService:Start()
	-- Tells the skill tree about Studio test allowances (display only).
	local function publish(player: Player)
		player:SetAttribute("SkillsUnlockAll", if unlockAll() then true else nil)
		player:SetAttribute("SkillBonusPoints", if bonusPoints() > 0 then bonusPoints() else nil)
	end
	Players.PlayerAdded:Connect(publish)
	for _, player in Players:GetPlayers() do
		publish(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		cooldowns[player] = nil
		globalReady[player] = nil
		lastNotice[player] = nil
	end)
	log:Info(
		"%d skills in 16 branches ready%s",
		#SkillDefinitions.IDS,
		if unlockAll() then ` (Studio: any level, +{bonusPoints()} points)` else ""
	)
end

return SkillService
