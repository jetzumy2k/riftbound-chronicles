--!strict
--[[
	ComboCounter — "12 HITS · GREAT" on the right of the screen while the
	local player keeps landing hits (D-103 stage C; rules in
	Logic/HitStreak). The number pops on every hit, the colour climbs with
	the tier, and it fades out when the streak ends. Sits mid-right, clear
	of the skill bar, joystick and top bar; text never only uses colour (the
	tier is written). Display only.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local HitStreak = require(ReplicatedStorage:WaitForChild("Shared").Logic.HitStreak)
local Theme = require(script.Parent.Theme)

local ComboCounter = {}

local TIER_COLORS = {
	Color3.fromRGB(255, 255, 255),
	Color3.fromRGB(255, 200, 90),
	Color3.fromRGB(255, 120, 70),
	Color3.fromRGB(255, 90, 200),
}

local state = HitStreak.new()
local holder: Frame? = nil
local number: TextLabel? = nil
local word: TextLabel? = nil
local scale: UIScale? = nil
local shown = false

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "RC_ComboCounter"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 6
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(1, 0.5)
	frame.Position = UDim2.new(1, -16, 0.36, 0)
	frame.Size = UDim2.fromOffset(150, 64)
	frame.BackgroundTransparency = 1
	frame.Visible = false
	frame.Parent = gui
	local s = Instance.new("UIScale")
	s.Parent = frame
	local n = Instance.new("TextLabel")
	n.BackgroundTransparency = 1
	n.Size = UDim2.new(1, 0, 0, 40)
	n.TextXAlignment = Enum.TextXAlignment.Right
	n.FontFace = Theme.Fonts.DisplayHeavy
	n.TextSize = 36
	n.TextStrokeTransparency = 0.1
	n.TextStrokeColor3 = Color3.fromRGB(30, 10, 0)
	n.Parent = frame
	local w = Instance.new("TextLabel")
	w.BackgroundTransparency = 1
	w.Position = UDim2.fromOffset(0, 40)
	w.Size = UDim2.new(1, 0, 0, 20)
	w.TextXAlignment = Enum.TextXAlignment.Right
	w.FontFace = Theme.Fonts.BodyBold
	w.TextSize = 15
	w.TextStrokeTransparency = 0.2
	w.Parent = frame
	holder, number, word, scale = frame, n, w, s
end

-- The local player landed a hit.
function ComboCounter.hit()
	local count = HitStreak.hit(state, os.clock())
	if count < HitStreak.SHOW_FROM or holder == nil or number == nil or word == nil or scale == nil then
		return
	end
	local index, name = HitStreak.tier(count)
	local color = TIER_COLORS[math.clamp(index, 1, #TIER_COLORS)]
	number.Text = `{count} HITS`
	number.TextColor3 = color
	number.TextTransparency = 0
	number.TextStrokeTransparency = 0.1
	word.Text = name
	word.TextColor3 = color
	word.TextTransparency = 0
	word.TextStrokeTransparency = 0.2
	holder.Visible = true
	shown = true
	scale.Scale = 1.35
	TweenService
		:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
end

function ComboCounter.start()
	build()
	-- Fades out once the streak ends.
	RunService.Heartbeat:Connect(function()
		if shown and not HitStreak.alive(state, os.clock()) then
			shown = false
			local info = TweenInfo.new(0.35)
			if number and word then
				TweenService:Create(number, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
				TweenService:Create(word, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			end
		end
	end)
end

return ComboCounter
