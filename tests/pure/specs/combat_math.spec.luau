local load = require("../loader")
local CombatMath = load("src/shared/Logic/CombatMath")
local StatFormulas = load("src/shared/Logic/StatFormulas")
local BasicAttacks = load("src/shared/Definitions/BasicAttacks")
local Enums = load("src/shared/Enums")
local Defaults = load("src/server/Config/Defaults")

local C = Defaults.Combat

local function hit(attackerLevel, defenderLevel, roll, coefficient)
	local a = StatFormulas.forLevel(attackerLevel)
	local d = StatFormulas.forLevel(defenderLevel)
	return CombatMath.damage({
		attack = a.Attack,
		attackerLevel = attackerLevel,
		coefficient = coefficient or 1,
		critChancePct = a.CritChancePct,
		critMultiplier = a.CritMultiplier,
		roll = roll or 0.99,
		defense = d.Defense,
	}, C)
end

local function baseFacts()
	return {
		sameEntity = false,
		attackerIsPlayer = true,
		targetIsPlayer = true,
		attackerRace = "Angel",
		targetRace = "Devil",
		attackerInSafeZone = false,
		targetInSafeZone = false,
		attackerDefeated = false,
		targetDefeated = false,
		targetProtected = false,
	}
end

return function(t)
	t.describe("D-01 power scale", function()
		t.it("is 1 at level 0 and ~3.967 at level 30", function()
			t.near(CombatMath.powerScale(0, C), 1, 1e-9)
			t.near(CombatMath.powerScale(30, C), 3.967, 0.001)
		end)

		t.it("keeps even fights within PLAN.md Appendix B (hits before defense)", function()
			-- Appendix B: L0 2.0, L10 3.0, L20 4.5, L30 6.9 basic hits (no defense).
			local expected = { [0] = 2.0, [10] = 3.0, [20] = 4.5, [30] = 6.9 }
			for level, hits in expected do
				local s = StatFormulas.forLevel(level)
				local raw = s.Attack * CombatMath.powerScale(level, C)
				t.near(s.MaxHP / raw, hits, 0.1, `L{level}`)
			end
		end)
	end)

	t.describe("damage", function()
		t.it("defense mitigates ~20% at L0 and ~35% at L30 (D-05)", function()
			local k0 = CombatMath.defenseK(0, C)
			t.near(1 - CombatMath.mitigate(100, 50, k0) / 100, 0.2, 0.001)
			local k30 = CombatMath.defenseK(30, C)
			local def30 = StatFormulas.forLevel(30).Defense
			t.near(1 - CombatMath.mitigate(100, def30, k30) / 100, 0.346, 0.01)
		end)

		t.it("an even L0 fight takes 3 basic Warrior hits; L30 takes ~11", function()
			local d0 = hit(0, 0)
			t.eq(math.ceil(StatFormulas.forLevel(0).MaxHP / d0), 3)
			local d30 = hit(30, 30)
			local hits30 = math.ceil(StatFormulas.forLevel(30).MaxHP / d30)
			t.ok(hits30 >= 9 and hits30 <= 12, tostring(hits30))
		end)

		t.it("crits multiply by the crit multiplier (D-02) on a low roll (D-03)", function()
			local normal, critA = hit(10, 10, 0.99)
			local critical, critB = hit(10, 10, 0.01)
			t.eq(critA, false)
			t.eq(critB, true)
			t.near(critical / normal, StatFormulas.forLevel(10).CritMultiplier, 0.02)
		end)

		t.it("crit chance is exactly 5%: rolls below 0.05 crit", function()
			t.ok(CombatMath.isCrit(5, 0.0499))
			t.ok(not CombatMath.isCrit(5, 0.05))
			t.ok(not CombatMath.isCrit(0, 0))
			t.ok(CombatMath.isCrit(100, 0.9999))
		end)

		t.it("damage is a whole number and never below 1", function()
			local dmg = CombatMath.damage({
				attack = 1,
				attackerLevel = 0,
				coefficient = 0.01,
				critChancePct = 0,
				critMultiplier = 1.5,
				roll = 0.5,
				defense = 1e9,
			}, C)
			t.eq(dmg, 1)
			local d = hit(5, 3)
			t.eq(d % 1, 0)
		end)
	end)

	t.describe("healing and regen", function()
		t.it("healing scales with level and never goes negative", function()
			local s = StatFormulas.forLevel(10)
			local heal = CombatMath.heal({
				attack = s.Attack,
				attackerLevel = 10,
				coefficient = 0.8,
				critChancePct = 0,
				critMultiplier = s.CritMultiplier,
				roll = 0.5,
			}, C)
			t.eq(heal, math.floor(s.Attack * 0.8 * CombatMath.powerScale(10, C) + 0.5))
		end)

		t.it("regen uses CLAUDE.md §5 percent of max HP per second", function()
			local s = StatFormulas.forLevel(30)
			t.near(CombatMath.regen(s.MaxHP, s.HPRegenPct, 1), s.MaxHP * 0.0062, 1e-6)
			t.eq(CombatMath.regen(100, 1, -5), 0)
		end)
	end)

	t.describe("range", function()
		t.it("allows range + tolerance, compensates ping up to the cap", function()
			t.ok(CombatMath.withinRange(12, 8, 0, 0, C))
			t.ok(not CombatMath.withinRange(12.1, 8, 0, 0, C))
			-- 0.2 s ping at 16 studs/s adds 3.2 studs.
			t.ok(CombatMath.withinRange(15, 8, 0.2, 16, C))
			-- Spoofed huge ping is capped at 0.3 s.
			t.ok(not CombatMath.withinRange(30, 8, 10, 16, C))
		end)
	end)

	t.describe("who can harm whom", function()
		t.it("opposite races can fight outside safe zones", function()
			t.ok((CombatMath.canHarm(baseFacts())))
		end)

		t.it("blocks self, same race, safe zones (both ways), protection and defeated", function()
			local cases = {
				{ "sameEntity", true, "self" },
				{ "targetRace", "Angel", "sameRace" },
				{ "attackerInSafeZone", true, "safeZone" },
				{ "targetInSafeZone", true, "safeZone" },
				{ "targetProtected", true, "protected" },
				{ "attackerDefeated", true, "attackerDefeated" },
				{ "targetDefeated", true, "targetDefeated" },
			}
			for _, case in cases do
				local facts = baseFacts()
				facts[case[1]] = case[2]
				local ok, reason = CombatMath.canHarm(facts)
				t.eq(ok, false, case[1])
				t.eq(reason, case[3], case[1])
			end
		end)

		t.it("training NPCs are hostile to both races", function()
			local facts = baseFacts()
			facts.targetIsPlayer = false
			facts.targetRace = "Angel"
			t.ok((CombatMath.canHarm(facts)))
		end)
	end)

	t.describe("basic attacks", function()
		t.it("every job has a basic attack with sane numbers", function()
			for _, job in Enums.Job do
				local attack = BasicAttacks.forJob(job)
				t.ok(attack ~= nil, job)
				t.ok(attack.range > 0 and attack.range <= 60, job)
				t.ok(attack.cooldown >= 0.5 and attack.cooldown <= 3, job)
				t.ok(attack.coefficient > 0 and attack.coefficient <= 2, job)
			end
			t.eq(BasicAttacks.forJob("Bard"), nil)
		end)

		t.it("melee is short range, ranged is long range", function()
			t.ok(BasicAttacks.forJob("Warrior").range < BasicAttacks.forJob("Healer").range)
			t.ok(BasicAttacks.forJob("Healer").range < BasicAttacks.forJob("Archer").range)
		end)
	end)
end
