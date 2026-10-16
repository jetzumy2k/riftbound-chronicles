--!strict
--[[
	AtmosphereController — per-area lighting (ZoneAtmosphere, PLAN.md D-37).

	Blends Lighting, Atmosphere, ColorCorrection and Bloom toward the preset
	of the capital nearest the camera: bright celestial sky over Skyreach
	Citadel, ember-red dusk over Emberdeep Bastion, neutral elsewhere.
	Local to this client only (Lighting changes on the client do not
	replicate). Updated a few times per second and eased, never snapping.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldLayout = require(Shared.Definitions.WorldLayout)
local ZoneAtmosphere = require(Shared.Definitions.ZoneAtmosphere)

local EASE_PER_SECOND = 1.5

local AtmosphereController = {}

local atmosphere: Atmosphere
local correction: ColorCorrectionEffect
local bloom: BloomEffect
local current: ZoneAtmosphere.Preset = ZoneAtmosphere.get("Neutral")

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
	end)
end

return AtmosphereController
