--!strict
--[[
	NotificationController — short, non-blocking toasts for server notices
	(CLAUDE.md §28: notifications must not block play).

	The server sends a text *key* (never player-written text); this controller
	maps keys to player-facing strings. Unknown keys are ignored.

	Toasts stack at the top centre inside the safe area, never take input,
	show an icon plus text (not colour alone) and fade after a few seconds.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Log = require(Shared.Util.Log)
local NetClient = require(Shared.Net.Client)

local UI = script.Parent.Parent.UI
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)

local MAX_TOASTS = 3
local TOAST_SECONDS = 2.8
local MAX_WIDTH = 480

local STRINGS: { [string]: string } = {
	["system.welcome"] = "Welcome to Riftbound Chronicles",
	["race.invalidPreset"] = "That look isn't available for this realm.",
	["combat.blocked.safeZone"] = "You can't fight inside a safe zone. Step past the glowing ring.",
	["combat.blocked.protected"] = "That target is protected right now.",
	["combat.blocked.sameRace"] = "You can't attack your own realm.",
	["combat.blocked.outOfRange"] = "Too far away. Move closer.",
	["combat.blocked.lineOfSight"] = "No clear line of sight.",
	["combat.blocked.noTarget"] = "No target in range. Face an enemy or tap one.",
}

local ICONS: { [string]: string } = {
	Info = "✦",
	Welcome = "✦",
	Warning = "⚠",
}

local log = Log.new("Notification")

local NotificationController = {}

local container: Frame? = nil
local toasts: { Frame } = {}

local function build()
	local gui = Kit.new("ScreenGui", {
		Name = "RC_Toasts",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		DisplayOrder = 20,
	})
	local holder = Kit.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.new(1, -32, 1, -20),
		Parent = gui,
	})
	Kit.new("UISizeConstraint", { MaxSize = Vector2.new(MAX_WIDTH, math.huge), Parent = holder })
	Kit.list(holder, Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Center)
	gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")
	container = holder
end

local function dismiss(toast: Frame)
	local index = table.find(toasts, toast)
	if index then
		table.remove(toasts, index)
	end
	local text = toast:FindFirstChild("Text")
	Kit.tween(toast, Kit.Tween.Smooth, { BackgroundTransparency = 1 })
	if text and text:IsA("TextLabel") then
		Kit.tween(text, Kit.Tween.Smooth, { TextTransparency = 1 })
	end
	local stroke = toast:FindFirstChildOfClass("UIStroke")
	if stroke then
		Kit.tween(stroke, Kit.Tween.Smooth, { Transparency = 1 })
	end
	task.delay(0.3, function()
		toast:Destroy()
	end)
end

local function show(kind: string, message: string)
	local holder = container
	if holder == nil then
		return
	end
	-- Same message already visible: just keep it alive instead of stacking.
	for _, existing in toasts do
		local text = existing:FindFirstChild("Text")
		if text and text:IsA("TextLabel") and text.Text == `{ICONS[kind] or "✦"}  {message}` then
			return
		end
	end
	while #toasts >= MAX_TOASTS do
		dismiss(toasts[1])
	end

	local camera = Workspace.CurrentCamera
	local textSize = if camera and camera.ViewportSize.Y < 500 then 14 else 16
	local toast = Kit.new("Frame", {
		Name = "Toast",
		BackgroundColor3 = Theme.Colors.Glass,
		BackgroundTransparency = 0.1,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.fromScale(1, 0),
		Active = false,
		Parent = holder,
	})
	Kit.corner(toast, 12)
	Kit.padding(toast, 10, 14)
	Kit.new("UIStroke", {
		Color = if kind == "Warning" then Color3.fromRGB(255, 170, 90) else Theme.Colors.Gold,
		Thickness = 1.5,
		Transparency = 0.1,
		Parent = toast,
	})
	Kit.new("TextLabel", {
		Name = "Text",
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.fromScale(1, 0),
		Text = `{ICONS[kind] or "✦"}  {message}`,
		TextWrapped = true,
		TextSize = textSize,
		FontFace = Theme.Fonts.BodyBold,
		TextColor3 = Theme.Colors.Text,
		Parent = toast,
	})
	table.insert(toasts, toast)
	task.delay(TOAST_SECONDS, function()
		if toast.Parent then
			dismiss(toast)
		end
	end)
end

function NotificationController:Init()
	build()
	NetClient.on("Notify", function(payload)
		if type(payload) ~= "table" or type(payload.textKey) ~= "string" then
			return
		end
		local message = STRINGS[payload.textKey]
		if message == nil then
			log:Debug("no text for key %s", payload.textKey)
			return
		end
		show(tostring(payload.kind), message)
	end)
end

return NotificationController
