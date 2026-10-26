--!strict
--[[
	HitStreak — the on-screen combo counter's rules (D-103 stage C). Every
	hit the local player lands within WINDOW seconds of the last one adds
	to the streak; a longer pause starts again. Tiers name a streak and pick
	its colour. Display only (the server's combat is not affected).
	Pure module, unit-tested.
]]

export type State = { count: number, lastAt: number }

local HitStreak = {}

HitStreak.WINDOW = 2.5
-- Shown from this many hits (one hit is not a combo).
HitStreak.SHOW_FROM = 2

-- Tier names from the lowest streak up.
HitStreak.TIERS = table.freeze({
	{ from = 2, name = "COMBO" },
	{ from = 10, name = "GREAT" },
	{ from = 25, name = "AMAZING" },
	{ from = 50, name = "LEGENDARY" },
})

function HitStreak.new(): State
	return { count = 0, lastAt = -math.huge }
end

-- One hit landed at `now`: returns the new streak.
function HitStreak.hit(state: State, now: number): number
	if now - state.lastAt > HitStreak.WINDOW then
		state.count = 0
	end
	state.count += 1
	state.lastAt = now
	return state.count
end

-- Whether the streak is still running at `now`.
function HitStreak.alive(state: State, now: number): boolean
	return state.count >= HitStreak.SHOW_FROM and now - state.lastAt <= HitStreak.WINDOW
end

-- Tier index (1..#TIERS) and name for a streak (0, "" below SHOW_FROM).
function HitStreak.tier(count: number): (number, string)
	local index, name = 0, ""
	for i, tier in HitStreak.TIERS do
		if count >= tier.from then
			index, name = i, tier.name
		end
	end
	return index, name
end

return table.freeze(HitStreak)
