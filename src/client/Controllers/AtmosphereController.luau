--!strict
--[[
	AtmosphereController — per-area lighting (ZoneAtmosphere, PLAN.md D-37).

	Blends Lighting, Atmosphere, ColorCorrection and Bloom toward the preset
	of the capital nearest the camera: bright celestial sky over Skyreach
	Citadel, ember-red dusk over Emberdeep Bastion, neutral elsewhere.
	Local to this client only (Lighting changes on the client do not
	replicate). Updated a few times per second and eased, never snapping.

	In the Desert Rift a single client-only emitter blows thin sand around
	the camera (D-83); it stops everywhere else.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldLayout = require(Shared.Definitions.WorldLayout)
local ZoneAtmosphere = require(Shared.Definitions.ZoneAtmosphere)

local EASE_PER_SECOND = 1.5
-- Blowing sand (D-83): particles per second around the camera, desert only.
local SAND_RATE = 16
local SAND_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

local AtmosphereController = {}

local atmosphere: Atmosphere
local correction: ColorCorrectionEffect
local bloom: BloomEffect
local current: ZoneAtmosphere.Preset = ZoneAtmosphere.get("Neutral")
local sandBox: Part? = nil
local sand: ParticleEmitter? = nil

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

-- A box of drifting sand that follows the camera; built on first use.
local function sandAt(position: Vector3, on: boolean)
	if sand == nil then
		if not on then
			return
		end
		local box = Instance.new("Part")
		box.Name = "RC_BlowingSand"
		box.Anchored = true
		box.CanCollide = false
		box.CanQuery = false
		box.CanTouch = false
		box.Transparency = 1
		box.Size = Vector3.new(90, 14, 90)
		local e = Instance.new("ParticleEmitter")
		e.Texture = SAND_TEXTURE
		e.Shape = Enum.ParticleEmitterShape.Box
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
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
		e.Rotation = NumberRange.new(0, 360)
		e.RotSpeed = NumberRange.new(-20, 20)
		e.LightInfluence = 1
		e.Rate = SAND_RATE
		e.Parent = box
		box.Parent = Workspace
		sandBox, sand = box, e
	end
	local e = sand :: ParticleEmitter
	e.Enabled = on
	if on then
		-- Upwind of the camera, so the drift passes through the view.
		(sandBox :: Part).CFrame = CFrame.new(position + Vector3.new(-25, 3, -15))
	end
end

function AtmosphereController:Start()
	atmosphere = ensure("Atmosphere", "RC_Atmosphere")
	correction = ensure("ColorCorrectionEffect", "RC_ColorCorrection")
	bloom = ensure("BloomEffect", "RC_Bloom")
	bloom.Size = 28
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
			local zone = WorldLayout.warZoneAt(position.X, position.Z)
			sandAt(position, zone ~= nil and zone.atmosphere == "Desert")
		end
	end)
end

return AtmosphereController
