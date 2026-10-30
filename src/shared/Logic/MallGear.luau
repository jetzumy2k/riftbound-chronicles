--!strict
--[[
	MallGear — which pieces an Item Mall gear entry gives (creator request
	2026-10-28, PLAN.md D-124). Pure; used by MallService and the Mall
	screen.

	  Set        the armor package only: helm, shoulders (sleeves), armor
	             (chest), gloves, pants, boots
	  Weapon     one weapon of a type the player's class and realm may use
	  OffHand    the class's off-hand piece (a shield; not every class
	             has one)
	  Accessory  one necklace, earrings or ring
	All Legendary in the Mall, with fixed attributes (ItemRules.fixedRoll).

	Level, Shaiya style: the buyer picks a level tier (LEVELS). The item is
	made at that level, and a piece can only be equipped at or above its
	item level (ItemRules.canEquip), so a higher tier can be bought ahead
	and worn later.
]]

local ItemDefinitions = require(script.Parent.Parent.Definitions.ItemDefinitions)
local JobDefinitions = require(script.Parent.Parent.Definitions.JobDefinitions)

local MallGear = {}

MallGear.LEVELS = table.freeze({ 0, 10, 20, 30 })
MallGear.ARMOR = table.freeze({ "Helm", "Shoulders", "Chest", "Hands", "Legs", "Boots" })
MallGear.ACCESSORIES = table.freeze({ "Necklace", "Earrings", "Ring" })
MallGear.KINDS = table.freeze({ Set = true, Weapon = true, OffHand = true, Accessory = true })
MallGear.PIECE_NAMES = table.freeze({
	Helm = "Helm",
	Shoulders = "Shoulders",
	Chest = "Armor",
	Hands = "Gloves",
	Legs = "Pants",
	Boots = "Boots",
	Necklace = "Necklace",
	Earrings = "Earrings",
	Ring = "Ring",
	Shield = "Shield",
})

export type Choice = { Bracket: number?, Family: string?, Piece: string? }
export type Piece = { def: ItemDefinitions.ItemDef, itemLevel: number }

-- The highest tier at or below `level` (the default choice).
function MallGear.defaultBracket(level: number): number
	local best = MallGear.LEVELS[1]
	for _, l in MallGear.LEVELS do
		if level >= l then
			best = l
		end
	end
	return best
end

-- Weapon types the class may use in this realm.
function MallGear.families(job: string, race: string?): { string }
	local out = {}
	for _, family in ItemDefinitions.familiesOf(job) do
		if JobDefinitions.allowsWeapon(job, race, family) then
			table.insert(out, family)
		end
	end
	return out
end

function MallGear.hasOffHand(job: string): boolean
	return table.find(ItemDefinitions.kindsOf(job), "Shield") ~= nil
end

local function piece(job: string, kind: string, family: string?, level: number): Piece?
	local def = ItemDefinitions.defFor(job, kind, family, level)
	if def == nil then
		return nil
	end
	return { def = def, itemLevel = math.clamp(level, def.minItemLevel, def.maxItemLevel) }
end

--[[
	The pieces `grantKind` gives a `job` / `race` character at `level` with
	`choice`. Returns (pieces) or (nil, reason): bracket, family, piece,
	noOffHand, kind.
]]
function MallGear.pieces(
	job: string,
	race: string?,
	grantKind: string,
	level: number,
	choice: Choice?
): ({ Piece }?, string?)
	local out: { Piece } = {}
	if grantKind == "Set" then
		for _, kind in MallGear.ARMOR do
			local p = piece(job, kind, nil, level)
			if p then
				table.insert(out, p)
			end
		end
	elseif grantKind == "Weapon" then
		local family = choice and choice.Family
		if family == nil or table.find(MallGear.families(job, race), family) == nil then
			return nil, "family"
		end
		local p = piece(job, "Weapon", family, level)
		if p == nil then
			return nil, "family"
		end
		table.insert(out, p)
	elseif grantKind == "OffHand" then
		if not MallGear.hasOffHand(job) then
			return nil, "noOffHand"
		end
		local p = piece(job, "Shield", nil, level)
		if p then
			table.insert(out, p)
		end
	elseif grantKind == "Accessory" then
		local kind = choice and choice.Piece
		if kind == nil or table.find(MallGear.ACCESSORIES, kind) == nil then
			return nil, "piece"
		end
		local p = piece(job, kind, nil, level)
		if p then
			table.insert(out, p)
		end
	else
		return nil, "kind"
	end
	return out, nil
end

-- The level a Mall purchase makes its gear at (a valid tier, else the
-- buyer's own default tier).
function MallGear.bracketOf(choice: Choice?, playerLevel: number): (number?, string?)
	local bracket = choice and choice.Bracket
	if bracket == nil then
		return MallGear.defaultBracket(playerLevel), nil
	end
	if table.find(MallGear.LEVELS, bracket) == nil then
		return nil, "bracket"
	end
	return bracket, nil
end

return table.freeze(MallGear)
