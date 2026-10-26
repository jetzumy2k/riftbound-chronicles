--!strict
--[[
	Kit — the part helpers every anime builder uses (PLAN.md D-100).

	Every piece is a built-in Roblox Part (block, ball, cylinder, wedge) or a
	Part with a built-in SpecialMesh sphere (an ellipsoid), coloured from the
	archetype palette, welded to a body part of the hidden R15 rig with a
	Weld (C0 = the offset in the body part's space, so it does not matter
	how the rig is posed while it is built), and made massless,
	non-colliding, non-queryable and non-touchable: it never changes
	movement, combat raycasts or hits.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnimeArchetypes = require(ReplicatedStorage.Shared.Definitions.AnimeArchetypes)

export type Shape = "Block" | "Ball" | "Cylinder" | "Ellipsoid" | "Wedge" | "CornerWedge"

export type Ctx = {
	folder: Folder,
	archetype: AnimeArchetypes.Archetype,
	-- The archetype palette with the player's skin and hair (Complexion).
	palette: { [string]: AnimeArchetypes.RGB },
	variant: string, -- head style: "Man" | "Woman"
	count: number,
}

export type Limb = { upper: BasePart?, lower: BasePart?, hand: BasePart? }
export type Leg = { upper: BasePart?, lower: BasePart?, foot: BasePart? }
export type Body = {
	head: BasePart?,
	upper: BasePart?,
	lower: BasePart?,
	root: BasePart?,
	arms: { [string]: Limb },
	legs: { [string]: Leg },
}

local Kit = {}

-- Right = +X on the rig, left = -X.
local SIDES: { [string]: number } = { Right = 1, Left = -1 }
table.freeze(SIDES)
Kit.SIDES = SIDES

-- Material per colour role (anything else: SmoothPlastic).
local MATERIAL: { [string]: Enum.Material } = {
	plate = Enum.Material.SmoothPlastic,
	plateShade = Enum.Material.SmoothPlastic,
	trim = Enum.Material.Metal,
	suit = Enum.Material.Fabric,
	cloth = Enum.Material.Fabric,
	gem = Enum.Material.Neon,
	glow = Enum.Material.Neon,
	blade = Enum.Material.Metal,
	grip = Enum.Material.Leather,
}
-- A little shine on polished pieces.
local REFLECTANCE: { [string]: number } = {
	plate = 0.08,
	trim = 0.15,
	blade = 0.25,
}

function Kit.color(ctx: Ctx, role: string): Color3
	local rgb = ctx.palette[role] or { 255, 0, 255 }
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

local function find(character: Model, name: string): BasePart?
	local part = character:FindFirstChild(name)
	return if part and part:IsA("BasePart") then part else nil
end

function Kit.readBody(character: Model): Body
	local body: Body = {
		head = find(character, "Head"),
		upper = find(character, "UpperTorso"),
		lower = find(character, "LowerTorso"),
		root = find(character, "HumanoidRootPart"),
		arms = {},
		legs = {},
	}
	for side in Kit.SIDES do
		body.arms[side] = {
			upper = find(character, `{side}UpperArm`),
			lower = find(character, `{side}LowerArm`),
			hand = find(character, `{side}Hand`),
		}
		body.legs[side] = {
			upper = find(character, `{side}UpperLeg`),
			lower = find(character, `{side}LowerLeg`),
			foot = find(character, `{side}Foot`),
		}
	end
	return body
end

--[[
	A piece of `role` colour welded to `anchor` at `offset` (anchor space).
	Sizes are the visible size: a Cylinder's axis is turned to run along
	the offset's Y, like every other shape here.
]]
function Kit.part(
	ctx: Ctx,
	anchor: BasePart,
	role: string,
	shape: Shape,
	size: Vector3,
	offset: CFrame
): BasePart
	local part: BasePart
	local frame = offset
	if shape == "Wedge" then
		part = Instance.new("WedgePart")
	elseif shape == "CornerWedge" then
		part = Instance.new("CornerWedgePart")
	else
		local p = Instance.new("Part")
		if shape == "Ball" then
			p.Shape = Enum.PartType.Ball
		elseif shape == "Cylinder" then
			p.Shape = Enum.PartType.Cylinder
			-- Roblox cylinders run along X; turn them to run along Y.
			size = Vector3.new(size.Y, size.X, size.Z)
			frame = offset * CFrame.Angles(0, 0, math.rad(90))
		elseif shape == "Ellipsoid" then
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = p
		end
		part = p
	end
	part.Name = role
	part.Size = Vector3.new(math.max(size.X, 0.05), math.max(size.Y, 0.05), math.max(size.Z, 0.05))
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = MATERIAL[role] or Enum.Material.SmoothPlastic
	part.Reflectance = REFLECTANCE[role] or 0
	part.Color = Kit.color(ctx, role)
	part:SetAttribute("RC_Role", role)
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = false
	part.CFrame = anchor.CFrame * frame
	local weld = Instance.new("Weld")
	weld.Part0 = anchor
	weld.Part1 = part
	weld.C0 = frame
	weld.Parent = part
	part.Parent = ctx.folder
	ctx.count += 1
	return part
end

function Kit.ellipsoid(ctx: Ctx, anchor: BasePart, role: string, size: Vector3, offset: CFrame): BasePart
	return Kit.part(ctx, anchor, role, "Ellipsoid", size, offset)
end

function Kit.block(ctx: Ctx, anchor: BasePart, role: string, size: Vector3, offset: CFrame): BasePart
	return Kit.part(ctx, anchor, role, "Block", size, offset)
end

-- A frame at `position` whose +Y runs along `up` and whose +Z leans toward
-- `toward` (made perpendicular to `up`).
function Kit.frame(position: Vector3, up: Vector3, toward: Vector3): CFrame
	local y = up.Unit
	local x = y:Cross(toward)
	if x.Magnitude < 1e-4 then
		x = y:Cross(Vector3.new(0, 0, 1))
		if x.Magnitude < 1e-4 then
			x = Vector3.new(1, 0, 0)
		end
	end
	x = x.Unit
	local z = x:Cross(y).Unit
	return CFrame.fromMatrix(position, x, y, z)
end

-- An ellipsoid running from `a` to `b` (anchor space), `width` across and
-- `depth` thick along `toward`.
function Kit.span(
	ctx: Ctx,
	anchor: BasePart,
	role: string,
	a: Vector3,
	b: Vector3,
	width: number,
	depth: number,
	toward: Vector3
): BasePart
	local length = (b - a).Magnitude
	return Kit.ellipsoid(
		ctx,
		anchor,
		role,
		Vector3.new(width, length, depth),
		Kit.frame((a + b) / 2, b - a, toward)
	)
end

-- A ring of `count` blocks around the offset's Y axis.
function Kit.ring(
	ctx: Ctx,
	anchor: BasePart,
	role: string,
	center: CFrame,
	radius: number,
	thickness: number,
	height: number,
	count: number
): { BasePart }
	local parts = {}
	local step = 2 * math.pi / count
	local length = 2 * radius * math.tan(step / 2) + thickness * 0.6
	for i = 0, count - 1 do
		local angle = i * step
		local at = center * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -radius)
		table.insert(parts, Kit.block(ctx, anchor, role, Vector3.new(length, height, thickness), at))
	end
	return parts
end

--[[
	A flat triangle a-b-c (anchor space) from two wedges, `thickness` thick
	(the classic two-wedge method: split at the foot of the height on the
	longest side).
]]
function Kit.triangle(
	ctx: Ctx,
	anchor: BasePart,
	role: string,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	thickness: number
)
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	-- Make b-c the longest side.
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local cross = ac:Cross(ab)
	if cross.Magnitude < 1e-4 then
		return
	end
	local right = cross.Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	Kit.part(
		ctx,
		anchor,
		role,
		"Wedge",
		Vector3.new(thickness, height, math.abs(ab:Dot(back))),
		CFrame.fromMatrix((a + b) / 2, right, up, back)
	)
	Kit.part(
		ctx,
		anchor,
		role,
		"Wedge",
		Vector3.new(thickness, height, math.abs(ac:Dot(back))),
		CFrame.fromMatrix((a + c) / 2, -right, up, -back)
	)
end

-- A small glowing gem in a trim setting, facing `offset`'s -Z.
function Kit.gem(ctx: Ctx, anchor: BasePart, size: number, offset: CFrame)
	Kit.ellipsoid(ctx, anchor, "trim", Vector3.new(size * 1.45, size * 1.45, size * 0.5), offset)
	Kit.ellipsoid(
		ctx,
		anchor,
		"gem",
		Vector3.new(size, size * 1.15, size * 0.55),
		offset * CFrame.new(0, 0, -size * 0.12)
	)
end

return Kit
