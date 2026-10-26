--!strict
--[[
	WeaponBuilder — ornate anime weapons held in the rig's hands
	(PLAN.md D-100).

	DivineSword  wrapped grip, gem pommel, a crossguard of swept gold
	             feathers round a blue gem, a broad silver blade with a
	             diamond point and a glowing gold fuller (light; sparkles
	             on Legendary / Mythical gear).
	InfernalSword  the same build in the Devil palette: a crossguard of
	             swept horns, a dark blade and a red glowing fuller.
	KiteShield   white kite shield with a gold border, a gold boss and gem
	             between two gold feathers, on the left forearm.

	Weapon frames follow OutfitBuilder's grips (FORWARD_GRIP: +Y from the
	grip to the tip, matched to the authored attack animations, D-69).
]]

local Kit = require(script.Parent.Kit)

local WeaponBuilder = {}

local V = Vector3.new
local C = CFrame.new
local A = CFrame.Angles
local rad = math.rad

-- Same as OutfitBuilder.FORWARD_GRIP (tools/anim/generate_arms.py GRIP).
local FORWARD_GRIP = C(0, -0.1, 0) * A(rad(-110), 0, 0)

local function sparkles(part: BasePart, color: Color3)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "RC_Sparkle"
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.Rate = 5
	emitter.Lifetime = NumberRange.new(0.4, 0.8)
	emitter.Speed = NumberRange.new(0.5, 1.5)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size =
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.18), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency =
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	emitter.Parent = part
end

function WeaponBuilder.divineSword(ctx: Kit.Ctx, hand: BasePart, sparkle: boolean)
	local g = FORWARD_GRIP
	local function at(y: number): CFrame
		return g * C(0, y, 0)
	end
	-- Grip and pommel.
	Kit.part(ctx, hand, "grip", "Cylinder", V(0.2, 0.95, 0.2), at(0.05))
	Kit.part(ctx, hand, "trim", "Cylinder", V(0.24, 0.07, 0.24), at(-0.3))
	Kit.part(ctx, hand, "trim", "Cylinder", V(0.24, 0.07, 0.24), at(0.4))
	Kit.ellipsoid(ctx, hand, "trim", V(0.3, 0.3, 0.3), at(-0.5))
	Kit.ellipsoid(ctx, hand, "gem", V(0.16, 0.16, 0.16), at(-0.64))
	-- Crossguard: a block, swept feather wings (Devils: horns) and a gem
	-- each side.
	local horned = ctx.archetype.race == "Devil"
	local wingRole = if horned then "horn" else "trim"
	Kit.block(ctx, hand, "trim", V(0.56, 0.22, 0.28), at(0.6))
	for _, sign in Kit.SIDES do
		Kit.ellipsoid(
			ctx,
			hand,
			wingRole,
			V(0.22, 0.95, if horned then 0.2 else 0.12),
			at(0.72)
				* C(sign * 0.5, if horned then -0.05 else 0.12, 0)
				* A(0, 0, rad(-sign * (if horned then 100 else 58)))
		)
		Kit.ellipsoid(
			ctx,
			hand,
			if horned then "glow" else "trim",
			V(0.16, 0.66, if horned then 0.14 else 0.1),
			at(0.82)
				* C(sign * (if horned then 0.86 else 0.4), 0.22, 0)
				* A(0, 0, rad(-sign * (if horned then 15 else 30)))
		)
	end
	Kit.gem(ctx, hand, 0.2, at(0.62) * C(0, 0, -0.14))
	Kit.gem(ctx, hand, 0.2, at(0.62) * C(0, 0, 0.14) * A(0, math.pi, 0))
	-- Blade, diamond point, fuller.
	local length = 3.9
	local base = 0.72
	Kit.ellipsoid(ctx, hand, "trim", V(0.58, 0.3, 0.14), at(base + 0.08))
	Kit.block(ctx, hand, "blade", V(0.46, length * 0.84, 0.09), at(base + length * 0.42))
	Kit.block(ctx, hand, "blade", V(0.33, 0.33, 0.09), at(base + length * 0.84) * A(0, 0, rad(45)))
	local fuller = Kit.block(ctx, hand, "glow", V(0.1, length * 0.7, 0.11), at(base + length * 0.4))
	local light = Instance.new("PointLight")
	light.Color = Kit.color(ctx, "glow")
	light.Brightness = 0.8
	light.Range = 6
	light.Shadows = false
	light.Parent = fuller
	if sparkle then
		sparkles(fuller, Kit.color(ctx, "glow"))
	end
end

function WeaponBuilder.kiteShield(ctx: Kit.Ctx, arm: BasePart)
	local s = arm.Size
	-- Facing out from the arm (-X), slightly forward; the face is -Z.
	local face = C(-(s.X / 2 + 0.18), -0.05, -0.1) * A(0, rad(90), 0)
	-- Gold border: a slightly larger copy behind the face.
	Kit.block(ctx, arm, "trim", V(1.74, 1.42, 0.12), face * C(0, 0.35, 0.05))
	Kit.block(ctx, arm, "trim", V(1.22, 1.22, 0.12), face * C(0, -0.35, 0.05) * A(0, 0, rad(45)))
	Kit.ellipsoid(ctx, arm, "trim", V(1.74, 0.6, 0.12), face * C(0, 1.05, 0.05))
	-- White face.
	Kit.block(ctx, arm, "plate", V(1.6, 1.32, 0.16), face * C(0, 0.35, 0))
	Kit.block(ctx, arm, "plate", V(1.12, 1.12, 0.16), face * C(0, -0.35, 0) * A(0, 0, rad(45)))
	Kit.ellipsoid(ctx, arm, "plate", V(1.6, 0.5, 0.16), face * C(0, 1.03, 0))
	-- Boss, gem and two gold feathers.
	Kit.ellipsoid(ctx, arm, "trim", V(0.58, 0.58, 0.22), face * C(0, 0.3, -0.1))
	Kit.ellipsoid(ctx, arm, "gem", V(0.3, 0.34, 0.16), face * C(0, 0.3, -0.2))
	for _, sign in Kit.SIDES do
		Kit.ellipsoid(
			ctx,
			arm,
			if ctx.archetype.race == "Devil" then "horn" else "trim",
			V(0.18, 0.8, 0.07),
			face * C(sign * 0.44, 0.48, -0.1) * A(0, 0, rad(-sign * 50))
		)
	end
end

-- Main hand from the archetype; `offHand` = "Shield" | "Sword" | nil.
function WeaponBuilder.build(ctx: Kit.Ctx, body: Kit.Body, offHand: string?, sparkle: boolean)
	local style = ctx.archetype.weapon
	if style == "DivineSword" or style == "InfernalSword" then
		local right = body.arms.Right.hand or body.arms.Right.lower
		if right then
			WeaponBuilder.divineSword(ctx, right, sparkle)
		end
		if offHand == "Sword" then
			local left = body.arms.Left.hand or body.arms.Left.lower
			if left then
				WeaponBuilder.divineSword(ctx, left, sparkle)
			end
		end
	end
	if offHand == "Shield" then
		local arm = body.arms.Left.lower or body.arms.Left.upper
		if arm then
			WeaponBuilder.kiteShield(ctx, arm)
		end
	end
end

return WeaponBuilder
