--[[
	D-120: the Fortune Wheel: value-weighted odds that add up to 100, rarer
	prizes less likely, free spins per day, bonus attribute points.
]]
local load = require("../loader")
local RouletteRules = load("src/shared/Logic/RouletteRules")
local AttributeRules = load("src/shared/Logic/AttributeRules")
local ItemDefinitions = load("src/shared/Definitions/ItemDefinitions")
local Defaults = load("src/server/Config/Defaults")

return function(t)
	t.describe("Fortune Wheel (D-120)", function()
		local c = Defaults.Roulette
		local w = c.Weights

		t.it("default odds are valid and the valuable prizes are the rare ones", function()
			t.ok(RouletteRules.validate(w))
			t.ok(w.ThankYou >= w.Standard and w.Standard >= w.Rare, "thank-you, common, rare most likely")
			for _, rare in { "Consumable", "Attribute", "Level", "Legendary" } do
				t.ok(w[rare] < w.Rare, `{rare} rarer than Rare gear`)
			end
			t.ok(w.Legendary <= w.Consumable and w.Level <= w.Consumable)
			local bad = table.clone(w)
			bad.ThankYou += 1
			t.ok(not RouletteRules.validate(bad), "must add up to 100")
			t.ok(c.GoldPerSpin > 0, "extra spins cost Gold")
		end)

		t.it("picks follow the weights across the roll range", function()
			t.eq(RouletteRules.pick(w, 0), "ThankYou")
			t.eq(RouletteRules.pick(w, 0.999), "Legendary")
			local counts = {}
			for i = 0, 999 do
				local prize = RouletteRules.pick(w, i / 1000)
				counts[prize] = (counts[prize] or 0) + 1
			end
			for _, prize in RouletteRules.PRIZES do
				t.eq(counts[prize] or 0, w[prize] * 10, `{prize} share`)
			end
		end)

		t.it("free spins reset each day; consumables are real items", function()
			t.eq(RouletteRules.freeLeft(nil, c, 5), c.FreeSpinsPerDay)
			t.eq(RouletteRules.freeLeft({ Day = 5, Used = c.FreeSpinsPerDay }, c, 5), 0)
			t.eq(RouletteRules.freeLeft({ Day = 4, Used = 9 }, c, 5), c.FreeSpinsPerDay)
			for _, prize in RouletteRules.CONSUMABLES do
				t.ok(prize.id == "Buff" or ItemDefinitions.stackable(prize.id) ~= nil, prize.id)
			end
		end)

		t.it("bonus attribute points add on top of spent ones", function()
			local both = AttributeRules.combine(
				{ REC = 2, INT = 0, WIS = 0, STR = 5, AGI = 0 },
				{ STR = 1, AGI = 3 }
			)
			t.eq(both.STR, 6)
			t.eq(both.AGI, 3)
			t.eq(both.REC, 2)
			t.eq(AttributeRules.combine(nil, nil).INT, 0)
		end)
	end)
end
