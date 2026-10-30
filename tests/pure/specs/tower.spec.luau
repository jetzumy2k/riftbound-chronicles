--[[
	D-131: the Tower Challenge: 12 floors (6 without the level 60 cap) with
	the band's points, real creatures, entry and board rules, the points
	cap, Monday weeks and the weekly schedule that opens it.
]]
local load = require("../loader")
local TowerRules = load("src/shared/Logic/TowerRules")
local EnemyDefinitions = load("src/shared/Definitions/EnemyDefinitions")
local EventDefinitions = load("src/shared/Definitions/EventDefinitions")
local EventRules = load("src/shared/Logic/EventRules")
local AttributeRules = load("src/shared/Logic/AttributeRules")
local RewardClaims = load("src/server/Persistence/RewardClaims")

-- 2026-11-02 00:00 UTC is a Monday.
local MONDAY = 1793577600

return function(t)
	t.describe("Tower Challenge (D-131)", function()
		t.it("two floors per band with the band's points; 31+ need the cap", function()
			t.eq(#TowerRules.FLOORS, 12)
			t.eq(#TowerRules.available(false), 6)
			t.eq(#TowerRules.available(true), 12)
			local points = { 2, 3, 4, 4, 5, 5 }
			for _, f in TowerRules.FLOORS do
				t.eq(f.points, points[f.band], f.id)
				t.eq(f.needsCap, f.minLevel > 30, f.id)
				t.ok(f.level >= f.minLevel and f.level <= f.maxLevel, `{f.id} creature level`)
			end
			local a, b = TowerRules.get("1A"), TowerRules.get("1B")
			t.ok(#b.waves > #a.waves, "B is harder")
			t.ok(b.level > a.level, "B creatures are higher")
		end)

		t.it("every wave uses a real creature", function()
			for _, f in TowerRules.FLOORS do
				for _, wave in f.waves do
					for _, group in wave do
						t.ok(EnemyDefinitions.get(group.enemy) ~= nil, `{f.id}: {group.enemy}`)
						t.ok(group.count >= 1)
					end
				end
				-- Bands past 30 use the gentle (level 31-60) creatures.
				local first = EnemyDefinitions.get(f.waves[1][1].enemy)
				t.eq(first.gentle == true, f.needsCap, `{f.id} gentle`)
			end
		end)

		t.it("entry needs the band's level and the cap; the board only counts in-band runs", function()
			local f = TowerRules.get("4A")
			t.eq(select(2, TowerRules.canEnter(f, 40, false)), "cap")
			t.eq(select(2, TowerRules.canEnter(f, 30, true)), "level")
			t.ok(TowerRules.canEnter(f, 31, true))
			t.ok(TowerRules.canEnter(TowerRules.get("1A"), 25, false), "over-levelled may enter")
			t.ok(TowerRules.countsForBoard(TowerRules.get("1A"), { 10, 8 }))
			t.ok(not TowerRules.countsForBoard(TowerRules.get("1A"), { 10, 11 }), "one above the band")
			t.ok(not TowerRules.countsForBoard(TowerRules.get("1A"), {}))
		end)

		t.it("points stop at the cap; they add to the spendable attribute points", function()
			local f = TowerRules.get("6B")
			t.eq(TowerRules.grantable(f, 0), 5)
			t.eq(TowerRules.grantable(f, 98), 2)
			t.eq(TowerRules.grantable(f, TowerRules.MAX_POINTS), 0)
			local total = 0
			for _, floor in TowerRules.FLOORS do
				total += floor.points
			end
			t.ok(total < TowerRules.MAX_POINTS, "first clears alone stay under the cap")
			t.eq(AttributeRules.pointsFor(10, 6), 56)
			local ok, result = AttributeRules.spend(AttributeRules.empty(), { STR = 55 }, 10, 6)
			t.ok(ok)
			t.eq(select(2, AttributeRules.spend(result, { AGI = 2 }, 10, 6)), "points")
			local kept, changed = AttributeRules.repair(result, 10, 6)
			t.eq(kept.STR, 55)
			t.ok(not changed)
			t.eq(AttributeRules.spent((AttributeRules.repair(result, 10, 0))), 0, "points gone: all back")
		end)

		t.it("claim ids are valid; first clears never expire", function()
			t.ok(RewardClaims.isValidId("T:1A"))
			t.ok(RewardClaims.isValidId("TW:2913:6B"))
			t.eq(RewardClaims.RETENTION_SECONDS.T, false)
		end)

		t.it("weeks start Monday 00:00 UTC; weekdays count from Monday", function()
			t.eq(TowerRules.weekday(MONDAY), 1)
			t.eq(TowerRules.weekday(MONDAY + 6 * 86400 + 3600), 7)
			t.eq(TowerRules.weekStart(TowerRules.weekOf(MONDAY)), MONDAY)
			t.eq(TowerRules.weekOf(MONDAY - 1), TowerRules.weekOf(MONDAY) - 1)
			t.eq(TowerRules.weekOf(MONDAY + 7 * 86400 - 1), TowerRules.weekOf(MONDAY))
			t.eq(TowerRules.formatTenths(754), "1:15.4")
			t.eq(TowerRules.tenths(75.44), 754)
		end)

		t.it("the schedule opens on its days, 15 minutes early, once", function()
			local schedule = { Enabled = true, Days = { 1, 3, 5 }, TimeUtcMinutes = 12 * 60, Hours = 3 }
			local noon = MONDAY + 12 * 3600
			-- Too early, then the 15-minute lead, then during, then over.
			t.eq(TowerRules.due({}, schedule, noon - 3600), nil)
			local s, e = TowerRules.due({}, schedule, noon - 10 * 60)
			t.eq(s, noon)
			t.eq(e, noon + 3 * 3600)
			t.eq(TowerRules.due({}, schedule, noon + 3600), noon)
			t.eq(TowerRules.due({}, schedule, noon + 3 * 3600), nil)
			-- Tuesday: not a Tower day.
			t.eq(TowerRules.due({}, schedule, noon + 86400), nil)
			-- Already started (or stopped early by staff): not again.
			local started = { { Id = "TowerChallenge", StartsAt = noon, EndsAt = noon + 3 * 3600 } }
			t.eq(TowerRules.due(started, schedule, noon + 60), nil)
			local stopped = { { Id = "TowerChallenge", StartsAt = noon, EndsAt = noon + 600 } }
			t.eq(TowerRules.due(stopped, schedule, noon + 3600), nil)
			-- Another event doesn't block it; off means never.
			t.eq(
				TowerRules.due(
					{ { Id = "DoubleExp", StartsAt = noon, EndsAt = noon + 99999 } },
					schedule,
					noon
				),
				noon
			)
			schedule.Enabled = false
			t.eq(TowerRules.due({}, schedule, noon), nil)
			t.eq(TowerRules.nextOpening(schedule, noon), nil)
		end)

		t.it("next opening and the usual spreads", function()
			local schedule = { Enabled = true, Days = { 6 }, TimeUtcMinutes = 600, Hours = 2 }
			local s = TowerRules.nextOpening(schedule, MONDAY)
			t.eq(s, MONDAY + 5 * 86400 + 600 * 60)
			t.eq(#TowerRules.SPREADS[1], 1)
			t.eq(#TowerRules.SPREADS[3], 3)
			t.eq(#TowerRules.cleanDays({ 5, 1, 1, 9, 3, 2 }), 3)
			t.eq(TowerRules.cleanDays({ 5, 1, 3 })[1], 1)
		end)

		t.it("the Tower Challenge event: ready, no cooldown, never drawn daily", function()
			local e = EventDefinitions.get(TowerRules.EVENT_ID)
			t.ok(e ~= nil)
			t.ok(EventDefinitions.isReady(e))
			t.eq(e.cooldownMinutes, 0)
			local daily = { Enabled = true, TimeUtcMinutes = 720, Minutes = 60, Excluded = {} }
			local picks = EventRules.dailyCandidates({}, daily, MONDAY, MONDAY)
			t.ok(table.find(picks, TowerRules.EVENT_ID) == nil)
			t.ok(#picks > 0)
		end)
	end)
end
