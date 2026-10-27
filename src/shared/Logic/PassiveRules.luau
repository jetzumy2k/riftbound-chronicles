--!strict
--[[
	PassiveRules — what learned class passives add to a character's stats
	(D-104; definitions in Definitions/PassiveDefinitions). Applied by
	StatsService after attribute points and before Mall buffs, as a new
	table (the incoming stats may be frozen).

	  totals    stat -> summed bonus of the job's learned passives
	  applyTo   stats with the passives added
	  describe  "+12% damage" style lines for a passive at a rank

	Only passives of the character's own job count; ranks are clamped to
	1..maxRank. Dodge stays under AttributeRules.EVASION_CAP_PCT. Pure.
]]

local PassiveDefinitions = require(script.Parent.Parent.Definitions.PassiveDefinitions)
local AttributeRules = require(script.Parent.AttributeRules)

local PassiveRules = {}

local LABELS: { [string]: string } = {
	DamagePct = "% damage",
	MaxHPPct = "% Max HP",
	DefensePct = "% Defense",
	CritChancePct = "% crit chance",
	CritDamagePct = "% crit damage",
	HealingPct = "% healing and shields",
	Focus = " max Focus",
	EvasionPct = "% dodge chance",
}

function PassiveRules.totals(owned: { [string]: any }?, job: string?): { [string]: number }
	local out: { [string]: number } = {}
	for _, passive in PassiveDefinitions.forJob(job) do
		local rank = if owned then owned[passive.id] else nil
		if type(rank) == "number" and rank >= 1 then
			rank = math.min(math.floor(rank), passive.maxRank)
			for stat, value in passive.perRank do
				out[stat] = (out[stat] or 0) + value * rank
			end
		end
	end
	return out
end

function PassiveRules.applyTo(stats: any, owned: { [string]: any }?, job: string?): any
	local t = PassiveRules.totals(owned, job)
	if next(t) == nil then
		return stats
	end
	local out: any = table.clone(stats)
	out.MaxHP = out.MaxHP * (1 + (t.MaxHPPct or 0) / 100)
	out.Defense = out.Defense * (1 + (t.DefensePct or 0) / 100)
	out.DamagePct = (out.DamagePct or 0) + (t.DamagePct or 0)
	out.CritChancePct = (out.CritChancePct or 0) + (t.CritChancePct or 0)
	out.CritDamagePct = (out.CritDamagePct or 0) + (t.CritDamagePct or 0)
	out.HealingPowerPct = (out.HealingPowerPct or 0) + (t.HealingPct or 0)
	out.FocusBonus = (out.FocusBonus or 0) + (t.Focus or 0)
	out.EvasionPct = math.min((out.EvasionPct or 0) + (t.EvasionPct or 0), AttributeRules.EVASION_CAP_PCT)
	return out
end

-- Player-facing lines for `passive` at `rank` (0 = not learned: nothing).
function PassiveRules.describe(passive: PassiveDefinitions.Passive, rank: number): { string }
	local lines = {}
	for _, stat in PassiveDefinitions.STATS do
		local value = passive.perRank[stat]
		if value and rank >= 1 then
			table.insert(lines, `+{value * rank}{LABELS[stat]}`)
		end
	end
	return lines
end

return table.freeze(PassiveRules)
