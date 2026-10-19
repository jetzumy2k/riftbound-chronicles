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

export type Category = "Weapon" | "Armor" | "Accessory"

export type ItemDef = {
	id: string,
	name: string,
	slot: string, -- Enums.ItemSlot
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

-- Armor nouns per job and slot.
local ARMOR_NOUN = {
	Warrior = { Helm = "Helm", Chest = "Plate", Legs = "Greaves", Boots = "Sabatons", Accessory = "Signet" },
	Healer = {
		Helm = "Circlet",
		Chest = "Vestment",
		Legs = "Leggings",
		Boots = "Sandals",
		Accessory = "Charm",
	},
	Archer = {
		Helm = "Hood",
		Chest = "Jerkin",
		Legs = "Breeches",
		Boots = "Treads",
		Accessory = "Quiver Band",
	},
	Mage = { Helm = "Cowl", Chest = "Robe", Legs = "Skirt", Boots = "Slippers", Accessory = "Focus Ring" },
}

local SLOT_GLYPH = {
	Helm = "⛑",
	Chest = "🛡",
	Legs = "👖",
	Boots = "👢",
	Accessory = "💍",
}

local FAMILY_GLYPH = {
	Sword = "🗡",
	Greatsword = "⚔",
	Polearm = "🔱",
	Mace = "🔨",
	Axe = "🪓",
	Staff = "🪄",
	Orb = "🔮",
	Bow = "🏹",
	Crossbow = "🏹",
	Wand = "🪄",
	Tome = "📖",
}

local ARMOR_SLOTS = { "Helm", "Chest", "Legs", "Boots" }

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
				name = `{prefix} {family}`,
				slot = "Weapon",
				category = "Weapon",
				job = job,
				family = family,
				tier = tier,
				minItemLevel = band[1],
				maxItemLevel = band[2],
				glyph = FAMILY_GLYPH[family] or "⚔",
			})
		end
		for _, slot in { "Helm", "Chest", "Legs", "Boots", "Accessory" } do
			add({
				id = `A_{job}_{slot}_T{tier}`,
				name = `{prefix} {ARMOR_NOUN[job][slot]}`,
				slot = slot,
				category = if slot == "Accessory" then "Accessory" else "Armor",
				job = job,
				family = nil,
				tier = tier,
				minItemLevel = band[1],
				maxItemLevel = band[2],
				glyph = SLOT_GLYPH[slot],
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

-- The def for a job's piece in `slot` (and weapon `family`) at an item level.
function ItemDefinitions.defFor(job: string, slot: string, family: string?, itemLevel: number): ItemDef?
	local tier = ItemDefinitions.tierFor(itemLevel)
	if slot == "Weapon" then
		return all[`W_{job}_{family}_T{tier}`]
	end
	return all[`A_{job}_{slot}_T{tier}`]
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
