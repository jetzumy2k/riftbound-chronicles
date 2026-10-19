--[[
	Level gap EXP rule (PLAN.md D-63, Logic/LevelGap).
]]

local load = require("../loader")
local LevelGap = load("src/shared/Logic/LevelGap")

return function(t)
	t.describe("LevelGap", function()
		t.it("puts every gap in the creator's bracket", function()
			local cases = {
				{ 25, "Deadly" },
				{ 20, "Deadly" },
				{ 19, "Higher" },
				{ 15, "Higher" },
				{ 10, "Higher" },
				{ 9, "High" },
				{ 5, "High" },
				{ 4, "Medium" },
				{ 2, "Medium" },
				{ 1, "Normal" },
				{ 0, "Normal" },
				{ -4, "Normal" },
				{ -5, "Minimal" },
				{ -9, "Minimal" },
				{ -10, "Trivial" },
				{ -29, "Trivial" },
			}
			for _, case in cases do
				local gap, expected = case[1], case[2]
				t.eq(LevelGap.tierFor(10 + gap, 10).id, expected, `gap {gap}`)
			end
		end)

		t.it("scales EXP: none at the extremes, more for stronger creatures", function()
			t.eq(LevelGap.scaleXp(100, 30, 10), 0, "20 above")
			t.eq(LevelGap.scaleXp(100, 20, 10), 150, "10 above")
			t.eq(LevelGap.scaleXp(100, 15, 10), 130, "5 above")
			t.eq(LevelGap.scaleXp(100, 12, 10), 115, "2 above")
			t.eq(LevelGap.scaleXp(100, 10, 10), 100, "equal")
			t.eq(LevelGap.scaleXp(100, 5, 10), 25, "5 below")
			t.eq(LevelGap.scaleXp(100, 0, 10), 0, "10 below")
			t.eq(LevelGap.scaleXp(1, 5, 10), 1, "a rewarding tier never rounds to 0")
			t.eq(LevelGap.scaleXp(0, 10, 10), 0, "nothing stays nothing")
		end)

		t.it("multipliers rise with danger until the deadly cliff", function()
			local order = { "Trivial", "Minimal", "Normal", "Medium", "High", "Higher" }
			for i = 2, #order do
				t.ok(LevelGap.Tiers[order[i]].percent > LevelGap.Tiers[order[i - 1]].percent, order[i])
			end
			t.eq(LevelGap.Tiers.Deadly.percent, 0)
		end)
	end)
end
