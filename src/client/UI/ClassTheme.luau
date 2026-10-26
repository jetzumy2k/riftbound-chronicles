--!strict
--[[
	ClassTheme — the class colours (Definitions/ClassThemes) as Color3 for
	the skill tree screen, plus small animation helpers it shares (D-103
	stage A). Display only.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local ClassThemes = require(ReplicatedStorage:WaitForChild("Shared").Definitions.ClassThemes)

export type Colors = {
	primary: Color3,
	secondary: Color3,
	accent: Color3,
	dark: Color3,
	text: Color3,
}

local ClassTheme = {}

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local cache: { [string]: Colors } = {}

function ClassTheme.forJob(job: string?): Colors
	local key = job or ""
	local hit = cache[key]
	if hit then
		return hit
	end
	local theme = ClassThemes.forJob(job)
	local colors: Colors = {
		primary = rgb(theme.primary),
		secondary = rgb(theme.secondary),
		accent = rgb(theme.accent),
		dark = rgb(theme.dark),
		text = rgb(theme.text),
	}
	cache[key] = colors
	return colors
end

function ClassTheme.role(branchId: string): string?
	return ClassThemes.role(branchId)
end

-- A two-colour gradient sequence.
function ClassTheme.sequence(a: Color3, b: Color3): ColorSequence
	return ColorSequence.new(a, b)
end

--[[
	Loops a tween forever (reversing). It stops by itself when the instance
	is destroyed with the panel; no connection to clean up.
]]
function ClassTheme.pulse(instance: Instance, seconds: number, goal: { [string]: any })
	TweenService:Create(
		instance,
		TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		goal
	):Play()
end

-- Spins a UIGradient forever (ultimate rings).
function ClassTheme.spin(gradient: UIGradient, seconds: number)
	gradient.Rotation = 0
	TweenService:Create(
		gradient,
		TweenInfo.new(seconds, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, false),
		{ Rotation = 360 }
	):Play()
end

return ClassTheme
