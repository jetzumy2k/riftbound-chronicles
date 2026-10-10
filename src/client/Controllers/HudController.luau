--!strict
--[[
	HudController — level medallion + XP bar and safe-zone badge, in the
	dark-glass + gold style (UI/Theme, UI/Kit).

	Mobile-first (CLAUDE.md §28):
	  - Top-left, inside CoreUISafeInsets (never under the top bar or a notch).
	  - Scaled from viewport height so it stays readable on phones.
	  - Progress shown as text ("1,234 / 5,000 XP") as well as bar fill; the
	    safe-zone badge has text and an icon, not colour alone.
	  - Non-interactive: never blocks touches.

	Display only: values come from the server (PlayerDataController and the
	server-set "SafeZone" attribute).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)

local UI = script.Parent.Parent.UI
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)

local PlayerDataController = require(script.Parent.PlayerDataController)

local BASE_HEIGHT = 720
local MIN_SCALE, MAX_SCALE = 0.85, 1.35

local HudController = {}

local levelText: TextLabel
local xpText: TextLabel
local fill: Frame
local safeBadge: Frame
local scale: UIScale
local lastLevel = -1

local function formatNumber(n: number): string
	local text = tostring(math.floor(n))
	local formatted = string.reverse((string.gsub(string.reverse(text), "(%d%d%d)", "%1,")))
	return (string.gsub(formatted, "^,", ""))
end

local function build()
	local gui = Kit.new("ScreenGui", {
		Name = "RC_Hud",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	scale = Kit.new("UIScale", { Parent = gui })

	-- Progress panel.
	local panel = Kit.glassPanel({
		Name = "Progress",
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.fromOffset(250, 60),
		Parent = gui,
	})

	local medallion = Kit.new("Frame", {
		Name = "Level",
		BackgroundColor3 = Theme.Colors.Ink,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 6, 0.5, 0),
		Size = UDim2.fromOffset(48, 48),
		Parent = panel,
	})
	Kit.corner(medallion, 24)
	Kit.goldStroke(medallion, 2)
	Kit.new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 5),
		Size = UDim2.new(1, 0, 0, 10),
		Text = "LV",
		TextSize = 10,
		FontFace = Theme.Fonts.BodyBold,
		TextColor3 = Theme.Colors.TextDim,
		Parent = medallion,
	})
	levelText = Kit.new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 14),
		Size = UDim2.new(1, 0, 0, 26),
		Text = "0",
		TextSize = 22,
		FontFace = Theme.Fonts.Display,
		TextColor3 = Theme.Colors.GoldBright,
		Parent = medallion,
	})

	xpText = Kit.new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(62, 8),
		Size = UDim2.new(1, -72, 0, 18),
		Text = "",
		TextSize = 13,
		FontFace = Theme.Fonts.BodyBold,
		TextColor3 = Theme.Colors.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = panel,
	})

	local track = Kit.new("Frame", {
		Name = "Track",
		BackgroundColor3 = Theme.Colors.Ink,
		Position = UDim2.fromOffset(62, 32),
		Size = UDim2.new(1, -74, 0, 12),
		Parent = panel,
	})
	Kit.corner(track, 6)
	Kit.new("UIStroke", { Color = Theme.Colors.GoldDeep, Thickness = 1, Transparency = 0.3, Parent = track })

	fill = Kit.new("Frame", {
		Name = "Fill",
		BackgroundColor3 = Color3.new(1, 1, 1),
		Size = UDim2.fromScale(0, 1),
		Parent = track,
	})
	Kit.corner(fill, 6)
	Kit.new("UIGradient", { Color = Theme.GoldSequence, Parent = fill })

	-- Safe-zone badge (server-published attribute; display only).
	safeBadge = Kit.new("Frame", {
		Name = "SafeZone",
		BackgroundColor3 = Theme.Colors.SafeDeep,
		BackgroundTransparency = 0.15,
		Position = UDim2.fromOffset(10, 78),
		Size = UDim2.fromOffset(150, 30),
		Visible = false,
		Parent = gui,
	})
	Kit.corner(safeBadge, 15)
	Kit.new("UIStroke", { Color = Theme.Colors.Safe, Thickness = 1.5, Parent = safeBadge })
	Kit.new("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = "🛡  SAFE ZONE",
		TextSize = 13,
		FontFace = Theme.Fonts.BodyBold,
		TextColor3 = Theme.Colors.Safe,
		Parent = safeBadge,
	})

	gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")
end

local function updateScale()
	local camera = Workspace.CurrentCamera
	if camera then
		scale.Scale = math.clamp(camera.ViewportSize.Y / BASE_HEIGHT, MIN_SCALE, MAX_SCALE)
	end
end

local function render(state: PlayerDataController.State)
	levelText.Text = tostring(state.Level)
	local ratio
	if state.Level >= Constants.Level.Max then
		xpText.Text = "MAX LEVEL"
		ratio = 1
	elseif state.XPToNext > 0 then
		xpText.Text = `{formatNumber(state.Experience)} / {formatNumber(state.XPToNext)} XP`
		ratio = math.clamp(state.Experience / state.XPToNext, 0, 1)
	else
		ratio = 0
	end
	Kit.tween(fill, Kit.Tween.Smooth, { Size = UDim2.fromScale(ratio, 1) })

	if lastLevel >= 0 and state.Level > lastLevel then
		-- Level-up pulse on the medallion.
		levelText.TextSize = 30
		Kit.tween(levelText, Kit.Tween.Smooth, { TextSize = 22 })
	end
	lastLevel = state.Level
end

function HudController:Start()
	build()
	updateScale()
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	end

	local localPlayer = Players.LocalPlayer :: Player
	local function renderSafeZone()
		safeBadge.Visible = localPlayer:GetAttribute("SafeZone") ~= nil
	end
	localPlayer:GetAttributeChangedSignal("SafeZone"):Connect(renderSafeZone)
	renderSafeZone()

	render(PlayerDataController:Get())
	PlayerDataController.Changed:Connect(function(state)
		render(state)
	end)
end

return HudController
