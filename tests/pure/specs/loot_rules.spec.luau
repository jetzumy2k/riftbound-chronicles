--[[
	Dungeon loot (Phase 10, PLAN.md D-06 / D-07 / D-67): table validation,
	1M-roll distributions within ±0.5%, the piece that drops.
]]

local load = require("../loader")
local LootRules = load("src/shared/Logic/LootRules")
local Schema = load("src/shared/Logic/Schema")
local ConfigCore = load("src/server/Config/ConfigCore")
local Defaults = load("src/server/Config/Defaults")
local buildSchema = load("src/server/Config/ConfigSchema")

-- Park-Miller generator: exact in doubles (products stay below 2^53).
local function lcg(seed: number): () -> number
	local state = seed
	return function()
		state = (state * 48271) % 2147483647
		return (state - 1) / 2147483646
	end
end

return function(t)
	t.describe("LootRules", function()
		t.it("the default tables are valid and match CLAUDE.md §12 / D-06 / D-07", function()
			local tables = Defaults.Loot.Tables
			for _, id in LootRules.TABLE_IDS do
				t.ok((LootRules.validate(tables[id])), id)
			end
			t.eq(tables.DungeonMob.Rarity.Rare, 30)
			t.eq(tables.DungeonMob.Rarity.Standard + tables.DungeonMob.Rarity.Uncommon, 70)
			t.eq(tables.DungeonBoss.Rarity.Legendary, 20)
			t.eq(tables.DungeonBoss.Rarity.Rare, 80)
			t.eq(tables.DungeonBoss.DropChancePct, 100)
			local ok = ConfigCore.resolve(Defaults, nil, buildSchema(Schema), Schema)
			t.ok(ok, "config schema accepts the defaults")
		end)

		t.it("rejects invalid tables", function()
			t.eq(
				select(2, LootRules.validate({ DropChancePct = 10, Rarity = { Rare = 50, Standard = 40 } })),
				"sum"
			)
			t.eq(select(2, LootRules.validate({ DropChancePct = 120, Rarity = { Rare = 100 } })), "chance")
			t.eq(select(2, LootRules.validate({ DropChancePct = 10, Rarity = { Godly = 100 } })), "rarity")
			t.eq(
				select(2, LootRules.validate({ DropChancePct = 10, Rarity = { Rare = -5, Epic = 105 } })),
				"rarity"
			)
			t.eq(select(2, LootRules.validate({ DropChancePct = 0 / 0, Rarity = { Rare = 100 } })), "chance")
			t.eq(select(2, LootRules.validate(nil)), "shape")
		end)

		t.it("1M rolls: drop chance and rarities within ±0.5%", function()
			local random = lcg(2024)
			local mob = Defaults.Loot.Tables.DungeonMob
			local counts = {}
			local drops = 0
			local n = 1000000
			for _ = 1, n do
				local rarity = LootRules.roll(mob, random(), random())
				if rarity then
					drops += 1
					counts[rarity] = (counts[rarity] or 0) + 1
				end
			end
			t.ok(math.abs(drops / n * 100 - mob.DropChancePct) < 0.5, `drop {drops / n * 100}%`)
			-- Rarity split given a drop, over 1M drops.
			local given = {}
			for _ = 1, n do
				local rarity = LootRules.roll(mob, 0, random()) :: string
				given[rarity] = (given[rarity] or 0) + 1
			end
			for rarity, weight in mob.Rarity do
				local pct = (given[rarity] or 0) / n * 100
				t.ok(math.abs(pct - weight) < 0.5, `{rarity} {pct}% vs {weight}%`)
			end
			local boss = Defaults.Loot.Tables.DungeonBoss
			local legendary, none = 0, 0
			for _ = 1, n do
				local rarity = LootRules.roll(boss, random(), random())
				if rarity == "Legendary" then
					legendary += 1
				elseif rarity == nil then
					none += 1
				end
			end
			t.eq(none, 0, "bosses always drop")
			t.ok(math.abs(legendary / n * 100 - 20) < 0.5, `legendary {legendary / n * 100}%`)
		end)

		t.it("drops a piece of the player's own class and realm", function()
			local random = lcg(5)
			local slots = {}
			for _ = 1, 5000 do
				local def = LootRules.pickPiece("Warrior", "Angel", 15, random(), random()) :: any
				t.ok(def ~= nil and def.job == "Warrior" and def.tier == 2)
				t.ok(def.family ~= "Axe", "Angels don't use axes")
				slots[def.slot] = true
			end
			for _, slot in { "Weapon", "Helm", "Chest", "Legs", "Boots", "Accessory" } do
				t.ok(slots[slot], slot)
			end
			t.eq(LootRules.itemLevelFor(40), 30)
			t.eq(LootRules.itemLevelFor(-2), 0)
		end)
	end)
end
