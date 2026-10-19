--!strict
--[[
	CreatureFx — the creatures' visual effects (creature overhaul stage 5,
	PLAN.md D-62). Display only, non-graphic (CLAUDE.md §18): dust, light
	trails, shockwave rings, a roar ripple, a breath puff, embers.

	  dust        a puff of dust on the ground (footfalls, landings)
	  shockwave   a ring racing out across the ground plus dust (slams,
	              stomps, a dive landing)
	  trail       glowing claw / weapon streaks across the creature's front
	  roar        a ripple of air from the head
	  breath      a burst of embers from a dragon's / chimera's jaws
	  embers      a slow drift of sparks round an enraged creature
	Mobile budget: a few anchored, non-colliding, non-queryable parts and two
	shared particle emitters (particles are emitted, never left running),
	cleaned up with Debris; the caller only asks near the camera.
]]

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local CreatureFx = {}

local DUST = Color3.fromRGB(176, 158, 132)

local function folder(): Folder
	local existing = Workspace:FindFirstChild("RC_ClientVfx")
	if existing and existing:IsA("Folder") then
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = "RC_ClientVfx"
	created.Parent = Workspace
	return created
end

local function part(
	size: Vector3,
	cf: CFrame,
	color: Color3,
	transparency: number,
	shape: Enum.PartType?
): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = transparency
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.CFrame = cf
	p.Parent = folder()
	return p
end

-- Shared emitters: an invisible anchored part moved to where particles are
-- wanted, then Emit (the particles stay in the world where they were made).
local emitters: { [string]: ParticleEmitter } = {}

local function emitter(name: string, setup: (ParticleEmitter) -> ()): ParticleEmitter
	local existing = emitters[name]
	if existing and existing.Parent and existing.Parent.Parent then
		return existing
	end
	local holder = part(Vector3.new(0.2, 0.2, 0.2), CFrame.new(), DUST, 1)
	holder.Name = `RC_{name}Emitter`
	local e = Instance.new("ParticleEmitter")
	e.Enabled = false
	setup(e)
	e.Parent = holder
	emitters[name] = e
	return e
end

local function dustEmitter(): ParticleEmitter
	return emitter("Dust", function(e)
		e.Color = ColorSequence.new(DUST)
		e.LightEmission = 0
		e.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.55),
			NumberSequenceKeypoint.new(1, 1),
		})
		e.Size =
			NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 2.2) })
		e.Lifetime = NumberRange.new(0.6, 1.1)
		e.Speed = NumberRange.new(3, 7)
		e.SpreadAngle = Vector2.new(80, 15)
		e.Drag = 4
		e.Acceleration = Vector3.new(0, 1.5, 0)
		e.Rotation = NumberRange.new(0, 360)
		e.RotSpeed = NumberRange.new(-40, 40)
		e.EmissionDirection = Enum.NormalId.Top
	end)
end

local function sparkEmitter(): ParticleEmitter
	return emitter("Spark", function(e)
		e.LightEmission = 1
		e.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		})
		e.Size =
			NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0.05) })
		e.Lifetime = NumberRange.new(0.5, 1)
		e.Speed = NumberRange.new(6, 14)
		e.SpreadAngle = Vector2.new(18, 18)
		e.Drag = 3
		e.Acceleration = Vector3.new(0, 3, 0)
	end)
end

local function emitAt(e: ParticleEmitter, cf: CFrame, count: number)
	local holder = e.Parent :: BasePart
	holder.CFrame = cf
	e:Emit(math.clamp(math.floor(count + 0.5), 1, 40))
end

-- A puff of dust at `position` (ground), `size` ~ the creature's scale.
function CreatureFx.dust(position: Vector3, size: number)
	local e = dustEmitter()
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4 * size),
		NumberSequenceKeypoint.new(1, 1.4 * size),
	})
	emitAt(e, CFrame.new(position), 3 + size * 2)
end

-- A ring racing out across the ground from `position`, `radius` studs.
function CreatureFx.shockwave(position: Vector3, radius: number, color: Color3)
	local ring = part(
		Vector3.new(0.12, 1, 1),
		CFrame.new(position + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		color:Lerp(Color3.new(1, 1, 1), 0.35),
		0.25,
		Enum.PartType.Cylinder
	)
	local info = TweenInfo.new(0.45, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
	TweenService:Create(ring, info, { Size = Vector3.new(0.05, radius * 2, radius * 2), Transparency = 1 })
		:Play()
	Debris:AddItem(ring, 0.5)
	local e = dustEmitter()
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, radius * 0.12),
		NumberSequenceKeypoint.new(1, radius * 0.35),
	})
	emitAt(e, CFrame.new(position), 6 + radius)
end

-- Glowing streaks across `origin` (the creature's front, facing -Z), as a
-- claw rake (3 streaks) or a weapon swing (1 wide streak).
function CreatureFx.trail(origin: CFrame, width: number, color: Color3, streaks: number)
	local glow = color:Lerp(Color3.new(1, 1, 1), 0.4)
	for i = 1, streaks do
		local offset = (i - (streaks + 1) / 2) * 0.35 * width / 3
		local streak = part(
			Vector3.new(width, 0.08 + 0.04 * width / 3, 0.08 + 0.04 * width / 3),
			origin * CFrame.new(0, offset, 0) * CFrame.Angles(0, 0, math.rad(-25)),
			glow,
			0.15
		)
		local info = TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(streak, info, {
			Transparency = 1,
			Size = Vector3.new(width * 1.25, 0.02, 0.02),
			CFrame = streak.CFrame * CFrame.new(0, -0.4 * width / 3, -0.3),
		}):Play()
		Debris:AddItem(streak, 0.32)
	end
end

-- A ripple of air from a roaring head.
function CreatureFx.roar(head: CFrame, size: number, color: Color3)
	local ball = part(
		Vector3.new(1, 1, 1) * size,
		head * CFrame.new(0, 0, -0.6 * size),
		color:Lerp(Color3.new(1, 1, 1), 0.6),
		0.75,
		Enum.PartType.Ball
	)
	ball.Material = Enum.Material.ForceField
	local info = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(ball, info, { Size = Vector3.new(1, 1, 1) * size * 5, Transparency = 1 }):Play()
	Debris:AddItem(ball, 0.65)
end

-- A burst of embers from the jaws (dragons, the chimera), pointing ahead.
function CreatureFx.breath(head: CFrame, size: number, color: Color3)
	local e = sparkEmitter()
	e.Color = ColorSequence.new(color:Lerp(Color3.fromRGB(255, 200, 90), 0.5), Color3.fromRGB(255, 90, 40))
	e.Speed = NumberRange.new(6 * size, 12 * size)
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35 * size),
		NumberSequenceKeypoint.new(1, 0.05),
	})
	-- Emitters shoot along the part's +Y (Top): turn it to face ahead.
	emitAt(e, head * CFrame.new(0, 0, -0.8 * size) * CFrame.Angles(math.rad(-90), 0, 0), 18 + size * 4)
end

-- Sparks drifting up round an enraged creature (on its root; switched on
-- and off, never left on a defeated one).
function CreatureFx.embers(root: BasePart, on: boolean, color: Color3)
	local existing = root:FindFirstChild("RC_Embers")
	if not on then
		if existing then
			existing:Destroy()
		end
		return
	end
	if existing then
		return
	end
	local e = Instance.new("ParticleEmitter")
	e.Name = "RC_Embers"
	e.Color = ColorSequence.new(color:Lerp(Color3.fromRGB(255, 80, 50), 0.5))
	e.LightEmission = 1
	e.Rate = 6
	e.Lifetime = NumberRange.new(0.8, 1.4)
	e.Speed = NumberRange.new(1, 3)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Acceleration = Vector3.new(0, 4, 0)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency =
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	e.Parent = root
end

return CreatureFx
