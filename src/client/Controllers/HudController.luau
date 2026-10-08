--!strict
--[[
	HudController
	Compact level + XP bar (mobile-first, CLAUDE.md §28):
	  - Top-left, inside CoreUISafeInsets (never under the Roblox top bar or
	    a phone notch).
	  - Fixed pixel sizes scaled by a UIScale from viewport height so it stays
	    readable on phones and unobtrusive on desktop.
	  - Progress is shown as text ("1,234 / 5,000 XP") as well as bar fill, so
	    colour is never the only indicator.
	  - Non-interactive: never blocks touches.

	Phase 19 replaces the placeholder styling with the full UI kit.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)

local PlayerDataController = require(script.Parent.PlayerDataController)

local BASE_HEIGHT = 720 -- design viewport height
local MIN_SCALE, MAX_SCALE = 0.85, 1.4

local HudController = {}

local gui: ScreenGui
local levelLabel: TextLabel
local xpLabel: TextLabel
local fill: Frame
local scale: UIScale

local function formatNumber(n: number): string
	local text = tostring(math.floor(n))
	local formatted = string.reverse((string.gsub(string.reverse(text), "(%d%d%d)", "%1,")))
	return (string.gsub(formatted, "^,", ""))
end

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "RC_Hud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	scale = Instance.new("UIScale")
	scale.Parent = gui

	local panel = Instance.new("Frame")
	panel.Name = "Progress"
	panel.Position = UDim2.fromOffset(8, 8)
	panel.Size = UDim2.fromOffset(220, 48)
	panel.BackgroundColor3 = Color3.fromRGB(20, 22, 32)
	panel.BackgroundTransparency = 0.25
	panel.Active = false
	panel.Parent = gui
	corner(panel, 10)

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingBottom = UDim.new(0, 6)
	padding.Parent = panel

	levelLabel = Instance.new("TextLabel")
	levelLabel.Name = "Level"
	levelLabel.BackgroundTransparency = 1
	levelLabel.Size = UDim2.fromOffset(64, 18)
	levelLabel.Font = Enum.Font.GothamBold
	levelLabel.TextSize = 16
	levelLabel.TextColor3 = Color3.fromRGB(255, 236, 170)
	levelLabel.TextXAlignment = Enum.TextXAlignment.Left
	levelLabel.Text = "Lv 0"
	levelLabel.Parent = panel

	xpLabel = Instance.new("TextLabel")
	xpLabel.Name = "XP"
	xpLabel.BackgroundTransparency = 1
	xpLabel.AnchorPoint = Vector2.new(1, 0)
	xpLabel.Position = UDim2.fromScale(1, 0)
	xpLabel.Size = UDim2.new(1, -68, 0, 18)
	xpLabel.Font = Enum.Font.Gotham
	xpLabel.TextSize = 13
	xpLabel.TextColor3 = Color3.fromRGB(225, 228, 240)
	xpLabel.TextXAlignment = Enum.TextXAlignment.Right
	xpLabel.TextTruncate = Enum.TextTruncate.AtEnd
	xpLabel.Text = ""
	xpLabel.Parent = panel

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.AnchorPoint = Vector2.new(0, 1)
	track.Position = UDim2.fromScale(0, 1)
	track.Size = UDim2.new(1, 0, 0, 10)
	track.BackgroundColor3 = Color3.fromRGB(55, 60, 80)
	track.Parent = panel
	corner(track, 5)

	fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Color3.fromRGB(120, 200, 255)
	fill.Parent = track
	corner(fill, 5)

	gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")
end

local function updateScale()
	local camera = Workspace.CurrentCamera
	if camera then
		scale.Scale = math.clamp(camera.ViewportSize.Y / BASE_HEIGHT, MIN_SCALE, MAX_SCALE)
	end
end

local function render(state: PlayerDataController.State)
	levelLabel.Text = `Lv {state.Level}`
	if state.Level >= Constants.Level.Max then
		xpLabel.Text = "MAX LEVEL"
		fill.Size = UDim2.fromScale(1, 1)
	elseif state.XPToNext > 0 then
		xpLabel.Text = `{formatNumber(state.Experience)} / {formatNumber(state.XPToNext)} XP`
		fill.Size = UDim2.fromScale(math.clamp(state.Experience / state.XPToNext, 0, 1), 1)
	end
end

function HudController:Start()
	build()
	updateScale()
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	end

	render(PlayerDataController:Get())
	PlayerDataController.Changed:Connect(function(state)
		render(state)
	end)
end

return HudController
