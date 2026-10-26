--!strict
--[[
	AuraBuilder — a light magical aura (PLAN.md D-100).

	Radiant: a few golden motes rising round the feet (one emitter, 5 a
	second; the halo and the sword carry the lights). Kept small: many
	characters share a map, and the D-82 budgets count emitters.
	Infernal: the same with embers, orange fading to red.
]]

local Kit = require(script.Parent.Kit)

local AuraBuilder = {}

AuraBuilder.RATE = 5

local function motes(ctx: Kit.Ctx, root: BasePart, color: ColorSequence)
	local holder =
		Kit.block(ctx, root, "glow", Vector3.new(0.1, 0.1, 0.1), CFrame.new(0, -root.Size.Y * 1.35, 0))
	holder.Transparency = 1
	holder.Name = "AuraHolder"
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "RC_Aura"
	emitter.Color = color
	emitter.LightEmission = 1
	emitter.Rate = AuraBuilder.RATE
	emitter.Lifetime = NumberRange.new(1.4, 2.4)
	emitter.Speed = NumberRange.new(1, 2)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.SpreadAngle = Vector2.new(35, 35)
	emitter.Shape = Enum.ParticleEmitterShape.Disc
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	emitter.Size =
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.16), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency =
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	emitter.Parent = holder
	-- The disc spreads the motes round the feet.
	holder.Size = Vector3.new(2.6, 0.1, 2.6)
end

function AuraBuilder.build(ctx: Kit.Ctx, body: Kit.Body)
	if body.root == nil then
		return
	end
	if ctx.archetype.aura == "Radiant" then
		motes(ctx, body.root, ColorSequence.new(Kit.color(ctx, "glow")))
	elseif ctx.archetype.aura == "Infernal" then
		motes(ctx, body.root, ColorSequence.new(Color3.fromRGB(255, 170, 60), Kit.color(ctx, "glow")))
	end
end

return AuraBuilder
