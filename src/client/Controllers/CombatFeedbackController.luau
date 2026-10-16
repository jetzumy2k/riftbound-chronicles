--!strict
--[[
	CombatFeedbackController — what players see when the server reports
	combat (Phase 6). Display only; never changes game state.

	  Attack  the attacker's combo-step animation (AnimationController) and
	          its effect at the clip's Hit frame (CombatVfx.playStep).
	  Damage  floating number (gold "✦" + larger on crits), a brief white
	          hit flash, a light or heavy hit reaction, hit-stop on both
	          fighters and a small camera shake when we are involved.
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

local AnimationController = require(script.Parent.AnimationController)
local MobVisualController = require(script.Parent.MobVisualController)
local CharacterMotionController = require(script.Parent.CharacterMotionController)
local CombatVfx = require(script.Parent.Parent.Effects.CombatVfx)
local CameraShake = require(script.Parent.Parent.Effects.CameraShake)
local BasicAttacks = require(Shared.Definitions.BasicAttacks)

local Players = game:GetService("Players")

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

local HIT_STOP_SECONDS = 0.055
local HEAVY_HIT_STOP_SECONDS = 0.1

-- Combo step: animation, aim, wind-up effects, then the effect on its Hit frame.
local function onAttack(model: Model, action: any, aim: any)
	if type(action) ~= "string" then
		return
	end
	local attack, index = BasicAttacks.stepForClip(action)
	if attack == nil or index == nil then
		return
	end
	local step = attack.steps[index]
	local isSelf = model == (Players.LocalPlayer :: Player).Character
	local aimModel: Model? = if typeof(aim) == "Instance" and aim:IsA("Model") then aim else nil
	if not isSelf then
		AnimationController.play(model, action)
	elseif aimModel then
		-- Our own attack: face the server-chosen target and mark it.
		local root = aimModel:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			CharacterMotionController.faceToward(root.Position, step.recovery + 0.3)
		end
		CombatVfx.targetRing(aimModel, 4)
	end

	-- Our own animation started on the button press; land the effect in sync.
	local hit = BasicAttacks.hitTime(step)
	local elapsed = AnimationController.actionElapsed(model, action) or 0
	local delay = math.max(0, hit - elapsed)
	if step.heavy and attack.style == "Magic" then
		CombatVfx.castCircle(model, hit + 0.35)
	end
	if step.vfx == "PowerArrow" then
		CombatVfx.chargeGlow(model, "Right", delay)
	end
	task.delay(delay, function()
		if model.Parent then
			CombatVfx.playStep(step.vfx, model, aimModel, step.projectileSpeed)
		end
	end)
end

local function onDamage(model: Model, payload: any)
	local heavy = payload.heavy == true
	local crit = payload.crit == true
	showNumber(model, payload.amount or 0, crit, false)
	hitFlash(model)
	-- React, unless the target is mid-attack (never cancel its swing).
	if not AnimationController.isAttacking(model) and model:GetAttribute("Defeated") ~= true then
		AnimationController.play(model, if heavy then "HitHeavy" else "HitLight")
	end

	local source: Model? = if typeof(payload.source) == "Instance" and payload.source:IsA("Model")
		then payload.source
		else nil
	local stop = if heavy or crit then HEAVY_HIT_STOP_SECONDS else HIT_STOP_SECONDS
	if source then
		AnimationController.hitStop(source, stop)
	end
	AnimationController.hitStop(model, stop * 0.8)

	local me = (Players.LocalPlayer :: Player).Character
	if me and source == me then
		CameraShake.add(if heavy then 0.45 elseif crit then 0.32 else 0.18)
	elseif me and model == me then
		CameraShake.add(if heavy then 0.55 else 0.3)
	end
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
	if kind == "Attack" then
		onAttack(model, payload.action, payload.aim)
	elseif kind == "MobAttack" then
		MobVisualController.attack(model, if type(payload.windup) == "number" then payload.windup else 0.5)
	elseif kind == "Damage" then
		onDamage(model, payload)
	elseif kind == "Heal" then
		showNumber(model, payload.amount or 0, payload.crit == true, true)
	elseif kind == "Defeat" then
		AnimationController.play(model, "Defeat")
		-- Kneel first, then the light burst and fade.
		task.delay(0.7, function()
			defeatBurst(model)
			setFade(model, 0.85, 0.9)
		end)
	elseif kind == "Revive" then
		AnimationController.reset(model)
		setFade(model, 0, 0.5)
	end
end

function CombatFeedbackController:Init()
	NetClient.on("CombatEvent", onEvent)
end

return CombatFeedbackController
