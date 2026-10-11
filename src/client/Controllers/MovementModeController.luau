--!strict
--[[
	MovementModeController — Sprint / Crouch input (animation pass).

	  Desktop  hold Shift to sprint; C or Left Ctrl toggles crouch
	  Gamepad  L3 toggles sprint; B toggles crouch
	  Touch    two toggle buttons above the attack button

	Sends only the wanted mode; the server sets the speed, spends Focus for
	sprinting and publishes the "Stance" attribute that drives the pose.
	Buttons show their state with text and outline, not colour alone.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local NetClient = require(Shared.Net.Client)

local UI = script.Parent.Parent.UI
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)

local BUTTON_SIZE = 64

local MovementModeController = {}

local wanted = "Walk"
local refreshButtons: () -> () = function() end

local function currentStance(): string
	local character = (Players.LocalPlayer :: Player).Character
	local stance = if character then character:GetAttribute("Stance") else nil
	return if type(stance) == "string" then stance else "Walk"
end

local function request(mode: string)
	if mode == wanted and mode == currentStance() then
		return
	end
	wanted = mode
	NetClient.fire("SetMovementMode", mode)
end

local function toggle(mode: string)
	request(if currentStance() == mode then "Walk" else mode)
end

local function buildTouchButtons()
	local gui = Kit.new("ScreenGui", {
		Name = "RC_Movement",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
		DisplayOrder = 5,
	})
	local buttons: { [string]: { button: TextButton, stroke: UIStroke } } = {}
	local specs = {
		{ mode = "Sprint", label = "»\nRUN", offset = 0 },
		{ mode = "Crouch", label = "⌄\nCROUCH", offset = BUTTON_SIZE + 12 },
	}
	for _, spec in specs do
		local button = Kit.new("TextButton", {
			Name = spec.mode,
			AnchorPoint = Vector2.new(1, 1),
			-- Above the attack button (right side, clear of the jump button).
			Position = UDim2.new(1, -120 - spec.offset, 1, -136),
			Size = UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE),
			BackgroundColor3 = Theme.Colors.Glass,
			BackgroundTransparency = 0.2,
			Text = spec.label,
			TextSize = 13,
			FontFace = Theme.Fonts.BodyBold,
			TextColor3 = Theme.Colors.Text,
			AutoButtonColor = false,
			Parent = gui,
		})
		Kit.corner(button, BUTTON_SIZE // 2)
		local stroke = Kit.new("UIStroke", {
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = Theme.Colors.Gold,
			Thickness = 1.5,
			Transparency = 0.4,
			Parent = button,
		})
		button.Activated:Connect(function()
			toggle(spec.mode)
		end)
		buttons[spec.mode] = { button = button, stroke = stroke }
	end
	refreshButtons = function()
		local stance = currentStance()
		for mode, entry in buttons do
			local active = stance == mode
			entry.stroke.Thickness = if active then 3 else 1.5
			entry.stroke.Transparency = if active then 0 else 0.4
			entry.button.TextColor3 = if active then Theme.Colors.GoldBright else Theme.Colors.Text
			entry.button.BackgroundColor3 = if active then Theme.Colors.GlassRaised else Theme.Colors.Glass
		end
	end
	gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")
end

function MovementModeController:Start()
	if UserInputService.TouchEnabled then
		buildTouchButtons()
	end

	local player = Players.LocalPlayer :: Player
	local function bind(character: Model)
		wanted = "Walk"
		character:GetAttributeChangedSignal("Stance"):Connect(function()
			wanted = currentStance()
			refreshButtons()
		end)
		refreshButtons()
	end
	player.CharacterAdded:Connect(bind)
	if player.Character then
		bind(player.Character)
	end

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.LeftShift or key == Enum.KeyCode.RightShift then
			request("Sprint")
		elseif key == Enum.KeyCode.C or key == Enum.KeyCode.LeftControl or key == Enum.KeyCode.ButtonB then
			toggle("Crouch")
		elseif key == Enum.KeyCode.ButtonL3 then
			toggle("Sprint")
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		local key = input.KeyCode
		if
			(key == Enum.KeyCode.LeftShift or key == Enum.KeyCode.RightShift)
			and currentStance() == "Sprint"
		then
			request("Walk")
		end
	end)
end

return MovementModeController
