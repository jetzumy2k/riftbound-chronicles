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
	  mesas   a few tall sandstone rock formations
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

export type Material = "Sand" | "Sandstone" | "Rock" | "Grass" | "LeafyGrass" | "Ground"

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

local function smoothstep(e0: number, e1: number, x: number): number
	local t = math.clamp((x - e0) / (e1 - e0), 0, 1)
	return t * t * (3 - 2 * t)
end

local function ridged(x: number, z: number, scale: number): number
	local n = math.noise(x / scale, z / scale, DesertTerrain.SEED)
	return 1 - math.abs(n) * 2 -- 1 on ridges, lower in troughs
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
	local height = dunes * fromOasis + 3 * fromOasis

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
		local wobble = 3 * math.noise(dx / 14, dz / 14, DesertTerrain.SEED + 7)
		local lift = 1 - smoothstep(mesa[3] - 4 + wobble, mesa[3] + 6 + wobble, d)
		if lift > 0.05 then
			height = math.max(height, mesa[4] * lift)
			if lift > 0.3 then
				material = if (mesa[1] + mesa[2]) % 2 == 0 then "Sandstone" else "Rock"
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
