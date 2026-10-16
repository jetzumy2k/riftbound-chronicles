--!strict
--[[
	WorldLayout
	Positions of the race capitals, their spawn points and safe zones
	(ARCHITECTURE.md §2: one place, spatially separated regions).

	Phase 3 uses graybox geometry built by WorldService from this data; the art
	pass (Phase 16) replaces the visuals but keeps these anchors.

	Vectors are {x, y, z} tables so this stays a pure module. Spawns are
	deterministic: each race always spawns on its own fixed SpawnLocation.

	Display-safe data only. Pure module.
]]

export type Vec = { number }

export type Volume = {
	kind: "cylinder" | "box",
	center: Vec,
	-- cylinder
	radius: number?,
	halfHeight: number?,
	-- box
	size: Vec?,
}

export type Realm = {
	race: string,
	zone: string,
	displayName: string,
	platformCenter: Vec,
	platformSize: Vec,
	spawnPosition: Vec,
	spawnLookAt: Vec,
	-- {r, g, b}
	baseColor: { number },
	trimColor: { number },
}

export type SafeZone = {
	id: string,
	race: string?, -- owning race, nil = neutral
	displayName: string,
	volume: Volume,
}

local WorldLayout = {}

WorldLayout.Realms = table.freeze({
	Angel = table.freeze({
		race = "Angel",
		zone = "AngelCapital",
		displayName = "Skyreach Citadel",
		platformCenter = { 0, 150, -600 },
		platformSize = { 300, 6, 300 },
		spawnPosition = { 0, 153.5, -600 },
		spawnLookAt = { 0, 153.5, -700 },
		baseColor = { 236, 232, 220 },
		trimColor = { 255, 214, 120 },
	} :: Realm),
	Devil = table.freeze({
		race = "Devil",
		zone = "DevilCapital",
		displayName = "Emberdeep Bastion",
		platformCenter = { 0, 20, 600 },
		platformSize = { 300, 6, 300 },
		spawnPosition = { 0, 23.5, 600 },
		spawnLookAt = { 0, 23.5, 700 },
		baseColor = { 46, 40, 44 },
		trimColor = { 255, 112, 52 },
	} :: Realm),
})

WorldLayout.SafeZones = table.freeze({
	table.freeze({
		id = "AngelCapital",
		race = "Angel",
		displayName = "Skyreach Citadel",
		volume = { kind = "cylinder", center = { 0, 150, -600 }, radius = 110, halfHeight = 70 },
	} :: SafeZone),
	table.freeze({
		id = "DevilCapital",
		race = "Devil",
		displayName = "Emberdeep Bastion",
		volume = { kind = "cylinder", center = { 0, 20, 600 }, radius = 110, halfHeight = 70 },
	} :: SafeZone),
	-- Phase 12: each realm's camp at opposite edges of the Desert Rift. The
	-- oasis in the middle is open PvP ground.
	table.freeze({
		id = "DesertAngelCamp",
		race = "Angel",
		displayName = "Angel Camp",
		volume = { kind = "cylinder", center = { -3200, 30, -360 }, radius = 40, halfHeight = 50 },
	} :: SafeZone),
	table.freeze({
		id = "DesertDevilCamp",
		race = "Devil",
		displayName = "Devil Camp",
		volume = { kind = "cylinder", center = { -3200, 30, 360 }, radius = 40, halfHeight = 50 },
	} :: SafeZone),
	-- Phase 13: the same for the Jungle Rift; the waterfall pool between is
	-- open PvP ground.
	table.freeze({
		id = "JungleAngelCamp",
		race = "Angel",
		displayName = "Angel Camp",
		volume = { kind = "cylinder", center = { 3200, 32, -360 }, radius = 40, halfHeight = 50 },
	} :: SafeZone),
	table.freeze({
		id = "JungleDevilCamp",
		race = "Devil",
		displayName = "Devil Camp",
		volume = { kind = "cylinder", center = { 3200, 32, 360 }, radius = 40, halfHeight = 50 },
	} :: SafeZone),
})

-- Where the camera looks while a new player chooses a race.
WorldLayout.SelectionCamera = table.freeze({
	position = { 0, 220, 0 },
	lookAt = { 0, 90, 0 },
})

-- Training yard (Phase 6): an open area attached to each capital, in front of
-- the spawn and outside the safe zone, so melee AND ranged jobs can practise.
-- Training dummies stand at the far end (Phase 9 adds real mobs).
WorldLayout.TrainingYard = table.freeze({
	depth = 160,
	width = 180,
	dummySpacing = 45,
	dummyInset = 25, -- from the far edge
	rangeMarkers = table.freeze({ 10, 20, 30, 40, 50 }), -- studs from the dummy line
})

WorldLayout.TrainingDummy = table.freeze({
	countPerRealm = 3,
	level = 1,
	maxHp = 2500,
})

-- +1 / -1: which way along Z the spawn faces (the yard lies that way).
function WorldLayout.yardDirection(realm: Realm): number
	return if realm.spawnLookAt[3] >= realm.spawnPosition[3] then 1 else -1
end

-- Yard platform center {x, y, z} and size {x, y, z}.
function WorldLayout.trainingYard(realm: Realm): ({ number }, { number })
	local yard = WorldLayout.TrainingYard
	local dir = WorldLayout.yardDirection(realm)
	local c = realm.platformCenter
	local center = { c[1], c[2], c[3] + dir * (realm.platformSize[3] / 2 + yard.depth / 2) }
	return center, { yard.width, realm.platformSize[2], yard.depth }
end

--[[
	Positions {x, y, z} of the training dummies for a realm (feet on the yard
	top), spread across the far end of the yard.
]]
function WorldLayout.dummyPositions(realm: Realm): { { number } }
	local yard = WorldLayout.TrainingYard
	local count = WorldLayout.TrainingDummy.countPerRealm
	local dir = WorldLayout.yardDirection(realm)
	local center, size = WorldLayout.trainingYard(realm)
	local top = center[2] + size[2] / 2
	local lineZ = center[3] + dir * (size[3] / 2 - yard.dummyInset)
	local positions = {}
	for i = 1, count do
		local offset = (i - (count + 1) / 2) * yard.dummySpacing
		table.insert(positions, { center[1] + offset, top, lineZ })
	end
	return positions
end

--------------------------------------------------------------------------------
-- City plan (Phase 16 capitals art, pulled forward; PLAN.md D-37)
--------------------------------------------------------------------------------

--[[
	Placements are in the realm's *local* frame, in studs from the platform's
	top centre: {right, up, forward}, where "forward" is the way the spawn
	faces (toward the training yard). The same plan is used by both capitals;
	each race builds it in its own style.
]]
export type Gate = {
	id: string,
	label: string,
	-- Where it leads and when it opens (shown on the gate until then).
	destination: string,
	opensIn: string,
	position: Vec,
	-- Degrees around the vertical axis: 0 faces forward, 90 faces right.
	facing: number,
}

WorldLayout.City = table.freeze({
	-- Grand cathedral (Angels) / keep (Devils) behind the spawn.
	landmark = table.freeze({ position = { 0, 0, -118 }, width = 76, depth = 44 }),
	-- Towers at the platform corners.
	towers = table.freeze({
		{ 128, 0, 128 },
		{ -128, 0, 128 },
		{ 128, 0, -128 },
		{ -128, 0, -128 },
	}),
	-- Lamps / braziers around the plaza ring.
	lampRadius = 58,
	lampCount = 8,
	-- Colonnades along both sides.
	colonnadeOffset = 138,
	colonnadeColumns = 7,
	gates = table.freeze({
		table.freeze({
			id = "DesertRift",
			label = "Desert Rift",
			destination = "DesertRift",
			opensIn = "War zones update",
			position = { -126, 0, 30 },
			facing = 90,
		} :: Gate),
		table.freeze({
			id = "JungleRift",
			label = "Jungle Rift",
			destination = "JungleRift",
			opensIn = "War zones update",
			position = { 126, 0, 30 },
			facing = -90,
		} :: Gate),
		table.freeze({
			id = "Dungeons",
			label = "Rift Dungeons",
			destination = "Dungeons",
			opensIn = "Dungeons update",
			position = { -64, 0, -126 },
			facing = 0,
		} :: Gate),
	}),
})

--[[
	World position {x, y, z} `distance` studs in front of gate `gateId` on
	the ground, and the gate's facing {x, y, z} (unit). nil if no such gate.
]]
function WorldLayout.gateFront(realm: Realm, gateId: string, distance: number): ({ number }?, { number }?)
	for _, gate in WorldLayout.City.gates do
		if gate.id == gateId then
			local a = math.rad(gate.facing)
			local p = gate.position
			local point = WorldLayout.toWorld(
				realm,
				{ p[1] + math.sin(a) * distance, 0, p[3] + math.cos(a) * distance }
			)
			local right, forward = WorldLayout.axes(realm)
			local facing = {
				forward[1] * math.cos(a) + right[1] * math.sin(a),
				0,
				forward[3] * math.cos(a) + right[3] * math.sin(a),
			}
			return point, facing
		end
	end
	return nil, nil
end

-- Unit vectors {x, y, z} of a realm's local frame: right, forward.
function WorldLayout.axes(realm: Realm): ({ number }, { number })
	local dir = WorldLayout.yardDirection(realm)
	return { -dir, 0, 0 }, { 0, 0, dir }
end

-- World position {x, y, z} of a local {right, up, forward} point on a realm.
function WorldLayout.toWorld(realm: Realm, localPoint: Vec): { number }
	local right, forward = WorldLayout.axes(realm)
	local c = realm.platformCenter
	local top = c[2] + realm.platformSize[2] / 2
	return {
		c[1] + right[1] * localPoint[1] + forward[1] * localPoint[3],
		top + localPoint[2],
		c[3] + right[3] * localPoint[1] + forward[3] * localPoint[3],
	}
end

--------------------------------------------------------------------------------
-- War zones (Phase 12/13; CLAUDE.md §13, PLAN.md D-41/D-43). Open PvP
-- between the realms everywhere except each realm's own camp at opposite
-- edges. Square regions far from the capitals; `terrain` picks the
-- heightmap (Logic/WarZoneTerrain).
--------------------------------------------------------------------------------

export type Camp = { enemy: string, x: number, z: number, count: number }

-- A realm's base in a war zone: arrival point, return portal and safe zone,
-- relative to the zone centre. Only that realm can pass its barrier.
export type Base = { x: number, z: number, safeZone: string, radius: number }

export type WarZone = {
	id: string,
	name: string,
	-- Ground centre {x, y, z}: y is the oasis plaza surface.
	center: Vec,
	size: number,
	-- Height of the camp plateaus above the centre's y.
	baseHeight: number,
	bases: { [string]: Base },
	-- "Desert" | "Jungle" (Logic/WarZoneTerrain).
	terrain: string,
	atmosphere: string,
	camps: { Camp },
}

WorldLayout.WarZones = table.freeze({
	DesertRift = table.freeze({
		id = "DesertRift",
		name = "Desert Rift",
		center = table.freeze({ -3200, 24, 0 }),
		size = 1000,
		baseHeight = 6,
		bases = table.freeze({
			Angel = table.freeze({ x = 0, z = -360, safeZone = "DesertAngelCamp", radius = 40 } :: Base),
			Devil = table.freeze({ x = 0, z = 360, safeZone = "DesertDevilCamp", radius = 40 } :: Base),
		}),
		terrain = "Desert",
		atmosphere = "Desert",
		camps = table.freeze({
			-- Around the oasis: contested PvP ground with creatures (and, in
			-- Phase 14, the PvP boss).
			table.freeze({ enemy = "SandScarab", x = 48, z = 22, count = 2 }),
			table.freeze({ enemy = "DuneStalker", x = -48, z = -22, count = 3 }),
			table.freeze({ enemy = "DuneStalker", x = 190, z = 120, count = 3 }),
			table.freeze({ enemy = "DuneStalker", x = -210, z = -150, count = 3 }),
			table.freeze({ enemy = "DuneStalker", x = 60, z = -260, count = 3 }),
			table.freeze({ enemy = "SandScarab", x = -240, z = 170, count = 2 }),
			table.freeze({ enemy = "SandScarab", x = 260, z = -120, count = 2 }),
			table.freeze({ enemy = "SandstoneGolem", x = -180, z = 270, count = 1 }),
			table.freeze({ enemy = "SandstoneGolem", x = 300, z = 260, count = 1 }),
		}),
	} :: WarZone),
	JungleRift = table.freeze({
		id = "JungleRift",
		name = "Jungle Rift",
		center = table.freeze({ 3200, 24, 0 }),
		size = 1000,
		baseHeight = 8,
		bases = table.freeze({
			Angel = table.freeze({ x = 0, z = -360, safeZone = "JungleAngelCamp", radius = 40 } :: Base),
			Devil = table.freeze({ x = 0, z = 360, safeZone = "JungleDevilCamp", radius = 40 } :: Base),
		}),
		terrain = "Jungle",
		atmosphere = "Jungle",
		camps = table.freeze({
			-- The plaza around the waterfall pool: contested ground.
			table.freeze({ enemy = "Thorncrawler", x = 10, z = -50, count = 2 }),
			table.freeze({ enemy = "JungleProwler", x = 10, z = 50, count = 3 }),
			-- The jungle floor between the camps and the river.
			table.freeze({ enemy = "JungleProwler", x = 200, z = -90, count = 3 }),
			table.freeze({ enemy = "JungleProwler", x = -200, z = 200, count = 3 }),
			table.freeze({ enemy = "Thorncrawler", x = 300, z = 100, count = 2 }),
			table.freeze({ enemy = "Thorncrawler", x = -120, z = -200, count = 2 }),
			table.freeze({ enemy = "MossbackGolem", x = 320, z = -200, count = 1 }),
			table.freeze({ enemy = "MossbackGolem", x = 120, z = 170, count = 1 }),
			-- Up on the highland above the falls.
			table.freeze({ enemy = "JungleProwler", x = -250, z = -60, count = 3 }),
			table.freeze({ enemy = "MossbackGolem", x = -280, z = 70, count = 1 }),
		}),
	} :: WarZone),
})

-- The war zone containing world point {x, z} (ignores height), or nil.
function WorldLayout.warZoneAt(x: number, z: number): WarZone?
	for _, zone in WorldLayout.WarZones :: { [string]: WarZone } do
		local half = zone.size / 2
		if math.abs(x - zone.center[1]) <= half and math.abs(z - zone.center[3]) <= half then
			return zone
		end
	end
	return nil
end

-- World position {x, y, z} of a point given relative to a war zone's centre.
function WorldLayout.zonePoint(zone: WarZone, relative: Vec): { number }
	return { zone.center[1] + relative[1], zone.center[2] + relative[2], zone.center[3] + relative[3] }
end

--[[
	World position {x, y, z} in `race`'s base: `towardCentre` studs from the
	base centre toward the zone centre (negative = away), `side` studs to the
	side. On the camp plateau. nil if the zone has no base for that race.
]]
function WorldLayout.basePoint(zone: WarZone, race: string, towardCentre: number, side: number): { number }?
	local base = zone.bases[race]
	if base == nil then
		return nil
	end
	local length = math.sqrt(base.x * base.x + base.z * base.z)
	local ix, iz = if length > 0 then -base.x / length else 0, if length > 0 then -base.z / length else 1
	-- Side direction: inward rotated 90 degrees.
	local sx, sz = -iz, ix
	return {
		zone.center[1] + base.x + ix * towardCentre + sx * side,
		zone.center[2] + zone.baseHeight,
		zone.center[3] + base.z + iz * towardCentre + sz * side,
	}
end

--------------------------------------------------------------------------------
-- Dungeon instance slots (Phase 9; ARCHITECTURE.md §2: reserved, spatially
-- isolated regions far from the main world, ≥ 2,000 studs apart; above
-- ground so nothing falls below Workspace.FallenPartsDestroyHeight).
--------------------------------------------------------------------------------

WorldLayout.DungeonSlots = table.freeze({
	origin = table.freeze({ 8000, 600, 0 }),
	spacing = 2500,
	maxSlots = 12,
	-- Anything with x beyond this is inside a dungeon slot.
	regionMinX = 7000,
})

-- Origin {x, y, z} of dungeon slot `index` (1-based).
function WorldLayout.dungeonSlotOrigin(index: number): { number }
	local slots = WorldLayout.DungeonSlots
	return { slots.origin[1] + (index - 1) * slots.spacing, slots.origin[2], slots.origin[3] }
end

function WorldLayout.isInDungeonRegion(x: number): boolean
	return x >= WorldLayout.DungeonSlots.regionMinX
end

function WorldLayout.realmFor(race: string): Realm?
	return (WorldLayout.Realms :: any)[race]
end

return table.freeze(WorldLayout)
