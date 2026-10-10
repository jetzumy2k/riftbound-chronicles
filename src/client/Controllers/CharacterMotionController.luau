--!strict
--[[
	CharacterMotionController — human-like movement feel for the local
	character (pulled forward from the Phase 15 animation pass at the creator's
	request, 2026-10-11).

	Layers on top of Roblox's movement and the character's animations:
	  - Eased start/stop: raw stick/WASD input is smoothed before it reaches the
	    Humanoid, so the character accelerates and brakes like a person instead
	    of snapping to full speed.
	  - Smooth turning: AutoRotate is replaced by an AlignOrientation that eases
	    the body toward the movement direction (or the camera in shift-lock).
	  - Body lean: forward with speed/acceleration, sideways into turns.
	  - Head and upper body follow where the camera looks (natural limits).
	  - Knee dip on landing, scaled by fall speed.

	All tuning lives in shared Logic/MotionMath (unit-tested, frame-rate
	independent). Speeds never exceed the server-set WalkSpeed, so this is
	compatible with movement validation (SECURITY_MODEL.md §5A.2).

	Joint offsets (lean, head look) are applied on this client only; other
	players see the standard animation. Replicating them is a Phase 15 item.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MotionMath = require(Shared.Logic.MotionMath)
local Log = require(Shared.Util.Log)

local RENDER_STEP_NAME = "RC_CharacterMotion"
local MANUAL_STATES: { [Enum.HumanoidStateType]: boolean } = {
	[Enum.HumanoidStateType.Climbing] = true,
	[Enum.HumanoidStateType.Swimming] = true,
	[Enum.HumanoidStateType.Seated] = true,
	[Enum.HumanoidStateType.Dead] = true,
	[Enum.HumanoidStateType.Physics] = true,
	[Enum.HumanoidStateType.Ragdoll] = true,
	[Enum.HumanoidStateType.FallingDown] = true,
	[Enum.HumanoidStateType.PlatformStanding] = true,
}

local log = Log.new("Motion")
local D = MotionMath.Defaults

local CharacterMotionController = {}

type Rig = {
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	rootJoint: Motor6D?,
	neck: Motor6D?,
	waist: Motor6D?,
	rootC0: CFrame,
	neckC0: CFrame,
	waistC0: CFrame,
	align: AlignOrientation,
	attachment: Attachment,
	connections: { RBXScriptConnection },
}

local controls: any = nil
local rig: Rig? = nil

-- Smoothed state.
local moveVector = Vector3.zero
local moving = false
local facingYaw = 0
local lastBodyYaw = 0
local turnRate = 0
local lastForwardSpeed = 0
local forwardAccel = 0
local leanPitch, leanRoll = 0, 0
local neckYaw, neckPitch, waistYaw = 0, 0, 0
local dip = 0
local fallSpeed = 0

local function getControls(): any
	if controls then
		return controls
	end
	local playerScripts = (Players.LocalPlayer :: Player):WaitForChild("PlayerScripts")
	local module = playerScripts:WaitForChild("PlayerModule", 10)
	if module and module:IsA("ModuleScript") then
		local ok, playerModule = pcall(require, module)
		if ok and playerModule and playerModule.GetControls then
			controls = playerModule:GetControls()
		end
	end
	return controls
end

local function motor(parent: Instance?, name: string): Motor6D?
	local joint = parent and parent:FindFirstChild(name)
	return if joint and joint:IsA("Motor6D") then joint else nil
end

local function teardown()
	local current = rig
	if current == nil then
		return
	end
	rig = nil
	RunService:UnbindFromRenderStep(RENDER_STEP_NAME)
	for _, connection in current.connections do
		connection:Disconnect()
	end
	if current.rootJoint then
		current.rootJoint.C0 = current.rootC0
	end
	if current.neck then
		current.neck.C0 = current.neckC0
	end
	if current.waist then
		current.waist.C0 = current.waistC0
	end
	current.align:Destroy()
	current.attachment:Destroy()
	if current.humanoid.Parent then
		current.humanoid.AutoRotate = true
	end
end

local function cameraAngles(): (number, number)
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return facingYaw, 0
	end
	local look = camera.CFrame.LookVector
	return MotionMath.yawOf(look.X, look.Z), math.asin(math.clamp(look.Y, -1, 1))
end

local function step(dt: number)
	local current = rig
	if current == nil or current.humanoid.Health <= 0 then
		return
	end
	local humanoid, root = current.humanoid, current.root
	local manual = MANUAL_STATES[humanoid:GetState()] == true

	-- 1. Eased movement input (runs after the default controls; last Move wins).
	local raw = Vector3.zero
	local ctrl = getControls()
	if ctrl then
		local ok, value = pcall(ctrl.GetMoveVector, ctrl)
		if ok and typeof(value) == "Vector3" then
			raw = value
		end
	end
	local rate = if raw.Magnitude >= moveVector.Magnitude then D.accelRate else D.decelRate
	moveVector = moveVector:Lerp(raw, MotionMath.alpha(rate, dt))
	if not manual then
		if raw.Magnitude > 0.01 or moveVector.Magnitude > 0.03 then
			humanoid:Move(moveVector, true)
			moving = true
		elseif moving then
			-- Hand control back (e.g. click-to-move) once fully stopped.
			humanoid:Move(Vector3.zero, true)
			moveVector = Vector3.zero
			moving = false
		end
	end

	-- 2. Smooth facing.
	current.align.Enabled = not manual
	humanoid.AutoRotate = manual
	local cameraYaw, cameraPitch = cameraAngles()
	if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
		facingYaw = cameraYaw -- shift-lock / first person: face the camera
	else
		local direction = humanoid.MoveDirection
		if direction.Magnitude > 0.1 then
			facingYaw = MotionMath.yawOf(direction.X, direction.Z)
		end
	end
	current.align.CFrame = CFrame.Angles(0, facingYaw, 0)

	-- 3. Lean from speed, acceleration and turning.
	local look = root.CFrame.LookVector
	local bodyYaw = MotionMath.yawOf(look.X, look.Z)
	local safeDt = math.max(dt, 1 / 240)
	turnRate = MotionMath.damp(turnRate, MotionMath.angleDelta(lastBodyYaw, bodyYaw) / safeDt, 10, dt)
	lastBodyYaw = bodyYaw

	local velocity = root.AssemblyLinearVelocity
	local forwardSpeed = velocity.X * look.X + velocity.Z * look.Z
	forwardAccel = MotionMath.damp(forwardAccel, (forwardSpeed - lastForwardSpeed) / safeDt, 8, dt)
	lastForwardSpeed = forwardSpeed

	local walkSpeed = math.max(humanoid.WalkSpeed, 1)
	local horizontal = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
	local targetPitch, targetRoll = 0, 0
	if grounded and not manual then
		targetPitch, targetRoll = MotionMath.lean(horizontal / walkSpeed, forwardAccel, turnRate)
	end
	leanPitch = MotionMath.damp(leanPitch, targetPitch, D.leanRate, dt)
	leanRoll = MotionMath.damp(leanRoll, targetRoll, D.leanRate, dt)

	-- 4. Landing dip recovery; track fall speed while airborne.
	if not grounded then
		fallSpeed = math.max(fallSpeed, -velocity.Y)
	end
	dip = MotionMath.damp(dip, 0, D.landingRecoverRate, dt)

	if current.rootJoint then
		current.rootJoint.C0 = current.rootC0
			* CFrame.new(0, -dip, 0)
			* CFrame.Angles(-leanPitch, 0, leanRoll)
	end

	-- 5. Head and upper body follow the camera.
	local targetNeckYaw, targetNeckPitch, targetWaistYaw = 0, 0, 0
	if not manual then
		targetNeckYaw, targetNeckPitch, targetWaistYaw = MotionMath.headLook(bodyYaw, cameraYaw, cameraPitch)
	end
	neckYaw = MotionMath.damp(neckYaw, targetNeckYaw, D.headRate, dt)
	neckPitch = MotionMath.damp(neckPitch, targetNeckPitch, D.headRate, dt)
	waistYaw = MotionMath.damp(waistYaw, targetWaistYaw, D.headRate, dt)
	if current.neck then
		current.neck.C0 = current.neckC0 * CFrame.Angles(neckPitch, neckYaw, 0)
	end
	if current.waist then
		current.waist.C0 = current.waistC0 * CFrame.Angles(0, waistYaw, 0)
	end
end

local function setup(character: Model)
	teardown()

	local humanoid = character:WaitForChild("Humanoid", 10)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if humanoid == nil or not humanoid:IsA("Humanoid") or root == nil or not root:IsA("BasePart") then
		return
	end

	-- R15 joints, with R6 fallbacks.
	local lowerTorso = character:FindFirstChild("LowerTorso")
	local upperTorso = character:FindFirstChild("UpperTorso")
	local head = character:FindFirstChild("Head")
	local rootJoint = motor(lowerTorso, "Root") or motor(root, "RootJoint")
	local neck = motor(head, "Neck") or motor(character:FindFirstChild("Torso"), "Neck")
	local waist = motor(upperTorso, "Waist")

	local attachment = Instance.new("Attachment")
	attachment.Name = "RC_MotionAttachment"
	attachment.Parent = root
	local align = Instance.new("AlignOrientation")
	align.Name = "RC_Facing"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.RigidityEnabled = false
	align.Responsiveness = D.turnRate * 1.6
	align.MaxTorque = math.huge
	align.Parent = root

	local look = root.CFrame.LookVector
	facingYaw = MotionMath.yawOf(look.X, look.Z)
	lastBodyYaw = facingYaw
	moveVector, moving = Vector3.zero, false
	turnRate, forwardAccel, lastForwardSpeed = 0, 0, 0
	leanPitch, leanRoll, dip, fallSpeed = 0, 0, 0, 0
	neckYaw, neckPitch, waistYaw = 0, 0, 0

	local newRig: Rig = {
		character = character,
		humanoid = humanoid,
		root = root,
		rootJoint = rootJoint,
		neck = neck,
		waist = waist,
		rootC0 = if rootJoint then rootJoint.C0 else CFrame.identity,
		neckC0 = if neck then neck.C0 else CFrame.identity,
		waistC0 = if waist then waist.C0 else CFrame.identity,
		align = align,
		attachment = attachment,
		connections = {},
	}

	table.insert(
		newRig.connections,
		humanoid.StateChanged:Connect(function(_, new)
			if new == Enum.HumanoidStateType.Landed then
				dip = math.max(dip, MotionMath.landingDip(fallSpeed))
				fallSpeed = 0
			elseif new == Enum.HumanoidStateType.Jumping then
				fallSpeed = 0
			end
		end)
	)
	table.insert(newRig.connections, humanoid.Died:Connect(teardown))

	rig = newRig
	RunService:BindToRenderStep(RENDER_STEP_NAME, Enum.RenderPriority.Input.Value + 1, step)
	log:Debug(
		"motion layer active (R15 joints: root=%s neck=%s waist=%s)",
		tostring(rootJoint ~= nil),
		tostring(neck ~= nil),
		tostring(waist ~= nil)
	)
end

function CharacterMotionController:Start()
	local player = Players.LocalPlayer :: Player
	player.CharacterAdded:Connect(function(character)
		task.spawn(setup, character)
	end)
	player.CharacterRemoving:Connect(teardown)
	if player.Character then
		task.spawn(setup, player.Character)
	end
end

return CharacterMotionController
