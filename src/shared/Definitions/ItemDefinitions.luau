--!strict
--[[
	ItemDefinitions — every gear piece and stackable (Phase 7, PLAN.md D-64;
	CLAUDE.md §8-9, D-25 slots). Display-safe: the client may read all of it.

	Gear is generated from small tables:
	  - weapons: one per job and weapon family (JobDefinitions.weaponsByRace,
	    so Angel / Devil families differ for warriors), per tier;
	  - armor: Helm, Chest, Legs, Boots per job, per tier;
	  - accessories: one per job, per tier (CLAUDE.md §17 Quest 3 "class-
	    specific accessory").
	Tiers cover item levels 0-9, 10-19 and 20-30 (`ItemDefinitions.tierFor`).
	A dropped item takes the def of its job / slot / family for the tier its
	item level falls in.

	Ids: "W_<Job>_<Family>_T<n>" (weapons), "A_<Job>_<Slot>_T<n>" (armor and
	accessories). Ids are saved in profiles: never rename one; removing one
	drops those items on load (logged in full, DATA_MODEL.md §3).

	Stackables: Enhancement Stone, Perfect Stone, Stone Fragment (D-09
	salvage; 10 make a stone) and the Healing Potion (Quest 1 consumable).
]]

local JobDefinitions = require(script.Parent.JobDefinitions)

export type Category = "Weapon" | "Shield" | "Armor" | "Accessory"

export type ItemDef = {
	id: string,
	name: string,
	-- What it is worn as: "Weapon", "Shield", an armor slot, "Necklace",
	-- "Earrings" or "Ring" (Ring1 / Ring2). ItemRules.fitsSlot maps it to
	-- equipment slots (D-68).
	slot: string,
	category: Category,
	job: string, -- job restriction (every gear piece belongs to one job)
	family: string?, -- weapons: Enums.WeaponType
	tier: number, -- 1..3
	minItemLevel: number,
	maxItemLevel: number,
	glyph: string, -- inventory tile icon
}

export type StackableDef = {
	id: string,
	name: string,
	description: string,
	glyph: string,
	maxStack: number,
	-- Consumables: what using one does (applied by the server).
	use: { kind: "HealPct", pct: number, cooldown: number }?,
}

local ItemDefinitions = {}

ItemDefinitions.TIERS = 3
ItemDefinitions.TIER_LEVELS = table.freeze({
	table.freeze({ 0, 9 }),
	table.freeze({ 10, 19 }),
	table.freeze({ 20, 30 }),
})

-- Name prefix per job and tier.
local PREFIX = {
	Warrior = { "Recruit's", "Vanguard", "Warlord's" },
	Healer = { "Acolyte's", "Mender's", "Saint's" },
	Archer = { "Scout's", "Ranger's", "Hawkeye" },
	Mage = { "Novice's", "Arcanist's", "Archmage's" },
}

-- Armor and accessory nouns per job and kind. "Accessory" ids (the D-64
-- class accessory) are now worn as the necklace (D-68).
local ARMOR_NOUN = {
	Warrior = {
		Helm = "Helm",
		Shoulders = "Pauldrons",
		Chest = "Plate",
		Hands = "Gauntlets",
		Legs = "Greaves",
		Boots = "Sabatons",
		Shield = "Shield",
		Accessory = "Signet Amulet",
		Earrings = "Studs",
		Ring = "Band",
	},
	Healer = {
		Helm = "Circlet",
		Shoulders = "Mantle",
		Chest = "Vestment",
		Hands = "Gloves",
		Legs = "Leggings",
		Boots = "Sandals",
		Accessory = "Charm",
		Earrings = "Drops",
		Ring = "Ring",
	},
	Archer = {
		Helm = "Hood",
		Shoulders = "Shoulder Guard",
		Chest = "Jerkin",
		Hands = "Bracers",
		Legs = "Breeches",
		Boots = "Treads",
		Accessory = "Talisman",
		Earrings = "Hoops",
		Ring = "Signet",
	},
	Mage = {
		Helm = "Cowl",
		Shoulders = "Spaulders",
		Chest = "Robe",
		Hands = "Wraps",
		Legs = "Skirt",
		Boots = "Slippers",
		Accessory = "Focus Pendant",
		Earrings = "Runes",
		Ring = "Focus Ring",
	},
}

-- Player-facing weapon category names (WeaponRules has the full rules).
local FAMILY_NAME = {
	Sword = "Short Sword",
	Greatsword = "Longsword",
	WarHammer = "War Hammer",
	BattleAxe = "Battle Axe",
	Axe = "Hand Axe",
}

local SLOT_GLYPH = {
	Helm = "👑",
	Shoulders = "🧥",
	Chest = "🛡",
	Hands = "🧤",
	Legs = "👖",
	Boots = "👢",
	Shield = "🛡",
	Accessory = "📿",
	Earrings = "💠",
	Ring = "💍",
}

local FAMILY_GLYPH = {
	Sword = "🗡",
	Greatsword = "🗡",
	Polearm = "🔱",
	Mace = "🔨",
	Axe = "🔨",
	WarHammer = "🔨",
	BattleAxe = "🔨",
	Dagger = "🔪",
	Staff = "🌟",
	Orb = "🔮",
	Bow = "🏹",
	Crossbow = "🏹",
	Wand = "🎇",
	Tome = "📖",
}

local ARMOR_SLOTS = { "Helm", "Shoulders", "Chest", "Hands", "Legs", "Boots" }
-- Kinds generated per job (the id keeps "Accessory" for the necklace).
local KINDS = { "Helm", "Shoulders", "Chest", "Hands", "Legs", "Boots", "Accessory", "Earrings", "Ring" }
local KIND_SLOT = { Accessory = "Necklace" }
local ACCESSORY_KINDS = { Accessory = true, Earrings = true, Ring = true }

local all: { [string]: ItemDef } = {}
local ids: { string } = {}

local function add(def: ItemDef)
	assert(all[def.id] == nil, `duplicate item id {def.id}`)
	all[def.id] = table.freeze(def)
	table.insert(ids, def.id)
end

-- Every weapon family a job may wield in either race, in a stable order.
local function familiesOf(job: string): { string }
	local definition = JobDefinitions.get(job)
	local out = {}
	if definition then
		for _, race in { "Angel", "Devil" } do
			local families: { string } = definition.weaponsByRace[race] or {}
			for _, family in families do
				if table.find(out, family) == nil then
					table.insert(out, family)
				end
			end
		end
	end
	return out
end

for _, job in JobDefinitions.Order do
	for tier = 1, ItemDefinitions.TIERS do
		local band = ItemDefinitions.TIER_LEVELS[tier]
		local prefix = PREFIX[job][tier]
		for _, family in familiesOf(job) do
			add({
				id = `W_{job}_{family}_T{tier}`,
				name = `{prefix} {FAMILY_NAME[family] or family}`,
				slot = "Weapon",
				category = "Weapon",
				job = job,
				family = family,
				tier = tier,
				minItemLevel = band[1],
				maxItemLevel = band[2],
				glyph = FAMILY_GLYPH[family] or "🗡",
			})
		end
		local kinds = table.clone(KINDS)
		if ARMOR_NOUN[job].Shield then
			table.insert(kinds, "Shield")
		end
		for _, kind in kinds do
			add({
				id = `A_{job}_{kind}_T{tier}`,
				name = `{prefix} {ARMOR_NOUN[job][kind]}`,
				slot = KIND_SLOT[kind] or kind,
				category = if ACCESSORY_KINDS[kind]
					then "Accessory"
					elseif kind == "Shield" then "Shield"
					else "Armor",
				job = job,
				family = nil,
				tier = tier,
				minItemLevel = band[1],
				maxItemLevel = band[2],
				glyph = SLOT_GLYPH[kind],
			})
		end
	end
end

ItemDefinitions.All = table.freeze(all)
ItemDefinitions.IDS = table.freeze(ids)
ItemDefinitions.ARMOR_SLOTS = table.freeze(ARMOR_SLOTS)

function ItemDefinitions.get(id: any): ItemDef?
	return if type(id) == "string" then all[id] else nil
end

-- Tier (1..3) an item level falls in.
function ItemDefinitions.tierFor(itemLevel: number): number
	for tier, band in ItemDefinitions.TIER_LEVELS do
		if itemLevel <= band[2] then
			return tier
		end
	end
	return ItemDefinitions.TIERS
end

-- The def for a job's piece of `kind` (an ItemDef.slot value, and the weapon
-- `family`) at an item level.
function ItemDefinitions.defFor(job: string, kind: string, family: string?, itemLevel: number): ItemDef?
	local tier = ItemDefinitions.tierFor(itemLevel)
	if kind == "Weapon" then
		return all[`W_{job}_{family}_T{tier}`]
	end
	return all[`A_{job}_{if kind == "Necklace" then "Accessory" else kind}_T{tier}`]
end

-- Every kind of piece a job has (weapons first), for loot and test kits.
function ItemDefinitions.kindsOf(job: string): { string }
	local out =
		{ "Weapon", "Helm", "Shoulders", "Chest", "Hands", "Legs", "Boots", "Necklace", "Earrings", "Ring" }
	if all[`A_{job}_Shield_T1`] then
		table.insert(out, 2, "Shield")
	end
	return out
end

-- Weapon families a job may wield, in either race.
ItemDefinitions.familiesOf = familiesOf

--------------------------------------------------------------------------------
-- Stackables
--------------------------------------------------------------------------------

local stackables: { [string]: StackableDef } = {
	EnhancementStone = {
		id = "EnhancementStone",
		name = "Enhancement Stone",
		description = "Raises a weapon or gear piece by +1 (enhancement opens later).",
		glyph = "💎",
		maxStack = 9999,
		use = nil,
	},
	PerfectStone = {
		id = "PerfectStone",
		name = "Perfect Enhancement Stone",
		description = "An enhancement that always succeeds (enhancement opens later).",
		glyph = "✨",
		maxStack = 9999,
		use = nil,
	},
	StoneFragment = {
		id = "StoneFragment",
		name = "Stone Fragment",
		description = "Salvaged from gear. 10 fragments combine into an Enhancement Stone.",
		glyph = "🔹",
		maxStack = 99999,
		use = nil,
	},
	HealingPotion = {
		id = "HealingPotion",
		name = "Healing Potion",
		description = "Restores 30% of your health at once. Usable every 15 seconds.",
		glyph = "🧪",
		maxStack = 999,
		use = { kind = "HealPct", pct = 30, cooldown = 15 },
	},
}

local stackableIds = {}
for id, def in stackables do
	table.freeze(def)
	table.insert(stackableIds, id)
end
table.sort(stackableIds)

ItemDefinitions.Stackables = table.freeze(stackables)
ItemDefinitions.STACKABLE_IDS = table.freeze(stackableIds)
-- Display order in the inventory.
ItemDefinitions.STACKABLE_ORDER =
	table.freeze({ "HealingPotion", "EnhancementStone", "PerfectStone", "StoneFragment" })

-- Ids of usable stackables (consumables).
local consumables = {}
for _, id in stackableIds do
	if stackables[id].use then
		table.insert(consumables, id)
	end
end
ItemDefinitions.CONSUMABLE_IDS = table.freeze(consumables)

function ItemDefinitions.stackable(id: any): StackableDef?
	return if type(id) == "string" then stackables[id] else nil
end

return table.freeze(ItemDefinitions)
