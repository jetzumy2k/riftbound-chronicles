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

function WorldLayout.realmFor(race: string): Realm?
	return (WorldLayout.Realms :: any)[race]
end

return table.freeze(WorldLayout)
