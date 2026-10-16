--!strict
--[[
	Architecture — a small building kit for the capitals (Phase 16 art,
	pulled forward; PLAN.md D-37).

	Every builder takes a parent and a base CFrame in *object space*: the
	origin is the ground centre of the piece, +Y is up and -Z is its front.
	Colours and materials come from a Style, so one plan builds a white-gold
	celestial city or a black-crimson volcanic one.

	Performance: plain Parts/WedgeParts only (no meshes to stream), decorative
	pieces never collide / query / touch, few lights. Part counts are logged
	per capital by WorldService.
]]

local Architecture = {}

export type Style = {
	race: string,
	stone: Color3,
	stoneMaterial: Enum.Material,
	stoneDark: Color3,
	trim: Color3,
	trimMaterial: Enum.Material,
	roof: Color3,
	roofMaterial: Enum.Material,
	glow: Color3,
	window: Color3,
	cloth: Color3,
	light: Color3,
	-- "spire" (tapered, elegant) or "spike" (jagged crown)
	towerTop: "spire" | "spike",
}

Architecture.Styles = {
	Angel = {
		race = "Angel",
		stone = Color3.fromRGB(222, 213, 196),
		stoneMaterial = Enum.Material.Marble,
		stoneDark = Color3.fromRGB(150, 160, 180),
		trim = Color3.fromRGB(226, 182, 86),
		trimMaterial = Enum.Material.Foil,
		roof = Color3.fromRGB(96, 132, 186),
		roofMaterial = Enum.Material.Slate,
		glow = Color3.fromRGB(255, 210, 120),
		window = Color3.fromRGB(150, 205, 255),
		cloth = Color3.fromRGB(70, 120, 210),
		light = Color3.fromRGB(255, 236, 196),
		towerTop = "spire",
	} :: Style,
	Devil = {
		race = "Devil",
		stone = Color3.fromRGB(104, 88, 90),
		stoneMaterial = Enum.Material.Basalt,
		stoneDark = Color3.fromRGB(70, 58, 62),
		trim = Color3.fromRGB(176, 40, 38),
		trimMaterial = Enum.Material.Metal,
		roof = Color3.fromRGB(84, 40, 44),
		roofMaterial = Enum.Material.Slate,
		glow = Color3.fromRGB(255, 96, 40),
		window = Color3.fromRGB(255, 84, 36),
		cloth = Color3.fromRGB(150, 22, 30),
		light = Color3.fromRGB(255, 120, 60),
		towerTop = "spike",
	} :: Style,
}

--------------------------------------------------------------------------------
-- Primitives
--------------------------------------------------------------------------------

export type PartOptions = {
	name: string?,
	shape: Enum.PartType?,
	transparency: number?,
	-- Decorative: no collision, queries, touches or shadow.
	decor: boolean?,
	shadow: boolean?,
}

local function setup(
	part: BasePart,
	parent: Instance,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material,
	options: PartOptions?
)
	part.Anchored = true
	part.Size = size
	part.CFrame = cf
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if options then
		if options.name then
			part.Name = options.name
		end
		if options.transparency then
			part.Transparency = options.transparency
		end
		if options.decor then
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
		end
		if options.shadow == false then
			part.CastShadow = false
		end
	end
	part.Parent = parent
end

function Architecture.part(
	parent: Instance,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material,
	options: PartOptions?
): Part
	local part = Instance.new("Part")
	if options and options.shape then
		part.Shape = options.shape
	end
	setup(part, parent, size, cf, color, material, options)
	return part
end

function Architecture.wedge(
	parent: Instance,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material,
	options: PartOptions?
): WedgePart
	local part = Instance.new("WedgePart")
	setup(part, parent, size, cf, color, material, options)
	return part
end

-- Upright cylinder standing on `cf` (base centre).
function Architecture.cylinder(
	parent: Instance,
	radius: number,
	height: number,
	cf: CFrame,
	color: Color3,
	material: Enum.Material,
	options: PartOptions?
): Part
	local opts: PartOptions = table.clone(options or {})
	opts.shape = Enum.PartType.Cylinder
	return Architecture.part(
		parent,
		Vector3.new(height, radius * 2, radius * 2),
		cf * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
		color,
		material,
		opts
	)
end

-- Flat disc (thin cylinder) lying on `cf`.
function Architecture.disc(
	parent: Instance,
	radius: number,
	thickness: number,
	cf: CFrame,
	color: Color3,
	material: Enum.Material,
	options: PartOptions?
): Part
	return Architecture.cylinder(parent, radius, thickness, cf, color, material, options)
end

-- Ring of `segments` blocks of the given radius lying on `cf`.
function Architecture.ring(
	parent: Instance,
	radius: number,
	width: number,
	height: number,
	segments: number,
	cf: CFrame,
	color: Color3,
	material: Enum.Material,
	options: PartOptions?
)
	local chord = 2 * radius * math.sin(math.pi / segments) + 0.05
	for i = 0, segments - 1 do
		local a = (i + 0.5) / segments * math.pi * 2
		Architecture.part(
			parent,
			Vector3.new(chord, height, width),
			cf * CFrame.Angles(0, -a, 0) * CFrame.new(0, height / 2, -radius),
			color,
			material,
			options
		)
	end
end

--------------------------------------------------------------------------------
-- Structural pieces
--------------------------------------------------------------------------------

-- Tapered spire of stacked tiers (alternating 45° turns) with a finial.
function Architecture.spire(parent: Instance, cf: CFrame, width: number, height: number, style: Style)
	local tiers = 6
	local y = 0
	for i = 0, tiers - 1 do
		local t = i / tiers
		local w = width * (1 - t * 0.85)
		local h = height / tiers
		Architecture.part(
			parent,
			Vector3.new(w, h, w),
			cf * CFrame.new(0, y + h / 2, 0) * CFrame.Angles(0, if i % 2 == 0 then 0 else math.rad(45), 0),
			if i == tiers - 1 then style.trim else style.roof,
			if i == tiers - 1 then style.trimMaterial else style.roofMaterial,
			{ decor = i > 0 }
		)
		y += h
	end
	-- Needle and glowing orb at the tip.
	Architecture.part(
		parent,
		Vector3.new(0.6, height * 0.25, 0.6),
		cf * CFrame.new(0, y + height * 0.125, 0),
		style.trim,
		style.trimMaterial,
		{ decor = true }
	)
	Architecture.part(
		parent,
		Vector3.new(1.6, 1.6, 1.6),
		cf * CFrame.new(0, y + height * 0.25 + 0.6, 0),
		style.glow,
		Enum.Material.Neon,
		{ decor = true, shape = Enum.PartType.Ball }
	)
end

-- Jagged crown of leaning spikes (Devil towers).
function Architecture.spikeCrown(parent: Instance, cf: CFrame, radius: number, height: number, style: Style)
	local count = 6
	for i = 0, count - 1 do
		local a = i / count * math.pi * 2
		local h = height * (if i % 2 == 0 then 1 else 0.65)
		Architecture.part(
			parent,
			Vector3.new(radius * 0.35, h, radius * 0.35),
			cf
				* CFrame.Angles(0, a, 0)
				* CFrame.new(0, 0, -radius * 0.75)
				* CFrame.Angles(math.rad(-14), 0, 0)
				* CFrame.new(0, h / 2, 0)
				* CFrame.Angles(0, math.rad(45), 0),
			style.roof,
			style.roofMaterial,
			{ decor = true }
		)
	end
	-- Central tall spike with a glowing core.
	Architecture.part(
		parent,
		Vector3.new(radius * 0.5, height * 1.5, radius * 0.5),
		cf * CFrame.new(0, height * 0.75, 0) * CFrame.Angles(0, math.rad(45), 0),
		style.roof,
		style.roofMaterial,
		{ decor = true }
	)
	Architecture.part(
		parent,
		Vector3.new(radius * 0.55, height * 0.3, radius * 0.55),
		cf * CFrame.new(0, height * 0.55, 0) * CFrame.Angles(0, math.rad(45), 0),
		style.glow,
		Enum.Material.Neon,
		{ decor = true }
	)
end

-- Round tower with trim bands, glowing windows and a spire or spiked crown.
function Architecture.tower(parent: Instance, cf: CFrame, radius: number, height: number, style: Style)
	local model = Instance.new("Model")
	model.Name = "Tower"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	Architecture.cylinder(model, radius * 1.18, 3, cf, style.stoneDark, style.stoneMaterial)
	Architecture.cylinder(model, radius, height, cf, style.stone, style.stoneMaterial)
	for _, f in { 0.35, 0.7 } do
		Architecture.cylinder(
			model,
			radius * 1.06,
			1.2,
			cf * CFrame.new(0, height * f, 0),
			style.trim,
			style.trimMaterial,
			{ decor = true }
		)
	end
	-- Windows on four sides, two levels.
	for level, f in { 0.5, 0.82 } do
		for i = 0, 3 do
			local a = i * math.pi / 2 + (level - 1) * math.pi / 4
			Architecture.part(
				model,
				Vector3.new(radius * 0.32, height * 0.09, 0.4),
				cf * CFrame.Angles(0, a, 0) * CFrame.new(0, height * f, -radius + 0.1),
				style.window,
				Enum.Material.Neon,
				{ decor = true }
			)
		end
	end
	local top = cf * CFrame.new(0, height, 0)
	-- Battlement ring.
	Architecture.ring(
		model,
		radius * 1.12,
		1.4,
		2.4,
		10,
		top,
		style.stone,
		style.stoneMaterial,
		{ decor = true }
	)
	if style.towerTop == "spire" then
		Architecture.spire(model, top, radius * 1.7, radius * 4.2, style)
	else
		Architecture.spikeCrown(model, top, radius, radius * 2.6, style)
	end
	model.Parent = parent
	return model
end

-- Column: plinth, shaft, capital.
function Architecture.column(parent: Instance, cf: CFrame, radius: number, height: number, style: Style)
	Architecture.part(
		parent,
		Vector3.new(radius * 2.6, 1.6, radius * 2.6),
		cf * CFrame.new(0, 0.8, 0),
		style.stoneDark,
		style.stoneMaterial
	)
	Architecture.cylinder(
		parent,
		radius,
		height - 3.2,
		cf * CFrame.new(0, 1.6, 0),
		style.stone,
		style.stoneMaterial
	)
	Architecture.part(
		parent,
		Vector3.new(radius * 2.8, 1.6, radius * 2.8),
		cf * CFrame.new(0, height - 0.8, 0),
		style.trim,
		style.trimMaterial,
		{ decor = true }
	)
end

-- Pointed arch: two piers and an arc of blocks. Walk-through opening.
function Architecture.arch(
	parent: Instance,
	cf: CFrame,
	span: number,
	height: number,
	depth: number,
	thickness: number,
	style: Style
)
	local pierHeight = height - span / 2
	for _, side in { -1, 1 } do
		Architecture.part(
			parent,
			Vector3.new(thickness, pierHeight, depth),
			cf * CFrame.new(side * (span / 2 + thickness / 2), pierHeight / 2, 0),
			style.stone,
			style.stoneMaterial
		)
	end
	local segments = 9
	local r = span / 2 + thickness / 2
	for i = 0, segments - 1 do
		local a0 = math.pi * i / segments
		local a1 = math.pi * (i + 1) / segments
		local p0 = Vector3.new(math.cos(a0) * r, math.sin(a0) * r * 1.15, 0)
		local p1 = Vector3.new(math.cos(a1) * r, math.sin(a1) * r * 1.15, 0)
		local mid = (p0 + p1) / 2
		local length = (p1 - p0).Magnitude + 0.4
		local angle = math.atan2(p1.Y - p0.Y, p1.X - p0.X)
		Architecture.part(
			parent,
			Vector3.new(length, thickness, depth),
			cf * CFrame.new(mid.X, pierHeight + mid.Y, 0) * CFrame.Angles(0, 0, angle),
			if i == math.floor(segments / 2) then style.trim else style.stone,
			if i == math.floor(segments / 2) then style.trimMaterial else style.stoneMaterial,
			{ decor = true }
		)
	end
end

-- Gable roof along X: `width` across Z, ridge `height` above `cf`.
function Architecture.gableRoof(
	parent: Instance,
	cf: CFrame,
	length: number,
	width: number,
	height: number,
	style: Style
)
	Architecture.wedge(
		parent,
		Vector3.new(length, height, width / 2),
		cf * CFrame.new(0, height / 2, -width / 4),
		style.roof,
		style.roofMaterial
	)
	Architecture.wedge(
		parent,
		Vector3.new(length, height, width / 2),
		cf * CFrame.new(0, height / 2, width / 4) * CFrame.Angles(0, math.pi, 0),
		style.roof,
		style.roofMaterial
	)
	Architecture.part(
		parent,
		Vector3.new(length + 0.4, 0.8, 0.8),
		cf * CFrame.new(0, height, 0),
		style.trim,
		style.trimMaterial,
		{ decor = true }
	)
end

-- Straight staircase rising toward -Z from `cf`.
function Architecture.stairs(
	parent: Instance,
	cf: CFrame,
	width: number,
	steps: number,
	rise: number,
	run: number,
	style: Style
)
	for i = 0, steps - 1 do
		Architecture.part(
			parent,
			Vector3.new(width, rise * (i + 1), run),
			cf * CFrame.new(0, rise * (i + 1) / 2, -run * (i + 0.5)),
			if i % 2 == 0 then style.stone else style.stoneDark,
			style.stoneMaterial
		)
	end
end

-- Lamp post (Angels) or ember brazier (Devils) with a light.
function Architecture.lamp(parent: Instance, cf: CFrame, style: Style)
	local glowPart: BasePart
	if style.towerTop == "spire" then
		Architecture.part(
			parent,
			Vector3.new(1.6, 1, 1.6),
			cf * CFrame.new(0, 0.5, 0),
			style.trim,
			style.trimMaterial
		)
		Architecture.cylinder(parent, 0.35, 11, cf * CFrame.new(0, 1, 0), style.trim, style.trimMaterial)
		glowPart = Architecture.part(
			parent,
			Vector3.new(1.8, 2.2, 1.8),
			cf * CFrame.new(0, 13, 0),
			style.glow,
			Enum.Material.Neon,
			{ decor = true, shape = Enum.PartType.Ball }
		)
		Architecture.part(
			parent,
			Vector3.new(2.4, 0.5, 2.4),
			cf * CFrame.new(0, 14.4, 0),
			style.trim,
			style.trimMaterial,
			{ decor = true }
		)
	else
		Architecture.cylinder(parent, 1.2, 5, cf, style.stoneDark, style.stoneMaterial)
		Architecture.cylinder(parent, 2.4, 1.2, cf * CFrame.new(0, 5, 0), style.trim, style.trimMaterial)
		glowPart = Architecture.part(
			parent,
			Vector3.new(3, 1.6, 3),
			cf * CFrame.new(0, 6.6, 0),
			style.glow,
			Enum.Material.Neon,
			{ decor = true, shape = Enum.PartType.Ball }
		)
		local fire = Instance.new("Fire")
		fire.Size = 5
		fire.Heat = 7
		fire.Color = style.glow
		fire.SecondaryColor = Color3.fromRGB(255, 200, 80)
		fire.Parent = glowPart
	end
	local light = Instance.new("PointLight")
	light.Color = style.light
	light.Range = 22
	light.Brightness = 1.6
	light.Shadows = false
	light.Parent = glowPart
end

-- Hanging banner on a crossbar (abstract emblem bands, no symbols).
function Architecture.banner(parent: Instance, cf: CFrame, width: number, height: number, style: Style)
	Architecture.part(
		parent,
		Vector3.new(width + 1.4, 0.6, 0.6),
		cf * CFrame.new(0, 0, 0),
		style.trim,
		style.trimMaterial,
		{ decor = true }
	)
	Architecture.part(
		parent,
		Vector3.new(width, height, 0.2),
		cf * CFrame.new(0, -height / 2, 0),
		style.cloth,
		Enum.Material.Fabric,
		{ decor = true }
	)
	Architecture.part(
		parent,
		Vector3.new(width * 0.6, height * 0.06, 0.25),
		cf * CFrame.new(0, -height * 0.35, -0.05),
		style.trim,
		style.trimMaterial,
		{ decor = true }
	)
	Architecture.part(
		parent,
		Vector3.new(width * 0.25, width * 0.25, 0.25),
		cf * CFrame.new(0, -height * 0.55, -0.05) * CFrame.Angles(0, 0, math.rad(45)),
		style.glow,
		Enum.Material.Neon,
		{ decor = true }
	)
	-- Pointed tail.
	Architecture.wedge(
		parent,
		Vector3.new(0.2, height * 0.18, width / 2),
		cf
			* CFrame.new(-width / 4, -height - height * 0.09, 0)
			* CFrame.Angles(math.rad(180), math.rad(90), 0),
		style.cloth,
		Enum.Material.Fabric,
		{ decor = true }
	)
	Architecture.wedge(
		parent,
		Vector3.new(0.2, height * 0.18, width / 2),
		cf
			* CFrame.new(width / 4, -height - height * 0.09, 0)
			* CFrame.Angles(math.rad(180), math.rad(-90), 0),
		style.cloth,
		Enum.Material.Fabric,
		{ decor = true }
	)
end

-- Crystal cluster (glowing shards).
function Architecture.crystals(parent: Instance, cf: CFrame, size: number, color: Color3)
	local shards = { { 0, 0, 1 }, { 0.5, 25, 0.7 }, { -0.5, -20, 0.6 }, { 0.2, 50, 0.45 } }
	for i, s in shards do
		local h = size * s[3]
		Architecture.part(
			parent,
			Vector3.new(size * 0.22, h, size * 0.22),
			cf
				* CFrame.new(s[1] * size * 0.3, 0, (i % 2 - 0.5) * size * 0.2)
				* CFrame.Angles(math.rad(s[2] * 0.4), math.rad(i * 37), math.rad(s[2]))
				* CFrame.new(0, h / 2, 0)
				* CFrame.Angles(0, math.rad(45), 0),
			color,
			Enum.Material.Neon,
			{ decor = true, transparency = 0.15 }
		)
	end
end

-- Puffy cloud of overlapping balls.
function Architecture.cloud(parent: Instance, center: Vector3, scale: number, seed: number)
	local rng = Random.new(seed)
	for _ = 1, 5 do
		local r = scale * rng:NextNumber(0.5, 1)
		Architecture.part(
			parent,
			Vector3.new(r * 2, r * 1.3, r * 2),
			CFrame.new(
				center
					+ Vector3.new(
						rng:NextNumber(-1, 1) * scale,
						rng:NextNumber(-0.2, 0.3) * scale,
						rng:NextNumber(-1, 1) * scale
					)
			),
			Color3.fromRGB(255, 255, 255),
			Enum.Material.SmoothPlastic,
			{ decor = true, shape = Enum.PartType.Ball, transparency = 0.12 }
		)
	end
end

-- Jagged rock spire (volcanic land / floating islands).
function Architecture.rockSpike(
	parent: Instance,
	cf: CFrame,
	height: number,
	width: number,
	color: Color3,
	material: Enum.Material,
	seed: number
)
	local rng = Random.new(seed)
	local tiers = 4
	local y = 0
	for i = 0, tiers - 1 do
		local t = i / tiers
		local w = width * (1 - t * 0.7)
		local h = height / tiers
		Architecture.part(
			parent,
			Vector3.new(w, h * 1.1, w * rng:NextNumber(0.7, 1)),
			cf
				* CFrame.new(rng:NextNumber(-0.1, 0.1) * w, y + h / 2, 0)
				* CFrame.Angles(
					math.rad(rng:NextNumber(-6, 6)),
					rng:NextNumber(0, math.pi),
					math.rad(rng:NextNumber(-6, 6))
				),
			color,
			material
		)
		y += h
	end
end

--------------------------------------------------------------------------------
-- Portal gate
--------------------------------------------------------------------------------

export type GateInfo = { label: string, opensIn: string, active: boolean }

-- Arch with a glowing portal surface and a name plate. Sealed portals are
-- dim, have a closed barrier and say when they open.
function Architecture.portalGate(parent: Instance, cf: CFrame, info: GateInfo, style: Style): BasePart
	local model = Instance.new("Model")
	model.Name = "Gate_" .. string.gsub(info.label, "%s", "")
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	-- Raised dais with steps.
	Architecture.part(
		model,
		Vector3.new(30, 1.2, 14),
		cf * CFrame.new(0, 0.6, 0),
		style.stoneDark,
		style.stoneMaterial
	)
	Architecture.part(
		model,
		Vector3.new(26, 1.2, 10),
		cf * CFrame.new(0, 1.8, 0),
		style.stone,
		style.stoneMaterial
	)
	local base = cf * CFrame.new(0, 2.4, 0)
	Architecture.arch(model, base, 16, 30, 4, 3, style)
	-- Portal surface.
	local surface = Architecture.part(
		model,
		Vector3.new(0.4, 22, 16),
		base * CFrame.new(0, 11.5, 0) * CFrame.Angles(0, math.rad(90), 0),
		style.glow,
		Enum.Material.Neon,
		{ decor = true, transparency = if info.active then 0.15 else 0.65 }
	)
	surface.Name = "PortalSurface"
	surface:SetAttribute("RC_Gate", info.label)
	-- Sealed: a physical barrier so nobody walks into a portal that does nothing yet.
	if not info.active then
		local barrier = Architecture.part(
			model,
			Vector3.new(16, 22, 1),
			base * CFrame.new(0, 11, 0),
			style.trim,
			Enum.Material.ForceField,
			{ transparency = 0.4, shadow = false }
		)
		barrier.Name = "SealedBarrier"
	end
	-- Pillar braziers.
	for _, side in { -1, 1 } do
		Architecture.crystals(model, base * CFrame.new(side * 13.5, 0, 3), 5, style.glow)
	end
	local light = Instance.new("PointLight")
	light.Color = style.glow
	light.Range = 26
	light.Brightness = if info.active then 2.5 else 1
	light.Parent = surface

	-- Name plate.
	local plate = Architecture.part(
		model,
		Vector3.new(18, 3.2, 0.6),
		base * CFrame.new(0, 31.5, -1),
		style.trim,
		style.trimMaterial,
		{ decor = true }
	)
	plate.Name = "NamePlate"
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 24
		gui.LightInfluence = 0
		local text = Instance.new("TextLabel")
		text.BackgroundTransparency = 1
		text.Size = UDim2.fromScale(1, 1)
		text.Text = string.upper(info.label)
		text.TextScaled = true
		text.FontFace = Font.new(Font.fromEnum(Enum.Font.Merriweather).Family, Enum.FontWeight.Bold)
		text.TextColor3 = if style.towerTop == "spire"
			then Color3.fromRGB(60, 40, 10)
			else Color3.fromRGB(255, 220, 190)
		text.Parent = gui
		gui.Parent = plate
	end
	if not info.active then
		local billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.fromOffset(220, 46)
		billboard.StudsOffset = Vector3.new(0, 0, 0)
		billboard.MaxDistance = 70
		billboard.LightInfluence = 0
		local text = Instance.new("TextLabel")
		text.BackgroundTransparency = 1
		text.Size = UDim2.fromScale(1, 1)
		text.Text = `Sealed\nOpens with the {info.opensIn}`
		text.TextSize = 16
		text.FontFace = Font.fromEnum(Enum.Font.GothamBold)
		text.TextColor3 = Color3.new(1, 1, 1)
		text.TextStrokeTransparency = 0.25
		text.Parent = billboard
		billboard.Parent = surface
	end
	model.Parent = parent
	return surface
end

return Architecture
