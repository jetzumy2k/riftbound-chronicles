--!strict
--[[
	EnemyDefinitions — dungeon and field creatures (CLAUDE.md §11/§18,
	Phase 9). Non-graphic, believable fantasy creatures.

	Stats start from the player formula at the enemy's level
	(StatFormulas.forLevel) and are scaled:
	  hpScale / attackScale / defenseScale   multipliers
	  attackCoefficient                       per-hit damage coefficient
	Behaviour (MobBrain):
	  aggroRadius   notices players this close
	  leashRadius   gives up beyond this distance from its spawn
	  attackRange   studs; windup = telegraph seconds before the hit lands
	  attackCooldown seconds between attacks
	  moveSpeed     Humanoid.WalkSpeed
	Rewards: xp per defeat at the creature's own level (shared with the
	party, DungeonRules.shareXp); camps that set another level scale it
	with the EXP curve (xpAt).
	Bosses (tier Boss / Floor / Mini) get HP and hit strength from
	Logic/BossBalance and enrage after ENRAGE_SECONDS (BossService).
	Visual: body plan + palette for the procedural creature builder;
	bosses follow Definitions/CreatureLanguage (D-88): an element sets the
	glow (mini bosses take the element's whole palette), and mini bosses
	come in three weights.

	Display-safe data only. Pure module.
]]

local BossBalance = require(script.Parent.Parent.Logic.BossBalance)
local CreatureLanguage = require(script.Parent.CreatureLanguage)
local XPTable = require(script.Parent.Parent.Logic.XPTable)

export type Body = "Wolf" | "Beetle" | "Golem" | "Sprite" | "Guardian" | "Serpent"

-- Extra anatomy a body plan can carry (CreatureBuilder; animated by
-- MobVisualController): bosses get their myth's look from these.
export type Trait = "ThreeHeads" | "Mane" | "Horns" | "Wings" | "SerpentTail" | "Spikes" | "Crest"

export type Enemy = {
	id: string,
	name: string,
	-- D-130: stats grow like players past level 30 (the level 31-60 dungeon).
	gentle: boolean?,
	level: number,
	elite: boolean,
	hpScale: number,
	attackScale: number,
	defenseScale: number,
	attackCoefficient: number,
	attackRange: number,
	windup: number,
	attackCooldown: number,
	aggroRadius: number,
	leashRadius: number,
	moveSpeed: number,
	xp: number,
	body: Body,
	scale: number,
	-- {r, g, b}
	color: { number },
	glow: { number },
	-- Bosses only (BossBalance tier).
	tier: BossBalance.Tier?,
	traits: { Trait }?,
	-- Bosses: the element their glow shows (CreatureLanguage, D-88).
	element: CreatureLanguage.Element?,
}

local EnemyDefinitions = {}

local enemies: { [string]: Enemy } = {
	-- Training Grounds critter (Quest 1: "defeat 5 training creatures").
	RiftSprite = {
		id = "RiftSprite",
		name = "Rift Sprite",
		level = 0,
		elite = false,
		hpScale = 0.9,
		attackScale = 0.5,
		defenseScale = 0.6,
		attackCoefficient = 0.12,
		attackRange = 5,
		windup = 0.45,
		attackCooldown = 2.2,
		aggroRadius = 14,
		leashRadius = 40,
		moveSpeed = 10,
		xp = 20,
		body = "Sprite",
		scale = 0.8,
		color = { 150, 200, 255 },
		glow = { 190, 240, 255 },
	},
	RiftWolf = {
		id = "RiftWolf",
		name = "Rift Wolf",
		level = 1,
		elite = false,
		hpScale = 1.1,
		attackScale = 0.9,
		defenseScale = 1,
		attackCoefficient = 0.22,
		attackRange = 6,
		windup = 0.4,
		attackCooldown = 1.6,
		aggroRadius = 34,
		leashRadius = 90,
		moveSpeed = 17,
		xp = 30,
		body = "Wolf",
		scale = 1,
		color = { 70, 76, 96 },
		glow = { 120, 200, 255 },
	},
	CrystalBeetle = {
		id = "CrystalBeetle",
		name = "Crystal Beetle",
		level = 2,
		elite = false,
		hpScale = 1.6,
		attackScale = 0.9,
		defenseScale = 1.4,
		attackCoefficient = 0.28,
		attackRange = 6.5,
		windup = 0.6,
		attackCooldown = 2.2,
		aggroRadius = 30,
		leashRadius = 90,
		moveSpeed = 11,
		xp = 45,
		body = "Beetle",
		scale = 1.1,
		color = { 52, 70, 88 },
		glow = { 140, 110, 255 },
	},
	StonebackGuardian = {
		id = "StonebackGuardian",
		name = "Stoneback Guardian",
		level = 3,
		elite = true,
		hpScale = 4,
		attackScale = 1.1,
		defenseScale = 1.6,
		attackCoefficient = 0.45,
		attackRange = 9,
		windup = 0.9,
		attackCooldown = 2.8,
		aggroRadius = 34,
		leashRadius = 90,
		moveSpeed = 10,
		xp = 120,
		body = "Golem",
		scale = 1.5,
		color = { 112, 106, 98 },
		glow = { 120, 220, 255 },
	},
	-- Desert Rift (Phase 12) field creatures, for Quest 6 and PvE between fights.
	-- Levels 25-30 (creator review 2026-10-17, D-49); camps set each spot's level.
	DuneStalker = {
		id = "DuneStalker",
		name = "Dune Stalker",
		level = 25,
		elite = false,
		hpScale = 1.1,
		attackScale = 0.9,
		defenseScale = 1,
		attackCoefficient = 0.22,
		attackRange = 6,
		windup = 0.4,
		attackCooldown = 1.6,
		aggroRadius = 32,
		leashRadius = 90,
		moveSpeed = 18,
		xp = 250,
		body = "Wolf",
		scale = 1.05,
		color = { 196, 160, 110 },
		glow = { 255, 170, 80 },
	},
	SandScarab = {
		id = "SandScarab",
		name = "Sand Scarab",
		level = 27,
		elite = false,
		hpScale = 1.6,
		attackScale = 0.9,
		defenseScale = 1.4,
		attackCoefficient = 0.28,
		attackRange = 6.5,
		windup = 0.6,
		attackCooldown = 2.2,
		aggroRadius = 28,
		leashRadius = 90,
		moveSpeed = 11,
		xp = 350,
		body = "Beetle",
		scale = 1.15,
		color = { 150, 110, 52 },
		glow = { 90, 230, 200 },
	},
	SandstoneGolem = {
		id = "SandstoneGolem",
		name = "Sandstone Golem",
		level = 29,
		elite = true,
		hpScale = 4,
		attackScale = 1.1,
		defenseScale = 1.6,
		attackCoefficient = 0.45,
		attackRange = 9,
		windup = 0.9,
		attackCooldown = 2.8,
		aggroRadius = 34,
		leashRadius = 90,
		moveSpeed = 10,
		xp = 1400,
		body = "Golem",
		scale = 1.6,
		color = { 206, 168, 116 },
		glow = { 255, 190, 90 },
	},
	-- Jungle Rift (Phase 13) field creatures, for Quest 7 and PvE between fights.
	-- Levels 25-30 (D-49).
	JungleProwler = {
		id = "JungleProwler",
		name = "Jungle Prowler",
		level = 25,
		elite = false,
		hpScale = 1.1,
		attackScale = 0.95,
		defenseScale = 1,
		attackCoefficient = 0.22,
		attackRange = 6,
		windup = 0.4,
		attackCooldown = 1.5,
		aggroRadius = 30,
		leashRadius = 90,
		moveSpeed = 19,
		xp = 250,
		body = "Wolf",
		scale = 1.1,
		color = { 52, 70, 48 },
		glow = { 190, 255, 110 },
	},
	Thorncrawler = {
		id = "Thorncrawler",
		name = "Thorncrawler",
		level = 27,
		elite = false,
		hpScale = 1.7,
		attackScale = 0.9,
		defenseScale = 1.4,
		attackCoefficient = 0.28,
		attackRange = 6.5,
		windup = 0.6,
		attackCooldown = 2.2,
		aggroRadius = 26,
		leashRadius = 90,
		moveSpeed = 11,
		xp = 350,
		body = "Beetle",
		scale = 1.2,
		color = { 96, 70, 46 },
		glow = { 230, 90, 170 },
	},
	MossbackGolem = {
		id = "MossbackGolem",
		name = "Mossback Golem",
		level = 29,
		elite = true,
		hpScale = 4.2,
		attackScale = 1.1,
		defenseScale = 1.6,
		attackCoefficient = 0.45,
		attackRange = 9,
		windup = 0.9,
		attackCooldown = 2.8,
		aggroRadius = 34,
		leashRadius = 90,
		moveSpeed = 10,
		xp = 1400,
		body = "Golem",
		scale = 1.65,
		color = { 92, 110, 84 },
		glow = { 120, 255, 170 },
	},
	-- Boss: abilities and phases live in DungeonDefinitions (Bosses).
	RiftGuardian = {
		id = "RiftGuardian",
		name = "Rift Guardian",
		level = 4,
		elite = true,
		hpScale = 14,
		attackScale = 1.1,
		defenseScale = 1.6,
		attackCoefficient = 0.4,
		attackRange = 11,
		windup = 0.8,
		attackCooldown = 2.6,
		aggroRadius = 60,
		leashRadius = 70,
		moveSpeed = 12,
		xp = 350,
		body = "Guardian",
		scale = 2.4,
		color = { 96, 92, 104 },
		glow = { 110, 200, 255 },
	},
}

--------------------------------------------------------------------------------
-- Generated roster (creator review 2026-10-17, PLAN.md D-47 / D-49): the
-- deeper dungeon floors' creatures, the floor bosses, the 30 floor-4 mini
-- bosses, the Dungeon Boss and the war-zone bosses. Names come from myth's
-- most fearsome beasts; looks reuse the procedural body plans (D-40) with
-- their own size and colours until the Phase 16 art pass.
--------------------------------------------------------------------------------

-- Behaviour templates per body plan.
local TEMPLATES: { [Body]: { [string]: any } } = {
	Wolf = {
		hpScale = 1.1,
		attackScale = 0.9,
		defenseScale = 1,
		attackCoefficient = 0.22,
		attackRange = 6,
		windup = 0.4,
		attackCooldown = 1.6,
		aggroRadius = 32,
		leashRadius = 90,
		moveSpeed = 17,
	},
	Beetle = {
		hpScale = 1.6,
		attackScale = 0.9,
		defenseScale = 1.4,
		attackCoefficient = 0.28,
		attackRange = 6.5,
		windup = 0.6,
		attackCooldown = 2.2,
		aggroRadius = 28,
		leashRadius = 90,
		moveSpeed = 11,
	},
	Golem = {
		hpScale = 4,
		attackScale = 1.1,
		defenseScale = 1.6,
		attackCoefficient = 0.45,
		attackRange = 9,
		windup = 0.9,
		attackCooldown = 2.8,
		aggroRadius = 34,
		leashRadius = 90,
		moveSpeed = 10,
	},
	Guardian = {
		hpScale = 4,
		attackScale = 1.1,
		defenseScale = 1.6,
		attackCoefficient = 0.4,
		attackRange = 9,
		windup = 0.8,
		attackCooldown = 2.6,
		aggroRadius = 34,
		leashRadius = 90,
		moveSpeed = 12,
	},
	Serpent = {
		hpScale = 1.6,
		attackScale = 0.9,
		defenseScale = 1.3,
		attackCoefficient = 0.28,
		attackRange = 7,
		windup = 0.6,
		attackCooldown = 2.2,
		aggroRadius = 30,
		leashRadius = 90,
		moveSpeed = 12,
	},
	Sprite = {
		hpScale = 0.9,
		attackScale = 0.5,
		defenseScale = 0.6,
		attackCoefficient = 0.12,
		attackRange = 5,
		windup = 0.45,
		attackCooldown = 2.2,
		aggroRadius = 14,
		leashRadius = 40,
		moveSpeed = 10,
	},
}

local function creature(
	id: string,
	name: string,
	body: Body,
	level: number,
	elite: boolean,
	xp: number,
	scale: number,
	color: { number },
	glow: { number }
): Enemy
	local enemy = table.clone(TEMPLATES[body]) :: any
	enemy.id = id
	enemy.name = name
	enemy.body = body
	enemy.level = level
	enemy.elite = elite
	enemy.xp = xp
	enemy.scale = scale
	enemy.color = color
	enemy.glow = glow
	if elite then
		enemy.hpScale = math.max(enemy.hpScale, 4)
	end
	return enemy :: Enemy
end

-- Seconds before a boss of each tier enrages (BossBalance).
EnemyDefinitions.ENRAGE_SECONDS = table.freeze({ Boss = 300, Floor = 240, Mini = 180 })
-- A boss's basic hit as a share of a reference player's HP, per tier.
local HIT_SHARE = { Boss = 0.3, Floor = 0.22, Mini = 0.18 }

--[[
	A boss: big, slow to anger, HP and hit strength designed by
	Logic/BossBalance for its tier (Boss: 1 player impossible, 2 super hard,
	party very hard, union hard; Floor: one notch easier; Mini: a duo's fight).
]]
local function boss(
	id: string,
	name: string,
	body: Body,
	level: number,
	tier: BossBalance.Tier,
	scale: number,
	color: { number },
	glow: { number },
	duoFraction: number?,
	gentle: boolean?
): Enemy
	local enemy = creature(id, name, body, level, true, 0, scale, color, glow) :: any
	enemy.gentle = gentle == true
	enemy.tier = tier
	enemy.aggroRadius = if tier == "Mini" then 40 else 60
	enemy.leashRadius = if tier == "Mini" then 60 else 80
	enemy.attackRange = if tier == "Mini" then 10 else 12
	enemy.windup = 0.8
	enemy.attackCooldown = 2.6
	enemy.moveSpeed = if tier == "Mini" then 13 else 12
	enemy.defenseScale = 1.6
	local enrage = EnemyDefinitions.ENRAGE_SECONDS[tier]
	local fraction = duoFraction or BossBalance.DUO_FRACTION[tier]
	enemy.hpScale = BossBalance.hpFor(level, enemy.defenseScale, fraction, enrage, gentle)
		/ BossBalance.creatureBase(level, gentle).MaxHP
	enemy.attackCoefficient = 0.6
	enemy.attackScale = BossBalance.attackScaleFor(level, enemy.attackCoefficient, HIT_SHARE[tier], gentle)
	enemy.xp = math.floor(400 + level * level * (if tier == "Mini" then 4 else 10))
	return enemy :: Enemy
end

local field = BossBalance.fieldDuoFraction

local roster: { Enemy } = {
	-- Floor 2: the Ember Depths (levels 11-20).
	creature("EmberHound", "Ember Hound", "Wolf", 12, false, 260, 1.05, { 90, 50, 40 }, { 255, 130, 60 }),
	creature(
		"CinderScarab",
		"Cinder Scarab",
		"Beetle",
		14,
		false,
		380,
		1.15,
		{ 70, 46, 40 },
		{ 255, 90, 40 }
	),
	creature("MagmaGolem", "Magma Golem", "Golem", 16, true, 1300, 1.6, { 84, 60, 54 }, { 255, 120, 40 }),
	-- Floor 3: the Frozen Abyss (levels 21-30).
	creature(
		"RimeStalker",
		"Rime Stalker",
		"Wolf",
		22,
		false,
		900,
		1.1,
		{ 170, 190, 210 },
		{ 140, 220, 255 }
	),
	creature(
		"AbyssCrawler",
		"Abyss Crawler",
		"Beetle",
		24,
		false,
		1200,
		1.2,
		{ 40, 48, 70 },
		{ 120, 140, 255 }
	),
	creature(
		"AbyssalKnight",
		"Abyssal Knight",
		"Guardian",
		26,
		true,
		4500,
		1.5,
		{ 60, 64, 84 },
		{ 150, 120, 255 }
	),

	-- Floor bosses (one per floor, guarding the way down).
	boss("Cerberus", "Cerberus, the Gate Hound", "Wolf", 10, "Floor", 3.2, { 46, 40, 50 }, { 255, 110, 60 }),
	boss(
		"Chimera",
		"Chimera of the Ember Depths",
		"Wolf",
		20,
		"Floor",
		3.4,
		{ 150, 96, 50 },
		{ 255, 160, 60 }
	),
	boss(
		"Basilisk",
		"Basilisk, the Stone-Eye",
		"Serpent",
		30,
		"Floor",
		3.4,
		{ 70, 96, 60 },
		{ 210, 255, 90 }
	),
	-- The Dungeon Boss in floor 4's sanctum.
	boss(
		"Typhon",
		"Typhon, Father of Monsters",
		"Guardian",
		40,
		"Boss",
		3.4,
		{ 52, 40, 64 },
		{ 200, 90, 255 }
	),

	-- Desert Rift bosses (levels 30-50).
	boss("Ammit", "Ammit the Devourer", "Wolf", 30, "Boss", 3, { 170, 130, 80 }, { 255, 200, 90 }, field(30)),
	boss(
		"Anzu",
		"Anzu, the Storm Bird",
		"Guardian",
		35,
		"Boss",
		2.8,
		{ 120, 100, 80 },
		{ 140, 200, 255 },
		field(35)
	),
	boss(
		"Sphinx",
		"The Riddling Sphinx",
		"Wolf",
		40,
		"Boss",
		3.4,
		{ 214, 176, 112 },
		{ 255, 220, 120 },
		field(40)
	),
	boss(
		"Apophis",
		"Apophis, Serpent of Sands",
		"Serpent",
		45,
		"Boss",
		3.6,
		{ 120, 70, 46 },
		{ 255, 140, 60 },
		field(45)
	),
	boss(
		"OasisColossus",
		"Oasis Colossus",
		"Golem",
		50,
		"Boss",
		4,
		{ 196, 160, 110 },
		{ 90, 230, 220 },
		field(50)
	),
	-- Jungle Rift bosses (levels 30-50).
	boss(
		"Camazotz",
		"Camazotz, the Death Bat",
		"Wolf",
		30,
		"Boss",
		3,
		{ 50, 40, 46 },
		{ 230, 90, 170 },
		field(30)
	),
	boss(
		"Ahuizotl",
		"Ahuizotl of the River",
		"Wolf",
		35,
		"Boss",
		3,
		{ 40, 70, 80 },
		{ 110, 230, 255 },
		field(35)
	),
	boss("Mapinguari", "Mapinguari", "Golem", 40, "Boss", 3.4, { 92, 70, 52 }, { 190, 255, 110 }, field(40)),
	boss(
		"JungleHydra",
		"Jungle Hydra",
		"Serpent",
		45,
		"Boss",
		3.8,
		{ 52, 86, 56 },
		{ 160, 255, 120 },
		field(45)
	),
	boss(
		"Leviathan",
		"Leviathan of the Falls",
		"Serpent",
		50,
		"Boss",
		4,
		{ 40, 70, 96 },
		{ 90, 200, 255 },
		field(50)
	),
	-- The Nullborn World Boss event (D-91): one in each war zone.
	boss(
		"NullbornHerald",
		"The Nullborn Herald",
		"Guardian",
		50,
		"Boss",
		4.2,
		{ 52, 38, 72 },
		{ 185, 105, 255 },
		field(50)
	),
}

-- D-130: the Abyssal Spire (levels 31-60). Its creatures are "gentle":
-- their stats grow like players past 30 (BossBalance.creatureBase), so the
-- level 60 era stays fair. EXP per kill follows the curve (about 200 kills
-- a level for regular creatures).
local function gentle(enemy: any, xpShare: number?): Enemy
	enemy.gentle = true
	if xpShare then
		enemy.xp = math.floor(XPTable.toNext(math.min(enemy.level, 59)) * xpShare)
	end
	return enemy :: Enemy
end
-- Rows of mixed values: { id, name, body, level, elite, scale, colour, glow }.
local SPIRE_CREATURES: { { any } } = {
	-- Floor 1: the Fallen Bastion (31-40).
	{ "HollowRevenant", "Hollow Revenant", "Wolf", 32, false, 1.15, { 70, 78, 96 }, { 170, 190, 255 } },
	{ "SpireCrawler", "Spire Crawler", "Beetle", 34, false, 1.25, { 54, 50, 78 }, { 190, 130, 255 } },
	{ "BastionColossus", "Bastion Colossus", "Golem", 36, true, 1.7, { 92, 88, 104 }, { 200, 170, 255 } },
	-- Floor 2: the Ashen Throne (41-50).
	{ "HellfireStalker", "Hellfire Stalker", "Wolf", 42, false, 1.2, { 96, 48, 36 }, { 255, 110, 40 } },
	{ "Pyreshell", "Pyreshell", "Beetle", 44, false, 1.3, { 80, 44, 34 }, { 255, 150, 60 } },
	{
		"ObsidianSentinel",
		"Obsidian Sentinel",
		"Guardian",
		46,
		true,
		1.6,
		{ 40, 34, 40 },
		{ 255, 90, 60 },
	},
	-- Floor 3: the Starless Vault (51-60).
	{ "VoidHound", "Void Hound", "Wolf", 52, false, 1.25, { 30, 28, 52 }, { 150, 110, 255 } },
	{ "StarDevourer", "Star Devourer", "Serpent", 54, false, 1.3, { 40, 46, 80 }, { 120, 200, 255 } },
	{ "AstralWarden", "Astral Warden", "Guardian", 56, true, 1.7, { 70, 80, 120 }, { 180, 220, 255 } },
}
for _, spec: any in SPIRE_CREATURES do
	table.insert(
		roster,
		gentle(
			creature(spec[1], spec[2], spec[3], spec[4], spec[5], 0, spec[6], spec[7], spec[8]),
			if spec[5] then 1.5 else 0.5
		)
	)
end
table.insert(
	roster,
	boss(
		"Behemoth",
		"Behemoth of the Bastion",
		"Golem",
		40,
		"Floor",
		3.4,
		{ 84, 80, 100 },
		{ 210, 180, 255 },
		nil,
		true
	)
)
table.insert(
	roster,
	boss(
		"Ifrit",
		"Ifrit, the Ashen King",
		"Guardian",
		50,
		"Floor",
		3.4,
		{ 70, 30, 24 },
		{ 255, 120, 40 },
		nil,
		true
	)
)
table.insert(
	roster,
	boss(
		"Jormungandr",
		"Jormungandr",
		"Serpent",
		58,
		"Floor",
		3.6,
		{ 30, 40, 70 },
		{ 110, 200, 255 },
		nil,
		true
	)
)
table.insert(
	roster,
	boss(
		"RiftEmperor",
		"The Rift Emperor",
		"Guardian",
		60,
		"Boss",
		4.4,
		{ 46, 32, 70 },
		{ 200, 140, 255 },
		nil,
		true
	)
)

-- Floor 4: thirty mini bosses, levels 31-40 (three per level), one per
-- chamber: { id, name, body }. Their element and weight follow below.
EnemyDefinitions.MINI_BOSSES = table.freeze({
	{ "Minotaur", "Minotaur", "Guardian" },
	{ "Gorgon", "Gorgon", "Guardian" },
	{ "HarpyQueen", "Harpy Queen", "Guardian" },
	{ "Fenrir", "Fenrir", "Wolf" },
	{ "Garmr", "Garmr", "Wolf" },
	{ "Orthrus", "Orthrus", "Wolf" },
	{ "Arachne", "Arachne", "Beetle" },
	{ "Scylla", "Scylla", "Beetle" },
	{ "Charybdis", "Charybdis", "Beetle" },
	{ "Tarasque", "Tarasque", "Golem" },
	{ "Grendel", "Grendel", "Golem" },
	{ "Yeti", "Yeti", "Golem" },
	{ "Griffin", "Griffin", "Guardian" },
	{ "Wyvern", "Wyvern", "Guardian" },
	{ "Fafnir", "Fafnir", "Guardian" },
	{ "NemeanLion", "Nemean Lion", "Wolf" },
	{ "Manticore", "Manticore", "Wolf" },
	{ "ErymanthianBoar", "Erymanthian Boar", "Wolf" },
	{ "Cockatrice", "Cockatrice", "Beetle" },
	{ "Bakunawa", "Bakunawa", "Serpent" },
	{ "Taotie", "Taotie", "Beetle" },
	{ "Bunyip", "Bunyip", "Golem" },
	{ "Catoblepas", "Catoblepas", "Golem" },
	{ "Ladon", "Ladon", "Serpent" },
	{ "Echidna", "Echidna", "Serpent" },
	{ "Nian", "Nian", "Guardian" },
	{ "Peryton", "Peryton", "Guardian" },
	{ "Cadejo", "Cadejo", "Wolf" },
	{ "BlackShuck", "Black Shuck", "Wolf" },
	{ "Kelpie", "Kelpie", "Beetle" },
})

-- Each boss's element (D-88), from its myth: the floor and field bosses
-- keep their own colours (within the element's hue); mini bosses wear the
-- element's palette.
local ELEMENT: { [string]: CreatureLanguage.Element } = {
	-- D-130: the Abyssal Spire.
	Behemoth = "Void",
	Ifrit = "Fire",
	Jormungandr = "Sky",
	RiftEmperor = "Void",
	Cerberus = "Fire",
	Chimera = "Fire",
	Basilisk = "Wild",
	Typhon = "Void",
	Ammit = "Sun",
	Anzu = "Sky",
	Sphinx = "Sun",
	Apophis = "Fire",
	OasisColossus = "Tide",
	Camazotz = "Shadow",
	Ahuizotl = "Tide",
	Mapinguari = "Wild",
	JungleHydra = "Wild",
	Leviathan = "Tide",
	NullbornHerald = "Void",
	Minotaur = "Fire",
	Gorgon = "Wild",
	HarpyQueen = "Sky",
	Fenrir = "Sky",
	Garmr = "Shadow",
	Orthrus = "Fire",
	Arachne = "Shadow",
	Scylla = "Tide",
	Charybdis = "Void",
	Tarasque = "Wild",
	Grendel = "Shadow",
	Yeti = "Sky",
	Griffin = "Sun",
	Wyvern = "Wild",
	Fafnir = "Sun",
	NemeanLion = "Sun",
	Manticore = "Fire",
	ErymanthianBoar = "Sky",
	Cockatrice = "Wild",
	Bakunawa = "Tide",
	Taotie = "Shadow",
	Bunyip = "Tide",
	Catoblepas = "Wild",
	Ladon = "Sun",
	Echidna = "Void",
	Nian = "Fire",
	Peryton = "Sky",
	Cadejo = "Void",
	BlackShuck = "Shadow",
	Kelpie = "Tide",
}

-- Mini boss weights (D-88): light and heavy breeds; the rest standard.
EnemyDefinitions.MINI_SCALE = table.freeze({ Light = 1.9, Standard = 2.2, Heavy = 2.5 })
local MINI_WEIGHT: { [string]: "Light" | "Heavy" } = {
	HarpyQueen = "Light",
	Cockatrice = "Light",
	Cadejo = "Light",
	Arachne = "Light",
	Peryton = "Light",
	Kelpie = "Light",
	Tarasque = "Heavy",
	Yeti = "Heavy",
	Fafnir = "Heavy",
	Grendel = "Heavy",
	ErymanthianBoar = "Heavy",
	Minotaur = "Heavy",
	Catoblepas = "Heavy",
}

for index, spec in EnemyDefinitions.MINI_BOSSES do
	local level = 30 + math.ceil(index / 3)
	local palette = CreatureLanguage.ELEMENTS[ELEMENT[spec[1]]]
	local scale = EnemyDefinitions.MINI_SCALE[MINI_WEIGHT[spec[1]] or "Standard"]
	table.insert(
		roster,
		boss(spec[1], spec[2], spec[3] :: any, level, "Mini", scale, palette.body, palette.glow)
	)
end

-- Each boss's myth look on top of its body plan (creator review 2026-10-17:
-- bosses must read as creatures, not statues).
local LOOKS: { [string]: { Trait } } = {
	Cerberus = { "ThreeHeads", "Mane", "Spikes" },
	-- D-130
	Behemoth = { "Spikes", "Horns" },
	Ifrit = { "Horns", "Wings" },
	Jormungandr = { "Crest", "Spikes" },
	RiftEmperor = { "Wings", "Horns", "Crest" },
	Chimera = { "Mane", "Horns", "Wings", "SerpentTail" },
	Basilisk = { "Crest", "Spikes" },
	Typhon = { "Wings", "Horns", "SerpentTail" },
	Ammit = { "Mane" },
	Anzu = { "Wings" },
	Sphinx = { "Mane", "Wings" },
	Apophis = { "Crest" },
	OasisColossus = { "Spikes" },
	Camazotz = { "Wings", "Spikes" },
	Ahuizotl = { "SerpentTail" },
	Mapinguari = { "Spikes" },
	JungleHydra = { "ThreeHeads", "Spikes" },
	Leviathan = { "Crest", "Spikes" },
	Minotaur = { "Horns" },
	Gorgon = { "SerpentTail" },
	HarpyQueen = { "Wings" },
	Fenrir = { "Mane" },
	Garmr = { "Spikes" },
	Orthrus = { "Mane" },
	Grendel = { "Spikes" },
	-- D-88: the Tarasque's spiked shell, the Taotie's horns.
	Tarasque = { "Spikes" },
	Taotie = { "Horns" },
	Griffin = { "Wings" },
	Wyvern = { "Wings", "SerpentTail" },
	Fafnir = { "Wings", "Horns" },
	NemeanLion = { "Mane" },
	Manticore = { "Mane", "SerpentTail" },
	ErymanthianBoar = { "Spikes" },
	Bakunawa = { "Crest" },
	Ladon = { "ThreeHeads" },
	Echidna = { "Crest" },
	Nian = { "Horns", "Mane" },
	Peryton = { "Wings", "Horns" },
	NullbornHerald = { "Horns" },
	Cadejo = { "Spikes" },
	BlackShuck = { "Mane" },
}

for _, enemy in roster do
	local traits = LOOKS[enemy.id]
	if traits then
		(enemy :: any).traits = traits
	end
	if enemy.tier then
		(enemy :: any).element = ELEMENT[enemy.id]
	end
end

for _, enemy in roster do
	assert(enemies[enemy.id] == nil, `duplicate enemy {enemy.id}`)
	enemies[enemy.id] = enemy
end

-- D-95 balance: regular creatures hit twice as hard, elites 1.5x, so a
-- player in a normal drop kit takes ~15-60 hits from a level-matched one
-- (was 20-115). Bosses keep their BossBalance hits.
EnemyDefinitions.REGULAR_DAMAGE_SCALE = 2
EnemyDefinitions.ELITE_DAMAGE_SCALE = 1.5
for _, enemy in enemies do
	if enemy.tier == nil then
		(enemy :: any).attackScale *= if enemy.elite
			then EnemyDefinitions.ELITE_DAMAGE_SCALE
			else EnemyDefinitions.REGULAR_DAMAGE_SCALE
	end
end

local function deepFreeze(value: any): any
	if type(value) == "table" and not table.isfrozen(value) then
		for _, child in value do
			deepFreeze(child)
		end
		table.freeze(value)
	end
	return value
end

EnemyDefinitions.ById = deepFreeze(enemies) :: { [string]: Enemy }

function EnemyDefinitions.get(id: any): Enemy?
	if type(id) ~= "string" then
		return nil
	end
	return EnemyDefinitions.ById[id]
end

-- EXP for defeating `enemy` at `level` (camps may set a level other than
-- the definition's): scaled along the EXP curve, never below 1.
function EnemyDefinitions.xpAt(enemy: Enemy, level: number?): number
	local at = level or enemy.level
	local function curve(l: number): number
		return XPTable.toNext(math.clamp(l, 0, 29))
	end
	local xp = if at == enemy.level then enemy.xp else enemy.xp * curve(at) / curve(enemy.level)
	-- D-95: the creature EXP scale (XPTable.creatureScale).
	return math.max(1, math.floor(xp * XPTable.creatureScale(at) + 0.5))
end

return table.freeze(EnemyDefinitions)
