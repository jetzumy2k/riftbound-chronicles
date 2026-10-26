local load = require("../loader")
local XPTable = load("src/shared/Logic/XPTable")
local EnemyDefinitions = load("src/shared/Definitions/EnemyDefinitions")
local ItemRules = load("src/shared/Logic/ItemRules")
local MallDefinitions = load("src/shared/Definitions/MallDefinitions")
local BossBalance = load("src/shared/Logic/BossBalance")

-- Phase 20 balance decisions (PLAN.md D-95, docs/balance/BALANCE_REVIEW.md).
return function(t)
	t.describe("Balance (D-95)", function()
		t.it("creature EXP: generous early, strict late", function()
			t.near(XPTable.creatureScale(0), 0.2, 1e-9)
			t.ok(XPTable.creatureScale(30) < 0.011, "about 1% at level 30")
			for level = 1, 30 do
				t.ok(XPTable.creatureScale(level) < XPTable.creatureScale(level - 1), "falls every level")
			end
			-- A level-matched creature is a few percent of a level, not a quarter.
			local wolf = EnemyDefinitions.get("RiftWolf")
			local share = EnemyDefinitions.xpAt(wolf, 1) / XPTable.toNext(1)
			t.ok(share > 0.02 and share < 0.1, `Rift Wolf at level 1: {share}`)
			local knight = EnemyDefinitions.get("AbyssalKnight")
			local late = EnemyDefinitions.xpAt(knight, 26) / XPTable.toNext(26)
			t.ok(late < 0.02, `Abyssal Knight at 26: {late}`)
			t.ok(EnemyDefinitions.xpAt(wolf, 0) >= 1, "never zero")
		end)

		t.it("regular creatures hit twice as hard, elites 1.5x, bosses unchanged", function()
			t.near(EnemyDefinitions.get("RiftWolf").attackScale, 0.9 * 2, 1e-9)
			t.near(EnemyDefinitions.get("MagmaGolem").attackScale, 1.1 * 1.5, 1e-9)
			for _, enemy in EnemyDefinitions.ById do
				if enemy.tier then
					t.ok(enemy.attackScale < 50, `{enemy.id} keeps its BossBalance hit`)
				end
			end
		end)

		t.it("Archer armour rolls defence", function()
			local stats = {}
			for _, entry in ItemRules.POOLS.Gear.Archer do
				stats[entry.stat] = entry.weight
			end
			t.ok(stats.MaxHP and stats.Defense, "Max HP and Defense in the pool")
			t.eq(stats.Attack, 2)
			t.eq(stats.CritChance, 2)
		end)

		t.it("the Mall sells only the Legendary set", function()
			for _, entry in MallDefinitions.CATALOG do
				if entry.grant.kind == "Set" then
					t.eq(entry.grant.rarity, "Legendary", entry.id)
				end
			end
			t.eq(MallDefinitions.get("MythicalSet"), nil)
		end)

		t.it("the Mall sells only Perfect Stones (D-99: no Robux into a chance-based upgrade)", function()
			for _, entry in MallDefinitions.CATALOG do
				if entry.grant.kind == "Stackable" then
					t.ok(entry.grant.id ~= "EnhancementStone", `{entry.id} sells plain Enhancement Stones`)
				end
			end
			t.ok(MallDefinitions.get("Perfect1") ~= nil, "Perfect Stones still sold")
		end)

		t.it("bosses are sized for a normally geared player", function()
			t.near(BossBalance.GEAR_FACTOR, 1.15, 1e-9)
		end)
	end)
end
