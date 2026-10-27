--[[
	D-118: gear wears, breaks (stats stop counting, never destroyed) and is
	repaired for Gold.
]]
local load = require("../loader")
local DurabilityRules = load("src/shared/Logic/DurabilityRules")
local ItemRules = load("src/shared/Logic/ItemRules")
local ItemDefinitions = load("src/shared/Definitions/ItemDefinitions")
local Defaults = load("src/server/Config/Defaults")

return function(t)
	t.describe("Durability (D-118)", function()
		local c = Defaults.Durability

		t.it("old items count as new; wear crosses low then broken once", function()
			t.eq(DurabilityRules.of({}), DurabilityRules.MAX)
			local item: any = { Durability = 21 }
			local after, crossed = DurabilityRules.wear(item, 1)
			t.eq(after, 20)
			t.eq(crossed, "low")
			item.Durability = after
			local after2, crossed2 = DurabilityRules.wear(item, 0.5)
			t.eq(crossed2, nil, "low is told once")
			item.Durability = 0.4
			local after3, crossed3 = DurabilityRules.wear(item, 1)
			t.eq(after3, 0)
			t.eq(crossed3, "broken")
			item.Durability = 0
			local _, crossed4 = DurabilityRules.wear(item, 1)
			t.eq(crossed4, nil, "already broken")
			t.ok(after2 < 20)
		end)

		t.it("weapons wear faster than armor; PvP defeats don't wear by default", function()
			t.ok(DurabilityRules.killWear(c, "Weapon", true) > DurabilityRules.killWear(c, "Chest", false))
			t.eq(DurabilityRules.defeatWear(c, true), 0)
			t.eq(DurabilityRules.defeatWear(c, false), DurabilityRules.MAX * c.DefeatWearPct / 100)
			local off = table.clone(c)
			off.Enabled = false
			t.eq(DurabilityRules.killWear(off, "Weapon", true), 0)
		end)

		t.it("repair costs more for rarer, higher and more worn gear; full costs nothing", function()
			t.eq(DurabilityRules.repairCost(c, { Rarity = "Rare", ItemLevel = 5 }), 0)
			local rare = DurabilityRules.repairCost(c, { Rarity = "Rare", ItemLevel = 5, Durability = 50 })
			local legend =
				DurabilityRules.repairCost(c, { Rarity = "Legendary", ItemLevel = 5, Durability = 50 })
			local high = DurabilityRules.repairCost(c, { Rarity = "Rare", ItemLevel = 25, Durability = 50 })
			local worse = DurabilityRules.repairCost(c, { Rarity = "Rare", ItemLevel = 5, Durability = 0 })
			t.ok(rare > 0 and legend > rare and high > rare and worse > rare)
		end)

		t.it("a broken worn piece adds no stats; repaired it counts again", function()
			local def = ItemDefinitions.defFor("Warrior", "Weapon", "Sword", 5) :: any
			local item: any = {
				Guid = "g",
				DefId = def.id,
				Rarity = "Rare",
				ItemLevel = 5,
				Attributes = {},
				Enhancement = 0,
				Locked = false,
				Source = "Test",
				CreatedAt = 0,
				Durability = 0,
			}
			local broken = ItemRules.gearTotals({ Weapon = "g" }, { g = item })
			t.eq(broken.Attack, 0)
			item.Durability = 1
			local fixed = ItemRules.gearTotals({ Weapon = "g" }, { g = item })
			t.ok(fixed.Attack > 0)
		end)
	end)
end
