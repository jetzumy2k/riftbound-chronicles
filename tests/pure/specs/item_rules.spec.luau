--[[
	Items and gear (Phase 7, PLAN.md D-64): definitions, attribute rolls,
	bounds, saved-item repair, gear stats, equip rules, salvage.
]]

local load = require("../loader")
local ItemDefinitions = load("src/shared/Definitions/ItemDefinitions")
local ItemRules = load("src/shared/Logic/ItemRules")
local StatFormulas = load("src/shared/Logic/StatFormulas")
local Enums = load("src/shared/Enums")

local RARITIES = { "Standard", "Uncommon", "Rare", "Epic", "Legendary", "Mythical" }

-- Deterministic [0, 1) generator (LCG) so the fuzz is repeatable.
local function lcg(seed: number): () -> number
	local state = seed
	return function()
		state = (state * 1103515245 + 12345) % 2147483648
		return state / 2147483648
	end
end

local function item(def: any, rarity: string, level: number, attributes: any): any
	return {
		Guid = "12345678-90AB-CDEF-1234-567890ABCDEF",
		DefId = def.id,
		Rarity = rarity,
		ItemLevel = level,
		Attributes = attributes,
		Enhancement = 0,
		Locked = false,
		Source = "Test",
		CreatedAt = 0,
	}
end

return function(t)
	t.describe("ItemDefinitions", function()
		t.it("covers every job, slot and tier with valid families", function()
			for _, job in { "Warrior", "Healer", "Archer", "Mage" } do
				for tier = 1, ItemDefinitions.TIERS do
					local level = ItemDefinitions.TIER_LEVELS[tier][1]
					for _, slot in Enums.ItemSlot do
						if slot == "Weapon" then
							for _, family in ItemDefinitions.familiesOf(job) do
								local def = ItemDefinitions.defFor(job, slot, family, level)
								t.ok(def ~= nil and def.tier == tier, `{job} {family} T{tier}`)
								t.ok(Enums.has(Enums.WeaponType, family), family)
							end
						else
							local def = ItemDefinitions.defFor(job, slot, nil, level)
							t.ok(def ~= nil and def.slot == slot, `{job} {slot} T{tier}`)
						end
					end
				end
			end
			t.eq(ItemDefinitions.tierFor(0), 1)
			t.eq(ItemDefinitions.tierFor(9), 1)
			t.eq(ItemDefinitions.tierFor(10), 2)
			t.eq(ItemDefinitions.tierFor(30), 3)
			t.ok(#ItemDefinitions.IDS >= 90)
		end)

		t.it("every pool is large enough for a Mythical roll", function()
			for _, group in ItemRules.POOLS do
				for job, entries in group do
					t.ok(#entries >= ItemRules.ROLLS.Mythical, job)
					for _, entry in entries do
						t.ok(ItemRules.STATS[entry.stat] ~= nil and entry.weight > 0, entry.stat)
					end
				end
			end
		end)
	end)

	t.describe("ItemRules.roll", function()
		t.it("100k rolls never leave the pool or the rarity's bounds", function()
			local random = lcg(7)
			local ids = ItemDefinitions.IDS
			for n = 1, 100000 do
				local def = ItemDefinitions.All[ids[(n % #ids) + 1]]
				local rarity = RARITIES[(n % #RARITIES) + 1]
				local level = def.minItemLevel
					+ math.floor(random() * (def.maxItemLevel - def.minItemLevel + 1))
				local attributes = ItemRules.roll(def, rarity, level, random)
				if #attributes ~= ItemRules.ROLLS[rarity] then
					t.ok(false, `count {def.id} {rarity}`)
					return
				end
				local seen = {}
				local pool = {}
				for _, entry in ItemRules.poolFor(def) do
					pool[entry.stat] = true
				end
				for _, attribute in attributes do
					local lo, hi = ItemRules.bounds(attribute.Stat, rarity, level)
					if
						not pool[attribute.Stat]
						or seen[attribute.Stat]
						or attribute.Value < lo
						or attribute.Value > hi
					then
						t.ok(
							false,
							`{def.id} {rarity} L{level} {attribute.Stat}={attribute.Value} [{lo},{hi}]`
						)
						return
					end
					seen[attribute.Stat] = true
				end
			end
			t.ok(true)
		end)

		t.it("rolled items pass repair untouched", function()
			local random = lcg(99)
			for _, id in ItemDefinitions.IDS do
				local def = ItemDefinitions.All[id]
				for _, rarity in RARITIES do
					local level = def.maxItemLevel
					local saved = item(def, rarity, level, ItemRules.roll(def, rarity, level, random))
					local keep, notes = ItemRules.repairItem(saved.Guid, saved)
					if not keep or #notes > 0 then
						t.ok(false, `{id} {rarity}: {table.concat(notes, "; ")}`)
						return
					end
				end
			end
			t.ok(true)
		end)

		t.it("higher rarity means more and bigger attributes", function()
			for i = 2, #RARITIES do
				t.ok(ItemRules.ROLLS[RARITIES[i]] >= ItemRules.ROLLS[RARITIES[i - 1]])
				local _, hiPrev = ItemRules.bounds("Attack", RARITIES[i - 1], 20)
				local _, hi = ItemRules.bounds("Attack", RARITIES[i], 20)
				t.ok(hi > hiPrev, RARITIES[i])
			end
			local _, low = ItemRules.bounds("Attack", "Rare", 0)
			local _, high = ItemRules.bounds("Attack", "Rare", 30)
			t.ok(high > low * 10, "flat stats grow with item level")
			local _, critLow = ItemRules.bounds("CritChance", "Rare", 0)
			local _, critHigh = ItemRules.bounds("CritChance", "Rare", 30)
			t.eq(critLow, critHigh, "percent stats don't")
		end)
	end)

	t.describe("ItemRules gear stats", function()
		local sword = ItemDefinitions.All.W_Warrior_Sword_T2
		local chest = ItemDefinitions.All.A_Warrior_Chest_T2
		local helm = ItemDefinitions.All.A_Warrior_Helm_T2

		t.it("weapons give attack, armor defense; enhancement follows CLAUDE.md §10", function()
			local plain = ItemRules.baseStats(sword, "Rare", 15, 0)
			local plus3 = ItemRules.baseStats(sword, "Rare", 15, 3)
			t.ok(plain.Attack > 0 and plain.Defense == 0)
			t.eq(plus3.Attack - plain.Attack, 60)
			t.eq(plus3.CritDamage, 7.5)
			local armor = ItemRules.baseStats(chest, "Rare", 15, 0)
			local armor2 = ItemRules.baseStats(chest, "Rare", 15, 2)
			t.ok(armor.Defense > 0 and armor.MaxHP > 0 and armor.Attack == 0)
			t.eq(armor2.Defense - armor.Defense, 16)
			t.eq(armor2.Attack, 0, "armor never gains attack")
		end)

		t.it("totals only count items in their own slot, and percent stats cap", function()
			local a = item(sword, "Rare", 15, { { Stat = "CritChance", Value = 25 } })
			a.Guid = "a"
			local b = item(chest, "Rare", 15, { { Stat = "Mitigation", Value = 20 } })
			b.Guid = "b"
			local c = item(helm, "Rare", 15, { { Stat = "Mitigation", Value = 20 } })
			c.Guid = "c"
			local inventory = { a = a, b = b, c = c }
			local totals =
				ItemRules.gearTotals({ Weapon = "a", Chest = "b", Helm = "c", Boots = "a" }, inventory)
			t.eq(totals.Mitigation, ItemRules.STATS.Mitigation.cap)
			t.eq(totals.CritChance, 25, "the sword counts once (not in Boots)")
			local base = StatFormulas.forLevel(15)
			local stats = ItemRules.withGear(base, totals)
			t.eq(stats.Attack, base.Attack + totals.Attack)
			t.eq(stats.CritChancePct, base.CritChancePct + 25)
			t.eq(stats.CritMultiplier, 1.5 + stats.CritDamagePct / 100)
			t.eq(stats.MitigationPct, 25)
		end)

		t.it("equip checks job, race weapon family and level", function()
			local axe = item(ItemDefinitions.All.W_Warrior_Axe_T1, "Standard", 5, {})
			t.ok((ItemRules.canEquip(axe, "Warrior", "Devil", 5)))
			t.eq(select(2, ItemRules.canEquip(axe, "Warrior", "Angel", 5)), "race")
			t.eq(select(2, ItemRules.canEquip(axe, "Mage", "Devil", 5)), "job")
			t.eq(select(2, ItemRules.canEquip(axe, "Warrior", "Devil", 4)), "level")
		end)

		t.it("salvage yields fragments by rarity", function()
			t.eq(ItemRules.salvageYield(item(sword, "Standard", 10, {})), 1)
			t.eq(ItemRules.salvageYield(item(sword, "Mythical", 10, {})), 15)
		end)

		t.it("gear look: worn slots with tier, rarity and weapon family (D-65)", function()
			local GearLook = load("src/shared/Logic/GearLook")
			local axe = item(ItemDefinitions.All.W_Warrior_Axe_T3, "Mythical", 25, {})
			axe.Guid = "axe"
			local boots = item(ItemDefinitions.All.A_Warrior_Boots_T1, "Standard", 2, {})
			boots.Guid = "boots"
			local look = GearLook.fromEquipment(
				{ Weapon = "axe", Boots = "boots", Helm = "missing", Chest = "axe" },
				{ axe = axe, boots = boots }
			)
			t.eq(look.Weapon.family, "Axe")
			t.eq(look.Weapon.tier, 3)
			t.eq(look.Weapon.rarity, "Mythical")
			t.eq(look.Boots.tier, 1)
			t.eq(look.Helm, nil, "missing item draws nothing")
			t.eq(look.Chest, nil, "a weapon in the chest slot draws nothing")
			t.eq(GearLook.RARITY_GLOW.Standard, nil, "Standard gear doesn't glow")
			t.ok(GearLook.SPARKLE.Mythical and not GearLook.SPARKLE.Rare)
		end)

		t.it("formats stats for display", function()
			t.eq(ItemRules.formatStat("Attack", 12), "+12 Attack")
			t.eq(ItemRules.formatStat("CritChance", 1.5), "+1.5% Crit Chance")
			t.eq(ItemRules.formatStat("CritDamage", 2), "+2% Crit Damage")
		end)
	end)
end
