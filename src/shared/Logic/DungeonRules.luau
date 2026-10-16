--!strict
--[[
	DungeonRules — pure rules for dungeon runs (PLAN.md Phase 9, D-32; respawns: PartyRules, D-39).

	  canEnter       level / party-size requirements
	  shareXp        D-32 party EXP sharing: the kill's EXP gets a bonus per
	                 extra member in range, then is split evenly
	  partyHpScale   enemy HP grows with party size so groups aren't trivial
	  phaseFor       boss phase for an HP fraction
	  runId          unique across servers: "<JobId>:<counter>"

	Pure module.
]]

local DungeonRules = {}

-- D-32: each extra party member in range adds this much to the shared pool.
DungeonRules.PARTY_XP_BONUS = 0.15

function DungeonRules.canEnter(
	level: number,
	partySize: number,
	minLevel: number,
	maxParty: number
): (boolean, string?)
	if partySize < 1 or partySize > maxParty then
		return false, "partySize"
	end
	if level < minLevel then
		return false, "level"
	end
	return true, nil
end

-- EXP each of `members` (≥ 1) players in range receives for `xp`.
function DungeonRules.shareXp(xp: number, members: number): number
	if members < 1 or xp <= 0 then
		return 0
	end
	-- Whole percentages keep the rounding exact (1.15 is not exact in binary).
	local bonusPct = math.floor(DungeonRules.PARTY_XP_BONUS * 100 + 0.5)
	local pool = xp * (100 + bonusPct * (members - 1)) / 100
	return math.floor(pool / members + 0.5)
end

function DungeonRules.partyHpScale(partySize: number, perExtraMember: number): number
	return 1 + perExtraMember * math.max(0, partySize - 1)
end

-- Index of the boss phase for `hpFraction` (phases ordered, each active
-- while hpFraction > untilHpFraction).
function DungeonRules.phaseFor(phases: { any }, hpFraction: number): number
	for index, phase in phases do
		if hpFraction > phase.untilHpFraction then
			return index
		end
	end
	return #phases
end

function DungeonRules.runId(jobId: string, counter: number): string
	local server = if jobId == "" then "studio" else jobId
	return `{server}:{counter}`
end

return table.freeze(DungeonRules)
