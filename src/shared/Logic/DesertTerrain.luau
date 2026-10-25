--!strict
--[[
	DesertTerrain — the Desert Rift's heightmap and materials (Phase 12).

	Pure: the server's DesertBuilder writes Roblox Terrain voxels from it, and
	tests / preview tools can sample it offline. Coordinates are relative to
	the zone centre (studs); heights are relative to the oasis plaza surface
	(0 = plaza level, negative = below).

	Shape:
	  oasis   flat grassy plaza ring around a sunken pool
	  dunes   rolling ridged sand dunes that rise away from the oasis
	  mesas   a few tall sandstone rock formations with stepped ledges
	  hoodoos thin rock spires in loose groups (the builder adds cap rocks)
	  arches  natural stone arches (the builder fills them as voxels: a
	          heightmap can't hold an overhang)
	  strata  rock bands by height on every cliff, mesa and spire face
	  rim     sandstone cliffs along the edge (a natural boundary)

	math.noise is deterministic, so every server builds the same desert.
]]

local DesertTerrain = {}

DesertTerrain.PLAZA_RADIUS = 66
DesertTerrain.POOL_RADIUS = 34
DesertTerrain.POOL_DEPTH = 9
-- Water surface relative to the plaza.
DesertTerrain.WATER_LEVEL = -2.5
DesertTerrain.RIM_WIDTH = 70
DesertTerrain.RIM_HEIGHT = 70
DesertTerrain.SEED = 17.31

export type Material = "Sand" | "Sandstone" | "Rock" | "Grass" | "LeafyGrass" | "Ground" | "Limestone"

-- Camp plateaus (WorldLayout.WarZones.DesertRift.bases): {x, z} and their
-- flat radius / height above the plaza.
DesertTerrain.BASES = table.freeze({ table.freeze({ 0, -360 }), table.freeze({ 0, 360 }) })
DesertTerrain.BASE_RADIUS = 52
DesertTerrain.BASE_HEIGHT = 6

-- Rock formations (mesas): {x, z, radius, height}.
DesertTerrain.MESAS = table.freeze({
	table.freeze({ 150, -40, 26, 42 }),
	table.freeze({ -130, 60, 22, 36 }),
	table.freeze({ -60, -190, 30, 50 }),
	table.freeze({ 220, 210, 24, 38 }),
	table.freeze({ -280, -280, 34, 56 }),
	table.freeze({ 300, -300, 28, 44 }),
})

-- Hoodoos (D-83): {x, z, radius, height}; clear of camps, bosses, paths.
DesertTerrain.HOODOOS = table.freeze({
	table.freeze({ 98, 193, 9, 37 }),
	table.freeze({ 192, 338, 7, 31 }),
	table.freeze({ -275, -103, 10, 30 }),
	table.freeze({ -289, 94, 7, 24 }),
	table.freeze({ -149, -241, 10, 34 }),
	table.freeze({ -236, 353, 9, 38 }),
	table.freeze({ 254, 69, 9, 35 }),
	table.freeze({ -130, -152, 9, 31 }),
	table.freeze({ -259, -195, 10, 35 }),
	table.freeze({ -114, -77, 9, 30 }),
	table.freeze({ 354, -124, 8, 32 }),
	table.freeze({ -179, 162, 7, 34 }),
})

-- Natural arches (D-83): {x1, z1, x2, z2, height, thickness}; the two feet
-- and the span's top above the ground at the midpoint.
DesertTerrain.ARCHES = table.freeze({
	table.freeze({ 72, 241, 78, 281, 22, 5 }),
	table.freeze({ 300, -79, 334, -59, 22, 5 }),
	table.freeze({ 279, 361, 285, 401, 27, 5 }),
})

-- Half-buried ruin sites (D-83, built from parts): {x, z}.
DesertTerrain.RUINS = table.freeze({
	table.freeze({ -330, 120 }),
	table.freeze({ 140, -330 }),
	table.freeze({ 330, 150 }),
})

-- Ledge height on the mesas and the thickness of one rock band (studs).
DesertTerrain.LEDGE_STEP = 9
DesertTerrain.STRATA_STEP = 5
local STRATA: { Material } = { "Sandstone", "Limestone", "Sandstone", "Rock", "Sandstone", "Ground" }

local function smoothstep(e0: number, e1: number, x: number): number
	local t = math.clamp((x - e0) / (e1 - e0), 0, 1)
	return t * t * (3 - 2 * t)
end

local function ridged(x: number, z: number, scale: number): number
	local n = math.noise(x / scale, z / scale, DesertTerrain.SEED)
	return 1 - math.abs(n) * 2 -- 1 on ridges, lower in troughs
end

-- Flat ledges with short steep risers: a stepped butte instead of a cone.
local function terrace(height: number, step: number): number
	local s = math.floor(height / step)
	local f = height / step - s
	return (s + smoothstep(0.55, 1, f)) * step
end

--[[
	Rock band at height y (relative to the plaza) under (x, z): the voxel
	writer uses it for buried rock, which is what every steep face shows.
	The bands tilt and wobble gently so they don't read as ruled lines.
]]
function DesertTerrain.strataShift(x: number, z: number): number
	return 2.2 * math.noise(x / 70, z / 70, DesertTerrain.SEED + 19) + (x + z) * 0.012
end

-- The band at height y for a column's strataShift (one noise per column).
function DesertTerrain.band(y: number, shift: number): Material
	local band = math.floor((y + shift) / DesertTerrain.STRATA_STEP) % #STRATA
	return STRATA[band + 1]
end

function DesertTerrain.strata(x: number, y: number, z: number): Material
	return DesertTerrain.band(y, DesertTerrain.strataShift(x, z))
end

--[[
	Surface height (studs, relative to the plaza) and material at (x, z)
	relative to the zone centre, for a zone of `size` studs square.
]]
function DesertTerrain.sample(x: number, z: number, size: number): (number, Material)
	local r = math.sqrt(x * x + z * z)

	-- Dunes: long ridges plus smaller ripples, growing away from the oasis.
	local dunes = 9 * math.max(0, ridged(x, z, 140)) + 4 * math.noise(x / 55, z / 55, DesertTerrain.SEED + 3)
	local fromOasis = smoothstep(DesertTerrain.PLAZA_RADIUS, DesertTerrain.PLAZA_RADIUS + 90, r)
	-- Wind ripples across the open sand, running one way like real dunes.
	local ripple = 0.8
		* math.sin((x * 0.83 + z * 0.55) / 4.5 + 2 * math.noise(x / 40, z / 40, DesertTerrain.SEED + 23))
	local open = smoothstep(DesertTerrain.PLAZA_RADIUS + 60, DesertTerrain.PLAZA_RADIUS + 140, r)
	local height = dunes * fromOasis + 3 * fromOasis + ripple * open

	-- Sunken pool in the middle of the plaza.
	if r < DesertTerrain.POOL_RADIUS + 6 then
		local dip = 1 - smoothstep(DesertTerrain.POOL_RADIUS - 8, DesertTerrain.POOL_RADIUS + 6, r)
		height -= DesertTerrain.POOL_DEPTH * dip
	end

	-- Mesas: steep-sided sandstone formations with flat tops.
	local material: Material = "Sand"
	for _, mesa in DesertTerrain.MESAS do
		local dx, dz = x - mesa[1], z - mesa[2]
		local d = math.sqrt(dx * dx + dz * dz)
		-- Ragged outline: broad bays and spurs, then small rough edges.
		local wobble = mesa[3] * 0.3 * math.noise(dx / 40, dz / 40, DesertTerrain.SEED + 31)
			+ 3 * math.noise(dx / 14, dz / 14, DesertTerrain.SEED + 7)
		-- A sheer cap cliff over a sloping talus that steps down in ledges.
		local cliff = 1 - smoothstep(mesa[3] - 4 + wobble, mesa[3] + 2 + wobble, d)
		local talus = 1 - smoothstep(mesa[3] - 4 + wobble, mesa[3] + 24 + wobble, d)
		local lift = 0.6 * cliff + 0.4 * talus
		if lift > 0.02 then
			height = math.max(height, terrace(mesa[4] * lift, DesertTerrain.LEDGE_STEP))
			if cliff > 0.5 then
				material = if (mesa[1] + mesa[2]) % 2 == 0 then "Sandstone" else "Rock"
			elseif d > mesa[3] then
				material = "Ground" -- scree fallen around the foot
			end
		end
	end

	-- Hoodoos: narrow spires with steep sides.
	for _, h in DesertTerrain.HOODOOS do
		local dx, dz = x - h[1], z - h[2]
		local d = math.sqrt(dx * dx + dz * dz)
		local edge = h[3] + 1.5 * math.noise(dx / 6, dz / 6, DesertTerrain.SEED + 29)
		if d < edge + 8 then
			local lift = 1 - smoothstep(edge * 0.55, edge, d)
			height = math.max(height, h[4] * lift ^ 0.6)
			if lift > 0.4 then
				material = "Sandstone"
			elseif d < edge + 6 then
				material = "Ground"
			end
		end
	end

	-- Rim cliffs along the zone edge.
	local edge = size / 2 - math.max(math.abs(x), math.abs(z))
	if edge < DesertTerrain.RIM_WIDTH then
		local rise = 1 - smoothstep(0, DesertTerrain.RIM_WIDTH, edge)
		local rough = 6 * math.noise(x / 30, z / 30, DesertTerrain.SEED + 11)
		height = math.max(height, (DesertTerrain.RIM_HEIGHT + rough) * rise)
		if rise > 0.35 then
			material = "Sandstone"
		end
	end

	-- Camp plateaus: flat ground for each realm's base, blending into the dunes.
	for _, base in DesertTerrain.BASES do
		local dx, dz = x - base[1], z - base[2]
		local d = math.sqrt(dx * dx + dz * dz)
		local flat = 1 - smoothstep(DesertTerrain.BASE_RADIUS, DesertTerrain.BASE_RADIUS + 30, d)
		if flat > 0 then
			height = height + (DesertTerrain.BASE_HEIGHT - height) * flat
			if flat > 0.95 then
				material = "Sandstone"
			end
		end
	end

	-- The oasis: grass around the pool, damp ground at the water's edge.
	if r < DesertTerrain.PLAZA_RADIUS + 10 and material == "Sand" then
		if r < DesertTerrain.POOL_RADIUS + 2 then
			material = "Ground"
		elseif r < DesertTerrain.PLAZA_RADIUS - 6 then
			material = if math.noise(x / 9, z / 9, DesertTerrain.SEED + 5) > 0 then "LeafyGrass" else "Grass"
		end
	end
	return height, material
end

return table.freeze(DesertTerrain)
