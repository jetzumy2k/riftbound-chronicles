--[[
	D-117: Merchant prices, sell-back, the Gold <-> Mall Points exchange and
	Gold from creatures.
]]
local load = require("../loader")
local ShopRules = load("src/shared/Logic/ShopRules")
local NpcDefinitions = load("src/shared/Definitions/NpcDefinitions")
local Defaults = load("src/server/Config/Defaults")

return function(t)
	t.describe("Shop (D-117)", function()
		local shop = Defaults.Shop
		local exchange = Defaults.Exchange

		t.it("sells Standard / Uncommon / Rare only, dearer by rarity and level", function()
			t.eq(ShopRules.gearPrice(shop, "Epic", 5), nil)
			t.eq(ShopRules.gearPrice(shop, "Legendary", 5), nil)
			local s0 = ShopRules.gearPrice(shop, "Standard", 0) :: number
			local u0 = ShopRules.gearPrice(shop, "Uncommon", 0) :: number
			local r0 = ShopRules.gearPrice(shop, "Rare", 0) :: number
			t.ok(s0 < u0 and u0 < r0)
			t.ok((ShopRules.gearPrice(shop, "Rare", 30) :: number) > r0 * 5, "level makes it dearer")
			t.eq(ShopRules.potionPrice(shop, 10), shop.PotionPrice * 10)
		end)

		t.it("buys back for less than it sells; enhancement adds value", function()
			for _, rarity in ShopRules.GEAR_RARITIES do
				for _, level in { 0, 10, 30 } do
					local buy = ShopRules.gearPrice(shop, rarity, level) :: number
					t.ok(
						ShopRules.sellPrice(shop, rarity, level, 0) < buy,
						`{rarity} L{level}: no buy-sell profit`
					)
				end
			end
			t.ok(ShopRules.sellPrice(shop, "Rare", 10, 10) > ShopRules.sellPrice(shop, "Rare", 10, 0))
			t.ok(ShopRules.sellPrice(shop, "Mythical", 10, 0) > ShopRules.sellPrice(shop, "Rare", 10, 0))
		end)

		t.it("exchanges both ways at the admin ratios, within the daily limits", function()
			local gold, ok = ShopRules.exchange(exchange, "ToGold", 10, 0)
			t.ok(ok)
			t.eq(gold, 10 * exchange.GoldPerMallPoint)
			local cost, ok2 = ShopRules.exchange(exchange, "ToMallPoints", 10, 0)
			t.ok(ok2)
			t.eq(cost, 10 * exchange.GoldForMallPoint)
			t.ok(exchange.GoldForMallPoint > exchange.GoldPerMallPoint, "no Gold <-> MP round-trip profit")
			local _, ok3, why =
				ShopRules.exchange(exchange, "ToMallPoints", 1, exchange.DailyGoldToMallPoints)
			t.ok(not ok3)
			t.eq(why, "daily")
			local _, ok4, why4 = ShopRules.exchange(exchange, "ToGold", 0, 0)
			t.ok(not ok4)
			t.eq(why4, "amount")
			local closed = table.clone(exchange)
			closed.Enabled = false
			t.ok(not select(2, ShopRules.exchange(closed, "ToGold", 1, 0)))
			t.eq(ShopRules.day(86400 * 3 + 5), 3)
		end)

		t.it("creatures drop Gold split like EXP; NPCs are defined", function()
			t.eq(ShopRules.killGold(100, 25, 1), 25)
			t.eq(ShopRules.killGold(100, 25, 2), 12)
			t.eq(ShopRules.killGold(1, 25, 4), 1, "at least 1 each")
			t.eq(ShopRules.killGold(100, 0, 1), 0)
			t.ok(NpcDefinitions.get("Merchant") ~= nil and NpcDefinitions.get("Exchanger") ~= nil)
			for _, npc in NpcDefinitions.List do
				t.ok(npc.names.Angel ~= nil and npc.names.Devil ~= nil, `{npc.id} named in both realms`)
			end
		end)
	end)
end
