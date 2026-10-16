--!strict
--[[
	CreatureBuilder — procedural creature rigs for mobs and bosses
	(CLAUDE.md §18, Phase 9; Phase 16 may swap in authored meshes).

	Every creature is a Model with:
	  HumanoidRootPart  invisible collision box the Humanoid walks with
	  Humanoid          WalkSpeed / HipHeight; tripping states disabled
	  limbs             body parts on Motor6D joints named after the part
	                    ("LegFL", "Head", "WingL", ...) so the client can
	                    animate them (MobVisualController) with Transform
	Attributes: RC_Body (body plan), RC_Enemy (definition id).

	Stylised, non-graphic: rift-crystal glow instead of wounds, no gore.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EnemyDefinitions = require(ReplicatedStorage.Shared.Definitions.EnemyDefinitions)

local CreatureBuilder = {}

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

type Ctx = {
	model: Model,
	root: BasePart,
	scale: number,
	color: Color3,
	dark: Color3,
	glow: Color3,
}

local function newPart(
	ctx: Ctx,
	name: string,
	size: Vector3,
	color: Color3,
	material: Enum.Material,
	shape: Enum.PartType?
): Part
	local part = Instance.new("Part")
	part.Name = name
	if shape then
		part.Shape = shape
	end
	part.Size = size * ctx.scale
	part.Color = color
	part.Material = material
	part.CanCollide = false
	part.CanTouch = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = ctx.model
	return part
end

--[[
	A limb on a Motor6D: `pivot` is the joint position relative to the root,
	`offset` the part centre relative to the joint (both unscaled), `tilt`
	an optional resting rotation of the part about its joint.
]]
local function limb(
	ctx: Ctx,
	name: string,
	size: Vector3,
	pivot: Vector3,
	offset: Vector3,
	color: Color3,
	material: Enum.Material,
	tilt: CFrame?,
	shape: Enum.PartType?
): Part
	local part = newPart(ctx, name, size, color, material, shape)
	local s = ctx.scale
	local joint = CFrame.new(pivot * s) * (tilt or CFrame.identity)
	part.CFrame = ctx.root.CFrame * joint * CFrame.new(offset * s)
	local motor = Instance.new("Motor6D")
	motor.Name = name
	motor.Part0 = ctx.root
	motor.Part1 = part
	motor.C0 = joint
	motor.C1 = CFrame.new(-offset * s)
	motor.Parent = ctx.root
	return part
end

-- A decoration welded to `to` at `offset` (unscaled, in `to`'s frame).
local function attach(
	ctx: Ctx,
	to: BasePart,
	name: string,
	size: Vector3,
	offset: CFrame,
	color: Color3,
	material: Enum.Material,
	shape: Enum.PartType?
): Part
	local part = newPart(ctx, name, size, color, material, shape)
	part.CFrame = to.CFrame * (offset.Rotation + offset.Position * ctx.scale)
	part.CanQuery = false
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = to
	weld.Part1 = part
	weld.Parent = part
	return part
end

-- Rounds a part into an ellipsoid that fills its box (built-in mesh, free).
local function round<T>(part: T): T
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part :: any
	return part
end

-- Ellipsoid decoration welded to `to`.
local function oval(
	ctx: Ctx,
	to: BasePart,
	name: string,
	size: Vector3,
	offset: CFrame,
	color: Color3,
	material: Enum.Material
): Part
	return round(attach(ctx, to, name, size, offset, color, material))
end

local function eyes(ctx: Ctx, head: BasePart, y: number, z: number, spread: number, size: number)
	for _, side in { -1, 1 } do
		local eye = attach(
			ctx,
			head,
			"Eye",
			Vector3.new(size, size * 0.75, size * 0.6),
			CFrame.new(side * spread, y, z),
			ctx.glow,
			Enum.Material.Neon,
			Enum.PartType.Ball
		)
		eye.CastShadow = false
	end
end

local function crystals(ctx: Ctx, on: BasePart, points: { Vector3 }, height: number)
	for i, p in points do
		local spike = attach(
			ctx,
			on,
			"Crystal",
			Vector3.new(0.35, height * (0.7 + (i % 3) * 0.2), 0.35),
			CFrame.new(p)
				* CFrame.Angles(math.rad(-15 + i * 9), math.rad(i * 40), math.rad((i % 2) * 20 - 10)),
			ctx.glow,
			Enum.Material.Neon
		)
		spike.Transparency = 0.1
		spike.CastShadow = false
	end
end

--------------------------------------------------------------------------------
-- Body plans (Option A, PLAN.md D-40: rounded procedural forms. Ellipsoids
-- for bodies and limbs; wedges only where a point is wanted: ears.)
--------------------------------------------------------------------------------

local function wolf(ctx: Ctx): (Vector3, number)
	local fur = Enum.Material.Fabric
	local light = ctx.color:Lerp(Color3.new(1, 1, 1), 0.18)
	local body = round(
		limb(ctx, "Body", Vector3.new(2.0, 1.75, 3.4), Vector3.new(0, 0.3, 0.2), Vector3.zero, ctx.color, fur)
	)
	oval(ctx, body, "Chest", Vector3.new(2.25, 2.15, 1.9), CFrame.new(0, 0.15, -1.45), ctx.color, fur)
	oval(ctx, body, "Haunch", Vector3.new(1.95, 1.75, 1.6), CFrame.new(0, 0.05, 1.45), ctx.color, fur)
	oval(ctx, body, "Belly", Vector3.new(1.5, 0.9, 2.8), CFrame.new(0, -0.55, 0), light, fur)
	oval(
		ctx,
		body,
		"Neck",
		Vector3.new(1.3, 1.35, 1.7),
		CFrame.new(0, 0.75, -2.25) * CFrame.Angles(math.rad(-32), 0, 0),
		ctx.color,
		fur
	)
	-- Ruff of thicker fur behind the head.
	oval(ctx, body, "Ruff", Vector3.new(2.0, 1.4, 1.0), CFrame.new(0, 0.55, -1.9), ctx.dark, fur)

	local head = round(
		limb(
			ctx,
			"Head",
			Vector3.new(1.45, 1.25, 1.45),
			Vector3.new(0, 0.95, -1.95),
			Vector3.new(0, 0.25, -0.75),
			ctx.color,
			fur
		)
	)
	oval(
		ctx,
		head,
		"Snout",
		Vector3.new(0.8, 0.66, 1.3),
		CFrame.new(0, -0.22, -1.0) * CFrame.Angles(math.rad(6), 0, 0),
		light,
		fur
	)
	oval(ctx, head, "Jaw", Vector3.new(0.66, 0.3, 1.0), CFrame.new(0, -0.5, -0.8), ctx.dark, fur)
	attach(
		ctx,
		head,
		"Nose",
		Vector3.new(0.34, 0.26, 0.28),
		CFrame.new(0, -0.08, -1.62),
		Color3.fromRGB(20, 20, 24),
		Enum.Material.SmoothPlastic,
		Enum.PartType.Ball
	)
	for _, side in { -1, 1 } do
		attach(
			ctx,
			head,
			"Ear",
			Vector3.new(0.38, 0.75, 0.3),
			CFrame.new(side * 0.45, 0.8, 0.2) * CFrame.Angles(math.rad(-10), 0, math.rad(side * -18)),
			ctx.dark,
			fur
		)
	end
	eyes(ctx, head, 0.22, -0.6, 0.36, 0.26)

	local legs: { { any } } = {
		{ "LegFL", -0.72, -1.4 },
		{ "LegFR", 0.72, -1.4 },
		{ "LegBL", -0.72, 1.4 },
		{ "LegBR", 0.72, 1.4 },
	}
	for _, leg in legs do
		local thigh = round(
			limb(
				ctx,
				leg[1],
				Vector3.new(0.75, 1.5, 0.9),
				Vector3.new(leg[2], -0.2, leg[3]),
				Vector3.new(0, -0.55, 0),
				ctx.color,
				fur
			)
		)
		oval(ctx, thigh, "Shin", Vector3.new(0.42, 1.4, 0.48), CFrame.new(0, -1.25, 0.08), ctx.dark, fur)
		oval(ctx, thigh, "Paw", Vector3.new(0.58, 0.32, 0.85), CFrame.new(0, -1.95, -0.1), ctx.dark, fur)
	end

	local tail = round(
		limb(
			ctx,
			"Tail",
			Vector3.new(0.5, 0.5, 1.2),
			Vector3.new(0, 0.65, 1.95),
			Vector3.new(0, 0.1, 0.55),
			ctx.color,
			fur,
			CFrame.Angles(math.rad(25), 0, 0)
		)
	)
	oval(ctx, tail, "TailMid", Vector3.new(0.44, 0.44, 1.0), CFrame.new(0, 0.1, 1.15), ctx.color, fur)
	oval(ctx, tail, "TailTip", Vector3.new(0.32, 0.32, 0.8), CFrame.new(0, 0.15, 1.9), light, fur)
	crystals(
		ctx,
		body,
		{ Vector3.new(0, 0.95, -0.7), Vector3.new(0.3, 0.95, 0.2), Vector3.new(-0.3, 0.9, 1.0) },
		1.1
	)
	-- Root size, standing height of the root centre.
	return Vector3.new(2, 2, 3.6), 2.45
end

local function beetle(ctx: Ctx): (Vector3, number)
	local slate = Enum.Material.Slate
	local shell = round(
		limb(
			ctx,
			"Body",
			Vector3.new(3.8, 2.2, 4.6),
			Vector3.new(0, 0.45, 0),
			Vector3.zero,
			ctx.color,
			Enum.Material.Glass
		)
	)
	shell.Reflectance = 0.12
	oval(ctx, shell, "Seam", Vector3.new(0.14, 2.24, 4.45), CFrame.identity, ctx.dark, slate)
	oval(ctx, shell, "Underside", Vector3.new(3.1, 1.0, 3.9), CFrame.new(0, -0.65, 0), ctx.dark, slate)
	local head = round(
		limb(
			ctx,
			"Head",
			Vector3.new(1.8, 1.15, 1.45),
			Vector3.new(0, 0.2, -2.15),
			Vector3.new(0, 0, -0.55),
			ctx.dark,
			slate
		)
	)
	for _, side in { -1, 1 } do
		oval(
			ctx,
			head,
			"Mandible",
			Vector3.new(0.3, 0.28, 1.25),
			CFrame.new(side * 0.45, -0.3, -0.95) * CFrame.Angles(0, math.rad(side * -28), 0),
			ctx.dark,
			slate
		)
		oval(
			ctx,
			head,
			"Antenna",
			Vector3.new(0.1, 0.1, 1.3),
			CFrame.new(side * 0.35, 0.45, -0.85) * CFrame.Angles(math.rad(30), math.rad(side * -20), 0),
			ctx.dark,
			slate
		)
	end
	eyes(ctx, head, 0.2, -0.6, 0.5, 0.28)
	local index = 0
	for _, z in { -1.2, 0, 1.2 } do
		for _, side in { -1, 1 } do
			index += 1
			local femur = round(
				limb(
					ctx,
					`Leg{index}`,
					Vector3.new(0.34, 1.3, 0.34),
					Vector3.new(side * 1.5, 0, z),
					Vector3.new(0, -0.55, 0),
					ctx.dark,
					slate,
					CFrame.Angles(0, 0, math.rad(side * 55))
				)
			)
			oval(
				ctx,
				femur,
				"Tibia",
				Vector3.new(0.26, 1.4, 0.26),
				CFrame.new(side * 0.45, -1.35, 0) * CFrame.Angles(0, 0, math.rad(side * -55)),
				ctx.dark,
				slate
			)
		end
	end
	crystals(ctx, shell, {
		Vector3.new(0, 1.0, -0.8),
		Vector3.new(0.6, 0.9, 0.4),
		Vector3.new(-0.6, 0.9, 0.5),
		Vector3.new(0, 1.0, 1.2),
	}, 1.5)
	return Vector3.new(3, 1.6, 3.6), 2.0
end

local function biped(ctx: Ctx, knight: boolean): (Vector3, number)
	local stone = Enum.Material.Slate
	local torso = round(
		limb(
			ctx,
			"Body",
			Vector3.new(3.5, 3.1, 2.3),
			Vector3.new(0, 0.9, 0),
			Vector3.new(0, 0.7, 0),
			ctx.color,
			stone
		)
	)
	oval(ctx, torso, "Abdomen", Vector3.new(2.5, 1.6, 1.9), CFrame.new(0, -1.35, 0), ctx.dark, stone)
	attach(
		ctx,
		torso,
		"Core",
		Vector3.new(0.85, 0.85, 0.85),
		CFrame.new(0, 0.2, -1.05),
		ctx.glow,
		Enum.Material.Neon,
		Enum.PartType.Ball
	).CastShadow =
		false
	for _, side in { -1, 1 } do
		oval(
			ctx,
			torso,
			"Shoulder",
			Vector3.new(1.7, 1.5, 1.7),
			CFrame.new(side * 1.85, 1.05, 0),
			ctx.dark,
			stone
		)
	end
	local head = round(
		limb(
			ctx,
			"Head",
			Vector3.new(1.45, 1.4, 1.5),
			Vector3.new(0, 2.65, 0),
			Vector3.new(0, 0.7, 0),
			ctx.dark,
			stone
		)
	)
	-- Heavy brow over the glowing eyes.
	oval(ctx, head, "Brow", Vector3.new(1.5, 0.45, 0.8), CFrame.new(0, 0.25, -0.5), ctx.color, stone)
	eyes(ctx, head, 0.02, -0.68, 0.3, 0.26)
	if knight then
		attach(
			ctx,
			head,
			"Crest",
			Vector3.new(0.3, 0.9, 1.6),
			CFrame.new(0, 0.95, 0.1),
			ctx.glow,
			Enum.Material.Neon
		).CastShadow =
			false
		for _, side in { -1, 1 } do
			oval(
				ctx,
				torso,
				"Pauldron",
				Vector3.new(2.0, 1.1, 2.1),
				CFrame.new(side * 2.0, 1.55, 0) * CFrame.Angles(0, 0, math.rad(side * -16)),
				ctx.color,
				stone
			)
		end
	end
	for _, side in { -1, 1 } do
		local name = if side < 0 then "ArmL" else "ArmR"
		local arm = round(
			limb(
				ctx,
				name,
				Vector3.new(1.2, 2.0, 1.2),
				Vector3.new(side * 2.2, 2.1, 0),
				Vector3.new(0, -0.8, 0),
				ctx.color,
				stone
			)
		)
		oval(ctx, arm, "Forearm", Vector3.new(1.3, 2.0, 1.3), CFrame.new(0, -1.4, 0), ctx.dark, stone)
		oval(ctx, arm, "Fist", Vector3.new(1.5, 1.3, 1.5), CFrame.new(0, -2.6, 0), ctx.color, stone)
		if knight and side > 0 then
			-- Stone greatsword held point-down and forward, with a glowing fuller.
			local tilt = math.rad(70)
			local length = 4.6
			local along = CFrame.new(0, -2.6, -0.2) * CFrame.Angles(tilt, 0, 0)
			attach(
				ctx,
				arm,
				"Blade",
				Vector3.new(0.4, length, 1.2),
				along * CFrame.new(0, -length / 2 - 0.3, 0),
				ctx.dark,
				stone
			)
			attach(
				ctx,
				arm,
				"BladeGlow",
				Vector3.new(0.45, length * 0.85, 0.3),
				along * CFrame.new(0, -length / 2 - 0.3, 0),
				ctx.glow,
				Enum.Material.Neon
			).CastShadow =
				false
			attach(
				ctx,
				arm,
				"Guard",
				Vector3.new(0.6, 0.5, 2.6),
				along * CFrame.new(0, -0.3, 0),
				ctx.glow,
				Enum.Material.Neon
			).CastShadow =
				false
		end
	end
	for _, side in { -1, 1 } do
		local name = if side < 0 then "LegL" else "LegR"
		local thigh = round(
			limb(
				ctx,
				name,
				Vector3.new(1.4, 1.8, 1.4),
				Vector3.new(side * 0.85, -0.2, 0),
				Vector3.new(0, -0.7, 0),
				ctx.color,
				stone
			)
		)
		oval(ctx, thigh, "Shin", Vector3.new(1.3, 1.8, 1.3), CFrame.new(0, -1.3, 0), ctx.dark, stone)
		oval(ctx, thigh, "Foot", Vector3.new(1.5, 0.6, 2.0), CFrame.new(0, -2.2, -0.3), ctx.color, stone)
	end
	crystals(
		ctx,
		torso,
		{ Vector3.new(0.6, 1.2, 0.9), Vector3.new(-0.6, 1.4, 0.9), Vector3.new(0, 0.6, 1.1) },
		1.6
	)
	return Vector3.new(2.4, 2.4, 1.6), 3.2
end

local function sprite(ctx: Ctx): (Vector3, number)
	local body = limb(
		ctx,
		"Body",
		Vector3.new(1.5, 1.5, 1.5),
		Vector3.zero,
		Vector3.zero,
		ctx.color,
		Enum.Material.Glass,
		nil,
		Enum.PartType.Ball
	)
	body.Transparency = 0.35
	local core = attach(
		ctx,
		body,
		"Core",
		Vector3.new(0.8, 0.8, 0.8),
		CFrame.identity,
		ctx.glow,
		Enum.Material.Neon,
		Enum.PartType.Ball
	)
	core.CastShadow = false
	local light = Instance.new("PointLight")
	light.Color = ctx.glow
	light.Range = 8
	light.Brightness = 1
	light.Parent = core
	eyes(ctx, body, 0.15, -0.66, 0.25, 0.22)
	for _, side in { -1, 1 } do
		local wing = round(
			limb(
				ctx,
				if side < 0 then "WingL" else "WingR",
				Vector3.new(1.7, 1.15, 0.08),
				Vector3.new(side * 0.5, 0.3, 0.3),
				Vector3.new(side * 0.8, 0.2, 0),
				ctx.glow,
				Enum.Material.Neon
			)
		)
		wing.Transparency = 0.45
		wing.CastShadow = false
	end
	return Vector3.new(1.2, 1.2, 1.2), 3.2
end

--[[
	Builds an unparented creature for `enemyId`, standing with its feet at
	`at` (ground point, facing its -Z). Returns nil for unknown ids.
]]
function CreatureBuilder.build(enemyId: string, at: CFrame): Model?
	local enemy = EnemyDefinitions.get(enemyId)
	if enemy == nil then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = enemy.name
	model:SetAttribute("RC_Body", enemy.body)
	model:SetAttribute("RC_Enemy", enemy.id)

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Transparency = 1
	root.CanCollide = true
	root.CanTouch = false
	root.CFrame = at
	root.Parent = model

	local color = rgb(enemy.color)
	local ctx: Ctx = {
		model = model,
		root = root,
		scale = enemy.scale,
		color = color,
		dark = color:Lerp(Color3.new(0, 0, 0), 0.35),
		glow = rgb(enemy.glow),
	}
	local rootSize, height
	local body = enemy.body
	if body == "Wolf" then
		rootSize, height = wolf(ctx)
	elseif body == "Beetle" then
		rootSize, height = beetle(ctx)
	elseif body == "Golem" then
		rootSize, height = biped(ctx, false)
	elseif body == "Guardian" then
		rootSize, height = biped(ctx, true)
	else
		rootSize, height = sprite(ctx)
	end
	local s = enemy.scale
	root.Size = rootSize * s
	-- Lift everything so the root centre stands `height` above the ground.
	model.PrimaryPart = root
	model:PivotTo(at * CFrame.new(0, height * s, 0))

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = height * s - root.Size.Y / 2
	humanoid.WalkSpeed = enemy.moveSpeed
	humanoid.DisplayName = if enemy.elite then `{enemy.name} ★` else enemy.name
	humanoid.NameDisplayDistance = 60
	humanoid.HealthDisplayDistance = 60
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOn
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	for _, state in
		{
			Enum.HumanoidStateType.FallingDown,
			Enum.HumanoidStateType.Ragdoll,
			Enum.HumanoidStateType.Climbing,
			Enum.HumanoidStateType.Swimming,
			Enum.HumanoidStateType.Seated,
			Enum.HumanoidStateType.Dead,
		}
	do
		humanoid:SetStateEnabled(state, false)
	end
	humanoid.Parent = model
	return model
end

return CreatureBuilder
