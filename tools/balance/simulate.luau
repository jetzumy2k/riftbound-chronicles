--[[
	Balance simulation (Phase 20, PLAN.md D-95). Uses the game's own pure
	formula modules (stats, combat math, gear, attributes, buffs, bosses,
	EXP), so the numbers are what the server would compute.

	    lune run tools/balance/simulate > build/balance.md

	Models (stated in each section):
	  - a player's sustained damage = basic chain (BasicAttacks.chainDps)
	    x skill bonus (BossBalance: up to +60% at level 30) x uptime 0.7;
	  - "gear kits" at the player's level: none, a typical drop kit (Rare,
	    mid rolls, +5 weapon / +3 armour), a Mall Mythical set (+0, fixed
	    85% rolls) and an endgame kit (Mythical +10);
	  - attributes: 150 points split (damage 75 / REC 75) at level 30,
	    5 per level below.
]]

local load = require("../../tests/pure/loader")
local StatFormulas = load("src/shared/Logic/StatFormulas")
local CombatMath = load("src/shared/Logic/CombatMath")
local ItemRules = load("src/shared/Logic/ItemRules")
local ItemDefinitions = load("src/shared/Definitions/ItemDefinitions")
local JobDefinitions = load("src/shared/Definitions/JobDefinitions")
local BasicAttacks = load("src/shared/Definitions/BasicAttacks")
local AttributeRules = load("src/shared/Logic/AttributeRules")
local BuffRules = load("src/shared/Logic/BuffRules")
local BossBalance = load("src/shared/Logic/BossBalance")
local EnemyDefinitions = load("src/shared/Definitions/EnemyDefinitions")
local XPTable = load("src/shared/Logic/XPTable")
local LevelGap = load("src/shared/Logic/LevelGap")
local Defaults = load("src/server/Config/Defaults")

local COMBAT = {
	PowerScalePerLevel = Defaults.Combat.PowerScalePerLevel,
	DefenseKBase = Defaults.Combat.DefenseKBase,
	DefenseKPerLevel = Defaults.Combat.DefenseKPerLevel,
	RangeToleranceStuds = 0,
	MaxPingCompensationSeconds = 0,
}
local JOBS = { "Warrior", "Healer", "Mage", "Archer" }
local RACE = { Warrior = "Angel", Healer = "Angel", Mage = "Devil", Archer = "Angel" }
local UPTIME = BossBalance.UPTIME
local LEVELS = { 1, 5, 10, 15, 20, 25, 30 }

local out = {}
local function p(line: string?)
	table.insert(out, line or "")
end
local function f1(n: number): string
	return string.format("%.1f", n)
end
local function f0(n: number): string
	return tostring(math.floor(n + 0.5))
end

--------------------------------------------------------------------------------
-- Gear kits
--------------------------------------------------------------------------------

local function family(job: string): string?
	for _, candidate in ItemDefinitions.familiesOf(job) do
		if JobDefinitions.allowsWeapon(job, RACE[job], candidate) then
			return candidate
		end
	end
	return nil
end

-- An item with mid (0.5) or fixed (quality) rolls.
local function item(def: any, rarity: string, level: number, enhancement: number, quality: number): any
	return {
		DefId = def.id,
		Rarity = rarity,
		ItemLevel = level,
		Enhancement = enhancement,
		Attributes = ItemRules.fixedRoll(def, rarity, level, quality),
	}
end

-- Kit: { rarity, weapon +, armour +, quality } or nil for no gear.
local KITS = {
	{ name = "no gear", rarity = nil },
	{ name = "drops (Rare +5/+3)", rarity = "Rare", weapon = 5, armour = 3, quality = 0.5 },
	{ name = "Mall Legendary set (+0)", rarity = "Legendary", weapon = 0, armour = 0, quality = ItemRules.FIXED_QUALITY },
	{ name = "endgame (Mythical +10)", rarity = "Mythical", weapon = 10, armour = 10, quality = 0.85 },
}

local function gearFor(job: string, level: number, kit: any): any
	local equipment, inventory = {}, {}
	if kit.rarity then
		local n = 0
		for _, kind in ItemDefinitions.kindsOf(job) do
			local def = ItemDefinitions.defFor(job, kind, if kind == "Weapon" then family(job) else nil, level)
			if def then
				n += 1
				local itemLevel = math.clamp(level, def.minItemLevel, def.maxItemLevel)
				local plus = if kind == "Weapon" then kit.weapon else kit.armour
				local guid = `g{n}`
				inventory[guid] = item(def, kit.rarity, itemLevel, plus, kit.quality)
				local slot = if kind == "Weapon" then "MainHand" elseif kind == "Shield" then "OffHand" elseif kind == "Ring" then "Ring1" else kind
				equipment[slot] = guid
			end
		end
	end
	return ItemRules.gearTotals(equipment, inventory)
end

local function attributesAt(level: number): any
	local points = AttributeRules.pointsFor(level)
	local half = math.floor(points / 2)
	return { REC = points - half, INT = half, WIS = 0, STR = half, AGI = 0 }
end

-- A character's stats: level + kit (+ attributes, + buffs).
local function stats(job: string, level: number, kit: any, withAttributes: boolean?, withBuffs: boolean?): any
	local base = ItemRules.withGear(StatFormulas.forLevel(level), gearFor(job, level, kit))
	local s = if withAttributes then AttributeRules.applyTo(base, attributesAt(level), job) else table.clone(base)
	if withBuffs then
		s = BuffRules.applyTo(s, { Might = 1e12, Iron = 1e12, Vigor = 1e12 }, 0)
	end
	return s
end

-- Average damage multiplier from crits.
local function critFactor(s: any): number
	local chance = math.clamp((s.CritChancePct or 5) / 100, 0, 1)
	return 1 + chance * ((s.CritMultiplier or 1.5) - 1)
end

-- Sustained damage per second of `s` (job, level) against `defense`.
local function dps(job: string, level: number, s: any, defense: number, mitigationPct: number?): number
	local chain = BasicAttacks.chainDps(BasicAttacks.ByJob[job])
	local skill = 1 + BossBalance.SKILL_BONUS * level / 30
	local coefficient = chain * skill * UPTIME * (1 + (s.SkillPowerPct or 0) / 100 * 0.5) * (1 + (s.DamagePct or 0) / 100)
	local raw = s.Attack * coefficient * CombatMath.powerScale(level, COMBAT)
	local hit = CombatMath.mitigate(raw, defense, CombatMath.defenseK(level, COMBAT))
	return hit * critFactor(s) * (1 - (mitigationPct or 0) / 100)
end

--------------------------------------------------------------------------------
-- 1. PvP: equal level, same kit
--------------------------------------------------------------------------------

p("# Balance simulation (Phase 20)")
p()
p("Generated by `lune run tools/balance/simulate`. Numbers come from the game's own formula modules.")
p("Sustained damage = basic chain x skill bonus (up to +60% at level 30) x 70% uptime, average crits; Skill Power counts half (skills are about half the damage).")
p()
p("## 1. PvP time to kill, equal level and kit (seconds)")
p()
p("Attacker vs defender of the same class, level and kit; the defender's Defense, HP and Damage Reduction apply. Target band: 6-15 s.")
p()
p("| Level | Kit | Warrior | Healer | Mage | Archer |")
p("|---|---|---|---|---|---|")
for _, level in LEVELS do
	for _, kit in KITS do
		if kit.rarity == nil or level >= 5 then
			local cells = {}
			for _, job in JOBS do
				local s = stats(job, level, kit)
				local t = s.MaxHP / dps(job, level, s, s.Defense, s.MitigationPct)
				table.insert(cells, f1(t))
			end
			p(`| {level} | {kit.name} | {table.concat(cells, " | ")} |`)
		end
	end
end

p()
p("## 2. PvP mismatch at level 30: paying vs not paying")
p()
p("Time for A to defeat B (seconds), both Warriors at level 30. Lower = A wins faster.")
p()
p("| A | B | A kills B | B kills A | A's advantage |")
p("|---|---|---|---|---|")
local MATCHES = {
	{ "drops (Rare +5/+3)", "drops (Rare +5/+3)", false, false },
	{ "Mall Legendary set (+0)", "drops (Rare +5/+3)", false, false },
	{ "Mall Legendary set (+0)", "drops (Rare +5/+3)", true, false },
	{ "endgame (Mythical +10)", "drops (Rare +5/+3)", false, false },
	{ "drops (Rare +5/+3)", "no gear", false, false },
}
local function kitNamed(name: string): any
	for _, kit in KITS do
		if kit.name == name then
			return kit
		end
	end
	return KITS[1]
end
for _, m in MATCHES do
	local a = stats("Warrior", 30, kitNamed(m[1]), true, m[3])
	local b = stats("Warrior", 30, kitNamed(m[2]), true, m[4])
	local aKills = b.MaxHP / dps("Warrior", 30, a, b.Defense, b.MitigationPct)
	local bKills = a.MaxHP / dps("Warrior", 30, b, a.Defense, a.MitigationPct)
	p(`| {m[1]}{if m[3] then " + Might/Iron/Vigor" else ""} | {m[2]} | {f1(aKills)} s | {f1(bKills)} s | {f1(bKills / aKills)}x |`)
end

p()
p("## 2b. PvP across classes at level 30 (drop kit + attributes), seconds for the row to defeat the column")
p()
p("| Attacker (row) vs defender | Warrior | Healer | Mage | Archer |")
p("|---|---|---|---|---|")
for _, attacker in JOBS do
	local a = stats(attacker, 30, kitNamed("drops (Rare +5/+3)"), true)
	local cells = {}
	for _, defender in JOBS do
		local b = stats(defender, 30, kitNamed("drops (Rare +5/+3)"), true)
		table.insert(cells, f1(b.MaxHP / dps(attacker, 30, a, b.Defense, b.MitigationPct)))
	end
	p(`| {attacker} | {table.concat(cells, " | ")} |`)
end

--------------------------------------------------------------------------------
-- 3. Creatures
--------------------------------------------------------------------------------

p()
p("## 3. Regular creatures: time to kill and how fast they hurt (drop kit)")
p()
p("| Creature | Lv | You kill it | It hits for | Hits to defeat you | EXP | EXP per minute of fighting |")
p("|---|---|---|---|---|---|---|")
local CREATURES = { "RiftWolf", "CrystalBeetle", "StonebackGuardian", "EmberHound", "CinderScarab", "MagmaGolem", "RimeStalker", "AbyssCrawler", "AbyssalKnight" }
for _, id in CREATURES do
	local e = EnemyDefinitions.get(id)
	local level = e.level
	local c = StatFormulas.forCreatureLevel(level)
	local hp = c.MaxHP * e.hpScale
	local def = c.Defense * e.defenseScale
	local playerLevel = math.min(level, 30)
	local s = stats("Warrior", playerLevel, kitNamed("drops (Rare +5/+3)"), true)
	local kill = hp / dps("Warrior", playerLevel, s, def)
	local raw = c.Attack * e.attackScale * e.attackCoefficient * CombatMath.powerScale(level, COMBAT)
	local hit = CombatMath.mitigate(raw, s.Defense, CombatMath.defenseK(level, COMBAT)) * (1 - (s.MitigationPct or 0) / 100)
	local xp = EnemyDefinitions.xpAt(e, level)
	-- Plus ~3 s to reach the next one.
	p(`| {e.name} | {level} | {f1(kill)} s | {f0(hit)} | {f0(s.MaxHP / hit)} | {xp} | {f0(xp / (kill + 3) * 60)} |`)
end

--------------------------------------------------------------------------------
-- 4. Bosses vs gear
--------------------------------------------------------------------------------

p()
p("## 4. Bosses: share of the enrage timer used, by group size and kit")
p()
p("BossBalance sizes boss HP for players with **no gear** (D-47 targets: Boss solo impossible, duo super hard, party very hard). Values above 1.0 mean the group cannot win before the enrage.")
p()
p("| Boss | Tier | Lv | Kit | Solo | Duo | Party 4 | Union 8 |")
p("|---|---|---|---|---|---|---|---|")
for _, id in { "Cerberus", "Chimera", "Basilisk", "Typhon", "Ammit", "OasisColossus", "NullbornHerald" } do
	local e = EnemyDefinitions.get(id)
	local level = e.level
	local c = StatFormulas.forCreatureLevel(level)
	local hp = c.MaxHP * e.hpScale
	local def = c.Defense * e.defenseScale
	local ref = BossBalance.referenceLevel(level)
	local enrage = EnemyDefinitions.ENRAGE_SECONDS[e.tier]
	for _, kitName in { "no gear", "drops (Rare +5/+3)", "endgame (Mythical +10)" } do
		local s = stats("Warrior", ref, kitNamed(kitName), kitName ~= "no gear")
		local one = dps("Warrior", ref, s, def)
		local cells = {}
		for _, n in { 1, 2, 4, 8 } do
			table.insert(cells, f1(hp / (one * n) / enrage))
		end
		p(`| {e.name} | {e.tier} | {level} | {kitName} | {table.concat(cells, " | ")} |`)
	end
end

--------------------------------------------------------------------------------
-- 5. Levelling
--------------------------------------------------------------------------------

p()
p("## 5. Time to level 30")
p()
local total = XPTable.totalToReach(30)
p(`Total EXP to reach 30: **{total}** (D-18 target: about 20-25 active hours).`)
p()
p("Model: the player fights the dungeon floor that matches their level (floors 1-3 creatures near their level, EXP after the creature EXP scale (D-95) and the level-gap rule), drop kit, 3 s between kills, half the time actually fighting (walking, respawns, resting), plus the floor bosses' bonuses (1,900 a run, same scale) about once per 20 minutes.")
p()
p("| Level band | Creatures | Minutes per level (avg) | Hours in band |")
p("|---|---|---|---|")
local bands = {
	{ 0, 10, { "RiftWolf", "CrystalBeetle", "StonebackGuardian" } },
	{ 10, 20, { "EmberHound", "CinderScarab", "MagmaGolem" } },
	{ 20, 30, { "RimeStalker", "AbyssCrawler", "AbyssalKnight" } },
}
local function minutesFor(level: number, multiplier: number): number
	local rate = 0
	local band = bands[math.min(3, level // 10 + 1)]
	for _, id in band[3] do
		local e = EnemyDefinitions.get(id)
		local cLevel = math.clamp(level, e.level - 2, e.level + 6)
		local c = StatFormulas.forCreatureLevel(cLevel)
		local st = stats("Warrior", level, kitNamed("drops (Rare +5/+3)"), true)
		local kill = c.MaxHP * e.hpScale / dps("Warrior", level, st, c.Defense * e.defenseScale)
		local xp = LevelGap.scaleXp(EnemyDefinitions.xpAt(e, cLevel), cLevel, level)
		rate += xp / (kill + 3) / #band[3]
	end
	local bonus = 1900 * XPTable.creatureScale(level) / 1200
	local perSecond = (rate + bonus) * 0.5 * multiplier
	return XPTable.toNext(level) / perSecond / 60
end
local hours = 0
for _, band in bands do
	local minutes = 0
	for level = band[1], band[2] - 1 do
		minutes += minutesFor(level, 1)
	end
	hours += minutes / 60
	p(`| {band[1]}-{band[2]} | {table.concat(band[3], ", ")} | {f1(minutes / (band[2] - band[1]))} | {f1(minutes / 60)} |`)
end
p()
p(`Estimated active time to level 30: **{f1(hours)} hours**. Level 1 takes {f1(minutesFor(1, 1))} min, level 10 {f1(minutesFor(10, 1))}, level 20 {f1(minutesFor(20, 1))}, level 29 {f1(minutesFor(29, 1))}.`)
local function total(m: number): number
	local t = 0
	for level = 0, 29 do
		t += minutesFor(level, m)
	end
	return t / 60
end
p(`With a Scroll of Insight (+50%): {f1(total(1.5))} h; with Double EXP: {f1(total(2))} h; both (2.5x): {f1(total(2.5))} h.`)

--------------------------------------------------------------------------------
-- 6. Economy
--------------------------------------------------------------------------------

p()
p("## 6. Enhancement and drops")
p()
local rates = Defaults.Enhancement.RatesPct
local stones = 0
local cells = {}
for i, rate in rates do
	local expected = 100 / rate
	stones += expected
	table.insert(cells, `+{i}: {f1(expected)}`)
end
p(`Expected Enhancement Stones per level (rates {table.concat(rates, "/")}%): {table.concat(cells, ", ")}.`)
p(`Expected stones from +0 to +10: **{f1(stones)}** per item (failures never downgrade, D-08). In MP at 27 MP each (x10 pack): {f0(stones * 27)} MP per item.`)
p()
local mob = Defaults.Loot.Tables.DungeonMob
local elite = Defaults.Loot.Tables.DungeonElite
p(`Dungeon drop chance: regular {mob.DropChancePct}% (Rare {mob.Rarity.Rare}% of drops), elite {elite.DropChancePct}%; bosses always drop (Legendary 20%).`)
p(`War-zone creatures: {Defaults.Loot.StoneTables.WarZoneMob.DropChancePct}% chance of a stone (Perfect {Defaults.Loot.StoneTables.WarZoneMob.Stones.PerfectStone}%).`)

print(table.concat(out, "\n"))
