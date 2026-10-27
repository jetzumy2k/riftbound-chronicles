--!strict
--[[
	EnhanceAura — the glow enhanced gear gives a character (creator request
	2026-10-27, PLAN.md D-110). Display only; GearLook.aura decides the
	stages, this draws them:

	  Weapon (its own level)
	    +4  motes drift off the weapon, faint light
	    +7  denser, brighter motes and light
	    +10 plus a slow shimmer of larger stars

	  Body (average of the six armor slots, so every piece raised stacks)
	    avg 4   a ring of light rising from the feet
	    avg 7   plus motes spiralling up to the chest
	    avg 10  plus a soft light around the body (full +10 armor)

	Within a stage the rate grows with the level, so +9 reads stronger than
	+7. Particle counts stay small (mobile, CLAUDE.md §27). Calling apply
	again replaces the previous aura.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GearLook = require(ReplicatedStorage.Shared.Logic.GearLook)

local NAME = "RC_EnhanceAura"

local EnhanceAura = {}

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- Brighter towards white, for particle cores.
local function core(color: Color3): ColorSequence
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, color:Lerp(Color3.new(1, 1, 1), 0.55)),
		ColorSequenceKeypoint.new(1, color),
	})
end

local function sizes(from: number): NumberSequence
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, from * 0.4),
		NumberSequenceKeypoint.new(0.3, from),
		NumberSequenceKeypoint.new(1, 0),
	})
end

local function fade(start: number): NumberSequence
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.2, start),
		NumberSequenceKeypoint.new(1, 1),
	})
end

local function emitter(parent: Instance, color: Color3): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = NAME
	e.Color = core(color)
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Parent = parent
	return e
end

local function light(parent: Instance, color: Color3, brightness: number, range: number)
	local l = Instance.new("PointLight")
	l.Name = NAME
	l.Color = color
	l.Brightness = brightness
	l.Range = range
	l.Shadows = false
	l.Parent = parent
end

local function clear(character: Model)
	for _, child in character:GetDescendants() do
		if child.Name == NAME then
			child:Destroy()
		end
	end
end

-- The weapon's glowing part (its sparkle emitter's parent), else the hand.
local function weaponAnchor(character: Model): BasePart?
	for _, child in character:GetDescendants() do
		if child.Name == "RC_Sparkle" and child.Parent and child.Parent:IsA("BasePart") then
			return child.Parent :: BasePart
		end
	end
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	return if hand and hand:IsA("BasePart") then hand else nil
end

local function weaponAura(character: Model, aura: GearLook.Aura)
	local anchor = weaponAnchor(character)
	if anchor == nil then
		return
	end
	local color = rgb(aura.weaponColor)
	local level = aura.weapon
	local motes = emitter(anchor, color)
	motes.Rate = 4 + level * 2.2
	motes.Lifetime = NumberRange.new(0.5, 1.1)
	motes.Speed = NumberRange.new(0.4, 1.4)
	motes.SpreadAngle = Vector2.new(180, 180)
	motes.Acceleration = Vector3.new(0, 1.5, 0)
	motes.Size = sizes(0.14 + level * 0.012)
	motes.Transparency = fade(0.15)
	light(anchor, color, 0.4 + level * 0.12, 4 + level * 0.5)
	if aura.weaponStage >= 3 then
		local stars = emitter(anchor, color)
		stars.Rate = 3
		stars.Lifetime = NumberRange.new(0.8, 1.4)
		stars.Speed = NumberRange.new(0.2, 0.6)
		stars.SpreadAngle = Vector2.new(180, 180)
		stars.RotSpeed = NumberRange.new(-90, 90)
		stars.Size = sizes(0.45)
		stars.Transparency = fade(0.35)
	end
end

local function bodyAura(character: Model, aura: GearLook.Aura)
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if root == nil or not root:IsA("BasePart") or humanoid == nil then
		return
	end
	local color = rgb(aura.armorColor)
	local level = aura.armor
	-- An invisible disc at the feet gives the emitters their shape.
	local feet = -(humanoid.HipHeight + root.Size.Y / 2) + 0.15
	local disc = Instance.new("Part")
	disc.Name = NAME
	disc.Shape = Enum.PartType.Cylinder
	disc.Size = Vector3.new(0.2, 3.6, 3.6)
	disc.Transparency = 1
	disc.CanCollide = false
	disc.CanQuery = false
	disc.CanTouch = false
	disc.Massless = true
	disc.CastShadow = false
	disc.CFrame = root.CFrame * CFrame.new(0, feet, 0) * CFrame.Angles(0, 0, math.rad(90))
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = disc
	weld.Parent = disc
	disc.Parent = character

	-- The cylinder's axis is its X: rotated upright, "Right" points up.
	local ring = emitter(disc, color)
	ring.Shape = Enum.ParticleEmitterShape.Cylinder
	ring.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	ring.EmissionDirection = Enum.NormalId.Right
	ring.Rate = 6 + level * 2
	ring.Lifetime = NumberRange.new(0.7, 1.2)
	ring.Speed = NumberRange.new(1.2, 2.2)
	ring.Size = sizes(0.22)
	ring.Transparency = fade(0.25)
	if aura.armorStage >= 2 then
		local rise = emitter(disc, color)
		rise.Shape = Enum.ParticleEmitterShape.Cylinder
		rise.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		rise.EmissionDirection = Enum.NormalId.Right
		rise.Rate = 2 + level
		rise.Lifetime = NumberRange.new(1.6, 2.4)
		rise.Speed = NumberRange.new(1.4, 2)
		rise.RotSpeed = NumberRange.new(-120, 120)
		rise.Size = sizes(0.3)
		rise.Transparency = fade(0.3)
	end
	if aura.armorStage >= 3 then
		light(root, color, 1.1, 11)
	end
end

--[[
	Draws the aura of `look` on `character` (replacing any earlier one).
	Nothing below +4.
]]
function EnhanceAura.apply(character: Model, look: GearLook.Look)
	clear(character)
	local aura = GearLook.aura(look)
	if aura.weaponStage > 0 then
		weaponAura(character, aura)
	end
	if aura.armorStage > 0 then
		bodyAura(character, aura)
	end
end

return EnhanceAura
