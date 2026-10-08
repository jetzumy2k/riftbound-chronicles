--!strict
--[[
	XPTable
	Experience curve (PLAN.md D-18): XPToNext(L) = round(100 * 1.18^L), L = 0..29.
	Total XP from Level 0 to 30 = 79,095 (each level rounded).

	Server-authoritative use: LevelService.GrantXP. The client uses it only to
	display progress bars.

	Pure module: no engine APIs beyond requires (tests load it via tests/pure/loader).
]]

local Constants = require(script.Parent.Parent.Constants)

local MAX_LEVEL: number = Constants.Level.Max
local BASE: number = Constants.Experience.Base
local GROWTH: number = Constants.Experience.Growth

export type ApplyResult = {
	level: number,
	experience: number,
	levelsGained: number,
	-- XP that counted toward progression.
	applied: number,
	-- XP thrown away because the level cap was reached.
	discarded: number,
}

local XPTable = {}

local toNextByLevel: { [number]: number } = {}
local totalToReach: { [number]: number } = { [0] = 0 }
for level = 0, MAX_LEVEL - 1 do
	toNextByLevel[level] = math.round(BASE * GROWTH ^ level)
	totalToReach[level + 1] = totalToReach[level] + toNextByLevel[level]
end

--[[
	XP needed to advance from `level` to `level + 1`. Returns 0 at the cap.
]]
function XPTable.toNext(level: number): number
	if level >= MAX_LEVEL then
		return 0
	end
	local value = toNextByLevel[level]
	assert(value ~= nil, `invalid level {level}`)
	return value
end

--[[
	Cumulative XP needed to reach `level` from Level 0.
]]
function XPTable.totalToReach(level: number): number
	local value = totalToReach[level]
	assert(value ~= nil, `invalid level {level}`)
	return value
end

--[[
	Applies `amount` XP to (level, experience). Inputs must already be valid
	(integer level 0..Max, experience within the level, amount >= 0).
	Handles multi-level gains and the cap.
]]
function XPTable.apply(level: number, experience: number, amount: number): ApplyResult
	local startLevel = level
	local xp = experience + amount

	while level < MAX_LEVEL and xp >= toNextByLevel[level] do
		xp -= toNextByLevel[level]
		level += 1
	end

	local discarded = 0
	if level >= MAX_LEVEL then
		discarded = xp
		xp = 0
	end

	return {
		level = level,
		experience = xp,
		levelsGained = level - startLevel,
		applied = amount - discarded,
		discarded = discarded,
	}
end

return table.freeze(XPTable)
