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
	Visual: body plan + palette for the procedural creature builder.

	Display-safe data only. Pure module.
]]

local BossBalance = require(script.Parent.Parent.Logic.BossBalance)
local StatFormulas = require(script.Parent.Parent.Logic.StatFormulas)
local XPTable = require(script.Parent.Parent.Logic.XPTable)

export type Body = "Wolf" | "Beetle" | "Golem" | "Sprite" | "Guardian" | "Serpent"

-- Extra anatomy a body plan can carry (CreatureBuilder; animated by
-- MobVisualController): bosses get their myth's look from these.
export type Trait = "ThreeHeads" | "Mane" | "Horns" | "Wings" | "SerpentTail" | "Spikes" | "Crest"

export type Enemy = {
	id: string,
	name: string,
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
	duoFraction: number?
): Enemy
	local enemy = creature(id, name, body, level, true, 0, scale, color, glow) :: any
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
	enemy.hpScale = BossBalance.hpFor(level, enemy.defenseScale, fraction, enrage)
		/ StatFormulas.forCreatureLevel(level).MaxHP
	enemy.attackCoefficient = 0.6
	enemy.attackScale = BossBalance.attackScaleFor(level, enemy.attackCoefficient, HIT_SHARE[tier])
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
}

-- Floor 4: thirty mini bosses, levels 31-40 (three per level), one per chamber.
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

local MINI_COLORS = {
	{ { 96, 60, 52 }, { 255, 140, 80 } },
	{ { 60, 90, 70 }, { 160, 255, 140 } },
	{ { 80, 70, 110 }, { 210, 150, 255 } },
	{ { 50, 60, 90 }, { 120, 190, 255 } },
	{ { 110, 96, 70 }, { 255, 220, 120 } },
	{ { 70, 50, 60 }, { 255, 110, 160 } },
}

for index, spec in EnemyDefinitions.MINI_BOSSES do
	local level = 30 + math.ceil(index / 3)
	local colors = MINI_COLORS[(index - 1) % #MINI_COLORS + 1]
	table.insert(roster, boss(spec[1], spec[2], spec[3] :: any, level, "Mini", 2.2, colors[1], colors[2]))
end

-- Each boss's myth look on top of its body plan (creator review 2026-10-17:
-- bosses must read as creatures, not statues).
local LOOKS: { [string]: { Trait } } = {
	Cerberus = { "ThreeHeads", "Mane", "Spikes" },
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
	Cadejo = { "Spikes" },
	BlackShuck = { "Mane" },
}

for _, enemy in roster do
	local traits = LOOKS[enemy.id]
	if traits then
		(enemy :: any).traits = traits
	end
end

for _, enemy in roster do
	assert(enemies[enemy.id] == nil, `duplicate enemy {enemy.id}`)
	enemies[enemy.id] = enemy
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
	if at == enemy.level then
		return enemy.xp
	end
	local function curve(l: number): number
		return XPTable.toNext(math.clamp(l, 0, 29))
	end
	return math.max(1, math.floor(enemy.xp * curve(at) / curve(enemy.level) + 0.5))
end

return table.freeze(EnemyDefinitions)
