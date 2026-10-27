--!strict
--[[
	ChainQuestDefinitions — the Warden's trial chain (creator request
	2026-10-27, PLAN.md D-119; ChainQuestService runs it).

	A level 25+ tour of the hardest hunting grounds, eight steps in order:
	the dungeon's third floor, then both war zones.
	  Kill     defeat `count` of the listed creatures
	  Collect  defeating one of them drops the trophy with the config's
	           CollectChancePct chance (rolled on the server); bring `count`
	Progress counts for every player who earns the creature's EXP (party
	friendly). Finishing all eight lets the player choose the reward: a
	Legendary gear piece of their class at their level, or a 1-day random
	buff. Repeatable after the config's cooldown.

	Each step says where its creatures live and how to get there (creator
	review 2026-10-27: the first panel only named the zone).

	Pure data.
]]

export type Step = {
	kind: string, -- "Kill" | "Collect"
	enemies: { string },
	count: number,
	-- Collect: the trophy's name.
	item: string?,
	icon: string,
	-- Short line for the list, and the creature(s) to look for.
	label: string,
	target: string,
	levels: string,
	-- The area, and the way there from the capital.
	where: string,
	route: string,
	tip: string?,
}

local ChainQuestDefinitions = {}

ChainQuestDefinitions.NAME = "The Warden's Trials"

local FLOOR3 = "Rift Hollow · Floor 3: The Frozen Abyss"
local TO_FLOOR3 =
	"In your capital, walk through the gate marked 🏰 Rift Dungeons. Go down the floor portals (glowing green) to Floor 3. They roam every room of the floor."
local DESERT = "Desert Rift (war zone)"
local TO_DESERT =
	"In your capital, walk through the gate marked 🏜️ Desert Rift (opened by the story quests). You arrive in your realm's camp; head out across the dunes toward the oasis."
local JUNGLE = "Jungle Rift (war zone)"
local TO_JUNGLE =
	"In your capital, walk through the gate marked 🌴 Jungle Rift (opened by the story quests). You arrive in your realm's camp; head down toward the river and the waterfall."
local PVP =
	"War zones are PvP: players of the other realm can attack you outside the camps. Go with your party."

ChainQuestDefinitions.Steps = table.freeze({
	table.freeze({
		kind = "Kill",
		enemies = table.freeze({ "RimeStalker" }),
		count = 12,
		icon = "🐺",
		label = "Defeat 12 Rime Stalkers",
		target = "Rime Stalker",
		levels = "Lv 21-30",
		where = FLOOR3,
		route = TO_FLOOR3,
	}),
	table.freeze({
		kind = "Collect",
		enemies = table.freeze({ "AbyssCrawler" }),
		count = 8,
		item = "Abyss Core",
		icon = "💎",
		label = "Collect 8 Abyss Cores",
		target = "Abyss Crawler",
		levels = "Lv 21-30",
		where = FLOOR3,
		route = TO_FLOOR3,
		tip = "Not every Abyss Crawler drops a core: keep hunting.",
	}),
	table.freeze({
		kind = "Kill",
		enemies = table.freeze({ "AbyssalKnight" }),
		count = 3,
		icon = "🛡️",
		label = "Defeat 3 Abyssal Knights",
		target = "Abyssal Knight",
		levels = "Lv 21-30 (tough)",
		where = FLOOR3,
		route = TO_FLOOR3,
		tip = "Abyssal Knights hit hard. Bring your party and potions.",
	}),
	table.freeze({
		kind = "Collect",
		enemies = table.freeze({ "SandScarab" }),
		count = 6,
		item = "Scarab Shell",
		icon = "🐞",
		label = "Collect 6 Scarab Shells",
		target = "Sand Scarab",
		levels = "Lv 25-30",
		where = DESERT,
		route = TO_DESERT,
		tip = "Sand Scarabs gather in pairs around the oasis and on the dunes. " .. PVP,
	}),
	table.freeze({
		kind = "Kill",
		enemies = table.freeze({ "DuneStalker" }),
		count = 10,
		icon = "🏜️",
		label = "Defeat 10 Dune Stalkers",
		target = "Dune Stalker",
		levels = "Lv 25-30",
		where = DESERT,
		route = TO_DESERT,
		tip = "Dune Stalkers hunt in packs of three all over the desert. " .. PVP,
	}),
	table.freeze({
		kind = "Collect",
		enemies = table.freeze({ "Thorncrawler" }),
		count = 6,
		item = "Thorn Barb",
		icon = "🌿",
		label = "Collect 6 Thorn Barbs",
		target = "Thorncrawler",
		levels = "Lv 25-30",
		where = JUNGLE,
		route = TO_JUNGLE,
		tip = "Thorncrawlers lurk near the waterfall pool and along the river. " .. PVP,
	}),
	table.freeze({
		kind = "Kill",
		enemies = table.freeze({ "JungleProwler" }),
		count = 8,
		icon = "🐆",
		label = "Defeat 8 Jungle Prowlers",
		target = "Jungle Prowler",
		levels = "Lv 25-30",
		where = JUNGLE,
		route = TO_JUNGLE,
		tip = "Jungle Prowlers roam the jungle floor and the highland above the falls. " .. PVP,
	}),
	table.freeze({
		kind = "Kill",
		enemies = table.freeze({ "SandstoneGolem", "MossbackGolem" }),
		count = 2,
		icon = "🗿",
		label = "Defeat 2 golems",
		target = "Sandstone Golem or Mossback Golem",
		levels = "Lv 29 (very tough)",
		where = "Desert Rift or Jungle Rift (war zones)",
		route = "Sandstone Golems stand alone in the far corners of the Desert Rift; Mossback Golems by the river and on the highland of the Jungle Rift. Use the 🏜️ Desert Rift or 🌴 Jungle Rift gate in your capital.",
		tip = "Golems are slow but very strong: fight them with your party. " .. PVP,
	}),
} :: { Step })

ChainQuestDefinitions.REWARDS = table.freeze({ "Legendary", "Buff" })
-- The buff reward lasts a day.
ChainQuestDefinitions.BUFF_SECONDS = 24 * 3600
-- The level the creatures need (the config's MinLevel defaults to it).
ChainQuestDefinitions.LEVEL = 25

return table.freeze(ChainQuestDefinitions)
