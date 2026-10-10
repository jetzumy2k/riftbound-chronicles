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
		platformSize = { 220, 6, 220 },
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
		platformSize = { 220, 6, 220 },
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
		volume = { kind = "cylinder", center = { 0, 150, -600 }, radius = 90, halfHeight = 60 },
	} :: SafeZone),
	table.freeze({
		id = "DevilCapital",
		race = "Devil",
		displayName = "Emberdeep Bastion",
		volume = { kind = "cylinder", center = { 0, 20, 600 }, radius = 90, halfHeight = 60 },
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

function WorldLayout.realmFor(race: string): Realm?
	return (WorldLayout.Realms :: any)[race]
end

return table.freeze(WorldLayout)
