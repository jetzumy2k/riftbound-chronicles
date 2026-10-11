--!strict
--[[
	CombatController — basic-attack input: a 3-step combo per job
	(BasicAttacks, PLAN.md D-36).

	Sends *intents only*: `BasicAttack(targetModel?)`. The server decides the
	combo step, whether anything happens (hostility, safe zones, protection,
	range, line of sight) and how much damage it does. The client predicts
	the step with the same rules (ComboMath) to start the animation at once.

	Feel:
	  - Hold to attack: holding the button / mouse / key keeps chaining.
	  - Input buffer: a press slightly early is remembered and fires the
	    moment the next step is allowed.
	  - Turns to face the target immediately; melee steps lunge in a little
	    toward a target that is just out of reach.
	  - Clicking / tapping an enemy makes it the sticky target.

	Input:
	  Desktop  left mouse (click an enemy to target it) or F
	  Gamepad  R2
	  Touch    on-screen attack button (bottom-right, left of jump); shows
	           the combo step as three pips (shape, not only colour)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BasicAttacks = require(Shared.Definitions.BasicAttacks)
local ComboMath = require(Shared.Logic.ComboMath)
local JobDefinitions = require(Shared.Definitions.JobDefinitions)
local NetClient = require(Shared.Net.Client)

local UI = script.Parent.Parent.UI
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)

local PlayerDataController = require(script.Parent.PlayerDataController)
local AnimationController = require(script.Parent.AnimationController)
local CharacterMotionController = require(script.Parent.CharacterMotionController)

local BUTTON_SIZE = 92
local RAY_LENGTH = 300
local BUFFER_SECONDS = 0.3
local LUNGE_SECONDS = 0.14 -- CombatService.LUNGE_SECONDS
local LUNGE_STOP_DISTANCE = 3.2
local AUTO_TARGET_CONE = 0.25

local CombatController = {}

local combo = ComboMath.new()
local holding: { [string]: boolean? } = {}
local queued = false
local stickyTarget: Model? = nil
local pips: { Frame } = {}
local button: TextButton? = nil
local glyph: TextLabel? = nil

local function currentAttack(): BasicAttacks.BasicAttack?
	return BasicAttacks.forJob(PlayerDataController:Get().Job)
end

local function localCharacter(): Model?
	return (Players.LocalPlayer :: Player).Character
end

local function rootOf(model: Model): BasePart?
	local root = model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Could this model be attacked by us? (The server decides for real.)
local function isHostile(model: Model): boolean
	if model == localCharacter() or model:GetAttribute("Defeated") == true or rootOf(model) == nil then
		return false
	end
	if model:FindFirstChildOfClass("Humanoid") == nil then
		return false
	end
	local player = Players:GetPlayerFromCharacter(model)
	if player == nil then
		return true -- NPCs (training dummies, mobs)
	end
	local ours = (Players.LocalPlayer :: Player):GetAttribute("Race")
	local theirs = player:GetAttribute("Race")
	return ours == nil or theirs == nil or ours ~= theirs
end

local function candidates(): { Model }
	local out = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(out, player.Character)
		end
	end
	local npcs = Workspace:FindFirstChild("RC_Npcs")
	if npcs then
		for _, child in npcs:GetChildren() do
			if child:IsA("Model") then
				table.insert(out, child)
			end
		end
	end
	return out
end

-- The target we expect the attack to hit: the sticky target if it is still
-- valid and close, otherwise the nearest hostile in front of us.
local function predictTarget(range: number): Model?
	local character = localCharacter()
	local root = character and rootOf(character)
	if root == nil then
		return nil
	end
	local sticky = stickyTarget
	if sticky and sticky.Parent and isHostile(sticky) then
		local stickyRoot = rootOf(sticky)
		if stickyRoot and (stickyRoot.Position - root.Position).Magnitude <= range + 4 then
			return sticky
		end
	end
	local best: Model? = nil
	local bestScore = math.huge
	local facing = root.CFrame.LookVector
	for _, model in candidates() do
		if not isHostile(model) then
			continue
		end
		local offset = (rootOf(model) :: BasePart).Position - root.Position
		local distance = offset.Magnitude
		if distance > range + 2 then
			continue
		end
		local flat = Vector3.new(offset.X, 0, offset.Z)
		local dot = if flat.Magnitude > 0.5 then flat.Unit:Dot(facing) else 1
		if dot < AUTO_TARGET_CONE then
			continue
		end
		-- Prefer close and in front.
		local score = distance * (1.6 - dot)
		if score < bestScore then
			best, bestScore = model, score
		end
	end
	return best
end

-- Character model under the mouse/tap position, if any (not our own).
local function modelAt(screenPosition: Vector2): Model?
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return nil
	end
	local ray = camera:ViewportPointToRay(screenPosition.X, screenPosition.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local character = localCharacter()
	params.FilterDescendantsInstances = if character then { character } else {}
	local result = Workspace:Raycast(ray.Origin, ray.Direction * RAY_LENGTH, params)
	if result == nil then
		return nil
	end
	local model = result.Instance:FindFirstAncestorOfClass("Model")
	while model and model:FindFirstChildOfClass("Humanoid") == nil do
		model = model:FindFirstAncestorOfClass("Model")
	end
	return model
end

-- Short burst of horizontal velocity toward the target (melee steps).
local function lunge(target: Model, maxStuds: number, delaySeconds: number)
	task.delay(delaySeconds, function()
		local character = localCharacter()
		local root = character and rootOf(character)
		local targetRoot = rootOf(target)
		if root == nil or targetRoot == nil or (character :: Model):GetAttribute("Defeated") == true then
			return
		end
		local offset = targetRoot.Position - root.Position
		local flat = Vector3.new(offset.X, 0, offset.Z)
		local travel = math.min(maxStuds, flat.Magnitude - LUNGE_STOP_DISTANCE)
		if travel < 0.3 then
			return
		end
		local attachment = root:FindFirstChild("RootAttachment")
		if attachment == nil or not attachment:IsA("Attachment") then
			return
		end
		local push = Instance.new("LinearVelocity")
		push.Name = "RC_Lunge"
		push.Attachment0 = attachment
		push.RelativeTo = Enum.ActuatorRelativeTo.World
		push.ForceLimitMode = Enum.ForceLimitMode.PerAxis
		push.MaxAxesForce = Vector3.new(60000, 0, 60000)
		push.VectorVelocity = flat.Unit * (travel / LUNGE_SECONDS)
		push.Parent = root
		task.delay(LUNGE_SECONDS, function()
			push:Destroy()
		end)
	end)
end

local function refreshPips()
	for index, pip in pips do
		local lit = index <= combo.index and os.clock() <= combo.readyAt + 0.7
		pip.BackgroundTransparency = if lit then 0 else 0.6
		pip.Size = if lit then UDim2.fromOffset(10, 10) else UDim2.fromOffset(7, 7)
	end
end

local function attack(explicitTarget: Model?)
	local definition = currentAttack()
	local character = localCharacter()
	if definition == nil or character == nil or character:GetAttribute("Defeated") == true then
		return
	end
	local now = os.clock()
	local index = ComboMath.resolve(combo, now, definition.steps)
	if index == nil then
		-- Slightly early: remember it and fire as soon as it is allowed.
		if ComboMath.waitTime(combo, now) <= BUFFER_SECONDS then
			queued = true
		end
		return
	end
	queued = false
	ComboMath.commit(combo, now, definition.steps, index, definition.finisherCooldown)
	local step = definition.steps[index]

	local target = if explicitTarget and isHostile(explicitTarget)
		then explicitTarget
		else predictTarget(definition.range)
	local targetRoot = if target then rootOf(target) else nil
	if targetRoot then
		CharacterMotionController.faceToward(targetRoot.Position, step.recovery + 0.3)
	end
	AnimationController.play(character, step.clip)
	if target and step.lunge and definition.style == "Melee" then
		lunge(target, step.lunge, math.max(0, BasicAttacks.hitTime(step) - 0.12))
	end
	NetClient.fire("BasicAttack", target)
	refreshPips()
end

local function anyHeld(): boolean
	return next(holding) ~= nil
end

local function buildTouchButton()
	local gui = Kit.new("ScreenGui", {
		Name = "RC_Combat",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
		DisplayOrder = 5,
	})
	local holder = Kit.new("TextButton", {
		Name = "Attack",
		AnchorPoint = Vector2.new(1, 1),
		-- Left of Roblox's touch jump button.
		Position = UDim2.new(1, -120, 1, -28),
		Size = UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE),
		BackgroundColor3 = Theme.Colors.Glass,
		BackgroundTransparency = 0.15,
		Text = "",
		AutoButtonColor = false,
		Parent = gui,
	})
	Kit.corner(holder, BUTTON_SIZE // 2)
	Kit.goldStroke(holder, 3)

	local icon = Kit.new("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0.8),
		Text = "⚔",
		TextSize = 40,
		FontFace = Theme.Fonts.DisplayHeavy,
		TextColor3 = Theme.Colors.GoldBright,
		ZIndex = 4,
		Parent = holder,
	})

	-- Combo step pips (size and fill, not colour alone).
	local row = Kit.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.fromOffset(46, 12),
		ZIndex = 4,
		Parent = holder,
	})
	Kit.list(row, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Center)
	for _ = 1, 3 do
		local pip = Kit.new("Frame", {
			BackgroundColor3 = Theme.Colors.GoldBright,
			BackgroundTransparency = 0.6,
			Size = UDim2.fromOffset(7, 7),
			ZIndex = 5,
			Parent = row,
		})
		Kit.corner(pip, 5)
		table.insert(pips, pip)
	end

	holder.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			holding.touch = true
			attack(nil)
		end
	end)
	holder.InputEnded:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			holding.touch = nil
		end
	end)

	gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")
	button = holder
	glyph = icon
end

local function refreshButton()
	local job = PlayerDataController:Get().Job
	local def = JobDefinitions.get(job)
	if glyph and def then
		glyph.Text = def.glyph
	end
	if button then
		button.Visible = job ~= nil
	end
end

local function disableCoreUi()
	-- The HUD shows HP; resets are handled by the server either way.
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
	end)
	task.spawn(function()
		for _ = 1, 10 do
			local ok = pcall(function()
				StarterGui:SetCore("ResetButtonCallback", false)
			end)
			if ok then
				return
			end
			task.wait(1)
		end
	end)
end

function CombatController:Start()
	disableCoreUi()

	if UserInputService.TouchEnabled then
		buildTouchButton()
	end
	refreshButton()
	PlayerDataController.Changed:Connect(refreshButton)

	local player = Players.LocalPlayer :: Player
	player.CharacterAdded:Connect(function()
		combo = ComboMath.new()
		holding = {}
		queued = false
		stickyTarget = nil
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			holding.mouse = true
			local position = input.Position
			local clicked = modelAt(Vector2.new(position.X, position.Y))
			if clicked and isHostile(clicked) then
				stickyTarget = clicked
			end
			attack(if clicked and isHostile(clicked) then clicked else nil)
		elseif input.KeyCode == Enum.KeyCode.F or input.KeyCode == Enum.KeyCode.ButtonR2 then
			holding[input.KeyCode.Name] = true
			attack(nil)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			holding.mouse = nil
		elseif input.KeyCode == Enum.KeyCode.F or input.KeyCode == Enum.KeyCode.ButtonR2 then
			holding[input.KeyCode.Name] = nil
		end
	end)

	-- Buffered presses and hold-to-attack fire the moment the next step is allowed.
	RunService.Heartbeat:Connect(function()
		if (queued or anyHeld()) and ComboMath.waitTime(combo, os.clock()) == 0 then
			attack(nil)
		end
		if #pips > 0 then
			refreshPips()
		end
	end)
end

return CombatController
