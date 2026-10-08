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

Enums.Job = list({ "Healer", "Warrior", "Archer" })

-- D-22: lowest -> highest.
Enums.Rarity = list({ "Standard", "Uncommon", "Rare", "Legendary", "Mythical" })

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
})

-- D-25.
Enums.ItemSlot = list({ "Weapon", "Helm", "Chest", "Legs", "Boots", "Accessory" })

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
