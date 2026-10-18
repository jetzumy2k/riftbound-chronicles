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
	Skeleton (D-51): the "Body" part rides on the root; legs, necks, heads,
	arms, tails and wings joint to the Body (or to the bone before them), so
	the whole creature moves together. Legs are three bones (upper "LegFL",
	lower "LegFLb", foot "LegFLc"; Animation/CreatureRigs) built in their
	standing pose, solved by Logic/CreatureIK; the upper joint carries the
	rest angles (attribute RestAngles) for the client's foot planting.
	Body plans: Wolf, Beetle, Golem / Guardian (bipeds), Sprite, Serpent.
	Traits (EnemyDefinitions.Trait) add a myth's anatomy: three heads, a
	mane, horns, wings, a serpent tail, spines, a crest. Elites get fangs
	and claws.
	Attributes: RC_Body (body plan), RC_Enemy (definition id), RC_Scale.

	Stylised, non-graphic: rift-crystal glow instead of wounds, no gore.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EnemyDefinitions = require(ReplicatedStorage.Shared.Definitions.EnemyDefinitions)
local CreatureRigs = require(ReplicatedStorage.Shared.Animation.CreatureRigs)
local CreatureIK = require(ReplicatedStorage.Shared.Logic.CreatureIK)
local CreatureMeshes = require(ReplicatedStorage.Shared.Animation.CreatureMeshes)

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
	-- Extra anatomy (EnemyDefinitions.Trait) and boss detailing.
	traits: { [string]: boolean },
	elite: boolean,
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

--[[
	A limb jointed to another limb (tails, necks, wing tips, jaws): `joint`
	is the joint in `parent`'s frame (position unscaled), `offset` the part
	centre relative to the joint. The animator bends the chain joint by joint.
]]
local function chain(
	ctx: Ctx,
	parent: BasePart,
	name: string,
	size: Vector3,
	joint: CFrame,
	offset: Vector3,
	color: Color3,
	material: Enum.Material
): Part
	local part = newPart(ctx, name, size, color, material)
	local s = ctx.scale
	local j = CFrame.new(joint.Position * s) * joint.Rotation
	part.CFrame = parent.CFrame * j * CFrame.new(offset * s)
	local motor = Instance.new("Motor6D")
	motor.Name = name
	motor.Part0 = parent
	motor.Part1 = part
	motor.C0 = j
	motor.C1 = CFrame.new(-offset * s)
	motor.Parent = parent
	return round(part)
end

export type LegParts = { upper: Part, lower: Part, foot: Part }

--[[
	A three-bone leg on `body` from its CreatureRigs spec, in its standing
	pose (foot on flat ground). Returns the bones for decoration.
]]
local function rigLeg(
	ctx: Ctx,
	body: BasePart,
	plan: CreatureRigs.Plan,
	leg: CreatureRigs.Leg,
	color: Color3,
	dark: Color3,
	material: Enum.Material
): LegParts
	local l1, l2, l3 = leg.lengths[1], leg.lengths[2], leg.lengths[3]
	local w = leg.widths
	local forward, down = CreatureRigs.restReach(plan, leg)
	local a1, a2, a3 = CreatureIK.solve(leg.lengths, leg.bend, math.rad(leg.footAngle), forward, down)
	local upper = chain(
		ctx,
		body,
		leg.name,
		Vector3.new(w[1], l1 + w[1] * 0.3, w[1]),
		CFrame.new(leg.hip) * CFrame.Angles(0, math.rad(leg.splay), 0) * CFrame.Angles(a1, 0, 0),
		Vector3.new(0, -l1 / 2, 0),
		color,
		material
	)
	local lower = chain(
		ctx,
		upper,
		`{leg.name}b`,
		Vector3.new(w[2], l2 + w[2] * 0.4, w[2]),
		CFrame.new(0, -l1 / 2, 0) * CFrame.Angles(a2, 0, 0),
		Vector3.new(0, -l2 / 2, 0),
		dark,
		material
	)
	local foot = chain(
		ctx,
		lower,
		`{leg.name}c`,
		Vector3.new(w[3], l3 + w[3] * 0.5, w[3]),
		CFrame.new(0, -l2 / 2, 0) * CFrame.Angles(a3, 0, 0),
		Vector3.new(0, -l3 / 2, 0),
		dark,
		material
	)
	local motor = body:FindFirstChild(leg.name)
	if motor then
		motor:SetAttribute("RestAngles", Vector3.new(a1, a2, a3))
	end
	return { upper = upper, lower = lower, foot = foot }
end

-- At the foot bone's tip, level with the body whatever the foot's angle.
local function soleFrame(leg: CreatureRigs.Leg, x: number, y: number, z: number): CFrame
	return CFrame.new(0, -leg.lengths[3] / 2, 0)
		* CFrame.Angles(-math.rad(leg.footAngle), 0, 0)
		* CFrame.new(x, y, z)
end

local function has(ctx: Ctx, trait: string): boolean
	return ctx.traits[trait] == true
end

local BONE = Color3.fromRGB(226, 214, 188)

-- Small ivory fangs / claws.
local function tooth(ctx: Ctx, on: BasePart, at: CFrame, length: number)
	oval(ctx, on, "Fang", Vector3.new(0.14, length, 0.14), at, BONE, Enum.Material.SmoothPlastic)
end

-- Curved horns: a thick base sweeping back and a thinner tip.
local function horns(ctx: Ctx, head: BasePart, y: number, spread: number, size: number)
	for _, side in { -1, 1 } do
		local base = CFrame.new(side * spread, y, 0.1) * CFrame.Angles(math.rad(-35), 0, math.rad(side * -25))
		oval(
			ctx,
			head,
			"Horn",
			Vector3.new(0.32, 1.0, 0.32) * size,
			base * CFrame.new(0, 0.4 * size, 0),
			BONE,
			Enum.Material.Slate
		)
		oval(
			ctx,
			head,
			"HornTip",
			Vector3.new(0.2, 0.85, 0.2) * size,
			base
				* CFrame.new(0, 0.85 * size, 0.15 * size)
				* CFrame.Angles(math.rad(-50), 0, 0)
				* CFrame.new(0, 0.3 * size, 0),
			BONE:Lerp(ctx.dark, 0.3),
			Enum.Material.Slate
		)
	end
end

-- A thick ruff of fur tufts in a ring (around a neck or behind a head),
-- the tips touched with the creature's glow.
local function mane(ctx: Ctx, on: BasePart, center: CFrame, radius: number, tuft: number)
	local fur = Enum.Material.Fabric
	local color = ctx.dark:Lerp(ctx.glow, 0.18)
	for i = 0, 9 do
		local a = i / 10 * math.pi * 2
		local at = center * CFrame.Angles(0, 0, a) * CFrame.new(0, radius, 0)
		oval(
			ctx,
			on,
			"Mane",
			Vector3.new(tuft * 0.9, tuft * 1.3, tuft * 1.5),
			at * CFrame.Angles(math.rad(-20), 0, 0),
			color,
			fur
		)
		if i % 2 == 0 then
			oval(
				ctx,
				on,
				"ManeTip",
				Vector3.new(tuft * 0.5, tuft * 0.8, tuft * 0.8),
				at * CFrame.new(0, tuft * 0.55, tuft * 0.35),
				ctx.glow,
				Enum.Material.Neon
			).CastShadow =
				false
		end
	end
end

-- A row of spines along `on`'s back, from z0 to z1 (unscaled, on's frame).
local function spines(
	ctx: Ctx,
	on: BasePart,
	y: number,
	z0: number,
	z1: number,
	count: number,
	height: number
)
	for i = 0, count - 1 do
		local t = if count > 1 then i / (count - 1) else 0.5
		local z = z0 + (z1 - z0) * t
		local h = height * (0.75 + 0.5 * math.sin(t * math.pi))
		oval(
			ctx,
			on,
			"Spine",
			Vector3.new(0.28, h, 0.55),
			CFrame.new(0, y + h * 0.35, z) * CFrame.Angles(math.rad(-28), 0, 0),
			ctx.dark:Lerp(ctx.glow, 0.25),
			Enum.Material.Slate
		)
	end
end

--[[
	Bat-like wings on the root at `pivot`: an inner arm and a jointed tip,
	each carrying a membrane. Motors WingL / WingL2 (and R) fold and beat.
]]
local function wings(ctx: Ctx, parent: BasePart, pivot: Vector3, span: number)
	local membrane = ctx.dark:Lerp(ctx.glow, 0.12)
	for _, side in { -1, 1 } do
		local tag = if side < 0 then "L" else "R"
		local inner = span * 0.55
		local outer = span * 0.45
		local arm = chain(
			ctx,
			parent,
			`Wing{tag}`,
			Vector3.new(inner, 0.32, 0.36),
			CFrame.new(pivot + Vector3.new(side * 0.4, 0, 0)) * CFrame.Angles(0, 0, math.rad(side * 18)),
			Vector3.new(side * inner / 2, 0, 0),
			ctx.dark,
			Enum.Material.Slate
		)
		oval(
			ctx,
			arm,
			"Membrane",
			Vector3.new(inner * 0.95, 0.1, span * 0.42),
			CFrame.new(0, -0.05, span * 0.2),
			membrane,
			Enum.Material.Fabric
		)
		local tip = chain(
			ctx,
			arm,
			`Wing{tag}2`,
			Vector3.new(outer, 0.26, 0.3),
			CFrame.new(side * inner / 2, 0, 0) * CFrame.Angles(0, 0, math.rad(side * 10)),
			Vector3.new(side * outer / 2, 0, 0),
			ctx.dark,
			Enum.Material.Slate
		)
		oval(
			ctx,
			tip,
			"Membrane",
			Vector3.new(outer * 0.95, 0.08, span * 0.34),
			CFrame.new(-side * outer * 0.05, -0.04, span * 0.16),
			membrane,
			Enum.Material.Fabric
		)
		tooth(ctx, tip, CFrame.new(side * outer / 2, 0, -0.1) * CFrame.Angles(0, 0, math.rad(side * 90)), 0.5)
	end
end

--[[
	A serpent's tail: `count` jointed segments (Tail, Tail2, ...) tapering
	back from `pivot` on the root and ending in a small snake head.
]]
local function serpentTail(
	ctx: Ctx,
	parent: BasePart,
	pivot: Vector3,
	thickness: number,
	count: number,
	tilt: number
)
	local mat = Enum.Material.Slate
	local prev: BasePart = parent
	local joint = CFrame.new(pivot) * CFrame.Angles(math.rad(tilt), 0, 0)
	local size = thickness
	local length = thickness * 1.8
	for i = 1, count do
		local name = if i == 1 then "Tail" else `Tail{i}`
		local color = if i % 2 == 0 then ctx.dark else ctx.color
		local seg = chain(
			ctx,
			prev,
			name,
			Vector3.new(size, size, length),
			joint,
			Vector3.new(0, 0, length * 0.45),
			color,
			mat
		)
		prev = seg
		joint = CFrame.new(0, 0, length * 0.85) * CFrame.Angles(math.rad(-6), 0, 0)
		size *= 0.86
		length *= 0.9
	end
	-- The snake head at the tip, looking back over the body.
	local head = chain(
		ctx,
		prev,
		"TailHead",
		Vector3.new(size * 1.5, size * 1.0, size * 2.0),
		joint * CFrame.Angles(math.rad(30), 0, 0),
		Vector3.new(0, 0, size * 0.8),
		ctx.color,
		mat
	)
	-- Its eyes face back along the tail (+Z of the chain).
	for _, x in { -1, 1 } do
		attach(
			ctx,
			head,
			"Eye",
			Vector3.new(0.18, 0.14, 0.12) * size * 2,
			CFrame.new(x * size * 0.42, size * 0.2, size * 0.55),
			ctx.glow,
			Enum.Material.Neon,
			Enum.PartType.Ball
		).CastShadow =
			false
	end
end

--------------------------------------------------------------------------------
-- Body plans (Option A, PLAN.md D-40: rounded procedural forms. Ellipsoids
-- for bodies and limbs; wedges only where a point is wanted: ears.)
--------------------------------------------------------------------------------

-- A wolf head on its joint (`name` Head / HeadL / HeadR), with a jaw that
-- opens (Jaw / JawL / JawR) for bites, howls and roars.
local function wolfHead(ctx: Ctx, parent: BasePart, name: string, joint: CFrame): Part
	local fur = Enum.Material.Fabric
	local light = ctx.color:Lerp(Color3.new(1, 1, 1), 0.18)
	local head = chain(
		ctx,
		parent,
		name,
		Vector3.new(1.45, 1.25, 1.45),
		joint,
		Vector3.new(0, 0.25, -0.75),
		ctx.color,
		fur
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
	local jaw = chain(
		ctx,
		head,
		`Jaw{string.sub(name, 5)}`,
		Vector3.new(0.66, 0.3, 1.0),
		CFrame.new(0, -0.4, -0.3),
		Vector3.new(0, -0.1, -0.5),
		ctx.dark,
		fur
	)
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
		if ctx.elite then
			-- Fangs over the lip and in the jaw.
			tooth(ctx, head, CFrame.new(side * 0.22, -0.62, -1.45), 0.42)
			tooth(ctx, jaw, CFrame.new(side * 0.2, 0.22, -0.35), 0.3)
		end
	end
	eyes(ctx, head, 0.22, -0.6, 0.36, 0.26)
	if has(ctx, "Horns") then
		horns(ctx, head, 0.55, 0.4, 1)
	end
	if has(ctx, "Mane") and not has(ctx, "ThreeHeads") then
		-- A lion's mane framing the face.
		mane(ctx, head, CFrame.new(0, 0.1, 0.25), 0.8, 0.7)
	end
	return head
end

local function wolf(ctx: Ctx): (Vector3, number)
	local fur = Enum.Material.Fabric
	local light = ctx.color:Lerp(Color3.new(1, 1, 1), 0.18)
	local three = has(ctx, "ThreeHeads")
	local body = round(
		limb(ctx, "Body", Vector3.new(2.0, 1.75, 3.4), Vector3.new(0, 0.3, 0.2), Vector3.zero, ctx.color, fur)
	)
	oval(
		ctx,
		body,
		"Chest",
		Vector3.new(if three then 2.8 else 2.25, 2.15, 1.9),
		CFrame.new(0, 0.15, -1.45),
		ctx.color,
		fur
	)
	oval(ctx, body, "Haunch", Vector3.new(1.95, 1.75, 1.6), CFrame.new(0, 0.05, 1.45), ctx.color, fur)
	oval(ctx, body, "Belly", Vector3.new(1.5, 0.9, 2.8), CFrame.new(0, -0.55, 0), light, fur)
	-- Ruff of thicker fur behind the head(s).
	oval(
		ctx,
		body,
		"Ruff",
		Vector3.new(if three then 2.8 else 2.0, 1.4, 1.0),
		CFrame.new(0, 0.55, -1.9),
		ctx.dark,
		fur
	)
	-- Necks rise from the chest (Neck / NeckL / NeckR) and carry the heads.
	local function neckAndHead(tag: string, at: Vector3, yaw: number)
		local neck = chain(
			ctx,
			body,
			`Neck{tag}`,
			Vector3.new(1.25, 1.3, 1.5),
			CFrame.new(at) * CFrame.Angles(0, math.rad(yaw), 0) * CFrame.Angles(math.rad(30), 0, 0),
			Vector3.new(0, 0, -0.5),
			ctx.color,
			fur
		)
		wolfHead(ctx, neck, `Head{tag}`, CFrame.new(0, 0, -0.45) * CFrame.Angles(math.rad(-30), 0, 0))
	end
	if three then
		-- Cerberus: three necks fanning out from a broad chest.
		neckAndHead("", Vector3.new(0, 0.5, -1.7), 0)
		neckAndHead("L", Vector3.new(-0.95, 0.3, -1.55), 28)
		neckAndHead("R", Vector3.new(0.95, 0.3, -1.55), -28)
	else
		neckAndHead("", Vector3.new(0, 0.45, -1.7), 0)
	end
	if has(ctx, "Mane") and three then
		mane(ctx, body, CFrame.new(0, 0.5, -1.7), 1.15, 0.85)
	end

	local plan = CreatureRigs.Plans.Wolf
	for _, leg in plan.legs do
		local bones = rigLeg(ctx, body, plan, leg, ctx.color, ctx.color:Lerp(ctx.dark, 0.5), fur)
		if leg.front then
			-- Shoulder and forearm muscle.
			oval(
				ctx,
				bones.upper,
				"Shoulder",
				Vector3.new(0.9, 1.0, 1.05),
				CFrame.new(0, 0.3, 0),
				ctx.color,
				fur
			)
			oval(
				ctx,
				bones.lower,
				"Forearm",
				Vector3.new(0.55, 0.8, 0.6),
				CFrame.new(0, 0.25, 0),
				ctx.color,
				fur
			)
		else
			-- Heavy thigh and the point of the hock.
			oval(
				ctx,
				bones.upper,
				"Thigh",
				Vector3.new(1.05, 1.45, 1.3),
				CFrame.new(0, 0.15, -0.05),
				ctx.color,
				fur
			)
			oval(
				ctx,
				bones.foot,
				"Hock",
				Vector3.new(0.38, 0.4, 0.42),
				CFrame.new(0, 0.38, 0.06),
				ctx.dark,
				fur
			)
		end
		oval(
			ctx,
			bones.foot,
			"Paw",
			Vector3.new(0.6, 0.3, 0.85),
			soleFrame(leg, 0, -0.02, -0.18),
			ctx.dark,
			fur
		)
		if ctx.elite then
			for _, dx in { -0.18, 0, 0.18 } do
				tooth(
					ctx,
					bones.foot,
					soleFrame(leg, dx, -0.08, -0.62) * CFrame.Angles(math.rad(-75), 0, 0),
					0.3
				)
			end
		end
	end

	if has(ctx, "SerpentTail") then
		serpentTail(ctx, body, Vector3.new(0, 0.35, 1.75), 0.55, 6, 20)
	else
		local tail = chain(
			ctx,
			body,
			"Tail",
			Vector3.new(0.5, 0.5, 1.2),
			CFrame.new(0, 0.35, 1.75) * CFrame.Angles(math.rad(25), 0, 0),
			Vector3.new(0, 0.1, 0.55),
			ctx.color,
			fur
		)
		oval(ctx, tail, "TailMid", Vector3.new(0.44, 0.44, 1.0), CFrame.new(0, 0.1, 1.15), ctx.color, fur)
		oval(ctx, tail, "TailTip", Vector3.new(0.32, 0.32, 0.8), CFrame.new(0, 0.15, 1.9), light, fur)
	end
	if has(ctx, "Wings") then
		wings(ctx, body, Vector3.new(0, 0.9, -0.8), 5)
	end
	if has(ctx, "Spikes") then
		spines(ctx, body, 0.75, -1.2, 1.5, 6, 0.9)
	end
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
	local head = chain(
		ctx,
		shell,
		"Head",
		Vector3.new(1.8, 1.15, 1.45),
		CFrame.new(0, -0.25, -2.15),
		Vector3.new(0, 0, -0.55),
		ctx.dark,
		slate
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
	local plan = CreatureRigs.Plans.Beetle
	for _, leg in plan.legs do
		local bones = rigLeg(ctx, shell, plan, leg, ctx.dark, ctx.dark, slate)
		-- A hooked claw at the tip.
		oval(
			ctx,
			bones.foot,
			"Claw",
			Vector3.new(0.18, 0.3, 0.14),
			soleFrame(leg, 0, -0.05, -0.08),
			ctx.glow:Lerp(ctx.dark, 0.6),
			slate
		)
	end
	if has(ctx, "Horns") then
		horns(ctx, head, 0.4, 0.5, 0.9)
	end
	if has(ctx, "Spikes") then
		spines(ctx, shell, 0.9, -1.4, 1.4, 5, 0.8)
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
	local head = chain(
		ctx,
		torso,
		"Head",
		Vector3.new(1.45, 1.4, 1.5),
		CFrame.new(0, 1.05, 0),
		Vector3.new(0, 0.7, 0),
		ctx.dark,
		stone
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
		local upperArm = chain(
			ctx,
			torso,
			name,
			Vector3.new(1.2, 1.9, 1.2),
			CFrame.new(side * 2.2, 0.5, 0),
			Vector3.new(0, -0.8, 0),
			ctx.color,
			stone
		)
		-- The forearm on an elbow (ArmL2 / ArmR2), slightly bent at rest.
		local arm = chain(
			ctx,
			upperArm,
			`{name}2`,
			Vector3.new(1.3, 2.0, 1.3),
			CFrame.new(0, -0.85, 0) * CFrame.Angles(math.rad(12), 0, 0),
			Vector3.new(0, -0.9, 0),
			ctx.dark,
			stone
		)
		oval(ctx, arm, "Fist", Vector3.new(1.5, 1.3, 1.5), CFrame.new(0, -1.0, 0), ctx.color, stone)
		if knight and side > 0 then
			-- Stone greatsword held point-down and forward, with a glowing fuller.
			local tilt = math.rad(70)
			local length = 4.6
			local along = CFrame.new(0, -1.0, -0.2) * CFrame.Angles(tilt, 0, 0)
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
	local plan = CreatureRigs.Plans.Golem
	for _, leg in plan.legs do
		local bones = rigLeg(ctx, torso, plan, leg, ctx.color, ctx.dark, stone)
		oval(
			ctx,
			bones.lower,
			"Knee",
			Vector3.new(1.2, 0.9, 1.2),
			CFrame.new(0, leg.lengths[2] / 2, -0.1),
			ctx.color,
			stone
		)
		oval(
			ctx,
			bones.foot,
			"Foot",
			Vector3.new(1.5, 0.6, 2.0),
			soleFrame(leg, 0, 0.18, -0.35),
			ctx.color,
			stone
		)
	end
	if has(ctx, "Horns") then
		horns(ctx, head, 0.55, 0.5, 1.2)
	end
	if has(ctx, "Mane") then
		mane(ctx, torso, CFrame.new(0, 1.9, 0) * CFrame.Angles(math.rad(90), 0, 0), 0.95, 0.8)
	end
	if has(ctx, "Wings") then
		wings(ctx, torso, Vector3.new(0, 0.8, 0.9), 6)
	end
	if has(ctx, "SerpentTail") then
		serpentTail(ctx, torso, Vector3.new(0, -1.9, 0.9), 0.8, 6, 35)
	end
	if has(ctx, "Spikes") then
		for _, y in { 1.3, 0.6, -0.1, -0.8 } do
			oval(
				ctx,
				torso,
				"Spine",
				Vector3.new(0.3, 0.6, 1.1),
				CFrame.new(0, y, 1.15) * CFrame.Angles(math.rad(30), 0, 0),
				ctx.dark:Lerp(ctx.glow, 0.25),
				stone
			)
		end
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

-- Body segments trailing behind a serpent's chest (Seg1 .. SegN).
local SERPENT_SEGMENTS = 7

-- A raised serpent neck (Neck / NeckB) ending in a head with an opening
-- jaw; `tag` is "", "L" or "R" for the hydra's extra heads.
local function serpentNeck(ctx: Ctx, body: BasePart, tag: string, pivot: Vector3, yaw: number)
	local mat = Enum.Material.Slate
	local light = ctx.color:Lerp(Color3.new(1, 1, 1), 0.3)
	local lower = chain(
		ctx,
		body,
		`Neck{tag}`,
		Vector3.new(1.4, 1.4, 2.3),
		CFrame.new(pivot) * CFrame.Angles(0, math.rad(yaw), 0) * CFrame.Angles(math.rad(50), 0, 0),
		Vector3.new(0, 0, -1.0),
		ctx.color,
		mat
	)
	oval(ctx, lower, "Throat", Vector3.new(1.0, 0.6, 2.1), CFrame.new(0, -0.5, -1.0), light, mat)
	local upper = chain(
		ctx,
		lower,
		`NeckB{tag}`,
		Vector3.new(1.25, 1.25, 2.1),
		CFrame.new(0, 0, -1.9) * CFrame.Angles(math.rad(20), 0, 0),
		Vector3.new(0, 0, -0.9),
		ctx.color,
		mat
	)
	oval(ctx, upper, "Throat", Vector3.new(0.9, 0.55, 1.9), CFrame.new(0, -0.45, -0.9), light, mat)
	-- Pitched back down so the head looks level along the ground.
	local head = chain(
		ctx,
		upper,
		`Head{tag}`,
		Vector3.new(1.55, 1.0, 2.1),
		CFrame.new(0, 0, -1.7) * CFrame.Angles(math.rad(-70), 0, 0),
		Vector3.new(0, 0.1, -0.85),
		ctx.color,
		mat
	)
	oval(ctx, head, "Brow", Vector3.new(1.7, 0.5, 1.0), CFrame.new(0, 0.35, -0.4), ctx.dark, mat)
	local jaw = chain(
		ctx,
		head,
		`Jaw{tag}`,
		Vector3.new(1.25, 0.38, 1.5),
		CFrame.new(0, -0.32, 0.35),
		Vector3.new(0, -0.12, -0.75),
		light,
		mat
	)
	for _, side in { -1, 1 } do
		tooth(ctx, head, CFrame.new(side * 0.35, -0.45, -0.8), 0.5)
		tooth(ctx, jaw, CFrame.new(side * 0.3, 0.25, -0.45), 0.3)
	end
	eyes(ctx, head, 0.3, -0.85, 0.5, 0.3)
	if has(ctx, "Crest") then
		-- A crown of glowing spines and two frills: the basilisk's "king" mark.
		for i, x in { -0.4, 0, 0.4 } do
			local spike = attach(
				ctx,
				head,
				"Crown",
				Vector3.new(0.22, 0.9 + (if x == 0 then 0.4 else 0), 0.22),
				CFrame.new(x, 0.75, 0.1 + i * 0.05) * CFrame.Angles(math.rad(-30), 0, math.rad(-x * 30)),
				ctx.glow,
				Enum.Material.Neon
			)
			spike.CastShadow = false
		end
		for _, side in { -1, 1 } do
			local frill = oval(
				ctx,
				head,
				"Frill",
				Vector3.new(0.12, 1.2, 1.5),
				CFrame.new(side * 0.8, 0.15, 0.35) * CFrame.Angles(0, 0, math.rad(side * -35)),
				ctx.glow,
				Enum.Material.Glass
			)
			frill.Transparency = 0.25
		end
	end
	if has(ctx, "Horns") then
		horns(ctx, head, 0.45, 0.45, 1)
	end
end

local function serpent(ctx: Ctx): (Vector3, number)
	local mat = Enum.Material.Slate
	local light = ctx.color:Lerp(Color3.new(1, 1, 1), 0.3)
	-- The chest rides on the root; necks rise from it and the body trails behind.
	local body = round(
		limb(ctx, "Body", Vector3.new(2.4, 1.8, 3.0), Vector3.new(0, -0.35, 0), Vector3.zero, ctx.color, mat)
	)
	oval(ctx, body, "Belly", Vector3.new(1.9, 0.8, 2.8), CFrame.new(0, -0.6, 0), light, mat)
	if has(ctx, "ThreeHeads") then
		serpentNeck(ctx, body, "L", Vector3.new(-0.8, 0.4, -1.1), 28)
		serpentNeck(ctx, body, "", Vector3.new(0, 0.5, -1.3), 0)
		serpentNeck(ctx, body, "R", Vector3.new(0.8, 0.4, -1.1), -28)
	else
		serpentNeck(ctx, body, "", Vector3.new(0, 0.4, -1.3), 0)
	end
	local prev: BasePart = body
	local w, h, l = 2.4, 1.8, 3.0
	for i = 1, SERPENT_SEGMENTS do
		local k = 0.9 ^ i
		local nw, nh, nl = 2.4 * k, 1.8 * k, 2.9 * k
		-- Bottoms stay on the ground as the body tapers.
		local seg = chain(
			ctx,
			prev,
			`Seg{i}`,
			Vector3.new(nw, nh, nl),
			CFrame.new(0, -(h - nh) / 2, l * 0.42),
			Vector3.new(0, 0, nl * 0.42),
			if i % 2 == 0 then ctx.dark else ctx.color,
			mat
		)
		oval(
			ctx,
			seg,
			"Belly",
			Vector3.new(nw * 0.8, nh * 0.45, nl * 0.95),
			CFrame.new(0, -nh * 0.33, 0),
			light,
			mat
		)
		if has(ctx, "Spikes") then
			spines(ctx, seg, nh * 0.4, 0, 0, 1, 0.9 * k + 0.2)
		end
		prev, w, h, l = seg, nw, nh, nl
	end
	-- A glowing tail tip.
	attach(
		ctx,
		prev,
		"TailGlow",
		Vector3.new(w * 0.5, h * 0.5, l * 0.6),
		CFrame.new(0, 0, l * 0.55),
		ctx.glow,
		Enum.Material.Neon,
		Enum.PartType.Ball
	).CastShadow =
		false
	crystals(ctx, body, { Vector3.new(0, 0.85, 0.2), Vector3.new(0.5, 0.75, 0.9) }, 1.2)
	return Vector3.new(2.2, 1.6, 3.0), 1.3
end

--[[
	Builds an unparented creature for `enemyId`, standing with its feet at
	`at` (ground point, facing its -Z). Returns nil for unknown ids.
]]
--------------------------------------------------------------------------------
-- Sculpted meshes (D-52): imported skinned models in CreatureModels
--------------------------------------------------------------------------------

local MODELS = script.Parent.Parent:FindFirstChild("CreatureModels")

local function meshTemplate(shape: string): Model?
	local template = MODELS and MODELS:FindFirstChild(shape)
	return if template and template:IsA("Model") then template else nil
end

-- The skin's material by body plan: fur, chitin, stone / scales.
local SKIN_MATERIAL: { [string]: Enum.Material } = {
	Quadruped = Enum.Material.Fabric,
	Hexapod = Enum.Material.SmoothPlastic,
	Octopod = Enum.Material.Fabric,
}

-- Colour and material of each mesh region for an enemy's palette.
local function regionStyle(region: string, ctx: Ctx, skin: Enum.Material): (Color3, Enum.Material)
	if region == "Under" then
		return ctx.color:Lerp(Color3.new(1, 0.95, 0.85), 0.35), skin
	elseif region == "Dark" then
		return ctx.dark, skin
	elseif region == "Horn" then
		return BONE, Enum.Material.SmoothPlastic
	elseif region == "Eye" or region == "Glow" then
		return ctx.glow, Enum.Material.Neon
	elseif region == "Mane" or region == "Tuft" then
		return ctx.dark:Lerp(ctx.glow, 0.3), Enum.Material.Fabric
	elseif region == "Horns" then
		return BONE, Enum.Material.SmoothPlastic
	elseif region == "Metal" then
		-- Armour: steel tinted with the creature's colour.
		return ctx.color:Lerp(Color3.fromRGB(150, 154, 164), 0.5), Enum.Material.Metal
	elseif region == "Blade" then
		return Color3.fromRGB(206, 212, 222):Lerp(ctx.glow, 0.12), Enum.Material.Metal
	elseif region == "Cloth" then
		return ctx.dark:Lerp(ctx.glow, 0.25), Enum.Material.Fabric
	elseif region == "Wing" then
		return ctx.color:Lerp(ctx.dark, 0.45), skin
	elseif region == "Sting" then
		return ctx.dark, Enum.Material.SmoothPlastic
	elseif region == "Spikes" or region == "Petal" then
		return ctx.glow:Lerp(Color3.new(1, 1, 1), 0.35), Enum.Material.Glass
	end
	return ctx.color, skin
end

--[[
	Clones the imported model for `shape`, sizes it, paints its regions and
	stands its Body bone over `at` (ground point, facing -Z). Its MeshParts
	ride the root by welds; the client drives the bones.
]]
local function buildFromMesh(
	enemy: EnemyDefinitions.Enemy,
	shape: string,
	template: Model,
	at: CFrame
): (Model, BasePart)
	local s = enemy.scale
	local data = CreatureMeshes.Shapes[shape]
	local model = template:Clone()
	model.Name = enemy.name
	-- The importer's extras: our animator drives the bones, and the pose
	-- backup (~100 values) would only be replicated to every player.
	for _, extra in { "AnimationController", "InitialPoses" } do
		local found = model:FindFirstChild(extra)
		if found then
			found:Destroy()
		end
	end
	local color = rgb(enemy.color)
	local ctx: Ctx = {
		model = model,
		root = nil :: any,
		scale = s,
		color = color,
		dark = color:Lerp(Color3.new(0, 0, 0), 0.35),
		glow = rgb(enemy.glow),
		traits = {},
		elite = enemy.elite,
	}
	local skin = SKIN_MATERIAL[data.bodyPlan] or Enum.Material.Slate
	local traitSet: { [string]: boolean } = {}
	for _, trait in ((enemy.traits :: any) or {}) :: { string } do
		traitSet[trait] = true
	end
	-- Optional parts this enemy does not have (wings, sting, horns...).
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") then
			local region = string.gsub(d.Name, "%d+$", "")
			local needs = CreatureRigs.MESH_OPTIONAL_REGIONS[region]
			local replacedBy = CreatureRigs.MESH_REPLACED_REGIONS[region]
			if (needs and not traitSet[needs]) or (replacedBy and traitSet[replacedBy]) then
				d:Destroy()
			end
		end
	end
	local parts: { BasePart } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
			d.Anchored = false
			d.CanCollide = false
			d.CanTouch = false
			d.Massless = true
			local region = string.gsub(d.Name, "%d+$", "")
			d.Color, d.Material = regionStyle(region, ctx, skin)
			if region == "Spikes" then
				d.Transparency = 0.15
			elseif region == "Petal" then
				d.Transparency = 0.3
			end
			d.CastShadow = region ~= "Eye" and region ~= "Glow"
			if d:IsA("MeshPart") then
				-- Region colour and material instead of a texture.
				d.TextureID = ""
			end
		end
	end
	if s ~= 1 then
		model:ScaleTo(s)
	end
	local function bone(name: string): Bone?
		for _, d in model:GetDescendants() do
			if d:IsA("Bone") and d.Name == name then
				return d
			end
		end
		return nil
	end
	-- Stand the Body bone on `at`, at its height, facing -Z of `at`.
	local bodyBone = bone("Body")
	local bonePosition = if bodyBone then bodyBone.WorldPosition else model:GetPivot().Position
	local facing = CFrame.identity
	if bodyBone then
		-- The sculpt binds the Body bone facing -Z; the importer turns it
		-- (and the model) round, so its yaw now is the model's facing.
		local look = bodyBone.WorldCFrame.LookVector
		facing = CFrame.Angles(0, math.atan2(-look.X, -look.Z), 0)
	end
	local target = at * CFrame.new(0, data.height * s, 0)
	local offset = target * (CFrame.new(bonePosition) * facing):Inverse()
	for _, part in parts do
		part.CFrame = offset * part.CFrame
	end
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Transparency = 1
	root.CanCollide = true
	root.CanTouch = false
	root.Size = (CreatureRigs.MESH_ROOT_SIZE[shape] or Vector3.new(2, 2, 3)) * s
	root.CFrame = target
	root.Parent = model
	for _, part in parts do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = part
		weld.Parent = part
	end
	model.PrimaryPart = root
	model:SetAttribute("RC_Shape", shape)
	return model, root
end

local function newHumanoid(enemy: EnemyDefinitions.Enemy, hipHeight: number): Humanoid
	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = hipHeight
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
	return humanoid
end

function CreatureBuilder.build(enemyId: string, at: CFrame): Model?
	local enemy = EnemyDefinitions.get(enemyId)
	if enemy == nil then
		return nil
	end
	-- A sculpted mesh when its model has been imported (D-52).
	local shape = CreatureRigs.meshShapeFor(enemy.body, enemy.traits :: any, enemy.id)
	local template = if shape then meshTemplate(shape) else nil
	if shape and template then
		local meshModel, meshRoot = buildFromMesh(enemy, shape, template, at)
		meshModel:SetAttribute("RC_Body", enemy.body)
		meshModel:SetAttribute("RC_Enemy", enemy.id)
		meshModel:SetAttribute("RC_Scale", enemy.scale)
		local height = CreatureMeshes.Shapes[shape].height * enemy.scale
		newHumanoid(enemy, height - meshRoot.Size.Y / 2).Parent = meshModel
		meshModel.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		return meshModel
	end
	local model = Instance.new("Model")
	model.Name = enemy.name
	model:SetAttribute("RC_Body", enemy.body)
	model:SetAttribute("RC_Enemy", enemy.id)
	model:SetAttribute("RC_Scale", enemy.scale)

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
		traits = {},
		elite = enemy.elite,
	}
	local traits: { string } = (enemy.traits :: any) or {}
	for _, trait in traits do
		ctx.traits[trait] = true
	end
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
	elseif body == "Serpent" then
		rootSize, height = serpent(ctx)
	else
		rootSize, height = sprite(ctx)
	end
	local s = enemy.scale
	root.Size = rootSize * s
	-- Lift everything so the root centre stands `height` above the ground.
	model.PrimaryPart = root
	model:PivotTo(at * CFrame.new(0, height * s, 0))

	newHumanoid(enemy, height * s - root.Size.Y / 2).Parent = model
	-- Streams to a player whole (and leaves whole): a creature never shows
	-- up with some of its joints, which the client animator would miss.
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	return model
end

return CreatureBuilder
