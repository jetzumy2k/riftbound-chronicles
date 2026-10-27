--!strict
--[[
	ItemRules — pure rules for gear (Phase 7, PLAN.md D-64; CLAUDE.md §8-10).

	  roll           the server's attribute roll for a new item
	  bounds         the allowed range of one attribute (rarity, item level)
	  repairItem     validates / clamps a saved item (ProfileValidator)
	  baseStats      a piece's own stats (def, rarity, item level, +N)
	  gearTotals     what all equipped pieces add, capped
	  withGear       base character stats + gear (StatsService)
	  canEquip       job / race weapon family / level check
	  salvageYield   Stone Fragments for salvaging (D-09)

	Attributes ("random bonus attributes", CLAUDE.md §8): each item gets
	ROLLS[rarity] different stats from its pool (by category and job), each
	a value in bounds(stat, rarity, itemLevel). Flat stats grow with item
	level like the character stat they add to (Attack 1.10^L, Defense
	1.08^L, HP 1.20^L); percent stats don't.

	Stats (percent stats in percent units):
	  Attack, Defense, MaxHP        flat
	  CritChance, CritDamage        percentage points (D-02 / D-03)
	  HPRegen                       percentage points of max HP per second
	  SkillPower                    % more skill damage
	  HealingPower                  % more healing and shields
	  Mitigation                    % less damage taken
	  FocusEfficiency               % less Focus spent on skills

	Pure module.
]]

local Shared = script.Parent.Parent
local Enums = require(Shared.Enums)
local Constants = require(Shared.Constants)
local ItemDefinitions = require(Shared.Definitions.ItemDefinitions)
local JobDefinitions = require(Shared.Definitions.JobDefinitions)
local WeaponRules = require(Shared.Definitions.WeaponRules)
local StatFormulas = require(script.Parent.StatFormulas)

type ItemDef = ItemDefinitions.ItemDef

export type Attribute = { Stat: string, Value: number }

export type Item = {
	Guid: string,
	DefId: string,
	Rarity: string,
	ItemLevel: number,
	Attributes: { Attribute },
	Enhancement: number,
	Locked: boolean,
	Source: string,
	CreatedAt: number,
	-- D-118: 0..Constants.Durability.Max; nil = new.
	Durability: number?,
}

export type GearTotals = {
	Attack: number,
	Defense: number,
	MaxHP: number,
	CritChance: number,
	CritDamage: number,
	HPRegen: number,
	SkillPower: number,
	HealingPower: number,
	Mitigation: number,
	FocusEfficiency: number,
}

export type Stats = StatFormulas.BaseStats & {
	SkillPowerPct: number,
	HealingPowerPct: number,
	MitigationPct: number,
	FocusEfficiencyPct: number,
}

type StatSpec = {
	name: string,
	min: number, -- Standard, item level 0
	max: number,
	growth: number, -- per item level (1 = none)
	step: number, -- rounding step (1 = whole numbers)
	percent: boolean,
	cap: number?, -- most all gear together may add
}

local ItemRules = {}

ItemRules.INVENTORY_CAP = 150 -- D-09
ItemRules.MAX_SOURCE_LENGTH = 64
ItemRules.FRAGMENTS_PER_STONE = 10 -- D-09
ItemRules.GUID_PATTERN = "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"

local STATS: { [string]: StatSpec } = {
	Attack = table.freeze({ name = "Attack", min = 2, max = 5, growth = 1.10, step = 1, percent = false }),
	Defense = table.freeze({ name = "Defense", min = 2, max = 4, growth = 1.08, step = 1, percent = false }),
	MaxHP = table.freeze({ name = "Max HP", min = 6, max = 14, growth = 1.20, step = 1, percent = false }),
	CritChance = table.freeze({
		name = "Crit Chance",
		min = 0.5,
		max = 2,
		growth = 1,
		step = 0.01,
		percent = true,
		cap = 30,
	}),
	CritDamage = table.freeze({
		name = "Crit Damage",
		min = 2,
		max = 6,
		growth = 1,
		step = 0.01,
		percent = true,
	}),
	HPRegen = table.freeze({
		name = "HP Regen /s",
		min = 0.02,
		max = 0.06,
		growth = 1,
		step = 0.001,
		percent = true,
		cap = 1,
	}),
	SkillPower = table.freeze({
		name = "Skill Power",
		min = 2,
		max = 5,
		growth = 1,
		step = 0.01,
		percent = true,
		cap = 60,
	}),
	HealingPower = table.freeze({
		name = "Healing Power",
		min = 3,
		max = 7,
		growth = 1,
		step = 0.01,
		percent = true,
		cap = 60,
	}),
	Mitigation = table.freeze({
		name = "Damage Reduction",
		min = 1,
		max = 3,
		growth = 1,
		step = 0.01,
		percent = true,
		cap = 25,
	}),
	FocusEfficiency = table.freeze({
		name = "Focus Efficiency",
		min = 2,
		max = 5,
		growth = 1,
		step = 0.01,
		percent = true,
		cap = 25,
	}),
}
ItemRules.STATS = table.freeze(STATS)

-- Display order.
ItemRules.STAT_ORDER = table.freeze({
	"Attack",
	"Defense",
	"MaxHP",
	"CritChance",
	"CritDamage",
	"HPRegen",
	"SkillPower",
	"HealingPower",
	"Mitigation",
	"FocusEfficiency",
})

-- Different attributes an item of each rarity gets.
ItemRules.ROLLS = table.freeze({
	Standard = 1,
	Uncommon = 1,
	Rare = 2,
	Epic = 2,
	Legendary = 3,
	Mythical = 4,
})

-- Attribute ranges grow with rarity...
ItemRules.RANGE_SCALE = table.freeze({
	Standard = 1,
	Uncommon = 1.15,
	Rare = 1.3,
	Epic = 1.5,
	Legendary = 1.75,
	Mythical = 2,
})

-- ...and so do a piece's own stats.
ItemRules.BASE_SCALE = table.freeze({
	Standard = 1,
	Uncommon = 1.1,
	Rare = 1.2,
	Epic = 1.3,
	Legendary = 1.4,
	Mythical = 1.5,
})

-- D-09: Stone Fragments per salvaged item.
ItemRules.SALVAGE = table.freeze({
	Standard = 1,
	Uncommon = 2,
	Rare = 4,
	Epic = 6,
	Legendary = 10,
	Mythical = 15,
})

type PoolEntry = { stat: string, weight: number }

local function pool(entries: { { any } }): { PoolEntry }
	local out = {}
	for _, entry in entries do
		table.insert(out, table.freeze({ stat = entry[1], weight = entry[2] }))
	end
	return table.freeze(out)
end

--[[
	Attribute pools (CLAUDE.md §8): weapons by job, and gear (armor and
	the accessory) by job. The weight makes a job's signature stats likelier.
]]
ItemRules.POOLS = table.freeze({
	Weapon = table.freeze({
		Warrior = pool({ { "Attack", 4 }, { "CritChance", 2 }, { "CritDamage", 2 }, { "SkillPower", 2 } }),
		Healer = pool({ { "HealingPower", 4 }, { "SkillPower", 2 }, { "Attack", 2 }, { "CritChance", 1 } }),
		Archer = pool({ { "Attack", 3 }, { "CritChance", 3 }, { "CritDamage", 3 }, { "SkillPower", 2 } }),
		Mage = pool({ { "SkillPower", 4 }, { "Attack", 2 }, { "CritDamage", 2 }, { "CritChance", 2 } }),
	}),
	Gear = table.freeze({
		Warrior = pool({
			{ "MaxHP", 3 },
			{ "Defense", 3 },
			{ "Mitigation", 2 },
			{ "Attack", 2 },
			{ "HPRegen", 1 },
		}),
		Healer = pool({ { "MaxHP", 3 }, { "HealingPower", 3 }, { "Defense", 2 }, { "FocusEfficiency", 2 } }),
		-- D-95: Archer armour rolls Max HP and Defense too (it had only
		-- damage stats, so top rolls made Archers glass cannons).
		Archer = pool({
			{ "Attack", 2 },
			{ "MaxHP", 2 },
			{ "CritChance", 2 },
			{ "Defense", 2 },
			{ "CritDamage", 2 },
			{ "SkillPower", 2 },
		}),
		Mage = pool({
			{ "SkillPower", 3 },
			{ "MaxHP", 2 },
			{ "Defense", 2 },
			{ "CritDamage", 2 },
			{ "FocusEfficiency", 2 },
		}),
	}),
})

function ItemRules.poolFor(def: ItemDef): { PoolEntry }
	local group = if def.category == "Weapon" then ItemRules.POOLS.Weapon else ItemRules.POOLS.Gear
	return group[def.job]
end

local function roundStep(value: number, step: number): number
	return math.floor(value / step + 0.5) * step
end

-- Removes binary noise from a rounded value (0.07 stays 0.07).
local function clean(value: number, step: number): number
	if step >= 1 then
		return value
	end
	local digits = if step >= 0.01 then 100 else 1000
	return math.floor(value * digits + 0.5) / digits
end

--[[
	The allowed range (lo, hi) of `stat` on an item of `rarity` and
	`itemLevel`, after rounding. Every rolled value lies in it.
]]
function ItemRules.bounds(stat: string, rarity: string, itemLevel: number): (number, number)
	local spec = ItemRules.STATS[stat]
	local scale = ItemRules.RANGE_SCALE[rarity] * spec.growth ^ itemLevel
	local lo = math.max(spec.step, roundStep(spec.min * scale, spec.step))
	local hi = math.max(lo, roundStep(spec.max * scale, spec.step))
	return clean(lo, spec.step), clean(hi, spec.step)
end

--[[
	Rolls the attributes of a new `def` item. `random()` returns [0, 1)
	(the server's Random). Different stats, weighted by the pool.
]]
function ItemRules.roll(
	def: ItemDef,
	rarity: string,
	itemLevel: number,
	random: () -> number,
	valueRolls: number?
): { Attribute }
	local remaining = table.clone(ItemRules.poolFor(def))
	local out: { Attribute } = {}
	for _ = 1, math.min(ItemRules.ROLLS[rarity], #remaining) do
		local total = 0
		for _, entry in remaining do
			total += entry.weight
		end
		local pick = random() * total
		local index = #remaining
		for i, entry in remaining do
			pick -= entry.weight
			if pick < 0 then
				index = i
				break
			end
		end
		local entry = table.remove(remaining, index) :: PoolEntry
		local spec = ItemRules.STATS[entry.stat]
		local lo, hi = ItemRules.bounds(entry.stat, rarity, itemLevel)
		-- `valueRolls` > 1 (live event, D-89): the best of that many rolls.
		local r = random()
		for _ = 2, valueRolls or 1 do
			r = math.max(r, random())
		end
		local value = math.clamp(clean(roundStep(lo + (hi - lo) * r, spec.step), spec.step), lo, hi)
		table.insert(out, { Stat = entry.stat, Value = value })
	end
	return out
end

--[[
	Fixed attributes (Item Mall sets, D-93): no randomness. The piece gets
	its pool's ROLLS[rarity] most likely stats (highest weight first, pool
	order on ties), each at `quality` (0..1) of its range. Shown before
	buying, so what you see is what you get.
]]
ItemRules.FIXED_QUALITY = 0.85

function ItemRules.fixedRoll(def: ItemDef, rarity: string, itemLevel: number, quality: number?): { Attribute }
	local ranked = table.clone(ItemRules.poolFor(def))
	local order = {}
	for index, entry in ranked do
		order[entry] = index
	end
	table.sort(ranked, function(a, b)
		if a.weight ~= b.weight then
			return a.weight > b.weight
		end
		return order[a] < order[b]
	end)
	local q = quality or ItemRules.FIXED_QUALITY
	local out: { Attribute } = {}
	for i = 1, math.min(ItemRules.ROLLS[rarity], #ranked) do
		local entry = ranked[i]
		local spec = ItemRules.STATS[entry.stat]
		local lo, hi = ItemRules.bounds(entry.stat, rarity, itemLevel)
		local value = math.clamp(clean(roundStep(lo + (hi - lo) * q, spec.step), spec.step), lo, hi)
		table.insert(out, { Stat = entry.stat, Value = value })
	end
	return out
end

--------------------------------------------------------------------------------
-- Validation
--------------------------------------------------------------------------------

local function isFinite(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function inPool(def: ItemDef, stat: any): boolean
	for _, entry in ItemRules.poolFor(def) do
		if entry.stat == stat then
			return true
		end
	end
	return false
end

--[[
	Validates a saved item in place (DATA_MODEL.md §3). Returns false when
	it must be dropped (unknown def, bad rarity, bad guid); otherwise
	clamps what it can and returns true plus notes.
]]
function ItemRules.repairItem(guid: any, item: any): (boolean, { string })
	local notes = {}
	if type(item) ~= "table" or type(guid) ~= "string" or item.Guid ~= guid then
		return false, { "guid mismatch" }
	end
	if string.match(guid, ItemRules.GUID_PATTERN) == nil then
		return false, { "bad guid" }
	end
	local def = ItemDefinitions.get(item.DefId)
	if def == nil then
		return false, { `unknown DefId {tostring(item.DefId)}` }
	end
	if not Enums.has(Enums.Rarity, item.Rarity) then
		return false, { `bad rarity {tostring(item.Rarity)}` }
	end
	for key in item do
		if
			key ~= "Guid"
			and key ~= "DefId"
			and key ~= "Rarity"
			and key ~= "ItemLevel"
			and key ~= "Attributes"
			and key ~= "Enhancement"
			and key ~= "Locked"
			and key ~= "Source"
			and key ~= "CreatedAt"
		then
			item[key] = nil
			table.insert(notes, `dropped key {tostring(key)}`)
		end
	end
	local level = item.ItemLevel
	if not isFinite(level) or level % 1 ~= 0 or level < def.minItemLevel or level > def.maxItemLevel then
		local fixed = if isFinite(level)
			then math.clamp(math.floor(level), def.minItemLevel, def.maxItemLevel)
			else def.minItemLevel
		table.insert(notes, `ItemLevel {tostring(level)} -> {fixed}`)
		item.ItemLevel = fixed
	end
	local enhancement = item.Enhancement
	if
		not isFinite(enhancement)
		or enhancement % 1 ~= 0
		or enhancement < 0
		or enhancement > Constants.Enhancement.Max
	then
		local fixed = if isFinite(enhancement)
			then math.clamp(math.floor(enhancement), 0, Constants.Enhancement.Max)
			else 0
		table.insert(notes, `Enhancement {tostring(enhancement)} -> {fixed}`)
		item.Enhancement = fixed
	end
	if type(item.Locked) ~= "boolean" then
		item.Locked = false
		table.insert(notes, "Locked reset")
	end
	-- D-118: items from before durability start new (no note: expected).
	local durability = item.Durability
	if durability == nil then
		item.Durability = Constants.Durability.Max
	elseif not isFinite(durability) or durability < 0 or durability > Constants.Durability.Max then
		local fixed = if isFinite(durability) then math.clamp(durability, 0, Constants.Durability.Max) else 0
		table.insert(notes, `Durability {tostring(durability)} -> {fixed}`)
		item.Durability = fixed
	end
	if type(item.Source) ~= "string" or #item.Source == 0 or #item.Source > ItemRules.MAX_SOURCE_LENGTH then
		item.Source = "Unknown"
		table.insert(notes, "Source reset")
	end
	if not isFinite(item.CreatedAt) or item.CreatedAt < 0 then
		item.CreatedAt = 0
		table.insert(notes, "CreatedAt reset")
	end
	-- Attributes: from the pool, no repeats, at most the rarity's count,
	-- values clamped into bounds.
	local attributes = if type(item.Attributes) == "table" then item.Attributes else {}
	local kept: { Attribute } = {}
	local seen = {}
	for _, attribute in attributes do
		if #kept >= ItemRules.ROLLS[item.Rarity] then
			table.insert(notes, "extra attribute dropped")
			break
		end
		local stat = type(attribute) == "table" and attribute.Stat
		if not inPool(def, stat) or seen[stat] or not isFinite(attribute.Value) then
			table.insert(notes, `attribute {tostring(stat)} dropped`)
			continue
		end
		seen[stat] = true
		local lo, hi = ItemRules.bounds(stat, item.Rarity, item.ItemLevel)
		local value = math.clamp(attribute.Value, lo, hi)
		if value ~= attribute.Value then
			table.insert(notes, `attribute {stat} {attribute.Value} -> {value}`)
		end
		table.insert(kept, { Stat = stat, Value = value })
	end
	item.Attributes = kept
	return true, notes
end

--------------------------------------------------------------------------------
-- Stats
--------------------------------------------------------------------------------

local function emptyTotals(): GearTotals
	return {
		Attack = 0,
		Defense = 0,
		MaxHP = 0,
		CritChance = 0,
		CritDamage = 0,
		HPRegen = 0,
		SkillPower = 0,
		HealingPower = 0,
		Mitigation = 0,
		FocusEfficiency = 0,
	}
end

-- Defense / HP of each armor kind at item level 0 (Standard).
local ARMOR_BASE = {
	Helm = { Defense = 2.5, MaxHP = 0 },
	Shoulders = { Defense = 2, MaxHP = 0 },
	Chest = { Defense = 4, MaxHP = 8 },
	Hands = { Defense = 1.5, MaxHP = 0 },
	Legs = { Defense = 3, MaxHP = 6 },
	Boots = { Defense = 2, MaxHP = 0 },
	Shield = { Defense = 5, MaxHP = 6 },
	Necklace = { Defense = 0, MaxHP = 6 },
	Earrings = { Defense = 0, MaxHP = 3 },
	Ring = { Defense = 0, MaxHP = 3 },
}
local WEAPON_ATTACK = 10
-- Two-handed weapons hit harder (no shield, no second blade, D-68).
local TWO_HANDED_SCALE = 1.3
-- An off-hand sword (dual swords) adds half its own Attack.
ItemRules.OFF_HAND_ATTACK = 0.5

--[[
	A piece's own stats (not its attributes): weapons give Attack, armor
	Defense (chest and legs some HP too), the accessory HP; all grow with
	item level and rarity. Enhancement (CLAUDE.md §10, Phase 8): weapons
	+20 Attack and +2.5% Crit Damage per +1; armor and accessories +8
	Defense per +1 (D-08).
]]
function ItemRules.baseStats(def: ItemDef, rarity: string, itemLevel: number, enhancement: number): GearTotals
	local out = emptyTotals()
	local scale = ItemRules.BASE_SCALE[rarity] or 1
	local growth = Constants.StatGrowth
	local plus = Constants.Enhancement
	if def.category == "Weapon" then
		local rule = WeaponRules.get(def.family)
		local hands = if rule and rule.hands == "Two" then TWO_HANDED_SCALE else 1
		out.Attack = math.floor(WEAPON_ATTACK * hands * growth.AttackMultiplier ^ itemLevel * scale + 0.5)
			+ plus.WeaponAttackPerLevel * enhancement
		out.CritDamage = plus.CritDamagePctPerLevel * enhancement
	else
		local base = ARMOR_BASE[def.slot]
		out.Defense = math.floor(base.Defense * growth.DefenseMultiplier ^ itemLevel * scale + 0.5)
			+ plus.ArmorDefensePerLevel * enhancement
		out.MaxHP = math.floor(base.MaxHP * growth.HPMultiplier ^ itemLevel * scale + 0.5)
	end
	return out
end

-- Everything one item adds: its own stats plus its attributes. In the
-- off-hand a weapon's own Attack and Crit Damage count half (dual swords).
function ItemRules.itemStats(item: Item, offHand: boolean?): GearTotals?
	local def = ItemDefinitions.get(item.DefId)
	if def == nil then
		return nil
	end
	local out = ItemRules.baseStats(def, item.Rarity, item.ItemLevel, item.Enhancement)
	if offHand and def.category == "Weapon" then
		out.Attack = math.floor(out.Attack * ItemRules.OFF_HAND_ATTACK + 0.5)
		out.CritDamage *= ItemRules.OFF_HAND_ATTACK
	end
	for _, attribute in item.Attributes do
		local key = attribute.Stat :: any
		if (out :: any)[key] ~= nil then
			(out :: any)[key] += attribute.Value
		end
	end
	return out
end

--[[
	What the equipped items add together. `equipment` maps slot -> guid,
	`inventory` guid -> item; dangling or wrong-slot entries are ignored.
	Percent stats are capped (STATS[...].cap).
]]
function ItemRules.gearTotals(equipment: { [string]: string }, inventory: { [string]: Item }): GearTotals
	local out = emptyTotals()
	for slot, guid in equipment do
		local item = inventory[guid]
		local def = item and ItemDefinitions.get(item.DefId)
		if item == nil or def == nil or not ItemRules.fitsSlot(def, slot) then
			continue
		end
		-- D-118: a broken piece adds nothing until it is repaired.
		if type(item.Durability) == "number" and item.Durability <= 0 then
			continue
		end
		local stats = ItemRules.itemStats(item, slot == "OffHand")
		if stats then
			for key, value in stats :: any do
				(out :: any)[key] += value
			end
		end
	end
	for key, spec in ItemRules.STATS do
		if spec.cap then
			(out :: any)[key] = math.min((out :: any)[key], spec.cap)
		end
	end
	return out
end

-- Base character stats plus gear.
function ItemRules.withGear(base: StatFormulas.BaseStats, gear: GearTotals): Stats
	local critDamagePct = base.CritDamagePct + gear.CritDamage
	return table.freeze({
		MaxHP = base.MaxHP + gear.MaxHP,
		Attack = base.Attack + gear.Attack,
		Defense = base.Defense + gear.Defense,
		CritDamagePct = critDamagePct,
		HPRegenPct = base.HPRegenPct + gear.HPRegen,
		CritChancePct = base.CritChancePct + gear.CritChance,
		CritMultiplier = Constants.Crit.BaseMultiplier + critDamagePct / 100,
		SkillPowerPct = gear.SkillPower,
		HealingPowerPct = gear.HealingPower,
		MitigationPct = gear.Mitigation,
		FocusEfficiencyPct = gear.FocusEfficiency,
	})
end

--------------------------------------------------------------------------------
-- Equipping and salvage
--------------------------------------------------------------------------------

--[[
	Whether a character (job, race, level) may wear `item`. Reasons:
	"unknown", "job", "race" (a weapon family the race doesn't use),
	"level".
]]
function ItemRules.canEquip(item: Item, job: string?, race: string?, level: number): (boolean, string?)
	local def = ItemDefinitions.get(item.DefId)
	if def == nil then
		return false, "unknown"
	end
	if def.job ~= job then
		return false, "job"
	end
	if def.family and not JobDefinitions.allowsWeapon(job, race, def.family) then
		return false, "race"
	end
	if level < item.ItemLevel then
		return false, "level"
	end
	return true, nil
end

--[[
	Whether a piece of `def` can sit in equipment `slot` at all (D-68):
	its own slot; a ring in Ring1 / Ring2; a shield in the off-hand; a
	dual-wield weapon (Warrior short sword) in the off-hand.
]]
function ItemRules.fitsSlot(def: ItemDef, slot: string): boolean
	local kind = def.slot
	if kind == slot then
		return true
	elseif kind == "Ring" then
		return slot == "Ring1" or slot == "Ring2"
	elseif kind == "Shield" then
		return slot == "OffHand"
	elseif kind == "Weapon" and slot == "OffHand" then
		local rule = WeaponRules.get(def.family)
		return rule ~= nil and rule.dual
	end
	return false
end

local function defIn(equipment: { [string]: string }, inventory: { [string]: Item }, slot: string): ItemDef?
	local guid = equipment[slot]
	local item = guid and inventory[guid]
	return if item then ItemDefinitions.get(item.DefId) else nil
end

--[[
	Whether the main hand and off-hand go together (D-68): a shield needs an
	empty main hand or a one-hander that allows it; an off-hand weapon
	needs the same dual-wield family in the main hand.
]]
function ItemRules.handsCompatible(main: ItemDef?, off: ItemDef?): boolean
	if off == nil then
		return true
	end
	local rule = main and WeaponRules.get(main.family)
	if off.slot == "Shield" then
		return main == nil or (rule ~= nil and rule.shield)
	end
	return main ~= nil and rule ~= nil and rule.dual and main.family == off.family
end

export type EquipPlan = {
	slot: string, -- where the item goes
	clear: { string }, -- slots emptied first (their items go back to the bag)
}

--[[
	Where `guid` goes when equipped, and what has to come off (D-68). The
	one conflict rule: **the newest item wins**; anything it can't be worn
	with goes back to the bag (never deleted). `target` picks Ring1 / Ring2
	or the off-hand for a second sword. Reasons: "unknown", "slot" (it
	can't go in `target`), "dualNeedsSword" (an off-hand sword needs the
	same kind of sword in the main hand).
]]
function ItemRules.planEquip(
	equipment: { [string]: string },
	inventory: { [string]: Item },
	guid: string,
	target: string?
): (EquipPlan?, string?)
	local item = inventory[guid]
	local def = item and ItemDefinitions.get(item.DefId)
	if def == nil then
		return nil, "unknown"
	end
	local slot: string
	if target then
		if not ItemRules.fitsSlot(def, target) then
			return nil, "slot"
		end
		slot = target
	elseif def.slot == "Ring" then
		slot = if equipment.Ring1 == nil or equipment.Ring1 == guid
			then "Ring1"
			elseif equipment.Ring2 == nil then "Ring2"
			else "Ring1"
	elseif def.slot == "Shield" then
		slot = "OffHand"
	else
		slot = def.slot
	end
	local clear = {}
	-- Moving between slots (a ring, a sword from one hand to the other).
	for other, equipped in equipment do
		if equipped == guid and other ~= slot then
			table.insert(clear, other)
		end
	end
	local function cleared(s: string): boolean
		return table.find(clear, s) ~= nil
	end
	local main = if slot == "Weapon"
		then def
		elseif cleared("Weapon") then nil
		else defIn(equipment, inventory, "Weapon")
	local off = if slot == "OffHand"
		then def
		elseif cleared("OffHand") then nil
		else defIn(equipment, inventory, "OffHand")
	if slot == "OffHand" and def.slot == "Weapon" and not ItemRules.handsCompatible(main, def) then
		return nil, "dualNeedsSword"
	end
	if not ItemRules.handsCompatible(main, off) then
		-- The newest item wins: clear the other hand.
		table.insert(clear, if slot == "OffHand" then "Weapon" else "OffHand")
	end
	local plan: EquipPlan = { slot = slot :: string, clear = clear }
	return plan, nil
end

export type Comparison = {
	slot: string,
	-- Items that leave the body (the slot's current piece, a cleared hand).
	replaces: { string },
	-- Gear total changes, in STAT_ORDER; only stats that change.
	deltas: { { stat: string, value: number } },
}

--[[
	What equipping `guid` (into `target`, as planEquip) would change: the
	pieces it replaces and the gear totals before vs after, caps included
	(stage 6, D-72). Nil and planEquip's reason when it can't go there.
]]
function ItemRules.compareEquip(
	equipment: { [string]: string },
	inventory: { [string]: Item },
	guid: string,
	target: string?
): (Comparison?, string?)
	local plan, reason = ItemRules.planEquip(equipment, inventory, guid, target)
	if plan == nil then
		return nil, reason
	end
	local after = table.clone(equipment)
	local replaces = {}
	local function leave(slot: string)
		local current = after[slot]
		if current and current ~= guid and not table.find(replaces, current) then
			table.insert(replaces, current)
		end
		after[slot] = nil
	end
	for _, slot in plan.clear do
		leave(slot)
	end
	leave(plan.slot)
	after[plan.slot] = guid
	local before = ItemRules.gearTotals(equipment, inventory)
	local now = ItemRules.gearTotals(after, inventory)
	local deltas = {}
	for _, stat in ItemRules.STAT_ORDER do
		local value = (now :: any)[stat] - (before :: any)[stat]
		if math.abs(value) > 1e-6 then
			table.insert(deltas, { stat = stat, value = value })
		end
	end
	return { slot = plan.slot, replaces = replaces, deltas = deltas }, nil
end

function ItemRules.salvageYield(item: Item): number
	return ItemRules.SALVAGE[item.Rarity] or 0
end

function ItemRules.statName(stat: string): string
	local spec = ItemRules.STATS[stat]
	return if spec then spec.name else stat
end

-- "+12 Attack", "+1.25% Crit Chance".
function ItemRules.formatStat(stat: string, value: number): string
	local spec = ItemRules.STATS[stat]
	if spec == nil then
		return `+{value} {stat}`
	end
	if spec.percent then
		local text = if spec.step < 0.01 then string.format("%.3f", value) else string.format("%.2f", value)
		text = string.gsub(text, "%.?0+$", "")
		return `+{text}% {spec.name}`
	end
	return `+{math.floor(value + 0.5)} {spec.name}`
end

-- "▲ +12 Attack" / "▼ -1.25% Crit Chance": the arrow carries the sign, so
-- colour is never the only cue (CLAUDE.md §28).
function ItemRules.formatDelta(stat: string, value: number): string
	if value < 0 then
		return "▼ -" .. string.sub(ItemRules.formatStat(stat, -value), 2)
	end
	return "▲ " .. ItemRules.formatStat(stat, value)
end

return table.freeze(ItemRules)
