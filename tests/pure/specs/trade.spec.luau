--[[
	D-121: what may be traded (never Mall items, equipped or locked gear),
	offers checked against the owner, and both sides able to receive.
]]
local load = require("../loader")
local TradeRules = load("src/shared/Logic/TradeRules")
local ItemRules = load("src/shared/Logic/ItemRules")
local ItemDefinitions = load("src/shared/Definitions/ItemDefinitions")

local function profile(): { [string]: any }
	return {
		Wallet = { Gold = 1000, MallPoints = 500 },
		Inventory = {
			a = { Source = "Drop:x", Locked = false },
			b = { Source = "Mall:LegendarySet", Locked = false },
			c = { Source = "Drop:y", Locked = true },
			d = { Source = "Drop:z", Locked = false },
		},
		Equipment = { Weapon = "d" },
		Stackables = { HealingPotion = 10, RaceRune = 1, EnhancementStone = 3 },
	}
end

return function(t)
	t.describe("Trading (D-121)", function()
		t.it("earned gear, Gold and earned consumables can be offered", function()
			local ok = TradeRules.checkOffer(
				profile(),
				{ Gold = 500, Items = { "a" }, Stackables = { HealingPotion = 4, EnhancementStone = 3 } }
			)
			t.ok(ok)
		end)

		t.it("Mall items, locked or equipped gear and Mall-only consumables never", function()
			local data = profile()
			t.eq(
				select(2, TradeRules.checkOffer(data, { Gold = 0, Items = { "b" }, Stackables = {} })),
				"mall"
			)
			t.eq(
				select(2, TradeRules.checkOffer(data, { Gold = 0, Items = { "c" }, Stackables = {} })),
				"locked"
			)
			t.eq(
				select(2, TradeRules.checkOffer(data, { Gold = 0, Items = { "d" }, Stackables = {} })),
				"equipped"
			)
			t.eq(
				select(
					2,
					TradeRules.checkOffer(data, { Gold = 0, Items = {}, Stackables = { RaceRune = 1 } })
				),
				"mall"
			)
			t.ok(TradeRules.MALL_ONLY.Buff_Might, "buff draughts are Mall items")
		end)

		t.it("no more than you own, no duplicates", function()
			local data = profile()
			t.eq(select(2, TradeRules.checkOffer(data, { Gold = 1001, Items = {}, Stackables = {} })), "gold")
			t.eq(
				select(
					2,
					TradeRules.checkOffer(data, { Gold = 0, Items = {}, Stackables = { HealingPotion = 11 } })
				),
				"count"
			)
			t.eq(
				select(2, TradeRules.checkOffer(data, { Gold = 0, Items = { "a", "a" }, Stackables = {} })),
				"item"
			)
			t.eq(
				select(2, TradeRules.checkOffer(data, { Gold = 0, Items = { "zz" }, Stackables = {} })),
				"item"
			)
		end)

		t.it("both sides need room for what they get", function()
			local data = profile()
			local give = TradeRules.emptyOffer()
			local cap = ItemDefinitions.stackable("HealingPotion").maxStack
			local take = { Gold = 0, Items = {}, Stackables = { HealingPotion = cap - 9 } }
			t.eq(select(2, TradeRules.canReceive(data, give, take)), "full")
			local full = profile()
			for i = 1, ItemRules.INVENTORY_CAP do
				full.Inventory[`x{i}`] = {}
			end
			t.eq(
				select(2, TradeRules.canReceive(full, give, { Gold = 0, Items = { "n" }, Stackables = {} })),
				"bag"
			)
			t.ok(TradeRules.canReceive(profile(), give, { Gold = 0, Items = { "n" }, Stackables = {} }))
			t.ok(TradeRules.isEmpty(TradeRules.emptyOffer()))
		end)
	end)
end
