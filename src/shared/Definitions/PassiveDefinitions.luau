--!strict
--[[
	PassiveDefinitions — class passives (D-104, creator request 2026-10-26).

	Three per class, always on once learned: they never take a skill bar
	slot. Each has 5 ranks bought with skill points from the same pool as
	the tree (owned ranks are stored with the skills in OwnedSkills). Higher
	ranks open with level like any skill (SkillRules.rankCap).

	Fields
	  id / name / job / description
	  unlockLevel   level needed for rank 1 (5, 12 or 20)
	  maxRank       5
	  perRank       bonus per rank, by stat (PassiveRules.applyTo):
	    DamagePct      % more damage dealt (physical or magic, by job)
	    MaxHPPct       % more Max HP
	    DefensePct     % more Defense
	    CritChancePct  crit chance, percentage points
	    CritDamagePct  crit damage, percentage points (CritMultiplier)
	    HealingPct     % more healing and shields
	    Focus          more max Focus
	    EvasionPct     dodge chance points (AttributeRules cap still applies)
	  icon / fx.element   drawn like a skill icon (SkillIcon.forSkill)

	"Strong" tuning (creator choice): about +20% of the class's main stat at
	rank 5. Pure data.
]]

export type Passive = {
	id: string,
	name: string,
	job: string,
	description: string,
	unlockLevel: number,
	-- Always nil: passives need no other skill (shape shared with skills).
	requires: string?,
	maxRank: number,
	perRank: { [string]: number },
	icon: string,
	fx: { element: string },
}

local PassiveDefinitions = {}

PassiveDefinitions.MAX_RANK = 5
PassiveDefinitions.UNLOCK_LEVELS = table.freeze({ 5, 12, 20 })
PassiveDefinitions.STATS = table.freeze({
	"DamagePct",
	"MaxHPPct",
	"DefensePct",
	"CritChancePct",
	"CritDamagePct",
	"HealingPct",
	"Focus",
	"EvasionPct",
})

local function passive(
	job: string,
	slot: number,
	id: string,
	name: string,
	icon: string,
	element: string,
	perRank: { [string]: number },
	description: string
): Passive
	return {
		id = id,
		name = name,
		job = job,
		description = description,
		unlockLevel = PassiveDefinitions.UNLOCK_LEVELS[slot],
		requires = nil,
		maxRank = PassiveDefinitions.MAX_RANK,
		perRank = perRank,
		icon = icon,
		fx = { element = element },
	}
end

local list: { Passive } = {
	-- Warrior: raw power, toughness, killer instinct.
	passive("Warrior", 1, "WarriorMight", "Warrior's Might", "fist", "Steel", {
		DamagePct = 4,
	}, "Years of drills: every swing and skill hits harder."),
	passive("Warrior", 2, "IronBody", "Iron Body", "shield", "Earth", {
		MaxHPPct = 5,
		DefensePct = 3,
	}, "A body hardened by battle: more health and armour."),
	passive("Warrior", 3, "BattleInstinct", "Battle Instinct", "roar", "Fire", {
		CritChancePct = 2,
		CritDamagePct = 6,
	}, "You see the opening first: more and stronger critical hits."),

	-- Archer: precision first, then power and footwork.
	passive("Archer", 1, "HawkSight", "Hawk Sight", "eye", "Wind", {
		CritChancePct = 3,
		CritDamagePct = 8,
	}, "Nothing escapes your sight: more and stronger critical hits."),
	passive("Archer", 2, "DeadlyAim", "Deadly Aim", "target", "Nature", {
		DamagePct = 4,
	}, "Every arrow finds the weak spot: more damage."),
	passive("Archer", 3, "FleetFoot", "Fleet Foot", "speed", "Wind", {
		EvasionPct = 1,
		MaxHPPct = 2,
	}, "Light on your feet: dodge more hits and last longer."),

	-- Mage: magic power, a deeper Focus pool, and a ward for a fragile body.
	passive("Mage", 1, "ArcaneMastery", "Arcane Mastery", "orb", "Arcane", {
		DamagePct = 4,
	}, "Deep study of the arcane: spells deal more damage."),
	passive("Mage", 2, "ManaFlow", "Mana Flow", "rune", "Frost", {
		Focus = 8,
	}, "Focus flows freely: a much larger Focus pool for more spells."),
	passive("Mage", 3, "ArcaneWard", "Arcane Ward", "barrier", "Arcane", {
		MaxHPPct = 4,
		DefensePct = 4,
	}, "A permanent shimmer of protection: more health and defense."),

	-- Healer: stronger heals, sturdier support, holy damage.
	passive("Healer", 1, "HolyDevotion", "Holy Devotion", "halo", "Holy", {
		HealingPct = 5,
	}, "Your faith in the light grows: heals and shields are stronger."),
	passive("Healer", 2, "BlessedVigor", "Blessed Vigor", "heart", "Holy", {
		MaxHPPct = 4,
		DefensePct = 3,
	}, "The light keeps you standing: more health and defense."),
	passive("Healer", 3, "SacredWrath", "Sacred Wrath", "star", "Holy", {
		DamagePct = 4,
	}, "Holy power turned on your foes: more damage."),
}

local byId: { [string]: Passive } = {}
local byJob: { [string]: { Passive } } = {}
local ids: { string } = {}
for _, entry in list do
	byId[entry.id] = entry
	byJob[entry.job] = byJob[entry.job] or {}
	table.insert(byJob[entry.job], entry)
	table.insert(ids, entry.id)
	table.freeze(entry.perRank)
	table.freeze(entry.fx)
	table.freeze(entry)
end
for _, entries in byJob do
	table.sort(entries, function(a, b)
		return a.unlockLevel < b.unlockLevel
	end)
	table.freeze(entries)
end

PassiveDefinitions.IDS = table.freeze(ids)

function PassiveDefinitions.get(id: any): Passive?
	return if type(id) == "string" then byId[id] else nil
end

-- The job's passives in unlock order (empty for no / unknown job).
function PassiveDefinitions.forJob(job: string?): { Passive }
	return byJob[job or ""] or {}
end

return table.freeze(PassiveDefinitions)
