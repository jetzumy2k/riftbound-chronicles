--!strict
--[[
	NpcDefinitions — the town NPCs that run a service (creator request
	2026-10-27, PLAN.md D-117 onward; built by ShopService). One of each
	stands in both capitals, at `at` in the capital's local frame
	(WorldLayout.toWorld), facing the spawn.

	Pure data.
]]

export type Npc = {
	id: string,
	-- Display name per realm.
	names: { [string]: string },
	title: string,
	icon: string,
	prompt: string,
	-- Capital-local position {x, y, z}.
	at: { number },
	-- The class whose gear look it wears.
	look: string,
}

local NpcDefinitions = {}

-- How close a player must stand to use an NPC (studs, server-checked).
NpcDefinitions.REACH = 14

--[[
	D-132 (creator request 2026-10-31): the town NPCs stand in two signed
	rows either side of the spawn, 14 studs apart, all facing it; the
	quest giver stands straight ahead (QuestDefinitions.Givers).
	  Market (left, x = -34):     Merchant, Blacksmith, Exchanger, Auctioneer
	  Challenges (right, x = 34): Tower Keeper, Warden, Puzzle Sage, Fortune Wheel
	(front to back). Each row has a sign behind it at `signX`.
]]
NpcDefinitions.ROWS = table.freeze({
	table.freeze({
		title = "🛍️ Market",
		signX = -46,
		ids = table.freeze({ "Merchant", "Blacksmith", "Exchanger", "Auctioneer" }),
	}),
	table.freeze({
		title = "🏆 Challenges",
		signX = 46,
		ids = table.freeze({ "Tower", "Warden", "Sage", "Fortune" }),
	}),
})

NpcDefinitions.List = table.freeze({
	table.freeze({
		id = "Merchant",
		names = table.freeze({ Angel = "Merchant Elowen", Devil = "Merchant Grisk" }),
		title = "Potions, gear and weapons",
		icon = "🛍️",
		prompt = "Trade",
		at = table.freeze({ -34, 0, 21 }),
		look = "Healer",
	}),
	table.freeze({
		id = "Exchanger",
		names = table.freeze({ Angel = "Exchanger Caelum", Devil = "Exchanger Vex" }),
		title = "Gold and Mall Points",
		icon = "💱",
		prompt = "Exchange",
		at = table.freeze({ -34, 0, -7 }),
		look = "Mage",
	}),
	-- D-118: repairs gear for Gold.
	table.freeze({
		id = "Blacksmith",
		names = table.freeze({ Angel = "Blacksmith Doran", Devil = "Blacksmith Korr" }),
		title = "Repairs gear",
		icon = "🔨",
		prompt = "Repair",
		at = table.freeze({ -34, 0, 7 }),
		look = "Warrior",
	}),
	-- D-120: the Fortune Wheel (RouletteService).
	table.freeze({
		id = "Fortune",
		names = table.freeze({ Angel = "Fortune Teller Lyra", Devil = "Fortune Teller Mordra" }),
		title = "Fortune Wheel",
		icon = "🎡",
		prompt = "Spin",
		at = table.freeze({ 34, 0, -21 }),
		look = "Healer",
	}),
	-- D-122: the Auction market (AuctionService).
	table.freeze({
		id = "Auctioneer",
		names = table.freeze({ Angel = "Auctioneer Cassia", Devil = "Auctioneer Varek" }),
		title = "Auction market",
		icon = "🏛️",
		prompt = "Auction",
		at = table.freeze({ -34, 0, -21 }),
		look = "Mage",
	}),
	-- D-128: the daily puzzle (PuzzleService).
	table.freeze({
		id = "Sage",
		names = table.freeze({ Angel = "Puzzle Sage Orin", Devil = "Puzzle Sage Ixa" }),
		title = "Daily puzzle",
		icon = "🧩",
		prompt = "Puzzle",
		at = table.freeze({ 34, 0, -7 }),
		look = "Mage",
	}),
	-- D-131: the Tower Challenge's entrance (TowerService).
	table.freeze({
		id = "Tower",
		names = table.freeze({ Angel = "Tower Keeper Aurel", Devil = "Tower Keeper Vex" }),
		title = "Tower Challenge",
		icon = "🗼",
		prompt = "Tower",
		at = table.freeze({ 34, 0, 21 }),
		look = "Warrior",
	}),
	-- D-119: gives the trial chain (ChainQuestService).
	table.freeze({
		id = "Warden",
		names = table.freeze({ Angel = "Warden Selene", Devil = "Warden Draven" }),
		title = "The Warden's Trials",
		icon = "🗝️",
		prompt = "Trials",
		at = table.freeze({ 34, 0, 7 }),
		look = "Archer",
	}),
} :: { Npc })

NpcDefinitions.IDS = {} :: { string }
NpcDefinitions.ById = {} :: { [string]: Npc }
for _, npc in NpcDefinitions.List do
	table.insert(NpcDefinitions.IDS, npc.id)
	NpcDefinitions.ById[npc.id] = npc
end
table.freeze(NpcDefinitions.IDS)
table.freeze(NpcDefinitions.ById)

function NpcDefinitions.get(id: any): Npc?
	return if type(id) == "string" then NpcDefinitions.ById[id] else nil
end

return table.freeze(NpcDefinitions)
