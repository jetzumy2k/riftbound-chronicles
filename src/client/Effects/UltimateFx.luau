--!strict
--[[
	UltimateFx — the short cinematic moment of an ultimate (D-103 stage B).

	Everyone nearby sees a large rune circle under the caster, a pillar of
	light and a flash in the skill's element colour. The caster also gets
	the skill's name sweeping across the screen in their class colour, an
	edge flash, a quick camera zoom-punch and a shake. Under a second, so
	combat never waits for it; nothing here changes game state.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ClassThemes = require(ReplicatedStorage:WaitForChild("Shared").Definitions.ClassThemes)

local SkillVfx = require(script.Parent.SkillVfx)
local CameraShake = require(script.Parent.CameraShake)
local Theme = require(script.Parent.Parent.UI.Theme)

local UltimateFx = {}

-- Other players feel a small shake within this distance.
local NEAR_STUDS = 40
local BANNER_SECONDS = 1.3

local gui: ScreenGui? = nil
local punching = false

local function screen(): ScreenGui
	if gui and gui.Parent then
		return gui
	end
	local created = Instance.new("ScreenGui")
	created.Name = "RC_UltimateFx"
	created.ResetOnSpawn = false
	created.IgnoreGuiInset = true
	created.DisplayOrder = 20
	created.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")
	gui = created
	return created
end

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- The skill's name sweeping across the screen.
local function banner(name: string, color: Color3)
	local root = screen()
	local band = Instance.new("Frame")
	band.AnchorPoint = Vector2.new(0.5, 0.5)
	band.Position = UDim2.fromScale(0.5, 0.32)
	band.Size = UDim2.new(1, 0, 0, 64)
	band.BackgroundColor3 = Color3.new(0, 0, 0)
	band.BackgroundTransparency = 1
	band.BorderSizePixel = 0
	band.Parent = root
	local gradient = Instance.new("UIGradient")
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = band
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.35, 0.5)
	label.Size = UDim2.new(1, -32, 1, 0)
	label.Text = string.upper(name)
	label.TextScaled = true
	label.FontFace = Theme.Fonts.DisplayHeavy
	label.TextColor3 = color
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0.2
	label.TextTransparency = 1
	label.Parent = band
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 44
	limit.Parent = label
	local inInfo = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(band, inInfo, { BackgroundTransparency = 0.3 }):Play()
	TweenService:Create(label, inInfo, { Position = UDim2.fromScale(0.5, 0.5), TextTransparency = 0 }):Play()
	task.delay(BANNER_SECONDS - 0.3, function()
		local outInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(band, outInfo, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(
			label,
			outInfo,
			{ Position = UDim2.fromScale(0.65, 0.5), TextTransparency = 1, TextStrokeTransparency = 1 }
		):Play()
	end)
	task.delay(BANNER_SECONDS + 0.1, function()
		band:Destroy()
	end)
end

-- A soft flash over the whole screen.
local function edgeFlash(color: Color3)
	local flash = Instance.new("Frame")
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = color
	flash.BackgroundTransparency = 0.55
	flash.BorderSizePixel = 0
	flash.Parent = screen()
	TweenService:Create(flash, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1,
	}):Play()
	task.delay(0.5, function()
		flash:Destroy()
	end)
end

-- Zooms in a little and back (once at a time; restores the player's FOV).
local function punch()
	local camera = Workspace.CurrentCamera
	if camera == nil or punching then
		return
	end
	punching = true
	local base = camera.FieldOfView
	local tighten =
		TweenService:Create(camera, TweenInfo.new(0.12, Enum.EasingStyle.Quad), { FieldOfView = base - 8 })
	tighten:Play()
	tighten.Completed:Once(function()
		local back =
			TweenService:Create(camera, TweenInfo.new(0.45, Enum.EasingStyle.Sine), { FieldOfView = base })
		back:Play()
		back.Completed:Once(function()
			punching = false
		end)
	end)
end

-- An ultimate starts: `windup` seconds until it lands.
function UltimateFx.play(model: Model, skill: any, windup: number)
	local root = model:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return
	end
	local palette = SkillVfx.palette(skill.fx and skill.fx.element)
	local feet = SkillVfx.groundAt(root.Position)
	local seconds = math.clamp(windup + 0.4, 0.8, 1.6)
	SkillVfx.runeCircle(feet, 9, palette.main, seconds)
	SkillVfx.beam(feet, 26, palette.main, 3)
	SkillVfx.flash(root.Position, palette.light, 7, 0.35)

	local me = Players.LocalPlayer :: Player
	if model == me.Character then
		local theme = ClassThemes.forJob(me:GetAttribute("Job") :: any)
		banner(skill.name, rgb(theme.text))
		edgeFlash(palette.main)
		punch()
		CameraShake.add(0.5)
	else
		local mine = me.Character and me.Character:FindFirstChild("HumanoidRootPart")
		if mine and mine:IsA("BasePart") and (mine.Position - root.Position).Magnitude <= NEAR_STUDS then
			CameraShake.add(0.2)
		end
	end
end

return UltimateFx
