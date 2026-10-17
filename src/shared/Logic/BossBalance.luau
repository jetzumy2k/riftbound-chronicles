--!strict
--[[
	BossBalance — how hard a boss is to kill, by group size (PLAN.md D-47).

	Creator rule (2026-10-17) for the Dungeon Boss and the war-zone bosses:
	  1 player  impossible      2 players  super hard
	  a party   very hard       a union    hard
	Bosses enrage after `enrageSeconds` (huge damage, faster abilities), so
	"impossible" means a group can't deal the boss's HP before the enrage.
	A boss's HP is designed from a model of a reference player's damage:

	  dps(L, D)   = CHAIN_COEF x skillBonus(L) x UPTIME
	                x Attack(L) x PowerScale(L) x K / (K + D)       (CombatMath)
	  K           = DefenseKBase + DefenseKPerLevel x L
	  skillBonus  = 1 + SKILL_BONUS x L / 30 (skills add up to ~60% at 30)
	  hp          = duoFraction x enrage x 2 x dps(refLevel, bossDefense)

	where refLevel = min(boss level, 30): the players expected there.
	Time to kill with n players = hp / (n x dps); as a share of the enrage
	timer that is duoFraction x 2 / n:

	  tier     duoFraction   1 player  2       party (4)  union (8 / 16)
	  Boss     0.95          1.90      0.95    0.48       0.24 / 0.12
	  Floor    0.70          1.40      0.70    0.35       0.18 / 0.09
	  Mini     0.30          0.60      0.30    0.15       -
	War-zone bosses ramp from the Floor numbers at level 30 to the Boss
	numbers at level 50 (fieldDuoFraction).

	Boss hits are sized as a share of the reference player's HP
	(attackCoefficientFor). Gear (Phases 7 / 10) raises player damage;
	Phase 20 re-tunes these numbers. Pure module.
]]

local StatFormulas = require(script.Parent.StatFormulas)
local Constants = require(script.Parent.Parent.Constants)

local BossBalance = {}

-- Must match Defaults.Combat (checked by tests).
BossBalance.COMBAT = table.freeze({
	PowerScalePerLevel = 1.047,
	DefenseKBase = 200,
	DefenseKPerLevel = 25,
})
-- Average basic-attack chain coefficient per second across the classes.
BossBalance.CHAIN_COEF = 0.96
BossBalance.SKILL_BONUS = 0.6
-- Share of the fight spent hitting (the rest: dodging, moving, reviving).
BossBalance.UPTIME = 0.7

export type Tier = "Boss" | "Floor" | "Mini"

BossBalance.DUO_FRACTION = table.freeze({
	Boss = 0.95,
	Floor = 0.7,
	Mini = 0.3,
})

-- Group sizes the tiers are described with.
BossBalance.GROUPS = table.freeze({ Solo = 1, Duo = 2, Party = 4, Union = 8 })

local function power(level: number): number
	return BossBalance.COMBAT.PowerScalePerLevel ^ level
end

local function k(level: number): number
	return BossBalance.COMBAT.DefenseKBase + BossBalance.COMBAT.DefenseKPerLevel * level
end

-- Players expected to fight a boss of `bossLevel`.
function BossBalance.referenceLevel(bossLevel: number): number
	return math.clamp(bossLevel, 0, Constants.Level.Max)
end

-- Modelled damage per second of one reference player against `defense`.
function BossBalance.playerDps(level: number, defense: number): number
	local attack = StatFormulas.forLevel(level).Attack
	local coefficient = BossBalance.CHAIN_COEF * (1 + BossBalance.SKILL_BONUS * level / Constants.Level.Max)
	return coefficient
		* BossBalance.UPTIME
		* attack
		* power(level)
		* k(level)
		/ (k(level) + math.max(defense, 0))
end

-- War-zone bosses get harder with level: level 30 is a Floor-tier fight,
-- level 50 a full Boss-tier one.
function BossBalance.fieldDuoFraction(level: number): number
	local t = math.clamp((level - 30) / 20, 0, 1)
	return BossBalance.DUO_FRACTION.Floor
		+ (BossBalance.DUO_FRACTION.Boss - BossBalance.DUO_FRACTION.Floor) * t
end

-- Boss max HP: a duo kills it in `duoFraction` of the enrage timer.
function BossBalance.hpFor(
	level: number,
	defenseScale: number,
	duoFraction: number,
	enrageSeconds: number
): number
	local defense = StatFormulas.forCreatureLevel(level).Defense * defenseScale
	local dps = BossBalance.playerDps(BossBalance.referenceLevel(level), defense)
	return duoFraction * enrageSeconds * 2 * dps
end

-- Seconds `players` reference players need to bring down `hp`.
function BossBalance.timeToKill(hp: number, players: number, level: number, defenseScale: number): number
	local defense = StatFormulas.forCreatureLevel(level).Defense * defenseScale
	return hp / (math.max(players, 1) * BossBalance.playerDps(BossBalance.referenceLevel(level), defense))
end

export type Verdict = "Impossible" | "SuperHard" | "VeryHard" | "Hard" | "Fair"

-- How hard a kill is from its time as a share of the enrage timer.
function BossBalance.verdict(timeToKill: number, enrageSeconds: number): Verdict
	local share = timeToKill / enrageSeconds
	if share > 1 then
		return "Impossible"
	elseif share > 0.8 then
		return "SuperHard"
	elseif share > 0.4 then
		return "VeryHard"
	elseif share > 0.1 then
		return "Hard"
	end
	return "Fair"
end

--[[
	Attack multiplier so one basic hit (`coefficient`) of a creature of
	`level` takes `hitFraction` of a reference player's HP. Abilities scale
	with it too (their coefficients are relative to Attack).
]]
function BossBalance.attackScaleFor(level: number, coefficient: number, hitFraction: number): number
	local ref = BossBalance.referenceLevel(level)
	local player = StatFormulas.forLevel(ref)
	local raw = StatFormulas.forCreatureLevel(level).Attack * coefficient * power(level)
	local dealt = raw * k(level) / (k(level) + player.Defense)
	return hitFraction * player.MaxHP / dealt
end

return table.freeze(BossBalance)
