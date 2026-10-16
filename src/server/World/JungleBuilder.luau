--!strict
--[[
	JungleBuilder — builds the Jungle Rift war zone (Phase 13; CLAUDE.md §13:
	dense tropical jungle, a large waterfall, a river, bridges and rock
	formations; PLAN.md D-43).

	  Terrain    smooth Roblox Terrain voxels from Logic/JungleTerrain: the
	             highland shelf and its cliff, the upper and lower river, the
	             plunge pool, hills, mossy outcrops and rim cliffs
	  Waterfall  the upper river pours over the cliff into the pool: layered
	             translucent sheets, white streaks, a curling lip, falling
	             spray and mist (two particle emitters), foam and boulders; a
	             small cascade feeds the river from a spring at the west rim
	  Plaza      contested PvP ground around the pool: a flagstone walk,
	             mossy ruins and arches, braziers, a rift crystal on an islet
	             and lily pads
	  Bridges    stone and rope bridges over the river (JungleTerrain.BRIDGES)
	  Forest     a seeded grid of rainforest trees and palms, ferns and bushes,
	             vines down the cliff; kept off the water, paths, camps and
	             steep ground
	  Camps      each realm's base (WarZoneKit) with stilt huts
	  Creature camps  overgrown shrines (storytelling)
	  Bounds     invisible walls just inside the rim cliffs

	Returns each realm's return portal surface so PvPService can wire them up.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local JungleTerrain = require(Shared.Logic.JungleTerrain)
local WarZoneTerrain = require(Shared.Logic.WarZoneTerrain)
local WorldLayout = require(Shared.Definitions.WorldLayout)
local Architecture = require(script.Parent.Architecture)
local TerrainWriter = require(script.Parent.TerrainWriter)
local WarZoneKit = require(script.Parent.WarZoneKit)
local Flora = require(script.Parent.Flora)

local JungleBuilder = {}

local A = Architecture
local T = JungleTerrain

local MOSS_STONE = Color3.fromRGB(122, 128, 112)
local MOSS_STONE_DARK = Color3.fromRGB(86, 94, 82)
local MOSS = Color3.fromRGB(92, 128, 64)
local WOOD = Color3.fromRGB(112, 84, 58)
local ROPE = Color3.fromRGB(176, 150, 104)
local WATER_DEEP = Color3.fromRGB(96, 156, 190)
local WATER_LIGHT = Color3.fromRGB(206, 236, 248)
local FOAM = Color3.fromRGB(240, 248, 252)
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

local STYLE: Architecture.Style = {
	race = "Jungle",
	stone = MOSS_STONE,
	stoneMaterial = Enum.Material.Cobblestone,
	stoneDark = MOSS_STONE_DARK,
	trim = MOSS,
	trimMaterial = Enum.Material.Grass,
	roof = MOSS_STONE_DARK,
	roofMaterial = Enum.Material.Slate,
	glow = Color3.fromRGB(120, 255, 200),
	window = Color3.fromRGB(120, 255, 200),
	cloth = Color3.fromRGB(40, 120, 90),
	light = Color3.fromRGB(255, 196, 120),
	towerTop = "spire",
}

local MATERIALS: { [string]: Enum.Material } = {
	Grass = Enum.Material.Grass,
	LeafyGrass = Enum.Material.LeafyGrass,
	Ground = Enum.Material.Ground,
	Mud = Enum.Material.Mud,
	Rock = Enum.Material.Rock,
	Slate = Enum.Material.Slate,
	Pebble = Enum.Material.Pebble,
}

-- World position of a point relative to the zone centre; y relative to the plaza.
local function at(zone: WorldLayout.WarZone, x: number, y: number, z: number): Vector3
	local c = zone.center
	return Vector3.new(c[1] + x, c[2] + y, c[3] + z)
end

-- Ground height relative to the plaza at (x, z) relative to the zone centre.
local function ground(zone: WorldLayout.WarZone, x: number, z: number): number
	return (WarZoneTerrain.sample(zone, x, z))
end

local function brazier(parent: Instance, cf: CFrame)
	A.cylinder(parent, 1.1, 3.6, cf, MOSS_STONE_DARK, Enum.Material.Cobblestone)
	A.cylinder(parent, 1.8, 0.8, cf * CFrame.new(0, 3.6, 0), MOSS_STONE, Enum.Material.Cobblestone)
	local flame = A.part(
		parent,
		Vector3.new(2, 1.1, 2),
		cf * CFrame.new(0, 4.7, 0),
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
	light.Brightness = 1.3
	light.Shadows = false
	light.Parent = flame
end

local function brokenColumn(parent: Instance, cf: CFrame, height: number, seed: number)
	local rng = Random.new(seed)
	A.part(
		parent,
		Vector3.new(4.4, 1.4, 4.4),
		cf * CFrame.new(0, 0.7, 0),
		MOSS_STONE_DARK,
		Enum.Material.Cobblestone
	)
	A.cylinder(parent, 1.5, height, cf * CFrame.new(0, 1.4, 0), MOSS_STONE, Enum.Material.Cobblestone)
	-- Moss cap and a fallen drum beside it.
	A.cylinder(
		parent,
		1.6,
		0.5,
		cf * CFrame.new(0, 1.4 + height, 0),
		MOSS,
		Enum.Material.Grass,
		{ decor = true }
	)
	A.part(
		parent,
		Vector3.new(3.6, 1.2, 3.2),
		cf * CFrame.new(rng:NextNumber(-1, 1), 0.6, 3.2) * CFrame.Angles(0.3, rng:NextNumber(0, 3), 0.2),
		MOSS_STONE,
		Enum.Material.Cobblestone
	)
	Flora.vine(parent, (cf * CFrame.new(1.4, height + 1, 0)).Position, height * 0.6, seed)
end

local function boulder(parent: Instance, position: Vector3, size: number, seed: number)
	local rng = Random.new(seed)
	local rock = A.part(
		parent,
		Vector3.new(size, size * rng:NextNumber(0.55, 0.8), size * rng:NextNumber(0.8, 1.1)),
		CFrame.new(position)
			* CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 3), rng:NextNumber(-0.3, 0.3)),
		MOSS_STONE_DARK:Lerp(MOSS_STONE, rng:NextNumber()),
		Enum.Material.Slate
	)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = rock
	-- Sphere-meshed parts keep box collision: let players walk over smoothly.
	rock.CanCollide = false
end

--------------------------------------------------------------------------------
-- Waterfall
--------------------------------------------------------------------------------

local function emitter(parent: BasePart, props: { [string]: any })
	local e = Instance.new("ParticleEmitter")
	e.Texture = SMOKE_TEXTURE
	e.LightInfluence = 1
	for key, value in props do
		(e :: any)[key] = value
	end
	e.Parent = parent
end

-- A translucent sheet of falling water from `top` to `bottom` (world).
local function sheet(parent: Instance, top: Vector3, bottom: Vector3, width: number, rng: Random)
	local mid = (top + bottom) / 2
	local length = (top - bottom).Magnitude
	-- Leans with the cliff: local +Y runs from bottom to top.
	local up = (top - bottom).Unit
	local across = Vector3.new(0, 0, 1)
	local out = up:Cross(across).Unit
	local frame = CFrame.fromMatrix(mid, out, up)
	A.part(parent, Vector3.new(1.4, length, width), frame, WATER_DEEP, Enum.Material.Glass, {
		decor = true,
		transparency = 0.25,
	})
	A.part(
		parent,
		Vector3.new(0.4, length, width * 0.9),
		frame * CFrame.new(0.9, 0, 0),
		WATER_LIGHT,
		Enum.Material.Glass,
		{
			decor = true,
			transparency = 0.55,
		}
	)
	-- White streaks down the face.
	for i = 1, math.floor(width / 3) do
		local z = rng:NextNumber(-width / 2 + 1, width / 2 - 1)
		local streak = rng:NextNumber(0.5, 0.75) * length
		A.part(
			parent,
			Vector3.new(0.3, streak, rng:NextNumber(0.5, 1.4)),
			frame * CFrame.new(1.2, length / 2 - streak / 2 - rng:NextNumber(0, length - streak), z),
			FOAM,
			Enum.Material.SmoothPlastic,
			{ decor = true, transparency = 0.3 + (i % 3) * 0.1 }
		)
	end
end

local function waterfall(model: Model, zone: WorldLayout.WarZone)
	local falls = Instance.new("Model")
	falls.Name = "Waterfall"
	local rng = Random.new(1301)
	local width = T.UPPER_HALF_WIDTH * 2 - 2
	local top = at(zone, T.LIP_X + 1, T.HIGH_WATER + 0.4, 0)
	local bottom = at(zone, T.CLIFF_X + 8, T.WATER_LEVEL - 0.5, 0)
	sheet(falls, top, bottom, width, rng)
	-- The lip: water curling over the edge.
	A.part(
		falls,
		Vector3.new(width, 2.4, 2.4),
		CFrame.new(top) * CFrame.Angles(0, math.pi / 2, 0),
		WATER_LIGHT,
		Enum.Material.Glass,
		{ decor = true, transparency = 0.3, shape = Enum.PartType.Cylinder }
	)
	-- Falling spray from the lip.
	local spray = A.part(
		falls,
		Vector3.new(2, 1, width),
		CFrame.new(top + Vector3.new(1.5, 0, 0)),
		FOAM,
		Enum.Material.SmoothPlastic,
		{
			decor = true,
			transparency = 1,
		}
	)
	emitter(spray, {
		Rate = 30,
		Lifetime = NumberRange.new(1.4, 1.8),
		Speed = NumberRange.new(4, 7),
		EmissionDirection = Enum.NormalId.Bottom,
		Acceleration = Vector3.new(4, -26, 0),
		SpreadAngle = Vector2.new(6, 6),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 4.5) }),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.45),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Color = ColorSequence.new(WATER_LIGHT),
	})
	-- Mist and foam where it lands.
	local base = bottom + Vector3.new(3, 1, 0)
	local mist =
		A.part(falls, Vector3.new(10, 1, width + 6), CFrame.new(base), FOAM, Enum.Material.SmoothPlastic, {
			decor = true,
			transparency = 1,
		})
	emitter(mist, {
		Rate = 16,
		Lifetime = NumberRange.new(2.5, 3.5),
		Speed = NumberRange.new(3, 7),
		EmissionDirection = Enum.NormalId.Top,
		Acceleration = Vector3.new(3, 1.5, 0),
		SpreadAngle = Vector2.new(50, 50),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 6), NumberSequenceKeypoint.new(1, 16) }),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.55),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Color = ColorSequence.new(FOAM),
	})
	for i = 0, 4 do
		local z = (i - 2) * width / 4 + rng:NextNumber(-2, 2)
		local p =
			Vector3.new(base.X + rng:NextNumber(-2, 5), zone.center[2] + T.WATER_LEVEL + 0.1, base.Z + z)
		local blob = A.part(
			falls,
			Vector3.new(rng:NextNumber(7, 11), 0.6, rng:NextNumber(6, 9)),
			CFrame.new(p) * CFrame.Angles(0, rng:NextNumber(0, 3), 0),
			FOAM,
			Enum.Material.SmoothPlastic,
			{ decor = true, transparency = 0.35 }
		)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = blob
	end
	-- Boulders at both sides of the fall.
	for _, side in { -1, 1 } do
		for k = 0, 1 do
			local z = side * (width / 2 + 4 + k * 6)
			boulder(
				falls,
				at(zone, T.CLIFF_X + 6 + k * 5, T.WATER_LEVEL + 0.5, z),
				8 - k * 2,
				40 + side * 3 + k
			)
		end
	end
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(180, 230, 255)
	glow.Range = 30
	glow.Brightness = 0.6
	glow.Shadows = false
	glow.Parent = mist

	-- The spring at the west rim that feeds the upper river.
	local springZ = T.riverAt(T.SPRING_X + 2) or 0
	local springTop = at(zone, T.SPRING_X - 8, T.HIGH_WATER + 9, springZ)
	local springBottom = at(zone, T.SPRING_X - 4, T.HIGH_WATER - 0.5, springZ)
	sheet(falls, springTop, springBottom, 8, rng)
	for k = 0, 4 do
		local a = (k - 2) * 0.55
		boulder(
			falls,
			at(
				zone,
				T.SPRING_X - 12 + math.abs(k - 2) * 3,
				T.HIGH_WATER + 4 + (2 - math.abs(k - 2)) * 5,
				springZ + math.sin(a) * 10
			),
			10 - math.abs(k - 2),
			70 + k
		)
	end
	falls.Parent = model
end

-- Vines down the cliff face on both sides of the falls.
local function cliffVines(model: Model, zone: WorldLayout.WarZone)
	local folder = Instance.new("Model")
	folder.Name = "CliffVines"
	local rng = Random.new(1302)
	for z = -T.HIGHLAND.halfDepth * 0.8, T.HIGHLAND.halfDepth * 0.8, 5 do
		if math.abs(z) < T.UPPER_HALF_WIDTH + 4 or rng:NextNumber() < 0.3 then
			continue
		end
		local x = T.cliffX(z) + 1
		local length = rng:NextNumber(10, 26)
		Flora.vine(folder, at(zone, x, ground(zone, x - 4, z) - 0.5, z), length, rng:NextInteger(1, 1e6))
	end
	folder.Parent = model
end

--------------------------------------------------------------------------------
-- Plaza
--------------------------------------------------------------------------------

-- True when (x, z) is in or right beside the river.
local function nearRiver(x: number, z: number, margin: number): boolean
	local riverZ, halfWidth = T.riverAt(x)
	return riverZ ~= nil and math.abs(z - riverZ) < halfWidth + margin
end

local function nearCliff(x: number, z: number, margin: number): boolean
	return math.abs(z) < T.HIGHLAND.halfDepth * 1.3 and x < T.cliffX(z) + margin and x > T.cliffX(z) - 14
end

local function plaza(model: Model, zone: WorldLayout.WarZone)
	local plazaModel = Instance.new("Model")
	plazaModel.Name = "Plaza"
	local rng = Random.new(1303)
	local pc = T.POOL_CENTER
	-- Flagstone walk around the pool (not under the falls or across the river).
	local segments = 36
	local r = T.POOL_RADIUS + 5
	local chord = 2 * r * math.sin(math.pi / segments) + 0.3
	for i = 0, segments - 1 do
		local a = (i + 0.5) / segments * math.pi * 2
		local x, z = pc[1] + math.cos(a) * r, pc[2] + math.sin(a) * r
		if nearCliff(x, z, 6) or nearRiver(x, z, 3) then
			continue
		end
		local y = ground(zone, x, z)
		A.part(
			plazaModel,
			Vector3.new(5, 0.5, chord),
			CFrame.new(at(zone, x, y + 0.15, z)) * CFrame.Angles(0, -a, 0),
			if i % 2 == 0 then MOSS_STONE else MOSS_STONE_DARK,
			Enum.Material.Cobblestone
		)
	end
	-- Ruins: broken columns and two standing arches around the plaza.
	local ruins = 10
	for i = 0, ruins - 1 do
		local a = (i + 0.25) / ruins * math.pi * 2
		local rr = T.PLAZA_RADIUS - 6
		local x, z = pc[1] + math.cos(a) * rr, pc[2] + math.sin(a) * rr
		if nearCliff(x, z, 8) or nearRiver(x, z, 6) then
			continue
		end
		local p = at(zone, x, ground(zone, x, z), z)
		if i % 3 == 0 then
			local centre = at(zone, pc[1], p.Y - zone.center[2], pc[2])
			A.arch(plazaModel, CFrame.lookAt(p, centre), 11, 18, 3, 2.2, STYLE)
		else
			brokenColumn(plazaModel, CFrame.new(p) * CFrame.Angles(0, a, 0), 7 + (i % 4) * 3, 200 + i)
		end
	end
	for i = 0, 5 do
		local a = (i + 0.5) / 6 * math.pi * 2
		local rr = T.POOL_RADIUS + 11
		local x, z = pc[1] + math.cos(a) * rr, pc[2] + math.sin(a) * rr
		if nearCliff(x, z, 6) or nearRiver(x, z, 4) then
			continue
		end
		brazier(plazaModel, CFrame.new(at(zone, x, ground(zone, x, z), z)))
	end
	-- A rift crystal on a mossy islet, east of the falls.
	local islet = at(zone, pc[1] + 12, T.WATER_LEVEL, pc[2] - 10)
	A.cylinder(
		plazaModel,
		5,
		4,
		CFrame.new(islet - Vector3.new(0, 3, 0)),
		MOSS_STONE_DARK,
		Enum.Material.Slate
	)
	A.cylinder(
		plazaModel,
		5.2,
		0.5,
		CFrame.new(islet + Vector3.new(0, 1, 0)),
		MOSS,
		Enum.Material.Grass,
		{ decor = true }
	)
	A.crystals(plazaModel, CFrame.new(islet + Vector3.new(0, 1.2, 0)), 9, STYLE.glow)
	-- Lily pads on the pool and along the lower river's banks.
	for i = 1, 16 do
		local a = rng:NextNumber(-math.pi * 0.6, math.pi * 0.6)
		local rr = rng:NextNumber(T.POOL_RADIUS * 0.45, T.POOL_RADIUS - 5)
		Flora.lilyPad(
			plazaModel,
			CFrame.new(at(zone, pc[1] + math.cos(a) * rr, T.WATER_LEVEL + 0.08, pc[2] + math.sin(a) * rr)),
			rng:NextNumber(2.5, 4.5),
			300 + i
		)
	end
	for i = 1, 22 do
		local x = rng:NextNumber(T.POOL_CENTER[1] + T.POOL_RADIUS + 10, T.RIVER_END_X - 50)
		local riverZ, halfWidth = T.riverAt(x)
		if riverZ then
			local side = if rng:NextNumber() < 0.5 then -1 else 1
			local z = riverZ + side * (halfWidth - rng:NextNumber(2, 5))
			Flora.lilyPad(
				plazaModel,
				CFrame.new(at(zone, x, T.WATER_LEVEL + 0.08, z)),
				rng:NextNumber(2.5, 4),
				400 + i
			)
		end
	end
	plazaModel.Parent = model
end

--------------------------------------------------------------------------------
-- Bridges
--------------------------------------------------------------------------------

-- Ramp from the ground up to a bridge end; `outward` points away from the river.
local function ramp(
	parent: Instance,
	endPoint: Vector3,
	outward: Vector3,
	groundY: number,
	width: number,
	color: Color3,
	material: Enum.Material
)
	local rise = endPoint.Y - groundY + 0.4
	if rise < 0.8 then
		return
	end
	local length = rise * 2.4
	local centre = Vector3.new(endPoint.X, groundY - 0.4 + rise / 2, endPoint.Z)
		+ outward * (length / 2 - 0.2)
	-- A wedge's tall side is its back (+Z): face it toward the bridge.
	A.wedge(
		parent,
		Vector3.new(width, rise, length),
		CFrame.lookAt(centre, centre + outward),
		color,
		material
	)
end

local function bridge(model: Model, zone: WorldLayout.WarZone, spec: JungleTerrain.Bridge, index: number)
	local riverZ, halfWidth, upper = T.riverAt(spec.x)
	if riverZ == nil then
		return
	end
	local b = Instance.new("Model")
	b.Name = `Bridge{index}`
	local rng = Random.new(500 + index)
	local level = if upper then T.HIGH_WATER else T.WATER_LEVEL
	-- Across the river: perpendicular to its flow at this point.
	local ahead = T.riverAt(spec.x + 1) or riverZ
	local flow = Vector3.new(1, 0, ahead - riverZ).Unit
	local across = Vector3.new(-flow.Z, 0, flow.X)
	local half = halfWidth + 7
	local centre = Vector3.new(spec.x, 0, riverZ)
	local ends = { centre + across * half, centre - across * half }
	local endHeights = {}
	for k, e in ends do
		endHeights[k] = math.max(ground(zone, e.X, e.Z), level + 2.2) + 0.4
	end
	local function world(p: Vector3, y: number): Vector3
		return at(zone, p.X, y, p.Z)
	end

	if spec.kind == "Stone" then
		local deckY = math.max(endHeights[1], endHeights[2], level + 3) + 0.6
		local length = half * 2 + 2
		local mid = world(centre, deckY - 0.7)
		local frame = CFrame.lookAt(mid, mid + across)
		A.part(b, Vector3.new(9, 1.4, length), frame, MOSS_STONE, Enum.Material.Cobblestone)
		for _, side in { -1, 1 } do
			A.part(
				b,
				Vector3.new(0.9, 2.4, length),
				frame * CFrame.new(side * 4.6, 1.9, 0),
				MOSS_STONE_DARK,
				Enum.Material.Cobblestone
			)
			-- Piers standing in the water.
			local pier = frame * CFrame.new(0, 0, side * (halfWidth - 3))
			local bed = level - JungleTerrain.RIVER_DEPTH - 1
			A.part(
				b,
				Vector3.new(7, deckY - bed, 3),
				CFrame.new(pier.Position.X, zone.center[2] + (deckY + bed) / 2 - 0.7, pier.Position.Z)
					* pier.Rotation,
				MOSS_STONE_DARK,
				Enum.Material.Cobblestone
			)
			Flora.vine(
				b,
				(frame * CFrame.new(side * 4.6, 0.7, rng:NextNumber(-4, 4))).Position,
				rng:NextNumber(3, 6),
				index * 10 + side
			)
		end
		for _, e in ends do
			local outward = (e - centre).Unit
			ramp(
				b,
				world(e, deckY),
				outward,
				zone.center[2] + ground(zone, e.X, e.Z),
				9,
				MOSS_STONE,
				Enum.Material.Cobblestone
			)
		end
	else
		-- Rope bridge: sagging planks between two pairs of posts.
		local span = half * 2
		local planks = math.ceil(span / 1.9)
		local sag = 1.6
		local function deckAt(t: number): Vector3
			local p = ends[1]:Lerp(ends[2], t)
			local y = endHeights[1] + (endHeights[2] - endHeights[1]) * t - sag * 4 * t * (1 - t)
			return world(p, y)
		end
		for i = 0, planks - 1 do
			local t0, t1 = i / planks, (i + 1) / planks
			local p0, p1 = deckAt(t0), deckAt(t1)
			local mid = (p0 + p1) / 2
			A.part(
				b,
				Vector3.new(7, 0.35, (p1 - p0).Magnitude - 0.15),
				CFrame.lookAt(mid, p1) * CFrame.Angles(0, 0, rng:NextNumber(-0.02, 0.02)),
				WOOD:Lerp(Color3.new(0, 0, 0), rng:NextNumber(0, 0.2)),
				Enum.Material.WoodPlanks
			)
		end
		-- Hand ropes, one segment per three planks, and the posts.
		for _, side in { -1, 1 } do
			local offset = flow * side * 3.6
			local steps = math.ceil(planks / 3)
			for i = 0, steps - 1 do
				local p0 = deckAt(i / steps) + offset + Vector3.new(0, 3, 0)
				local p1 = deckAt((i + 1) / steps) + offset + Vector3.new(0, 3, 0)
				A.part(
					b,
					Vector3.new(0.22, 0.22, (p1 - p0).Magnitude + 0.1),
					CFrame.lookAt((p0 + p1) / 2, p1),
					ROPE,
					Enum.Material.Fabric,
					{ decor = true }
				)
			end
			for k = 1, 2 do
				local top = deckAt(k - 1) + offset
				A.cylinder(b, 0.45, 5, CFrame.new(top - Vector3.new(0, 1.6, 0)), WOOD, Enum.Material.Wood)
			end
		end
		for k, e in ends do
			local outward = (e - centre).Unit
			ramp(
				b,
				deckAt(k - 1),
				outward,
				zone.center[2] + ground(zone, e.X, e.Z),
				7,
				WOOD,
				Enum.Material.WoodPlanks
			)
		end
	end
	b.Parent = model
end

--------------------------------------------------------------------------------
-- Forest
--------------------------------------------------------------------------------

local function steep(zone: WorldLayout.WarZone, x: number, z: number, limit: number): boolean
	local h = ground(zone, x, z)
	for _, d in { { 3, 0 }, { -3, 0 }, { 0, 3 }, { 0, -3 } } do
		if math.abs(ground(zone, x + d[1], z + d[2]) - h) > limit then
			return true
		end
	end
	return false
end

-- Whether a plant may grow at (x, z): dry, not steep, off the paths.
local function plantable(zone: WorldLayout.WarZone, x: number, z: number, clearance: number): boolean
	local height, _, water = WarZoneTerrain.sample(zone, x, z)
	if water and height < water + 1 then
		return false
	end
	local pc = T.POOL_CENTER
	if math.sqrt((x - pc[1]) ^ 2 + (z - pc[2]) ^ 2) < T.POOL_RADIUS + 8 + clearance then
		return false
	end
	if nearRiver(x, z, 4 + clearance) or nearCliff(x, z, 6) then
		return false
	end
	for _, base in zone.bases do
		if math.sqrt((x - base.x) ^ 2 + (z - base.z) ^ 2) < base.radius + 14 + clearance then
			return false
		end
	end
	for _, camp in zone.camps do
		if math.sqrt((x - camp.x) ^ 2 + (z - camp.z) ^ 2) < 14 + clearance then
			return false
		end
	end
	for _, spec in T.BRIDGES do
		local riverZ, halfWidth = T.riverAt(spec.x)
		if riverZ and math.abs(x - spec.x) < 8 + clearance and math.abs(z - riverZ) < halfWidth + 24 then
			return false
		end
	end
	return not steep(zone, x, z, 3)
end

local function forest(model: Model, zone: WorldLayout.WarZone): number
	local trees = Instance.new("Model")
	trees.Name = "Forest"
	local rng = Random.new(1304)
	local half = zone.size / 2 - 12
	local planted = 0
	-- Trees: a jittered grid; the plaza stays open for fighting.
	local spacing = 50
	for gx = -half, half, spacing do
		for gz = -half, half, spacing do
			local x = gx + rng:NextNumber(-spacing * 0.35, spacing * 0.35)
			local z = gz + rng:NextNumber(-spacing * 0.35, spacing * 0.35)
			local seed = rng:NextInteger(1, 1e6)
			local roll = rng:NextNumber()
			if roll > 0.8 or math.sqrt(x * x + z * z) < T.PLAZA_RADIUS + 6 then
				continue
			end
			if not plantable(zone, x, z, 4) then
				continue
			end
			local base = CFrame.new(at(zone, x, ground(zone, x, z) - 0.6, z))
			if roll < 0.58 then
				Flora.jungleTree(trees, base, rng:NextNumber(34, 58), seed)
			else
				Flora.palm(trees, base, rng:NextNumber(18, 28), seed)
			end
			planted += 1
		end
	end
	-- Undergrowth: ferns and bushes, also around the plaza's edge.
	local small = 32
	for gx = -half, half, small do
		for gz = -half, half, small do
			local x = gx + rng:NextNumber(-small * 0.4, small * 0.4)
			local z = gz + rng:NextNumber(-small * 0.4, small * 0.4)
			local seed = rng:NextInteger(1, 1e6)
			local roll = rng:NextNumber()
			if roll > 0.55 or math.sqrt(x * x + z * z) < T.PLAZA_RADIUS - 10 then
				continue
			end
			if not plantable(zone, x, z, 0) then
				continue
			end
			local base = CFrame.new(at(zone, x, ground(zone, x, z) - 0.2, z))
			if roll < 0.3 then
				Flora.fern(trees, base, rng:NextNumber(4, 7), seed)
			else
				Flora.bush(trees, base, rng:NextNumber(5, 9), seed)
			end
		end
	end
	trees.Parent = model
	return planted
end

--------------------------------------------------------------------------------
-- Camps
--------------------------------------------------------------------------------

-- A stilt hut: raised floor on posts, half walls and a thatched roof.
local function hut(parent: Instance, cf: CFrame, index: number, style: Architecture.Style)
	local floorY = 2.4
	for _, x in { -3.6, 3.6 } do
		for _, z in { -3, 3 } do
			A.cylinder(parent, 0.35, floorY + 6.5, cf * CFrame.new(x, 0, z), WOOD, Enum.Material.Wood)
		end
	end
	A.part(parent, Vector3.new(8.4, 0.5, 7.2), cf * CFrame.new(0, floorY, 0), WOOD, Enum.Material.WoodPlanks)
	A.part(
		parent,
		Vector3.new(8.4, 3, 0.4),
		cf * CFrame.new(0, floorY + 1.7, -3.4),
		if index % 2 == 0 then style.cloth else style.stone,
		Enum.Material.Fabric
	)
	-- Thatch in place of the realm's slate roof.
	local thatch = table.clone(style)
	thatch.roof = Color3.fromRGB(150, 128, 76)
	thatch.roofMaterial = Enum.Material.Grass
	A.gableRoof(parent, cf * CFrame.new(0, floorY + 6.3, 0), 9.6, 8.6, 3.4, thatch)
end

-- Overgrown shrines at the creature camps.
local function creatureCamps(model: Model, zone: WorldLayout.WarZone)
	for i, camp in zone.camps do
		if math.sqrt(camp.x * camp.x + camp.z * camp.z) < T.PLAZA_RADIUS then
			continue -- the plaza has its own ruins
		end
		local x, z = camp.x + 12, camp.z - 6
		brokenColumn(model, CFrame.new(at(zone, x, ground(zone, x, z) - 0.4, z)), 6 + i % 4 * 2, 600 + i)
		brazier(
			model,
			CFrame.new(at(zone, camp.x - 7, ground(zone, camp.x - 7, camp.z + 5) - 1.2, camp.z + 5))
		)
	end
end

export type Built = { portals: { [string]: BasePart }, parts: number, trees: number }

function JungleBuilder.build(root: Instance, zone: WorldLayout.WarZone): Built
	TerrainWriter.write(zone, MATERIALS, Enum.Material.Rock)
	local model = Instance.new("Model")
	model.Name = zone.id
	waterfall(model, zone)
	cliffVines(model, zone)
	plaza(model, zone)
	for index, spec in T.BRIDGES do
		bridge(model, zone, spec, index)
	end
	local portals: { [string]: BasePart } = {}
	for race in zone.bases do
		local portal = WarZoneKit.camp(model, zone, race, hut)
		if portal then
			portals[race] = portal
		end
	end
	creatureCamps(model, zone)
	local trees = forest(model, zone)
	WarZoneKit.bounds(model, zone, T.RIM_WIDTH)
	model.Parent = root
	local parts = 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
		end
	end
	return { portals = portals, parts = parts, trees = trees }
end

return JungleBuilder
