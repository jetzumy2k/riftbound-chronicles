--!strict
--[[
	JobDefinitions (CLAUDE.md §6, Phase 4)

	Each character has exactly one job. A job decides:
	  - which skill categories it may equip (enforced by JobService on the
	    server, used by SkillService in Phase 5);
	  - which weapon families it may wield (enforced by EquipmentService in
	    Phase 7). Weapons differ slightly per race, per the gear concept sheet.

	Jobs deliberately carry no hidden stat multipliers: CLAUDE.md §5 base stats
	apply to everyone, and job identity comes from skills and gear.

	Display-safe data only. Pure module.
]]

export type JobDefinition = {
	id: string,
	displayName: string,
	glyph: string,
	-- Short role line per race (from the concept sheet).
	roleByRace: { [string]: string },
	description: string,
	allowedSkillCategories: { string },
	weaponsByRace: { [string]: { string } },
}

local JobDefinitions = {}

local function freezeDeep<T>(value: T): T
	if type(value) == "table" and not table.isfrozen(value :: any) then
		for _, child in value :: any do
			freezeDeep(child)
		end
		table.freeze(value :: any)
	end
	return value
end

JobDefinitions.Warrior = freezeDeep({
	id = "Warrior",
	displayName = "Warrior",
	glyph = "⚔",
	roleByRace = {
		Angel = "High Defense · Melee DPS",
		Devil = "High Defense · Melee DPS",
	},
	description = "Frontline champion who guards allies, shrugs off blows and controls the fight up close.",
	-- CLAUDE.md §6.2
	allowedSkillCategories = { "Guard", "Shield", "DefenseBuff", "MeleeAttack", "AreaMelee", "Taunt" },
	weaponsByRace = {
		Angel = { "Sword", "Greatsword", "Polearm", "Mace" },
		Devil = { "Sword", "Greatsword", "Axe", "Polearm" },
	},
} :: JobDefinition)

JobDefinitions.Healer = freezeDeep({
	id = "Healer",
	displayName = "Healer",
	glyph = "✧",
	roleByRace = {
		Angel = "Healing · Support · Buff",
		Devil = "Healing · Support · Debuff",
	},
	description = "Keeps the party standing with healing and shields, and turns the tide with arcane power.",
	-- CLAUDE.md §6.1 (HolyAttack is the internal id of the radiant/arcane attack category).
	allowedSkillCategories = { "Heal", "Shield", "Cleanse", "HolyAttack", "AreaSupport" },
	weaponsByRace = {
		Angel = { "Staff", "Orb" },
		Devil = { "Staff", "Orb" },
	},
} :: JobDefinition)

JobDefinitions.Archer = freezeDeep({
	id = "Archer",
	displayName = "Archer",
	glyph = "➹",
	roleByRace = {
		Angel = "Long Range · High DPS",
		Devil = "Long Range · High DPS",
	},
	description = "Precise long-range striker who marks targets, strikes from afar and repositions quickly.",
	-- CLAUDE.md §6.3
	allowedSkillCategories = { "RangedAttack", "Precision", "Mobility", "Mark", "RangedArea" },
	weaponsByRace = {
		Angel = { "Bow", "Crossbow" },
		Devil = { "Bow", "Crossbow" },
	},
} :: JobDefinition)

-- Added by the creator 2026-10-11 (PLAN.md D-30), inspired by Shaiya's mage.
JobDefinitions.Mage = freezeDeep({
	id = "Mage",
	displayName = "Mage",
	glyph = "✺",
	roleByRace = {
		Angel = "Arcane Burst · Area DPS",
		Devil = "Hex Burst · Area DPS",
	},
	description = "Master of raw arcane power: devastating area spells, crowd control and barriers, but fragile up close.",
	allowedSkillCategories = { "MagicAttack", "AreaMagic", "Control", "Barrier" },
	weaponsByRace = {
		Angel = { "Staff", "Wand", "Tome" },
		Devil = { "Staff", "Wand", "Tome" },
	},
} :: JobDefinition)

-- Display order on the selection screen.
JobDefinitions.Order = table.freeze({ "Warrior", "Healer", "Archer", "Mage" })

-- Player-facing names for skill categories (internal ids stay stable).
JobDefinitions.CategoryNames = table.freeze({
	Heal = "Healing",
	Shield = "Shield",
	Cleanse = "Cleanse",
	HolyAttack = "Radiant Strike",
	AreaSupport = "Area Support",
	Guard = "Guard",
	DefenseBuff = "Fortify",
	MeleeAttack = "Melee Strike",
	AreaMelee = "Cleave",
	Taunt = "Taunt",
	RangedAttack = "Ranged Shot",
	Precision = "Precision",
	Mobility = "Mobility",
	Mark = "Mark",
	RangedArea = "Volley",
	MagicAttack = "Spell",
	AreaMagic = "Area Spell",
	Control = "Crowd Control",
	Barrier = "Barrier",
})

function JobDefinitions.get(job: any): JobDefinition?
	if job == "Warrior" or job == "Healer" or job == "Archer" or job == "Mage" then
		return (JobDefinitions :: any)[job]
	end
	return nil
end

-- Server rule used by SkillService (Phase 5): may `job` equip a skill of `category`?
function JobDefinitions.allowsSkillCategory(job: any, category: any): boolean
	local def = JobDefinitions.get(job)
	return def ~= nil
		and type(category) == "string"
		and table.find(def.allowedSkillCategories, category) ~= nil
end

-- Server rule used by EquipmentService (Phase 7): may `job` of `race` wield `weaponType`?
function JobDefinitions.allowsWeapon(job: any, race: any, weaponType: any): boolean
	local def = JobDefinitions.get(job)
	if def == nil or type(race) ~= "string" or type(weaponType) ~= "string" then
		return false
	end
	local weapons = def.weaponsByRace[race]
	return weapons ~= nil and table.find(weapons, weaponType) ~= nil
end

return table.freeze(JobDefinitions)
