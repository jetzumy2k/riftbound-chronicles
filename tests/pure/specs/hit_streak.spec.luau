--[[
	D-103 stage C: the on-screen combo counter.
]]
local load = require("../loader")
local HitStreak = load("src/shared/Logic/HitStreak")

return function(t)
	t.describe("HitStreak", function()
		t.it("counts hits inside the window and restarts after a pause", function()
			local s = HitStreak.new()
			t.eq(HitStreak.hit(s, 0), 1)
			t.eq(HitStreak.hit(s, 1), 2)
			t.eq(HitStreak.hit(s, 3.4), 3, "2.4 s later still counts")
			t.eq(HitStreak.hit(s, 6.5), 1, "a 3.1 s pause starts again")
		end)

		t.it("shows only real combos and hides once the streak ends", function()
			local s = HitStreak.new()
			HitStreak.hit(s, 0)
			t.ok(not HitStreak.alive(s, 0), "one hit is not a combo")
			HitStreak.hit(s, 0.5)
			t.ok(HitStreak.alive(s, 1))
			t.ok(not HitStreak.alive(s, 0.5 + HitStreak.WINDOW + 0.01))
		end)

		t.it("tiers climb with the streak and always have a name", function()
			t.eq(select(1, HitStreak.tier(1)), 0)
			t.eq(select(2, HitStreak.tier(2)), "COMBO")
			t.eq(select(2, HitStreak.tier(12)), "GREAT")
			t.eq(select(2, HitStreak.tier(30)), "AMAZING")
			t.eq(select(2, HitStreak.tier(99)), "LEGENDARY")
			local last = 0
			for _, tier in HitStreak.TIERS do
				t.ok(tier.from > last and #tier.name > 0)
				last = tier.from
			end
		end)
	end)
end
