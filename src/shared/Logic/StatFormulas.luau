--!strict
--[[
	StatFormulas
	Base character stats by level, exactly as CLAUDE.md §5 specifies:

	  HP(L)          = 200 * 1.20^L             (multiplicative)
	  Attack(L)      = 100 * 1.10^L             (multiplicative)
	  Defense(L)     =  50 * 1.08^L             (multiplicative)
	  CritDamage(L)  = 0.05% + 0.05% * L        (additive percentage points)
	  HPRegen(L)     = 0.02% + 0.02% * L        (additive percentage points)

	Plus approved defaults:
	  CritChance     = 5%                       (PLAN.md D-03)
	  CritMultiplier = 1.5 + CritDamage% / 100  (PLAN.md D-02)

	Values are unrounded; rounding is a display concern. Gear and enhancement
	bonuses are layered on top by StatsService (Phase 7/8). Damage scaling
	(Level Power Scale, D-01) is applied by combat (Phase 6), not here.

	Percent values are in percent units: 0.05 means 0.05%.

	Pure module: no engine APIs beyond requires (tests load it via tests/pure/loader).
]]

local Constants = require(script.Parent.Parent.Constants)

export type BaseStats = {
	MaxHP: number,
	Attack: number,
	Defense: number,
	CritDamagePct: number,
	HPRegenPct: number,
	CritChancePct: number,
	CritMultiplier: number,
}

local BASE = Constants.BaseStats
local GROWTH = Constants.StatGrowth
local CRIT = Constants.Crit

local StatFormulas = {}

function StatFormulas.forLevel(level: number): BaseStats
	assert(
		type(level) == "number"
			and level % 1 == 0
			and level >= Constants.Level.Min
			and level <= Constants.Level.Max,
		`invalid level {tostring(level)}`
	)

	local critDamagePct = BASE.CritDamagePct + GROWTH.CritDamagePctPerLevel * level

	return table.freeze({
		MaxHP = BASE.HP * GROWTH.HPMultiplier ^ level,
		Attack = BASE.Attack * GROWTH.AttackMultiplier ^ level,
		Defense = BASE.Defense * GROWTH.DefenseMultiplier ^ level,
		CritDamagePct = critDamagePct,
		HPRegenPct = BASE.HPRegenPct + GROWTH.HPRegenPctPerLevel * level,
		CritChancePct = CRIT.BaseChancePct,
		CritMultiplier = CRIT.BaseMultiplier + critDamagePct / 100,
	})
end

return table.freeze(StatFormulas)
