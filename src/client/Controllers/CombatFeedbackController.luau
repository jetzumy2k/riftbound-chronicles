--!strict
--[[
	CombatFeedbackController — what players see when the server reports
	combat (Phase 6). Display only; never changes game state.

	  Damage  floating number (gold "✦" + larger on crits) and a brief white
	          hit flash on the target.
	  Defeat  non-graphic: a burst of light and the body fades out
	          (no blood, no dismemberment — CLAUDE.md §14, §18).
	  Revive  fade back in (training dummies resetting).

	Floating numbers are capped to keep phones smooth.
]]

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local NetClient = require(Shared.Net.Client)

local UI = script.Parent.Parent.UI
local Theme = require(UI.Theme)

local MAX_NUMBERS = 14
local NUMBER_LIFETIME = 0.9
local SPARKLE_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"

local CombatFeedbackController = {}

local activeNumbers = 0
local rng = Random.new()

local function anchorPart(model: Model): BasePart?
	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head
	end
	return model.PrimaryPart
end

local function formatNumber(n: number): string
	local text = tostring(math.floor(n))
	local formatted = string.reverse((string.gsub(string.reverse(text), "(%d%d%d)", "%1,")))
	return (string.gsub(formatted, "^,", ""))
end

local function showNumber(model: Model, amount: number, crit: boolean, heal: boolean)
	local adornee = anchorPart(model)
	if adornee == nil or activeNumbers >= MAX_NUMBERS then
		return
	end
	activeNumbers += 1

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "RC_Number"
	billboard.Adornee = adornee
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Size = UDim2.fromOffset(160, 48)
	billboard.StudsOffset = Vector3.new(rng:NextNumber(-1.2, 1.2), 2.2, 0)
	billboard.MaxDistance = 120

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.FontFace = Theme.Fonts.DisplayHeavy
	label.TextScaled = false
	label.TextSize = if crit then 34 else 24
	label.Text = if heal
		then `+{formatNumber(amount)}`
		elseif crit then `✦ {formatNumber(amount)}`
		else formatNumber(amount)
	label.TextColor3 = if heal
		then Color3.fromRGB(140, 255, 170)
		elseif crit then Theme.Colors.GoldBright
		else Color3.fromRGB(255, 255, 255)
	label.TextStrokeColor3 = Color3.fromRGB(20, 12, 4)
	label.TextStrokeTransparency = 0.2
	label.Parent = billboard

	billboard.Parent = adornee
	local info = TweenInfo.new(NUMBER_LIFETIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(billboard, info, { StudsOffset = billboard.StudsOffset + Vector3.new(0, 2.4, 0) })
		:Play()
	TweenService:Create(
		label,
		TweenInfo.new(
			NUMBER_LIFETIME * 0.6,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.In,
			0,
			false,
			NUMBER_LIFETIME * 0.4
		),
		{
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}
	):Play()
	task.delay(NUMBER_LIFETIME, function()
		activeNumbers -= 1
		billboard:Destroy()
	end)
end

local function hitFlash(model: Model)
	local highlight = model:FindFirstChild("RC_HitFlash")
	if highlight == nil then
		local created = Instance.new("Highlight")
		created.Name = "RC_HitFlash"
		created.FillColor = Color3.new(1, 1, 1)
		created.OutlineTransparency = 1
		created.DepthMode = Enum.HighlightDepthMode.Occluded
		created.Parent = model
		highlight = created
	end
	local flash = highlight :: Highlight
	flash.FillTransparency = 0.45
	TweenService:Create(flash, TweenInfo.new(0.18), { FillTransparency = 1 }):Play()
end

local function setFade(model: Model, target: number, seconds: number)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") or part:IsA("Decal") then
			TweenService:Create(
				part,
				TweenInfo.new(seconds, Enum.EasingStyle.Sine),
				{ LocalTransparencyModifier = target }
			):Play()
		end
	end
end

local function defeatBurst(model: Model)
	local part = anchorPart(model)
	if part == nil then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "RC_DefeatBurst"
	attachment.Parent = part
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SPARKLE_TEXTURE
	emitter.LightEmission = 1
	emitter.Color = ColorSequence.new(Theme.Colors.GoldBright, Color3.new(1, 1, 1))
	emitter.Size =
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	emitter.Lifetime = NumberRange.new(0.6, 1.1)
	emitter.Speed = NumberRange.new(4, 9)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Enabled = false
	emitter.Parent = attachment
	emitter:Emit(36)
	Debris:AddItem(attachment, 2)
end

local function onEvent(payload: any)
	if
		type(payload) ~= "table"
		or typeof(payload.target) ~= "Instance"
		or not payload.target:IsA("Model")
	then
		return
	end
	local model = payload.target :: Model
	local kind = payload.kind
	if kind == "Damage" then
		showNumber(model, payload.amount or 0, payload.crit == true, false)
		hitFlash(model)
	elseif kind == "Heal" then
		showNumber(model, payload.amount or 0, payload.crit == true, true)
	elseif kind == "Defeat" then
		defeatBurst(model)
		setFade(model, 0.85, 0.9)
	elseif kind == "Revive" then
		setFade(model, 0, 0.5)
	end
end

function CombatFeedbackController:Init()
	NetClient.on("CombatEvent", onEvent)
end

return CombatFeedbackController
