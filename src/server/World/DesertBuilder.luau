--!strict
--[[
	DesertBuilder — builds the Desert Rift war zone (Phase 12; CLAUDE.md §13:
	large desert, rock formations, dunes, an oasis in the centre with water,
	vegetation and structures).

	  Terrain   smooth Roblox Terrain voxels from Logic/DesertTerrain: rippled
	            dunes, stepped mesas and hoodoos banded with rock strata, a
	            grassy oasis and its pool (free, streams well, far smoother
	            than parts)
	  Rocks     voxel cap rocks on the hoodoos, natural stone arches and
	            boulders (Terrain fills: no parts; D-83)
	  Plants    cacti and dry scrub across the dunes, reeds and lily pads in
	            the pool, a second ring of palms (decor parts; D-83)
	  Ruins     three half-buried ruin sites out in the dunes and a wooden
	            pier on the pool (storytelling; D-83)
	  Oasis     contested PvP ground: sandstone arches around the pool, palm
	            trees, a market of tents and braziers
	  Camps     each realm's base at opposite edges (Angels north, Devils
	            south): tents in the realm's colours, banners, the "Return
	            Home" portal and a shimmering ring (the server keeps the other
	            realm out)
	  Creature camps  tents and a fire at each creature camp (storytelling)
	  Bounds    invisible walls just inside the rim cliffs

	Returns each realm's return portal surface so PvPService can wire them up.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local DesertTerrain = require(Shared.Logic.DesertTerrain)
local WarZoneTerrain = require(Shared.Logic.WarZoneTerrain)
local WorldLayout = require(Shared.Definitions.WorldLayout)
local Architecture = require(script.Parent.Architecture)
local TerrainWriter = require(script.Parent.TerrainWriter)
local WarZoneKit = require(script.Parent.WarZoneKit)
local Flora = require(script.Parent.Flora)

local DesertBuilder = {}

local A = Architecture

local SANDSTONE = Color3.fromRGB(214, 176, 124)
local SANDSTONE_DARK = Color3.fromRGB(170, 132, 88)
local GOLD = Color3.fromRGB(226, 182, 86)
local CLOTH_COLORS = {
	Color3.fromRGB(176, 52, 46),
	Color3.fromRGB(46, 108, 150),
	Color3.fromRGB(214, 170, 64),
	Color3.fromRGB(110, 70, 140),
}

local STYLE: Architecture.Style = {
	race = "Desert",
	stone = SANDSTONE,
	stoneMaterial = Enum.Material.Sandstone,
	stoneDark = SANDSTONE_DARK,
	trim = GOLD,
	trimMaterial = Enum.Material.Metal,
	roof = SANDSTONE_DARK,
	roofMaterial = Enum.Material.Sandstone,
	glow = Color3.fromRGB(110, 220, 255),
	window = Color3.fromRGB(110, 220, 255),
	cloth = Color3.fromRGB(176, 52, 46),
	light = Color3.fromRGB(255, 200, 130),
	towerTop = "spire",
}

local MATERIALS: { [string]: Enum.Material } = {
	Sand = Enum.Material.Sand,
	Sandstone = Enum.Material.Sandstone,
	Rock = Enum.Material.Rock,
	Grass = Enum.Material.Grass,
	LeafyGrass = Enum.Material.LeafyGrass,
	Ground = Enum.Material.Ground,
	Limestone = Enum.Material.Limestone,
}

local WOOD = Color3.fromRGB(116, 84, 54)

-- Ground height (world Y) at a point relative to the zone centre.
local function groundY(zone: WorldLayout.WarZone, x: number, z: number): number
	return WarZoneTerrain.groundY(zone, zone.center[1] + x, zone.center[3] + z)
end

--------------------------------------------------------------------------------
-- Props
--------------------------------------------------------------------------------

local function tent(parent: Instance, cf: CFrame, width: number, depth: number, color: Color3)
	local height = width * 0.55
	for _, side in { -1, 1 } do
		A.wedge(
			parent,
			Vector3.new(depth, height, width / 2),
			cf
				* CFrame.new(0, height / 2, side * width / 4)
				* CFrame.Angles(0, if side < 0 then 0 else math.pi, 0),
			color,
			Enum.Material.Fabric
		)
	end
	-- Poles and a rug in front.
	for _, x in { -depth / 2, depth / 2 } do
		A.cylinder(
			parent,
			0.18,
			height + 1,
			cf * CFrame.new(x, 0, 0),
			Color3.fromRGB(110, 80, 50),
			Enum.Material.Wood,
			{ decor = true }
		)
	end
	A.part(
		parent,
		Vector3.new(depth * 0.8, 0.12, width * 0.5),
		cf * CFrame.new(0, 0.06, width * 0.75),
		color:Lerp(GOLD, 0.35),
		Enum.Material.Fabric,
		{ decor = true }
	)
end

local function brazier(parent: Instance, cf: CFrame)
	A.cylinder(parent, 1.1, 3.6, cf, SANDSTONE_DARK, Enum.Material.Sandstone)
	A.cylinder(parent, 1.9, 0.8, cf * CFrame.new(0, 3.6, 0), GOLD, Enum.Material.Metal)
	local flame = A.part(
		parent,
		Vector3.new(2.2, 1.2, 2.2),
		cf * CFrame.new(0, 4.8, 0),
		Color3.fromRGB(255, 150, 60),
		Enum.Material.Neon,
		{ decor = true, shape = Enum.PartType.Ball }
	)
	local fire = Instance.new("Fire")
	fire.Size = 4
	fire.Heat = 6
	fire.Parent = flame
	local light = Instance.new("PointLight")
	light.Color = STYLE.light
	light.Range = 20
	light.Brightness = 1.4
	light.Shadows = false
	light.Parent = flame
end

local function brokenColumn(parent: Instance, cf: CFrame, height: number)
	A.part(
		parent,
		Vector3.new(4.4, 1.4, 4.4),
		cf * CFrame.new(0, 0.7, 0),
		SANDSTONE_DARK,
		Enum.Material.Sandstone
	)
	A.cylinder(parent, 1.5, height, cf * CFrame.new(0, 1.4, 0), SANDSTONE, Enum.Material.Sandstone)
	A.part(
		parent,
		Vector3.new(3.6, 1.2, 3.2),
		cf * CFrame.new(0.8, 0.6, 3.2) * CFrame.Angles(0.3, 0.6, 0.2),
		SANDSTONE,
		Enum.Material.Sandstone
	)
end

local function oasis(model: Model, zone: WorldLayout.WarZone)
	local c = zone.center
	local centre = CFrame.new(c[1], c[2], c[3])
	-- Stone walkway ring around the pool and an outer ring of arches.
	A.ring(model, DesertTerrain.POOL_RADIUS + 5, 6, 0.4, 40, centre, SANDSTONE, Enum.Material.Sandstone)
	A.ring(
		model,
		DesertTerrain.POOL_RADIUS + 8,
		0.6,
		0.5,
		40,
		centre,
		GOLD,
		Enum.Material.Metal,
		{ decor = true }
	)
	local arches = 8
	for i = 0, arches - 1 do
		local a = (i + 0.5) / arches * math.pi * 2
		local r = DesertTerrain.PLAZA_RADIUS - 6
		local p = Vector3.new(c[1] + math.sin(a) * r, c[2], c[3] + math.cos(a) * r)
		if i % 2 == 0 then
			A.arch(model, CFrame.lookAt(p, Vector3.new(c[1], c[2], c[3])), 12, 20, 3, 2.4, STYLE)
		else
			brokenColumn(model, CFrame.new(p) * CFrame.Angles(0, a, 0), 9 + (i % 3) * 3)
		end
	end
	-- Palms between the pool and the arches.
	for i = 0, 15 do
		local a = i / 16 * math.pi * 2 + 0.2
		local r = DesertTerrain.POOL_RADIUS + 12 + (i % 3) * 5
		local x, z = math.sin(a) * r, math.cos(a) * r
		if math.abs(x) < 10 and (z > 20 or z < -30) then
			continue -- keep the arrival point and the portal path clear
		end
		Flora.palm(model, CFrame.new(c[1] + x, groundY(zone, x, z) - 0.5, c[3] + z), 16 + (i % 4) * 3, i)
	end
	-- A little island with a rift crystal in the pool.
	A.cylinder(model, 5, 3, centre * CFrame.new(0, -4, 0), SANDSTONE_DARK, Enum.Material.Sandstone)
	A.crystals(model, centre * CFrame.new(0, -1, 0), 10, STYLE.glow)
	-- Market tents along the north side.
	for i, x in { -26, -12, 12, 26 } do
		local z = -(DesertTerrain.PLAZA_RADIUS - 18)
		tent(
			model,
			CFrame.new(c[1] + x, c[2], c[3] + z) * CFrame.Angles(0, math.pi, 0),
			8,
			7,
			CLOTH_COLORS[i]
		)
	end
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2
		local r = DesertTerrain.PLAZA_RADIUS - 14
		brazier(model, CFrame.new(c[1] + math.sin(a) * r, c[2], c[3] + math.cos(a) * r))
	end
end

local function camps(model: Model, zone: WorldLayout.WarZone)
	local c = zone.center
	for i, camp in zone.camps do
		local x, z = camp.x + 10, camp.z + 10
		if math.sqrt(camp.x * camp.x + camp.z * camp.z) < DesertTerrain.PLAZA_RADIUS then
			continue -- oasis creatures need no tents
		end
		local y = groundY(zone, x, z)
		tent(
			model,
			CFrame.new(c[1] + x, y - 0.3, c[3] + z) * CFrame.Angles(0, i, 0),
			9,
			8,
			CLOTH_COLORS[i % #CLOTH_COLORS + 1]:Lerp(Color3.fromRGB(60, 50, 40), 0.4)
		)
		local fireY = groundY(zone, camp.x - 6, camp.z + 4)
		brazier(model, CFrame.new(c[1] + camp.x - 6, fireY - 1.5, c[3] + camp.z + 4))
		brokenColumn(
			model,
			CFrame.new(c[1] + camp.x + 14, groundY(zone, camp.x + 14, camp.z - 8) - 0.5, c[3] + camp.z - 8),
			6 + i
		)
	end
end

--------------------------------------------------------------------------------
-- Rock formations, plants and ruins (Phase 16 stage 2, D-83)
--------------------------------------------------------------------------------

-- Voxel cap rocks on the hoodoos and the natural arches: a heightmap can't
-- hold an overhang, so these are filled straight into Terrain.
local function rockFormations(zone: WorldLayout.WarZone)
	local terrain = Workspace.Terrain
	local c = zone.center
	for i, h in DesertTerrain.HOODOOS do
		local top = groundY(zone, h[1], h[2])
		local r = h[3] * 0.75
		terrain:FillBlock(
			CFrame.new(c[1] + h[1], top + 1.5, c[3] + h[2]) * CFrame.Angles(0.07 * (i % 3 - 1), i, 0.05),
			Vector3.new(r * 2.3, 4, r * 1.9),
			Enum.Material.Rock
		)
	end
	for _, a in DesertTerrain.ARCHES do
		local p1 = Vector3.new(c[1] + a[1], groundY(zone, a[1], a[2]) - 3, c[3] + a[2])
		local p2 = Vector3.new(c[1] + a[3], groundY(zone, a[3], a[4]) - 3, c[3] + a[4])
		local steps = math.ceil((p2 - p1).Magnitude * 1.6 / a[6])
		for s = 0, steps do
			local t = s / steps
			local up = math.sin(t * math.pi)
			-- Thick feet, a thinner span.
			terrain:FillBall(
				p1:Lerp(p2, t) + Vector3.new(0, up * (a[5] + 3), 0),
				a[6] * (1.4 - 0.5 * up),
				Enum.Material.Sandstone
			)
		end
	end
end

-- Open dune ground away from the oasis, camps, bosses and rock formations.
local function openGround(zone: WorldLayout.WarZone, x: number, z: number): boolean
	if math.sqrt(x * x + z * z) < DesertTerrain.PLAZA_RADIUS + 25 then
		return false
	end
	if math.max(math.abs(x), math.abs(z)) > zone.size / 2 - DesertTerrain.RIM_WIDTH - 8 then
		return false
	end
	local function near(px: number, pz: number, radius: number): boolean
		return (x - px) ^ 2 + (z - pz) ^ 2 < radius * radius
	end
	for _, camp in zone.camps do
		if near(camp.x, camp.z, 22) then
			return false
		end
	end
	for _, boss in zone.bosses do
		if near(boss.x, boss.z, 40) then
			return false
		end
	end
	for _, base in DesertTerrain.BASES do
		if near(base[1], base[2], DesertTerrain.BASE_RADIUS + 15) then
			return false
		end
	end
	for _, m in DesertTerrain.MESAS do
		if near(m[1], m[2], m[3] + 12) then
			return false
		end
	end
	for _, h in DesertTerrain.HOODOOS do
		if near(h[1], h[2], h[3] + 6) then
			return false
		end
	end
	for _, a in DesertTerrain.ARCHES do
		local span = math.sqrt((a[3] - a[1]) ^ 2 + (a[4] - a[2]) ^ 2)
		if near((a[1] + a[3]) / 2, (a[2] + a[4]) / 2, span / 2 + 8) then
			return false
		end
	end
	for _, r in DesertTerrain.RUINS do
		if near(r[1], r[2], 24) then
			return false
		end
	end
	return true
end

-- Cacti, dry scrub and terrain boulders scattered over the dunes.
local function scatter(model: Model, zone: WorldLayout.WarZone)
	local c = zone.center
	local rng = Random.new(83)
	local plants = Instance.new("Model")
	plants.Name = "DunePlants"
	local placed = { cactus = 0, shrub = 0, boulder = 0 }
	local want = { cactus = 70, shrub = 80, boulder = 40 }
	local half = zone.size / 2
	for _ = 1, 2000 do
		if placed.cactus >= want.cactus and placed.shrub >= want.shrub and placed.boulder >= want.boulder then
			break
		end
		local x, z = rng:NextNumber(-half, half), rng:NextNumber(-half, half)
		if not openGround(zone, x, z) then
			continue
		end
		local y = groundY(zone, x, z)
		local roll = rng:NextNumber()
		local seed = rng:NextInteger(1, 1000000)
		if roll < 0.37 and placed.cactus < want.cactus then
			placed.cactus += 1
			Flora.cactus(plants, CFrame.new(c[1] + x, y - 0.6, c[3] + z), rng:NextNumber(8, 15), seed)
		elseif roll < 0.8 and placed.shrub < want.shrub then
			placed.shrub += 1
			Flora.dryShrub(plants, CFrame.new(c[1] + x, y - 0.3, c[3] + z), rng:NextNumber(2, 4), seed)
		elseif placed.boulder < want.boulder then
			placed.boulder += 1
			local r = rng:NextNumber(2, 4)
			Workspace.Terrain:FillBall(Vector3.new(c[1] + x, y - r * 0.35, c[3] + z), r, Enum.Material.Rock)
		end
	end
	plants.Parent = model
end

-- The oasis's greenery and pier: reeds at the water's edge, lily pads, an
-- outer ring of palms on the first dunes.
local function oasisLife(model: Model, zone: WorldLayout.WarZone)
	local c = zone.center
	local water = c[2] + DesertTerrain.WATER_LEVEL
	for i = 0, 23 do
		local a = i / 24 * math.pi * 2 + 0.13
		local r = DesertTerrain.POOL_RADIUS - 2 + (i % 3)
		local x, z = math.sin(a) * r, math.cos(a) * r
		if x > 20 and math.abs(z) < 8 then
			continue -- the pier
		end
		Flora.reeds(model, CFrame.new(c[1] + x, groundY(zone, x, z) - 0.3, c[3] + z), 5 + (i % 4), i + 400)
	end
	for i = 0, 13 do
		local a = i / 14 * math.pi * 2 + 0.5
		local r = 12 + (i * 7) % 15
		Flora.lilyPad(
			model,
			CFrame.new(c[1] + math.sin(a) * r, water + 0.08, c[3] + math.cos(a) * r),
			2.4 + (i % 3) * 0.6,
			i + 500
		)
	end
	for i = 0, 9 do
		local a = i / 10 * math.pi * 2 + 0.31
		local r = DesertTerrain.PLAZA_RADIUS + 8 + (i % 3) * 6
		local x, z = math.sin(a) * r, math.cos(a) * r
		if math.abs(x) < 16 then
			continue -- the paths to the camps
		end
		Flora.palm(
			model,
			CFrame.new(c[1] + x, groundY(zone, x, z) - 0.5, c[3] + z),
			18 + (i % 3) * 4,
			i + 600
		)
	end
	-- A wooden pier out over the water on the east side.
	local pier = CFrame.new(c[1] + DesertTerrain.POOL_RADIUS - 4, water + 1, c[3])
	A.part(model, Vector3.new(12, 0.5, 5), pier, WOOD, Enum.Material.WoodPlanks)
	for _, px in { -5, 0, 5 } do
		for _, pz in { -2.2, 2.2 } do
			A.cylinder(
				model,
				0.3,
				3,
				pier * CFrame.new(px, -2.75, pz),
				WOOD:Lerp(Color3.new(0, 0, 0), 0.2),
				Enum.Material.Wood,
				{
					decor = true,
				}
			)
		end
	end
end

-- A half-buried ruin: a fallen obelisk, broken columns and loose blocks.
local function ruin(model: Model, zone: WorldLayout.WarZone, x: number, z: number, seed: number)
	local c = zone.center
	local rng = Random.new(seed)
	local y = groundY(zone, x, z)
	local at = CFrame.new(c[1] + x, y, c[3] + z) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	A.part(
		model,
		Vector3.new(3.4, 3.4, 22),
		at * CFrame.new(0, 0.6, 0) * CFrame.Angles(math.rad(8), 0, math.rad(4)),
		SANDSTONE,
		Enum.Material.Sandstone
	)
	A.wedge(
		model,
		Vector3.new(3.4, 3, 3.4),
		at * CFrame.new(0, 2.1, -12.6) * CFrame.Angles(math.rad(-82), 0, 0),
		GOLD,
		Enum.Material.Metal
	)
	for i = 0, 2 do
		local a = i / 3 * math.pi * 2 + 0.4
		local p = at * CFrame.new(math.sin(a) * 10, 0, math.cos(a) * 9 + 4)
		local lx, lz = p.Position.X - c[1], p.Position.Z - c[3]
		brokenColumn(
			model,
			CFrame.new(p.Position.X, groundY(zone, lx, lz) - 1, p.Position.Z) * p.Rotation,
			rng:NextInteger(4, 10)
		)
	end
	for i = 1, 4 do
		local s = rng:NextNumber(2, 3.5)
		A.part(
			model,
			Vector3.new(s * 1.4, s, s),
			at
				* CFrame.new(rng:NextNumber(-9, 9), s * 0.25, rng:NextNumber(-8, 12))
				* CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 3), rng:NextNumber(-0.3, 0.3)),
			if i % 2 == 0 then SANDSTONE else SANDSTONE_DARK,
			Enum.Material.Sandstone
		)
	end
	-- A low stretch of wall.
	A.part(
		model,
		Vector3.new(14, 4, 2.4),
		at * CFrame.new(0, 1, 13) * CFrame.Angles(0, 0.2, 0),
		SANDSTONE_DARK,
		Enum.Material.Sandstone
	)
end

export type Built = { portals: { [string]: BasePart }, parts: number }

function DesertBuilder.build(root: Instance, zone: WorldLayout.WarZone): Built
	TerrainWriter.write(zone, MATERIALS, Enum.Material.Sandstone)
	local model = Instance.new("Model")
	model.Name = zone.id
	rockFormations(zone)
	oasis(model, zone)
	oasisLife(model, zone)
	scatter(model, zone)
	for i, r in DesertTerrain.RUINS do
		ruin(model, zone, r[1], r[2], 830 + i)
	end
	local portals: { [string]: BasePart } = {}
	for race in zone.bases do
		local portal = WarZoneKit.camp(model, zone, race, function(parent, cf, index, style)
			tent(parent, cf, 9, 8, if index % 2 == 0 then style.cloth else style.trim:Lerp(style.stone, 0.4))
		end)
		if portal then
			portals[race] = portal
		end
	end
	camps(model, zone)
	WarZoneKit.bounds(model, zone, DesertTerrain.RIM_WIDTH)
	model.Parent = root
	local parts = 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
		end
	end
	return { portals = portals, parts = parts }
end

return DesertBuilder
