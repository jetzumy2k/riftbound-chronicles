--[[
	D-106: four healing potion sizes (shared cooldown) and the quick
	button's pick; D-105: the Scroll of Relearning.
]]
local load = require("../loader")
local PotionRules = load("src/shared/Logic/PotionRules")
local ItemDefinitions = load("src/shared/Definitions/ItemDefinitions")
local MallDefinitions = load("src/shared/Definitions/MallDefinitions")

return function(t)
	t.describe("PotionRules", function()
		t.it("30 / 50 / 75 / 90% sizes, weakest first", function()
			local sizes = {}
			for _, id in PotionRules.IDS do
				table.insert(sizes, PotionRules.pctOf(id))
				t.ok(table.find(ItemDefinitions.CONSUMABLE_IDS, id) ~= nil, id)
			end
			t.eq(table.concat(sizes, ","), "30,50,75,90")
			t.ok(not PotionRules.isPotion("RebirthScroll"))
		end)

		t.it("picks the smallest potion that covers the missing HP, else the biggest", function()
			local have = { HealingPotion = 2, MajorHealingPotion = 1, SupremeHealingPotion = 1 }
			t.eq(PotionRules.pick(have, 10), "HealingPotion")
			t.eq(PotionRules.pick(have, 45), "MajorHealingPotion")
			t.eq(PotionRules.pick(have, 95), "SupremeHealingPotion")
			t.eq(PotionRules.pick({ HealingPotion = 1 }, 80), "HealingPotion")
			t.eq(PotionRules.pick({}, 50), nil)
			t.eq(PotionRules.count(have), 4)
		end)

		t.it("bigger potions cost more Mall Points per potion", function()
			local last = 0
			for _, entryId in { "Potions10", "GreaterPotions10", "MajorPotions10", "SupremePotions10" } do
				local entry = MallDefinitions.get(entryId)
				t.ok(entry ~= nil and entry.price > last, entryId)
				last = entry.price
			end
		end)
	end)

	t.describe("Scroll of Relearning", function()
		t.it("is a consumable that resets skills and is sold in the Mall", function()
			local def = ItemDefinitions.stackable("RelearnScroll")
			t.eq(def.use.kind, "SkillReset")
			t.eq(MallDefinitions.get("Relearn").grant.id, "RelearnScroll")
		end)
	end)
end
