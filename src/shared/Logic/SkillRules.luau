--!strict
--[[
	SkillRules — the skill tree and skill bar rules (Phase 5, PLAN.md D-45).
	The server decides with these; the client uses the same functions only
	to display and predict (tree state, tooltips, greyed-out buttons).

	Skills are stored per character as `owned[id] = rank` (1..maxRank).

	  pointsFor / spent / available   skill points: 1 at level 0 plus 1 per
	                                  level (+ a Studio-only test bonus)
	  rankCap         highest rank open at a level: rank 1 at level 0, one
	                  more every RANK_LEVEL_STEP levels (rank 5 at 24)
	  canLearn        learn a skill or raise its rank by one: own job, level
	                  for its tier and for the rank, the skill above it
	                  learned, a free point, below max rank
	  fitToLevel      drops skills / ranks the level doesn't open (repair)
	  validateLoadout a whole 3 + 1 skill bar: learned, own job, slot type,
	                  no duplicates (T-04)
	  canCast         equipped, learned, stun / freeze / silence, cooldown,
	                  global cooldown, Focus
	  autoFill        fills empty bar slots with learned skills
	  effectAtRank    a skill effect's numbers at a rank
	  comboApplies    does a skill's combo trigger on this target?
	  incoming        damage after Mark / Guard and the shield's absorb
	  canHelp         heal / shield / buff rules (D-24: same realm only)
	  controlSeconds  stun / freeze / root / slow / silence duration after
	                  boss immunity and the PvP scale
	  describe        player-facing lines for the skill info panel

	Pure module.
]]

local SkillDefinitions = require(script.Parent.Parent.Definitions.SkillDefinitions)
local JobDefinitions = require(script.Parent.Parent.Definitions.JobDefinitions)

type Skill = SkillDefinitions.Skill
type Effect = SkillDefinitions.Effect

export type Owned = { [string]: number }
export type Loadout = { Regular: { string }, Special: string? }

export type CastFacts = {
	job: string?,
	owned: Owned,
	loadout: Loadout,
	now: number,
	readyAt: number?, -- this skill's cooldown end (nil = never cast)
	globalReadyAt: number,
	focus: number,
	stunned: boolean, -- stunned or frozen
	silenced: boolean,
	-- Network jitter: casts this early still count.
	slack: number,
}

export type HelpFacts = {
	helperIsPlayer: boolean,
	targetIsPlayer: boolean,
	helperRace: string?,
	targetRace: string?,
	helperDefeated: boolean,
	targetDefeated: boolean,
	helperInSafeZone: boolean,
	targetInSafeZone: boolean,
	targetInCombat: boolean,
}

local SkillRules = {}

SkillRules.REGULAR_SLOTS = 3
-- A skill's rank can rise once per this many levels (rank 5 opens at 24).
SkillRules.RANK_LEVEL_STEP = 6
-- Per rank above 1: damage / heal / shield / over-time numbers.
SkillRules.COEFFICIENT_PER_RANK = 0.12
-- Per rank above 1: control durations and buff / debuff percentages.
SkillRules.DURATION_PER_RANK = 0.08
SkillRules.PCT_PER_RANK = 0.1
-- Hard caps (fairness): no long stuns, no near-immunity.
SkillRules.CAPS = table.freeze({
	Stun = 2,
	Freeze = 2.5,
	Root = 3.5,
	Silence = 3.5,
	Pct = 60,
})

-- Statuses whose duration counts as crowd control (PvP scale, boss immunity).
local CONTROL = { Stun = true, Freeze = true, Root = true, Slow = true, Silence = true }
SkillRules.CONTROL = table.freeze(CONTROL)
-- Statuses Cleanse removes.
SkillRules.CLEANSED =
	table.freeze({ "Stun", "Freeze", "Root", "Slow", "Silence", "Mark", "Weaken", "Poison", "Burn" })

--------------------------------------------------------------------------------
-- Points and learning
--------------------------------------------------------------------------------

function SkillRules.pointsFor(level: number, bonus: number?): number
	return 1 + math.max(0, math.floor(level)) + math.max(0, bonus or 0)
end

function SkillRules.spent(owned: Owned): number
	local total = 0
	for _, rank in owned do
		if type(rank) == "number" then
			total += rank
		end
	end
	return total
end

function SkillRules.available(owned: Owned, level: number, bonus: number?): number
	return SkillRules.pointsFor(level, bonus) - SkillRules.spent(owned)
end

function SkillRules.rankOf(owned: Owned, id: string): number
	local rank = owned[id]
	return if type(rank) == "number" then rank else 0
end

-- Level at which `rank` opens (for any skill).
function SkillRules.rankLevel(rank: number): number
	return math.max(0, rank - 1) * SkillRules.RANK_LEVEL_STEP
end

-- Highest rank of `skill` a character of `level` may reach.
function SkillRules.rankCap(skill: Skill, level: number, unlockAll: boolean?): number
	if unlockAll then
		return skill.maxRank
	end
	return math.clamp(1 + math.floor(math.max(level, 0) / SkillRules.RANK_LEVEL_STEP), 1, skill.maxRank)
end

local function learned(owned: Owned, id: string?): boolean
	return id ~= nil and SkillRules.rankOf(owned, id) >= 1
end

--[[
	May the character learn `id` (or raise it one rank)? Returns (ok, reason).
	`unlockAll` (Studio only) lifts the level gate.
]]
function SkillRules.canLearn(
	job: string?,
	owned: Owned,
	level: number,
	bonus: number?,
	unlockAll: boolean,
	id: any
): (boolean, string?)
	local skill = SkillDefinitions.get(id)
	if job == nil then
		return false, "noJob"
	elseif
		skill == nil
		or skill.job ~= job
		or not JobDefinitions.allowsSkillCategory(job, skill.category)
	then
		return false, "wrongJob"
	elseif SkillRules.rankOf(owned, skill.id) >= skill.maxRank then
		return false, "maxRank"
	elseif not unlockAll and level < skill.unlockLevel then
		return false, "locked"
	elseif SkillRules.rankOf(owned, skill.id) >= SkillRules.rankCap(skill, level, unlockAll) then
		return false, "rankLocked"
	elseif skill.requires and not learned(owned, skill.requires) then
		return false, "requires"
	elseif SkillRules.available(owned, level, bonus) <= 0 then
		return false, "noPoints"
	end
	return true, nil
end

--[[
	A copy of `owned` without skills the level hasn't opened and with ranks
	clamped to the level's cap (e.g. after a config change or a Studio test
	allowance is switched off). Deeper tiers open later, so removing a skill
	never leaves one below it. Returns (owned, changed).
]]
function SkillRules.fitToLevel(owned: Owned, level: number, unlockAll: boolean?): (Owned, boolean)
	local out: Owned = {}
	local changed = false
	for id, rank in owned do
		local skill = SkillDefinitions.get(id)
		if skill == nil or (not unlockAll and level < skill.unlockLevel) then
			changed = true
			continue
		end
		local cap = SkillRules.rankCap(skill, level, unlockAll)
		out[id] = math.min(rank, cap)
		changed = changed or rank > cap
	end
	return out, changed
end

-- Skills of `job` that open at a level in (fromLevel, toLevel].
function SkillRules.unlockedBetween(job: string?, fromLevel: number, toLevel: number): { Skill }
	local out = {}
	for _, skill in SkillDefinitions.forJob(job) do
		if skill.unlockLevel > fromLevel and skill.unlockLevel <= toLevel then
			table.insert(out, skill)
		end
	end
	return out
end

--------------------------------------------------------------------------------
-- Skill bar
--------------------------------------------------------------------------------

local function usable(skill: Skill?, job: string?, owned: Owned): boolean
	return skill ~= nil
		and job ~= nil
		and skill.job == job
		and learned(owned, skill.id)
		and JobDefinitions.allowsSkillCategory(job, skill.category)
end

--[[
	Returns (ok, reason). `regular` is at most 3 entries (the remote schema
	enforces it); this checks everything else.
]]
function SkillRules.validateLoadout(
	job: string?,
	owned: Owned,
	regular: { any },
	special: any
): (boolean, string?)
	if job == nil then
		return false, "noJob"
	end
	if type(regular) ~= "table" or #regular > SkillRules.REGULAR_SLOTS then
		return false, "tooMany"
	end
	local seen: { [string]: boolean } = {}
	for _, id in regular do
		local skill = SkillDefinitions.get(id)
		if skill == nil or not usable(skill, job, owned) then
			return false, "notLearned"
		elseif skill.type ~= "Regular" then
			return false, "wrongSlot"
		elseif seen[skill.id] then
			return false, "duplicate"
		end
		seen[skill.id] = true
	end
	if special ~= nil then
		local skill = SkillDefinitions.get(special)
		if skill == nil or not usable(skill, job, owned) then
			return false, "notLearned"
		elseif skill.type ~= "Special" then
			return false, "wrongSlot"
		end
	end
	return true, nil
end

function SkillRules.isEquipped(loadout: Loadout, id: string): boolean
	return loadout.Special == id or table.find(loadout.Regular, id) ~= nil
end

-- Returns (ok, reason) for casting skill `id` (T-03 / T-04).
function SkillRules.canCast(id: any, facts: CastFacts): (boolean, string?)
	local skill = SkillDefinitions.get(id)
	if skill == nil or not usable(skill, facts.job, facts.owned) then
		return false, "notLearned"
	elseif not SkillRules.isEquipped(facts.loadout, skill.id) then
		return false, "notEquipped"
	elseif facts.stunned then
		return false, "stunned"
	elseif facts.silenced then
		return false, "silenced"
	elseif facts.now < facts.globalReadyAt - facts.slack then
		return false, "busy"
	elseif facts.readyAt and facts.now < facts.readyAt - facts.slack then
		return false, "cooldown"
	elseif facts.focus < skill.focusCost then
		return false, "noFocus"
	end
	return true, nil
end

--[[
	A copy of `loadout` with empty slots filled by learned skills that are
	not on the bar yet (tree order). Never moves the player's choices.
]]
function SkillRules.autoFill(job: string?, owned: Owned, loadout: Loadout): Loadout
	local regular = table.clone(loadout.Regular)
	local special = loadout.Special
	for _, skill in SkillDefinitions.forJob(job) do
		if not usable(skill, job, owned) then
			continue
		end
		if skill.type == "Regular" then
			if #regular < SkillRules.REGULAR_SLOTS and table.find(regular, skill.id) == nil then
				table.insert(regular, skill.id)
			end
		elseif special == nil then
			special = skill.id
		end
	end
	return { Regular = regular, Special = special }
end

-- The loadout without skills that are no longer learned (after a reset).
function SkillRules.prune(job: string?, owned: Owned, loadout: Loadout): Loadout
	local regular = {}
	for _, id in loadout.Regular do
		local skill = SkillDefinitions.get(id)
		if
			usable(skill, job, owned)
			and (skill :: Skill).type == "Regular"
			and table.find(regular, id) == nil
		then
			table.insert(regular, id)
		end
	end
	local special = SkillDefinitions.get(loadout.Special)
	return {
		Regular = regular,
		Special = if usable(special, job, owned) and (special :: Skill).type == "Special"
			then (special :: Skill).id
			else nil,
	}
end

--------------------------------------------------------------------------------
-- Ranks and combos
--------------------------------------------------------------------------------

-- `effect` with its numbers at `rank` (1 = as defined).
function SkillRules.effectAtRank(effect: Effect, rank: number): Effect
	local r = math.max(1, rank) - 1
	local out = table.clone(effect) :: Effect
	if out.coefficient then
		out.coefficient = out.coefficient * (1 + SkillRules.COEFFICIENT_PER_RANK * r)
	end
	local cap = (SkillRules.CAPS :: any)[effect.kind]
	if out.seconds and cap then
		out.seconds = math.min(out.seconds * (1 + SkillRules.DURATION_PER_RANK * r), cap)
	end
	if out.pct then
		out.pct = math.min(out.pct * (1 + SkillRules.PCT_PER_RANK * r), SkillRules.CAPS.Pct)
	end
	return out
end

--[[
	Does `combo` trigger on a target with these statuses and HP fraction?
	`has(kind)` reports whether the target has a status right now.
]]
function SkillRules.comboApplies(
	combo: SkillDefinitions.Combo?,
	has: (string) -> boolean,
	hpFraction: number
): boolean
	if combo == nil then
		return false
	end
	if combo.status then
		return has(combo.status)
	end
	if combo.lowHpPct then
		return hpFraction * 100 < combo.lowHpPct
	end
	return false
end

--------------------------------------------------------------------------------
-- Damage and support
--------------------------------------------------------------------------------

--[[
	Damage `amount` arriving at a target that is marked (`markPct`% more),
	guarded (`guardPct`% less) and shielded (`shield` points absorb first).
	Returns (hpDamage, absorbed, shieldLeft); all whole numbers >= 0.
]]
function SkillRules.incoming(
	amount: number,
	markPct: number,
	guardPct: number,
	shield: number
): (number, number, number)
	local scaled = amount * (1 + math.max(markPct, 0) / 100) * (1 - math.clamp(guardPct, 0, 90) / 100)
	scaled = math.max(1, math.floor(scaled + 0.5))
	local absorbed = math.min(scaled, math.max(0, math.floor(shield)))
	return scaled - absorbed, absorbed, math.max(0, math.floor(shield) - absorbed)
end

-- Attack after Empower (+%) and Weaken (−%); never below 10%.
function SkillRules.attackScale(empowerPct: number, weakenPct: number): number
	return math.max(0.1, (1 + math.max(empowerPct, 0) / 100) * (1 - math.clamp(weakenPct, 0, 90) / 100))
end

--[[
	May the helper heal / shield / buff / cleanse the target? Returns
	(allowed, reason). Same realm only (D-24). A helper standing in a safe
	zone can't support someone who is fighting outside it.
]]
function SkillRules.canHelp(facts: HelpFacts): (boolean, string?)
	if facts.helperDefeated then
		return false, "helperDefeated"
	elseif facts.targetDefeated then
		return false, "targetDefeated"
	elseif not facts.targetIsPlayer or not facts.helperIsPlayer then
		return false, "notAlly"
	elseif facts.helperRace == nil or facts.helperRace ~= facts.targetRace then
		return false, "notAlly"
	elseif facts.helperInSafeZone and not facts.targetInSafeZone and facts.targetInCombat then
		return false, "safeZone"
	end
	return true, nil
end

--[[
	Seconds a crowd-control status lasts on its target: 0 for a
	control-immune target (bosses), scaled by `pvpScale` when a player
	controls a player. Taunt never affects players but works on bosses.
]]
function SkillRules.controlSeconds(
	kind: string,
	seconds: number,
	targetImmune: boolean,
	playerVsPlayer: boolean,
	pvpScale: number
): number
	if kind == "Taunt" then
		return if playerVsPlayer then 0 else seconds
	end
	if not CONTROL[kind] then
		return seconds
	end
	if targetImmune then
		return 0
	end
	if playerVsPlayer then
		return seconds * math.clamp(pvpScale, 0, 1)
	end
	return seconds
end

--------------------------------------------------------------------------------
-- Player-facing text (skill info panel, tooltips)
--------------------------------------------------------------------------------

local function pct(coefficient: number): string
	return `{math.floor(coefficient * 100 + 0.5)}%`
end

local function secs(seconds: number): string
	local rounded = math.floor(seconds * 10 + 0.5) / 10
	return if rounded % 1 == 0 then `{math.floor(rounded)} s` else `{rounded} s`
end

local STATUS_TEXT: { [string]: string } = {
	Stun = "Stuns",
	Freeze = "Freezes solid",
	Root = "Roots in place",
	Silence = "Silences (no skills)",
	Taunt = "Taunts creatures",
}

-- One line per effect at `rank`, e.g. "Deals 150% Attack damage".
function SkillRules.effectLine(effect: Effect, rank: number, target: SkillDefinitions.Target): string
	local e = SkillRules.effectAtRank(effect, rank)
	local who = if e.self
		then "you"
		elseif target == "SelfArea" and not SkillDefinitions.HOSTILE_KINDS[e.kind] then "allies"
		else "the target"
	local k = e.kind
	if k == "Damage" then
		local crit = if e.critBonusPct then ` (+{e.critBonusPct}% crit chance)` else ""
		return `Deals {pct(e.coefficient or 1)} Attack damage{crit}`
	elseif k == "Heal" then
		return `Heals {pct(e.coefficient or 1)} Attack`
	elseif k == "Shield" then
		return `Shields {who} for {pct(e.coefficient or 1)} Attack ({secs(e.seconds or 0)})`
	elseif k == "Poison" or k == "Burn" then
		return `{if k == "Poison" then "Poisons" else "Burns"}: {pct(e.coefficient or 0)} Attack every second for {secs(
			e.seconds or 0
		)}`
	elseif k == "Regen" then
		return `Heals {pct(e.coefficient or 0)} Attack every second for {secs(e.seconds or 0)}`
	elseif k == "Slow" then
		return `Slows by {math.floor(e.pct or 0)}% for {secs(e.seconds or 0)}`
	elseif k == "Mark" then
		return `Marks: takes {math.floor(e.pct or 0)}% more damage for {secs(e.seconds or 0)}`
	elseif k == "Weaken" then
		return `Weakens: deals {math.floor(e.pct or 0)}% less damage for {secs(e.seconds or 0)}`
	elseif k == "Guard" then
		return `{who == "you" and "You take" or "Takes"} {math.floor(e.pct or 0)}% less damage for {secs(
			e.seconds or 0
		)}`
	elseif k == "Harden" then
		return `Hardens {who}: +{math.floor(e.pct or 0)}% Defense for {secs(e.seconds or 0)}`
	elseif k == "Empower" then
		return `Empowers {who}: +{math.floor(e.pct or 0)}% Attack for {secs(e.seconds or 0)}`
	elseif k == "Haste" then
		return `Hastes {who}: moves {math.floor(e.pct or 0)}% faster for {secs(e.seconds or 0)}`
	elseif k == "Cleanse" then
		return `Removes stuns, freezes, roots, slows, silences, marks, weakness, poison and burns`
	elseif k == "Dash" then
		return `Dashes {e.studs or 0} studs`
	end
	return `{STATUS_TEXT[k] or k} for {secs(e.seconds or 0)}`
end

local STATUS_ADJECTIVE: { [string]: string } = {
	Stun = "stunned",
	Freeze = "frozen",
	Root = "rooted",
	Slow = "slowed",
	Poison = "poisoned",
	Burn = "burning",
	Mark = "marked",
	Weaken = "weakened",
	Silence = "silenced",
}

local TARGET_TEXT: { [string]: string } = {
	Enemy = "Single enemy",
	Ally = "Ally or yourself",
	Self = "Yourself",
	SelfArea = "Area around you",
	EnemyArea = "Area at your target",
	Dash = "Movement",
}

export type Description = {
	header: string, -- "REGULAR · Melee Strike · Blademaster"
	stats: string, -- "Focus 12 · Cooldown 5 s · Range 8"
	target: string,
	effects: { string },
	combo: string?,
	nextRank: { string }?, -- what changes at the next rank (nil at max)
}

function SkillRules.describe(skill: Skill, rank: number): Description
	local shown = math.max(rank, 1)
	local category = (JobDefinitions.CategoryNames :: any)[skill.category] or skill.category
	local stats = { `Focus {skill.focusCost}`, `Cooldown {secs(skill.cooldown)}` }
	if skill.range > 0 then
		table.insert(stats, `Range {skill.range}`)
	end
	if skill.radius then
		table.insert(stats, `Radius {skill.radius}`)
	end
	local effects = {}
	for _, effect in skill.effects do
		table.insert(effects, SkillRules.effectLine(effect, shown, skill.target))
	end
	if skill.waves and skill.waves > 1 then
		table.insert(effects, `Hits {skill.waves} times`)
	end
	if skill.delay then
		table.insert(effects, `Lands after a {secs(skill.delay)} warning`)
	end
	local combo: string? = nil
	if skill.combo then
		local c = skill.combo
		local condition = if c.status
			then `{STATUS_ADJECTIVE[c.status] or string.lower(c.status)} targets`
			else `targets below {c.lowHpPct}% HP`
		combo =
			`COMBO · {c.name}: +{c.bonusPct}% damage on {condition}{if c.consume then " (ends it)" else ""}`
	end
	local nextRank: { string }? = nil
	if rank >= 1 and rank < skill.maxRank then
		local lines = {}
		for _, effect in skill.effects do
			local now = SkillRules.effectLine(effect, rank, skill.target)
			local later = SkillRules.effectLine(effect, rank + 1, skill.target)
			if now ~= later then
				table.insert(lines, later)
			end
		end
		nextRank = lines
	end
	return {
		header = `{string.upper(skill.type)} · {category} · {skill.branch}`,
		stats = table.concat(stats, "  ·  "),
		target = TARGET_TEXT[skill.target] or skill.target,
		effects = effects,
		combo = combo,
		nextRank = nextRank,
	}
end

return table.freeze(SkillRules)
