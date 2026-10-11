--!strict
--[[
	CombatVfx — client-side, non-graphic combat effects (CLAUDE.md §14/§18:
	stylised light, no blood). One effect per combo step (BasicAttacks.vfx):

	  SlashAcross   glowing crescent sweeping right -> left
	  SlashRising   crescent rising left -> right
	  Cleave        vertical crescent + light shockwave on the ground
	  Bolt          radiant bolt from the staff
	  Nova          ring of light at the caster + pillar of light on the target
	  Missile       arcane missile from the wand
	  PalmMissile   arcane missile from the open left hand
	  Burst         large arcane orb that bursts on arrival
	  Arrow         arrow with a light trail
	  PowerArrow    bright, heavier arrow that bursts on arrival

	Also: castCircle (finisher wind-ups), chargeGlow (bow draw), targetRing.

	Every effect is a few anchored, non-colliding, non-queryable parts in a
	client-only folder, cleaned up with Debris. Colour comes from the actor's
	outfit glow so effects match each character's look. Projectiles fly at
	the step's server projectile speed, so they arrive when the damage does.
]]

local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local CombatVfx = {}

local FOLDER_NAME = "RC_ClientVfx"
local DEFAULT_GLOW = Color3.fromRGB(255, 220, 140)
local WHITE = Color3.new(1, 1, 1)

local function folder(): Folder
	local existing = Workspace:FindFirstChild(FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = FOLDER_NAME
	created.Parent = Workspace
	return created
end

local function vfxPart(size: Vector3, cframe: CFrame, color: Color3, shape: Enum.PartType?): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Size = size
	if shape then
		part.Shape = shape
	end
	part.CFrame = cframe
	part.Parent = folder()
	return part
end

local function fadeOut(part: BasePart, seconds: number, delaySeconds: number?)
	TweenService:Create(
		part,
		TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, delaySeconds or 0),
		{ Transparency = 1 }
	):Play()
	Debris:AddItem(part, seconds + (delaySeconds or 0) + 0.05)
end

local function rootOf(model: Model): BasePart?
	local root = model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function partOf(model: Model, names: { string }): BasePart?
	for _, name in names do
		local part = model:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			return part
		end
	end
	return rootOf(model)
end

local function floorUnder(model: Model): Vector3?
	local root = rootOf(model)
	if root == nil then
		return nil
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	return root.Position
		- Vector3.new(0, (if humanoid then humanoid.HipHeight else 2) + root.Size.Y / 2 - 0.08, 0)
end

-- The actor's outfit glow colour (falls back to warm gold).
function CombatVfx.glowColor(model: Model): Color3
	local outfit = model:FindFirstChild("RC_Outfit")
	if outfit then
		for _, part in outfit:GetChildren() do
			if part:IsA("BasePart") and part:GetAttribute("RC_Role") == "glow" then
				return part.Color
			end
		end
	end
	return DEFAULT_GLOW
end

--------------------------------------------------------------------------------
-- Slashes
--------------------------------------------------------------------------------

export type SlashStyle = "Across" | "Rising" | "Cleave"

-- A crescent of light in front of the actor; segments appear in sweep order.
function CombatVfx.slashArc(model: Model, style: SlashStyle)
	local root = rootOf(model)
	if root == nil then
		return
	end
	local color = CombatVfx.glowColor(model)
	local tilt, height, radius, sweep, reverse
	if style == "Rising" then
		tilt, height, radius, sweep, reverse = 30, 0.9, 3.6, 150, true
	elseif style == "Cleave" then
		tilt, height, radius, sweep, reverse = 90, 0.4, 4.2, 140, true
	else
		tilt, height, radius, sweep, reverse = -18, 0.7, 3.8, 160, false
	end
	local center = root.CFrame * CFrame.new(0, height, -1.6) * CFrame.Angles(0, 0, math.rad(tilt))
	local segments = 12
	for i = 0, segments - 1 do
		local order = if reverse then segments - 1 - i else i
		local a0 = math.rad(sweep / 2 - i * (sweep / segments))
		local a1 = math.rad(sweep / 2 - (i + 1) * (sweep / segments))
		local p0 = center * Vector3.new(math.sin(a0) * radius, 0, -math.cos(a0) * radius * 0.55)
		local p1 = center * Vector3.new(math.sin(a1) * radius, 0, -math.cos(a1) * radius * 0.55)
		local middle = (p0 + p1) / 2
		-- Thick in the middle of the sweep, thin at the tips.
		local thickness = 0.06 + 0.32 * math.sin(math.pi * (i + 0.5) / segments)
		local part = vfxPart(
			Vector3.new((p1 - p0).Magnitude + 0.12, thickness, 0.08),
			CFrame.lookAt(middle, p1) * CFrame.Angles(0, math.rad(90), 0),
			if i % 3 == 1 then WHITE else color
		)
		part.Transparency = 1
		local appear = order * 0.008
		TweenService:Create(
			part,
			TweenInfo.new(0.02, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, appear),
			{
				Transparency = 0.1,
			}
		):Play()
		fadeOut(part, 0.26, appear + 0.03)
	end
end

-- Expanding ring of light on the ground.
function CombatVfx.groundShock(position: Vector3, color: Color3, radius: number)
	local segments = 18
	for i = 0, segments - 1 do
		local a = (i / segments) * math.pi * 2
		local part = vfxPart(
			Vector3.new(0.9, 0.12, 0.22),
			CFrame.new(position + Vector3.new(math.cos(a), 0, math.sin(a)) * 0.6) * CFrame.Angles(0, -a, 0),
			if i % 2 == 0 then color else WHITE
		)
		part.Transparency = 0.1
		TweenService:Create(part, TweenInfo.new(0.32, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			CFrame = CFrame.new(position + Vector3.new(math.cos(a), 0.05, math.sin(a)) * radius)
				* CFrame.Angles(0, -a, 0),
			Size = Vector3.new(radius * 0.4, 0.06, 0.16),
		}):Play()
		fadeOut(part, 0.3, 0.12)
	end
end

--------------------------------------------------------------------------------
-- Casting
--------------------------------------------------------------------------------

-- Rotating, expanding magic circle at the actor's feet.
function CombatVfx.castCircle(model: Model, seconds: number)
	local floor = floorUnder(model)
	if floor == nil then
		return
	end
	local color = CombatVfx.glowColor(model)
	local holder = Instance.new("Model")
	holder.Name = "CastCircle"
	local segments, radius = 16, 2.6
	for i = 0, segments - 1 do
		local a0 = (i / segments) * math.pi * 2
		local a1 = ((i + 1) / segments) * math.pi * 2
		local p0 = Vector3.new(math.cos(a0) * radius, 0, math.sin(a0) * radius)
		local p1 = Vector3.new(math.cos(a1) * radius, 0, math.sin(a1) * radius)
		local part = vfxPart(Vector3.new((p1 - p0).Magnitude + 0.05, 0.06, 0.14), CFrame.new(), color)
		part.CFrame = CFrame.new(floor) * CFrame.lookAt((p0 + p1) / 2, p1) * CFrame.Angles(0, math.rad(90), 0)
		part.Parent = holder
	end
	for i = 0, 5 do
		local a = (i / 6) * math.pi * 2
		local rune = vfxPart(
			Vector3.new(0.35, 0.06, 0.35),
			CFrame.new(floor + Vector3.new(math.cos(a) * radius * 0.6, 0, math.sin(a) * radius * 0.6))
				* CFrame.Angles(0, a + math.rad(45), 0),
			color
		)
		rune.Parent = holder
	end
	holder.Parent = folder()
	local start = os.clock()
	local pivot = CFrame.new(floor)
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - start
		if t > seconds or holder.Parent == nil then
			connection:Disconnect()
			return
		end
		local grow = 0.7 + 0.3 * math.min(t / 0.2, 1)
		holder:PivotTo(pivot * CFrame.Angles(0, t * 2.4, 0))
		for _, part in holder:GetChildren() do
			if part:IsA("BasePart") then
				part.Transparency = 0.1 + 0.9 * math.max(0, (t - seconds * 0.6) / (seconds * 0.4))
			end
		end
		holder:ScaleTo(grow)
	end)
	Debris:AddItem(holder, seconds + 0.1)
end

-- Small glowing flash at a hand.
function CombatVfx.handGlyph(model: Model, side: "Left" | "Right")
	local hand = partOf(model, { side .. "Hand", side .. " Arm" })
	if hand == nil then
		return
	end
	local glyph =
		vfxPart(Vector3.new(0.8, 0.8, 0.8), hand.CFrame, CombatVfx.glowColor(model), Enum.PartType.Ball)
	glyph.Transparency = 0.25
	TweenService:Create(glyph, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(1.9, 1.9, 1.9),
	}):Play()
	fadeOut(glyph, 0.3)
end

-- Light gathering at a hand for `seconds` (bow draw, charged casts).
function CombatVfx.chargeGlow(model: Model, side: "Left" | "Right", seconds: number)
	local hand = partOf(model, { side .. "Hand", side .. " Arm" })
	if hand == nil then
		return
	end
	local orb =
		vfxPart(Vector3.new(0.2, 0.2, 0.2), hand.CFrame, CombatVfx.glowColor(model), Enum.PartType.Ball)
	orb.Transparency = 0.2
	local start = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - start
		if t > seconds or orb.Parent == nil or hand.Parent == nil then
			connection:Disconnect()
			orb:Destroy()
			return
		end
		local grow = 0.2 + 1.0 * (t / seconds)
		local pulse = 1 + 0.15 * math.sin(t * 40)
		orb.Size = Vector3.one * grow * pulse
		orb.CFrame = hand.CFrame
	end)
end

--------------------------------------------------------------------------------
-- Projectiles and impacts
--------------------------------------------------------------------------------

local function burstAt(position: Vector3, color: Color3, size: number)
	local burst = vfxPart(Vector3.one * size * 0.3, CFrame.new(position), color, Enum.PartType.Ball)
	burst.Transparency = 0.15
	TweenService:Create(burst, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.one * size,
	}):Play()
	fadeOut(burst, 0.24)
	local core = vfxPart(Vector3.one * size * 0.2, CFrame.new(position), WHITE, Enum.PartType.Ball)
	core.Transparency = 0.1
	TweenService:Create(core, TweenInfo.new(0.16), { Size = Vector3.one * size * 0.55 }):Play()
	fadeOut(core, 0.18)
end

export type ProjectileKind = "Bolt" | "Missile" | "Arrow" | "PowerArrow" | "Orb"

--[[
	Projectile from `fromPart` to the target at `speed` studs/s (the server's
	projectile speed, so it lands with the damage).
]]
function CombatVfx.projectile(
	model: Model,
	fromPart: BasePart?,
	target: Model,
	kind: ProjectileKind,
	speed: number
)
	local targetRoot = rootOf(target)
	if fromPart == nil or targetRoot == nil then
		return
	end
	local color = CombatVfx.glowColor(model)
	local from = fromPart.Position
	local to = targetRoot.Position + Vector3.new(0, 0.6, 0)
	local distance = (to - from).Magnitude
	if distance < 1 then
		return
	end
	local travel = math.clamp(distance / speed, 0.05, 1.2)

	local size = if kind == "Arrow"
		then Vector3.new(0.12, 0.12, 2.0)
		elseif kind == "PowerArrow" then Vector3.new(0.22, 0.22, 2.8)
		elseif kind == "Missile" then Vector3.new(0.7, 0.7, 0.7)
		elseif kind == "Orb" then Vector3.new(1.6, 1.6, 1.6)
		else Vector3.new(0.9, 0.9, 0.9)
	local isArrow = kind == "Arrow" or kind == "PowerArrow"
	local bolt = vfxPart(size, CFrame.lookAt(from, to), color, if isArrow then nil else Enum.PartType.Ball)

	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, math.max(size.Y, 0.3) * 0.45, 0)
	a0.Parent = bolt
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -math.max(size.Y, 0.3) * 0.45, 0)
	a1.Parent = bolt
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(color, WHITE)
	trail.LightEmission = 1
	trail.Lifetime = if kind == "PowerArrow" or kind == "Orb" then 0.3 else 0.16
	trail.Transparency = NumberSequence.new(0.1, 1)
	trail.Parent = bolt

	TweenService:Create(bolt, TweenInfo.new(travel, Enum.EasingStyle.Linear), {
		CFrame = CFrame.lookAt(to, to + (to - from).Unit),
	}):Play()
	task.delay(travel, function()
		local big = kind == "PowerArrow" or kind == "Orb"
		burstAt(to, color, if big then 4.2 else 2.2)
		if big then
			local floor = floorUnder(target)
			if floor then
				CombatVfx.groundShock(floor, color, 4.5)
			end
		end
		bolt:Destroy()
	end)
end

-- Pillar of light on a target (healer finisher).
function CombatVfx.pillar(target: Model, color: Color3)
	local floor = floorUnder(target)
	if floor == nil then
		return
	end
	local beam = vfxPart(
		Vector3.new(0.4, 14, 0.4),
		CFrame.new(floor + Vector3.new(0, 7, 0)),
		WHITE,
		Enum.PartType.Cylinder
	)
	beam.CFrame = CFrame.new(floor + Vector3.new(0, 7, 0)) * CFrame.Angles(0, 0, math.rad(90))
	beam.Transparency = 0.1
	TweenService:Create(beam, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(14, 2.6, 2.6),
	}):Play()
	fadeOut(beam, 0.4, 0.1)
	CombatVfx.groundShock(floor, color, 4)
end

--[[
	The effect of one combo step at its Hit frame. `aim` is the attack's
	target (may be nil); `speed` the step's projectile speed.
]]
function CombatVfx.playStep(vfx: string, model: Model, aim: Model?, speed: number?)
	local color = CombatVfx.glowColor(model)
	local projectileSpeed = speed or 120
	if vfx == "SlashAcross" then
		CombatVfx.slashArc(model, "Across")
	elseif vfx == "SlashRising" then
		CombatVfx.slashArc(model, "Rising")
	elseif vfx == "Cleave" then
		CombatVfx.slashArc(model, "Cleave")
		local root = rootOf(model)
		local floor = floorUnder(model)
		if root and floor then
			CombatVfx.groundShock(floor + root.CFrame.LookVector * 3.5, color, 5)
		end
	elseif vfx == "Bolt" then
		CombatVfx.handGlyph(model, "Right")
		if aim then
			CombatVfx.projectile(
				model,
				partOf(model, { "RightHand", "Right Arm" }),
				aim,
				"Bolt",
				projectileSpeed
			)
		end
	elseif vfx == "Nova" then
		local floor = floorUnder(model)
		if floor then
			CombatVfx.groundShock(floor, color, 6)
		end
		if aim then
			CombatVfx.pillar(aim, color)
		end
	elseif vfx == "Missile" then
		CombatVfx.handGlyph(model, "Right")
		if aim then
			CombatVfx.projectile(
				model,
				partOf(model, { "RightHand", "Right Arm" }),
				aim,
				"Missile",
				projectileSpeed
			)
		end
	elseif vfx == "PalmMissile" then
		CombatVfx.handGlyph(model, "Left")
		if aim then
			CombatVfx.projectile(
				model,
				partOf(model, { "LeftHand", "Left Arm" }),
				aim,
				"Missile",
				projectileSpeed
			)
		end
	elseif vfx == "Burst" then
		CombatVfx.handGlyph(model, "Right")
		CombatVfx.handGlyph(model, "Left")
		if aim then
			CombatVfx.projectile(model, partOf(model, { "UpperTorso", "Torso" }), aim, "Orb", projectileSpeed)
		end
	elseif vfx == "Arrow" or vfx == "PowerArrow" then
		if aim then
			CombatVfx.projectile(
				model,
				partOf(model, { "LeftHand", "Left Arm" }),
				aim,
				if vfx == "PowerArrow" then "PowerArrow" else "Arrow",
				projectileSpeed
			)
		end
	end
end

--------------------------------------------------------------------------------
-- Target ring
--------------------------------------------------------------------------------

local ring: Model? = nil
local ringTarget: Model? = nil
local ringUntil = 0

-- Ring that follows the current target for a few seconds.
function CombatVfx.targetRing(target: Model, seconds: number)
	if ring == nil then
		local holder = Instance.new("Model")
		holder.Name = "TargetRing"
		local segments, radius = 14, 2.2
		for i = 0, segments - 1 do
			if i % 2 == 1 then
				continue -- dashed ring
			end
			local a0 = (i / segments) * math.pi * 2
			local a1 = ((i + 1) / segments) * math.pi * 2
			local p0 = Vector3.new(math.cos(a0) * radius, 0, math.sin(a0) * radius)
			local p1 = Vector3.new(math.cos(a1) * radius, 0, math.sin(a1) * radius)
			local part = vfxPart(
				Vector3.new((p1 - p0).Magnitude, 0.08, 0.16),
				CFrame.lookAt((p0 + p1) / 2, p1) * CFrame.Angles(0, math.rad(90), 0),
				Color3.fromRGB(255, 90, 80)
			)
			part.Parent = holder
		end
		holder.Parent = folder()
		ring = holder
		RunService.RenderStepped:Connect(function()
			local current = ring
			if current == nil then
				return
			end
			local targetModel = ringTarget
			local root = if targetModel then rootOf(targetModel) else nil
			if
				root == nil
				or os.clock() > ringUntil
				or (targetModel and targetModel:GetAttribute("Defeated") == true)
			then
				current:PivotTo(CFrame.new(0, -10000, 0))
				return
			end
			local floor = floorUnder(targetModel :: Model)
			if floor then
				current:PivotTo(
					CFrame.new(floor + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, os.clock() * 1.5, 0)
				)
			end
		end)
	end
	ringTarget = target
	ringUntil = os.clock() + seconds
end

return CombatVfx
