--!strict
--[[
	AtmosphereController — per-area lighting (ZoneAtmosphere, PLAN.md D-37).

	Blends Lighting, Atmosphere, ColorCorrection and Bloom toward the preset
	of the capital nearest the camera: bright celestial sky over Skyreach
	Citadel, ember-red dusk over Emberdeep Bastion, neutral elsewhere.
	Local to this client only (Lighting changes on the client do not
	replicate). Updated a few times per second and eased, never snapping.

	Each zone's extras (ZoneAtmosphere.Extras, D-84) switch when the camera
	enters it: one client-only particle emitter around the camera (blowing
	sand in the Desert Rift, D-83; light motes in the Jungle Rift), the
	wind that sways terrain grass, the water colour and the sun rays.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldLayout = require(Shared.Definitions.WorldLayout)
local ZoneAtmosphere = require(Shared.Definitions.ZoneAtmosphere)

local EASE_PER_SECOND = 1.5
-- Camera particles per second: blowing sand (D-83), canopy motes (D-84).
local SAND_RATE = 16
local MOTE_RATE = 12
local SAND_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local MOTE_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"

local AtmosphereController = {}

local atmosphere: Atmosphere
local correction: ColorCorrectionEffect
local bloom: BloomEffect
local current: ZoneAtmosphere.Preset = ZoneAtmosphere.get("Neutral")
local particleBox: Part? = nil
local emitters: { [string]: ParticleEmitter? } = {}
local sunRays: SunRaysEffect
local extrasName = ""

local function rgb(t: { number }): Color3
	return Color3.fromRGB(math.floor(t[1] + 0.5), math.floor(t[2] + 0.5), math.floor(t[3] + 0.5))
end

local function ensure<T>(className: string, name: string): T
	local existing = Lighting:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing :: any
	end
	local created = Instance.new(className :: any)
	created.Name = name
	created.Parent = Lighting
	return created :: any
end

-- The preset the camera should see now.
local function target(): ZoneAtmosphere.Preset
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return ZoneAtmosphere.get("Neutral")
	end
	local position = camera.Focus.Position
	if WorldLayout.isInDungeonRegion(position.X) then
		return ZoneAtmosphere.get("Dungeon")
	end
	local warZone = WorldLayout.warZoneAt(position.X, position.Z)
	if warZone then
		return ZoneAtmosphere.get(warZone.atmosphere)
	end
	local best: ZoneAtmosphere.Preset = ZoneAtmosphere.get("Neutral")
	local bestWeight = 0
	for race, realm in WorldLayout.Realms :: { [string]: WorldLayout.Realm } do
		local c = realm.platformCenter
		local distance = (position - Vector3.new(c[1], c[2], c[3])).Magnitude
		local w = ZoneAtmosphere.weight(distance)
		if w > bestWeight then
			bestWeight = w
			best = ZoneAtmosphere.blend(ZoneAtmosphere.get("Neutral"), ZoneAtmosphere.get(race), w)
		end
	end
	return best
end

local function apply(preset: ZoneAtmosphere.Preset)
	Lighting.ClockTime = preset.clockTime
	Lighting.Brightness = preset.brightness
	Lighting.Ambient = rgb(preset.ambient)
	Lighting.OutdoorAmbient = rgb(preset.outdoorAmbient)
	Lighting.ColorShift_Top = rgb(preset.colorShiftTop)
	Lighting.ExposureCompensation = preset.exposure
	atmosphere.Density = preset.density
	atmosphere.Haze = preset.haze
	atmosphere.Glare = preset.glare
	atmosphere.Color = rgb(preset.atmosphereColor)
	atmosphere.Decay = rgb(preset.decay)
	correction.TintColor = rgb(preset.tint)
	correction.Saturation = preset.saturation
	correction.Contrast = preset.contrast
	bloom.Intensity = preset.bloomIntensity
	bloom.Threshold = preset.bloomThreshold
end

local function box(): Part
	if particleBox == nil then
		local part = Instance.new("Part")
		part.Name = "RC_ZoneParticles"
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Transparency = 1
		part.Size = Vector3.new(90, 14, 90)
		part.Parent = Workspace
		particleBox = part
	end
	return particleBox :: Part
end

local function makeEmitter(kind: string): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.Rotation = NumberRange.new(0, 360)
	if kind == "Sand" then
		e.Texture = SAND_TEXTURE
		e.Color = ColorSequence.new(Color3.fromRGB(226, 196, 146))
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 7) })
		e.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.3, 0.82),
			NumberSequenceKeypoint.new(1, 1),
		})
		e.Lifetime = NumberRange.new(3, 5)
		e.Speed = NumberRange.new(1, 3)
		e.Acceleration = Vector3.new(9, -0.5, 5)
		e.RotSpeed = NumberRange.new(-20, 20)
		e.LightInfluence = 1
		e.Rate = SAND_RATE
	else
		-- Motes: tiny warm specks catching the light under the canopy.
		e.Texture = MOTE_TEXTURE
		e.Color = ColorSequence.new(Color3.fromRGB(236, 240, 170))
		e.Size =
			NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.18), NumberSequenceKeypoint.new(1, 0.3) })
		e.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.3, 0.3),
			NumberSequenceKeypoint.new(0.7, 0.4),
			NumberSequenceKeypoint.new(1, 1),
		})
		e.Lifetime = NumberRange.new(4, 7)
		e.Speed = NumberRange.new(0.3, 1)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Acceleration = Vector3.new(0.4, 0.15, 0.25)
		e.LightEmission = 0.8
		e.LightInfluence = 0.3
		e.Rate = MOTE_RATE
	end
	e.Parent = box()
	return e
end

-- The extras' zone name for a camera position.
local function zoneName(position: Vector3): string
	if WorldLayout.isInDungeonRegion(position.X) then
		return "Dungeon"
	end
	local warZone = WorldLayout.warZoneAt(position.X, position.Z)
	return if warZone then warZone.atmosphere else "Neutral"
end

local function applyExtras(name: string)
	local extras = ZoneAtmosphere.extras(name)
	for kind, e in emitters :: { [string]: ParticleEmitter } do
		e.Enabled = kind == extras.particles
	end
	if extras.particles and emitters[extras.particles] == nil then
		emitters[extras.particles] = makeEmitter(extras.particles)
	end
	Workspace.GlobalWind = Vector3.new(extras.wind[1], extras.wind[2], extras.wind[3])
	Workspace.Terrain.WaterColor = rgb(extras.water)
	sunRays.Intensity = extras.sunRays
end

function AtmosphereController:Start()
	atmosphere = ensure("Atmosphere", "RC_Atmosphere")
	correction = ensure("ColorCorrectionEffect", "RC_ColorCorrection")
	bloom = ensure("BloomEffect", "RC_Bloom")
	bloom.Size = 28
	sunRays = ensure("SunRaysEffect", "RC_SunRays")
	sunRays.Spread = 0.6
	apply(current)

	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		if elapsed < 0.1 then
			return
		end
		local step = elapsed
		elapsed = 0
		current = ZoneAtmosphere.blend(current, target(), 1 - math.exp(-EASE_PER_SECOND * step))
		apply(current)
		local camera = Workspace.CurrentCamera
		if camera then
			local position = camera.Focus.Position
			local name = zoneName(position)
			if name ~= extrasName then
				extrasName = name
				applyExtras(name)
			end
			if particleBox then
				-- Upwind of the camera, so the drift passes through the view.
				particleBox.CFrame = CFrame.new(position + Vector3.new(-25, 3, -15))
			end
		end
	end)
end

return AtmosphereController
