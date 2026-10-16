--!strict
--[[
	MobVisualController — procedural creature animation (Phase 9; creature
	art pass is Phase 16). Display only.

	Creatures from World/CreatureBuilder carry their limbs on Motor6D joints
	named after the part. Each frame, for nearby creatures, this sets the
	joints' Transform from:
	  - locomotion: a gait cycle driven by real ground speed (quadruped
	    diagonal pairs, beetle tripods, biped arm/leg swing, sprite hover and
	    wing flaps) plus breathing / tail wag at rest
	  - attacks: rear back during the telegraphed wind-up (so players can
	    read and dodge it), a fast strike, then an eased recovery
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local UPDATE_DISTANCE = 140
local STRIKE_SECONDS = 0.14
local RECOVER_SECONDS = 0.35

local MobVisualController = {}

type Rig = {
	model: Model,
	root: BasePart,
	body: string,
	motors: { [string]: Motor6D },
	phase: number,
	attackStart: number?,
	windup: number,
}

local rigs: { [Model]: Rig } = {}

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- 0..1 anticipation and 0..1 strike weights for the current attack.
local function attackWeights(rig: Rig, now: number): (number, number)
	local start = rig.attackStart
	if start == nil then
		return 0, 0
	end
	local t = now - start
	local windup = rig.windup
	if t < windup then
		return smooth(t / windup), 0
	elseif t < windup + STRIKE_SECONDS then
		local s = (t - windup) / STRIKE_SECONDS
		return 1 - s, smooth(s)
	elseif t < windup + STRIKE_SECONDS + RECOVER_SECONDS then
		return 0, 1 - smooth((t - windup - STRIKE_SECONDS) / RECOVER_SECONDS)
	end
	rig.attackStart = nil
	return 0, 0
end

local function set(rig: Rig, name: string, cf: CFrame)
	local motor = rig.motors[name]
	if motor then
		motor.Transform = cf
	end
end

local function rx(deg: number): CFrame
	return CFrame.Angles(math.rad(deg), 0, 0)
end

local function animate(rig: Rig, dt: number, now: number)
	local velocity = rig.root.AssemblyLinearVelocity
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local moving = math.clamp(speed / 12, 0, 1)
	rig.phase += dt * (2 + speed * 0.55)
	local p = rig.phase
	local swing = math.sin(p * 3.2)
	local breathe = math.sin(now * 2.2)
	local rear, strike = attackWeights(rig, now)

	if rig.body == "Wolf" then
		local a = 38 * moving
		set(rig, "LegFL", rx(swing * a))
		set(rig, "LegBR", rx(swing * a))
		set(rig, "LegFR", rx(-swing * a))
		set(rig, "LegBL", rx(-swing * a))
		set(
			rig,
			"Body",
			CFrame.new(0, math.abs(swing) * 0.15 * moving + breathe * 0.04 + rear * 0.2, strike * -1.2)
				* rx(rear * 14 - strike * 10)
		)
		set(rig, "Head", CFrame.new(0, 0, strike * -1.4) * rx(rear * 18 - strike * 26 + breathe * 2))
		set(rig, "Tail", CFrame.Angles(0, math.sin(now * (if moving > 0.2 then 9 else 4)) * math.rad(18), 0))
	elseif rig.body == "Beetle" then
		local a = 22 * moving
		for i = 1, 6 do
			local group = if i % 2 == 0 then 1 else -1
			set(
				rig,
				`Leg{i}`,
				rx(swing * a * group) * CFrame.new(0, math.max(0, swing * group) * 0.2 * moving, 0)
			)
		end
		set(
			rig,
			"Body",
			CFrame.new(0, breathe * 0.05 + rear * 0.3, strike * -0.8) * rx(rear * 10 - strike * 6)
		)
		set(rig, "Head", CFrame.new(0, 0, strike * -1.2) * rx(rear * 20 - strike * 24))
	elseif rig.body == "Golem" or rig.body == "Guardian" then
		local a = 26 * moving
		set(rig, "LegL", rx(swing * a))
		set(rig, "LegR", rx(-swing * a))
		set(rig, "ArmL", rx(-swing * a * 0.6 + breathe * 2))
		-- Right arm: the weapon arm raises overhead in the wind-up and slams down.
		set(rig, "ArmR", rx(swing * a * 0.6 + rear * 165 + strike * 40))
		set(
			rig,
			"Body",
			CFrame.new(0, breathe * 0.06 - strike * 0.3, 0)
				* rx(rear * 8 - strike * 16)
				* CFrame.Angles(0, math.rad(rear * -12), 0)
		)
		set(rig, "Head", rx(breathe * 2 + rear * 6))
	else -- Sprite
		set(rig, "Body", CFrame.new(0, math.sin(now * 2.4) * 0.45 + rear * 0.6, strike * -1.6))
		local flap = math.sin(now * (14 + rear * 10)) * math.rad(40)
		set(rig, "WingL", CFrame.Angles(0, flap, 0) * CFrame.new(0, math.sin(now * 2.4) * 0.45, 0))
		set(rig, "WingR", CFrame.Angles(0, -flap, 0) * CFrame.new(0, math.sin(now * 2.4) * 0.45, 0))
	end
end

local function track(model: Model)
	if rigs[model] then
		return
	end
	local body = model:GetAttribute("RC_Body")
	local root = model:WaitForChild("HumanoidRootPart", 5)
	if type(body) ~= "string" or root == nil or not root:IsA("BasePart") then
		return
	end
	local motors: { [string]: Motor6D } = {}
	for _, child in root:GetChildren() do
		if child:IsA("Motor6D") then
			motors[child.Name] = child
		end
	end
	rigs[model] = {
		model = model,
		root = root,
		body = body,
		motors = motors,
		phase = math.random() * 10,
		attackStart = nil,
		windup = 0.5,
	}
	model.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			rigs[model] = nil
		end
	end)
end

-- Plays the wind-up -> strike motion; `windup` seconds until the hit lands.
function MobVisualController.attack(model: Model, windup: number)
	local rig = rigs[model]
	if rig then
		rig.attackStart = os.clock()
		rig.windup = math.max(0.15, windup)
	end
end

function MobVisualController.isCreature(model: Model): boolean
	return model:GetAttribute("RC_Body") ~= nil
end

function MobVisualController:Start()
	task.spawn(function()
		local npcs = Workspace:WaitForChild("RC_Npcs", 30)
		if npcs == nil then
			return
		end
		npcs.ChildAdded:Connect(function(child)
			if child:IsA("Model") and (child :: Model):GetAttribute("RC_Body") ~= nil then
				task.spawn(track, child :: Model)
			end
		end)
		for _, child in npcs:GetChildren() do
			if child:IsA("Model") and (child :: Model):GetAttribute("RC_Body") ~= nil then
				task.spawn(track, child :: Model)
			end
		end
	end)
	-- After the Animator (Character priority) so these transforms win.
	RunService:BindToRenderStep("RC_MobVisual", Enum.RenderPriority.Character.Value + 2, function(dt: number)
		local camera = Workspace.CurrentCamera
		local origin = if camera then camera.CFrame.Position else Vector3.zero
		local now = os.clock()
		for _, rig in rigs do
			if (rig.root.Position - origin).Magnitude <= UPDATE_DISTANCE then
				animate(rig, dt, now)
			end
		end
	end)
end

return MobVisualController
