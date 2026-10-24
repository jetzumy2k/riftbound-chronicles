local load = require("../loader")
local WorldBudget = load("src/shared/Logic/WorldBudget")

return function(t)
	t.describe("WorldBudget", function()
		t.it("every kind has a budget with every field", function()
			for _, kind in WorldBudget.KINDS do
				local budget = WorldBudget.BUDGETS[kind]
				t.ok(budget ~= nil, kind)
				for _, field in WorldBudget.FIELDS do
					t.ok(type(budget[field]) == "number" and budget[field] >= 0, `{kind}.{field}`)
				end
			end
		end)

		t.it("capital part budget stays near D-37's 1,000 parts", function()
			t.ok(WorldBudget.BUDGETS.Capital.parts <= 1500)
		end)

		t.it("an empty zone is within every budget", function()
			for _, kind in WorldBudget.KINDS do
				t.eq(#WorldBudget.over(kind, WorldBudget.empty()), 0)
			end
		end)

		t.it("over lists only the fields past their limit, in order", function()
			local counts = WorldBudget.empty()
			counts.parts = WorldBudget.BUDGETS.Capital.parts + 1
			counts.lights = WorldBudget.BUDGETS.Capital.lights
			counts.emitters = WorldBudget.BUDGETS.Capital.emitters + 3
			local over = WorldBudget.over("Capital", counts)
			t.eq(#over, 2)
			t.ok(string.find(over[1], "^parts ") ~= nil)
			t.ok(string.find(over[2], "^emitters ") ~= nil)
		end)

		t.it("summary shows use and share of each field", function()
			local counts = WorldBudget.empty()
			counts.parts = 700
			local line = WorldBudget.summary("Capital", counts)
			t.ok(string.find(line, "parts 700/1400 (50%)", 1, true) ~= nil, line)
			t.ok(string.find(line, "emitterRate 0/", 1, true) ~= nil, line)
		end)

		t.it("unknown kinds raise", function()
			t.throws(function()
				WorldBudget.over("Moon", WorldBudget.empty())
			end, "unknown zone kind")
		end)
	end)
end
