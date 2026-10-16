--!strict
--[[
	DesertBuilder — builds the Desert Rift war zone (Phase 12; CLAUDE.md §13:
	large desert, rock formations, dunes, an oasis in the centre with water,
	vegetation and structures).

	  Terrain   smooth Roblox Terrain voxels from Logic/DesertTerrain: dunes,
	            sandstone mesas, rock, a grassy oasis and its pool (free,
	            streams well, far smoother than parts)
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
local WorldLayout = require(Shared.Definitions.WorldLayout)
local Architecture = require(script.Parent.Architecture)

local DesertBuilder = {}

local A = Architecture
local VOXEL = 4
local CHUNK = 32 -- columns per side per WriteVoxels call

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
}

--------------------------------------------------------------------------------
-- Terrain
--------------------------------------------------------------------------------

local function writeTerrain(zone: WorldLayout.WarZone)
	local terrain = Workspace.Terrain
	local c = zone.center
	local half = zone.size / 2
	local x0 = math.floor((c[1] - half) / VOXEL) * VOXEL
	local z0 = math.floor((c[3] - half) / VOXEL) * VOXEL
	local columns = math.ceil(zone.size / VOXEL)
	local yBottom = math.floor((c[2] - DesertTerrain.POOL_DEPTH - 12) / VOXEL) * VOXEL
	local yTop = math.ceil((c[2] + DesertTerrain.RIM_HEIGHT + 16) / VOXEL) * VOXEL
	local layers = (yTop - yBottom) // VOXEL
	local water = c[2] + DesertTerrain.WATER_LEVEL

	for ci = 0, columns - 1, CHUNK do
		for ck = 0, columns - 1, CHUNK do
			local nx = math.min(CHUNK, columns - ci)
			local nz = math.min(CHUNK, columns - ck)
			local materials = table.create(nx)
			local occupancy = table.create(nx)
			for i = 1, nx do
				local mi = table.create(layers)
				local oi = table.create(layers)
				for j = 1, layers do
					mi[j] = table.create(nz, Enum.Material.Air)
					oi[j] = table.create(nz, 0)
				end
				materials[i] = mi
				occupancy[i] = oi
				local wx = x0 + (ci + i - 0.5) * VOXEL
				for k = 1, nz do
					local wz = z0 + (ck + k - 0.5) * VOXEL
					local height, materialName = DesertTerrain.sample(wx - c[1], wz - c[3], zone.size)
					local surface = c[2] + height
					local top = MATERIALS[materialName]
					for j = 1, layers do
						local yb = yBottom + (j - 1) * VOXEL
						local fill = math.clamp((surface - yb) / VOXEL, 0, 1)
						if fill > 0 then
							oi[j][k] = fill
							-- Sand over sandstone bedrock.
							mi[j][k] = if surface - yb < VOXEL * 2.5 then top else Enum.Material.Sandstone
						elseif yb < water then
							oi[j][k] = math.clamp((water - yb) / VOXEL, 0, 1)
							mi[j][k] = Enum.Material.Water
						end
					end
				end
			end
			local region = Region3.new(
				Vector3.new(x0 + ci * VOXEL, yBottom, z0 + ck * VOXEL),
				Vector3.new(x0 + (ci + nx) * VOXEL, yBottom + layers * VOXEL, z0 + (ck + nz) * VOXEL)
			)
			terrain:WriteVoxels(region, VOXEL, materials, occupancy)
		end
	end
end

-- Ground height (world Y) at a point relative to the zone centre.
local function groundY(zone: WorldLayout.WarZone, x: number, z: number): number
	local height = DesertTerrain.sample(x, z, zone.size)
	return zone.center[2] + height
end

--------------------------------------------------------------------------------
-- Props
--------------------------------------------------------------------------------

local function palm(parent: Instance, base: CFrame, height: number, seed: number)
	local rng = Random.new(seed)
	local lean = math.rad(rng:NextNumber(6, 16))
	local turn = rng:NextNumber(0, math.pi * 2)
	local segments = 6
	local cf = base * CFrame.Angles(0, turn, 0)
	local trunk = Color3.fromRGB(122, 92, 60)
	for i = 0, segments - 1 do
		local length = height / segments
		cf = cf * CFrame.Angles(lean / segments * 1.6, 0, 0)
		local radius = 0.9 - i * 0.08
		A.cylinder(
			parent,
			radius,
			length + 0.3,
			cf,
			if i % 2 == 0 then trunk else trunk:Lerp(Color3.new(0, 0, 0), 0.15),
			Enum.Material.Wood,
			{ decor = i > 0 }
		)
		cf = cf * CFrame.new(0, length, 0)
	end
	local frond = Color3.fromRGB(64, 132, 54)
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local leaf = A.part(
			parent,
			Vector3.new(1.4, 0.25, 9),
			cf
				* CFrame.Angles(0, a, 0)
				* CFrame.Angles(math.rad(-28 - rng:NextNumber(0, 18)), 0, 0)
				* CFrame.new(0, 0, -4.2),
			frond:Lerp(Color3.fromRGB(150, 170, 60), rng:NextNumber(0, 0.4)),
			Enum.Material.Grass,
			{ decor = true }
		)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = leaf
	end
	for i = 0, 2 do
		local a = i / 3 * math.pi * 2
		A.part(
			parent,
			Vector3.new(0.8, 0.8, 0.8),
			cf * CFrame.Angles(0, a, 0) * CFrame.new(0, -0.6, -0.7),
			Color3.fromRGB(96, 70, 40),
			Enum.Material.Wood,
			{ decor = true, shape = Enum.PartType.Ball }
		)
	end
end

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
		palm(model, CFrame.new(c[1] + x, groundY(zone, x, z) - 0.5, c[3] + z), 16 + (i % 4) * 3, i)
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

-- A realm's base: plateau camp, return portal and the realm-only barrier.
local function base(model: Model, zone: WorldLayout.WarZone, race: string): BasePart?
	local def = zone.bases[race]
	local style = (Architecture.Styles :: any)[race] :: Architecture.Style
	local centre = WorldLayout.basePoint(zone, race, 0, 0)
	local inward = WorldLayout.basePoint(zone, race, 10, 0)
	if def == nil or style == nil or centre == nil or inward == nil then
		return nil
	end
	local camp = Instance.new("Model")
	camp.Name = `{race}Camp`
	local c = Vector3.new(centre[1], centre[2], centre[3])
	local facing = CFrame.lookAt(c, Vector3.new(inward[1], centre[2], inward[3]))
	-- Paved floor with the realm's trim ring.
	A.disc(camp, def.radius - 2, 0.4, facing, style.stone, style.stoneMaterial, { decor = true })
	A.ring(camp, def.radius - 4, 1, 0.5, 40, facing, style.trim, style.trimMaterial, { decor = true })
	-- Return portal at the back, facing the desert.
	local portal =
		A.portalGate(camp, facing * CFrame.new(0, 0, def.radius - 14) * CFrame.Angles(0, math.pi, 0), {
			label = "Return Home",
			opensIn = "",
			active = true,
		}, style)
	-- Tents and banners along both sides, braziers / lamps at the entrance.
	for i, side in { -1, 1, -1, 1 } do
		local back = if i <= 2 then 6 else 20
		tent(
			camp,
			facing * CFrame.new(side * 22, 0, back) * CFrame.Angles(0, side * math.pi / 2, 0),
			9,
			8,
			if i % 2 == 0 then style.cloth else style.trim:Lerp(style.stone, 0.4)
		)
	end
	for _, side in { -1, 1 } do
		A.cylinder(camp, 0.35, 16, facing * CFrame.new(side * 14, 0, -16), style.trim, style.trimMaterial)
		A.banner(camp, facing * CFrame.new(side * 14, 15, -16), 5, 10, style)
		A.lamp(camp, facing * CFrame.new(side * 9, 0, -def.radius + 8), style)
	end
	-- Barrier ring: a shimmering marker only. Nothing collides with it; the
	-- server keeps the other realm out (PvPService), so nobody can ever be
	-- trapped inside their own camp.
	local segments = 32
	local radius = def.radius + 1
	local chord = 2 * radius * math.sin(math.pi / segments) + 0.2
	for i = 0, segments - 1 do
		local a = (i + 0.5) / segments * math.pi * 2
		local wall = Instance.new("Part")
		wall.Name = "RealmBarrier"
		wall.Anchored = true
		wall.Size = Vector3.new(chord, 16, 1)
		wall.CFrame = CFrame.new(c) * CFrame.Angles(0, -a, 0) * CFrame.new(0, 8, -radius)
		wall.Material = Enum.Material.ForceField
		wall.Color = style.glow
		wall.Transparency = 0.55
		wall.CastShadow = false
		wall.CanCollide = false
		wall.CanQuery = false
		wall.CanTouch = false
		wall.Parent = camp
	end
	camp.Parent = model
	return portal
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

local function bounds(model: Model, zone: WorldLayout.WarZone)
	local c = zone.center
	local inner = zone.size / 2 - DesertTerrain.RIM_WIDTH * 0.45
	for _, spec in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
		local wall = A.part(
			model,
			Vector3.new(if spec[1] ~= 0 then 4 else inner * 2, 400, if spec[2] ~= 0 then 4 else inner * 2),
			CFrame.new(c[1] + spec[1] * inner, c[2] + 150, c[3] + spec[2] * inner),
			Color3.new(1, 1, 1),
			Enum.Material.SmoothPlastic,
			{ transparency = 1, shadow = false }
		)
		wall.Name = "Boundary"
		wall.CanQuery = false
	end
end

export type Built = { portals: { [string]: BasePart }, parts: number }

function DesertBuilder.build(root: Instance, zone: WorldLayout.WarZone): Built
	writeTerrain(zone)
	local model = Instance.new("Model")
	model.Name = zone.id
	oasis(model, zone)
	local portals: { [string]: BasePart } = {}
	for race in zone.bases do
		local portal = base(model, zone, race)
		if portal then
			portals[race] = portal
		end
	end
	camps(model, zone)
	bounds(model, zone)
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
