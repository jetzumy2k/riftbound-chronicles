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
local LevelCap = require(script.Parent.LevelCap)

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
local BASE_LEVEL: number = Constants.Level.Base
for level = 0, MAX_LEVEL - 1 do
	-- D-129: past 30, +6 % a level from the last original step.
	toNextByLevel[level] = if level < BASE_LEVEL
		then math.round(BASE * GROWTH ^ level)
		else math.round(BASE * GROWTH ^ (BASE_LEVEL - 1) * LevelCap.XP_GROWTH ^ (level - BASE_LEVEL + 1))
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
	Creature EXP scale by creature level (Phase 20 balance, PLAN.md D-95):
	creatures gave about a quarter of a level each, so level 30 took under an
	hour. Every creature kill and dungeon-boss bonus is scaled by
	CREATURE_SCALE_BASE x CREATURE_SCALE_DECAY ^ level: generous early (a few
	minutes per level), about 19 active hours to 30 in the balance model
	(docs/balance). Quests are not scaled.
]]
XPTable.CREATURE_SCALE_BASE = 0.2
XPTable.CREATURE_SCALE_DECAY = 0.905

function XPTable.creatureScale(level: number): number
	return XPTable.CREATURE_SCALE_BASE * XPTable.CREATURE_SCALE_DECAY ^ math.clamp(level, 0, BASE_LEVEL)
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
function XPTable.apply(level: number, experience: number, amount: number, cap: number?): ApplyResult
	-- D-129: the live cap (30, or 60 with the admin switch); never above Max.
	local top = math.clamp(cap or BASE_LEVEL, 0, MAX_LEVEL)
	local startLevel = level
	local xp = experience + amount

	while level < top and xp >= toNextByLevel[level] do
		xp -= toNextByLevel[level]
		level += 1
	end

	local discarded = 0
	if level >= top then
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
