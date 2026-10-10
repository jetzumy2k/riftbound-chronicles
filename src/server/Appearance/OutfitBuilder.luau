--!strict
--[[
	OutfitBuilder
	Procedural fantasy outfit built on top of a player's avatar until approved
	Creator Store / catalog art replaces it (see Wardrobe):

	  All races : tunic, chest plate with glowing crest, belt and buckle,
	              pauldrons, bracers, gloves, greaves, boots, cape.
	  Angels    : long robe panels, feathered wings, ring of light.
	  Devils    : armoured tassets, curved horns, bat-like wings, tail.

	Every piece is sized from the avatar's own body parts (so it fits any body
	scale), welded to that part (so it follows animations), and is massless,
	non-colliding and non-queryable (never affects movement, combat raycasts or
	hit detection). Each part carries an "RC_Role" attribute; colours come from
	the shared FacePresets palette so server outfits and client previews match.

	Non-graphic, fantasy-styled shapes only (CLAUDE.md §18/§19, PLAN.md PC-1).
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
}

type Options = {
	shape: Enum.PartType?,
	sphereMesh: boolean?,
	material: Enum.Material?,
	-- Colour role when it differs from the part role (e.g. a metal-coloured cape).
	colorRole: string?,
}

type Ctx = {
	folder: Folder,
	-- Slots supplied by approved art; the procedural version is skipped.
	skip: { [string]: boolean },
	preset: FacePresets.FacePreset,
	character: Model,
}

local OutfitBuilder = {}

OutfitBuilder.FOLDER_NAME = FOLDER_NAME

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function bodyPart(character: Model, ...: string): BasePart?
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
	part.Material = opts.material or MATERIAL_BY_ROLE[role] or Enum.Material.SmoothPlastic
	local colorRole = opts.colorRole or role
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

	if opts.sphereMesh then
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

-- Cylinder sleeve around a vertical limb segment.
local function sleeve(
	ctx: Ctx,
	limb: BasePart,
	role: string,
	lengthScale: number,
	girth: number,
	yOffset: number?
)
	local s = limb.Size
	local diameter = math.max(s.X, s.Z) * girth
	piece(
		ctx,
		limb,
		role,
		Vector3.new(s.Y * lengthScale, diameter, diameter),
		CFrame.new(0, (yOffset or 0) * s.Y, 0) * CFrame.Angles(0, 0, math.rad(90)),
		{ shape = Enum.PartType.Cylinder }
	)
end

--------------------------------------------------------------------------------
-- Shared armour
--------------------------------------------------------------------------------

local function buildTorso(ctx: Ctx, race: string)
	local upper = bodyPart(ctx.character, "UpperTorso", "Torso")
	local lower = bodyPart(ctx.character, "LowerTorso")
	if upper == nil then
		return
	end
	local u = upper.Size

	-- Tunic shell and breastplate with a glowing crest.
	piece(ctx, upper, "cloth", u * Vector3.new(1.08, 1.04, 1.14), CFrame.new())
	piece(
		ctx,
		upper,
		"metal",
		Vector3.new(u.X * 0.86, u.Y * 0.72, 0.16),
		CFrame.new(0, u.Y * 0.08, -(u.Z / 2 + 0.1))
	)
	piece(ctx, upper, "glow", Vector3.new(u.X * 0.62, 0.07, 0.06), CFrame.new(0, u.Y * 0.3, -(u.Z / 2 + 0.2)))
	piece(
		ctx,
		upper,
		"glow",
		Vector3.new(0.24, 0.24, 0.06),
		CFrame.new(0, u.Y * 0.02, -(u.Z / 2 + 0.2)) * CFrame.Angles(0, 0, math.rad(45))
	)

	local base = lower or upper
	local l = base.Size
	local beltY = if lower then l.Y * 0.3 else -u.Y * 0.42
	if lower then
		piece(ctx, lower, "cloth", l * Vector3.new(1.1, 1.06, 1.16), CFrame.new())
	end
	piece(ctx, base, "leather", Vector3.new(l.X * 1.14, 0.28, l.Z * 1.2), CFrame.new(0, beltY, 0))
	piece(ctx, base, "metal", Vector3.new(0.34, 0.26, 0.08), CFrame.new(0, beltY, -(l.Z * 0.6 + 0.04)))

	if race == "Angel" then
		-- Flowing robe panels front and back.
		for _, side in { -1, 1 } do
			piece(
				ctx,
				base,
				"cloth",
				Vector3.new(l.X * 1.02, l.Y * 1.7, 0.1),
				CFrame.new(0, beltY - l.Y * 0.9, side * (l.Z * 0.6 + 0.06))
			)
		end
	else
		-- Short armoured tassets.
		for _, side in { -1, 1 } do
			piece(
				ctx,
				base,
				"metal",
				Vector3.new(l.X * 0.92, l.Y * 1.05, 0.12),
				CFrame.new(0, beltY - l.Y * 0.62, side * (l.Z * 0.6 + 0.07))
			)
		end
	end
end

-- Cape hanging from the shoulders, tinted with the look's metal colour.
local function buildCape(ctx: Ctx)
	local upper = bodyPart(ctx.character, "UpperTorso", "Torso")
	if upper == nil then
		return
	end
	local u = upper.Size
	piece(
		ctx,
		upper,
		"cloth",
		Vector3.new(u.X * 1.04, u.Y * 2.5, 0.08),
		CFrame.new(0, -u.Y * 0.7, u.Z / 2 + 0.14) * CFrame.Angles(math.rad(6), 0, 0),
		{ colorRole = "metal", material = Enum.Material.Fabric }
	)
end

local function buildArms(ctx: Ctx)
	for _, side in { "Left", "Right" } do
		local sign = if side == "Left" then -1 else 1
		local upperArm = bodyPart(ctx.character, `{side}UpperArm`, `{side} Arm`)
		local lowerArm = bodyPart(ctx.character, `{side}LowerArm`)
		local hand = bodyPart(ctx.character, `{side}Hand`)

		if upperArm then
			local s = upperArm.Size
			sleeve(ctx, upperArm, "cloth", 1.0, 1.14)
			-- Rounded pauldron over the shoulder.
			piece(
				ctx,
				upperArm,
				"metal",
				Vector3.new(s.X * 1.9, s.Y * 0.42, s.Z * 1.9),
				CFrame.new(sign * s.X * 0.12, s.Y * 0.4, 0),
				{ sphereMesh = true }
			)
			piece(
				ctx,
				upperArm,
				"glow",
				Vector3.new(s.X * 1.95, 0.06, s.Z * 1.95),
				CFrame.new(sign * s.X * 0.12, s.Y * 0.3, 0),
				{ sphereMesh = true }
			)
		end
		if lowerArm then
			sleeve(ctx, lowerArm, "cloth", 1.0, 1.12)
			sleeve(ctx, lowerArm, "metal", 0.62, 1.3, -0.12)
		end
		if hand then
			piece(ctx, hand, "leather", hand.Size * 1.14, CFrame.new())
		end
	end
end

local function buildLegs(ctx: Ctx)
	for _, side in { "Left", "Right" } do
		local upperLeg = bodyPart(ctx.character, `{side}UpperLeg`, `{side} Leg`)
		local lowerLeg = bodyPart(ctx.character, `{side}LowerLeg`)
		local foot = bodyPart(ctx.character, `{side}Foot`)

		if upperLeg then
			sleeve(ctx, upperLeg, "cloth", 1.0, 1.12)
		end
		if lowerLeg then
			local s = lowerLeg.Size
			sleeve(ctx, lowerLeg, "leather", 1.0, 1.14)
			piece(
				ctx,
				lowerLeg,
				"metal",
				Vector3.new(s.X * 0.84, s.Y * 0.78, 0.12),
				CFrame.new(0, s.Y * 0.05, -(s.Z / 2 + 0.08))
			)
		end
		if foot then
			local s = foot.Size
			piece(ctx, foot, "leather", s * Vector3.new(1.16, 1.3, 1.14), CFrame.new(0, s.Y * 0.12, 0))
		end
	end
end

--------------------------------------------------------------------------------
-- Race features
--------------------------------------------------------------------------------

-- Fan of feather/blade shapes behind the shoulders.
local function buildWings(ctx: Ctx, race: string)
	local upper = bodyPart(ctx.character, "UpperTorso", "Torso")
	if upper == nil then
		return
	end
	local u = upper.Size
	local isAngel = race == "Angel"
	local count = if isAngel then 5 else 4
	local baseLength = u.Y * (if isAngel then 2.5 else 2.2)
	local width = u.Y * (if isAngel then 0.55 else 0.32)

	for _, side in { -1, 1 } do
		local root = CFrame.new(side * u.X * 0.22, u.Y * 0.28, u.Z / 2 + 0.3)
			* CFrame.Angles(math.rad(14), 0, 0)
		for i = 1, count do
			local length = baseLength * (1 - (i - 1) * 0.14)
			local angle = math.rad(22 + (i - 1) * (if isAngel then 22 else 26))
			local offset = root * CFrame.Angles(0, 0, -side * angle) * CFrame.new(0, length / 2, 0)
			piece(ctx, upper, "wing", Vector3.new(width, length, 0.12), offset, { sphereMesh = true })
			if not isAngel then
				-- Bony spar along each membrane blade.
				piece(
					ctx,
					upper,
					"horn",
					Vector3.new(length, 0.09, 0.09),
					offset * CFrame.new(-side * width * 0.42, 0, 0) * CFrame.Angles(0, 0, math.rad(90)),
					{ shape = Enum.PartType.Cylinder }
				)
			end
		end
		if isAngel then
			-- Glowing inner edge.
			piece(
				ctx,
				upper,
				"glow",
				Vector3.new(0.08, baseLength * 0.9, 0.06),
				root * CFrame.Angles(0, 0, -side * math.rad(30)) * CFrame.new(0, baseLength * 0.45, -0.05),
				{ sphereMesh = true }
			)
		end
	end
end

local function buildHalo(ctx: Ctx)
	local head = bodyPart(ctx.character, "Head")
	if head == nil then
		return
	end
	local beads = 16
	local radius = math.max(head.Size.X, head.Size.Z) * 0.62
	local center = CFrame.new(0, head.Size.Y / 2 + 0.55, 0) * CFrame.Angles(math.rad(-12), 0, 0)
	for i = 1, beads do
		local angle = (i / beads) * math.pi * 2
		piece(
			ctx,
			head,
			"glow",
			Vector3.new(0.17, 0.17, 0.17),
			center * CFrame.new(math.cos(angle) * radius, 0, math.sin(angle) * radius),
			{ shape = Enum.PartType.Ball }
		)
	end
end

local function buildHorns(ctx: Ctx)
	local head = bodyPart(ctx.character, "Head")
	if head == nil then
		return
	end
	local h = head.Size
	local segments = 4
	for _, side in { -1, 1 } do
		local cframe = CFrame.new(side * h.X * 0.26, h.Y * 0.38, -h.Z * 0.08)
			* CFrame.Angles(0, 0, math.rad(-side * 22))
		for j = 1, segments do
			local thickness = 0.3 - (j - 1) * 0.055
			local length = 0.32
			local role = if j == segments then "glow" else "horn"
			piece(
				ctx,
				head,
				role,
				Vector3.new(thickness, length + 0.08, thickness),
				cframe * CFrame.new(0, length / 2, 0),
				{ sphereMesh = true }
			)
			-- Curve upward, outward and back.
			cframe = cframe * CFrame.new(0, length, 0) * CFrame.Angles(math.rad(28), 0, math.rad(-side * 8))
		end
	end
end

local function buildTail(ctx: Ctx)
	local base = bodyPart(ctx.character, "LowerTorso", "Torso")
	if base == nil then
		return
	end
	local l = base.Size
	local cframe = CFrame.new(0, -l.Y * 0.1, l.Z / 2 + 0.05) * CFrame.Angles(math.rad(120), 0, 0)
	local segments = 6
	for j = 1, segments do
		local thickness = 0.26 - (j - 1) * 0.03
		local length = 0.42
		piece(
			ctx,
			base,
			"horn",
			Vector3.new(thickness, length + 0.06, thickness),
			cframe * CFrame.new(0, length / 2, 0),
			{ sphereMesh = true }
		)
		cframe = cframe * CFrame.new(0, length, 0) * CFrame.Angles(math.rad(-12), 0, 0)
	end
	-- Spade-shaped glowing tip.
	piece(
		ctx,
		base,
		"glow",
		Vector3.new(0.34, 0.34, 0.08),
		cframe * CFrame.new(0, 0.12, 0) * CFrame.Angles(0, 0, math.rad(45))
	)
end

--------------------------------------------------------------------------------

-- Outfit slots. Approved accessories tagged with one of these (RC_Slot
-- attribute) replace the matching procedural pieces.
OutfitBuilder.SLOTS = table.freeze({ "Body", "Cape", "Wings", "Halo", "Horns", "Tail" })

--[[
	Builds the outfit into a new folder on `character`, replacing any previous
	one. `skip` lists slots provided by approved art. Returns the folder (or nil
	if the preset is invalid).
]]
function OutfitBuilder.build(
	character: Model,
	race: string,
	preset: FacePresets.FacePreset,
	skip: { [string]: boolean }?
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
	local ctx: Ctx = { folder = folder, preset = preset, character = character, skip = skip or {} }
	local function wants(slot: string): boolean
		return not ctx.skip[slot]
	end

	if wants("Body") then
		buildTorso(ctx, race)
		buildArms(ctx)
		buildLegs(ctx)
	end
	if wants("Cape") then
		buildCape(ctx)
	end
	if wants("Wings") then
		buildWings(ctx, race)
	end
	if race == "Angel" then
		if wants("Halo") then
			buildHalo(ctx)
		end
	else
		if wants("Horns") then
			buildHorns(ctx)
		end
		if wants("Tail") then
			buildTail(ctx)
		end
	end

	folder.Parent = character
	return folder
end

return OutfitBuilder
