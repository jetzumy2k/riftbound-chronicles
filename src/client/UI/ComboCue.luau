--!strict
--[[
	ComboCue — "NEXT 2/3" with a shrinking bar just above the skill bar while
	the basic-attack chain window is open (D-103 stage C; rules in
	Logic/ComboMath.window). Pressing attack before the bar empties continues
	the combo; the finisher is written as FINISHER so the cue never relies on
	colour alone. Display only.
]]

local Players = game:GetService("Players")

local Theme = require(script.Parent.Theme)

local ComboCue = {}

local holder: Frame? = nil
local label: TextLabel? = nil
local fill: Frame? = nil

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "RC_ComboCue"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 6
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Position = UDim2.new(0.5, 0, 1, -112)
	frame.Size = UDim2.fromOffset(120, 26)
	frame.BackgroundTransparency = 1
	frame.Visible = false
	frame.Parent = gui
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.new(1, 0, 0, 18)
	text.FontFace = Theme.Fonts.BodyBold
	text.TextSize = 14
	text.TextColor3 = Theme.Colors.GoldBright
	text.TextStrokeTransparency = 0.2
	text.Parent = frame
	local track = Instance.new("Frame")
	track.Position = UDim2.fromOffset(10, 20)
	track.Size = UDim2.new(1, -20, 0, 5)
	track.BackgroundColor3 = Color3.fromRGB(20, 16, 30)
	track.BackgroundTransparency = 0.3
	track.BorderSizePixel = 0
	track.Parent = frame
	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(1, 0)
	trackCorner.Parent = track
	local bar = Instance.new("Frame")
	bar.Size = UDim2.fromScale(1, 1)
	bar.BackgroundColor3 = Theme.Colors.GoldBright
	bar.BorderSizePixel = 0
	bar.Parent = track
	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(1, 0)
	barCorner.Parent = bar
	holder, label, fill = frame, text, bar
end

-- Shows the window (`left` 1 -> 0) for the press that starts step `nextStep`
-- of `total`, or hides it when `left` is nil.
function ComboCue.update(left: number?, nextStep: number?, total: number)
	if holder == nil or label == nil or fill == nil then
		return
	end
	if left == nil or nextStep == nil then
		holder.Visible = false
		return
	end
	label.Text = if nextStep >= total then "FINISHER!" else `NEXT {nextStep}/{total}`
	fill.Size = UDim2.fromScale(math.clamp(left, 0, 1), 1)
	holder.Visible = true
end

function ComboCue.start()
	build()
end

return ComboCue
