--!strict
--[[
	CameraShake — short, decaying camera shake for impacts (hit feel).

	`add(trauma)` adds 0..1 "trauma"; the shake strength is trauma², so small
	hits barely move the camera and finishers punch. Applied after the
	default camera each frame and decays quickly; never moves the character.
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local MAX_ANGLE = math.rad(1.4)
local MAX_OFFSET = 0.18
local DECAY_PER_SECOND = 2.6
local FREQUENCY = 22

local CameraShake = {}

local trauma = 0
local bound = false
local seed = math.random() * 1000

local function step(dt: number)
	if trauma <= 0 then
		return
	end
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end
	local strength = trauma * trauma
	local t = os.clock() * FREQUENCY
	local pitch = math.noise(seed, t) * MAX_ANGLE * strength
	local yaw = math.noise(seed + 10, t) * MAX_ANGLE * strength
	local roll = math.noise(seed + 20, t) * MAX_ANGLE * strength * 0.6
	local offset = Vector3.new(math.noise(seed + 30, t), math.noise(seed + 40, t), 0) * MAX_OFFSET * strength
	camera.CFrame = camera.CFrame * CFrame.new(offset) * CFrame.Angles(pitch, yaw, roll)
	trauma = math.max(0, trauma - DECAY_PER_SECOND * dt)
end

function CameraShake.add(amount: number)
	trauma = math.clamp(trauma + amount, 0, 1)
	if not bound then
		bound = true
		RunService:BindToRenderStep("RC_CameraShake", Enum.RenderPriority.Camera.Value + 1, step)
	end
end

return CameraShake
