--!strict
--[[
	AttributeRules — attribute points (creator request 2026-10-25, PLAN.md
	D-90). Pure.

	Every level gives POINTS_PER_LEVEL points the player spends on five
	attributes (saved in the profile as Attributes = { REC, INT, WIS, STR,
	AGI }). The game has one Attack stat, Focus instead of MP and one
	Defense, so damage is **physical** for Warriors and Archers and
	**magic** for Mages and Healers:

	  REC Recovery      +Max HP, +Defense
	  INT Intelligence  +magic damage (Mage / Healer attacks and skills)
	  WIS Wisdom        +max Focus (the game's MP), +magic resistance (less
	                    damage from magic attackers: Mage / Healer players
	                    and element bosses), +magic accuracy (lowers the
	                    target's dodge against your magic), +Healing Power
	  STR Strength      +physical damage (Warrior / Archer attacks and skills)
	  AGI Agility       +evasion: a chance to dodge a hit completely

	Values per point (PER_POINT) keep gear the main source of power: all
	150 points of a level-30 character in one attribute give +30% (damage,
	HP and Defense, healing), +45 Focus, 15% magic resistance or 9% dodge,
	about what the matching lines on a full set of good gear add. These add on top of the CLAUDE.md §5 level
	stats, which stay as they are. A free reset is allowed once every
	RESET_SECONDS.
]]

local AttributeRules = {}

AttributeRules.IDS = table.freeze({ "REC", "INT", "WIS", "STR", "AGI" })
AttributeRules.NAMES = table.freeze({
	REC = "Recovery",
	INT = "Intelligence",
	WIS = "Wisdom",
	STR = "Strength",
	AGI = "Agility",
})
AttributeRules.POINTS_PER_LEVEL = 5
AttributeRules.RESET_SECONDS = 24 * 3600
-- Points one request may add (the panel batches presses).
AttributeRules.MAX_STEP = 150

AttributeRules.PER_POINT = table.freeze({
	-- REC: % more Max HP and Defense.
	HPPct = 0.2,
	DefensePct = 0.2,
	-- STR (physical jobs) / INT (magic jobs): % more damage dealt.
	DamagePct = 0.2,
	-- WIS: Focus, % less magic damage taken, dodge points removed from a
	-- target against your magic, % more healing and shields.
	Focus = 0.3,
	MagicResistPct = 0.1,
	MagicAccuracyPct = 0.06,
	HealingPct = 0.2,
	-- AGI: % chance to dodge a hit.
	EvasionPct = 0.06,
})

-- Caps (all 150 points in one attribute stay under them).
AttributeRules.EVASION_CAP_PCT = 10
AttributeRules.MAGIC_RESIST_CAP_PCT = 20

-- Jobs whose damage counts as magic.
local MAGIC_JOBS = { Mage = true, Healer = true }

export type Attributes = { REC: number, INT: number, WIS: number, STR: number, AGI: number }
export type Bonuses = {
	hpPct: number,
	defensePct: number,
	damagePct: number,
	magic: boolean,
	focus: number,
	magicResistPct: number,
	magicAccuracyPct: number,
	healingPct: number,
	evasionPct: number,
}

function AttributeRules.empty(): Attributes
	return { REC = 0, INT = 0, WIS = 0, STR = 0, AGI = 0 }
end

function AttributeRules.isMagic(job: string?): boolean
	return job ~= nil and MAGIC_JOBS[job] == true
end

function AttributeRules.pointsFor(level: number): number
	return math.max(0, math.floor(level)) * AttributeRules.POINTS_PER_LEVEL
end

function AttributeRules.spent(attributes: Attributes): number
	local total = 0
	for _, id in AttributeRules.IDS do
		total += (attributes :: any)[id]
	end
	return total
end

function AttributeRules.unspent(attributes: Attributes, level: number): number
	return AttributeRules.pointsFor(level) - AttributeRules.spent(attributes)
end

--[[
	A stored value made safe: whole numbers >= 0 for the five ids, unknown
	keys dropped; if more points are spent than `level` gives (a level set
	down), every point is returned. Returns (attributes, changed).
]]
function AttributeRules.repair(value: any, level: number): (Attributes, boolean)
	local out = AttributeRules.empty()
	local changed = type(value) ~= "table"
	if type(value) == "table" then
		for key, n in value do
			local valid = AttributeRules.NAMES[key] ~= nil
				and type(n) == "number"
				and n == n
				and n >= 0
				and n % 1 == 0
				and n <= 10000
			if not valid then
				changed = true
			else
				(out :: any)[key] = n
			end
		end
	end
	if AttributeRules.spent(out) > AttributeRules.pointsFor(level) then
		return AttributeRules.empty(), true
	end
	return out, changed
end

--[[
	Checks a request to add `adds` ({ id = points }) at `level`. Returns
	(true, newAttributes) or (false, reason): "shape", "points".
]]
function AttributeRules.spend(current: Attributes, adds: any, level: number): (boolean, any)
	if type(adds) ~= "table" then
		return false, "shape"
	end
	local out = table.clone(current) :: any
	local added = 0
	for key, n in adds do
		if AttributeRules.NAMES[key] == nil or type(n) ~= "number" or n % 1 ~= 0 or n < 0 then
			return false, "shape"
		end
		out[key] += n
		added += n
	end
	if added <= 0 or added > AttributeRules.MAX_STEP then
		return false, "shape"
	end
	if AttributeRules.spent(out) > AttributeRules.pointsFor(level) then
		return false, "points"
	end
	return true, out
end

-- Whether a free reset is allowed at `now` after the last at `lastAt`.
function AttributeRules.canReset(lastAt: number, now: number): (boolean, number)
	if lastAt <= 0 then
		return true, 0
	end
	local readyAt = lastAt + AttributeRules.RESET_SECONDS
	return now >= readyAt, math.max(0, readyAt - now)
end

-- What the attributes give a character of `job`.
function AttributeRules.bonuses(attributes: Attributes, job: string?): Bonuses
	local p = AttributeRules.PER_POINT
	local magic = AttributeRules.isMagic(job)
	return {
		hpPct = attributes.REC * p.HPPct,
		defensePct = attributes.REC * p.DefensePct,
		damagePct = (if magic then attributes.INT else attributes.STR) * p.DamagePct,
		magic = magic,
		focus = attributes.WIS * p.Focus,
		magicResistPct = math.min(attributes.WIS * p.MagicResistPct, AttributeRules.MAGIC_RESIST_CAP_PCT),
		magicAccuracyPct = attributes.WIS * p.MagicAccuracyPct,
		healingPct = attributes.WIS * p.HealingPct,
		evasionPct = math.min(attributes.AGI * p.EvasionPct, AttributeRules.EVASION_CAP_PCT),
	}
end

--[[
	`stats` (StatsService: level + gear; may be frozen) with the attributes
	added, as a new table: Max HP, Defense and Healing Power here, plus the
	fields CombatService reads (DamagePct, MagicHit, MagicResistPct,
	MagicAccuracyPct, EvasionPct, FocusBonus).
]]
-- D-120: spent points plus the permanent bonus points (Fortune Wheel).
function AttributeRules.combine(attributes: any, bonus: any): Attributes
	local out = AttributeRules.empty()
	for _, id in AttributeRules.IDS do
		local a = if type(attributes) == "table" and type(attributes[id]) == "number"
			then attributes[id]
			else 0
		local b = if type(bonus) == "table" and type(bonus[id]) == "number" then bonus[id] else 0
		out[id] = a + b
	end
	return out
end

function AttributeRules.applyTo(stats: any, attributes: Attributes, job: string?): any
	local b = AttributeRules.bonuses(attributes, job)
	local out = table.clone(stats)
	out.MaxHP = stats.MaxHP * (1 + b.hpPct / 100)
	out.Defense = stats.Defense * (1 + b.defensePct / 100)
	out.HealingPowerPct = (stats.HealingPowerPct or 0) + b.healingPct
	out.DamagePct = b.damagePct
	out.MagicHit = b.magic
	out.MagicResistPct = b.magicResistPct
	out.MagicAccuracyPct = b.magicAccuracyPct
	out.EvasionPct = b.evasionPct
	out.FocusBonus = b.focus
	return out
end

-- The chance (0..1) a hit is dodged: the target's evasion, less the
-- attacker's magic accuracy when the hit is magic.
function AttributeRules.dodgeChance(evasionPct: number, magicAccuracyPct: number, magicHit: boolean): number
	local pct = evasionPct - (if magicHit then magicAccuracyPct else 0)
	return math.clamp(pct, 0, AttributeRules.EVASION_CAP_PCT) / 100
end

return AttributeRules
