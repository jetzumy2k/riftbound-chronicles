--!strict
--[[
	CombatController — basic-attack input (Phase 6).

	Sends *intents only*: `BasicAttack(targetModel?)`. The server decides
	whether anything happens (cooldown, hostility, safe zones, protection,
	range, line of sight) and how much damage it does.

	Input:
	  Desktop  left click (on a target) or F (nearest enemy in front)
	  Gamepad  R2
	  Touch    on-screen attack button (bottom-right, left of jump)

	The cooldown sweep on the button is cosmetic; the server tracks the real
	cooldown.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BasicAttacks = require(Shared.Definitions.BasicAttacks)
local JobDefinitions = require(Shared.Definitions.JobDefinitions)
local NetClient = require(Shared.Net.Client)

local UI = script.Parent.Parent.UI
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)

local PlayerDataController = require(script.Parent.PlayerDataController)

local BUTTON_SIZE = 92
local RAY_LENGTH = 300

local CombatController = {}

local nextLocalAttackAt = 0
local button: TextButton? = nil
local sweep: Frame? = nil
local glyph: TextLabel? = nil

local function currentAttack(): BasicAttacks.BasicAttack?
	return BasicAttacks.forJob(PlayerDataController:Get().Job)
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
	local character = (Players.LocalPlayer :: Player).Character
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

local function attack(target: Model?)
	local definition = currentAttack()
	local character = (Players.LocalPlayer :: Player).Character
	if definition == nil or character == nil or character:GetAttribute("Defeated") == true then
		return
	end
	local now = os.clock()
	if now < nextLocalAttackAt then
		return
	end
	nextLocalAttackAt = now + definition.cooldown
	NetClient.fire("BasicAttack", target)

	if sweep then
		sweep.Size = UDim2.fromScale(1, 1)
		Kit.tween(
			sweep,
			TweenInfo.new(definition.cooldown, Enum.EasingStyle.Linear),
			{ Size = UDim2.fromScale(1, 0) }
		)
	end
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

	local cooldown = Kit.new("Frame", {
		Name = "Cooldown",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0),
		BackgroundColor3 = Theme.Colors.Ink,
		BackgroundTransparency = 0.35,
		ZIndex = 3,
		Parent = holder,
	})
	Kit.corner(cooldown, BUTTON_SIZE // 2)

	local icon = Kit.new("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = "⚔",
		TextSize = 40,
		FontFace = Theme.Fonts.DisplayHeavy,
		TextColor3 = Theme.Colors.GoldBright,
		ZIndex = 4,
		Parent = holder,
	})

	holder.Activated:Connect(function()
		attack(nil)
	end)

	gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")
	button = holder
	sweep = cooldown
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

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			local position = input.Position
			attack(modelAt(Vector2.new(position.X, position.Y)))
		elseif input.KeyCode == Enum.KeyCode.F or input.KeyCode == Enum.KeyCode.ButtonR2 then
			attack(nil)
		end
	end)
end

return CombatController
