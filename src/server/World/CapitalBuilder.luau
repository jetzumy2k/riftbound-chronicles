--!strict
--[[
	CapitalBuilder — builds a race capital from WorldLayout (anchors and the
	shared city plan) in that race's Architecture style (PLAN.md D-37).

	  Skyreach Citadel (Angels)   white-gold cathedral city floating above the
	                              clouds on a rock island, with floating islets
	  Emberdeep Bastion (Devils)  black-crimson gothic keep over a lava sea,
	                              jagged rock spires and a volcano

	Both: plaza with the spawn waystone and the safe-zone ring, corner towers,
	colonnades with banners, lamps / braziers, portal gates (Desert Rift,
	Jungle Rift, Rift Dungeons; sealed until their updates) and the training
	yard. The core (platform, spawn, yard) is streamed persistently so a
	spawning player always has a floor; decoration streams normally.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldLayout = require(ReplicatedStorage.Shared.Definitions.WorldLayout)
local Architecture = require(script.Parent.Architecture)

type Style = Architecture.Style

local CapitalBuilder = {}

local function v3(t: { number }): Vector3
	return Vector3.new(t[1], t[2], t[3])
end

-- CFrame at a local {right, up, forward} point, its front (-Z) turned
-- `facing` degrees from the realm's forward toward its right.
local function localCF(realm: WorldLayout.Realm, point: { number }, facing: number?): CFrame
	local right, forward = WorldLayout.axes(realm)
	local a = math.rad(facing or 0)
	local look = v3(forward) * math.cos(a) + v3(right) * math.sin(a)
	local position = v3(WorldLayout.toWorld(realm, point))
	return CFrame.lookAt(position, position + look)
end

local function decor(part: BasePart)
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
end

--------------------------------------------------------------------------------
-- Landmarks
--------------------------------------------------------------------------------

local function cathedral(parent: Instance, cf: CFrame, width: number, depth: number, style: Style)
	local model = Instance.new("Model")
	model.Name = "Cathedral"
	local A = Architecture
	A.part(
		model,
		Vector3.new(width + 8, 3, depth + 8),
		cf * CFrame.new(0, 1.5, 0),
		style.stoneDark,
		style.stoneMaterial
	)
	local base = cf * CFrame.new(0, 3, 0)
	-- Front steps.
	A.stairs(
		model,
		base * CFrame.new(0, -3, -depth / 2 - 4 - 6) * CFrame.Angles(0, math.pi, 0),
		34,
		3,
		1,
		2,
		style
	)
	-- Nave and aisles.
	local naveW, naveH = 40, 46
	A.part(
		model,
		Vector3.new(naveW, naveH, depth),
		base * CFrame.new(0, naveH / 2, 0),
		style.stone,
		style.stoneMaterial
	)
	A.gableRoof(
		model,
		base * CFrame.new(0, naveH, 0) * CFrame.Angles(0, math.rad(90), 0),
		depth + 2,
		naveW + 2,
		18,
		style
	)
	for _, side in { -1, 1 } do
		A.part(
			model,
			Vector3.new(14, 28, depth - 6),
			base * CFrame.new(side * 27, 14, 3),
			style.stoneDark,
			style.stoneMaterial
		)
		-- Lean-to aisle roof.
		A.wedge(
			model,
			Vector3.new(depth - 6, 8, 14),
			base * CFrame.new(side * 27, 32, 3) * CFrame.Angles(0, math.rad(side * 90), 0),
			style.roof,
			style.roofMaterial
		)
		-- Flying buttresses.
		for i = -1, 1 do
			A.part(
				model,
				Vector3.new(3, 40, 4),
				base * CFrame.new(side * 37, 20, i * 12 + 4),
				style.stone,
				style.stoneMaterial
			)
			A.part(
				model,
				Vector3.new(16, 2.4, 3),
				base * CFrame.new(side * 29, 38, i * 12 + 4) * CFrame.Angles(0, 0, math.rad(side * -28)),
				style.stone,
				style.stoneMaterial,
				{ decor = true }
			)
			A.part(
				model,
				Vector3.new(2.2, 6, 2.2),
				base * CFrame.new(side * 37, 43, i * 12 + 4),
				style.trim,
				style.trimMaterial,
				{ decor = true }
			)
		end
		-- Tall lancet windows on the facade.
		A.part(
			model,
			Vector3.new(3.2, 14, 0.4),
			base * CFrame.new(side * 12, 22, -depth / 2 - 0.25),
			style.window,
			Enum.Material.Neon,
			{ decor = true }
		)
	end
	local front = base * CFrame.new(0, 0, -depth / 2)
	-- Rose window with a gold rim.
	A.part(
		model,
		Vector3.new(0.6, 19, 19),
		front * CFrame.new(0, 32, -0.2) * CFrame.Angles(0, math.rad(90), 0),
		style.trim,
		style.trimMaterial,
		{ decor = true, shape = Enum.PartType.Cylinder }
	)
	A.part(
		model,
		Vector3.new(0.6, 16, 16),
		front * CFrame.new(0, 32, -0.5) * CFrame.Angles(0, math.rad(90), 0),
		style.window,
		Enum.Material.Neon,
		{ decor = true, shape = Enum.PartType.Cylinder }
	)
	for i = 0, 3 do
		A.part(
			model,
			Vector3.new(0.8, 15, 0.5),
			front * CFrame.new(0, 32, -0.8) * CFrame.Angles(0, 0, math.rad(i * 45)),
			style.trim,
			style.trimMaterial,
			{ decor = true }
		)
	end
	-- Main door under a pointed arch.
	A.arch(model, front * CFrame.new(0, 0, -1.5), 11, 22, 3, 2.4, style)
	A.part(model, Vector3.new(11, 15, 0.8), front * CFrame.new(0, 7.5, -0.6), style.trim, style.trimMaterial)
	-- Gold bands across the facade.
	for _, y in { 18, 43 } do
		A.part(
			model,
			Vector3.new(naveW + 0.6, 1.2, 0.8),
			front * CFrame.new(0, y, -0.3),
			style.trim,
			style.trimMaterial,
			{ decor = true }
		)
	end
	-- Twin bell towers and the crossing spire.
	for _, side in { -1, 1 } do
		A.tower(model, front * CFrame.new(side * 27, 0, 4), 8, 72, style)
	end
	A.spire(model, base * CFrame.new(0, naveH + 14, 6), 11, 52, style)
	-- A floating gold ring above the crossing (celestial motif).
	A.ring(
		model,
		13,
		0.8,
		0.8,
		18,
		base * CFrame.new(0, naveH + 92, 6) * CFrame.Angles(math.rad(12), 0, 0),
		style.trim,
		style.trimMaterial,
		{ decor = true }
	)
	model.Parent = parent
end

local function keep(parent: Instance, cf: CFrame, width: number, depth: number, style: Style)
	local model = Instance.new("Model")
	model.Name = "Keep"
	local A = Architecture
	A.part(
		model,
		Vector3.new(width + 8, 3, depth + 8),
		cf * CFrame.new(0, 1.5, 0),
		style.stoneDark,
		style.stoneMaterial
	)
	local base = cf * CFrame.new(0, 3, 0)
	local hallW, hallH = 48, 40
	A.part(
		model,
		Vector3.new(hallW, hallH, depth),
		base * CFrame.new(0, hallH / 2, 0),
		style.stone,
		style.stoneMaterial
	)
	-- Crenellations and wall spikes along the roof edge.
	for i = 0, 7 do
		local x = -hallW / 2 + 3 + i * (hallW - 6) / 7
		for _, z in { -depth / 2 + 1.5, depth / 2 - 1.5 } do
			A.part(
				model,
				Vector3.new(3, 4, 3),
				base * CFrame.new(x, hallH + 2, z),
				style.stone,
				style.stoneMaterial,
				{ decor = true }
			)
		end
		if i % 2 == 0 then
			A.part(
				model,
				Vector3.new(1.2, 7, 1.2),
				base
					* CFrame.new(x, hallH + 7, -depth / 2 + 1.5)
					* CFrame.Angles(math.rad(-15), 0, math.rad(45)),
				style.trim,
				style.trimMaterial,
				{ decor = true }
			)
		end
	end
	local front = base * CFrame.new(0, 0, -depth / 2)
	-- Slit windows glowing with ember light.
	for row, y in { 14, 26 } do
		for i = -3, 3 do
			if i == 0 and row == 1 then
				continue
			end
			A.part(
				model,
				Vector3.new(1.4, 6, 0.4),
				front * CFrame.new(i * 6, y, -0.25),
				style.window,
				Enum.Material.Neon,
				{ decor = true }
			)
		end
	end
	-- Great gate with a glowing portcullis.
	A.arch(model, front * CFrame.new(0, 0, -1.5), 12, 24, 3.4, 3, style)
	for i = -2, 2 do
		A.part(
			model,
			Vector3.new(0.5, 15, 0.5),
			front * CFrame.new(i * 2.2, 7.5, -0.8),
			style.glow,
			Enum.Material.Neon,
			{ decor = true }
		)
	end
	for _, y in { 4, 9, 14 } do
		A.part(
			model,
			Vector3.new(11, 0.5, 0.5),
			front * CFrame.new(0, y, -0.8),
			style.glow,
			Enum.Material.Neon,
			{ decor = true }
		)
	end
	A.part(
		model,
		Vector3.new(12, 15, 0.6),
		front * CFrame.new(0, 7.5, -0.2),
		style.stoneDark,
		style.stoneMaterial
	)
	-- Banners on the facade.
	for _, side in { -1, 1 } do
		A.banner(model, front * CFrame.new(side * 14, 36, -0.8), 6, 18, style)
	end
	-- Towers: twin front towers and the great central tower.
	for _, side in { -1, 1 } do
		A.tower(model, front * CFrame.new(side * 28, 0, 4), 8, 62, style)
	end
	A.tower(model, base * CFrame.new(0, hallH - 2, 8), 11, 56, style)
	-- Lava moat across the front with a stone bridge.
	local moat = A.part(
		model,
		Vector3.new(width + 8, 0.6, 7),
		cf * CFrame.new(0, 0.2, -depth / 2 - 10),
		style.glow,
		Enum.Material.CrackedLava,
		{ decor = true }
	)
	moat.Name = "LavaMoat"
	A.part(
		model,
		Vector3.new(16, 1.4, 10),
		cf * CFrame.new(0, 0.7, -depth / 2 - 10),
		style.stoneDark,
		style.stoneMaterial
	)
	local light = Instance.new("PointLight")
	light.Color = style.light
	light.Range = 30
	light.Brightness = 2
	light.Parent = moat
	model.Parent = parent
end

--------------------------------------------------------------------------------
-- Surroundings
--------------------------------------------------------------------------------

local function skyIsland(parent: Instance, realm: WorldLayout.Realm, style: Style)
	local A = Architecture
	local model = Instance.new("Model")
	model.Name = "SkyIsland"
	local center = v3(realm.platformCenter)
	local bottom = center.Y - realm.platformSize[2] / 2
	local rock = Color3.fromRGB(196, 188, 176)
	-- Inverted rocky cone under the platform.
	local tiers = 6
	local y = bottom
	for i = 0, tiers - 1 do
		local t = i / tiers
		local w = realm.platformSize[1] * (0.98 - t * 0.78)
		local h = 18 - i * 1.5
		A.part(
			model,
			Vector3.new(w, h, w * 0.96),
			CFrame.new(center.X, y - h / 2, center.Z) * CFrame.Angles(0, math.rad(i * 17), 0),
			rock,
			Enum.Material.Slate,
			{ decor = true }
		)
		y -= h * 0.92
	end
	-- Hanging crystals beneath.
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2
		A.crystals(
			model,
			CFrame.new(
				center + Vector3.new(math.cos(a) * 60, -(realm.platformSize[2] + 30), math.sin(a) * 60)
			) * CFrame.Angles(math.pi, 0, 0),
			14,
			style.window
		)
	end
	-- Cloud sea around and below.
	for i = 0, 13 do
		local a = i / 14 * math.pi * 2
		local r = 140 + (i % 3) * 45
		A.cloud(
			model,
			center + Vector3.new(math.cos(a) * r, -30 - (i % 4) * 14, math.sin(a) * r),
			22 + (i % 3) * 6,
			i
		)
	end
	-- Floating islets with little spires.
	for i = 0, 3 do
		local a = (i + 0.5) / 4 * math.pi * 2
		local p = center + Vector3.new(math.cos(a) * 250, 10 + (i % 2) * 30, math.sin(a) * 250)
		A.part(
			model,
			Vector3.new(34, 6, 30),
			CFrame.new(p),
			style.stone,
			style.stoneMaterial,
			{ decor = true }
		)
		A.part(
			model,
			Vector3.new(26, 10, 22),
			CFrame.new(p - Vector3.new(0, 8, 0)) * CFrame.Angles(0, 0.4, 0),
			rock,
			Enum.Material.Slate,
			{ decor = true }
		)
		A.part(
			model,
			Vector3.new(12, 10, 10),
			CFrame.new(p - Vector3.new(0, 16, 0)) * CFrame.Angles(0, 1, 0),
			rock,
			Enum.Material.Slate,
			{ decor = true }
		)
		local tower = A.tower(model, CFrame.new(p + Vector3.new(0, 3, 0)), 4, 26, style)
		for _, d in tower:GetDescendants() do
			if d:IsA("BasePart") then
				decor(d)
			end
		end
	end
	model.Parent = parent
end

local function volcanicLand(parent: Instance, realm: WorldLayout.Realm, style: Style)
	local A = Architecture
	local model = Instance.new("Model")
	model.Name = "VolcanicLand"
	local center = v3(realm.platformCenter)
	local bottom = center.Y - realm.platformSize[2] / 2
	local lavaY = bottom - 14
	local lava = A.part(
		model,
		Vector3.new(1400, 2, 1400),
		CFrame.new(center.X, lavaY, center.Z),
		Color3.fromRGB(255, 92, 30),
		Enum.Material.CrackedLava,
		{ decor = true }
	)
	lava.Name = "LavaSea"
	-- Massive pillars holding the city above the lava.
	local half = realm.platformSize[1] / 2 - 26
	for _, c in
		{
			Vector3.new(half, 0, half),
			Vector3.new(-half, 0, half),
			Vector3.new(half, 0, -half),
			Vector3.new(-half, 0, -half),
		}
	do
		A.part(
			model,
			Vector3.new(30, bottom - lavaY + 2, 30),
			CFrame.new(center.X + c.X, (bottom + lavaY) / 2, center.Z + c.Z)
				* CFrame.Angles(0, math.rad(45), 0),
			style.stoneDark,
			style.stoneMaterial
		)
	end
	-- Glowing lava falls pouring off the platform edges.
	for i = -1, 1 do
		for _, side in { -1, 1 } do
			A.part(
				model,
				Vector3.new(8, bottom - lavaY, 1.4),
				CFrame.new(
					center.X + i * 70,
					(bottom + lavaY) / 2,
					center.Z + side * (realm.platformSize[3] / 2 + 0.8)
				),
				style.glow,
				Enum.Material.Neon,
				{ decor = true, transparency = 0.1 }
			)
		end
	end
	-- Jagged spires rising from the lava.
	local rng = Random.new(66)
	for i = 0, 15 do
		local a = i / 16 * math.pi * 2 + rng:NextNumber(-0.1, 0.1)
		local r = rng:NextNumber(210, 360)
		local h = rng:NextNumber(40, 120)
		A.rockSpike(
			model,
			CFrame.new(center.X + math.cos(a) * r, lavaY, center.Z + math.sin(a) * r),
			h,
			rng:NextNumber(18, 34),
			style.stoneDark,
			Enum.Material.Basalt,
			i
		)
	end
	-- Volcano on the horizon beyond the training yard (seen from the spawn),
	-- concave slopes, a glowing crater and lava streams.
	local _, forward = WorldLayout.axes(realm)
	local volcanoBase = center + v3(forward) * 700 + Vector3.new(0, lavaY - center.Y, 0)
	local tiers, baseWidth, tierHeight = 11, 440, 24
	local y = 0
	for i = 0, tiers - 1 do
		local t = i / tiers
		local w = baseWidth * (1 - 0.82 * t ^ 0.7)
		A.part(
			model,
			Vector3.new(w, tierHeight, w * 0.94),
			CFrame.new(volcanoBase + Vector3.new(0, y + tierHeight / 2, 0))
				* CFrame.Angles(0, math.rad(i * 19), 0),
			style.stoneDark,
			Enum.Material.Basalt,
			{ decor = true }
		)
		y += tierHeight * 0.92
	end
	local topWidth = baseWidth * (1 - 0.82 * ((tiers - 1) / tiers) ^ 0.7)
	local crater = A.disc(
		model,
		topWidth * 0.38,
		3,
		CFrame.new(volcanoBase + Vector3.new(0, y - 1, 0)),
		style.glow,
		Enum.Material.Neon,
		{ decor = true }
	)
	local craterLight = Instance.new("PointLight")
	craterLight.Color = style.light
	craterLight.Range = 60
	craterLight.Brightness = 3
	craterLight.Parent = crater
	for i = 0, 5 do
		local a = (i + 0.3) / 6 * math.pi * 2
		local dirVec = Vector3.new(math.cos(a), 0, math.sin(a))
		local from = volcanoBase + Vector3.new(0, y - 2, 0) + dirVec * topWidth * 0.42
		local to = volcanoBase + Vector3.new(0, tierHeight * 0.6, 0) + dirVec * baseWidth * 0.47
		local length = (to - from).Magnitude
		A.part(
			model,
			Vector3.new(3 + (i % 2) * 2, 1.2, length),
			CFrame.lookAt((from + to) / 2, to) * CFrame.new(0, 1.5, 0),
			style.glow,
			Enum.Material.Neon,
			{ decor = true }
		)
	end
	-- Drifting embers over the city.
	local emberSource = A.part(
		model,
		Vector3.new(realm.platformSize[1], 1, realm.platformSize[3]),
		CFrame.new(center + Vector3.new(0, -2, 0)),
		style.glow,
		Enum.Material.SmoothPlastic,
		{ decor = true, transparency = 1 }
	)
	local embers = Instance.new("ParticleEmitter")
	embers.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	embers.Color = ColorSequence.new(style.glow, Color3.fromRGB(255, 200, 90))
	embers.LightEmission = 1
	embers.Size =
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	embers.Lifetime = NumberRange.new(5, 8)
	embers.Rate = 14
	embers.Speed = NumberRange.new(2, 5)
	embers.Acceleration = Vector3.new(0, 1.5, 0)
	embers.SpreadAngle = Vector2.new(25, 25)
	embers.EmissionDirection = Enum.NormalId.Top
	embers.Parent = emberSource
	model.Parent = parent
end

--------------------------------------------------------------------------------
-- City
--------------------------------------------------------------------------------

local function plaza(parent: Instance, realm: WorldLayout.Realm, style: Style, safeRadius: number)
	local A = Architecture
	local center = localCF(realm, { 0, 0, 0 })
	-- Paved disc with an inlaid ring at the safe-zone edge and a star around the spawn.
	A.disc(parent, safeRadius + 2, 0.3, center, style.stoneDark, style.stoneMaterial, { decor = true })
	A.disc(parent, safeRadius - 3, 0.36, center, style.stone, style.stoneMaterial, { decor = true })
	A.ring(parent, safeRadius, 1.6, 0.5, 48, center, style.trim, style.trimMaterial, { decor = true })
	A.ring(parent, safeRadius - 2.2, 0.5, 0.45, 48, center, style.glow, Enum.Material.Neon, { decor = true })
	A.ring(parent, 34, 1.2, 0.5, 28, center, style.trim, style.trimMaterial, { decor = true })
	for i = 0, 7 do
		A.part(
			parent,
			Vector3.new(0.8, 0.45, 26),
			center * CFrame.Angles(0, i * math.pi / 4, 0) * CFrame.new(0, 0.2, -20),
			style.trim,
			style.trimMaterial,
			{ decor = true }
		)
	end
	-- Waystone behind the spawn: a floating crystal over a pedestal.
	local stone = localCF(realm, { 0, 0, -16 })
	A.part(parent, Vector3.new(8, 2, 8), stone * CFrame.new(0, 1, 0), style.stoneDark, style.stoneMaterial)
	A.part(
		parent,
		Vector3.new(5, 2, 5),
		stone * CFrame.new(0, 3, 0) * CFrame.Angles(0, math.rad(45), 0),
		style.trim,
		style.trimMaterial
	)
	local crystal = A.part(
		parent,
		Vector3.new(3.4, 9, 3.4),
		stone * CFrame.new(0, 10, 0) * CFrame.Angles(0, math.rad(45), 0),
		style.window,
		Enum.Material.Neon,
		{ decor = true, transparency = 0.1 }
	)
	crystal.Name = "Waystone"
	A.ring(
		parent,
		4.5,
		0.5,
		0.5,
		12,
		stone * CFrame.new(0, 9, 0) * CFrame.Angles(math.rad(70), 0, 0),
		style.trim,
		style.trimMaterial,
		{ decor = true }
	)
	local light = Instance.new("PointLight")
	light.Color = style.window
	light.Range = 24
	light.Brightness = 2
	light.Parent = crystal
end

local function edges(parent: Instance, realm: WorldLayout.Realm, style: Style)
	local A = Architecture
	local half = realm.platformSize[1] / 2
	-- Balustrade on the back and side edges (the front opens onto the yard;
	-- gaps leave room for the side gates).
	local function rail(from: { number }, to: { number })
		local a = v3(WorldLayout.toWorld(realm, from))
		local b = v3(WorldLayout.toWorld(realm, to))
		local length = (b - a).Magnitude
		local cf = CFrame.lookAt((a + b) / 2, b)
		A.part(
			parent,
			Vector3.new(1.4, 3.2, length),
			cf * CFrame.new(0, 1.6, 0),
			style.stone,
			style.stoneMaterial
		)
		A.part(
			parent,
			Vector3.new(1.8, 0.6, length),
			cf * CFrame.new(0, 3.5, 0),
			style.trim,
			style.trimMaterial,
			{ decor = true }
		)
	end
	local e = half - 1
	rail({ -e, 0, -e }, { e, 0, -e })
	rail({ -e, 0, -e }, { -e, 0, 14 })
	rail({ -e, 0, 46 }, { -e, 0, e })
	rail({ e, 0, -e }, { e, 0, 14 })
	rail({ e, 0, 46 }, { e, 0, e })
end

local function colonnades(parent: Instance, realm: WorldLayout.Realm, style: Style)
	local A = Architecture
	local plan = WorldLayout.City
	local count = plan.colonnadeColumns
	for _, side in { -1, 1 } do
		local x = side * plan.colonnadeOffset * 0.82
		local z0, z1 = -96, 4
		for i = 0, count - 1 do
			local z = z0 + (z1 - z0) * i / (count - 1)
			A.column(parent, localCF(realm, { x, 0, z }), 1.6, 22, style)
			if i % 2 == 1 then
				A.banner(parent, localCF(realm, { x - side * 1.8, 20.5, z }, side * -90), 4, 12, style)
			end
		end
		-- Entablature beam on top.
		local mid = localCF(realm, { x, 22.8, (z0 + z1) / 2 })
		A.part(
			parent,
			Vector3.new(5, 1.6, z1 - z0 + 6),
			mid,
			style.stone,
			style.stoneMaterial,
			{ decor = true }
		)
		A.part(
			parent,
			Vector3.new(5.4, 0.6, z1 - z0 + 6.4),
			mid * CFrame.new(0, 1.1, 0),
			style.trim,
			style.trimMaterial,
			{ decor = true }
		)
	end
end

local function lamps(parent: Instance, realm: WorldLayout.Realm, style: Style)
	local plan = WorldLayout.City
	for i = 0, plan.lampCount - 1 do
		local a = (i + 0.5) / plan.lampCount * math.pi * 2
		Architecture.lamp(
			parent,
			localCF(realm, { math.cos(a) * plan.lampRadius, 0, math.sin(a) * plan.lampRadius }),
			style
		)
	end
end

local function trainingYard(core: Instance, decorParent: Instance, realm: WorldLayout.Realm, style: Style)
	local A = Architecture
	local yardCenter, yardSize = WorldLayout.trainingYard(realm)
	local floor = A.part(
		core,
		v3(yardSize),
		CFrame.new(v3(yardCenter)),
		style.stone:Lerp(style.trim, 0.1),
		style.stoneMaterial
	)
	floor.Name = "TrainingYard"
	floor:SetAttribute("RC_Zone", "TrainingGrounds")
	local yardTop = yardCenter[2] + yardSize[2] / 2
	local dir = WorldLayout.yardDirection(realm)
	local dummies = WorldLayout.dummyPositions(realm)
	local lineZ = dummies[1][3]
	for _, distance in WorldLayout.TrainingYard.rangeMarkers do
		local z = lineZ - dir * distance
		local stripe = A.part(
			decorParent,
			Vector3.new(yardSize[1] - 16, 0.1, 0.6),
			CFrame.new(yardCenter[1], yardTop + 0.05, z),
			style.glow,
			Enum.Material.Neon,
			{ decor = true, transparency = 0.45 }
		)
		stripe.Name = "RangeMarker"
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(90, 26)
		gui.StudsOffset = Vector3.new(-(yardSize[1] / 2 - 14), 1.2, 0)
		gui.MaxDistance = 90
		gui.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Text = `{distance} studs`
		label.TextSize = 16
		label.FontFace = Font.fromEnum(Enum.Font.GothamBold)
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextStrokeTransparency = 0.3
		label.Parent = gui
		gui.Parent = stripe
	end
	-- Railing on the yard's three open sides.
	local hx, hz = yardSize[1] / 2, yardSize[3] / 2
	local farZ = yardCenter[3] + dir * hz
	for _, spec in
		{
			{ Vector3.new(yardSize[1], 0, 0), Vector3.new(yardCenter[1], 0, farZ) },
			{ Vector3.new(0, 0, yardSize[3]), Vector3.new(yardCenter[1] - hx, 0, yardCenter[3]) },
			{ Vector3.new(0, 0, yardSize[3]), Vector3.new(yardCenter[1] + hx, 0, yardCenter[3]) },
		}
	do
		local size = spec[1] + Vector3.new(1.4, 3, 1.4)
		A.part(
			decorParent,
			size,
			CFrame.new(spec[2].X, yardTop + 1.5, spec[2].Z),
			style.stone,
			style.stoneMaterial
		)
	end
	-- Archway sign where the yard meets the city.
	local signZ = yardCenter[3] - dir * (hz - 4)
	local archCF = CFrame.lookAt(
		Vector3.new(yardCenter[1], yardTop, signZ),
		Vector3.new(yardCenter[1], yardTop, signZ + dir)
	)
	A.arch(decorParent, archCF, 44, 30, 3, 3, style)
	local sign = A.part(
		decorParent,
		Vector3.new(22, 4, 0.8),
		archCF * CFrame.new(0, 26, 0),
		style.trim,
		style.trimMaterial,
		{ decor = true }
	)
	sign.Name = "TrainingSign"
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 30
		gui.LightInfluence = 0
		local text = Instance.new("TextLabel")
		text.BackgroundTransparency = 1
		text.Size = UDim2.fromScale(1, 1)
		text.Text = "⚔  TRAINING GROUNDS  ⚔"
		text.TextScaled = true
		text.FontFace = Font.new(Font.fromEnum(Enum.Font.Merriweather).Family, Enum.FontWeight.Bold)
		text.TextColor3 = if style.towerTop == "spire"
			then Color3.fromRGB(60, 40, 10)
			else Color3.fromRGB(255, 220, 190)
		text.Parent = gui
		gui.Parent = sign
	end
end

export type Built = {
	spawn: SpawnLocation,
	parts: number,
	gates: { [string]: BasePart },
}

--[[
	Builds the capital for `realm` under `root`. Returns its SpawnLocation,
	part count (performance budget) and the portal surfaces by gate id.
]]
function CapitalBuilder.build(
	root: Instance,
	realm: WorldLayout.Realm,
	safeZone: WorldLayout.SafeZone?
): Built
	local style = (Architecture.Styles :: any)[realm.race] :: Style
	local A = Architecture
	local capital = Instance.new("Model")
	capital.Name = realm.zone

	-- Core: always streamed in (floor + spawn + yard).
	local core = Instance.new("Model")
	core.Name = "Core"
	core.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	core.Parent = capital
	local city = Instance.new("Model")
	city.Name = "City"
	city.Parent = capital

	local center = v3(realm.platformCenter)
	local size = v3(realm.platformSize)
	local platform = A.part(core, size, CFrame.new(center), style.stoneDark, style.stoneMaterial)
	platform.Name = "Platform"
	A.part(
		city,
		Vector3.new(size.X + 1, 1.2, size.Z + 1),
		CFrame.new(center - Vector3.new(0, size.Y / 2 - 0.6, 0)),
		style.trim,
		style.trimMaterial,
		{ decor = true }
	)

	-- Spawn (deterministic: one per race).
	local top = center.Y + size.Y / 2
	local spawnPosition = v3(realm.spawnPosition)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = `Spawn_{realm.race}`
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = CFrame.lookAt(
		Vector3.new(spawnPosition.X, top + 0.5, spawnPosition.Z),
		Vector3.new(realm.spawnLookAt[1], top + 0.5, realm.spawnLookAt[3])
	)
	spawn.Color = style.trim
	spawn.Material = style.trimMaterial
	spawn.Neutral = true
	spawn.Duration = 0 -- spawn protection is a combat-state concern, not a ForceField
	spawn.Parent = core

	local safeRadius = if safeZone and safeZone.volume.radius then safeZone.volume.radius else 100
	plaza(city, realm, style, safeRadius)
	edges(city, realm, style)
	colonnades(city, realm, style)
	lamps(city, realm, style)

	local plan = WorldLayout.City
	for _, corner in plan.towers do
		A.tower(city, localCF(realm, corner), 10, 58, style)
	end
	local landmarkCF = localCF(realm, plan.landmark.position)
	if style.towerTop == "spire" then
		cathedral(city, landmarkCF, plan.landmark.width, plan.landmark.depth, style)
		skyIsland(city, realm, style)
	else
		keep(city, landmarkCF, plan.landmark.width, plan.landmark.depth, style)
		volcanicLand(city, realm, style)
	end

	local gates: { [string]: BasePart } = {}
	for _, gate in plan.gates do
		gates[gate.id] = A.portalGate(city, localCF(realm, gate.position, gate.facing), {
			label = gate.label,
			opensIn = gate.opensIn,
			active = false,
		}, style)
	end

	trainingYard(core, city, realm, style)
	capital.Parent = root

	local parts = 0
	for _, d in capital:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
		end
	end
	return { spawn = spawn, parts = parts, gates = gates }
end

return CapitalBuilder
