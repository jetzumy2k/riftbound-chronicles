--!strict
--[[
	MobVisualController — procedural creature animation (Phase 9, D-42;
	authored creature art is Phase 16 / D-40). Display only.

	Creatures from World/CreatureBuilder carry their limbs on Motor6D joints
	named after the part. Each frame, for nearby creatures, this sets the
	joints' Transform from a small body simulation:

	  Locomotion  speed is smoothed and the gait phase advances with the
	              distance actually walked (stride length per body plan), so
	              feet don't slide. Quadrupeds blend a 4-beat walk into a
	              gallop (legs lift on the swing, the spine flexes, the head
	              counter-bobs); beetles walk in alternating tripods; golems
	              take heavy swaying strides with a dip on each footfall;
	              sprites hover, drift and tilt into their motion.
	  Turning     the body banks into turns and the head leads them; it
	              pitches back when speeding up and forward when braking.
	  Idle        breathing, slow tail sway, and the head looks around now
	              and then.
	  Actions     attack: crouch / rear during the telegraphed wind-up, a fast
	              lunge, an eased recovery; hit: a short recoil; defeat: the
	              body sinks and rolls onto its side before it fades.
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local UPDATE_DISTANCE = 160
local STRIKE_SECONDS = 0.16
local RECOVER_SECONDS = 0.4
local HIT_SECONDS = 0.3
local DEFEAT_SECONDS = 0.9

local MobVisualController = {}

type Rig = {
	model: Model,
	root: BasePart,
	body: string,
	scale: number,
	motors: { [string]: Motor6D },
	-- Smoothed state.
	speed: number,
	phase: number,
	yaw: number,
	turnRate: number,
	accel: number,
	-- Idle look-around.
	look: Vector2,
	lookTarget: Vector2,
	nextLookAt: number,
	-- Actions.
	attackStart: number?,
	windup: number,
	hitStart: number?,
	defeatStart: number?,
}

local rigs: { [Model]: Rig } = {}
local rng = Random.new()

-- Stride length (studs per full gait cycle) per body plan, before scaling.
local STRIDE: { [string]: number } = { Wolf = 4.2, Beetle = 2.4, Golem = 4.6, Guardian = 4.6, Sprite = 6 }

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function approach(current: number, target: number, rate: number, dt: number): number
	return current + (target - current) * (1 - math.exp(-rate * dt))
end

local function rx(deg: number): CFrame
	return CFrame.Angles(math.rad(deg), 0, 0)
end

local function set(rig: Rig, name: string, cf: CFrame)
	local motor = rig.motors[name]
	if motor then
		motor.Transform = cf
	end
end

-- 0..1 anticipation and strike weights for the current attack.
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

local function pulse(start: number?, now: number, seconds: number): number
	if start == nil then
		return 0
	end
	local t = (now - start) / seconds
	if t >= 1 then
		return 0
	end
	-- Fast in, eased out.
	return math.sin(math.min(t * 4, 1) * math.pi / 2) * (1 - smooth(t))
end

--------------------------------------------------------------------------------
-- Body plans
--------------------------------------------------------------------------------

local function quadruped(rig: Rig, now: number, rear: number, strike: number, hit: number, down: number)
	local run = smooth((rig.speed - 6) / 8) -- 0 walk .. 1 gallop
	local moving = math.clamp(rig.speed / 3, 0, 1)
	local cycle = rig.phase * math.pi * 2
	-- Leg phase offsets: lateral-sequence walk -> rotary gallop.
	local offsets: { [string]: number } = {
		LegFL = 0,
		LegFR = 0.5 * (1 - run) + 0.12 * run,
		LegBL = 0.75 * (1 - run) + 0.55 * run,
		LegBR = 0.25 * (1 - run) + 0.65 * run,
	}
	local swingDeg = (24 + 22 * run) * moving
	for name, offset in offsets do
		local a = cycle + offset * math.pi * 2
		local swing = math.sin(a) * swingDeg
		-- Lift the paw while the leg swings forward (cos > 0), plant it otherwise.
		local lift = math.max(0, math.cos(a)) * (0.25 + 0.35 * run) * moving
		local front = string.sub(name, 4, 4) == "F"
		local brace = if front then rear * -20 + strike * 25 else rear * 18 - strike * 10
		set(rig, name, CFrame.new(0, lift, 0) * rx(swing + brace - down * 70))
	end
	local breathe = math.sin(now * 2.1) * (1 - moving)
	local flex = math.sin(cycle * 2) * 5 * run
	local bob = math.abs(math.sin(cycle)) * (0.08 + 0.18 * run) * moving
	local bank = math.clamp(-rig.turnRate * 9, -14, 14)
	local pitch = math.clamp(-rig.accel * 0.8, -6, 6)
	set(
		rig,
		"Body",
		CFrame.new(0, bob + breathe * 0.04 - rear * 0.35 - down * 1.1, strike * -1.4 + hit * 0.5)
			* CFrame.Angles(
				math.rad(flex + pitch + rear * 8 - strike * 10 - hit * 8),
				0,
				math.rad(bank + down * 75)
			)
	)
	-- The head leads turns, counter-bobs at speed and looks around at rest.
	local look = rig.look * (1 - moving)
	set(
		rig,
		"Head",
		CFrame.new(0, -bob * 0.6, strike * -1.2)
			* CFrame.Angles(
				math.rad(
					look.Y + rear * 16 - strike * 28 - math.sin(cycle) * 6 * run + hit * 12 + breathe * 2
				),
				math.rad(look.X + math.clamp(rig.turnRate * 14, -25, 25)),
				0
			)
	)
	local wag = math.sin(now * (if moving > 0.3 then 10 else 3.5)) * (if moving > 0.3 then 12 else 18)
	set(
		rig,
		"Tail",
		CFrame.Angles(math.rad(-run * 18 + rear * 10 - down * 20), math.rad(wag * (1 - down)), 0)
	)
end

local function beetle(rig: Rig, now: number, rear: number, strike: number, hit: number, down: number)
	local moving = math.clamp(rig.speed / 2.5, 0, 1)
	local cycle = rig.phase * math.pi * 2
	for i = 1, 6 do
		-- Alternating tripods: legs 1, 4, 5 and 2, 3, 6.
		local group = if i == 1 or i == 4 or i == 5 then 0 else math.pi
		local a = cycle + group
		local swing = math.sin(a) * 26 * moving
		local lift = math.max(0, math.cos(a)) * 0.35 * moving
		local fold = down * (if i % 2 == 0 then 50 else -50)
		set(rig, `Leg{i}`, CFrame.new(0, lift, 0) * rx(swing) * CFrame.Angles(0, 0, math.rad(fold)))
	end
	local sway = math.sin(cycle) * 3 * moving
	local breathe = math.sin(now * 1.6) * (1 - moving)
	set(
		rig,
		"Body",
		CFrame.new(0, breathe * 0.05 + rear * 0.35 - down * 0.8, strike * -0.9 + hit * 0.4)
			* CFrame.Angles(
				math.rad(rear * 10 - strike * 6 - hit * 6),
				0,
				math.rad(sway + math.clamp(-rig.turnRate * 6, -8, 8) + down * 160)
			)
	)
	set(
		rig,
		"Head",
		CFrame.new(0, 0, strike * -1.1)
			* CFrame.Angles(
				math.rad(rear * 22 - strike * 26 + rig.look.Y * 0.5),
				math.rad(rig.look.X * 0.6 * (1 - moving)),
				0
			)
	)
end

local function biped(rig: Rig, now: number, rear: number, strike: number, hit: number, down: number)
	local moving = math.clamp(rig.speed / 3, 0, 1)
	local cycle = rig.phase * math.pi * 2
	local swing = math.sin(cycle) * 28 * moving
	local liftL = math.max(0, math.cos(cycle)) * 0.4 * moving
	local liftR = math.max(0, -math.cos(cycle)) * 0.4 * moving
	set(rig, "LegL", CFrame.new(0, liftL, 0) * rx(swing - down * 80))
	set(rig, "LegR", CFrame.new(0, liftR, 0) * rx(-swing - down * 60))
	local breathe = math.sin(now * 1.5)
	set(rig, "ArmL", rx(-swing * 0.7 + breathe * 2 - hit * 20) * CFrame.Angles(0, 0, math.rad(-down * 40)))
	-- The weapon arm raises overhead in the wind-up and slams down.
	set(
		rig,
		"ArmR",
		rx(swing * 0.7 + rear * 165 + strike * 40 - hit * 20) * CFrame.Angles(0, 0, math.rad(down * 40))
	)
	-- Heavy stride: weight shifts side to side and dips at each footfall.
	local roll = math.sin(cycle) * 4 * moving
	local dip = -math.abs(math.cos(cycle)) * 0.18 * moving
	set(
		rig,
		"Body",
		CFrame.new(0, dip + breathe * 0.05 - strike * 0.3 - down * 1.6, hit * 0.4)
			* CFrame.Angles(
				math.rad(rear * 8 - strike * 16 - hit * 10 + math.clamp(-rig.accel * 0.6, -5, 5) - down * 35),
				math.rad(rear * -12),
				math.rad(roll + math.clamp(-rig.turnRate * 6, -8, 8))
			)
	)
	set(
		rig,
		"Head",
		CFrame.Angles(
			math.rad(breathe * 2 + rear * 6 + rig.look.Y * 0.6 - down * 25),
			math.rad(rig.look.X * (1 - moving)),
			0
		)
	)
end

local function sprite(rig: Rig, now: number, rear: number, strike: number, hit: number, down: number)
	local moving = math.clamp(rig.speed / 4, 0, 1)
	local hover = math.sin(now * 2.4) * 0.45 + math.sin(now * 1.1) * 0.2
	local drift = math.sin(now * 0.9) * 0.3
	set(
		rig,
		"Body",
		CFrame.new(drift, hover + rear * 0.6 - down * 2, strike * -1.8 + hit * 0.6)
			* CFrame.Angles(
				math.rad(-moving * 18 - hit * 15),
				0,
				math.rad(math.clamp(-rig.turnRate * 10, -20, 20))
			)
	)
	local flap = math.sin(now * (14 + rear * 10 + moving * 6)) * math.rad(40) * (1 - down)
	set(rig, "WingL", CFrame.Angles(0, flap, 0) * CFrame.new(0, hover, 0))
	set(rig, "WingR", CFrame.Angles(0, -flap, 0) * CFrame.new(0, hover, 0))
end

--------------------------------------------------------------------------------

local function animate(rig: Rig, dt: number, now: number)
	local velocity = rig.root.AssemblyLinearVelocity
	local measured = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local previous = rig.speed
	rig.speed = approach(rig.speed, measured, 8, dt)
	rig.accel = approach(rig.accel, (rig.speed - previous) / math.max(dt, 1e-3), 6, dt)
	-- Gait phase from the distance walked (no foot sliding).
	local stride = (STRIDE[rig.body] or 4) * rig.scale
	rig.phase = (rig.phase + rig.speed * dt / stride) % 1
	-- Turning rate (radians per second), smoothed.
	local look = rig.root.CFrame.LookVector
	local yaw = math.atan2(-look.X, -look.Z)
	local delta = (yaw - rig.yaw + math.pi) % (math.pi * 2) - math.pi
	rig.yaw = yaw
	rig.turnRate = approach(rig.turnRate, delta / math.max(dt, 1e-3), 6, dt)
	-- Idle look-around.
	if now >= rig.nextLookAt then
		rig.nextLookAt = now + rng:NextNumber(2.5, 6)
		rig.lookTarget = if rng:NextNumber() < 0.35
			then Vector2.zero
			else Vector2.new(rng:NextNumber(-35, 35), rng:NextNumber(-10, 12))
	end
	rig.look = rig.look:Lerp(rig.lookTarget, 1 - math.exp(-2.5 * dt))

	local rear, strike = attackWeights(rig, now)
	local hit = pulse(rig.hitStart, now, HIT_SECONDS)
	local down = if rig.defeatStart then smooth((now - rig.defeatStart) / DEFEAT_SECONDS) else 0
	if rig.body == "Wolf" then
		quadruped(rig, now, rear, strike, hit, down)
	elseif rig.body == "Beetle" then
		beetle(rig, now, rear, strike, hit, down)
	elseif rig.body == "Golem" or rig.body == "Guardian" then
		biped(rig, now, rear, strike, hit, down)
	else
		sprite(rig, now, rear, strike, hit, down)
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
	local look = root.CFrame.LookVector
	rigs[model] = {
		model = model,
		root = root,
		body = body,
		scale = math.max(0.5, root.Size.Y / 2),
		motors = motors,
		speed = 0,
		phase = rng:NextNumber(),
		yaw = math.atan2(-look.X, -look.Z),
		turnRate = 0,
		accel = 0,
		look = Vector2.zero,
		lookTarget = Vector2.zero,
		nextLookAt = os.clock() + rng:NextNumber(0, 3),
		attackStart = nil,
		windup = 0.5,
		hitStart = nil,
		defeatStart = nil,
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

-- A short recoil when the creature takes damage.
function MobVisualController.hit(model: Model)
	local rig = rigs[model]
	if rig and rig.defeatStart == nil then
		rig.hitStart = os.clock()
	end
end

-- Sinks and rolls over (the body then fades, CombatFeedbackController).
function MobVisualController.defeat(model: Model)
	local rig = rigs[model]
	if rig then
		rig.defeatStart = os.clock()
		rig.attackStart = nil
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
