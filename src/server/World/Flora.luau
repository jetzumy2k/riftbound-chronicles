--!strict
--[[
	Flora — procedural plants for the war zones (Phases 12-13).

	Low part counts so a whole jungle streams well on mobile: trunks and
	roots collide (cover and terrain), leaves, ferns and vines are decor (no
	collision, queries or touches). Each plant takes a seed so every server
	builds the same forest.

	  palm        leaning palm with fronds and coconuts (Desert oasis, Jungle)
	  jungleTree  tall rainforest tree: buttress roots, branches, layered
	              canopy and hanging vines
	  fern        a low fan of leaves
	  bush        a couple of leafy mounds
	  lilyPad     a floating pad, sometimes with a flower
	  vine        a hanging vine strand (cliffs, bridges)
]]

local Architecture = require(script.Parent.Architecture)

local Flora = {}

local A = Architecture

local LEAF_GREENS = {
	Color3.fromRGB(46, 104, 44),
	Color3.fromRGB(58, 122, 48),
	Color3.fromRGB(38, 88, 50),
	Color3.fromRGB(78, 132, 54),
}
local BARK = Color3.fromRGB(104, 84, 64)
local BARK_PALE = Color3.fromRGB(138, 124, 104)

-- A block part shown as an ellipsoid (SpecialMesh sphere).
local function blob(
	parent: Instance,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material,
	collide: boolean
)
	local part = A.part(parent, size, cf, color, material, { decor = not collide })
	if not collide then
		-- Leaves still shade the ground: the forest floor reads darker.
		part.CastShadow = true
	end
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

local function leafGreen(rng: Random): Color3
	local base = LEAF_GREENS[rng:NextInteger(1, #LEAF_GREENS)]
	return base:Lerp(Color3.fromRGB(150, 170, 60), rng:NextNumber(0, 0.2))
end

function Flora.palm(parent: Instance, base: CFrame, height: number, seed: number)
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

-- Tall rainforest tree standing on `base` (ground level), about `height` tall.
function Flora.jungleTree(parent: Instance, base: CFrame, height: number, seed: number)
	local rng = Random.new(seed)
	local radius = height / 24 + rng:NextNumber(0, 0.5)
	local bark = BARK:Lerp(BARK_PALE, rng:NextNumber(0, 0.6))
	local cf = base * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)

	-- Buttress roots flaring out from the trunk (tall side against it).
	for i = 0, 2 do
		local a = i / 3 * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
		local out = Vector3.new(math.sin(a), 0, math.cos(a))
		local length = radius * 2.6
		local tall = radius * 3.2
		local p = cf.Position + out * (radius + length / 2 - 0.4) + Vector3.new(0, tall / 2 - 0.6, 0)
		A.wedge(
			parent,
			Vector3.new(radius * 0.5, tall, length),
			CFrame.lookAt(p, p + out),
			bark,
			Enum.Material.Wood
		)
	end

	-- Trunk: three tapering, slightly leaning segments.
	local trunkHeight = height * 0.72
	for i = 0, 2 do
		local length = trunkHeight / 3
		A.cylinder(
			parent,
			radius * (1 - i * 0.18),
			length + 0.4,
			cf,
			if i == 1 then bark:Lerp(Color3.new(0, 0, 0), 0.1) else bark,
			Enum.Material.Wood
		)
		cf = cf
			* CFrame.new(0, length, 0)
			* CFrame.Angles(rng:NextNumber(-0.05, 0.05), 0, rng:NextNumber(-0.05, 0.05))
	end
	local top = cf

	-- Two branches reaching out and up, each ending in a canopy layer.
	local canopy = height * 0.42
	local ends = { top * CFrame.new(0, height * 0.12, 0) }
	for i = 0, 1 do
		local yaw = i * math.pi + rng:NextNumber(-0.6, 0.6)
		local tilt = math.rad(rng:NextNumber(42, 58))
		local length = height * rng:NextNumber(0.24, 0.3)
		local from = top
			* CFrame.new(0, -height * 0.06 * i, 0)
			* CFrame.Angles(0, yaw, 0)
			* CFrame.Angles(tilt, 0, 0)
		A.cylinder(parent, radius * 0.42, length, from, bark, Enum.Material.Wood, { decor = true })
		table.insert(ends, from * CFrame.new(0, length, 0))
	end
	for i, at in ends do
		local size = canopy * (if i == 1 then 1 else rng:NextNumber(0.7, 0.85))
		blob(
			parent,
			Vector3.new(size, size * 0.42, size * rng:NextNumber(0.85, 1.1)),
			CFrame.new(at.Position + Vector3.new(0, size * 0.1, 0))
				* CFrame.Angles(0, rng:NextNumber(0, 3), 0),
			leafGreen(rng),
			Enum.Material.Grass,
			false
		)
	end
	-- A hanging vine from one branch.
	local hang = ends[2].Position
	local vineLength = height * rng:NextNumber(0.25, 0.4)
	A.part(
		parent,
		Vector3.new(0.3, vineLength, 0.3),
		CFrame.new(hang - Vector3.new(0, vineLength / 2 + canopy * 0.12, 0)),
		Color3.fromRGB(70, 110, 50),
		Enum.Material.Grass,
		{ decor = true }
	)
end

function Flora.fern(parent: Instance, base: CFrame, size: number, seed: number)
	local rng = Random.new(seed)
	local color = leafGreen(rng)
	for i = 0, 4 do
		local a = i / 5 * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
		local leaf = blob(
			parent,
			Vector3.new(size * 0.35, 0.2, size),
			base
				* CFrame.Angles(0, a, 0)
				* CFrame.Angles(math.rad(rng:NextNumber(18, 34)), 0, 0)
				* CFrame.new(0, 0, -size * 0.45),
			color:Lerp(Color3.new(0, 0, 0), rng:NextNumber(0, 0.15)),
			Enum.Material.Grass,
			false
		)
		leaf.CastShadow = false
	end
end

function Flora.bush(parent: Instance, base: CFrame, size: number, seed: number)
	local rng = Random.new(seed)
	for i = 0, 1 do
		local s = size * (1 - i * 0.3)
		blob(
			parent,
			Vector3.new(s, s * 0.6, s * rng:NextNumber(0.8, 1.1)),
			base * CFrame.new(i * size * 0.45, s * 0.22, rng:NextNumber(-1, 1)),
			leafGreen(rng),
			Enum.Material.Grass,
			false
		)
	end
end

function Flora.lilyPad(parent: Instance, at: CFrame, size: number, seed: number)
	local rng = Random.new(seed)
	A.cylinder(
		parent,
		size / 2,
		0.15,
		at,
		Color3.fromRGB(70, 130, 60):Lerp(Color3.fromRGB(110, 150, 60), rng:NextNumber()),
		Enum.Material.Grass,
		{ decor = true }
	)
	if rng:NextNumber() < 0.35 then
		A.part(
			parent,
			Vector3.new(0.9, 0.7, 0.9),
			at * CFrame.new(rng:NextNumber(-0.5, 0.5), 0.4, rng:NextNumber(-0.5, 0.5)),
			if rng:NextNumber() < 0.5 then Color3.fromRGB(240, 150, 200) else Color3.fromRGB(250, 240, 250),
			Enum.Material.SmoothPlastic,
			{ decor = true, shape = Enum.PartType.Ball }
		)
	end
end

-- A strand hanging down from `top` (world position), `length` studs.
function Flora.vine(parent: Instance, top: Vector3, length: number, seed: number)
	local rng = Random.new(seed)
	A.part(
		parent,
		Vector3.new(rng:NextNumber(0.3, 0.6), length, rng:NextNumber(0.3, 0.6)),
		CFrame.new(top - Vector3.new(0, length / 2, 0)) * CFrame.Angles(0, rng:NextNumber(0, 3), 0),
		Color3.fromRGB(60, 104, 44):Lerp(Color3.fromRGB(96, 130, 60), rng:NextNumber()),
		Enum.Material.Grass,
		{ decor = true }
	)
end

return Flora
