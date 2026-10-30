--!strict
--[[
	TowerRules — the Tower Challenge (creator request 2026-10-30, PLAN.md
	D-131). Pure.

	Two floors per level band, A and a harder B:

	  band   levels  points   creatures (the dungeon floor of that band)
	  1      1-10    2        Rift Wolf, Crystal Beetle, Stoneback Guardian
	  2      11-20   3        Ember Hound, Cinder Scarab, Magma Golem
	  3      21-30   4        Rime Stalker, Abyss Crawler, Abyssal Knight
	  4      31-40   4        Skeleton Soldier, Grave Ghoul, Death Knight
	  5      41-50   5        Ashbone Warrior, Cinder Husk, Dullahan
	  6      51-60   5        Wraithbone Sentry, Grave Knight, Dread Dullahan

	Bands 4-6 need the level 60 cap (12 floors with it on, 6 with it off).
	A floor is a run of creature waves in a sealed arena against the clock.

	Rewards (against farming):
	  - the first clear of a floor gives its points once per character
	    (reward claim T:<floor>): bonus attribute points the player spends
	    in the Attributes panel, at most MAX_POINTS in all;
	  - the week's 3 fastest clears of each floor (Monday 00:00 UTC to the
	    next) get the floor's points again once the week is over (claim
	    TW:<week>:<floor>). Only runs where nobody is above the band's top
	    level count for the week's board;
	  - a cleared floor can be run again for the board, never for points;
	    EXP from its creatures follows the usual level-gap rule.

	Opening: the Tower is open only while the "Tower Challenge" event runs.
	The admin's schedule (config Events.Tower: up to 3 UTC weekdays, a time
	and a length) starts that event by itself; the admin may also start or
	schedule it from the Events tab like any other event.
]]

local TowerRules = {}

export type Wave = { { enemy: string, count: number, hpScale: number? } }
export type Floor = {
	id: string,
	band: number,
	tier: string,
	name: string,
	minLevel: number,
	maxLevel: number,
	-- The creatures' level.
	level: number,
	points: number,
	needsCap: boolean,
	waves: { Wave },
	limitSeconds: number,
}
export type Schedule = { Enabled: boolean, Days: { number }, TimeUtcMinutes: number, Hours: number }
export type Window = { Id: string, StartsAt: number, EndsAt: number }

TowerRules.EVENT_ID = "TowerChallenge"
-- Bonus attribute points the Tower may give one character in all.
TowerRules.MAX_POINTS = 100
-- How many of the week's fastest clears of a floor earn its points again.
TowerRules.TOP = 3
-- A scheduled opening starts this long early as a "starting soon" event
-- (the usual 15-minute notice, D-114).
TowerRules.LEAD_SECONDS = 15 * 60
-- Party creatures get this much more health per extra player.
TowerRules.PARTY_HP_PER_PLAYER = 0.6
-- Seconds between the arrival and the first wave, and between waves.
TowerRules.COUNTDOWN_SECONDS = 5
TowerRules.WAVE_GAP_SECONDS = 3

local WEEK = 7 * 86400
-- 1970-01-05 00:00 UTC was a Monday.
local FIRST_MONDAY = 4 * 86400

local BANDS: { { any } } = {
	{ 1, 10, 2, "RiftWolf", "CrystalBeetle", "StonebackGuardian", "The Hollow Steps" },
	{ 11, 20, 3, "EmberHound", "CinderScarab", "MagmaGolem", "The Cinder Steps" },
	{ 21, 30, 4, "RimeStalker", "AbyssCrawler", "AbyssalKnight", "The Rime Steps" },
	-- D-133: the undead of the Abyssal Spire.
	{ 31, 40, 4, "SkeletonSoldier", "GraveGhoul", "DeathKnight", "The Bastion Steps" },
	{ 41, 50, 5, "AshboneWarrior", "CinderHusk", "Dullahan", "The Ashen Steps" },
	{ 51, 60, 5, "WraithboneSentry", "GraveKnight", "DreadDullahan", "The Starless Steps" },
}

local floors: { Floor } = {}
for band, b in BANDS do
	local minLevel, maxLevel, points, a, c, elite, name = b[1], b[2], b[3], b[4], b[5], b[6], b[7]
	-- A: four waves, the last an elite with extra health.
	table.insert(floors, {
		id = `{band}A`,
		band = band,
		tier = "A",
		name = `{name} · A`,
		minLevel = minLevel,
		maxLevel = maxLevel,
		level = maxLevel - 3,
		points = points,
		needsCap = minLevel > 30,
		waves = {
			{ { enemy = a, count = 4 } },
			{ { enemy = c, count = 4 } },
			{ { enemy = a, count = 3 }, { enemy = c, count = 2 } },
			{ { enemy = elite, count = 1, hpScale = 2.5 } },
		},
		limitSeconds = 6 * 60,
	})
	-- B: five waves at the band's top level, two elites and a champion.
	table.insert(floors, {
		id = `{band}B`,
		band = band,
		tier = "B",
		name = `{name} · B`,
		minLevel = minLevel,
		maxLevel = maxLevel,
		level = maxLevel,
		points = points,
		needsCap = minLevel > 30,
		waves = {
			{ { enemy = a, count = 5 } },
			{ { enemy = c, count = 5 } },
			{ { enemy = a, count = 3 }, { enemy = c, count = 3 } },
			{ { enemy = elite, count = 2, hpScale = 1.5 } },
			{ { enemy = elite, count = 1, hpScale = 4 }, { enemy = a, count = 3 } },
		},
		limitSeconds = 8 * 60,
	})
end
TowerRules.FLOORS = floors
TowerRules.IDS = {} :: { string }
TowerRules.ById = {} :: { [string]: Floor }
for _, f in floors do
	table.insert(TowerRules.IDS, f.id)
	TowerRules.ById[f.id] = f
end

function TowerRules.get(id: any): Floor?
	return if type(id) == "string" then TowerRules.ById[id] else nil
end

-- The floors that exist with the cap switch as it is (6 or 12).
function TowerRules.available(level60: boolean): { Floor }
	local out = {}
	for _, f in floors do
		if level60 or not f.needsCap then
			table.insert(out, f)
		end
	end
	return out
end

--[[
	Whether a player of `level` may start floor `f`. Returns (ok, reason):
	"cap" (needs the level 60 cap), "level" (below the band).
]]
function TowerRules.canEnter(f: Floor, level: number, level60: boolean): (boolean, string?)
	if f.needsCap and not level60 then
		return false, "cap"
	end
	if level < f.minLevel then
		return false, "level"
	end
	return true, nil
end

-- Whether a clear by players of these levels counts for the week's board.
function TowerRules.countsForBoard(f: Floor, levels: { number }): boolean
	for _, level in levels do
		if level > f.maxLevel then
			return false
		end
	end
	return #levels > 0
end

-- The creatures' health multiplier for a run of `players` players.
function TowerRules.partyHpScale(players: number): number
	return 1 + TowerRules.PARTY_HP_PER_PLAYER * math.max(0, players - 1)
end

-- Points a first clear (or a top-3 place) gives with `have` already.
function TowerRules.grantable(f: Floor, have: number): number
	return math.clamp(TowerRules.MAX_POINTS - have, 0, f.points)
end

-- Clear times are kept in tenths of a second.
function TowerRules.tenths(seconds: number): number
	return math.max(1, math.floor(seconds * 10 + 0.5))
end

function TowerRules.formatTenths(tenths: number): string
	local seconds = tenths // 10
	return string.format("%d:%02d.%d", seconds // 60, seconds % 60, tenths % 10)
end

--------------------------------------------------------------------------------
-- Weeks and the schedule (UTC)
--------------------------------------------------------------------------------

-- The week number of `now` (weeks start Monday 00:00 UTC).
function TowerRules.weekOf(now: number): number
	return (now - FIRST_MONDAY) // WEEK
end

-- When week `week` starts.
function TowerRules.weekStart(week: number): number
	return FIRST_MONDAY + week * WEEK
end

-- The UTC weekday of `t`: 1 Monday ... 7 Sunday.
function TowerRules.weekday(t: number): number
	return ((t // 86400) + 3) % 7 + 1
end

-- The usual spread for 1, 2 or 3 openings a week (weekday numbers).
TowerRules.SPREADS = table.freeze({
	table.freeze({ 6 }),
	table.freeze({ 3, 6 }),
	table.freeze({ 1, 3, 5 }),
})

-- A stored schedule made safe: 1-3 distinct weekdays, sorted.
function TowerRules.cleanDays(days: any): { number }
	local out = {}
	if type(days) == "table" then
		for _, d in days do
			if type(d) == "number" and d % 1 == 0 and d >= 1 and d <= 7 and not table.find(out, d) then
				table.insert(out, d)
			end
		end
	end
	table.sort(out)
	while #out > 3 do
		table.remove(out)
	end
	return out
end

-- The scheduled openings {startsAt, endsAt} that touch the days around `now`.
function TowerRules.openingsNear(schedule: Schedule, now: number, daysAhead: number?): { { number } }
	local out = {}
	if not schedule.Enabled then
		return out
	end
	local today = now // 86400
	for k = -1, daysAhead or 1 do
		local dayStart = (today + k) * 86400
		if table.find(schedule.Days, TowerRules.weekday(dayStart)) then
			local s = dayStart + schedule.TimeUtcMinutes * 60
			table.insert(out, { s, s + schedule.Hours * 3600 })
		end
	end
	return out
end

--[[
	The scheduled opening that should be started as an event at `now`, as
	(startsAt, endsAt), or nil: from LEAD_SECONDS before it until it ends,
	unless a Tower event already touches it (started, or stopped early by
	staff: a stopped opening is not started again).
]]
function TowerRules.due(windows: { Window }, schedule: Schedule, now: number): (number?, number?)
	for _, o in TowerRules.openingsNear(schedule, now) do
		local s, e = o[1], o[2]
		if now >= s - TowerRules.LEAD_SECONDS and now < e - 60 then
			local touched = false
			for _, w in windows do
				if
					w.Id == TowerRules.EVENT_ID
					and w.StartsAt < e
					and w.EndsAt > s - TowerRules.LEAD_SECONDS
				then
					touched = true
					break
				end
			end
			if not touched then
				return s, e
			end
		end
	end
	return nil, nil
end

-- The next scheduled opening still to end after `now`, or nil.
function TowerRules.nextOpening(schedule: Schedule, now: number): (number?, number?)
	for _, o in TowerRules.openingsNear(schedule, now, 8) do
		if o[2] > now then
			return o[1], o[2]
		end
	end
	return nil, nil
end

return TowerRules
