--[[
	Enhancement (Phase 8, PLAN.md D-08 / D-66): rates, the +10 cap, one
	stone per attempt, no downgrade on failure, Perfect Stones.
]]

local load = require("../loader")
local EnhanceRules = load("src/shared/Logic/EnhanceRules")
local ItemDefinitions = load("src/shared/Definitions/ItemDefinitions")
local ItemRules = load("src/shared/Logic/ItemRules")

return function(t)
	t.describe("EnhanceRules", function()
		t.it("follows D-08: +1..+5 sure, then 90/80/70/60/50, 0 at +10", function()
			local expected = { 100, 100, 100, 100, 100, 90, 80, 70, 60, 50 }
			for level = 0, 9 do
				t.eq(EnhanceRules.rateFor(level), expected[level + 1], `+{level}`)
				t.eq(EnhanceRules.rateFor(level, nil, true), 100, "perfect")
			end
			t.eq(EnhanceRules.rateFor(10), 0)
			t.eq(EnhanceRules.rateFor(10, nil, true), 0, "perfect can't pass the cap")
			t.eq(EnhanceRules.rateFor(6, { 1, 2, 3 }), 80, "a malformed table falls back")
		end)

		t.it("20 requests in one frame use exactly the stones there are", function()
			local item = { Enhancement = 0 }
			local stacks = { EnhancementStone = 5 }
			local done = 0
			for _ = 1, 20 do
				if EnhanceRules.attempt(item, stacks, false, 0) then
					done += 1
				end
			end
			t.eq(done, 5)
			t.eq(item.Enhancement, 5)
			t.eq(stacks.EnhancementStone, nil, "none left, never negative")
		end)

		t.it("can never pass +10, even with stones left", function()
			local item = { Enhancement = 0 }
			local stacks = { EnhancementStone = 100, PerfectStone = 100 }
			for i = 1, 40 do
				EnhanceRules.attempt(item, stacks, i % 2 == 0, 0)
			end
			t.eq(item.Enhancement, 10)
			t.eq(
				stacks.EnhancementStone + stacks.PerfectStone,
				200 - 10,
				"only successful-or-tried attempts consumed"
			)
			local result, reason = EnhanceRules.attempt(item, stacks, false, 0)
			t.eq(result, nil)
			t.eq(reason, "max")
		end)

		t.it("a failure keeps the level and uses one stone", function()
			local item = { Enhancement = 7 }
			local stacks = { EnhancementStone = 3 }
			local result = EnhanceRules.attempt(item, stacks, false, 0.99) :: any
			t.eq(result.success, false)
			t.eq(item.Enhancement, 7, "never downgraded")
			t.eq(stacks.EnhancementStone, 2)
			t.eq(result.rate, 70)
		end)

		t.it("a Perfect Stone always succeeds and uses only itself", function()
			local item = { Enhancement = 9 }
			local stacks = { EnhancementStone = 4, PerfectStone = 1 }
			local result = EnhanceRules.attempt(item, stacks, true, 0.999) :: any
			t.eq(result.success, true)
			t.eq(item.Enhancement, 10)
			t.eq(stacks.EnhancementStone, 4)
			t.eq(stacks.PerfectStone, nil)
			t.eq(select(2, EnhanceRules.attempt({ Enhancement = 2 }, {}, true, 0)), "noStone")
		end)

		t.it("success rates match the table over many rolls", function()
			local seed = 11
			local function random()
				seed = (seed * 1103515245 + 12345) % 2147483648
				return seed / 2147483648
			end
			local wins = 0
			for _ = 1, 20000 do
				local result = EnhanceRules.attempt(
					{ Enhancement = 9 },
					{ EnhancementStone = 1 },
					false,
					random()
				) :: any
				if result.success then
					wins += 1
				end
			end
			t.ok(math.abs(wins / 20000 - 0.5) < 0.02, `+10 rate {wins / 20000}`)
		end)

		t.it("each +1: weapon +20 Attack +2.5% crit damage, armor +8 Defense only", function()
			local sword = ItemDefinitions.All.W_Archer_Bow_T3
			local boots = ItemDefinitions.All.A_Mage_Boots_T3
			local ring = ItemDefinitions.All.A_Healer_Accessory_T3
			local w0, w10 =
				ItemRules.baseStats(sword, "Epic", 25, 0), ItemRules.baseStats(sword, "Epic", 25, 10)
			t.eq(w10.Attack - w0.Attack, 200)
			t.eq(w10.CritDamage - w0.CritDamage, 25)
			t.eq(w10.Defense, 0)
			for _, def in { boots, ring } do
				local a0, a10 =
					ItemRules.baseStats(def, "Epic", 25, 0), ItemRules.baseStats(def, "Epic", 25, 10)
				t.eq(a10.Defense - a0.Defense, 80)
				t.eq(a10.Attack, 0, "armor never gains attack")
				t.eq(a10.CritDamage, 0)
			end
		end)
	end)
end
