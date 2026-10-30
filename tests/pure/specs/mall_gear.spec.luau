--[[
	D-124: Item Mall gear sold separately (armor package / weapon /
	off-hand / accessory), Legendary only, at a level tier the buyer picks;
	gear can't be worn below its level.
]]
local load = require("../loader")
local MallGear = load("src/shared/Logic/MallGear")
local MallDefinitions = load("src/shared/Definitions/MallDefinitions")
local ItemRules = load("src/shared/Logic/ItemRules")

return function(t)
	t.describe("Mall gear (D-124)", function()
		t.it("the armor package is only helm, shoulders, armor, gloves, pants, boots", function()
			local pieces = MallGear.pieces("Mage", "Angel", "Set", 10) :: any
			t.eq(#pieces, 6)
			local slots = {}
			for _, p in pieces do
				table.insert(slots, p.def.slot)
				t.eq(p.itemLevel, 10)
			end
			table.sort(slots)
			t.eq(table.concat(slots, ","), "Boots,Chest,Hands,Helm,Legs,Shoulders")
		end)

		t.it("weapons, off-hands and accessories are separate, and checked", function()
			local families = MallGear.families("Warrior", "Angel")
			local weapon = MallGear.pieces("Warrior", "Angel", "Weapon", 20, { Family = families[1] }) :: any
			t.eq(#weapon, 1)
			t.eq(weapon[1].def.slot, "Weapon")
			t.eq(select(2, MallGear.pieces("Warrior", "Angel", "Weapon", 20, { Family = "Wand" })), "family")
			local shield = MallGear.pieces("Warrior", "Angel", "OffHand", 20) :: any
			t.eq(shield[1].def.slot, "Shield")
			t.eq(select(2, MallGear.pieces("Mage", "Angel", "OffHand", 20)), "noOffHand")
			local ring = MallGear.pieces("Archer", "Devil", "Accessory", 0, { Piece = "Ring" }) :: any
			t.eq(ring[1].def.slot, "Ring")
			t.eq(select(2, MallGear.pieces("Archer", "Devil", "Accessory", 0, { Piece = "Hat" })), "piece")
		end)

		t.it("every Mall gear entry is Legendary", function()
			for _, entry in MallDefinitions.CATALOG do
				if MallGear.KINDS[entry.grant.kind] then
					t.eq(entry.grant.rarity, "Legendary", entry.id)
				end
			end
		end)

		t.it("level tiers: default is the highest reached; only listed tiers", function()
			t.eq(MallGear.defaultBracket(0), 0)
			t.eq(MallGear.defaultBracket(17), 10)
			t.eq(MallGear.defaultBracket(30), 30)
			t.eq(MallGear.bracketOf(nil, 23), 20)
			t.eq(MallGear.bracketOf({ Bracket = 30 }, 5), 30, "can buy ahead")
			t.eq(select(2, MallGear.bracketOf({ Bracket = 15 }, 20)), "bracket")
		end)

		t.it("gear can't be worn below its level", function()
			local pieces = MallGear.pieces("Mage", "Angel", "Set", 30) :: any
			local item: any = { DefId = pieces[1].def.id, ItemLevel = 30, Rarity = "Legendary" }
			t.eq(select(2, ItemRules.canEquip(item, "Mage", "Angel", 29)), "level")
			t.ok(ItemRules.canEquip(item, "Mage", "Angel", 30))
		end)
		t.it(
			"level 60 cap: gear tiers 4-6, Mall tiers 40-60 and drops follow the live cap (D-129)",
			function()
				local ItemDefinitions = load("src/shared/Definitions/ItemDefinitions")
				local LootRules = load("src/shared/Logic/LootRules")
				local LevelCap = load("src/shared/Logic/LevelCap")
				t.eq(ItemDefinitions.tierFor(45), 5)
				t.ok(ItemDefinitions.defFor("Mage", "Chest", nil, 55) ~= nil, "Lv 55 armor exists")
				t.eq(#MallGear.levels(30), 4)
				t.eq(#MallGear.levels(60), 7)
				t.eq(
					select(2, MallGear.bracketOf({ Bracket = 40 }, 30, 30)),
					"bracket",
					"no Lv 40 gear while the cap is 30"
				)
				t.eq(LootRules.itemLevelFor(45), 30, "cap 30: drops stay wearable")
				t.eq(LootRules.itemLevelFor(45, 60), 45)
				t.eq(LevelCap.gearLevel(30), 30)
				t.near(LevelCap.gearLevel(40), 33, 1e-9)
				t.eq(LevelCap.of(true), 60)
				t.eq(LevelCap.of(false), 30)
			end
		)
	end)
end
