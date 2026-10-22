--!strict
--[[
	Enums
	Shared enumerations. Values are plain strings so they serialize cleanly into
	DataStores and remote payloads. Each enum is a frozen, ordered list; order is
	meaningful where noted (e.g. Rarity is lowest -> highest).

	Pure module: no Roblox APIs.
]]

local Enums = {}

local function list(values: { string }): { string }
	return table.freeze(values)
end

Enums.Race = list({ "Angel", "Devil" })

-- The adult head a player picks (D-72; Appearance/BodyStyle.HEADS).
Enums.HeadStyle = list({ "Man", "Woman" })

-- Mage added by the creator 2026-10-11 (PLAN.md D-30).
Enums.Job = list({ "Healer", "Warrior", "Archer", "Mage" })

-- D-22: lowest -> highest. Epic added 2026-10-11 (creator decision, matches the gear concept sheet).
Enums.Rarity = list({ "Standard", "Uncommon", "Rare", "Epic", "Legendary", "Mythical" })

Enums.SkillType = list({ "Regular", "Special" })

-- CLAUDE.md §6: allowed categories per job are defined in JobDefinitions (Phase 4).
Enums.SkillCategory = list({
	-- Healer
	"Heal",
	"Shield",
	"Cleanse",
	"HolyAttack",
	"AreaSupport",
	-- Warrior
	"Guard",
	"DefenseBuff",
	"MeleeAttack",
	"AreaMelee",
	"Taunt",
	-- Archer
	"RangedAttack",
	"Precision",
	"Mobility",
	"Mark",
	"RangedArea",
	-- Mage (D-30)
	"MagicAttack",
	"AreaMagic",
	"Control",
	"Barrier",
})

-- Weapon families from the gear concept sheet (docs/ART_DIRECTION.md §2).
Enums.WeaponType = list({
	"Sword",
	"Greatsword",
	"Polearm",
	"Mace",
	"Axe",
	"Staff",
	"Orb",
	"Bow",
	"Crossbow",
	"Wand",
	"Tome",
	-- Equipment overhaul (D-68): the creator's weapon rules.
	"Dagger",
	"WarHammer",
	"BattleAxe",
})

-- D-25, extended by the equipment overhaul (D-68): Weapon is the main hand;
-- OffHand holds a shield or a second sword; Necklace replaces the old
-- "Accessory" slot (profiles migrate, v3); two ring slots.
Enums.ItemSlot = list({
	"Weapon",
	"OffHand",
	"Helm",
	"Shoulders",
	"Chest",
	"Hands",
	"Legs",
	"Boots",
	"Necklace",
	"Earrings",
	"Ring1",
	"Ring2",
})

Enums.Zone = list({
	"AngelCapital",
	"DevilCapital",
	"TrainingGrounds",
	"Dungeon",
	"DesertRift",
	"JungleRift",
})

-- Highest -> lowest privilege.
Enums.Role = list({ "Owner", "Admin", "Moderator", "Player" })

-- Lowest -> highest severity.
Enums.LogLevel = list({ "Debug", "Info", "Warn", "Error" })

-- Reasons a remote call can be rejected by the server pipeline.
Enums.RejectCode = list({
	"RateLimited",
	"BadArity",
	"BadArgs",
	"BadState",
	"NoPermission",
	"NoHandler",
	"HandlerError",
})

--[[
	Returns true if `value` is a member of the enum `values`.
]]
function Enums.has(values: { string }, value: any): boolean
	if type(value) ~= "string" then
		return false
	end
	return table.find(values, value) ~= nil
end

--[[
	Returns the 1-based position of `value` in an ordered enum, or nil.
]]
function Enums.indexOf(values: { string }, value: any): number?
	if type(value) ~= "string" then
		return nil
	end
	return table.find(values, value)
end

return table.freeze(Enums)
