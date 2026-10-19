--!strict
--[[
	EnhanceRules — pure rules for enhancement (Phase 8, PLAN.md D-08 / D-66;
	CLAUDE.md §10).

	  rateFor    chance (percent) to go from +N to +N+1
	  check      can this item be enhanced with this stone right now?
	  attempt    one attempt: consume one stone, roll, apply (one
	             synchronous step; EnhancementService calls it)

	D-08: +1 to +5 always succeed; from +6 the rates decline (configurable,
	default 90/80/70/60/50). A failure never downgrades or destroys the item
	(only the stone is used). A Perfect Enhancement Stone always succeeds.
	The cap is +10 (Constants.Enhancement.Max). What each +1 adds is in
	ItemRules.baseStats (weapon +20 Attack and +2.5% Crit Damage, armor and
	accessories +8 Defense).

	Pure module.
]]

local Constants = require(script.Parent.Parent.Constants)

local EnhanceRules = {}

EnhanceRules.MAX = Constants.Enhancement.Max
EnhanceRules.STONE = "EnhancementStone"
EnhanceRules.PERFECT = "PerfectStone"
-- D-08 default rates (percent) for reaching +1 … +10.
EnhanceRules.DEFAULT_RATES = table.freeze({ 100, 100, 100, 100, 100, 90, 80, 70, 60, 50 })

export type Result = {
	success: boolean,
	from: number,
	to: number,
	stone: string,
	rate: number,
}

-- Percent chance to go from `current` to `current + 1` (0 at the cap).
-- `rates` must hold one value per level; anything else uses the defaults.
function EnhanceRules.rateFor(current: number, rates: { number }?, perfect: boolean?): number
	if current >= EnhanceRules.MAX or current < 0 then
		return 0
	end
	if perfect then
		return 100
	end
	local table_ = if rates and #rates == EnhanceRules.MAX then rates else EnhanceRules.DEFAULT_RATES
	return math.clamp(table_[current + 1], 0, 100)
end

--[[
	Whether `item` (with `Enhancement`) can be enhanced now with a normal
	or Perfect stone from `stackables`. Reasons: "max", "noStone".
]]
function EnhanceRules.check(
	item: { Enhancement: number },
	stackables: { [string]: number },
	perfect: boolean
): (boolean, string?)
	if item.Enhancement >= EnhanceRules.MAX then
		return false, "max"
	end
	local stone = if perfect then EnhanceRules.PERFECT else EnhanceRules.STONE
	if (stackables[stone] or 0) < 1 then
		return false, "noStone"
	end
	return true, nil
end

--[[
	One attempt, in one synchronous step: checks, consumes exactly one
	stone, rolls (`roll` in [0, 1) from the server) and applies. Mutates
	`item` and `stackables`; returns nil and a reason when refused (nothing
	consumed).
]]
function EnhanceRules.attempt(
	item: { Enhancement: number },
	stackables: { [string]: number },
	perfect: boolean,
	roll: number,
	rates: { number }?
): (Result?, string?)
	local ok, reason = EnhanceRules.check(item, stackables, perfect)
	if not ok then
		return nil, reason
	end
	local stone = if perfect then EnhanceRules.PERFECT else EnhanceRules.STONE
	local from = item.Enhancement
	local rate = EnhanceRules.rateFor(from, rates, perfect)
	stackables[stone] -= 1
	if stackables[stone] <= 0 then
		stackables[stone] = nil
	end
	local success = roll * 100 < rate
	if success then
		item.Enhancement = from + 1
	end
	return { success = success, from = from, to = item.Enhancement, stone = stone, rate = rate }, nil
end

return table.freeze(EnhanceRules)
