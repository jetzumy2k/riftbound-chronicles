--[[
	D-104: class passives (always on, no bar slot) and 3 skill points per level.
]]
local load = require("../loader")
local PassiveDefinitions = load("src/shared/Definitions/PassiveDefinitions")
local PassiveRules = load("src/shared/Logic/PassiveRules")
local SkillDefinitions = load("src/shared/Definitions/SkillDefinitions")
local SkillRules = load("src/shared/Logic/SkillRules")
local AttributeRules = load("src/shared/Logic/AttributeRules")
local Enums = load("src/shared/Enums")

local BASE = { MaxHP = 1000, Defense = 100, CritChancePct = 5, CritDamagePct = 1, HealingPowerPct = 0 }

return function(t)
	t.describe("PassiveDefinitions", function()
		t.it("every class has 3 passives at levels 5, 12 and 20 with known stats", function()
			local known = {}
			for _, stat in PassiveDefinitions.STATS do
				known[stat] = true
			end
			for _, job in Enums.Job do
				local list = PassiveDefinitions.forJob(job)
				t.eq(#list, 3, job)
				for index, passive in list do
					t.eq(passive.unlockLevel, PassiveDefinitions.UNLOCK_LEVELS[index])
					t.eq(passive.maxRank, 5)
					t.eq(SkillDefinitions.get(passive.id), nil, `{passive.id} clashes with a skill id`)
					for stat, value in passive.perRank do
						t.ok(known[stat] and value > 0, `{passive.id}.{stat}`)
					end
				end
			end
		end)

		t.it("strong tuning: about +20% of the main stat at rank 5, never above +30%", function()
			for _, id in PassiveDefinitions.IDS do
				local passive = PassiveDefinitions.get(id)
				for stat, value in passive.perRank do
					if stat ~= "Focus" and stat ~= "CritDamagePct" then
						t.ok(value * 5 <= 30, `{id}.{stat}`)
					end
				end
			end
			t.eq(PassiveRules.totals({ WarriorMight = 5 }, "Warrior").DamagePct, 20)
		end)
	end)

	t.describe("PassiveRules", function()
		t.it("adds learned passives of the own job only, ranks clamped", function()
			local stats = PassiveRules.applyTo(BASE, { IronBody = 5, ArcaneMastery = 5 }, "Warrior")
			t.eq(stats.MaxHP, 1250)
			t.ok(math.abs(stats.Defense - 115) < 1e-6)
			t.eq(stats.DamagePct, 0, "a Mage passive does nothing for a Warrior")
			local clamped = PassiveRules.totals({ WarriorMight = 99 }, "Warrior")
			t.eq(clamped.DamagePct, 20)
			t.eq(PassiveRules.applyTo(BASE, {}, "Warrior"), BASE, "nothing learned: same table")
		end)

		t.it("crit, healing, Focus and a capped dodge", function()
			local archer = PassiveRules.applyTo(BASE, { HawkSight = 5, FleetFoot = 5 }, "Archer")
			t.eq(archer.CritChancePct, 20)
			t.eq(archer.CritDamagePct, 41)
			local dodgy = PassiveRules.applyTo(
				table.freeze({ MaxHP = 1, Defense = 1, EvasionPct = 9 }),
				{ FleetFoot = 5 },
				"Archer"
			)
			t.eq(dodgy.EvasionPct, AttributeRules.EVASION_CAP_PCT)
			t.eq(PassiveRules.applyTo(BASE, { HolyDevotion = 5 }, "Healer").HealingPowerPct, 25)
			t.eq(PassiveRules.applyTo(BASE, { ManaFlow = 5 }, "Mage").FocusBonus, 40)
		end)

		t.it("describes the bonus at a rank", function()
			local lines = PassiveRules.describe(PassiveDefinitions.get("IronBody"), 2)
			t.eq(lines[1], "+10% Max HP")
			t.eq(lines[2], "+6% Defense")
			t.eq(#PassiveRules.describe(PassiveDefinitions.get("IronBody"), 0), 0)
		end)
	end)

	t.describe("learning passives", function()
		t.it("uses skill points, the level gate and rank caps; own class only", function()
			local function reason(owned, level, id)
				return select(2, SkillRules.canLearn("Warrior", owned, level, 0, false, id))
			end
			t.eq(reason({}, 4, "WarriorMight"), "locked")
			t.ok(SkillRules.canLearn("Warrior", {}, 5, 0, false, "WarriorMight"))
			t.eq(reason({ WarriorMight = 1 }, 5, "WarriorMight"), "rankLocked")
			t.ok(SkillRules.canLearn("Warrior", { WarriorMight = 1 }, 6, 0, false, "WarriorMight"))
			t.eq(reason({}, 30, "HawkSight"), "wrongJob")
			t.eq(reason({ WarriorMight = 5 }, 30, "WarriorMight"), "maxRank")
			t.eq(SkillRules.spent({ WarriorMight = 3, CleavingStrike = 2 }), 5)
		end)

		t.it("level 30 affords a full build plus every passive, never the whole tree", function()
			local build = 6 * 5 + 3 + 3 -- six skills at rank 5, an ultimate, prerequisites
			local passives = 3 * PassiveDefinitions.MAX_RANK
			t.ok(SkillRules.pointsFor(30) >= build + passives)
			local tree = 0
			for _, skill in SkillDefinitions.forJob("Warrior") do
				tree += skill.maxRank
			end
			t.ok(SkillRules.pointsFor(30) < tree + passives)
		end)

		t.it("fitToLevel keeps passives the level opens and trims the rest", function()
			local out, changed = SkillRules.fitToLevel({ WarriorMight = 5, BattleInstinct = 1 }, 12)
			t.ok(changed)
			t.eq(out.WarriorMight, 3)
			t.eq(out.BattleInstinct, nil)
		end)
	end)
end
