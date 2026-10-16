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
}

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

export type Built = { portals: { [string]: BasePart }, parts: number }

function DesertBuilder.build(root: Instance, zone: WorldLayout.WarZone): Built
	TerrainWriter.write(zone, MATERIALS, Enum.Material.Sandstone)
	local model = Instance.new("Model")
	model.Name = zone.id
	oasis(model, zone)
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
