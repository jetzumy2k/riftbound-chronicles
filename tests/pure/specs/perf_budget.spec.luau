local load = require("../loader")
local PerfBudget = load("src/shared/Logic/PerfBudget")

return function(t)
	t.describe("PerfBudget", function()
		t.it("percentile and average", function()
			local samples = { 10, 20, 30, 40, 50, 60, 70, 80, 90, 100 }
			t.eq(PerfBudget.percentile(samples, 0.95), 100)
			t.eq(PerfBudget.percentile(samples, 0.5), 50)
			t.eq(PerfBudget.percentile({}, 0.95), 0)
			t.eq(PerfBudget.average(samples), 55)
			t.eq(samples[1], 10, "input not sorted in place")
		end)
		t.it("rates per player per second, safe with no players", function()
			t.eq(PerfBudget.rate(600, 10, 60), 1)
			t.eq(PerfBudget.rate(600, 0, 60), 0)
			t.eq(PerfBudget.rate(600, 10, 0), 0)
		end)
		t.it("reports every field over its limit", function()
			local report = {
				players = 30,
				frameAvgMs = 16.7,
				frameP95Ms = 30,
				memoryMb = 1200,
				outPerPlayerPerSecond = 12,
				inPerPlayerPerSecond = 40,
				characterParts = 290,
			}
			local overs = PerfBudget.check(report)
			t.eq(#overs, 2)
			t.eq(overs[1].field, "frameP95Ms")
			t.eq(overs[2].field, "inPerPlayerPerSecond")
		end)
		t.it("a full anime character fits the part budget (D-100 ~250-300)", function()
			t.ok(PerfBudget.LIMITS.characterParts >= 300)
		end)
	end)
end
