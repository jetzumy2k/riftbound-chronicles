--!strict
--[[
	JungleTerrain — the Jungle Rift's heightmap, water and materials
	(Phase 13; CLAUDE.md §13: dense tropical jungle, a large waterfall, a
	river, bridges and rock formations).

	Pure: the server's JungleBuilder writes Roblox Terrain voxels from it, and
	tests / preview tools can sample it offline. Coordinates are relative to
	the zone centre (studs); heights are relative to the plaza around the
	plunge pool (0 = plaza level, negative = below).

	Shape:
	  highland  a raised jungle shelf in the west, gentle slopes to the north
	            and south, ending in a sheer cliff on its east side
	  upper river  flows east across the highland from a spring at the west
	            rim and pours over the cliff: the waterfall
	  plunge pool  at the foot of the falls in the middle of the zone, ringed
	            by a flat plaza (contested PvP ground, like the Desert oasis)
	  river     leaves the pool eastward and meanders to the east rim; the
	            builder spans it with bridges (BRIDGES)
	  hills     rolling jungle ground and mossy rock outcrops elsewhere
	  rim       rock cliffs along the edge (a natural boundary)
	  strata    grey and slate rock bands with earthy seams by height on
	            the cliff, outcrop and rim faces (D-84)
	  camps     each realm's flat plateau at opposite edges (Angels north,
	            Devils south; WorldLayout.WarZones.JungleRift.bases)

	sample() also returns the water surface for each column: the upper river
	sits HIGH_WATER above the plaza, everything else at WATER_LEVEL. Ground
	outside the river and pool always stays above its water line.

	math.noise is deterministic, so every server builds the same jungle.
]]

local JungleTerrain = {}

JungleTerrain.SEED = 41.73

JungleTerrain.PLAZA_RADIUS = 64
-- Plunge pool at the foot of the falls: centre {x, z}, radius, depth.
JungleTerrain.POOL_CENTER = table.freeze({ -14, 0 })
JungleTerrain.POOL_RADIUS = 38
JungleTerrain.POOL_DEPTH = 11
-- Water surfaces relative to the plaza: the pool and lower river, and the
-- upper river on the highland.
JungleTerrain.WATER_LEVEL = -2.5
JungleTerrain.RIM_WIDTH = 70
JungleTerrain.RIM_HEIGHT = 74

-- The highland shelf: spans x from the west rim to the cliff, |z| up to
-- halfDepth (with gentle slopes beyond), `height` above the plaza.
JungleTerrain.HIGHLAND = table.freeze({ halfDepth = 120, height = 44 })
JungleTerrain.HIGH_WATER = JungleTerrain.HIGHLAND.height - 3
-- x of the cliff edge at z = 0; the upper river ends at the lip, just
-- behind it, and pours over as the waterfall.
JungleTerrain.CLIFF_X = -46
JungleTerrain.LIP_X = JungleTerrain.CLIFF_X - 3

-- Upper river: from the spring (x) to the cliff; lower river: from the pool
-- to where it sinks into the east rim. Half widths are the water's edges.
JungleTerrain.SPRING_X = -420
JungleTerrain.RIVER_END_X = 410
JungleTerrain.UPPER_HALF_WIDTH = 11
JungleTerrain.LOWER_HALF_WIDTH = 14
JungleTerrain.RIVER_DEPTH = 7

-- Camp plateaus (WorldLayout.WarZones.JungleRift.bases).
JungleTerrain.BASES = table.freeze({ table.freeze({ 0, -360 }), table.freeze({ 0, 360 }) })
JungleTerrain.BASE_RADIUS = 52
JungleTerrain.BASE_HEIGHT = 8

-- Mossy rock outcrops (cover between the camps and the river): {x, z, radius, height}.
JungleTerrain.OUTCROPS = table.freeze({
	table.freeze({ 170, -150, 24, 30 }),
	table.freeze({ -150, 230, 26, 34 }),
	table.freeze({ 250, 190, 22, 28 }),
	table.freeze({ -300, -250, 30, 40 }),
	table.freeze({ 330, -300, 26, 36 }),
	table.freeze({ 90, 250, 18, 22 }),
})

-- Bridges over the river: x along the river; `upper` bridges cross the
-- highland stretch. Kind is the builder's style.
export type Bridge = { x: number, upper: boolean, kind: "Stone" | "Rope" }
JungleTerrain.BRIDGES = table.freeze({
	table.freeze({ x = 52, upper = false, kind = "Stone" } :: Bridge),
	table.freeze({ x = 160, upper = false, kind = "Rope" } :: Bridge),
	table.freeze({ x = 300, upper = false, kind = "Rope" } :: Bridge),
	table.freeze({ x = -150, upper = true, kind = "Stone" } :: Bridge),
	table.freeze({ x = -330, upper = true, kind = "Rope" } :: Bridge),
})

export type Material = "Grass" | "LeafyGrass" | "Ground" | "Mud" | "Rock" | "Slate" | "Pebble"

-- Rock bands on every steep face (D-84): band thickness and order.
JungleTerrain.STRATA_STEP = 6
local STRATA: { Material } = { "Rock", "Slate", "Rock", "Ground", "Slate", "Rock" }

local function smoothstep(e0: number, e1: number, x: number): number
	local t = math.clamp((x - e0) / (e1 - e0), 0, 1)
	return t * t * (3 - 2 * t)
end

-- Rock band shift for the column at (x, z) (one noise per column) and the
-- band at height y (relative to the plaza) for that shift.
function JungleTerrain.strataShift(x: number, z: number): number
	return 2.5 * math.noise(x / 60, z / 60, JungleTerrain.SEED + 19) - (x - z) * 0.01
end

function JungleTerrain.band(y: number, shift: number): Material
	local band = math.floor((y + shift) / JungleTerrain.STRATA_STEP) % #STRATA
	return STRATA[band + 1]
end

-- x of the cliff edge at depth z: a shallow amphitheatre around the falls,
-- straight right at the lip so the waterfall sheet is flat.
function JungleTerrain.cliffX(z: number): number
	local bow = z * z / 450
	local wobble = 6 * math.noise(z / 38, JungleTerrain.SEED, 3) * smoothstep(22, 45, math.abs(z))
	return JungleTerrain.CLIFF_X - bow + wobble
end

--[[
	The river at x: centre z, half width of the water and whether this is the
	upper (highland) stretch. nil where there is no river (the pool and
	beyond the ends).
]]
function JungleTerrain.riverAt(x: number): (number?, number, boolean)
	if x >= JungleTerrain.SPRING_X and x <= JungleTerrain.LIP_X then
		-- Gentle meander that lines up with the lip (z = 0 at the cliff).
		local t = x - JungleTerrain.CLIFF_X
		return 16 * math.sin(t / 70), JungleTerrain.UPPER_HALF_WIDTH, true
	end
	local poolEdge = JungleTerrain.POOL_CENTER[1] + JungleTerrain.POOL_RADIUS - 6
	if x >= poolEdge and x <= JungleTerrain.RIVER_END_X then
		local t = x - poolEdge
		local widen = smoothstep(0, 300, t) * 4
		return 24 * math.sin(t / 85), JungleTerrain.LOWER_HALF_WIDTH + widen, false
	end
	return nil, 0, false
end

-- Height of the highland shelf at (x, z), before the river is carved.
local function highland(x: number, z: number): (number, number)
	local h = JungleTerrain.HIGHLAND
	local sides = 1 - smoothstep(h.halfDepth * 0.75, h.halfDepth * 1.3, math.abs(z))
	local edge = JungleTerrain.cliffX(z)
	local front = 1 - smoothstep(edge - 3, edge + 4, x)
	local lift = sides * front
	local rough = 2.5 * math.noise(x / 40, z / 40, JungleTerrain.SEED + 9)
	return (h.height + rough * lift) * lift, lift
end

--[[
	Surface height (studs, relative to the plaza), material and water surface
	(relative, or nil for none) at (x, z) relative to the zone centre, for a
	zone of `size` studs square.
]]
function JungleTerrain.sample(x: number, z: number, size: number): (number, Material, number?)
	local r = math.sqrt(x * x + z * z)
	local material: Material = "Grass"

	-- Rolling jungle hills that grow away from the plaza.
	local fromPlaza = smoothstep(JungleTerrain.PLAZA_RADIUS, JungleTerrain.PLAZA_RADIUS + 80, r)
	local hills = 10 * (math.noise(x / 130, z / 130, JungleTerrain.SEED) + 0.45)
		+ 3.5 * math.noise(x / 45, z / 45, JungleTerrain.SEED + 2)
	local height = math.max(0, hills) * fromPlaza

	-- The highland shelf and its cliff.
	local shelf, lift = highland(x, z)
	if shelf > height then
		height = shelf
		if lift > 0.08 and lift < 0.92 and x > JungleTerrain.cliffX(z) - 8 then
			material = if math.noise(x / 8, z / 8, JungleTerrain.SEED + 4) > 0 then "Rock" else "Slate"
		elseif lift >= 0.92 then
			material = "LeafyGrass"
		end
	end

	-- Rock outcrops: rounded, mossy on top.
	for _, rock in JungleTerrain.OUTCROPS do
		local dx, dz = x - rock[1], z - rock[2]
		local d = math.sqrt(dx * dx + dz * dz)
		local wobble = 3 * math.noise(dx / 12, dz / 12, JungleTerrain.SEED + 7)
		local rise = 1 - smoothstep(rock[3] * 0.5 + wobble, rock[3] + 8 + wobble, d)
		if rise > 0.03 then
			local top = height + rock[4] * math.sqrt(rise)
			if top > height then
				height = top
				material = if rise > 0.75 then "LeafyGrass" elseif rise > 0.2 then "Rock" else material
			end
		end
	end

	-- Rim cliffs along the zone edge.
	local edge = size / 2 - math.max(math.abs(x), math.abs(z))
	if edge < JungleTerrain.RIM_WIDTH then
		local rise = 1 - smoothstep(0, JungleTerrain.RIM_WIDTH, edge)
		local rough = 7 * math.noise(x / 30, z / 30, JungleTerrain.SEED + 11)
		local rim = (JungleTerrain.RIM_HEIGHT + rough) * rise
		if rim > height then
			height = rim
			if rise > 0.3 then
				material = if rise > 0.85 then "LeafyGrass" else "Rock"
			end
		end
	end

	-- Camp plateaus: flat ground for each realm's base.
	for _, base in JungleTerrain.BASES do
		local dx, dz = x - base[1], z - base[2]
		local d = math.sqrt(dx * dx + dz * dz)
		local flat = 1 - smoothstep(JungleTerrain.BASE_RADIUS, JungleTerrain.BASE_RADIUS + 30, d)
		if flat > 0 then
			height = height + (JungleTerrain.BASE_HEIGHT - height) * flat
			if flat > 0.95 then
				material = "Ground"
			end
		end
	end

	-- Rivers: a channel with muddy banks, water at the stretch's level.
	local water = JungleTerrain.WATER_LEVEL
	local riverZ, halfWidth, upper = JungleTerrain.riverAt(x)
	if riverZ then
		local level = if upper then JungleTerrain.HIGH_WATER else JungleTerrain.WATER_LEVEL
		local d = math.abs(z - riverZ)
		-- Fade the channel in at the spring and out where it sinks into the rim.
		local fade = if upper
			then smoothstep(JungleTerrain.SPRING_X, JungleTerrain.SPRING_X + 30, x)
			else 1 - smoothstep(JungleTerrain.RIVER_END_X - 40, JungleTerrain.RIVER_END_X, x)
		local cut = (1 - smoothstep(halfWidth - 3, halfWidth + 5, d)) * fade
		if cut > 0 then
			local bed = level - JungleTerrain.RIVER_DEPTH
			height = height + (math.min(height, bed) - height) * cut
			if d < halfWidth + 1 then
				material = if d < halfWidth - 3 then "Pebble" else "Mud"
			end
		end
		if upper and d < halfWidth + 6 and x <= JungleTerrain.cliffX(z) - 3 then
			water = level
		end
		if d < halfWidth + 6 and material ~= "Pebble" then
			material = "Mud"
		end
	end

	-- Plunge pool at the foot of the falls, cut into the cliff base.
	local pdx, pdz = x - JungleTerrain.POOL_CENTER[1], z - JungleTerrain.POOL_CENTER[2]
	local pr = math.sqrt(pdx * pdx + pdz * pdz)
	if pr < JungleTerrain.POOL_RADIUS + 6 then
		local dip = 1 - smoothstep(JungleTerrain.POOL_RADIUS - 10, JungleTerrain.POOL_RADIUS + 6, pr)
		-- The shelf itself stays: its cliff drops straight into the water.
		local onShelf = x < JungleTerrain.cliffX(z) - 3 and math.abs(z) < JungleTerrain.HIGHLAND.halfDepth
		if not onShelf then
			height = height + (math.min(height, -JungleTerrain.POOL_DEPTH) - height) * dip
		end
		if pr < JungleTerrain.POOL_RADIUS + 2 and not onShelf then
			material = if pr < JungleTerrain.POOL_RADIUS - 6 then "Pebble" else "Rock"
		end
	end

	-- Plaza ground: damp jungle floor with grass patches.
	if material == "Grass" then
		local n = math.noise(x / 14, z / 14, JungleTerrain.SEED + 5)
		material = if n > 0.25 then "LeafyGrass" elseif n < -0.35 then "Ground" else "Grass"
	end
	return height, material, water
end

return table.freeze(JungleTerrain)
