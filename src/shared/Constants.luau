--!strict
--[[
	Constants
	Values fixed by the spec (CLAUDE.md). Tunable balance values that admins may
	change live belong in server configuration, not here.

	Pure module: no Roblox APIs.
]]

local Constants = {}

-- CLAUDE.md §4
-- D-129: Max is the highest level there can be (with the admin's level 60
-- switch); Base is the original cap, still the cap while the switch is off
-- (Logic/LevelCap).
Constants.Level = table.freeze({
	Min = 0,
	Max = 60,
	Base = 30,
})

-- CLAUDE.md §5 (Level 0 values). Percent values are expressed in percent units:
-- 0.05 means 0.05%.
Constants.BaseStats = table.freeze({
	HP = 200,
	Defense = 50,
	Attack = 100,
	CritDamagePct = 0.05,
	HPRegenPct = 0.02,
})

-- CLAUDE.md §5 per-level growth (multiplicative for HP/Attack/Defense,
-- additive percentage points for Crit Damage/HP Regen).
Constants.StatGrowth = table.freeze({
	HPMultiplier = 1.20,
	AttackMultiplier = 1.10,
	DefenseMultiplier = 1.08,
	CritDamagePctPerLevel = 0.05,
	HPRegenPctPerLevel = 0.02,
})

-- PLAN.md D-02 / D-03 (approved defaults; Phase 20 may move these to config).
-- Crit multiplier = BaseMultiplier + CritDamagePct / 100.
Constants.Crit = table.freeze({
	BaseChancePct = 5,
	BaseMultiplier = 1.5,
})

-- PLAN.md D-18: XPToNext(L) = round(Base * Growth ^ L) for L in 0..Max-1.
-- XP earned at the level cap is discarded (not banked).
Constants.Experience = table.freeze({
	Base = 100,
	Growth = 1.18,
	-- Sanity cap for a single server-side grant; anything larger is a bug.
	MaxGrant = 1000000,
})

-- CLAUDE.md §7 (6 regular slots since D-75; Auto Attack can take one)
Constants.Loadout = table.freeze({
	RegularSlots = 6,
	SpecialSlots = 1,
})

-- CLAUDE.md §10 (+ PLAN.md D-08 for armor)
Constants.Enhancement = table.freeze({
	Max = 10,
	WeaponAttackPerLevel = 20,
	CritDamagePctPerLevel = 2.5,
	ArmorDefensePerLevel = 8,
})

Constants.Net = table.freeze({
	-- Folder under ReplicatedStorage that holds every remote. Created by the server only.
	RemotesFolderName = "Remotes",
	-- How long the client waits for the server to publish remotes before giving up.
	ClientRemoteWaitSeconds = 60,
})

-- Attribute names set by the server on well-known instances.
-- The build tag shown in Studio when the game starts (raise with each
-- change the creator should see; D-127).
Constants.BUILD = "D-134"

-- D-118: gear durability (a new item has Max).
Constants.Durability = table.freeze({
	Max = 100,
})

-- D-115: characters per account (all of the account's realm).
Constants.Characters = table.freeze({
	MaxSlots = 4,
})

Constants.Attributes = table.freeze({
	Maintenance = "RC_Maintenance",
	ConfigVersion = "RC_ConfigVersion",
	-- Flags.AutoAttack, mirrored for clients (the Auto-attack switch).
	AutoAttack = "RC_AutoAttack",
	-- D-105: Skills.FreeTreeReset / FreeAttributeReset (the Reset buttons).
	FreeTreeReset = "RC_FreeTreeReset",
	FreeAttributeReset = "RC_FreeAttributeReset",
	-- D-109: Mall.Prices, one attribute per entry: RC_MallPrice_<id>.
	MallPricePrefix = "RC_MallPrice_",
})

return table.freeze(Constants)
