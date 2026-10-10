--!strict
--[[
	Types
	Shared type aliases. Keep in sync with Enums.luau (string unions mirror the
	enum lists).
]]

export type Race = "Angel" | "Devil"
export type Job = "Healer" | "Warrior" | "Archer"
export type Rarity = "Standard" | "Uncommon" | "Rare" | "Epic" | "Legendary" | "Mythical"
export type SkillType = "Regular" | "Special"
export type ItemSlot = "Weapon" | "Helm" | "Chest" | "Legs" | "Boots" | "Accessory"
export type Zone =
	"AngelCapital"
	| "DevilCapital"
	| "TrainingGrounds"
	| "Dungeon"
	| "DesertRift"
	| "JungleRift"
export type Role = "Owner" | "Admin" | "Moderator" | "Player"
export type LogLevel = "Debug" | "Info" | "Warn" | "Error"
export type RejectCode =
	"RateLimited"
	| "BadArity"
	| "BadArgs"
	| "BadState"
	| "NoPermission"
	| "NoHandler"
	| "HandlerError"

-- Lifecycle contract every server service / client controller follows.
export type Service = {
	Init: ((self: any) -> ())?,
	Start: ((self: any) -> ())?,
}

-- ModuleScripts must return exactly one non-nil value; types are consumed via
-- `local Types = require(...)` and `Types.Race` etc.
return {}
