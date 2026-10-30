--!strict
--[[
	QuestDefinitions — the story quests (CLAUDE.md §16-17, PLAN.md Phase 11,
	D-73). Display-safe data only. Pure module.

	A quest has steps (objectives) that are done **in order**: only the
	first unfinished one counts progress, and the tracker always shows one
	clear next thing to do (the onboarding path, GM-2). Progress comes only
	from server events (QuestService); there is no progress remote.

	Objective types and their params:
	  Visit         place: a Place; radius (studs)
	  EnterZone     zone: "Dungeon" | "DungeonFloor<N>" | a war zone id
	  Kill          enemies: { enemy id }; owner: "training"? (MobService tag)
	  Interact      targets: { interactable id } (Collect / Inspect /
	                Investigate; target = #targets, any order)
	  ReturnSafely  zone: war zone id (walk out through its Return portal)
	  ParticipatePvP  (a hit given or taken against the other realm)

	Places (resolved on the server to world positions):
	  city      `at` = {right, up, forward} in the player's own capital
	            (WorldLayout.toWorld); one copy per realm
	  gate      `gate` id in the player's capital, `distance` in front
	  yard      the player's own training yard
	  dungeon   floor index, room id and {x, z} from the room centre, in
	            the player's realm's dungeon copy
	  warZone   zone id and {x, z} from its centre (shared by both realms)

	Rewards are granted once per profile under reward id "Q:<id>"
	(RewardClaims). Item rewards name a kind and rarity weights; the server
	picks the piece for the player's class and level. EXP is a share of the
	quest level's EXP-to-next (XPTable), so it scales with balance changes.

	Feature unlocks (story flags) gate, on live servers only (Studio skips
	them so testers aren't locked out):
	  DungeonAccess        Quest 1  the capital's Rift Dungeons gate
	  EnhancementUnlocked  Quest 2  enhancing gear
	  PortalAccess         Quest 4  the war-zone gates (with level >= 10, D-16)
	  RiftToken            Quest 10 one extra skill point (the special-skill
	                       unlock token of CLAUDE.md §17, under the D-45 tree)
]]

export type Place = {
	kind: "city" | "gate" | "yard" | "dungeon" | "warZone",
	at: { number }?,
	gate: string?,
	distance: number?,
	floor: number?,
	room: string?,
	zone: string?,
	x: number?,
	z: number?,
}

export type Objective = {
	id: string,
	type: "Visit" | "EnterZone" | "Kill" | "Interact" | "ReturnSafely" | "ParticipatePvP",
	target: number,
	text: string,
	place: Place?,
	radius: number?,
	zone: string?,
	enemies: { string }?,
	owner: string?,
	targets: { string }?,
}

export type ItemReward = {
	-- "weapon" | "armor" (any armor slot) | "gear" (weapon or armor) |
	-- "necklace" | "earrings"
	kind: string,
	rarity: { [string]: number }, -- weights, sum 100
}

export type Rewards = {
	xpShare: number,
	items: { ItemReward }?,
	stackables: { [string]: number }?,
	wallet: { [string]: number }?,
	titles: { string }?,
	cosmetics: { string }?,
	flags: { string }?,
}

export type Dialogue = {
	offer: string,
	progress: string,
	complete: string,
}

export type Quest = {
	id: string,
	order: number,
	name: string,
	summary: string,
	level: number,
	prerequisites: { string },
	-- Accepted automatically once available (Quest 1, the onboarding start).
	autoAccept: boolean?,
	objectives: { Objective },
	rewards: Rewards,
	dialogue: Dialogue,
}

export type Interactable = {
	id: string,
	label: string,
	action: string, -- prompt verb: "Collect" | "Inspect" | "Investigate"
	place: Place,
}

export type Giver = {
	race: string,
	name: string,
	title: string,
	at: { number },
}

local QuestDefinitions = {}

-- Quest givers: one in each capital, in front of the spawn. Dialogue text
-- uses {giver}, {realm}, {rival} and {player}.
QuestDefinitions.Givers = table.freeze({
	Angel = table.freeze({
		race = "Angel",
		name = "Seraph Commander Aurelia",
		title = "Skyreach Vanguard",
		-- D-132: straight ahead of the spawn, between the two NPC rows.
		at = { 0, 0, 24 },
	}),
	Devil = table.freeze({
		race = "Devil",
		name = "Warlord Malakar",
		title = "Emberdeep Legion",
		at = { 0, 0, 24 },
	}),
} :: { [string]: Giver })
-- How close a player must be to the giver to accept or turn in (studs).
QuestDefinitions.GIVER_REACH = 16
QuestDefinitions.INTERACT_REACH = 12

QuestDefinitions.Interactables = table.freeze({
	-- Quest 3: Rift fragments in the Shattered Crypts (floor 1).
	FragmentNave = {
		id = "FragmentNave",
		label = "Rift Fragment",
		action = "Collect",
		place = { kind = "dungeon", floor = 1, room = "CandleNave", x = 42, z = 10 },
	},
	FragmentCloister = {
		id = "FragmentCloister",
		label = "Rift Fragment",
		action = "Collect",
		place = { kind = "dungeon", floor = 1, room = "SunkenCloister", x = -40, z = -12 },
	},
	FragmentChapel = {
		id = "FragmentChapel",
		label = "Rift Fragment",
		action = "Collect",
		place = { kind = "dungeon", floor = 1, room = "BrokenChapel", x = 44, z = -20 },
	},
	-- Quest 4: the Gate Core behind Cerberus.
	GateCore = {
		id = "GateCore",
		label = "Gate Core",
		action = "Collect",
		place = { kind = "dungeon", floor = 1, room = "CerberusGate", x = 0, z = -48 },
	},
	-- Quest 5: both war-zone gates in your capital.
	DesertGate = {
		id = "DesertGate",
		label = "Desert Rift Gate",
		action = "Inspect",
		place = { kind = "gate", gate = "DesertRift", distance = 10 },
	},
	JungleGate = {
		id = "JungleGate",
		label = "Jungle Rift Gate",
		action = "Inspect",
		place = { kind = "gate", gate = "JungleRift", distance = 10 },
	},
	-- Quest 9: clues that someone feeds both realms false reports.
	ClueOasis = {
		id = "ClueOasis",
		label = "Scorched Orders",
		action = "Investigate",
		place = { kind = "warZone", zone = "DesertRift", x = 34, z = 30 },
	},
	ClueFalls = {
		id = "ClueFalls",
		label = "Torn War Banner",
		action = "Investigate",
		place = { kind = "warZone", zone = "JungleRift", x = 60, z = 48 },
	},
	ClueDepths = {
		id = "ClueDepths",
		label = "Nullborn Sigil",
		action = "Investigate",
		place = { kind = "dungeon", floor = 2, room = "AshGallery", x = 40, z = 0 },
	},
} :: { [string]: Interactable })

local DESERT = { "DuneStalker", "SandScarab", "SandstoneGolem" }
local JUNGLE = { "JungleProwler", "Thorncrawler", "MossbackGolem" }

local quests: { Quest } = {
	{
		id = "FirstSpark",
		order = 1,
		name = "First Spark",
		summary = "Train in the yard and prove yourself against the Rift Sprites.",
		level = 0,
		prerequisites = {},
		autoAccept = true,
		objectives = {
			{
				id = "train",
				type = "Visit",
				target = 1,
				text = "Go to the Training Grounds",
				place = { kind = "yard" },
				radius = 0,
			},
			{
				id = "sprites",
				type = "Kill",
				target = 5,
				text = "Defeat Rift Sprites",
				enemies = { "RiftSprite" },
				owner = "training",
			},
		},
		rewards = {
			xpShare = 1,
			items = { { kind = "weapon", rarity = { Uncommon = 100 } } },
			stackables = { HealingPotion = 5 },
			flags = { "DungeonAccess" },
		},
		dialogue = {
			offer = "Welcome, recruit. The Rift has torn the sky between our realm and {rival}. Before you face it, show me you can fight: train in the yard and drive off the Rift Sprites.",
			progress = "The Rift Sprites gather in the Training Grounds, past the plaza. Five of them, recruit.",
			complete = "Well fought. Take this blade and these potions. The Rift Dungeons gate is open to you now.",
		},
	},
	{
		id = "IntoTheRift",
		order = 2,
		name = "Into the Rift",
		summary = "Enter the Rift Dungeons and defeat the guardian of the Shattered Crypts' halls.",
		level = 1,
		prerequisites = { "FirstSpark" },
		objectives = {
			{
				id = "enter",
				type = "EnterZone",
				target = 1,
				text = "Enter the Rift Dungeons",
				zone = "Dungeon",
			},
			{
				id = "halls",
				type = "Kill",
				target = 8,
				text = "Clear the Shattered Crypts' halls",
				enemies = { "RiftWolf", "CrystalBeetle" },
			},
			{
				id = "guardian",
				type = "Kill",
				target = 1,
				text = "Defeat a Stoneback Guardian",
				enemies = { "StonebackGuardian" },
			},
		},
		rewards = {
			xpShare = 0.8,
			items = { { kind = "armor", rarity = { Rare = 30, Uncommon = 70 } } },
			stackables = { EnhancementStone = 3 },
			flags = { "EnhancementUnlocked" },
		},
		dialogue = {
			offer = "Creatures pour out of the Rift Dungeons. Go down into the Shattered Crypts, clear the halls and bring down the stone guardian that commands them.",
			progress = "The Rift Dungeons gate stands at the back of the plaza. The guardian waits beyond the crystal gallery.",
			complete = "The guardian is broken. You have earned the smiths' trust: take these Enhancement Stones and strengthen your gear.",
		},
	},
	{
		id = "EchoesOfTheOtherRealm",
		order = 3,
		name = "Echoes of the Other Realm",
		summary = "Find three Rift fragments in the Shattered Crypts.",
		level = 4,
		prerequisites = { "IntoTheRift" },
		objectives = {
			{
				id = "fragments",
				type = "Interact",
				target = 3,
				text = "Collect Rift fragments in the Shattered Crypts",
				targets = { "FragmentNave", "FragmentCloister", "FragmentChapel" },
			},
		},
		rewards = {
			xpShare = 0.7,
			items = { { kind = "necklace", rarity = { Rare = 100 } } },
			flags = { "EchoesSeen" },
		},
		dialogue = {
			offer = "Our scouts saw glowing shards in the crypts: the Candlelit Nave, the Sunken Cloister, the Broken Chapel. Bring them to me before {rival} claims them.",
			progress = "Three fragments, recruit. Look in the Nave, the Cloister and the Chapel.",
			complete = "Listen... the fragments hum with voices. Not ours, and not {rival}'s either. Something older. Keep this charm close; we will speak of this again.",
		},
	},
	{
		id = "TheBrokenGate",
		order = 4,
		name = "The Broken Gate",
		summary = "Defeat Cerberus and recover the Gate Core from its lair.",
		level = 8,
		prerequisites = { "EchoesOfTheOtherRealm" },
		objectives = {
			{
				id = "cerberus",
				type = "Kill",
				target = 1,
				text = "Defeat Cerberus at the end of the Shattered Crypts",
				enemies = { "Cerberus" },
			},
			{
				id = "core",
				type = "Interact",
				target = 1,
				text = "Recover the Gate Core from Cerberus's Gate",
				targets = { "GateCore" },
			},
		},
		rewards = {
			xpShare = 0.8,
			items = { { kind = "gear", rarity = { Rare = 100 } } },
			flags = { "PortalAccess" },
		},
		dialogue = {
			offer = "The fragments led us to a gate deep in the crypts, guarded by Cerberus. Its core powers the rifts to the war zones. Slay the beast and bring me the core.",
			progress = "Cerberus guards the gate at the far end of the first floor. Take allies if you can.",
			complete = "The Gate Core! With it our war-zone gates will open for you once you reach level 10. Wear this with pride.",
		},
	},
	{
		id = "TwoPathsOneRift",
		order = 5,
		name = "Two Paths, One Rift",
		summary = "Visit the heart of your capital and inspect both war-zone gates.",
		level = 10,
		prerequisites = { "TheBrokenGate" },
		objectives = {
			{
				id = "capital",
				type = "Visit",
				target = 1,
				text = "Stand before the great hall of your capital",
				place = { kind = "city", at = { 0, 0, -86 } },
				radius = 22,
			},
			{
				id = "desert",
				type = "Interact",
				target = 1,
				text = "Inspect the Desert Rift gate",
				targets = { "DesertGate" },
			},
			{
				id = "jungle",
				type = "Interact",
				target = 1,
				text = "Inspect the Jungle Rift gate",
				targets = { "JungleGate" },
			},
		},
		rewards = {
			xpShare = 0.6,
			stackables = { HealingPotion = 5 },
			titles = { "Riftwalker" },
		},
		dialogue = {
			offer = "Two gates now hum with the core's power: one to a burning desert, one to a drowned jungle. Walk our great hall, then inspect both gates so you know the way.",
			progress = "The great hall, then the desert gate on one side of the plaza and the jungle gate on the other.",
			complete = "Both gates hold. You walk where few recruits have: from today you are a Riftwalker.",
		},
	},
	{
		id = "TrialOfTheDesert",
		order = 6,
		name = "Trial of the Desert",
		summary = "Enter the Desert Rift, defeat its creatures and return safely.",
		level = 20,
		prerequisites = { "TwoPathsOneRift" },
		objectives = {
			{
				id = "enter",
				type = "EnterZone",
				target = 1,
				text = "Enter the Desert Rift",
				zone = "DesertRift",
			},
			{ id = "hunt", type = "Kill", target = 6, text = "Defeat desert creatures", enemies = DESERT },
			{
				id = "return",
				type = "ReturnSafely",
				target = 1,
				text = "Return home through your camp's portal",
				zone = "DesertRift",
			},
		},
		rewards = {
			xpShare = 0.6,
			stackables = { EnhancementStone = 5 },
			cosmetics = { "DesertMantle" },
		},
		dialogue = {
			offer = "The Desert Rift is open ground: {rival} may be there too. Hunt its creatures and come back alive through our camp's portal. Falling doesn't count.",
			progress = "Dune Stalkers, scarabs, golems: six of them. Then walk out through our camp's Return portal.",
			complete = "Sand in your boots and your head still on your shoulders. Take this mantle of the dunes.",
		},
	},
	{
		id = "TrialOfTheJungle",
		order = 7,
		name = "Trial of the Jungle",
		summary = "Enter the Jungle Rift, defeat its creatures and return safely.",
		level = 20,
		prerequisites = { "TwoPathsOneRift" },
		objectives = {
			{
				id = "enter",
				type = "EnterZone",
				target = 1,
				text = "Enter the Jungle Rift",
				zone = "JungleRift",
			},
			{ id = "hunt", type = "Kill", target = 6, text = "Defeat jungle creatures", enemies = JUNGLE },
			{
				id = "return",
				type = "ReturnSafely",
				target = 1,
				text = "Return home through your camp's portal",
				zone = "JungleRift",
			},
		},
		rewards = {
			xpShare = 0.6,
			stackables = { EnhancementStone = 5 },
			cosmetics = { "JungleMantle" },
		},
		dialogue = {
			offer = "Beyond the jungle gate the river roars and things hunt in the canopy. Thin them out and return through our camp's portal.",
			progress = "Prowlers, thorncrawlers, mossback golems: six of them, then home through the portal.",
			complete = "You came back from the green dark. Wear this mantle of the canopy.",
		},
	},
	{
		id = "RivalEncounter",
		order = 8,
		name = "Rival Encounter",
		summary = "Take part in a clash with {rival} in a war zone. No victory needed.",
		level = 20,
		prerequisites = { "TwoPathsOneRift" },
		objectives = {
			{
				id = "clash",
				type = "ParticipatePvP",
				target = 1,
				text = "Clash with a player of the other realm in a war zone",
			},
		},
		rewards = {
			xpShare = 0.5,
			wallet = { PvPMarks = 25 },
			cosmetics = { "JobCrest" },
		},
		dialogue = {
			offer = "Sooner or later you will meet {rival} in the war zones. I don't ask for a victory; I ask that you stand your ground once and see them for yourself.",
			progress = "Find {rival} in the Desert or Jungle Rift. Strike or be struck: either way, you will have met them.",
			complete = "You met them. Did you notice? They fight like soldiers who were told the same lies we were. Take these marks and this crest.",
		},
	},
	{
		id = "TheFalseWar",
		order = 9,
		name = "The False War",
		summary = "Investigate the clues that both realms are being deceived.",
		level = 22,
		prerequisites = { "TrialOfTheDesert", "TrialOfTheJungle", "RivalEncounter" },
		objectives = {
			{
				id = "clues",
				type = "Interact",
				target = 3,
				text = "Investigate clues in the oasis, by the waterfall and in the Ember Depths",
				targets = { "ClueOasis", "ClueFalls", "ClueDepths" },
			},
		},
		rewards = {
			xpShare = 0.6,
			items = { { kind = "earrings", rarity = { Rare = 100 } } },
			titles = { "Truthseeker" },
			flags = { "FalseWarRevealed" },
		},
		dialogue = {
			offer = "Orders signed with my seal that I never wrote. Reports of attacks that never happened. Someone is feeding both realms lies. Search the desert oasis, the jungle falls and the Ember Depths.",
			progress = "The oasis, the waterfall pool and the Ash Gallery on the second floor of the dungeons.",
			complete = "The same sigil on every clue: the Nullborn. They want our realms to bleed each other dry. Neither {rival} nor we are the true enemy. Tell no one yet, Truthseeker.",
		},
	},
	{
		id = "GuardianOfTheRift",
		order = 10,
		name = "Guardian of the Rift",
		summary = "Defeat the Basilisk, the Nullborn's guardian of the Frozen Abyss.",
		level = 26,
		prerequisites = { "TheFalseWar" },
		objectives = {
			{
				id = "enter",
				type = "EnterZone",
				target = 1,
				text = "Reach the Frozen Abyss (dungeon floor 3)",
				zone = "DungeonFloor3",
			},
			{
				id = "basilisk",
				type = "Kill",
				target = 1,
				text = "Defeat the Basilisk",
				enemies = { "Basilisk" },
			},
		},
		rewards = {
			xpShare = 0.7,
			items = { { kind = "gear", rarity = { Legendary = 25, Epic = 75 } } },
			flags = { "RiftToken" },
		},
		dialogue = {
			offer = "The Nullborn bound a great guardian in the Frozen Abyss, the third floor of the dungeons. Destroy the Basilisk and their hold on the Rift weakens.",
			progress = "The Basilisk's mirror hall lies at the end of the Frozen Abyss.",
			complete = "The guardian is gone. Take this Rift token: it opens one more skill to you. And this, from our vault.",
		},
	},
	{
		id = "TheNullbornGate",
		order = 11,
		name = "The Nullborn Gate",
		summary = "Descend to the Nullborn Depths and defeat Typhon, the final guardian.",
		level = 30,
		prerequisites = { "GuardianOfTheRift" },
		objectives = {
			{
				id = "depths",
				type = "EnterZone",
				target = 1,
				text = "Descend to the Nullborn Depths (dungeon floor 4)",
				zone = "DungeonFloor4",
			},
			{
				id = "typhon",
				type = "Kill",
				target = 1,
				text = "Defeat Typhon in his sanctum",
				enemies = { "Typhon" },
			},
		},
		rewards = {
			xpShare = 0,
			items = { { kind = "gear", rarity = { Mythical = 20, Legendary = 80 } } },
			titles = { "Nullbane" },
			cosmetics = { "NullbornAura" },
			flags = { "EndgameAccess" },
		},
		dialogue = {
			offer = "The Nullborn Gate lies beneath the Hall of Thirty. Typhon holds it open. End him, and both realms may yet see the truth.",
			progress = "Through the Hall of Thirty to Typhon's Sanctum. Take the strongest allies you know.",
			complete = "Typhon has fallen and the gate is sealed. {rival} will hear of this too; perhaps the war ends here. The depths stay open for those who would guard them. Rise, Nullbane.",
		},
	},
}

QuestDefinitions.List = table.freeze(quests)

-- Titles a quest (or later, PvP and events) can grant. Display text only.
QuestDefinitions.Titles = table.freeze({
	Riftwalker = "Riftwalker",
	Truthseeker = "Truthseeker",
	Nullbane = "Nullbane",
	-- PvP victory titles (Phase 14, D-76; thresholds in PvPRules.VICTORY_TITLES).
	Skirmisher = "Skirmisher",
	RiftVanguard = "Rift Vanguard",
	RiftChampion = "Rift Champion",
	TwinRealmLegend = "Twin Realm Legend",
	-- D-134: past 500 victories.
	RiftWarlord = "Rift Warlord",
	RealmConqueror = "Realm Conqueror",
	EternalWarbringer = "Eternal Warbringer",
	-- Live event titles (Phase 18 stage 3, D-92).
	TreasureSeeker = "Treasure Seeker",
	KeenEye = "Keen Eye",
	RealmDefender = "Realm Defender",
	TournamentVictor = "Tournament Victor",
	ParadeStar = "Parade Star",
} :: { [string]: string })

-- Cosmetics granted now; shown on the character in the art pass (Phase 16).
QuestDefinitions.Cosmetics = table.freeze({
	DesertMantle = "Mantle of the Dunes",
	JungleMantle = "Mantle of the Canopy",
	JobCrest = "Class Crest",
	NullbornAura = "Nullborn Aura",
} :: { [string]: string })

QuestDefinitions.FLAGS = table.freeze({
	"DungeonAccess",
	"EnhancementUnlocked",
	"EchoesSeen",
	"PortalAccess",
	"FalseWarRevealed",
	"RiftToken",
	"EndgameAccess",
})

local byId: { [string]: Quest } = {}
local ids: { string } = {}
for _, quest in quests do
	byId[quest.id] = quest
	table.insert(ids, quest.id)
end
QuestDefinitions.IDS = table.freeze(ids)

function QuestDefinitions.get(id: any): Quest?
	return if type(id) == "string" then byId[id] else nil
end

function QuestDefinitions.objective(quest: Quest, objectiveId: string): Objective?
	for _, objective in quest.objectives do
		if objective.id == objectiveId then
			return objective
		end
	end
	return nil
end

-- Dialogue / summary text with the realm names filled in.
function QuestDefinitions.fill(text: string, race: string?, playerName: string?): string
	local giver = race and QuestDefinitions.Givers[race]
	local rival = if race == "Angel"
		then "the Devils"
		elseif race == "Devil" then "the Angels"
		else "the other realm"
	local realm = if race == "Angel"
		then "the Angels"
		elseif race == "Devil" then "the Devils"
		else "your realm"
	return (
		string.gsub(text, "{(%w+)}", {
			giver = if giver then giver.name else "your commander",
			rival = rival,
			realm = realm,
			player = playerName or "recruit",
		})
	)
end

return table.freeze(QuestDefinitions)
