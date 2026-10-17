--!strict
--[[
	DungeonDefinitions — the Rift Hollow dungeon: 4 floors of rooms, creature
	camps and bosses (CLAUDE.md §11, PLAN.md Phase 9, D-42, D-47).

	Each realm has one persistent copy that every player of that realm shares
	(D-42). Floors (creator review 2026-10-17):
	  1  The Shattered Crypts   creatures 1-10,  floor boss Cerberus (10)
	  2  The Ember Depths       creatures 11-20, floor boss Chimera (20)
	  3  The Frozen Abyss       creatures 21-30, floor boss Basilisk (30)
	  4  The Nullborn Depths    the Hall of Thirty: 30 mini-boss chambers
	                            (levels 31-40), then Typhon's Sanctum, a room
	                            of its own for the Dungeon Boss (40)
	Floors 1-3 are a landing, 7 rooms and the floor boss's lair, joined by
	passages. Every floor is open to every level and nothing is locked; the
	way down is the portal at the back of the lair, guarded by creature
	packs in every room, guards around the lair and the floor boss.

	Geometry, per floor ("floor frame"): x right, z = depth (positive
	deeper), floor top at y = 0. Floors sit side by side in the realm's
	dungeon slot, `offsetX` apart. Rooms are rectangles (`center` {x, z},
	`size` {w, h, d}) with door openings on their sides; passages are open
	corridors joining doors. Camps are placed relative to their room's centre.

	Respawn classes:
	  Mob        Dungeon.MobRespawnSeconds after falling
	  MiniBoss   Dungeon.MiniBossRespawnMinutes
	  FloorBoss  Dungeon.FloorBossRespawnMinutes
	  Boss       Dungeon.BossRespawnHours
	Bosses (DungeonDefinitions.Bosses) telegraph their abilities on the
	ground, change phase at HP fractions and enrage after `enrageSeconds`
	(EnemyDefinitions.ENRAGE_SECONDS, sized by Logic/BossBalance):
	  Circle  {radius} at the targeted player
	  Cone    {radius, angle} in front of the boss
	  Ring    {inner, radius} around the boss (stand close to dodge)
	  Summon  `count` of `enemy` at `level` near the boss

	Display-safe data only. Pure module.
]]

local EnemyDefinitions = require(script.Parent.EnemyDefinitions)

export type RespawnClass = "Mob" | "MiniBoss" | "FloorBoss" | "Boss"

export type Camp = {
	enemy: string,
	x: number,
	z: number,
	count: number,
	class: RespawnClass,
	-- Creature level for this camp (default: the enemy's own).
	level: number?,
}

export type Side = "N" | "S" | "E" | "W"
-- An opening in a room wall: `side`, `offset` along the wall from its middle.
export type Door = { side: Side, offset: number, width: number }

export type RoomKind = "Start" | "Room" | "Lair" | "Hall" | "Chamber" | "Sanctum"

export type Room = {
	id: string,
	name: string,
	kind: RoomKind,
	center: { number }, -- {x, z} in the floor frame
	size: { number }, -- {w, h, d}
	doors: { Door },
	camps: { Camp },
	boss: string?,
}

export type Passage = {
	center: { number }, -- {x, z}
	size: { number }, -- {w, d}
	axis: "X" | "Z", -- direction of travel
}

export type Theme = "Crystal" | "Ember" | "Frost" | "Void"

export type Floor = {
	index: number,
	name: string,
	theme: Theme,
	levels: { number }, -- {min, max} of its creatures
	offsetX: number,
	rooms: { Room },
	passages: { Passage },
	-- Points in the floor frame {x, z}.
	arrival: { number },
	leavePortal: { number },
	upPortal: { number }?,
	downPortal: { number }?,
	-- Index of the room whose boss guards the way down (lair / sanctum).
	bossRoom: number,
}

export type Ability = {
	id: string,
	shape: "Circle" | "Cone" | "Ring" | "Summon",
	radius: number?,
	inner: number?,
	angle: number?,
	telegraph: number,
	coefficient: number?,
	enemy: string?,
	level: number?,
	count: number?,
}

export type Phase = {
	untilHpFraction: number,
	abilities: { string },
	cooldown: number,
	speedScale: number,
	announce: string?,
}

export type Boss = {
	id: string,
	enemy: string,
	abilities: { [string]: Ability },
	phases: { Phase },
	enrageSeconds: number,
}

export type Dungeon = {
	id: string,
	name: string,
	minLevel: number,
	floors: { Floor },
	doorWidth: number,
	-- One-time EXP for everyone who helped defeat a boss spawn, per class.
	bonusXp: { [string]: number },
	atmosphere: string,
}

local DungeonDefinitions = {}

DungeonDefinitions.FLOOR_SPACING = 500
DungeonDefinitions.DOOR_WIDTH = 28
DungeonDefinitions.PASSAGE_LENGTH = 40
DungeonDefinitions.HALL_CHAMBERS_PER_SIDE = 15

--------------------------------------------------------------------------------
-- Bosses (generated from body-plan archetypes)
--------------------------------------------------------------------------------

local bosses: { [string]: Boss } = {}

type Archetype = "Beast" | "Crawler" | "Colossus" | "Titan"

local ARCHETYPE_OF: { [string]: Archetype } = {
	Wolf = "Beast",
	Beetle = "Crawler",
	Golem = "Colossus",
	Guardian = "Titan",
	Sprite = "Beast",
	Serpent = "Crawler",
}

-- Three abilities per archetype: a targeted one, a frontal one and a ring.
local function abilitiesFor(archetype: Archetype, size: number): { [string]: Ability }
	local s = size
	if archetype == "Beast" then
		return {
			Pounce = { id = "Pounce", shape = "Circle", radius = 8 * s, telegraph = 1.1, coefficient = 0.75 },
			Maul = {
				id = "Maul",
				shape = "Cone",
				radius = 15 * s,
				angle = 100,
				telegraph = 1,
				coefficient = 0.65,
			},
			Rampage = {
				id = "Rampage",
				shape = "Ring",
				inner = 7 * s,
				radius = 24 * s,
				telegraph = 1.5,
				coefficient = 0.85,
			},
		}
	elseif archetype == "Crawler" then
		return {
			Spit = { id = "Spit", shape = "Circle", radius = 10 * s, telegraph = 1.2, coefficient = 0.7 },
			Lash = {
				id = "Lash",
				shape = "Cone",
				radius = 17 * s,
				angle = 120,
				telegraph = 1.1,
				coefficient = 0.6,
			},
			Burrow = {
				id = "Burrow",
				shape = "Ring",
				inner = 8 * s,
				radius = 26 * s,
				telegraph = 1.6,
				coefficient = 0.85,
			},
		}
	elseif archetype == "Colossus" then
		return {
			Slam = { id = "Slam", shape = "Circle", radius = 10 * s, telegraph = 1.3, coefficient = 0.8 },
			Sweep = {
				id = "Sweep",
				shape = "Cone",
				radius = 18 * s,
				angle = 110,
				telegraph = 1.1,
				coefficient = 0.65,
			},
			Quake = {
				id = "Quake",
				shape = "Ring",
				inner = 9 * s,
				radius = 30 * s,
				telegraph = 1.6,
				coefficient = 0.9,
			},
		}
	end
	return {
		Smite = { id = "Smite", shape = "Circle", radius = 9 * s, telegraph = 1.2, coefficient = 0.75 },
		Cleave = {
			id = "Cleave",
			shape = "Cone",
			radius = 16 * s,
			angle = 100,
			telegraph = 1.1,
			coefficient = 0.65,
		},
		Shockwave = {
			id = "Shockwave",
			shape = "Ring",
			inner = 9 * s,
			radius = 30 * s,
			telegraph = 1.6,
			coefficient = 0.9,
		},
	}
end

local function abilityIds(archetype: Archetype): { string }
	if archetype == "Beast" then
		return { "Pounce", "Maul", "Rampage" }
	elseif archetype == "Crawler" then
		return { "Spit", "Lash", "Burrow" }
	elseif archetype == "Colossus" then
		return { "Slam", "Sweep", "Quake" }
	end
	return { "Smite", "Cleave", "Shockwave" }
end

--[[
	A boss definition for `enemyId`. `adds`: creatures it summons
	in the middle phase (nil: no summons, e.g. mini bosses).
]]
type Adds = { enemy: string, level: number, count: number }

local function makeBoss(enemyId: string, adds: Adds?): Boss
	local enemy = EnemyDefinitions.get(enemyId)
	assert(enemy and enemy.tier, `{enemyId} is not a boss`)
	local archetype: Archetype = ARCHETYPE_OF[enemy.body] :: any
	local abilities = abilitiesFor(archetype, if enemy.tier == "Mini" then 0.8 else 1)
	local ids = abilityIds(archetype)
	local name = enemy.name:match("^[^,]+") or enemy.name
	local phases: { Phase }
	if enemy.tier == "Mini" then
		phases = {
			{ untilHpFraction = 0.5, abilities = { ids[1], ids[2] }, cooldown = 5, speedScale = 1 },
			{
				untilHpFraction = 0,
				abilities = { ids[1], ids[2], ids[3] },
				cooldown = 4,
				speedScale = 1.15,
				announce = `{name} grows furious! Stay close when the ring appears.`,
			},
		}
	else
		local middle = { ids[1], ids[2] }
		if adds then
			abilities.Summon = {
				id = "Summon",
				shape = "Summon",
				enemy = adds.enemy,
				level = adds.level,
				count = adds.count,
				telegraph = 1.2,
			}
			table.insert(middle, "Summon")
		else
			table.insert(middle, ids[3])
		end
		phases = {
			{ untilHpFraction = 0.65, abilities = { ids[1], ids[2] }, cooldown = 4.5, speedScale = 1 },
			{
				untilHpFraction = 0.3,
				abilities = middle,
				cooldown = 3.8,
				speedScale = 1.1,
				announce = if adds then `{name} calls its brood!` else `{name} lashes out wildly!`,
			},
			{
				untilHpFraction = 0,
				abilities = { ids[1], ids[2], ids[3] },
				cooldown = 3,
				speedScale = 1.25,
				announce = `{name} is in a frenzy! Stay close to dodge the ring.`,
			},
		}
	end
	local boss: Boss = {
		id = enemyId,
		enemy = enemyId,
		abilities = abilities,
		phases = phases,
		enrageSeconds = EnemyDefinitions.ENRAGE_SECONDS[enemy.tier :: any],
	}
	bosses[enemyId] = boss
	return boss
end

makeBoss("Cerberus", { enemy = "RiftWolf", level = 9, count = 2 })
makeBoss("Chimera", { enemy = "EmberHound", level = 19, count = 2 })
makeBoss("Basilisk", { enemy = "AbyssCrawler", level = 29, count = 2 })
makeBoss("Typhon", { enemy = "AbyssalKnight", level = 36, count = 2 })
for _, spec in EnemyDefinitions.MINI_BOSSES do
	makeBoss(spec[1], nil)
end
-- War-zone bosses (PvPService): summons from their own zone's creatures.
makeBoss("Ammit", { enemy = "DuneStalker", level = 28, count = 2 })
makeBoss("Anzu", { enemy = "DuneStalker", level = 29, count = 2 })
makeBoss("Sphinx", { enemy = "SandScarab", level = 30, count = 2 })
makeBoss("Apophis", { enemy = "SandScarab", level = 30, count = 3 })
makeBoss("OasisColossus", { enemy = "SandstoneGolem", level = 30, count = 2 })
makeBoss("Camazotz", { enemy = "JungleProwler", level = 28, count = 2 })
makeBoss("Ahuizotl", { enemy = "JungleProwler", level = 29, count = 2 })
makeBoss("Mapinguari", { enemy = "Thorncrawler", level = 30, count = 2 })
makeBoss("JungleHydra", { enemy = "Thorncrawler", level = 30, count = 3 })
makeBoss("Leviathan", { enemy = "MossbackGolem", level = 30, count = 2 })

--------------------------------------------------------------------------------
-- Floor layouts
--------------------------------------------------------------------------------

local DOOR = DungeonDefinitions.DOOR_WIDTH
local PASSAGE = DungeonDefinitions.PASSAGE_LENGTH
-- Wide enough for two portal gates (30 studs each) side by side.
local LANDING = { 84, 34, 40 }

type RoomSpec = { id: string, name: string, size: { number } }
type FloorSpec = {
	name: string,
	theme: Theme,
	levels: { number },
	-- Regular creature, sturdy creature, elite.
	mobs: { string },
	miniBoss: string,
	rooms: { RoomSpec },
	lair: RoomSpec,
	floorBoss: string,
}

-- Creature groups per room (1-7): {mob slot 1/2/3, count, class?}. Rooms
-- are packed (creator review 2026-10-17: floors are guarded, not locked).
local ROOM_CAMPS: { { { any } } } = {
	{ { 1, 3 }, { 2, 3 }, { 1, 3 }, { 1, 3 } },
	{ { 1, 3 }, { 2, 3 }, { 1, 3 }, { 2, 2 } },
	{ { 2, 3 }, { 1, 3 }, { 2, 2 }, { 1, 3 }, { 3, 1 } },
	{ { 1, 3 }, { 2, 2 }, { 3, 1, "MiniBoss" }, { 1, 3 }, { 2, 2 } },
	{ { 2, 3 }, { 1, 3 }, { 3, 1 }, { 1, 3 }, { 2, 2 } },
	{ { 1, 3 }, { 2, 3 }, { 3, 1 }, { 2, 2 }, { 1, 3 } },
	{ { 2, 3 }, { 1, 3 }, { 3, 2 }, { 1, 3 }, { 2, 3 } },
}

-- Guards around a lair (relative to its centre; the boss stands at z 20
-- and the way down at the back wall): packs on the flanks, two elites
-- flanking the portal. {mob slot, x, z, count}.
local LAIR_GUARDS: { { number } } = {
	{ 1, -62, -48, 3 },
	{ 2, 62, -48, 3 },
	{ 1, -70, 22, 3 },
	{ 2, 70, 22, 3 },
	{ 3, -42, 62, 1 },
	{ 3, 42, 62, 1 },
}

-- Camps spread across a room (relative to its centre, clear of the doors).
local function placeCamps(groups: { { any } }, spec: FloorSpec, w: number, d: number, level: number): { Camp }
	local camps = {}
	local n = #groups
	for i, group in groups do
		local slot, count, class = group[1], group[2], group[3] or "Mob"
		local enemy = if class == "MiniBoss" then spec.miniBoss else spec.mobs[slot]
		local fx = (i - 0.5) / n
		local x = (-w / 2 + 24) + fx * (w - 48)
		local z = if i % 2 == 1 then -d / 2 + 0.38 * d else -d / 2 + 0.7 * d
		if class == "MiniBoss" then
			x, z = 0, d / 2 - 34
		end
		table.insert(camps, {
			enemy = enemy,
			x = math.floor(x + 0.5),
			z = math.floor(z + 0.5),
			count = count,
			class = class,
			level = math.min(level + (if slot == 3 then 1 else 0), spec.levels[2] - 1),
		})
	end
	return camps
end

local function door(side: Side, offset: number?): Door
	return { side = side, offset = offset or 0, width = DOOR }
end

local function landing(floorIndex: number): Room
	return {
		id = `F{floorIndex}Landing`,
		name = "Landing",
		kind = "Start",
		center = { 0, LANDING[3] / 2 },
		size = LANDING,
		doors = { door("S") },
		camps = {},
	}
end

-- Floors 1-3: landing, 7 rooms and the lair in a line (deeper = +z).
local function chainFloor(index: number, spec: FloorSpec): Floor
	local rooms: { Room } = { landing(index) }
	local passages: { Passage } = {}
	local z = LANDING[3]
	local count = #spec.rooms
	local span = spec.levels[2] - 1 - spec.levels[1]
	local all = table.clone(spec.rooms)
	table.insert(all, spec.lair)
	for r, roomSpec in all do
		table.insert(passages, { center = { 0, z + PASSAGE / 2 }, size = { DOOR, PASSAGE }, axis = "Z" })
		z += PASSAGE
		local w, h, d = roomSpec.size[1], roomSpec.size[2], roomSpec.size[3]
		local isLair = r > count
		local camps: { Camp }
		if isLair then
			camps = { { enemy = spec.floorBoss, x = 0, z = 20, count = 1, class = "FloorBoss" } }
			for _, guard in LAIR_GUARDS do
				table.insert(camps, {
					enemy = spec.mobs[guard[1]],
					x = guard[2],
					z = guard[3],
					count = guard[4],
					class = "Mob",
					level = spec.levels[2] - 1,
				})
			end
		else
			local level = spec.levels[1] + math.floor((r - 1) * span / (count - 1) + 0.5)
			camps = placeCamps(ROOM_CAMPS[r], spec, w, d, level)
		end
		table.insert(rooms, {
			id = roomSpec.id,
			name = roomSpec.name,
			kind = if isLair then "Lair" else "Room",
			center = { 0, z + d / 2 },
			size = { w, h, d },
			doors = if isLair then { door("N") } else { door("N"), door("S") },
			camps = camps,
			boss = if isLair then spec.floorBoss else nil,
		})
		z += d
	end
	return {
		index = index,
		name = spec.name,
		theme = spec.theme,
		levels = spec.levels,
		offsetX = (index - 1) * DungeonDefinitions.FLOOR_SPACING,
		rooms = rooms,
		passages = passages,
		arrival = { 0, 28 },
		leavePortal = { -20, 8 },
		upPortal = if index > 1 then { 20, 8 } else nil,
		downPortal = { 0, z - 12 },
		bossRoom = #rooms,
	}
end

-- Floor 4: landing, the Hall of Thirty (15 chambers a side) and the sanctum.
local function hallFloor(index: number): Floor
	local rooms: { Room } = { landing(index) }
	local passages: { Passage } = {}
	local perSide = DungeonDefinitions.HALL_CHAMBERS_PER_SIDE
	local hallW, chamberW, chamberD, pitch = 44, 56, 44, 52
	local link = 6 -- through the hall wall and the chamber wall
	local z = LANDING[3]
	table.insert(passages, { center = { 0, z + PASSAGE / 2 }, size = { DOOR, PASSAGE }, axis = "Z" })
	z += PASSAGE
	local hallD = 30 + perSide * pitch
	local hallZ0 = z
	local hallDoors = { door("N"), door("S") }
	local chambers: { Room } = {}
	for i, spec in EnemyDefinitions.MINI_BOSSES do
		local sideIndex = (i - 1) // perSide -- 0: west, 1: east
		local k = (i - 1) % perSide
		local side: Side = if sideIndex == 0 then "W" else "E"
		local sign = if sideIndex == 0 then -1 else 1
		local cz = hallZ0 + 30 + k * pitch + chamberD / 2 - 4
		-- Door offsets run along the wall from its middle (toward +z).
		local alongHall = cz - (hallZ0 + hallD / 2)
		table.insert(hallDoors, { side = side, offset = alongHall, width = 18 })
		-- Hall wall (3) and chamber wall (3) back to back, bridged by a link.
		local cx = sign * (hallW / 2 + link + chamberW / 2)
		table.insert(passages, {
			center = { sign * (hallW / 2 + link / 2), cz },
			size = { link, 18 },
			axis = "X",
		})
		local enemy = EnemyDefinitions.get(spec[1]) :: EnemyDefinitions.Enemy
		table.insert(chambers, {
			id = `Chamber{i}`,
			name = `{enemy.name}'s Chamber`,
			kind = "Chamber",
			center = { cx, cz },
			size = { chamberW, 34, chamberD },
			doors = { { side = if sign < 0 then "E" else "W", offset = 0, width = 18 } },
			camps = { { enemy = spec[1], x = sign * 6, z = 0, count = 1, class = "MiniBoss" } },
			boss = spec[1],
		})
	end
	table.insert(rooms, {
		id = "HallOfThirty",
		name = "Hall of Thirty",
		kind = "Hall",
		center = { 0, hallZ0 + hallD / 2 },
		size = { hallW, 40, hallD },
		doors = hallDoors,
		camps = {},
	})
	for _, chamber in chambers do
		table.insert(rooms, chamber)
	end
	z = hallZ0 + hallD
	table.insert(passages, { center = { 0, z + PASSAGE / 2 }, size = { DOOR, PASSAGE }, axis = "Z" })
	z += PASSAGE
	local sanctum = { 200, 76, 190 }
	table.insert(rooms, {
		id = "TyphonSanctum",
		name = "Typhon's Sanctum",
		kind = "Sanctum",
		center = { 0, z + sanctum[3] / 2 },
		size = sanctum,
		doors = { door("N") },
		camps = { { enemy = "Typhon", x = 0, z = 25, count = 1, class = "Boss" } },
		boss = "Typhon",
	})
	return {
		index = index,
		name = "The Nullborn Depths",
		theme = "Void",
		levels = { 31, 40 },
		offsetX = (index - 1) * DungeonDefinitions.FLOOR_SPACING,
		rooms = rooms,
		passages = passages,
		arrival = { 0, 28 },
		leavePortal = { -20, 8 },
		upPortal = { 20, 8 },
		downPortal = nil,
		bossRoom = #rooms,
	}
end

local function rooms(specs: { { any } }): { RoomSpec }
	local out = {}
	for _, s in specs do
		table.insert(out, { id = s[1], name = s[2], size = s[3] })
	end
	return out
end

local floors: { Floor } = {
	chainFloor(1, {
		name = "The Shattered Crypts",
		theme = "Crystal",
		levels = { 1, 10 },
		mobs = { "RiftWolf", "CrystalBeetle", "StonebackGuardian" },
		miniBoss = "StonebackGuardian",
		rooms = rooms({
			{ "EntryHall", "Shattered Entry Hall", { 140, 46, 150 } },
			{ "CandleNave", "Candlelit Nave", { 150, 48, 160 } },
			{ "CrystalGallery", "Crystal Gallery", { 170, 54, 180 } },
			{ "GuardianGate", "Guardian's Gate", { 160, 52, 180 } },
			{ "SunkenCloister", "Sunken Cloister", { 150, 50, 160 } },
			{ "BrokenChapel", "Broken Chapel", { 160, 56, 170 } },
			{ "RiftWell", "The Rift Well", { 170, 56, 170 } },
		}),
		lair = { id = "CerberusGate", name = "Cerberus's Gate", size = { 190, 72, 190 } },
		floorBoss = "Cerberus",
	}),
	chainFloor(2, {
		name = "The Ember Depths",
		theme = "Ember",
		levels = { 11, 20 },
		mobs = { "EmberHound", "CinderScarab", "MagmaGolem" },
		miniBoss = "MagmaGolem",
		rooms = rooms({
			{ "CinderStair", "Cinder Stair", { 140, 46, 150 } },
			{ "AshGallery", "Ash Gallery", { 160, 50, 170 } },
			{ "OldForge", "The Old Forge", { 170, 54, 180 } },
			{ "LavaHall", "Lava Bridge Hall", { 160, 56, 180 } },
			{ "SmoulderVault", "Smoulder Vault", { 150, 50, 160 } },
			{ "ObsidianCloister", "Obsidian Cloister", { 160, 54, 170 } },
			{ "MagmaRift", "Magma Rift", { 170, 58, 170 } },
		}),
		lair = { id = "ChimeraDen", name = "Chimera's Den", size = { 190, 72, 190 } },
		floorBoss = "Chimera",
	}),
	chainFloor(3, {
		name = "The Frozen Abyss",
		theme = "Frost",
		levels = { 21, 30 },
		mobs = { "RimeStalker", "AbyssCrawler", "AbyssalKnight" },
		miniBoss = "AbyssalKnight",
		rooms = rooms({
			{ "RimeGate", "Rime Gate", { 140, 46, 150 } },
			{ "IcicleHall", "Hall of Icicles", { 160, 54, 170 } },
			{ "AbyssLibrary", "Abyssal Library", { 170, 56, 180 } },
			{ "FrozenChoir", "Frozen Choir", { 160, 56, 180 } },
			{ "GlacierVault", "Glacier Vault", { 150, 50, 160 } },
			{ "StarlessNave", "Starless Nave", { 160, 58, 170 } },
			{ "SunkenThrone", "Sunken Throne", { 170, 60, 170 } },
		}),
		lair = { id = "BasiliskHall", name = "Basilisk's Mirror Hall", size = { 190, 72, 190 } },
		floorBoss = "Basilisk",
	}),
	hallFloor(4),
}

local dungeons: { [string]: Dungeon } = {
	RiftHollow = {
		id = "RiftHollow",
		name = "Rift Hollow",
		minLevel = 1,
		floors = floors,
		doorWidth = DOOR,
		bonusXp = { MiniBoss = 400, FloorBoss = 1500, Boss = 5000 },
		atmosphere = "Dungeon",
	},
}

local function deepFreeze(value: any): any
	if type(value) == "table" and not table.isfrozen(value) then
		for _, child in value do
			deepFreeze(child)
		end
		table.freeze(value)
	end
	return value
end

DungeonDefinitions.ById = deepFreeze(dungeons) :: { [string]: Dungeon }
DungeonDefinitions.Bosses = deepFreeze(bosses) :: { [string]: Boss }

function DungeonDefinitions.get(id: any): Dungeon?
	if type(id) ~= "string" then
		return nil
	end
	return DungeonDefinitions.ById[id]
end

function DungeonDefinitions.boss(id: any): Boss?
	if type(id) ~= "string" then
		return nil
	end
	return DungeonDefinitions.Bosses[id]
end

-- {minX, maxX, minZ, maxZ} of a floor in its floor frame (rooms and passages).
local boundsCache: { [Floor]: { number } } = {}
function DungeonDefinitions.floorBounds(floor: Floor): { number }
	local cached = boundsCache[floor]
	if cached then
		return cached
	end
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	local function add(cx: number, cz: number, w: number, d: number)
		minX, maxX = math.min(minX, cx - w / 2), math.max(maxX, cx + w / 2)
		minZ, maxZ = math.min(minZ, cz - d / 2), math.max(maxZ, cz + d / 2)
	end
	for _, room in floor.rooms do
		add(room.center[1], room.center[2], room.size[1], room.size[3])
	end
	for _, passage in floor.passages do
		add(passage.center[1], passage.center[2], passage.size[1], passage.size[2])
	end
	local bounds = table.freeze({ minX, maxX, minZ, maxZ })
	boundsCache[floor] = bounds
	return bounds
end

-- Index of the room containing floor-frame point (x, z), or nil (passages).
function DungeonDefinitions.roomAt(floor: Floor, x: number, z: number): number?
	for index, room in floor.rooms do
		local cx, cz = room.center[1], room.center[2]
		if math.abs(x - cx) <= room.size[1] / 2 and math.abs(z - cz) <= room.size[3] / 2 then
			return index
		end
	end
	return nil
end

--[[
	Which floor a point in the copy's frame is on: copy-frame x / z (z =
	depth, positive deeper). Returns (floor index, floor-frame x) or nil.
]]
function DungeonDefinitions.floorAt(
	dungeon: Dungeon,
	x: number,
	z: number,
	margin: number?
): (number?, number)
	local pad = margin or 30
	for index, floor in dungeon.floors do
		local b = DungeonDefinitions.floorBounds(floor)
		local fx = x - floor.offsetX
		if fx >= b[1] - pad and fx <= b[2] + pad and z >= b[3] - pad and z <= b[4] + pad then
			return index, fx
		end
	end
	return nil, 0
end

return table.freeze(DungeonDefinitions)
