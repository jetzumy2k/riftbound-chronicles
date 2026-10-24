--!strict
--[[
	LootRules — pure rules for loot tables (Phase 10, PLAN.md D-06 / D-07 /
	D-67; CLAUDE.md §12).

	A loot table has a drop chance and, given a drop, rarity weights:

	  { DropChancePct = 12, Rarity = { Standard = 45, Uncommon = 25, Rare = 30 } }

	  validate     a table is usable: chance 0..100, known rarities, each
	               weight 0..100, weights summing to 100
	  roll         the rarity that drops (nil = nothing), from two server
	               rolls in [0, 1)
	  pickPiece    which piece of the player's own class drops (slot and,
	               for weapons, a family their realm uses)
	  validateStones / rollStone   stone tables (Phase 14, war-zone
	               creatures): a drop chance and stone weights summing to 100

	CLAUDE.md §15 (Phase 14, D-76): the PvP boss table is 20% Mythical /
	80% Rare; PvP regular creatures drop 30% Perfect Enhancement Stone / 70%
	Enhancement Stone, given a drop (the drop chance is separate, as D-06).

	CLAUDE.md §12 interpretation (documented in config too): a regular mob's
	"30% rare / 70% rare" means 30% Rare / 70% Standard-or-Uncommon, split
	45% Standard / 25% Uncommon (D-07); bosses 20% Legendary / 80% Rare.
	Whether anything drops at all is the separate drop chance (D-06).

	Pure module.
]]

local Enums = require(script.Parent.Parent.Enums)
local JobDefinitions = require(script.Parent.Parent.Definitions.JobDefinitions)
local ItemDefinitions = require(script.Parent.Parent.Definitions.ItemDefinitions)

export type Table = {
	DropChancePct: number,
	Rarity: { [string]: number },
}

export type StoneTable = {
	DropChancePct: number,
	Stones: { [string]: number },
}

local LootRules = {}

LootRules.TABLE_IDS = table.freeze({
	"DungeonMob",
	"DungeonElite",
	"DungeonMiniBoss",
	"DungeonFloorBoss",
	"DungeonBoss",
	"WarZoneBoss",
})
LootRules.STONE_TABLE_IDS = table.freeze({ "WarZoneMob" })
-- Stones a stone table may drop, in a stable roll order.
LootRules.STONES = table.freeze({ "EnhancementStone", "PerfectStone" })

-- Which kind of piece drops, by weight (D-68): weapons most, armor
-- pieces next, shields (Warrior only) and jewellery least.
LootRules.SLOT_WEIGHTS = table.freeze({
	{ slot = "Weapon", weight = 4 },
	{ slot = "Helm", weight = 2 },
	{ slot = "Shoulders", weight = 2 },
	{ slot = "Chest", weight = 2 },
	{ slot = "Hands", weight = 2 },
	{ slot = "Legs", weight = 2 },
	{ slot = "Boots", weight = 2 },
	{ slot = "Shield", weight = 1 },
	{ slot = "Necklace", weight = 1 },
	{ slot = "Earrings", weight = 1 },
	{ slot = "Ring", weight = 1 },
})

local EPSILON = 1e-6

local function isNumber(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

--[[
	Whether `t` is a usable loot table. Returns false and a reason when not:
	"chance", "rarity" (unknown or bad weight), "sum" (weights ≠ 100),
	"shape".
]]
function LootRules.validate(t: any): (boolean, string?)
	if type(t) ~= "table" or type(t.Rarity) ~= "table" then
		return false, "shape"
	end
	if not isNumber(t.DropChancePct) or t.DropChancePct < 0 or t.DropChancePct > 100 then
		return false, "chance"
	end
	local sum = 0
	for rarity, weight in t.Rarity do
		if not Enums.has(Enums.Rarity, rarity) or not isNumber(weight) or weight < 0 or weight > 100 then
			return false, "rarity"
		end
		sum += weight
	end
	if math.abs(sum - 100) > EPSILON then
		return false, "sum"
	end
	return true, nil
end

--[[
	The rarity that drops, or nil. `dropRoll` decides whether anything
	drops, `rarityRoll` which rarity (both in [0, 1)). Rarities are walked
	from lowest to highest so the order is stable.
]]
function LootRules.roll(t: Table, dropRoll: number, rarityRoll: number): string?
	if dropRoll * 100 >= t.DropChancePct then
		return nil
	end
	local pick = rarityRoll * 100
	local last: string? = nil
	for _, rarity in Enums.Rarity do
		local weight = t.Rarity[rarity]
		if weight and weight > 0 then
			last = rarity
			pick -= weight
			if pick < 0 then
				return rarity
			end
		end
	end
	return last
end

--[[
	The piece that drops for a character of `job` and `race` at
	`itemLevel`: a slot by SLOT_WEIGHTS and, for a weapon, a family the
	realm uses. Returns the def (nil only for an unknown job).
]]
function LootRules.pickPiece(
	job: string,
	race: string?,
	itemLevel: number,
	slotRoll: number,
	familyRoll: number
): ItemDefinitions.ItemDef?
	-- Only kinds the class has (shields are Warrior gear).
	local kinds = ItemDefinitions.kindsOf(job)
	local entries = {}
	local total = 0
	for _, entry in LootRules.SLOT_WEIGHTS do
		if table.find(kinds, entry.slot) then
			table.insert(entries, entry)
			total += entry.weight
		end
	end
	local pick = slotRoll * total
	local slot = "Weapon"
	for _, entry in entries do
		pick -= entry.weight
		if pick < 0 then
			slot = entry.slot
			break
		end
	end
	local family: string? = nil
	if slot == "Weapon" then
		local usable = {}
		for _, candidate in ItemDefinitions.familiesOf(job) do
			if JobDefinitions.allowsWeapon(job, race, candidate) then
				table.insert(usable, candidate)
			end
		end
		if #usable == 0 then
			return nil
		end
		family = usable[math.clamp(math.floor(familyRoll * #usable) + 1, 1, #usable)]
	end
	return ItemDefinitions.defFor(job, slot, family, itemLevel)
end

-- Whether `t` is a usable stone table ("shape", "chance", "stone", "sum").
function LootRules.validateStones(t: any): (boolean, string?)
	if type(t) ~= "table" or type(t.Stones) ~= "table" then
		return false, "shape"
	end
	if not isNumber(t.DropChancePct) or t.DropChancePct < 0 or t.DropChancePct > 100 then
		return false, "chance"
	end
	local sum = 0
	for stone, weight in t.Stones do
		if not table.find(LootRules.STONES, stone) or not isNumber(weight) or weight < 0 or weight > 100 then
			return false, "stone"
		end
		sum += weight
	end
	if math.abs(sum - 100) > EPSILON then
		return false, "sum"
	end
	return true, nil
end

-- The stone that drops, or nil (two server rolls in [0, 1), as `roll`).
function LootRules.rollStone(t: StoneTable, dropRoll: number, stoneRoll: number): string?
	if dropRoll * 100 >= t.DropChancePct then
		return nil
	end
	local pick = stoneRoll * 100
	local last: string? = nil
	for _, stone in LootRules.STONES do
		local weight = t.Stones[stone]
		if weight and weight > 0 then
			last = stone
			pick -= weight
			if pick < 0 then
				return stone
			end
		end
	end
	return last
end

-- The item level a creature's drop gets (players cap at 30).
function LootRules.itemLevelFor(creatureLevel: number): number
	return math.clamp(math.floor(creatureLevel), 0, 30)
end

return table.freeze(LootRules)
