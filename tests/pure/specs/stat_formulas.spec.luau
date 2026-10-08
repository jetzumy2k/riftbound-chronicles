local load = require("../loader")
local StatFormulas = load("src/shared/Logic/StatFormulas")

-- PLAN.md Appendix A (values rounded to 0.1 there).
local APPENDIX_A = {
	{ level = 0, hp = 200.0, atk = 100.0, def = 50.0, crit = 0.05, regen = 0.02 },
	{ level = 5, hp = 497.7, atk = 161.1, def = 73.5, crit = 0.30, regen = 0.12 },
	{ level = 10, hp = 1238.3, atk = 259.4, def = 107.9, crit = 0.55, regen = 0.22 },
	{ level = 15, hp = 3081.4, atk = 417.7, def = 158.6, crit = 0.80, regen = 0.32 },
	{ level = 20, hp = 7667.5, atk = 672.7, def = 233.0, crit = 1.05, regen = 0.42 },
	{ level = 25, hp = 19079.2, atk = 1083.5, def = 342.4, crit = 1.30, regen = 0.52 },
	{ level = 30, hp = 47475.3, atk = 1744.9, def = 503.1, crit = 1.55, regen = 0.62 },
}

return function(t)
	t.it("matches the CLAUDE.md §5 table at every 5 levels (Appendix A)", function()
		for _, row in APPENDIX_A do
			local s = StatFormulas.forLevel(row.level)
			t.near(s.MaxHP, row.hp, 0.06, `HP L{row.level}`)
			t.near(s.Attack, row.atk, 0.06, `ATK L{row.level}`)
			t.near(s.Defense, row.def, 0.06, `DEF L{row.level}`)
			t.near(s.CritDamagePct, row.crit, 1e-9, `Crit L{row.level}`)
			t.near(s.HPRegenPct, row.regen, 1e-9, `Regen L{row.level}`)
		end
	end)

	t.it("uses multiplicative growth for HP/ATK/DEF", function()
		for level = 1, 30 do
			local prev, cur = StatFormulas.forLevel(level - 1), StatFormulas.forLevel(level)
			t.near(cur.MaxHP / prev.MaxHP, 1.20, 1e-9)
			t.near(cur.Attack / prev.Attack, 1.10, 1e-9)
			t.near(cur.Defense / prev.Defense, 1.08, 1e-9)
		end
	end)

	t.it("uses additive percentage points for crit damage and regen", function()
		for level = 1, 30 do
			local prev, cur = StatFormulas.forLevel(level - 1), StatFormulas.forLevel(level)
			t.near(cur.CritDamagePct - prev.CritDamagePct, 0.05, 1e-9)
			t.near(cur.HPRegenPct - prev.HPRegenPct, 0.02, 1e-9)
		end
	end)

	t.it("applies D-02 crit multiplier and D-03 crit chance", function()
		local s0 = StatFormulas.forLevel(0)
		t.eq(s0.CritChancePct, 5)
		t.near(s0.CritMultiplier, 1.5005, 1e-9)
		t.near(StatFormulas.forLevel(30).CritMultiplier, 1.5155, 1e-9)
	end)

	t.it("rejects invalid levels", function()
		t.throws(function()
			StatFormulas.forLevel(31)
		end, "invalid level")
		t.throws(function()
			StatFormulas.forLevel(-1)
		end, "invalid level")
		t.throws(function()
			StatFormulas.forLevel(2.5)
		end, "invalid level")
	end)

	t.it("returns frozen results", function()
		t.ok(table.isfrozen(StatFormulas.forLevel(3)))
	end)
end
