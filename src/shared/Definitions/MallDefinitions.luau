--!strict
--[[
	MallDefinitions — the Item Mall (creator request 2026-10-25, PLAN.md
	D-93). Display-safe data; the server checks every purchase.

	Mall Points (MP) are bought with Robux through Roblox Developer Products
	(PACKS; the creator makes each product on the Creator Dashboard and puts
	its id in `productId`; 0 = not set up yet, the pack shows as
	unavailable). MP are also given by events (D-93 stage 2).

	Everything in the CATALOG is fixed: no random results. Only the
	Legendary set is sold (D-95: a Mythical set gave a 3.8x PvP edge over
	normal drop gear; Mythical stays a PvP-boss / endgame reward). Gear sets have
	fixed attributes shown before buying (ItemRules.fixedRoll; creator
	decision 2026-10-25), so they are not paid random items. Enhancement
	Stones are sold as stones: the enhancement rates they are used with are
	shown to players (D-08) and a Perfect Stone always succeeds. A human
	must review Roblox's monetization rules before publishing (PLAN.md
	D-93).
]]

local MallDefinitions = {}

export type Pack = { id: string, points: number, bonusPct: number, robux: number, productId: number }
export type Grant = { kind: "Stackable", id: string, count: number } | { kind: "Set", rarity: string }
export type Entry = {
	id: string,
	name: string,
	icon: string,
	-- "Buffs" | "Stones" | "Sets"
	tab: string,
	-- The heading it is listed under inside its tab.
	section: string,
	-- What it does in a few words (shown on its card).
	short: string,
	price: number,
	grant: any,
	description: string,
}

-- Robux packs (creator choice 2026-10-25: four packs, bonus on the big ones).
MallDefinitions.PACKS = table.freeze({
	table.freeze({ id = "MP100", points = 100, bonusPct = 0, robux = 80, productId = 0 }),
	table.freeze({ id = "MP550", points = 500, bonusPct = 10, robux = 400, productId = 0 }),
	table.freeze({ id = "MP1200", points = 1000, bonusPct = 20, robux = 800, productId = 0 }),
	table.freeze({ id = "MP2600", points = 2000, bonusPct = 30, robux = 1600, productId = 0 }),
}) :: { Pack }

MallDefinitions.TABS = table.freeze({ "Buffs", "Stones", "Sets", "Points" })
MallDefinitions.TAB_NAMES = table.freeze({
	Buffs = "🧪 Buffs",
	Stones = "💎 Stones",
	Sets = "🔶 Gear sets",
	Points = "💠 Get Mall Points",
})
-- Section order inside each tab.
MallDefinitions.SECTIONS = table.freeze({
	Buffs = table.freeze({ "Boosts", "Combat draughts", "Utility" }),
	Stones = table.freeze({ "Enhancement Stones", "Perfect Stones" }),
	Sets = table.freeze({ "Complete sets" }),
})

local function stack(id: string, count: number): any
	return { kind = "Stackable", id = id, count = count }
end

local CATALOG: { Entry } = {
	-- Buffs (used from the bag; BuffRules).
	{
		id = "Insight",
		short = "+50% EXP · 60 min",
		section = "Boosts",
		name = "Scroll of Insight",
		icon = "✨",
		tab = "Buffs",
		price = 60,
		grant = stack("Buff_Insight", 1),
		description = "+50% EXP for 60 minutes.",
	},
	{
		id = "Fortune",
		short = "+50% gear drops · 60 min",
		section = "Boosts",
		name = "Fortune Charm",
		icon = "🍀",
		tab = "Buffs",
		price = 80,
		grant = stack("Buff_Fortune", 1),
		description = "Gear drops 50% more often for 60 minutes.",
	},
	{
		id = "StoneSeeker",
		short = "+50% stone drops · 60 min",
		section = "Boosts",
		name = "Stone Seeker's Lantern",
		icon = "🔍",
		tab = "Buffs",
		price = 60,
		grant = stack("Buff_StoneSeeker", 1),
		description = "War-zone creatures drop stones 50% more often for 60 minutes.",
	},
	{
		id = "Might",
		short = "+10% damage · 30 min",
		section = "Combat draughts",
		name = "Draught of Might",
		icon = "💪",
		tab = "Buffs",
		price = 50,
		grant = stack("Buff_Might", 1),
		description = "+10% damage for 30 minutes.",
	},
	{
		id = "Iron",
		short = "+10% Defense · 30 min",
		section = "Combat draughts",
		name = "Draught of Iron",
		icon = "🛡️",
		tab = "Buffs",
		price = 50,
		grant = stack("Buff_Iron", 1),
		description = "+10% Defense for 30 minutes.",
	},
	{
		id = "Vigor",
		short = "+10% Max HP · 30 min",
		section = "Combat draughts",
		name = "Draught of Vigor",
		icon = "💗",
		tab = "Buffs",
		price = 50,
		grant = stack("Buff_Vigor", 1),
		description = "+10% Max HP for 30 minutes.",
	},
	{
		id = "Clarity",
		short = "+30 max Focus · 30 min",
		section = "Combat draughts",
		name = "Draught of Clarity",
		icon = "🔷",
		tab = "Buffs",
		price = 40,
		grant = stack("Buff_Clarity", 1),
		description = "+30 max Focus for 30 minutes.",
	},
	{
		id = "Rebirth",
		short = "Get all attribute points back",
		section = "Utility",
		name = "Scroll of Rebirth",
		icon = "🔄",
		tab = "Buffs",
		price = 100,
		grant = stack("RebirthScroll", 1),
		description = "Returns all your attribute points at once, even inside the 24-hour wait.",
	},
	{
		id = "Potions10",
		short = "10 potions · heal 30% each",
		section = "Utility",
		name = "Healing Potions x10",
		icon = "🧪",
		tab = "Buffs",
		price = 30,
		grant = stack("HealingPotion", 10),
		description = "Ten potions that each restore 30% of your health.",
	},
	-- Stones.
	{
		id = "Stone1",
		short = "Enhance gear by +1",
		section = "Enhancement Stones",
		name = "Enhancement Stone",
		icon = "💎",
		tab = "Stones",
		price = 30,
		grant = stack("EnhancementStone", 1),
		description = "Raises a weapon or gear piece by +1 (success rates shown when enhancing).",
	},
	{
		id = "Stone10",
		short = "10 stones · 10% off",
		section = "Enhancement Stones",
		name = "Enhancement Stones x10",
		icon = "💎",
		tab = "Stones",
		price = 270,
		grant = stack("EnhancementStone", 10),
		description = "Ten Enhancement Stones (10% off).",
	},
	{
		id = "Perfect1",
		short = "+1 that always succeeds",
		section = "Perfect Stones",
		name = "Perfect Enhancement Stone",
		icon = "✨",
		tab = "Stones",
		price = 150,
		grant = stack("PerfectStone", 1),
		description = "An enhancement that always succeeds.",
	},
	{
		id = "Perfect5",
		short = "5 Perfect Stones",
		section = "Perfect Stones",
		name = "Perfect Stones x5",
		icon = "✨",
		tab = "Stones",
		price = 700,
		grant = stack("PerfectStone", 5),
		description = "Five Perfect Enhancement Stones (about 7% off).",
	},
	-- Complete sets for the buyer's class at their level, fixed attributes.
	{
		id = "LegendarySet",
		short = "Every piece for your class",
		section = "Complete sets",
		name = "Legendary Set",
		icon = "🔶",
		tab = "Sets",
		price = 2500,
		grant = { kind = "Set", rarity = "Legendary" },
		description = "Every piece for your class (weapon, armour, jewellery) at your level, Legendary, with fixed attributes.",
	},
}
MallDefinitions.CATALOG = table.freeze(CATALOG)

MallDefinitions.ById = {} :: { [string]: Entry }
MallDefinitions.IDS = {} :: { string }
for _, entry in MallDefinitions.CATALOG do
	table.freeze(entry)
	assert(MallDefinitions.ById[entry.id] == nil, `duplicate mall entry {entry.id}`)
	MallDefinitions.ById[entry.id] = entry
	table.insert(MallDefinitions.IDS, entry.id)
end

function MallDefinitions.get(id: any): Entry?
	return if type(id) == "string" then MallDefinitions.ById[id] else nil
end

-- The pack a Developer Product id pays for (nil if unknown / not set up).
function MallDefinitions.packForProduct(productId: number): Pack?
	if productId == 0 then
		return nil
	end
	for _, pack in MallDefinitions.PACKS do
		if pack.productId == productId then
			return pack
		end
	end
	return nil
end

-- Mall Points a pack gives, bonus included.
function MallDefinitions.pointsOf(pack: Pack): number
	return math.floor(pack.points * (1 + pack.bonusPct / 100) + 0.5)
end

return MallDefinitions
