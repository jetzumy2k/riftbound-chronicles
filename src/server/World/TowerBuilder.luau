--!strict
--[[
	TowerBuilder — the sealed arena of one Tower Challenge run (PLAN.md
	D-131). Built when a run starts, destroyed when it ends.

	A round stone hall: floor top at `origin`, a ring wall with no way
	out, pillars with braziers and a glowing rune circle in the middle,
	coloured by the floor's level band. Markers (invisible, non-colliding):
	  Arrival   where the players arrive (facing the middle)
	The creatures spawn around the rune circle (TowerBuilder.spawnPoint).
]]

local TowerBuilder = {}

TowerBuilder.RADIUS = 62
local WALL_HEIGHT = 34
local SEGMENTS = 28
local PILLARS = 8

-- Per band: stone, trim, light.
local THEMES = {
	{ Color3.fromRGB(96, 100, 112), Color3.fromRGB(120, 170, 255), Color3.fromRGB(150, 200, 255) },
	{ Color3.fromRGB(70, 52, 46), Color3.fromRGB(255, 120, 50), Color3.fromRGB(255, 160, 90) },
	{ Color3.fromRGB(150, 165, 180), Color3.fromRGB(150, 220, 255), Color3.fromRGB(190, 230, 255) },
	{ Color3.fromRGB(60, 56, 78), Color3.fromRGB(190, 140, 255), Color3.fromRGB(200, 170, 255) },
	{ Color3.fromRGB(56, 36, 34), Color3.fromRGB(255, 90, 40), Color3.fromRGB(255, 140, 80) },
	{ Color3.fromRGB(34, 34, 56), Color3.fromRGB(120, 200, 255), Color3.fromRGB(170, 150, 255) },
}

local function part(parent: Instance, props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(p :: any)[key] = value
	end
	p.Parent = parent
	return p
end

local function light(parent: BasePart, color: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = parent
end

--[[
	Builds the arena for band `band` (1-6) with its floor centre at
	`origin`. Returns the model (named Tower_<name>).
]]
function TowerBuilder.build(name: string, origin: Vector3, band: number): Model
	local theme = THEMES[math.clamp(band, 1, #THEMES)]
	local stone, trim, glow = theme[1], theme[2], theme[3]
	local model = Instance.new("Model")
	model.Name = `Tower_{name}`
	local r = TowerBuilder.RADIUS

	-- Floor: a thick disc, a darker ring and the rune circle.
	part(model, {
		Name = "Floor",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(6, r * 2 + 8, r * 2 + 8),
		CFrame = CFrame.new(origin - Vector3.new(0, 3, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Material = Enum.Material.Slate,
		Color = stone,
	})
	part(model, {
		Name = "Ring",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, r * 1.2, r * 1.2),
		CFrame = CFrame.new(origin + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Material = Enum.Material.Cobblestone,
		Color = stone:Lerp(Color3.new(0, 0, 0), 0.35),
		CanCollide = false,
	})
	local rune = part(model, {
		Name = "Rune",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.25, 22, 22),
		CFrame = CFrame.new(origin + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Material = Enum.Material.Neon,
		Color = trim,
		Transparency = 0.45,
		CanCollide = false,
	})
	light(rune, glow, 40, 1.5)

	-- Ring wall: segments with a trim band, no gaps.
	local segment = 2 * math.pi * r / SEGMENTS + 1
	for i = 1, SEGMENTS do
		local a = (i / SEGMENTS) * math.pi * 2
		local cf = CFrame.new(origin) * CFrame.Angles(0, a, 0) * CFrame.new(0, WALL_HEIGHT / 2, -r - 2)
		part(model, {
			Name = "Wall",
			Size = Vector3.new(segment, WALL_HEIGHT, 4),
			CFrame = cf,
			Material = Enum.Material.Slate,
			Color = stone,
		})
		part(model, {
			Name = "Trim",
			Size = Vector3.new(segment, 0.8, 0.6),
			CFrame = cf * CFrame.new(0, -WALL_HEIGHT / 2 + 6, 2.2),
			Material = Enum.Material.Neon,
			Color = trim,
			Transparency = 0.3,
			CanCollide = false,
		})
	end

	-- Pillars with braziers.
	for i = 1, PILLARS do
		local a = (i / PILLARS) * math.pi * 2 + math.pi / PILLARS
		local at = origin + Vector3.new(math.sin(a) * (r - 8), 0, math.cos(a) * (r - 8))
		part(model, {
			Name = "Pillar",
			Size = Vector3.new(5, 22, 5),
			CFrame = CFrame.new(at + Vector3.new(0, 11, 0)),
			Material = Enum.Material.Slate,
			Color = stone:Lerp(Color3.new(1, 1, 1), 0.1),
		})
		local bowl = part(model, {
			Name = "Brazier",
			Size = Vector3.new(4, 1.2, 4),
			CFrame = CFrame.new(at + Vector3.new(0, 22.6, 0)),
			Material = Enum.Material.Metal,
			Color = Color3.fromRGB(50, 46, 44),
		})
		local flame = part(model, {
			Name = "Flame",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(2.6, 2.6, 2.6),
			CFrame = bowl.CFrame + Vector3.new(0, 1.6, 0),
			Material = Enum.Material.Neon,
			Color = glow,
			CanCollide = false,
		})
		light(flame, glow, 34, 1.4)
	end

	local arrival = part(model, {
		Name = "Arrival",
		Size = Vector3.new(4, 1, 4),
		CFrame = CFrame.lookAt(origin + Vector3.new(0, 3, r - 14), origin + Vector3.new(0, 3, 0)),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
	arrival:SetAttribute("RC_Marker", true)
	return model
end

-- Where creature `i` of `count` stands (ground CFrame facing the arrival).
function TowerBuilder.spawnPoint(origin: Vector3, i: number, count: number): CFrame
	local a = (i / math.max(1, count)) * math.pi * 2
	local radius = if count == 1 then 0 else 14 + (i % 2) * 6
	local at = origin + Vector3.new(math.sin(a) * radius, 0, math.cos(a) * radius - 10)
	return CFrame.lookAt(at, Vector3.new(origin.X, at.Y, origin.Z + TowerBuilder.RADIUS))
end

-- Arrival spot `i` of a party (spread out side by side).
function TowerBuilder.arrival(origin: Vector3, i: number): CFrame
	local r = TowerBuilder.RADIUS
	local at = origin + Vector3.new((i - 1) * 5 - 7.5, 4, r - 14)
	return CFrame.lookAt(at, Vector3.new(origin.X, at.Y, origin.Z))
end

-- Whether `position` is inside the arena of `origin` (with some slack).
function TowerBuilder.inside(origin: Vector3, position: Vector3): boolean
	local d = position - origin
	return Vector3.new(d.X, 0, d.Z).Magnitude <= TowerBuilder.RADIUS + 12 and math.abs(d.Y) < 80
end

return TowerBuilder
