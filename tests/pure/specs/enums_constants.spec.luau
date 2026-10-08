local load = require("../loader")
local Enums = load("src/shared/Enums")
local Constants = load("src/shared/Constants")

return function(t)
	t.describe("Enums", function()
		t.it("Rarity is ordered lowest to highest (D-22)", function()
			local expected = { "Standard", "Uncommon", "Rare", "Legendary", "Mythical" }
			t.eq(#Enums.Rarity, #expected)
			for i, name in expected do
				t.eq(Enums.Rarity[i], name)
			end
		end)

		t.it("has() accepts members and rejects everything else", function()
			t.ok(Enums.has(Enums.Race, "Angel"))
			t.ok(Enums.has(Enums.Job, "Archer"))
			t.ok(not Enums.has(Enums.Race, "angel"))
			t.ok(not Enums.has(Enums.Race, nil))
			t.ok(not Enums.has(Enums.Race, 1))
			t.ok(not Enums.has(Enums.Race, {}))
		end)

		t.it("indexOf() returns positions", function()
			t.eq(Enums.indexOf(Enums.Rarity, "Rare"), 3)
			t.eq(Enums.indexOf(Enums.Rarity, "Nope"), nil)
		end)

		t.it("enums are frozen", function()
			t.ok(table.isfrozen(Enums))
			t.ok(table.isfrozen(Enums.Race))
			t.throws(function()
				(Enums.Race :: any)[3] = "Human"
			end)
		end)

		t.it("ItemSlot matches D-25", function()
			t.eq(table.concat(Enums.ItemSlot, ","), "Weapon,Helm,Chest,Legs,Boots,Accessory")
		end)
	end)

	t.describe("Constants match CLAUDE.md", function()
		t.it("levels 0..30", function()
			t.eq(Constants.Level.Min, 0)
			t.eq(Constants.Level.Max, 30)
		end)

		t.it("base stats (§5)", function()
			t.eq(Constants.BaseStats.HP, 200)
			t.eq(Constants.BaseStats.Defense, 50)
			t.eq(Constants.BaseStats.Attack, 100)
			t.eq(Constants.BaseStats.CritDamagePct, 0.05)
			t.eq(Constants.BaseStats.HPRegenPct, 0.02)
		end)

		t.it("growth (§5)", function()
			t.eq(Constants.StatGrowth.HPMultiplier, 1.20)
			t.eq(Constants.StatGrowth.AttackMultiplier, 1.10)
			t.eq(Constants.StatGrowth.DefenseMultiplier, 1.08)
			t.eq(Constants.StatGrowth.CritDamagePctPerLevel, 0.05)
			t.eq(Constants.StatGrowth.HPRegenPctPerLevel, 0.02)
		end)

		t.it("loadout and enhancement (§7, §10)", function()
			t.eq(Constants.Loadout.RegularSlots, 3)
			t.eq(Constants.Loadout.SpecialSlots, 1)
			t.eq(Constants.Enhancement.Max, 10)
			t.eq(Constants.Enhancement.WeaponAttackPerLevel, 20)
			t.eq(Constants.Enhancement.CritDamagePctPerLevel, 2.5)
			t.eq(Constants.Enhancement.ArmorDefensePerLevel, 8)
		end)
	end)
end
