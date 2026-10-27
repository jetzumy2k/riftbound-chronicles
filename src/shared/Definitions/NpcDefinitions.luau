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

NpcDefinitions.List = table.freeze({
	table.freeze({
		id = "Merchant",
		names = table.freeze({ Angel = "Merchant Elowen", Devil = "Merchant Grisk" }),
		title = "Potions, gear and weapons",
		icon = "🛍️",
		prompt = "Trade",
		at = table.freeze({ 26, 0, 16 }),
		look = "Healer",
	}),
	table.freeze({
		id = "Exchanger",
		names = table.freeze({ Angel = "Exchanger Caelum", Devil = "Exchanger Vex" }),
		title = "Gold and Mall Points",
		icon = "💱",
		prompt = "Exchange",
		at = table.freeze({ 34, 0, -8 }),
		look = "Mage",
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
