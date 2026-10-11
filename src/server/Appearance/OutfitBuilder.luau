--!strict
--[[
	OutfitBuilder — procedural fantasy outfits following the creator's concept
	sheets (docs/characters and gears/, PLAN.md D-35):

	  Warrior  heavy layered plate: cuirass with glowing crest, layered
	           pauldrons, tassets, vambraces, greaves, long cape, sword.
	  Healer   flowing robe with gold mantle, bell sleeves, sash, staff with a
	           glowing head.
	  Archer   light leather armour, chest strap, quiver, asymmetric half
	           cape, single pauldron, bow.
	  Mage     arcane coat with high collar, rune belt, bell sleeves, wand and
	           a floating tome.
	  (none)   recruit tunic while the job is not chosen yet (race preview).

	Race features: Angels get large layered feathered wings and a halo ring;
	Devils get bat wings with bone spars, curved horns and a tail. Colours come
	from the look palette (FacePresets) so server outfits and client previews
	match.

	Every piece is sized from the avatar's own body parts, welded to them (so
	it animates with the body), and is massless, non-colliding, non-queryable
	and non-touchable: it never affects movement, combat raycasts or hits.
	Approved Creator Store art replaces whole slots (Wardrobe).

	Fantasy-styled, modest and non-religious (CLAUDE.md §2/§3.1/§18,
	ART_DIRECTION.md §7).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FacePresets = require(ReplicatedStorage.Shared.Definitions.FacePresets)

local FOLDER_NAME = "RC_Outfit"

local MATERIAL_BY_ROLE: { [string]: Enum.Material } = {
	cloth = Enum.Material.Fabric,
	leather = Enum.Material.Leather,
	metal = Enum.Material.Metal,
	glow = Enum.Material.Neon,
	wing = Enum.Material.SmoothPlastic,
	horn = Enum.Material.SmoothPlastic,
	blade = Enum.Material.Metal,
	wood = Enum.Material.Wood,
}

type Options = {
	shape: Enum.PartType?,
	ellipsoid: boolean?,
	material: Enum.Material?,
	colorRole: string?,
}

type Ctx = {
	folder: Folder,
	preset: FacePresets.FacePreset,
	character: Model,
	race: string,
	skip: { [string]: boolean },
}

type Limb = { upper: BasePart?, lower: BasePart?, hand: BasePart? }
type Leg = { upper: BasePart?, lower: BasePart?, foot: BasePart? }

type Body = {
	head: BasePart?,
	upper: BasePart?,
	lower: BasePart?,
	arms: { [string]: Limb },
	legs: { [string]: Leg },
}

local OutfitBuilder = {}

OutfitBuilder.FOLDER_NAME = FOLDER_NAME
-- Slots approved art can replace (Wardrobe / PrepareAccessory).
OutfitBuilder.SLOTS = table.freeze({ "Body", "Cape", "Wings", "Halo", "Horns", "Tail", "Weapon" })

local SIDES: { [string]: number } = { Left = -1, Right = 1 }

--------------------------------------------------------------------------------
-- Primitives
--------------------------------------------------------------------------------

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function find(character: Model, ...: string): BasePart?
	for _, name in { ... } do
		local part = character:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			return part
		end
	end
	return nil
end

local function piece(
	ctx: Ctx,
	anchor: BasePart,
	role: string,
	size: Vector3,
	offset: CFrame,
	options: Options?
): Part
	local opts: Options = options or {}
	local part = Instance.new("Part")
	part.Name = role
	part.Size = Vector3.new(math.max(size.X, 0.05), math.max(size.Y, 0.05), math.max(size.Z, 0.05))
	if opts.shape then
		part.Shape = opts.shape
	end
	local colorRole = opts.colorRole or role
	part.Material = opts.material or MATERIAL_BY_ROLE[role] or Enum.Material.SmoothPlastic
	part.Color = rgb(FacePresets.roleColor(ctx.preset, colorRole))
	part:SetAttribute("RC_Role", colorRole)
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = false
	if opts.ellipsoid then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = part
	end
	part.CFrame = anchor.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = anchor
	weld.Part1 = part
	weld.Parent = part
	part.Parent = ctx.folder
	return part
end

-- Cylinder between two points given in the anchor's local space.
local function segment(
	ctx: Ctx,
	anchor: BasePart,
	role: string,
	a: Vector3,
	b: Vector3,
	thickness: number,
	options: Options?
)
	local delta = b - a
	local length = delta.Magnitude
	if length < 0.01 then
		return
	end
	local center = (a + b) / 2
	local up = if math.abs(delta.Unit.Y) > 0.95 then Vector3.zAxis else Vector3.yAxis
	local frame = CFrame.lookAt(center, b, up) * CFrame.Angles(0, math.rad(90), 0)
	local opts: Options = if options then table.clone(options) else {}
	opts.shape = Enum.PartType.Cylinder
	piece(ctx, anchor, role, Vector3.new(length, thickness, thickness), frame, opts)
end

-- Flat ellipsoid filling the triangle a / b / c (anchor space): wing membranes.
local function membrane(
	ctx: Ctx,
	anchor: BasePart,
	role: string,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	thickness: number
)
	local mid = (b + c) / 2
	local xAxis = b - c
	local yAxis = a - mid
	if xAxis.Magnitude < 0.01 or yAxis.Magnitude < 0.01 then
		return
	end
	local x = xAxis.Unit
	local z = x:Cross(yAxis.Unit)
	if z.Magnitude < 0.01 then
		return
	end
	z = z.Unit
	local y = z:Cross(x)
	local center = (a + b + c) / 3
	piece(
		ctx,
		anchor,
		role,
		Vector3.new(xAxis.Magnitude * 1.05, yAxis.Magnitude * 1.25, thickness),
		CFrame.fromMatrix(center, x, y, z),
		{ ellipsoid = true }
	)
end

-- Smooth ring of cylinder segments in the XZ plane of `frame` (anchor space).
local function ring(
	ctx: Ctx,
	anchor: BasePart,
	role: string,
	frame: CFrame,
	radius: number,
	thickness: number,
	count: number
)
	for i = 0, count - 1 do
		local a0 = (i / count) * math.pi * 2
		local a1 = ((i + 1) / count) * math.pi * 2
		local p0 = frame * Vector3.new(math.cos(a0) * radius, 0, math.sin(a0) * radius)
		local p1 = frame * Vector3.new(math.cos(a1) * radius, 0, math.sin(a1) * radius)
		local dir = (p1 - p0).Unit
		segment(ctx, anchor, role, p0 - dir * thickness * 0.3, p1 + dir * thickness * 0.3, thickness)
	end
end

-- Cylinder shell around a vertical limb segment.
local function sleeve(
	ctx: Ctx,
	limb: BasePart?,
	role: string,
	lengthScale: number,
	girth: number,
	yOffset: number?,
	options: Options?
)
	if limb == nil then
		return
	end
	local s = limb.Size
	local diameter = math.max(s.X, s.Z) * girth
	local opts: Options = if options then table.clone(options) else {}
	opts.shape = Enum.PartType.Cylinder
	piece(
		ctx,
		limb,
		role,
		Vector3.new(s.Y * lengthScale, diameter, diameter),
		CFrame.new(0, (yOffset or 0) * s.Y, 0) * CFrame.Angles(0, 0, math.rad(90)),
		opts
	)
end

local function shell(ctx: Ctx, part: BasePart?, role: string, scale: Vector3, options: Options?)
	if part then
		piece(ctx, part, role, part.Size * scale, CFrame.new(), options)
	end
end

local function gem(ctx: Ctx, anchor: BasePart, size: number, offset: CFrame)
	piece(
		ctx,
		anchor,
		"glow",
		Vector3.new(size, size, size * 0.4),
		offset * CFrame.Angles(0, 0, math.rad(45))
	)
end

-- Z offset in front of a part's surface (characters face -Z).
local function front(part: BasePart, extra: number): number
	return -(part.Size.Z / 2 + extra)
end

--------------------------------------------------------------------------------
-- Body lookup (R15, with R6 fallbacks)
--------------------------------------------------------------------------------

local function readBody(character: Model): Body
	local body: Body = {
		head = find(character, "Head"),
		upper = find(character, "UpperTorso", "Torso"),
		lower = find(character, "LowerTorso"),
		arms = {},
		legs = {},
	}
	for side in SIDES do
		body.arms[side] = {
			upper = find(character, `{side}UpperArm`, `{side} Arm`),
			lower = find(character, `{side}LowerArm`),
			hand = find(character, `{side}Hand`),
		}
		body.legs[side] = {
			upper = find(character, `{side}UpperLeg`, `{side} Leg`),
			lower = find(character, `{side}LowerLeg`),
			foot = find(character, `{side}Foot`),
		}
	end
	return body
end

--------------------------------------------------------------------------------
-- Shared layers
--------------------------------------------------------------------------------

local function belt(ctx: Ctx, body: Body, role: string, gems: number)
	local base = body.lower or body.upper
	if base == nil then
		return
	end
	local l = base.Size
	local y = if body.lower then l.Y * 0.3 else -l.Y * 0.42
	piece(ctx, base, role, Vector3.new(l.X * 1.16, 0.3, l.Z * 1.24), CFrame.new(0, y, 0))
	piece(ctx, base, "metal", Vector3.new(0.4, 0.34, 0.08), CFrame.new(0, y, front(base, l.Z * 0.12 + 0.04)))
	for i = 1, gems do
		local x = (i - (gems + 1) / 2) * l.X * 0.32
		gem(ctx, base, 0.16, CFrame.new(x, y, front(base, l.Z * 0.12 + 0.09)))
	end
end

local function gloves(ctx: Ctx, body: Body, role: string)
	for _, arm in body.arms do
		shell(ctx, arm.hand, role, Vector3.new(1.16, 1.12, 1.16))
	end
end

local function boots(ctx: Ctx, body: Body, role: string, tall: boolean)
	for _, leg in body.legs do
		local foot = leg.foot
		if foot then
			piece(
				ctx,
				foot,
				role,
				foot.Size * Vector3.new(1.18, 1.35, 1.16),
				CFrame.new(0, foot.Size.Y * 0.12, 0)
			)
		end
		if tall then
			sleeve(ctx, leg.lower, role, 0.75, 1.24, -0.12)
		end
	end
end

-- Long bell sleeves with gold cuffs (Healer / Mage).
local function bellSleeves(ctx: Ctx, body: Body)
	for _, arm in body.arms do
		sleeve(ctx, arm.upper, "cloth", 1.0, 1.2)
		sleeve(ctx, arm.lower, "cloth", 0.95, 1.5, -0.05)
		if arm.lower then
			local s = arm.lower.Size
			sleeve(ctx, arm.lower, "metal", 0.12, 1.62, -0.46)
			piece(
				ctx,
				arm.lower,
				"glow",
				Vector3.new(0.06, s.Y * 0.5, 0.06),
				CFrame.new(0, -s.Y * 0.1, front(arm.lower, s.Z * 0.24))
			)
		end
	end
end

-- Flared robe skirt from the waist with glowing hems.
local function robeSkirt(ctx: Ctx, body: Body, lengthScale: number, panels: number, openFront: boolean)
	local base = body.lower or body.upper
	if base == nil then
		return
	end
	local l = base.Size
	local top = if body.lower then -l.Y * 0.2 else -l.Y * 0.45
	local radius = math.max(l.X, l.Z) * 0.62
	local length = math.max(l.Y, 0.4) * lengthScale
	local flare = math.rad(9)
	for i = 0, panels - 1 do
		local angle = (i / panels) * math.pi * 2
		if openFront and i == 0 then
			continue -- angle 0 faces forward: leave the coat open at the front
		end
		local width = (2 * math.pi * radius / panels) * 1.25
		local around = CFrame.Angles(0, angle, 0)
		piece(
			ctx,
			base,
			"cloth",
			Vector3.new(width, length, 0.1),
			around * CFrame.new(0, top - length / 2, -radius) * CFrame.Angles(-flare, 0, 0)
		)
		piece(
			ctx,
			base,
			"glow",
			Vector3.new(width, 0.08, 0.12),
			around
				* CFrame.new(0, top - length + 0.06, -radius - length * math.sin(flare))
				* CFrame.Angles(-flare, 0, 0)
		)
	end
end

-- Shoulder mantle / capelet with a gold rim.
local function mantle(ctx: Ctx, body: Body, scale: number)
	local upper = body.upper
	if upper == nil then
		return
	end
	local u = upper.Size
	piece(
		ctx,
		upper,
		"cloth",
		Vector3.new(u.X * 1.32 * scale, u.Y * 0.42, u.Z * 1.55 * scale),
		CFrame.new(0, u.Y * 0.36, 0),
		{ ellipsoid = true }
	)
	piece(
		ctx,
		upper,
		"metal",
		Vector3.new(u.X * 1.36 * scale, 0.1, u.Z * 1.6 * scale),
		CFrame.new(0, u.Y * 0.26, 0),
		{ ellipsoid = true }
	)
end

local function cape(ctx: Ctx, body: Body, lengthScale: number, colorRole: string)
	local upper = body.upper
	if upper == nil or ctx.skip.Cape then
		return
	end
	local u = upper.Size
	local length = u.Y * lengthScale
	local tilt = CFrame.Angles(math.rad(7), 0, 0)
	piece(
		ctx,
		upper,
		"cloth",
		Vector3.new(u.X * 1.1, length, 0.08),
		CFrame.new(0, u.Y * 0.42 - length / 2, u.Z / 2 + 0.16) * tilt,
		{ colorRole = colorRole, material = Enum.Material.Fabric }
	)
	piece(
		ctx,
		upper,
		"glow",
		Vector3.new(u.X * 1.1, 0.1, 0.1),
		CFrame.new(0, u.Y * 0.42 - length + 0.05, u.Z / 2 + 0.16 + length * math.sin(math.rad(7))) * tilt
	)
end

--------------------------------------------------------------------------------
-- Job outfits
--------------------------------------------------------------------------------

local function warrior(ctx: Ctx, body: Body)
	local upper, lower = body.upper, body.lower
	if upper then
		local u = upper.Size
		-- Cuirass, central ridge, glowing crest and gorget.
		shell(ctx, upper, "metal", Vector3.new(1.12, 1.06, 1.2))
		piece(
			ctx,
			upper,
			"glow",
			Vector3.new(0.08, u.Y * 0.62, 0.08),
			CFrame.new(0, -u.Y * 0.05, front(upper, u.Z * 0.1 + 0.05))
		)
		gem(ctx, upper, 0.36, CFrame.new(0, u.Y * 0.15, front(upper, u.Z * 0.1 + 0.08)))
		piece(
			ctx,
			upper,
			"metal",
			Vector3.new(u.X * 0.72, 0.32, u.Z * 1.15),
			CFrame.new(0, u.Y * 0.5, 0),
			{ ellipsoid = true }
		)
	end
	if lower then
		local l = lower.Size
		shell(ctx, lower, "metal", Vector3.new(1.12, 1.1, 1.2))
		-- Front/back and side tassets.
		for _, z in { -1, 1 } do
			piece(
				ctx,
				lower,
				"metal",
				Vector3.new(l.X * 0.82, l.Y * 2.6, 0.12),
				CFrame.new(0, -l.Y * 1.35, z * (l.Z * 0.62)) * CFrame.Angles(math.rad(z * 6), 0, 0)
			)
			piece(
				ctx,
				lower,
				"glow",
				Vector3.new(l.X * 0.82, 0.07, 0.14),
				CFrame.new(0, -l.Y * 2.6, z * (l.Z * 0.62 + 0.1))
			)
		end
		for _, x in { -1, 1 } do
			piece(
				ctx,
				lower,
				"metal",
				Vector3.new(0.12, l.Y * 2.2, l.Z * 0.8),
				CFrame.new(x * (l.X * 0.6), -l.Y * 1.15, 0) * CFrame.Angles(0, 0, math.rad(-x * 8))
			)
		end
	end
	belt(ctx, body, "leather", 1)

	for side, sign in SIDES do
		local arm = body.arms[side]
		sleeve(ctx, arm.upper, "cloth", 1.0, 1.12)
		local upperArm = arm.upper
		if upperArm then
			local s = upperArm.Size
			-- Layered pauldrons with a glowing rim.
			piece(
				ctx,
				upperArm,
				"metal",
				Vector3.new(s.X * 2.2, s.Y * 0.5, s.Z * 2.1),
				CFrame.new(sign * s.X * 0.15, s.Y * 0.44, 0),
				{ ellipsoid = true }
			)
			piece(
				ctx,
				upperArm,
				"metal",
				Vector3.new(s.X * 1.9, s.Y * 0.36, s.Z * 1.85),
				CFrame.new(sign * s.X * 0.22, s.Y * 0.2, 0),
				{ ellipsoid = true }
			)
			piece(
				ctx,
				upperArm,
				"glow",
				Vector3.new(s.X * 2.25, 0.07, s.Z * 2.15),
				CFrame.new(sign * s.X * 0.15, s.Y * 0.32, 0),
				{ ellipsoid = true }
			)
			if ctx.race == "Angel" then
				for i = 0, 2 do
					piece(
						ctx,
						upperArm,
						"metal",
						Vector3.new(0.14, s.Y * (0.9 - i * 0.18), 0.32),
						CFrame.new(sign * s.X * (0.55 + i * 0.12), s.Y * 0.62, 0)
							* CFrame.Angles(0, 0, math.rad(-sign * (25 + i * 22))),
						{ ellipsoid = true }
					)
				end
			else
				for i = 0, 1 do
					piece(
						ctx,
						upperArm,
						"horn",
						Vector3.new(0.2, s.Y * (0.75 - i * 0.2), 0.2),
						CFrame.new(sign * s.X * (0.45 + i * 0.35), s.Y * 0.72, (i - 0.5) * 0.3)
							* CFrame.Angles(0, 0, math.rad(-sign * (20 + i * 25))),
						{ ellipsoid = true }
					)
				end
			end
		end
		sleeve(ctx, arm.lower, "metal", 0.7, 1.32, -0.1)
		local lowerArm = arm.lower
		if lowerArm then
			local s = lowerArm.Size
			piece(
				ctx,
				lowerArm,
				"metal",
				Vector3.new(s.X * 1.4, s.Y * 0.32, s.Z * 1.4),
				CFrame.new(0, s.Y * 0.45, 0),
				{ ellipsoid = true }
			)
		end

		local leg = body.legs[side]
		sleeve(ctx, leg.upper, "cloth", 1.0, 1.12)
		local thigh = leg.upper
		if thigh then
			piece(
				ctx,
				thigh,
				"metal",
				Vector3.new(thigh.Size.X * 0.95, thigh.Size.Y * 0.8, 0.14),
				CFrame.new(0, thigh.Size.Y * 0.05, front(thigh, 0.08))
			)
		end
		sleeve(ctx, leg.lower, "metal", 1.0, 1.26)
		local shin = leg.lower
		if shin then
			local s = shin.Size
			piece(
				ctx,
				shin,
				"metal",
				Vector3.new(s.X * 1.35, s.Y * 0.35, s.Z * 1.35),
				CFrame.new(0, s.Y * 0.5, front(shin, 0.02)),
				{ ellipsoid = true }
			)
			piece(
				ctx,
				shin,
				"glow",
				Vector3.new(0.07, s.Y * 0.6, 0.07),
				CFrame.new(0, 0, front(shin, s.Z * 0.14 + 0.05))
			)
		end
	end
	gloves(ctx, body, "metal")
	boots(ctx, body, "metal", false)
	cape(ctx, body, 3.1, "metal")
end

local function healer(ctx: Ctx, body: Body)
	shell(ctx, body.upper, "cloth", Vector3.new(1.1, 1.05, 1.18))
	shell(ctx, body.lower, "cloth", Vector3.new(1.12, 1.1, 1.2))
	local upper = body.upper
	if upper then
		local u = upper.Size
		piece(
			ctx,
			upper,
			"metal",
			Vector3.new(0.18, u.Y * 0.95, 0.06),
			CFrame.new(0, -u.Y * 0.02, front(upper, u.Z * 0.09 + 0.03))
		)
		gem(ctx, upper, 0.3, CFrame.new(0, u.Y * 0.22, front(upper, u.Z * 0.09 + 0.08)))
	end
	mantle(ctx, body, 1.0)
	belt(ctx, body, "metal", 3)
	robeSkirt(ctx, body, 5.4, 8, false)
	bellSleeves(ctx, body)
	for side, sign in SIDES do
		local upperArm = body.arms[side].upper
		if upperArm then
			local s = upperArm.Size
			piece(
				ctx,
				upperArm,
				"metal",
				Vector3.new(s.X * 1.7, s.Y * 0.32, s.Z * 1.7),
				CFrame.new(sign * s.X * 0.12, s.Y * 0.42, 0),
				{ ellipsoid = true }
			)
		end
		sleeve(ctx, body.legs[side].upper, "cloth", 1.0, 1.12)
	end
	gloves(ctx, body, "leather")
	boots(ctx, body, "leather", false)
end

local function archer(ctx: Ctx, body: Body)
	local upper = body.upper
	shell(ctx, upper, "leather", Vector3.new(1.1, 1.04, 1.16))
	shell(ctx, body.lower, "cloth", Vector3.new(1.1, 1.08, 1.16))
	if upper then
		local u = upper.Size
		-- Diagonal chest strap (front and back).
		for _, z in { -1, 1 } do
			local zz = z * (u.Z / 2 + u.Z * 0.09 + 0.05)
			segment(
				ctx,
				upper,
				"leather",
				Vector3.new(-u.X * 0.45, u.Y * 0.48, zz),
				Vector3.new(u.X * 0.45, -u.Y * 0.48, zz),
				0.18
			)
		end
		gem(ctx, upper, 0.22, CFrame.new(0, 0, front(upper, u.Z * 0.09 + 0.12)))
		-- Hood collar behind the neck.
		piece(
			ctx,
			upper,
			"cloth",
			Vector3.new(u.X * 0.95, u.Y * 0.5, u.Z * 1.0),
			CFrame.new(0, u.Y * 0.55, u.Z * 0.35),
			{ ellipsoid = true }
		)
		-- Quiver with glowing-fletched arrows.
		local quiverTop = Vector3.new(u.X * 0.35, u.Y * 0.95, u.Z / 2 + 0.35)
		local quiverBottom = Vector3.new(-u.X * 0.15, -u.Y * 0.5, u.Z / 2 + 0.32)
		local axis = (quiverTop - quiverBottom).Unit
		segment(ctx, upper, "leather", quiverBottom, quiverTop, 0.52)
		segment(ctx, upper, "metal", quiverTop - axis * 0.12, quiverTop, 0.58)
		for i = 0, 3 do
			local offset = Vector3.new((i - 1.5) * 0.1, 0, (i % 2) * 0.1)
			local tip = quiverTop + axis * 0.7 + offset
			segment(ctx, upper, "wood", quiverTop + offset, tip, 0.05)
			piece(
				ctx,
				upper,
				"glow",
				Vector3.new(0.12, 0.28, 0.04),
				CFrame.lookAt(tip, tip + axis) * CFrame.Angles(math.rad(90), 0, 0),
				{ ellipsoid = true }
			)
		end
	end
	belt(ctx, body, "leather", 1)
	-- Asymmetric half cape and a single pauldron on the left shoulder.
	local leftUpperArm = body.arms.Left.upper
	if upper and not ctx.skip.Cape then
		local u = upper.Size
		piece(
			ctx,
			upper,
			"cloth",
			Vector3.new(u.X * 0.6, u.Y * 1.9, 0.08),
			CFrame.new(-u.X * 0.3, -u.Y * 0.4, u.Z / 2 + 0.14) * CFrame.Angles(math.rad(6), 0, math.rad(4)),
			{ colorRole = "metal", material = Enum.Material.Fabric }
		)
	end
	if leftUpperArm then
		local s = leftUpperArm.Size
		piece(
			ctx,
			leftUpperArm,
			"metal",
			Vector3.new(s.X * 1.9, s.Y * 0.42, s.Z * 1.85),
			CFrame.new(-s.X * 0.15, s.Y * 0.42, 0),
			{ ellipsoid = true }
		)
		piece(
			ctx,
			leftUpperArm,
			"glow",
			Vector3.new(s.X * 1.95, 0.07, s.Z * 1.9),
			CFrame.new(-s.X * 0.15, s.Y * 0.3, 0),
			{ ellipsoid = true }
		)
	end
	for side in SIDES do
		local arm = body.arms[side]
		sleeve(ctx, arm.upper, "cloth", 1.0, 1.1)
		sleeve(ctx, arm.lower, "leather", 0.75, 1.3, -0.1)
		local leg = body.legs[side]
		sleeve(ctx, leg.upper, "cloth", 1.0, 1.1)
		local shin = leg.lower
		if shin then
			local s = shin.Size
			piece(
				ctx,
				shin,
				"leather",
				Vector3.new(s.X * 1.3, s.Y * 0.3, s.Z * 1.3),
				CFrame.new(0, s.Y * 0.5, front(shin, 0.02)),
				{ ellipsoid = true }
			)
		end
	end
	gloves(ctx, body, "leather")
	boots(ctx, body, "leather", true)
end

local function mage(ctx: Ctx, body: Body)
	local upper = body.upper
	shell(ctx, upper, "cloth", Vector3.new(1.1, 1.05, 1.18))
	shell(ctx, body.lower, "cloth", Vector3.new(1.12, 1.1, 1.2))
	if upper then
		local u = upper.Size
		-- High arcane collar: two flared plates behind the neck.
		for _, x in { -1, 1 } do
			local frame = CFrame.new(x * u.X * 0.22, u.Y * 0.78, u.Z * 0.32)
				* CFrame.Angles(math.rad(-12), math.rad(x * 22), math.rad(-x * 10))
			piece(
				ctx,
				upper,
				"cloth",
				Vector3.new(u.X * 0.42, u.Y * 0.62, 0.1),
				frame,
				{ colorRole = "metal" }
			)
			piece(
				ctx,
				upper,
				"glow",
				Vector3.new(u.X * 0.42, 0.06, 0.12),
				frame * CFrame.new(0, u.Y * 0.31, 0)
			)
		end
		-- Open coat lapels with gold piping.
		for _, x in { -1, 1 } do
			piece(
				ctx,
				upper,
				"metal",
				Vector3.new(0.1, u.Y * 0.95, 0.06),
				CFrame.new(x * u.X * 0.16, -u.Y * 0.02, front(upper, u.Z * 0.09 + 0.03))
			)
		end
		gem(ctx, upper, 0.3, CFrame.new(0, u.Y * 0.2, front(upper, u.Z * 0.09 + 0.08)))
	end
	mantle(ctx, body, 0.92)
	belt(ctx, body, "leather", 3)
	robeSkirt(ctx, body, 5.6, 7, true)
	bellSleeves(ctx, body)
	for side in SIDES do
		sleeve(ctx, body.legs[side].upper, "cloth", 1.0, 1.12)
	end
	gloves(ctx, body, "leather")
	boots(ctx, body, "leather", true)
end

-- Plain recruit tunic (no job yet, e.g. the realm preview).
local function recruit(ctx: Ctx, body: Body)
	shell(ctx, body.upper, "cloth", Vector3.new(1.08, 1.04, 1.14))
	shell(ctx, body.lower, "cloth", Vector3.new(1.1, 1.08, 1.16))
	local upper = body.upper
	if upper then
		gem(ctx, upper, 0.26, CFrame.new(0, upper.Size.Y * 0.1, front(upper, upper.Size.Z * 0.07 + 0.06)))
	end
	mantle(ctx, body, 0.9)
	belt(ctx, body, "leather", 1)
	for side in SIDES do
		sleeve(ctx, body.arms[side].upper, "cloth", 1.0, 1.12)
		sleeve(ctx, body.arms[side].lower, "cloth", 1.0, 1.12)
		sleeve(ctx, body.legs[side].upper, "cloth", 1.0, 1.12)
	end
	gloves(ctx, body, "leather")
	boots(ctx, body, "leather", true)
	cape(ctx, body, 2.4, "metal")
end

--------------------------------------------------------------------------------
-- Race features
--------------------------------------------------------------------------------

local function angelWings(ctx: Ctx, body: Body)
	local upper = body.upper
	if upper == nil then
		return
	end
	local u = upper.Size
	-- Three layered feather rows: primaries, secondaries, coverts.
	local rows = {
		{ count = 4, length = 3.4, width = 0.62, start = 18, step = 24, z = 0.0 },
		{ count = 3, length = 2.4, width = 0.7, start = 30, step = 26, z = -0.12 },
		{ count = 2, length = 1.5, width = 0.75, start = 42, step = 30, z = -0.24 },
	}
	for _, sign in SIDES do
		local root = CFrame.new(sign * u.X * 0.22, u.Y * 0.32, u.Z / 2 + 0.38)
			* CFrame.Angles(math.rad(16), math.rad(-sign * 14), 0)
		for _, row in rows do
			for i = 0, row.count - 1 do
				local length = u.Y * row.length * (1 - i * 0.1)
				local angle = math.rad(row.start + i * row.step)
				local frame = root * CFrame.Angles(0, 0, -sign * angle) * CFrame.new(0, length / 2, row.z)
				piece(
					ctx,
					upper,
					"wing",
					Vector3.new(u.Y * row.width, length, 0.12),
					frame,
					{ ellipsoid = true }
				)
			end
		end
		-- Glowing leading edge.
		local edgeStart = (root * CFrame.new(0, 0, 0.05)).Position
		local edgeEnd = (root * CFrame.Angles(0, 0, -sign * math.rad(20)) * CFrame.new(0, u.Y * 3.3, 0.05)).Position
		segment(ctx, upper, "glow", edgeStart, edgeEnd, 0.1)
	end
end

local function batWings(ctx: Ctx, body: Body)
	local upper = body.upper
	if upper == nil then
		return
	end
	local u = upper.Size
	local scale = u.Y
	for _, sign in SIDES do
		local root = Vector3.new(sign * u.X * 0.22, u.Y * 0.3, u.Z / 2 + 0.3)
		local wrist = root + Vector3.new(sign * 1.6, 1.5, 0.5) * scale
		segment(ctx, upper, "horn", root, wrist, 0.22)
		-- Finger spars fanning out from the wrist, glowing tips.
		local directions = {
			Vector3.new(sign * 1.4, 0.7, 0.2),
			Vector3.new(sign * 1.5, -0.4, 0.25),
			Vector3.new(sign * 1.1, -1.4, 0.25),
			Vector3.new(sign * 0.4, -1.9, 0.2),
		}
		local tips = {}
		for _, direction in directions do
			local tip = wrist + direction * scale
			segment(ctx, upper, "horn", wrist, tip, 0.12)
			piece(ctx, upper, "glow", Vector3.new(0.16, 0.16, 0.16), CFrame.new(tip), { ellipsoid = true })
			table.insert(tips, tip)
		end
		-- Membranes between spars and back to the body.
		table.insert(tips, root + Vector3.new(0, -0.4 * scale, 0))
		for i = 1, #tips - 1 do
			membrane(ctx, upper, "wing", wrist, tips[i], tips[i + 1], 0.06)
		end
	end
end

local function halo(ctx: Ctx, body: Body)
	local head = body.head
	if head == nil then
		return
	end
	local radius = math.max(head.Size.X, head.Size.Z) * 0.6
	local frame = CFrame.new(0, head.Size.Y / 2 + 0.6, 0.08) * CFrame.Angles(math.rad(-14), 0, 0)
	ring(ctx, head, "glow", frame, radius, 0.12, 14)
end

local function horns(ctx: Ctx, body: Body)
	local head = body.head
	if head == nil then
		return
	end
	local h = head.Size
	for _, sign in SIDES do
		local frame = CFrame.new(sign * h.X * 0.28, h.Y * 0.36, -h.Z * 0.05)
			* CFrame.Angles(math.rad(-10), 0, math.rad(-sign * 35))
		local segments = 5
		for j = 1, segments do
			local thickness = 0.34 - (j - 1) * 0.06
			local length = 0.36
			local role = if j == segments then "glow" else "horn"
			piece(
				ctx,
				head,
				role,
				Vector3.new(thickness, length + 0.1, thickness),
				frame * CFrame.new(0, length / 2, 0),
				{ ellipsoid = true }
			)
			if j < segments then
				piece(
					ctx,
					head,
					"metal",
					Vector3.new(thickness * 1.08, 0.06, thickness * 1.08),
					frame * CFrame.new(0, length * 0.9, 0),
					{ ellipsoid = true }
				)
			end
			-- Curve up, out and back.
			frame = frame * CFrame.new(0, length, 0) * CFrame.Angles(math.rad(24), 0, math.rad(sign * 12))
		end
	end
end

local function tail(ctx: Ctx, body: Body)
	local base = body.lower or body.upper
	if base == nil then
		return
	end
	local l = base.Size
	local frame = CFrame.new(0, -l.Y * 0.1, l.Z / 2 + 0.05) * CFrame.Angles(math.rad(125), 0, 0)
	for j = 1, 6 do
		local thickness = 0.26 - (j - 1) * 0.03
		local length = 0.44
		piece(
			ctx,
			base,
			"horn",
			Vector3.new(thickness, length + 0.06, thickness),
			frame * CFrame.new(0, length / 2, 0),
			{ ellipsoid = true }
		)
		frame = frame
			* CFrame.new(0, length, 0)
			* CFrame.Angles(math.rad(-12), 0, math.rad(if j % 2 == 0 then 6 else -6))
	end
	piece(
		ctx,
		base,
		"glow",
		Vector3.new(0.38, 0.38, 0.08),
		frame * CFrame.new(0, 0.14, 0) * CFrame.Angles(0, 0, math.rad(45))
	)
end

--------------------------------------------------------------------------------
-- Weapons (starter look per job; Phase 7 equipment replaces them)
--------------------------------------------------------------------------------

local function handOrArm(body: Body, side: string): BasePart?
	local arm = body.arms[side]
	return arm.hand or arm.lower or arm.upper
end

-- Weapon frames inside the hand: +Y runs from the grip toward the tip.
local FORWARD_GRIP = CFrame.new(0, -0.1, 0) * CFrame.Angles(math.rad(-110), 0, 0)
local VERTICAL_GRIP = CFrame.new(0, -0.05, -0.12)

local function sword(ctx: Ctx, body: Body)
	local hand = handOrArm(body, "Right")
	if hand == nil then
		return
	end
	local g = FORWARD_GRIP
	segment(
		ctx,
		hand,
		"leather",
		(g * CFrame.new(0, -0.55, 0)).Position,
		(g * CFrame.new(0, 0.45, 0)).Position,
		0.2
	)
	piece(ctx, hand, "metal", Vector3.new(0.3, 0.3, 0.3), g * CFrame.new(0, -0.62, 0), { ellipsoid = true })
	piece(ctx, hand, "metal", Vector3.new(1.4, 0.18, 0.3), g * CFrame.new(0, 0.55, 0))
	gem(ctx, hand, 0.22, g * CFrame.new(0, 0.55, -0.17))
	for _, x in { -1, 1 } do
		if ctx.race == "Angel" then
			piece(
				ctx,
				hand,
				"metal",
				Vector3.new(0.16, 0.7, 0.24),
				g * CFrame.new(x * 0.62, 0.78, 0) * CFrame.Angles(0, 0, math.rad(-x * 35)),
				{ ellipsoid = true }
			)
		else
			piece(
				ctx,
				hand,
				"horn",
				Vector3.new(0.14, 0.6, 0.14),
				g * CFrame.new(x * 0.7, 0.75, 0) * CFrame.Angles(0, 0, math.rad(-x * 30)),
				{ ellipsoid = true }
			)
		end
	end
	local bladeLength = 4.2
	piece(
		ctx,
		hand,
		"blade",
		Vector3.new(0.4, bladeLength, 0.08),
		g * CFrame.new(0, 0.64 + bladeLength / 2, 0)
	)
	piece(
		ctx,
		hand,
		"blade",
		Vector3.new(0.4, 0.6, 0.08),
		g * CFrame.new(0, 0.64 + bladeLength + 0.2, 0),
		{ ellipsoid = true }
	)
	piece(
		ctx,
		hand,
		"glow",
		Vector3.new(0.08, bladeLength * 0.85, 0.1),
		g * CFrame.new(0, 0.7 + bladeLength * 0.45, 0)
	)
end

local function staff(ctx: Ctx, body: Body)
	local hand = handOrArm(body, "Right")
	if hand == nil then
		return
	end
	local g = VERTICAL_GRIP
	segment(
		ctx,
		hand,
		"wood",
		(g * CFrame.new(0, -3.1, 0)).Position,
		(g * CFrame.new(0, 3.0, 0)).Position,
		0.2
	)
	for _, y in { -3.0, 0.4, 2.8 } do
		piece(
			ctx,
			hand,
			"metal",
			Vector3.new(0.28, 0.16, 0.28),
			g * CFrame.new(0, y, 0),
			{ ellipsoid = true }
		)
	end
	local head = g * CFrame.new(0, 3.55, 0)
	piece(ctx, hand, "glow", Vector3.new(0.55, 0.55, 0.55), head, { shape = Enum.PartType.Ball })
	if ctx.race == "Angel" then
		ring(ctx, hand, "metal", head * CFrame.Angles(math.rad(90), 0, 0), 0.62, 0.09, 10)
		for _, x in { -1, 1 } do
			piece(
				ctx,
				hand,
				"metal",
				Vector3.new(0.14, 0.9, 0.3),
				head * CFrame.new(x * 0.62, -0.2, 0) * CFrame.Angles(0, 0, math.rad(-x * 40)),
				{ ellipsoid = true }
			)
		end
	else
		for i = 0, 2 do
			piece(
				ctx,
				hand,
				"glow",
				Vector3.new(0.16, 1.0, 0.16),
				head
					* CFrame.Angles(0, math.rad(i * 120), 0)
					* CFrame.new(0.42, 0.1, 0)
					* CFrame.Angles(0, 0, math.rad(-22)),
				{ ellipsoid = true }
			)
		end
		ring(ctx, hand, "horn", head * CFrame.new(0, -0.35, 0), 0.4, 0.1, 8)
	end
end

local function bow(ctx: Ctx, body: Body)
	local hand = handOrArm(body, "Left")
	if hand == nil then
		return
	end
	local g = VERTICAL_GRIP
	local angel = ctx.race == "Angel"
	local points = {}
	local steps = 6
	for i = 0, steps do
		local t = (i / steps) * 2 - 1
		local z = -0.6 * (1 - t * t) - 0.15 * t ^ 4
		table.insert(points, (g * CFrame.new(0, t * 2.5, z)).Position)
	end
	for i = 1, #points - 1 do
		segment(ctx, hand, if angel then "metal" else "horn", points[i], points[i + 1], 0.16)
	end
	-- Glowing string and limb tips.
	segment(ctx, hand, "glow", points[1], points[#points], 0.04)
	for _, index in { 1, #points } do
		piece(ctx, hand, "glow", Vector3.new(0.2, 0.36, 0.2), CFrame.new(points[index]), { ellipsoid = true })
	end
	piece(
		ctx,
		hand,
		"leather",
		Vector3.new(0.26, 0.6, 0.26),
		g * CFrame.new(0, 0, -0.6),
		{ ellipsoid = true }
	)
	if not angel then
		for _, t in { -0.6, 0.6 } do
			local base = (g * CFrame.new(0, t * 2.5, -0.6 * (1 - t * t))).Position
			segment(ctx, hand, "horn", base, base + Vector3.new(0, t * 0.3, -0.5), 0.08)
		end
	end
end

local function wandAndTome(ctx: Ctx, body: Body)
	local hand = handOrArm(body, "Right")
	if hand then
		local g = FORWARD_GRIP
		segment(
			ctx,
			hand,
			"wood",
			(g * CFrame.new(0, -0.4, 0)).Position,
			(g * CFrame.new(0, 1.6, 0)).Position,
			0.12
		)
		piece(
			ctx,
			hand,
			"metal",
			Vector3.new(0.22, 0.2, 0.22),
			g * CFrame.new(0, 1.6, 0),
			{ ellipsoid = true }
		)
		piece(
			ctx,
			hand,
			"glow",
			Vector3.new(0.22, 0.55, 0.22),
			g * CFrame.new(0, 1.95, 0),
			{ ellipsoid = true }
		)
	end
	local base = body.lower or body.upper
	if base then
		-- Floating tome beside the left hip.
		local l = base.Size
		local frame = CFrame.new(-(l.X * 0.9 + 0.45), 0.2, -0.25)
			* CFrame.Angles(math.rad(-15), math.rad(30), math.rad(8))
		piece(ctx, base, "leather", Vector3.new(0.95, 1.25, 0.32), frame)
		piece(
			ctx,
			base,
			"cloth",
			Vector3.new(0.85, 1.15, 0.36),
			frame * CFrame.new(0.06, 0, 0),
			{ colorRole = "wing" }
		)
		gem(ctx, base, 0.32, frame * CFrame.new(0, 0, -0.19))
		for _, corner in { Vector2.new(-1, -1), Vector2.new(1, -1), Vector2.new(-1, 1), Vector2.new(1, 1) } do
			piece(
				ctx,
				base,
				"metal",
				Vector3.new(0.16, 0.16, 0.36),
				frame * CFrame.new(corner.X * 0.42, corner.Y * 0.56, 0)
			)
		end
	end
end

--------------------------------------------------------------------------------

--[[
	Builds the outfit into a new folder on `character`, replacing any previous
	one. `skip` lists slots provided by approved art; `job` picks the outfit
	(nil = recruit). Returns the folder, or nil if the preset is invalid.
]]
function OutfitBuilder.build(
	character: Model,
	race: string,
	preset: FacePresets.FacePreset,
	skip: { [string]: boolean }?,
	job: string?
): Folder?
	if preset.race ~= race then
		return nil
	end
	local existing = character:FindFirstChild(FOLDER_NAME)
	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	local ctx: Ctx =
		{ folder = folder, preset = preset, character = character, race = race, skip = skip or {} }
	local body = readBody(character)
	local function wants(slot: string): boolean
		return not ctx.skip[slot]
	end

	if wants("Body") then
		if job == "Warrior" then
			warrior(ctx, body)
		elseif job == "Healer" then
			healer(ctx, body)
		elseif job == "Archer" then
			archer(ctx, body)
		elseif job == "Mage" then
			mage(ctx, body)
		else
			recruit(ctx, body)
		end
	end

	if wants("Weapon") then
		if job == "Warrior" then
			sword(ctx, body)
		elseif job == "Healer" then
			staff(ctx, body)
		elseif job == "Archer" then
			bow(ctx, body)
		elseif job == "Mage" then
			wandAndTome(ctx, body)
		end
	end

	if race == "Angel" then
		if wants("Wings") then
			angelWings(ctx, body)
		end
		if wants("Halo") then
			halo(ctx, body)
		end
	else
		if wants("Wings") then
			batWings(ctx, body)
		end
		if wants("Horns") then
			horns(ctx, body)
		end
		if wants("Tail") then
			tail(ctx, body)
		end
	end

	folder.Parent = character
	return folder
end

return OutfitBuilder
