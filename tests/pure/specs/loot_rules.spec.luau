--[[
	Dungeon loot (Phase 10, PLAN.md D-06 / D-07 / D-67) and PvP loot
	(Phase 14, D-76): table validation, 1M-roll distributions within ±0.5%,
	the piece that drops, boss claims paying once.
]]

local load = require("../loader")
local LootRules = load("src/shared/Logic/LootRules")
local Schema = load("src/shared/Logic/Schema")
local ConfigCore = load("src/server/Config/ConfigCore")
local Defaults = load("src/server/Config/Defaults")
local buildSchema = load("src/server/Config/ConfigSchema")
local RewardClaims = load("src/server/Persistence/RewardClaims")
local DungeonRules = load("src/shared/Logic/DungeonRules")

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

		t.it("PvP tables are valid and match CLAUDE.md §15", function()
			local boss = Defaults.Loot.Tables.WarZoneBoss
			t.ok((LootRules.validate(boss)))
			t.eq(boss.DropChancePct, 100)
			t.eq(boss.Rarity.Mythical, 20)
			t.eq(boss.Rarity.Rare, 80)
			for _, id in LootRules.STONE_TABLE_IDS do
				t.ok((LootRules.validateStones(Defaults.Loot.StoneTables[id])), id)
			end
			local mob = Defaults.Loot.StoneTables.WarZoneMob
			t.eq(mob.Stones.PerfectStone, 30)
			t.eq(mob.Stones.EnhancementStone, 70)
		end)

		t.it("rejects invalid stone tables", function()
			local function why(tbl)
				return select(2, LootRules.validateStones(tbl))
			end
			t.eq(why({ DropChancePct = 25, Stones = { PerfectStone = 30, EnhancementStone = 60 } }), "sum")
			t.eq(why({ DropChancePct = 25, Stones = { GoldBar = 100 } }), "stone")
			t.eq(why({ DropChancePct = -1, Stones = { PerfectStone = 100 } }), "chance")
			t.eq(
				why({ DropChancePct = 25, Stones = { PerfectStone = 0 / 0, EnhancementStone = 100 } }),
				"stone"
			)
			t.eq(why({ DropChancePct = 25 }), "shape")
			-- A rarity table is not a stone table (and the other way round).
			t.eq(why(Defaults.Loot.Tables.WarZoneBoss), "shape")
			t.eq(select(2, LootRules.validate(Defaults.Loot.StoneTables.WarZoneMob)), "shape")
		end)

		t.it("1M rolls: PvP boss 20% Mythical / 80% Rare, stones 30% / 70% within ±0.5%", function()
			local random = lcg(1407)
			local n = 1000000
			local boss = Defaults.Loot.Tables.WarZoneBoss
			local counts = {}
			for _ = 1, n do
				local rarity = LootRules.roll(boss, random(), random())
				t.ok(rarity == "Rare" or rarity == "Mythical", "always Rare or Mythical")
				counts[rarity :: string] = (counts[rarity :: string] or 0) + 1
			end
			t.ok(math.abs(counts.Mythical / n * 100 - 20) < 0.5, `mythical {counts.Mythical / n * 100}%`)
			t.ok(math.abs(counts.Rare / n * 100 - 80) < 0.5, `rare {counts.Rare / n * 100}%`)

			local mob = Defaults.Loot.StoneTables.WarZoneMob
			local drops = 0
			for _ = 1, n do
				if LootRules.rollStone(mob, random(), random()) then
					drops += 1
				end
			end
			t.ok(math.abs(drops / n * 100 - mob.DropChancePct) < 0.5, `stone drop {drops / n * 100}%`)
			local perfect = 0
			for _ = 1, n do
				local stone = LootRules.rollStone(mob, 0, random())
				t.ok(stone == "PerfectStone" or stone == "EnhancementStone")
				if stone == "PerfectStone" then
					perfect += 1
				end
			end
			t.ok(math.abs(perfect / n * 100 - 30) < 0.5, `perfect {perfect / n * 100}%`)
			-- Edges: a 0% table never drops; the last roll value stays in range.
			t.eq(LootRules.rollStone({ DropChancePct = 0, Stones = { EnhancementStone = 100 } }, 0, 0.5), nil)
			t.eq(LootRules.rollStone(mob, 0, 0.9999999), "PerfectStone")
		end)

		t.it("a PvP boss spawn pays each player once (loot and Marks share the claim)", function()
			local data = { ClaimedRewardIds = {}, Wallet = { PvPMarks = 0 } }
			local id = `B:{DungeonRules.runId("job-1", 3)}:Ammit:L`
			t.ok(RewardClaims.isValidId(id), id)
			local function pay(d)
				d.Wallet.PvPMarks += 10
			end
			t.eq(RewardClaims.claim(data, id, 1000, pay), "granted")
			t.eq(RewardClaims.claim(data, id, 1001, pay), "already")
			t.eq(data.Wallet.PvPMarks, 10)
			-- The next spawn of the same boss is a new claim.
			t.eq(RewardClaims.claim(data, `B:{DungeonRules.runId("job-1", 4)}:Ammit:L`, 1002, pay), "granted")
			t.eq(data.Wallet.PvPMarks, 20)
		end)

		t.it("drops a piece of the player's own class and realm", function()
			local random = lcg(5)
			local slots = {}
			for _ = 1, 5000 do
				local def = LootRules.pickPiece("Warrior", "Angel", 15, random(), random()) :: any
				t.ok(def ~= nil and def.job == "Warrior" and def.tier == 2)
				slots[def.slot] = true
			end
			for _, slot in
				{
					"Weapon",
					"Helm",
					"Shoulders",
					"Chest",
					"Hands",
					"Legs",
					"Boots",
					"Shield",
					"Necklace",
					"Earrings",
					"Ring",
				}
			do
				t.ok(slots[slot], slot)
			end
			t.eq(LootRules.itemLevelFor(40), 30)
			t.eq(LootRules.itemLevelFor(-2), 0)
		end)
	end)
end
