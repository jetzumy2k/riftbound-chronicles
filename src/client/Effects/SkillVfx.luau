--!strict
--[[
	SkillVfx — layered, non-graphic skill effects (Phase 5 rework, D-45).
	Stylised light, ice, fire, earth and magic only: no blood, no gore
	(CLAUDE.md §14 / §18).

	Every skill has a recipe in SkillDefinitions.fx:
	  element  colour palette (Steel, Earth, Holy, Nature, Frost, Fire,
	           Arcane, Shadow, Wind, Storm)
	  cast     at the cast start: Weapon (glint + sparks), Hands (glowing
	           orbs at the hands), Raise (light rising from the hands),
	           Circle (rune circle under the caster)
	  travel   at the Hit frame: Bolt, Orb, Arrow, Lance, Missiles or None
	  impact   when the server's hit lands on someone: Slash, Burst,
	           Explosion, Shatter, Pillar, Ward, Heal, Sigil, Venom, Quake
	  area     area skills: Nova, Whirl, Quake, Rain, Meteor, Blizzard,
	           Circle (a dome of light over allies)
	Combo hits get a bigger impact, a ring of light and a "COMBO" title.

	Effects are client-only anchored, non-colliding, non-queryable parts and
	short particle bursts, cleaned up with Debris. Particle counts stay small
	for phones.
]]

local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local SkillVfx = {}

local SPARKLES = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"
local WHITE = Color3.new(1, 1, 1)

export type Palette = { main: Color3, light: Color3, dark: Color3 }

local PALETTES: { [string]: Palette } = {
	Steel = {
		main = Color3.fromRGB(215, 228, 255),
		light = Color3.fromRGB(255, 244, 210),
		dark = Color3.fromRGB(120, 140, 190),
	},
	Earth = {
		main = Color3.fromRGB(214, 160, 92),
		light = Color3.fromRGB(255, 220, 150),
		dark = Color3.fromRGB(110, 78, 46),
	},
	Holy = {
		main = Color3.fromRGB(255, 226, 140),
		light = Color3.fromRGB(255, 252, 228),
		dark = Color3.fromRGB(220, 170, 70),
	},
	Nature = {
		main = Color3.fromRGB(120, 230, 110),
		light = Color3.fromRGB(210, 255, 180),
		dark = Color3.fromRGB(50, 130, 60),
	},
	Frost = {
		main = Color3.fromRGB(140, 210, 255),
		light = Color3.fromRGB(230, 248, 255),
		dark = Color3.fromRGB(70, 130, 210),
	},
	Fire = {
		main = Color3.fromRGB(255, 120, 40),
		light = Color3.fromRGB(255, 226, 120),
		dark = Color3.fromRGB(190, 50, 20),
	},
	Arcane = {
		main = Color3.fromRGB(170, 110, 255),
		light = Color3.fromRGB(232, 205, 255),
		dark = Color3.fromRGB(90, 50, 190),
	},
	Shadow = {
		main = Color3.fromRGB(165, 80, 220),
		light = Color3.fromRGB(240, 170, 255),
		dark = Color3.fromRGB(70, 30, 110),
	},
	Wind = {
		main = Color3.fromRGB(150, 240, 220),
		light = Color3.fromRGB(235, 255, 250),
		dark = Color3.fromRGB(70, 170, 160),
	},
	Storm = {
		main = Color3.fromRGB(150, 200, 255),
		light = Color3.fromRGB(255, 250, 190),
		dark = Color3.fromRGB(70, 90, 210),
	},
}

function SkillVfx.palette(element: string?): Palette
	return PALETTES[element or ""] or PALETTES.Steel
end

--------------------------------------------------------------------------------
-- Primitives
--------------------------------------------------------------------------------

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
	cframe: CFrame,
	color: Color3,
	shape: Enum.PartType?,
	material: Enum.Material?
): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = material or Enum.Material.Neon
	p.Color = color
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.CFrame = cframe
	p.Parent = folder()
	return p
end

local function tween(
	instance: Instance,
	seconds: number,
	goal: { [string]: any },
	style: Enum.EasingStyle?,
	direction: Enum.EasingDirection?,
	delay: number?
)
	TweenService:Create(
		instance,
		TweenInfo.new(
			seconds,
			style or Enum.EasingStyle.Quad,
			direction or Enum.EasingDirection.Out,
			0,
			false,
			delay or 0
		),
		goal
	):Play()
end

local function fade(p: BasePart, seconds: number, delay: number?)
	tween(p, seconds, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, delay)
	Debris:AddItem(p, seconds + (delay or 0) + 0.05)
end

local function light(position: Vector3, color: Color3, range: number, seconds: number)
	local holder = part(Vector3.one * 0.2, CFrame.new(position), color)
	holder.Transparency = 1
	local glow = Instance.new("PointLight")
	glow.Color = color
	glow.Range = range
	glow.Brightness = 3
	glow.Shadows = false
	glow.Parent = holder
	tween(glow, seconds, { Brightness = 0 })
	Debris:AddItem(holder, seconds + 0.05)
end

export type BurstOptions = {
	texture: string?,
	count: number?,
	speed: NumberRange?,
	size: number?,
	lifetime: NumberRange?,
	spread: number?,
	acceleration: Vector3?,
	direction: Vector3?,
	lightEmission: number?,
	colorTo: Color3?,
}

-- A one-shot particle burst at `position`.
function SkillVfx.particles(position: Vector3, color: Color3, options: BurstOptions?)
	local o: BurstOptions = options or {} :: BurstOptions
	local holder =
		part(Vector3.one * 0.2, CFrame.lookAt(position, position + (o.direction or Vector3.yAxis)), color)
	holder.Transparency = 1
	local attachment = Instance.new("Attachment")
	attachment.Parent = holder
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = o.texture or SPARKLES
	emitter.Color = ColorSequence.new(color, o.colorTo or color)
	emitter.LightEmission = o.lightEmission or 1
	local size = o.size or 0.6
	emitter.Size =
		NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency =
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = o.lifetime or NumberRange.new(0.4, 0.8)
	emitter.Speed = o.speed or NumberRange.new(6, 14)
	local spread = o.spread or 180
	emitter.SpreadAngle = Vector2.new(spread, spread)
	emitter.Acceleration = o.acceleration or Vector3.zero
	emitter.EmissionDirection = Enum.NormalId.Front
	emitter.Rate = 0
	emitter.Parent = attachment
	emitter:Emit(o.count or 18)
	Debris:AddItem(holder, 2.5)
end

-- Expanding ring of light flat on the ground.
function SkillVfx.shockwave(position: Vector3, radius: number, color: Color3, seconds: number?)
	local time = seconds or 0.45
	local ring = part(
		Vector3.new(0.2, 1, 1),
		CFrame.new(position + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		color,
		Enum.PartType.Cylinder
	)
	ring.Transparency = 0.15
	tween(ring, time, { Size = Vector3.new(0.12, radius * 2, radius * 2) }, Enum.EasingStyle.Quart)
	fade(ring, time * 0.8, time * 0.25)
	-- A bright thin edge riding the front.
	local edge = part(
		Vector3.new(0.3, 1.2, 1.2),
		CFrame.new(position + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		WHITE,
		Enum.PartType.Cylinder,
		Enum.Material.ForceField
	)
	tween(edge, time, { Size = Vector3.new(0.3, radius * 2.05, radius * 2.05) }, Enum.EasingStyle.Quart)
	fade(edge, time * 0.6, time * 0.4)
end

-- Glowing ball that swells and fades.
function SkillVfx.flash(position: Vector3, color: Color3, size: number, seconds: number?)
	local time = seconds or 0.3
	local ball = part(Vector3.one * size * 0.25, CFrame.new(position), color, Enum.PartType.Ball)
	ball.Transparency = 0.1
	tween(ball, time, { Size = Vector3.one * size })
	fade(ball, time, time * 0.2)
	local core = part(Vector3.one * size * 0.15, CFrame.new(position), WHITE, Enum.PartType.Ball)
	tween(core, time * 0.7, { Size = Vector3.one * size * 0.5 })
	fade(core, time * 0.7)
	light(position, color, size * 3, time + 0.2)
end

-- Rotating rune circle on the ground for `seconds`.
function SkillVfx.runeCircle(position: Vector3, radius: number, color: Color3, seconds: number)
	local holder = Instance.new("Model")
	holder.Name = "Rune"
	local pieces = {}
	for ringIndex, r in { radius, radius * 0.66 } do
		local segments = if ringIndex == 1 then 18 else 10
		for i = 0, segments - 1 do
			if i % 3 == 2 then
				continue
			end
			local a0 = (i / segments) * math.pi * 2
			local a1 = ((i + 0.85) / segments) * math.pi * 2
			local p0 = Vector3.new(math.cos(a0) * r, 0, math.sin(a0) * r)
			local p1 = Vector3.new(math.cos(a1) * r, 0, math.sin(a1) * r)
			local piece = part(
				Vector3.new((p1 - p0).Magnitude, 0.06, if ringIndex == 1 then 0.22 else 0.14),
				CFrame.lookAt((p0 + p1) / 2, p1) * CFrame.Angles(0, math.rad(90), 0),
				if ringIndex == 1 then color else WHITE
			)
			piece.Transparency = 1
			piece.Parent = holder
			table.insert(pieces, piece)
		end
	end
	holder.Parent = folder()
	for _, piece in pieces do
		tween(piece, 0.2, { Transparency = 0.15 })
	end
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - started
		if t > seconds or holder.Parent == nil then
			connection:Disconnect()
			return
		end
		holder:PivotTo(CFrame.new(position + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, t * 2.2, 0))
	end)
	task.delay(seconds, function()
		for _, piece in pieces do
			fade(piece, 0.25)
		end
		Debris:AddItem(holder, 0.4)
	end)
end

-- Vertical beam of light.
function SkillVfx.beam(position: Vector3, height: number, color: Color3, width: number)
	local beam = part(
		Vector3.new(height, width * 0.3, width * 0.3),
		CFrame.new(position + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		color,
		Enum.PartType.Cylinder
	)
	beam.Transparency = 0.1
	tween(beam, 0.15, { Size = Vector3.new(height, width, width) })
	fade(beam, 0.45, 0.15)
	local core = part(
		Vector3.new(height, width * 0.35, width * 0.35),
		CFrame.new(position + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		WHITE,
		Enum.PartType.Cylinder
	)
	fade(core, 0.4, 0.1)
end

--------------------------------------------------------------------------------
-- Body helpers
--------------------------------------------------------------------------------

local function rootOf(model: Model?): BasePart?
	if model == nil then
		return nil
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function partOf(model: Model, names: { string }): BasePart?
	for _, name in names do
		local p = model:FindFirstChild(name)
		if p and p:IsA("BasePart") then
			return p
		end
	end
	return rootOf(model)
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Include

-- The ground under a point (the world map), or the point lowered to the feet.
function SkillVfx.groundAt(point: Vector3): Vector3
	local world = Workspace:FindFirstChild("RC_World")
	if world then
		groundParams.FilterDescendantsInstances = { world }
		local hit = Workspace:Raycast(point + Vector3.new(0, 8, 0), Vector3.new(0, -40, 0), groundParams)
		if hit then
			return hit.Position
		end
	end
	return point - Vector3.new(0, 3, 0)
end

local function feet(model: Model): Vector3?
	local root = rootOf(model)
	if root == nil then
		return nil
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	return root.Position
		- Vector3.new(0, (if humanoid then humanoid.HipHeight else 2) + root.Size.Y / 2 - 0.08, 0)
end

local function chest(model: Model): Vector3?
	local p = partOf(model, { "UpperTorso", "Torso", "HumanoidRootPart" })
	return if p then p.Position else nil
end

-- A glowing orb that follows a body part for `seconds`.
local function handOrb(model: Model, side: "Left" | "Right", color: Color3, seconds: number)
	local hand = partOf(model, { side .. "Hand", side .. " Arm" })
	if hand == nil then
		return
	end
	local orb = part(Vector3.one * 0.5, hand.CFrame, color, Enum.PartType.Ball)
	orb.Transparency = 0.15
	tween(orb, seconds * 0.6, { Size = Vector3.one * 1.3 })
	local glow = Instance.new("PointLight")
	glow.Color = color
	glow.Range = 8
	glow.Brightness = 2
	glow.Parent = orb
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		if os.clock() - started > seconds or hand.Parent == nil or orb.Parent == nil then
			connection:Disconnect()
			return
		end
		orb.CFrame = hand.CFrame * CFrame.new(0, -0.6, 0)
	end)
	fade(orb, 0.2, seconds)
end

--------------------------------------------------------------------------------
-- Cast (at the start of the animation)
--------------------------------------------------------------------------------

function SkillVfx.cast(fx: any, model: Model, seconds: number)
	local pal = SkillVfx.palette(fx.element)
	local base = feet(model)
	if fx.cast == "Hands" then
		handOrb(model, "Right", pal.main, seconds)
		handOrb(model, "Left", pal.light, seconds * 0.8)
	elseif fx.cast == "Raise" then
		handOrb(model, "Right", pal.main, seconds)
		handOrb(model, "Left", pal.main, seconds)
		local top = partOf(model, { "Head" })
		if top then
			SkillVfx.particles(top.Position + Vector3.new(0, 1.5, 0), pal.light, {
				count = 16,
				speed = NumberRange.new(2, 5),
				acceleration = Vector3.new(0, 6, 0),
				spread = 60,
			})
		end
		if base then
			SkillVfx.runeCircle(base, 3.2, pal.main, seconds + 0.2)
		end
	elseif fx.cast == "Circle" then
		if base then
			SkillVfx.runeCircle(base, 4, pal.main, seconds + 0.3)
		end
	else -- Weapon: a glint and sparks along the weapon arm
		local hand = partOf(model, { "RightHand", "Right Arm" })
		if hand then
			SkillVfx.particles(hand.Position, pal.light, {
				count = 10,
				speed = NumberRange.new(3, 7),
				size = 0.45,
			})
		end
	end
end

--------------------------------------------------------------------------------
-- Travel (at the Hit frame)
--------------------------------------------------------------------------------

-- A projectile from `from` to `target`, arriving after the server's travel time.
function SkillVfx.projectile(fx: any, model: Model, target: Model, speed: number, onArrive: (() -> ())?)
	local pal = SkillVfx.palette(fx.element)
	local fromPart = if fx.travel == "Arrow"
		then partOf(model, { "LeftHand", "Left Arm" })
		else partOf(model, { "RightHand", "Right Arm" })
	local targetRoot = rootOf(target)
	if fromPart == nil or targetRoot == nil then
		return
	end
	local from = fromPart.Position
	local to = targetRoot.Position + Vector3.new(0, 0.8, 0)
	local distance = (to - from).Magnitude
	if distance < 1 then
		return
	end
	local travel = math.clamp(distance / math.max(speed, 1), 0.05, 1.5)
	local kind = fx.travel
	local size = if kind == "Arrow"
		then Vector3.new(0.18, 0.18, 2.6)
		elseif kind == "Lance" then Vector3.new(0.4, 0.4, 4)
		elseif kind == "Orb" then Vector3.one * 1.8
		elseif kind == "Missiles" then Vector3.one * 0.8
		else Vector3.one * 1.1
	local round = kind == "Orb" or kind == "Bolt" or kind == "Missiles"
	local bolt = part(size, CFrame.lookAt(from, to), pal.main, if round then Enum.PartType.Ball else nil)
	-- Bright core and a light.
	local glow = Instance.new("PointLight")
	glow.Color = pal.main
	glow.Range = 10
	glow.Brightness = 2.5
	glow.Parent = bolt
	-- Trail.
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, math.max(size.Y, 0.4) * 0.5, 0)
	a0.Parent = bolt
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -math.max(size.Y, 0.4) * 0.5, 0)
	a1.Parent = bolt
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(pal.light, pal.main)
	trail.LightEmission = 1
	trail.Lifetime = if kind == "Orb" or kind == "Lance" then 0.35 else 0.2
	trail.Transparency = NumberSequence.new(0.05, 1)
	trail.Parent = bolt
	-- Element particles streaming behind (fire smoke, frost sparkles...).
	local emitterAttachment = Instance.new("Attachment")
	emitterAttachment.Parent = bolt
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = if fx.element == "Fire" then FIRE elseif fx.element == "Nature" then SMOKE else SPARKLES
	emitter.Color = ColorSequence.new(pal.light, pal.main)
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, size.Y * 0.6 + 0.2),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new(0.2, 1)
	emitter.Lifetime = NumberRange.new(0.2, 0.35)
	emitter.Speed = NumberRange.new(0.5, 2)
	emitter.Rate = 40
	emitter.Parent = emitterAttachment

	local curve = if kind == "Missiles"
		then Vector3.new(math.random(-3, 3), math.random(1, 3), 0)
		else Vector3.zero
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local alpha = math.clamp((os.clock() - started) / travel, 0, 1)
		local goal = (targetRoot.Position + Vector3.new(0, 0.8, 0))
		local point = from:Lerp(goal, alpha) + curve * math.sin(alpha * math.pi)
		local ahead = from:Lerp(goal, math.min(alpha + 0.05, 1))
			+ curve * math.sin(math.min(alpha + 0.05, 1) * math.pi)
		bolt.CFrame = if (ahead - point).Magnitude > 0.01
			then CFrame.lookAt(point, ahead)
			else CFrame.new(point)
		if alpha >= 1 then
			connection:Disconnect()
			emitter.Enabled = false
			bolt.Transparency = 1
			Debris:AddItem(bolt, 0.5)
			if onArrive then
				onArrive()
			end
		end
	end)
end

--------------------------------------------------------------------------------
-- Impact (when the hit lands on someone)
--------------------------------------------------------------------------------

function SkillVfx.impact(fx: any, target: Model, big: boolean?)
	local pal = SkillVfx.palette(fx.element)
	local at = chest(target)
	local ground = feet(target)
	if at == nil then
		return
	end
	local scale = if big then 1.6 else 1
	local style = fx.impact
	if style == "Slash" then
		for i = 0, 1 do
			local tilt = if i == 0 then 35 else -35
			local slash = part(
				Vector3.new(0.12, 0.5, 5 * scale),
				CFrame.new(at) * CFrame.Angles(math.rad(tilt), math.rad(math.random(0, 180)), 0),
				pal.light
			)
			tween(slash, 0.15, { Size = Vector3.new(0.05, 0.15, 7 * scale) })
			fade(slash, 0.2, 0.05 + i * 0.05)
		end
		SkillVfx.particles(at, pal.light, { count = 12, size = 0.4, speed = NumberRange.new(8, 16) })
	elseif style == "Explosion" then
		SkillVfx.flash(at, pal.main, 6 * scale, 0.35)
		SkillVfx.particles(at, pal.light, { count = 24, speed = NumberRange.new(10, 22), size = 0.6 })
		SkillVfx.particles(at, pal.dark, {
			texture = SMOKE,
			count = 8,
			speed = NumberRange.new(2, 6),
			size = 2.4,
			lifetime = NumberRange.new(0.6, 1.1),
			lightEmission = 0,
		})
		if fx.element == "Fire" then
			SkillVfx.particles(
				at,
				pal.main,
				{ texture = FIRE, count = 12, speed = NumberRange.new(4, 9), size = 1.6 }
			)
		end
		if ground then
			SkillVfx.shockwave(ground, 5 * scale, pal.main)
		end
	elseif style == "Shatter" then
		-- Shards of ice burst outward.
		for _ = 1, if big then 10 else 6 do
			local dir = Vector3.new(math.random() - 0.5, math.random() * 0.8, math.random() - 0.5).Unit
			local shard = part(
				Vector3.new(0.35, 0.35, 1.4),
				CFrame.lookAt(at, at + dir),
				pal.light,
				nil,
				Enum.Material.Glass
			)
			shard.Transparency = 0.2
			tween(shard, 0.4, { CFrame = CFrame.lookAt(at + dir * 5 * scale, at + dir * 6 * scale) })
			fade(shard, 0.3, 0.15)
		end
		SkillVfx.flash(at, pal.main, 3.5 * scale, 0.25)
		SkillVfx.particles(at, pal.light, { count = 16, speed = NumberRange.new(6, 12), size = 0.5 })
	elseif style == "Pillar" then
		if ground then
			SkillVfx.beam(ground, 16, pal.main, 3 * scale)
			SkillVfx.shockwave(ground, 4 * scale, pal.light)
		end
		SkillVfx.particles(
			at,
			pal.light,
			{ count = 14, acceleration = Vector3.new(0, 10, 0), speed = NumberRange.new(2, 5) }
		)
	elseif style == "Ward" then
		local bubble =
			part(Vector3.one * 2, CFrame.new(at), pal.main, Enum.PartType.Ball, Enum.Material.ForceField)
		tween(bubble, 0.3, { Size = Vector3.one * 7 })
		fade(bubble, 0.4, 0.3)
		SkillVfx.particles(at, pal.light, { count = 12, speed = NumberRange.new(2, 5), size = 0.5 })
	elseif style == "Heal" then
		SkillVfx.particles(at, pal.light, {
			count = 20,
			speed = NumberRange.new(1, 4),
			acceleration = Vector3.new(0, 7, 0),
			spread = 70,
			size = 0.55,
		})
		-- A soft plus of light.
		for _, axis in { Vector3.new(1.8, 0.35, 0.35), Vector3.new(0.35, 1.8, 0.35) } do
			local bar = part(axis, CFrame.new(at + Vector3.new(0, 2.6, 0)), pal.light)
			bar.Transparency = 0.2
			tween(bar, 0.6, { CFrame = CFrame.new(at + Vector3.new(0, 4, 0)) })
			fade(bar, 0.4, 0.25)
		end
		if ground then
			SkillVfx.shockwave(ground, 3.2, pal.main, 0.5)
		end
	elseif style == "Sigil" then
		if ground then
			SkillVfx.runeCircle(ground, 3, pal.main, 0.9)
		end
		SkillVfx.flash(at + Vector3.new(0, 2.6, 0), pal.main, 2, 0.4)
	elseif style == "Venom" then
		SkillVfx.particles(at, pal.main, {
			texture = SMOKE,
			count = 10,
			size = 1.8,
			speed = NumberRange.new(1, 4),
			lifetime = NumberRange.new(0.6, 1),
			lightEmission = 0.3,
		})
		SkillVfx.particles(at, pal.light, { count = 14, speed = NumberRange.new(5, 10), size = 0.4 })
		SkillVfx.flash(at, pal.main, 2.5, 0.25)
	elseif style == "Quake" then
		if ground then
			SkillVfx.shockwave(ground, 5 * scale, pal.main)
			SkillVfx.particles(ground, pal.dark, {
				texture = SMOKE,
				count = 8,
				size = 2,
				speed = NumberRange.new(2, 6),
				lightEmission = 0,
				spread = 60,
			})
		end
		SkillVfx.flash(at, pal.light, 3 * scale, 0.25)
	else -- Burst
		SkillVfx.flash(at, pal.main, 3.6 * scale, 0.28)
		SkillVfx.particles(at, pal.light, { count = 14, speed = NumberRange.new(6, 14), size = 0.5 })
	end
	if big and ground then
		-- Combo: an extra ring of light.
		SkillVfx.shockwave(ground, 7, WHITE, 0.5)
	end
end

--------------------------------------------------------------------------------
-- Areas
--------------------------------------------------------------------------------

local function rocks(center: Vector3, radius: number, color: Color3)
	for _ = 1, 7 do
		local a = math.random() * math.pi * 2
		local r = math.random() * radius * 0.8
		local at = center + Vector3.new(math.cos(a) * r, 0.3, math.sin(a) * r)
		local rock =
			part(Vector3.one * (0.5 + math.random() * 0.8), CFrame.new(at), color, nil, Enum.Material.Slate)
		tween(rock, 0.22, {
			CFrame = CFrame.new(at + Vector3.new(0, 2 + math.random() * 2, 0))
				* CFrame.Angles(math.random(), math.random(), 0),
		})
		tween(rock, 0.25, { CFrame = CFrame.new(at) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0.22)
		fade(rock, 0.3, 0.45)
	end
end

local function fallingShards(
	center: Vector3,
	radius: number,
	pal: Palette,
	count: number,
	kind: "Arrow" | "Ice"
)
	for _ = 1, count do
		local a = math.random() * math.pi * 2
		local r = math.random() * radius
		local land = center + Vector3.new(math.cos(a) * r, 0.2, math.sin(a) * r)
		local from = land + Vector3.new(math.random(-3, 3), 26, math.random(-3, 3))
		local size = if kind == "Arrow" then Vector3.new(0.14, 0.14, 2.6) else Vector3.new(0.5, 0.5, 2)
		local shard = part(
			size,
			CFrame.lookAt(from, land),
			if kind == "Arrow" then pal.light else pal.main,
			nil,
			if kind == "Ice" then Enum.Material.Glass else nil
		)
		local fall = 0.22 + math.random() * 0.12
		tween(
			shard,
			fall,
			{ CFrame = CFrame.lookAt(land, land + (land - from).Unit) },
			Enum.EasingStyle.Linear
		)
		fade(shard, 0.2, fall)
	end
end

--[[
	An area skill landing (one wave). `center` is the ground point; `wave`
	starts at 1. Rain / Blizzard / Meteor fall for ~0.3 s before landing.
]]
function SkillVfx.area(fx: any, center: Vector3, radius: number, wave: number, caster: Model?)
	local pal = SkillVfx.palette(fx.element)
	local area = fx.area
	if area == "Nova" then
		SkillVfx.shockwave(center, radius, pal.main, 0.5)
		SkillVfx.shockwave(center, radius * 0.6, pal.light, 0.35)
		SkillVfx.flash(center + Vector3.new(0, 2.5, 0), pal.main, 6, 0.35)
		SkillVfx.particles(center + Vector3.new(0, 1, 0), pal.light, {
			count = 26,
			speed = NumberRange.new(radius * 1.2, radius * 2),
			spread = 90,
			direction = Vector3.yAxis,
			size = 0.6,
		})
	elseif area == "Whirl" then
		-- Crescents around the caster.
		local origin = center + Vector3.new(0, 2.6, 0)
		for i = 0, 5 do
			local a = (i / 6) * math.pi * 2 + wave
			local offset = Vector3.new(math.cos(a), 0, math.sin(a)) * radius * 0.55
			local arc = part(
				Vector3.new(0.12, 0.4, radius * 0.7),
				CFrame.lookAt(origin + offset, origin + offset + Vector3.new(-math.sin(a), 0, math.cos(a))),
				pal.light
			)
			arc.Transparency = 0.1
			tween(arc, 0.25, { CFrame = arc.CFrame * CFrame.Angles(0, math.rad(60), 0) })
			fade(arc, 0.2, 0.08)
		end
		SkillVfx.shockwave(center, radius, pal.main, 0.35)
		SkillVfx.particles(
			center,
			pal.dark,
			{ texture = SMOKE, count = 6, size = 1.6, speed = NumberRange.new(4, 8), lightEmission = 0 }
		)
	elseif area == "Quake" then
		SkillVfx.shockwave(center, radius, pal.main, 0.5)
		SkillVfx.shockwave(center, radius * 0.5, pal.light, 0.3)
		rocks(center, radius, pal.dark)
		SkillVfx.particles(center, pal.dark, {
			texture = SMOKE,
			count = 12,
			size = 2.5,
			speed = NumberRange.new(3, 8),
			lightEmission = 0,
			spread = 70,
		})
		SkillVfx.flash(center + Vector3.new(0, 1, 0), pal.light, 5, 0.3)
	elseif area == "Rain" then
		fallingShards(center, radius, pal, 9, "Arrow")
		task.delay(0.28, SkillVfx.shockwave, center, radius, pal.main, 0.35)
		if fx.element == "Nature" then
			task.delay(0.3, SkillVfx.particles, center, pal.main, {
				texture = SMOKE,
				count = 10,
				size = 3,
				speed = NumberRange.new(1, 3),
				lightEmission = 0.2,
				spread = 80,
			})
		end
	elseif area == "Blizzard" then
		fallingShards(center, radius, pal, 8, "Ice")
		task.delay(0.28, function()
			SkillVfx.shockwave(center, radius, pal.light, 0.4)
			SkillVfx.particles(
				center + Vector3.new(0, 2, 0),
				pal.light,
				{ count = 18, speed = NumberRange.new(2, 6), size = 0.5, spread = 90 }
			)
		end)
	elseif area == "Meteor" then
		local from = center + Vector3.new(-12, 46, -8)
		local rock = part(Vector3.one * 4, CFrame.new(from), pal.main, Enum.PartType.Ball)
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, 1.6, 0)
		a0.Parent = rock
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, -1.6, 0)
		a1.Parent = rock
		local trail = Instance.new("Trail")
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Color = ColorSequence.new(pal.light, pal.main)
		trail.LightEmission = 1
		trail.Lifetime = 0.45
		trail.Transparency = NumberSequence.new(0, 1)
		trail.Parent = rock
		local emitterAttachment = Instance.new("Attachment")
		emitterAttachment.Parent = rock
		local emitter = Instance.new("ParticleEmitter")
		emitter.Texture = if fx.element == "Fire" then FIRE else SPARKLES
		emitter.Color = ColorSequence.new(pal.light, pal.main)
		emitter.LightEmission = 1
		emitter.Size = NumberSequence.new(2.5, 0)
		emitter.Lifetime = NumberRange.new(0.3, 0.5)
		emitter.Rate = 60
		emitter.Parent = emitterAttachment
		tween(
			rock,
			0.32,
			{ CFrame = CFrame.new(center + Vector3.new(0, 1.5, 0)) },
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.In
		)
		task.delay(0.32, function()
			rock:Destroy()
			SkillVfx.flash(center + Vector3.new(0, 2, 0), pal.main, radius * 1.1, 0.45)
			SkillVfx.shockwave(center, radius, pal.main, 0.5)
			SkillVfx.shockwave(center, radius * 0.6, WHITE, 0.35)
			SkillVfx.particles(
				center + Vector3.new(0, 1, 0),
				pal.light,
				{ count = 30, speed = NumberRange.new(14, 26), spread = 80, size = 0.8 }
			)
			SkillVfx.particles(center + Vector3.new(0, 1, 0), pal.dark, {
				texture = SMOKE,
				count = 12,
				size = 4,
				speed = NumberRange.new(3, 8),
				lightEmission = 0,
				lifetime = NumberRange.new(0.8, 1.4),
			})
			if fx.element == "Fire" then
				SkillVfx.particles(
					center,
					pal.main,
					{ texture = FIRE, count = 16, size = 3, speed = NumberRange.new(3, 8), spread = 70 }
				)
			end
			rocks(center, radius, pal.dark)
		end)
	elseif area == "Circle" then
		-- A dome of light over the allies.
		local dome =
			part(Vector3.one * 2, CFrame.new(center), pal.main, Enum.PartType.Ball, Enum.Material.ForceField)
		tween(dome, 0.4, { Size = Vector3.one * radius * 2 })
		fade(dome, 0.6, 0.5)
		SkillVfx.shockwave(center, radius, pal.light, 0.5)
		SkillVfx.particles(
			center + Vector3.new(0, 1, 0),
			pal.light,
			{ count = 22, speed = NumberRange.new(2, 6), acceleration = Vector3.new(0, 5, 0), spread = 90 }
		)
	end
	if caster and (area == "Nova" or area == "Whirl" or area == "Quake") then
		local at = chest(caster)
		if at then
			light(at, pal.main, radius * 1.5, 0.4)
		end
	end
end

--------------------------------------------------------------------------------
-- Combo title
--------------------------------------------------------------------------------

-- Big floating "COMBO · SHATTER" over the target.
function SkillVfx.comboTitle(target: Model, name: string, color: Color3?)
	local anchor = partOf(target, { "Head", "HumanoidRootPart" })
	if anchor == nil then
		return
	end
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "RC_Combo"
	billboard.Adornee = anchor
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Size = UDim2.fromOffset(260, 60)
	billboard.StudsOffset = Vector3.new(0, 4.2, 0)
	billboard.MaxDistance = 140
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = `COMBO · {string.upper(name)}!`
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.TextColor3 = color or Color3.fromRGB(255, 210, 110)
	label.TextStrokeColor3 = Color3.fromRGB(40, 16, 0)
	label.TextStrokeTransparency = 0
	label.Parent = billboard
	local scale = Instance.new("UIScale")
	scale.Scale = 1.6
	scale.Parent = label
	billboard.Parent = anchor
	tween(scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
	tween(
		billboard,
		1.1,
		{ StudsOffset = Vector3.new(0, 6, 0) },
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out,
		0.3
	)
	tween(
		label,
		0.4,
		{ TextTransparency = 1, TextStrokeTransparency = 1 },
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.In,
		1
	)
	Debris:AddItem(billboard, 1.5)
end

return SkillVfx
