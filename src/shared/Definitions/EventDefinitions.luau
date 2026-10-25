--!strict
--[[
	EventDefinitions — the live event templates (CLAUDE.md §23, Phase 18,
	PLAN.md D-89). Display-safe data; the server decides everything.

	Each template:
	  id, name, icon, blurb   what players see in the announcement / HUD
	  kind      Modifier (multiplies rewards / rules), World (spawns,
	            weather), Hunt (things to find), Challenge (scored contest)
	  stage     the Phase 18 stage that makes it playable (1 now; 2 world
	            events; 3 hunts and challenges). The panel only starts
	            events whose stage is built (EventDefinitions.READY_STAGE).
	  minutes   default / max duration
	  cooldownMinutes  the least time between two runs of it
	  zone      where it applies: All, Dungeon, Desert, Jungle, WarZones,
	            Capitals, Training
	  eligible  who it applies to: race / job / minLevel (all optional)
	  modifiers Logic/EventRules categories -> multiplier (stacked
	            additively with other events, then capped)
	  spawns    (stages 2-3) what it brings into the world
	  rewards   (stages 2-3) what taking part pays

	Events never change saved player data when they end: they only scale
	rewards as they are earned (EventRules).
]]

local EventDefinitions = {}

export type Kind = "Modifier" | "World" | "Hunt" | "Challenge"
export type Zone = "All" | "Dungeon" | "Desert" | "Jungle" | "WarZones" | "Capitals" | "Training"
export type Eligible = { race: string?, job: string?, minLevel: number? }
export type Event = {
	id: string,
	name: string,
	icon: string,
	blurb: string,
	kind: Kind,
	stage: number,
	minutes: number,
	maxMinutes: number,
	cooldownMinutes: number,
	zone: Zone,
	eligible: Eligible?,
	modifiers: { [string]: number },
	spawns: { [string]: any }?,
	rewards: { [string]: any }?,
}

-- Stages built so far: events above this can't be started yet.
EventDefinitions.READY_STAGE = 3

local DAY = 24 * 60

local function event(id: string, name: string, icon: string, blurb: string, spec: { [string]: any }): Event
	local e = table.clone(spec) :: any
	e.id = id
	e.name = name
	e.icon = icon
	e.blurb = blurb
	e.kind = e.kind or "Modifier"
	e.stage = e.stage or 1
	e.minutes = e.minutes or 60
	e.maxMinutes = e.maxMinutes or 3 * DAY
	e.cooldownMinutes = e.cooldownMinutes or 60
	e.zone = e.zone or "All"
	e.modifiers = e.modifiers or {}
	return e :: Event
end

-- In panel order (CLAUDE.md §23 numbering).
EventDefinitions.List = {
	event("DoubleExp", "Double EXP Weekend", "✨", "All EXP from creatures is doubled.", {
		minutes = 2 * DAY,
		modifiers = { XP = 2 },
	}),
	event("DoubleDrops", "Double Dungeon Drop Rate", "🎁", "Dungeon creatures drop gear twice as often.", {
		zone = "Dungeon",
		modifiers = { DropChance = 2 },
	}),
	event("RareGearRush", "Rare Gear Rush", "🔷", "Rare gear drops far more often.", {
		modifiers = { RareWeight = 2 },
	}),
	event("LegendaryHunt", "Legendary Hunt", "🔶", "Bosses drop Legendary gear more often.", {
		modifiers = { LegendaryWeight = 2 },
	}),
	event("MythicalInvasion", "Mythical Boss Invasion", "👑", "Mythical bosses invade the war zones.", {
		kind = "World",
		stage = 2,
		zone = "WarZones",
		modifiers = { MythicalWeight = 1.5 },
		spawns = { bosses = "WarZone", count = 2 },
	}),
	event("StoneRush", "Enhancement Stone Rush", "💎", "War-zone creatures drop stones more often.", {
		zone = "WarZones",
		modifiers = { StoneChance = 2 },
	}),
	event("PerfectStoneHunt", "Perfect Stone Hunt", "💠", "More of the dropped stones are Perfect.", {
		zone = "WarZones",
		modifiers = { PerfectWeight = 2 },
	}),
	event("DesertStorm", "Desert Storm", "🌪️", "A sandstorm sweeps the Desert Rift.", {
		kind = "World",
		stage = 2,
		zone = "Desert",
		modifiers = { XP = 1.25 },
		spawns = { weather = "Sandstorm" },
	}),
	event("JungleFlood", "Jungle Flood", "🌊", "The river floods the Jungle Rift.", {
		kind = "World",
		stage = 2,
		zone = "Jungle",
		modifiers = { XP = 1.25 },
		spawns = { weather = "Flood" },
	}),
	event("RiftBeastInvasion", "Rift Beast Invasion", "🐺", "Rift beasts pour into the war zones.", {
		kind = "World",
		stage = 2,
		zone = "WarZones",
		spawns = { packs = 6 },
	}),
	event("BossFrenzy", "Boss Frenzy", "😤", "Fallen bosses return much sooner.", {
		kind = "World",
		stage = 2,
		zone = "WarZones",
		modifiers = { BossRespawn = 0.25 },
	}),
	event("EliteSwarm", "Elite Mob Swarm", "⭐", "Elite creatures join the war-zone camps.", {
		kind = "World",
		stage = 2,
		zone = "WarZones",
		spawns = { elites = true },
	}),
	event("TreasureHunt", "Treasure Hunt", "🗺️", "Follow the clues to buried treasure.", {
		kind = "Hunt",
		stage = 3,
		spawns = { chests = 5 },
	}),
	event("HiddenChestHunt", "Hidden Chest Hunt", "🧰", "Chests are hidden around the realms.", {
		kind = "Hunt",
		stage = 3,
		spawns = { chests = 12 },
	}),
	event("RaceChallenge", "Race Challenge", "🏁", "Angels and Devils race for the most victories.", {
		kind = "Challenge",
		stage = 3,
		zone = "WarZones",
	}),
	event("AngelDefense", "Angel Defense Event", "🛡️", "Defend Skyreach from the Rift.", {
		kind = "Challenge",
		stage = 3,
		zone = "Capitals",
		eligible = { race = "Angel" },
	}),
	event("DevilDefense", "Devil Defense Event", "🔥", "Defend Emberdeep from the Rift.", {
		kind = "Challenge",
		stage = 3,
		zone = "Capitals",
		eligible = { race = "Devil" },
	}),
	event("CrossRaceTournament", "Cross-Race Tournament", "🏆", "A tournament between the realms.", {
		kind = "Challenge",
		stage = 3,
		zone = "WarZones",
		eligible = { minLevel = 10 },
	}),
	event("ArenaRush", "PvP Arena Rush", "🏟️", "Victories in the war zones pay double PvP Marks.", {
		kind = "Challenge",
		stage = 3,
		zone = "WarZones",
		eligible = { minLevel = 10 },
		modifiers = { Marks = 2 },
	}),
	event(
		"NoCooldownTraining",
		"No-Cooldown Training",
		"⏳",
		"Skills recharge almost instantly in the training yards.",
		{
			zone = "Training",
			modifiers = { TrainingCooldown = 0.1 },
		}
	),
	event("HealingFestival", "Healing Festival", "💚", "All healing and shields are 50% stronger.", {
		modifiers = { Healing = 1.5 },
	}),
	event("ArcherChallenge", "Archer Precision Challenge", "🏹", "Archers earn bonus EXP.", {
		eligible = { job = "Archer" },
		modifiers = { XP = 1.5 },
	}),
	event("WarriorChallenge", "Warrior Survival Challenge", "🗡️", "Warriors earn bonus EXP.", {
		eligible = { job = "Warrior" },
		modifiers = { XP = 1.5 },
	}),
	event("ClassMastery", "Class Mastery Event", "📘", "Every class earns bonus EXP.", {
		modifiers = { XP = 1.25 },
	}),
	event(
		"NullbornWorldBoss",
		"Nullborn World Boss",
		"🌑",
		"The Nullborn Herald descends. Every realm must fight.",
		{
			kind = "World",
			stage = 2,
			zone = "WarZones",
			minutes = 30,
			maxMinutes = 120,
			cooldownMinutes = 6 * 60,
			spawns = { worldBoss = "NullbornHerald" },
		}
	),
	event("TripleQuestExp", "Triple Quest EXP", "📜", "Quests pay three times the EXP.", {
		modifiers = { QuestXP = 3 },
	}),
	event(
		"DungeonMarathon",
		"Dungeon Marathon",
		"🏃",
		"Dungeon boss bonuses are doubled and gear drops more often.",
		{
			zone = "Dungeon",
			modifiers = { BossXP = 2, DropChance = 1.5 },
		}
	),
	event(
		"RareAttributeWeekend",
		"Rare Attribute Weekend",
		"🎲",
		"Gear attributes roll twice and keep the better value.",
		{
			minutes = 2 * DAY,
			modifiers = { AttributeRolls = 2 },
		}
	),
	event("CosmeticParade", "Cosmetic Parade", "🎉", "Show off your look in the capitals.", {
		kind = "Challenge",
		stage = 3,
		zone = "Capitals",
	}),
	event(
		"RiftEclipse",
		"Rift Eclipse",
		"🌘",
		"The sky darkens and Rift creatures grow stronger and richer.",
		{
			kind = "World",
			stage = 2,
			modifiers = { XP = 1.5, DropChance = 1.25 },
			spawns = { sky = "Eclipse" },
		}
	),
}

EventDefinitions.ById = {} :: { [string]: Event }
EventDefinitions.IDS = {} :: { string }
for _, e in EventDefinitions.List do
	assert(EventDefinitions.ById[e.id] == nil, `duplicate event {e.id}`)
	EventDefinitions.ById[e.id] = e
	table.insert(EventDefinitions.IDS, e.id)
end

function EventDefinitions.get(id: any): Event?
	if type(id) ~= "string" then
		return nil
	end
	return EventDefinitions.ById[id]
end

function EventDefinitions.isReady(e: Event): boolean
	return e.stage <= EventDefinitions.READY_STAGE
end

return EventDefinitions
