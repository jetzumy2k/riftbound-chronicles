--!strict
--[[
	LevelGap — EXP and danger by the level gap between a creature and a
	player (creator's request 2026-10-19, PLAN.md D-63). Pure module.

	gap = creature level − player level:

	  gap ≥ 20        Deadly   no EXP (far too strong to farm)
	  10 … 19         Higher   ×1.5
	  5 … 9           High     ×1.3
	  2 … 4           Medium   ×1.15
	  −4 … 1          Normal   ×1
	  −9 … −5         Minimal  ×0.25
	  gap ≤ −10       Trivial  no EXP

	The creator named 10–15 for "higher" and left 16–19 open; those count
	as Higher too, so EXP never drops before the Deadly cliff.

	  tierFor     the tier for a gap (nameplate colour, EXP multiplier)
	  scaleXp     a kill's EXP for one player after the gap rule
]]

export type TierId = "Deadly" | "Higher" | "High" | "Medium" | "Normal" | "Minimal" | "Trivial"

export type Tier = {
	id: TierId,
	-- Whole percent, so the rounding is exact (1.15 is not exact in binary).
	percent: number,
}

local function tier(id: TierId, percent: number): Tier
	return table.freeze({ id = id, percent = percent })
end

local LevelGap = {}

LevelGap.Tiers = table.freeze({
	Deadly = tier("Deadly", 0),
	Higher = tier("Higher", 150),
	High = tier("High", 130),
	Medium = tier("Medium", 115),
	Normal = tier("Normal", 100),
	Minimal = tier("Minimal", 25),
	Trivial = tier("Trivial", 0),
})

function LevelGap.tierFor(creatureLevel: number, playerLevel: number): Tier
	local gap = math.floor(creatureLevel) - math.floor(playerLevel)
	local tiers = LevelGap.Tiers
	if gap >= 20 then
		return tiers.Deadly
	elseif gap >= 10 then
		return tiers.Higher
	elseif gap >= 5 then
		return tiers.High
	elseif gap >= 2 then
		return tiers.Medium
	elseif gap >= -4 then
		return tiers.Normal
	elseif gap >= -9 then
		return tiers.Minimal
	end
	return tiers.Trivial
end

-- EXP one player gets from `xp` (their share of a kill) after the gap
-- rule. A rewarding tier never rounds a kill down to nothing.
function LevelGap.scaleXp(xp: number, creatureLevel: number, playerLevel: number): number
	local percent = LevelGap.tierFor(creatureLevel, playerLevel).percent
	if xp <= 0 or percent <= 0 then
		return 0
	end
	return math.max(1, math.floor(xp * percent / 100 + 0.5))
end

return table.freeze(LevelGap)
