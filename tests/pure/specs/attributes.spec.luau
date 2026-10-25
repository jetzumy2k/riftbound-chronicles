local load = require("../loader")
local AttributeRules = load("src/shared/Logic/AttributeRules")
local ProfileTemplate = load("src/server/Persistence/ProfileTemplate")
local ProfileValidator = load("src/server/Persistence/ProfileValidator")
local ProfileView = load("src/server/Persistence/ProfileView")
local StatFormulas = load("src/shared/Logic/StatFormulas")
local ItemRules = load("src/shared/Logic/ItemRules")

local function attrs(rec, int, wis, str, agi)
	return { REC = rec, INT = int, WIS = wis, STR = str, AGI = agi }
end

return function(t)
	t.describe("Attributes", function()
		t.it("5 points a level, 150 at level 30", function()
			t.eq(AttributeRules.pointsFor(0), 0)
			t.eq(AttributeRules.pointsFor(1), 5)
			t.eq(AttributeRules.pointsFor(30), 150)
			t.eq(AttributeRules.unspent(attrs(10, 0, 5, 0, 0), 4), 5)
		end)

		t.it("spending is checked against the level", function()
			local ok, result = AttributeRules.spend(AttributeRules.empty(), { STR = 5 }, 1)
			t.ok(ok and result.STR == 5, "spend all 5 at level 1")
			local over = { AttributeRules.spend(result, { AGI = 1 }, 1) }
			t.eq(over[1], false)
			t.eq(over[2], "points")
			t.eq(select(2, AttributeRules.spend(AttributeRules.empty(), { LUCK = 1 }, 10)), "shape")
			t.eq(select(2, AttributeRules.spend(AttributeRules.empty(), { STR = 1.5 }, 10)), "shape")
			t.eq(select(2, AttributeRules.spend(AttributeRules.empty(), { STR = -1, AGI = 2 }, 10)), "shape")
			t.eq(select(2, AttributeRules.spend(AttributeRules.empty(), {}, 10)), "shape", "nothing added")
			local ok2, many = AttributeRules.spend(AttributeRules.empty(), { REC = 2, WIS = 3 }, 1)
			t.ok(ok2 and many.REC == 2 and many.WIS == 3, "several at once")
		end)

		t.it("physical classes gain from STR, magic classes from INT", function()
			local a = attrs(0, 50, 0, 100, 0)
			t.near(AttributeRules.bonuses(a, "Warrior").damagePct, 20, 1e-9)
			t.near(AttributeRules.bonuses(a, "Archer").damagePct, 20, 1e-9)
			t.near(AttributeRules.bonuses(a, "Mage").damagePct, 10, 1e-9)
			t.near(AttributeRules.bonuses(a, "Healer").damagePct, 10, 1e-9)
			t.ok(
				AttributeRules.bonuses(a, "Mage").magic and not AttributeRules.bonuses(a, "Warrior").magic,
				"magic flag"
			)
		end)

		t.it("all 150 points in one attribute stay modest and capped", function()
			local b = AttributeRules.bonuses(attrs(150, 150, 150, 150, 150), "Mage")
			t.near(b.hpPct, 30, 1e-9)
			t.near(b.defensePct, 30, 1e-9)
			t.near(b.damagePct, 30, 1e-9)
			t.near(b.healingPct, 30, 1e-9)
			t.near(b.focus, 45, 1e-9)
			t.ok(b.magicResistPct <= AttributeRules.MAGIC_RESIST_CAP_PCT, "resist capped")
			t.ok(b.evasionPct <= AttributeRules.EVASION_CAP_PCT, "dodge capped")
			local huge = AttributeRules.bonuses(attrs(0, 0, 9999, 0, 9999), "Mage")
			t.eq(huge.evasionPct, AttributeRules.EVASION_CAP_PCT)
			t.eq(huge.magicResistPct, AttributeRules.MAGIC_RESIST_CAP_PCT)
		end)

		t.it("dodge: Agility, less magic accuracy on magic hits", function()
			t.near(AttributeRules.dodgeChance(9, 0, false), 0.09, 1e-9)
			t.near(AttributeRules.dodgeChance(9, 6, true), 0.03, 1e-9)
			t.near(AttributeRules.dodgeChance(9, 6, false), 0.09, 1e-9, "accuracy is for magic only")
			t.eq(AttributeRules.dodgeChance(5, 9, true), 0)
			t.eq(AttributeRules.dodgeChance(50, 0, false), AttributeRules.EVASION_CAP_PCT / 100)
		end)

		t.it("applies to the frozen gear stats without writing into them", function()
			-- Regression (creator report 2026-10-25, "no damage"): StatsService
			-- wrote into ItemRules.withGear's frozen table, which stopped
			-- every player's combat setup.
			local gear = ItemRules.gearTotals({}, {})
			local base = ItemRules.withGear(StatFormulas.forLevel(10), gear)
			t.ok(table.isfrozen(base), "gear stats are frozen")
			local stats = AttributeRules.applyTo(base, attrs(50, 0, 50, 50, 50), "Warrior")
			t.near(stats.MaxHP, base.MaxHP * 1.1, 1e-6)
			t.near(stats.Defense, base.Defense * 1.1, 1e-6)
			t.near(stats.DamagePct, 10, 1e-9)
			t.eq(stats.MagicHit, false)
			t.near(stats.EvasionPct, 3, 1e-9)
			t.near(stats.FocusBonus, 15, 1e-9)
			t.eq(stats.Attack, base.Attack)
			local none = AttributeRules.applyTo(base, AttributeRules.empty(), nil)
			t.eq(none.MaxHP, base.MaxHP)
			t.eq(none.DamagePct, 0)
		end)

		t.it("a free reset once a day", function()
			t.ok(AttributeRules.canReset(0, 1000), "never reset")
			local ok, wait = AttributeRules.canReset(1000, 1000 + 3600)
			t.ok(not ok and wait == 23 * 3600, "23 h to wait")
			t.ok(AttributeRules.canReset(1000, 1000 + 24 * 3600), "ready after 24 h")
		end)

		t.it("profiles: missing attributes are filled, bad ones repaired", function()
			local data = ProfileTemplate.new()
			data.Attributes = nil
			data.AttributeResetAt = nil
			ProfileValidator.repair(data)
			t.eq(AttributeRules.spent(data.Attributes), 0)
			t.eq(data.AttributeResetAt, 0)

			local cheat = ProfileTemplate.new()
			cheat.Level = 2
			cheat.Attributes = { REC = 3, STR = 2.5, LUCK = 9, AGI = -1 }
			ProfileValidator.repair(cheat)
			t.eq(cheat.Attributes.REC, 3)
			t.eq(cheat.Attributes.STR, 0)
			t.eq(cheat.Attributes.AGI, 0)
			t.eq(cheat.Attributes.LUCK, nil)

			local over = ProfileTemplate.new()
			over.Level = 1
			over.Attributes = attrs(10, 0, 0, 0, 0)
			ProfileValidator.repair(over)
			t.eq(AttributeRules.spent(over.Attributes), 0, "more than the level gives: all returned")

			local fine = ProfileTemplate.new()
			fine.Level = 3
			fine.TotalExperience = 1e6
			fine.Attributes = attrs(5, 0, 5, 5, 0)
			local notes = ProfileValidator.repair(fine)
			t.eq(#notes, 0, table.concat(notes, " | "))
		end)

		t.it("the view sends the points and the reset wait", function()
			local data = ProfileTemplate.new()
			data.Attributes = attrs(1, 2, 3, 4, 5)
			data.AttributeResetAt = os.time() - 3600
			local view = ProfileView.attributes(data)
			t.eq(view.Attributes.AGI, 5)
			t.ok(view.ResetIn > 22 * 3600 and view.ResetIn <= 23 * 3600, `ResetIn {view.ResetIn}`)
			t.ok(ProfileView.snapshot(data).Attributes ~= nil, "in the snapshot")
		end)
	end)
end
