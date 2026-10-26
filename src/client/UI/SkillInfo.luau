--!strict
--[[
	SkillInfo — the information card for one skill (Phase 5, D-45): used by
	the skill tree's detail pane and by skill-bar tooltips.

	  icon + name, "REGULAR · Melee Strike · Blademaster", rank N / max,
	  cost / cooldown / range, target type, one line per effect at the
	  current rank, the combo rule, what the next rank adds, and (in the
	  tree) why it can't be learned yet.

	Every line is text (never colour alone). Text comes from
	Logic/SkillRules.describe, the same numbers the server uses.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SkillDefinitions = require(Shared.Definitions.SkillDefinitions)
local SkillRules = require(Shared.Logic.SkillRules)

local Theme = require(script.Parent.Theme)
local Kit = require(script.Parent.Kit)
local SkillIcon = require(script.Parent.SkillIcon)

local SkillInfo = {}

local COMBO_COLOR = Color3.fromRGB(255, 200, 110)
local NEXT_COLOR = Color3.fromRGB(150, 230, 170)
local STAT_COLOR = Color3.fromRGB(150, 205, 255)

local function line(parent: Instance, order: number, text: string, size: number, font: Font, color: Color3)
	local label = Kit.label(text, size, font, color)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.LayoutOrder = order
	label.RichText = false
	label.Parent = parent
	return label
end

export type Options = {
	-- Extra line at the bottom (e.g. "Requires Whirlwind · Level 8").
	note: string?,
	noteColor: Color3?,
	-- Compact tooltip: no "next rank" block.
	compact: boolean?,
	-- D-103: class colour for the title and chips (skill tree screen).
	accent: Color3?,
}

local ULTIMATE_COLOR = Color3.fromRGB(255, 205, 90)
local PHYSICAL_COLOR = Color3.fromRGB(255, 150, 120)
local MAGIC_COLOR = Color3.fromRGB(190, 150, 255)
local HEAL_COLOR = Color3.fromRGB(140, 255, 170)
local GUARD_COLOR = Color3.fromRGB(150, 210, 255)

-- D-103: what kind of power a skill uses, for the chip row.
local function powerKind(skill: SkillDefinitions.Skill): (string, Color3)
	if SkillDefinitions.effect(skill, "Damage") then
		local magic = skill.job == "Mage" or skill.job == "Healer"
		return if magic then "🔮 Magic" else "🗡 Physical", if magic then MAGIC_COLOR else PHYSICAL_COLOR
	elseif SkillDefinitions.effect(skill, "Heal") or SkillDefinitions.effect(skill, "Regen") then
		return "➕ Healing", HEAL_COLOR
	elseif
		SkillDefinitions.effect(skill, "Shield")
		or SkillDefinitions.effect(skill, "Guard")
		or SkillDefinitions.effect(skill, "Immune")
		or SkillDefinitions.effect(skill, "Reflect")
	then
		return "🛡 Protection", GUARD_COLOR
	end
	return "💫 Support", Theme.Colors.TextDim
end

-- A small rounded tag: text in `color` with a matching outline.
local function chip(parent: Instance, order: number, text: string, color: Color3)
	local tag = Kit.new("TextLabel", {
		BackgroundColor3 = Theme.Colors.Ink,
		BackgroundTransparency = 0.25,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 22),
		Text = text,
		TextSize = 11,
		FontFace = Theme.Fonts.BodyBold,
		TextColor3 = color,
		LayoutOrder = order,
		Parent = parent,
	})
	Kit.corner(tag, 11)
	Kit.padding(tag, 0, 8)
	Kit.new("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = color,
		Transparency = 0.5,
		Thickness = 1,
		Parent = tag,
	})
end

--[[
	Fills `parent` (a frame with a vertical UIListLayout and AutomaticSize Y)
	with the card for `skill` at `rank` (0 = not learned yet).
]]
function SkillInfo.fill(parent: Instance, skill: SkillDefinitions.Skill, rank: number, options: Options?)
	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local info = SkillRules.describe(skill, rank)
	local order = 0
	local function add(text: string, size: number, font: Font, color: Color3)
		order += 1
		return line(parent, order, text, size, font, color)
	end
	local rankText = if rank >= 1
		then `Rank {rank} / {skill.maxRank}`
		else `Not learned · max rank {skill.maxRank}`
	order += 1
	local title = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 36),
		LayoutOrder = order,
		Parent = parent,
	})
	local icon = SkillIcon.forSkill(skill, 34, { dim = rank == 0 })
	icon.Parent = title
	local accent = options and options.accent
	local name = Kit.label(skill.name, 17, Theme.Fonts.Display, accent or Theme.Colors.GoldBright)
	name.AutomaticSize = Enum.AutomaticSize.None
	name.Position = UDim2.fromOffset(42, 0)
	name.Size = UDim2.new(1, -42, 1, 0)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Parent = title
	-- D-103: chips for the facts players compare at a glance.
	if not SkillDefinitions.isBasic(skill) then
		order += 1
		local chips = Kit.new("Frame", {
			BackgroundTransparency = 1,
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.fromScale(1, 0),
			LayoutOrder = order,
			Parent = parent,
		})
		local flow = Kit.list(chips, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Left)
		flow.Wraps = true
		local ultimate = skill.type == "Special"
		chip(
			chips,
			1,
			if ultimate then "⭐ ULTIMATE" else "REGULAR",
			if ultimate then ULTIMATE_COLOR else accent or Theme.Colors.TextDim
		)
		local kind, kindColor = powerKind(skill)
		chip(chips, 2, kind, kindColor)
		chip(chips, 3, `⌛ {skill.cooldown} s`, STAT_COLOR)
		chip(chips, 4, `💧 {skill.focusCost} Focus`, STAT_COLOR)
		if skill.range > 0 then
			chip(chips, 5, `🎯 {skill.range} studs`, STAT_COLOR)
		end
		if SkillDefinitions.effect(skill, "Extend") then
			chip(chips, 6, "🔁 EXTENDER", Color3.fromRGB(140, 230, 255))
		end
	end
	add(info.header, 11, Theme.Fonts.BodyBold, Theme.Colors.TextDim)
	add(`{rankText}  ·  {info.target}`, 12, Theme.Fonts.BodyBold, Theme.Colors.Text)
	add(info.stats, 12, Theme.Fonts.BodyBold, STAT_COLOR)
	add(skill.description, 12, Theme.Fonts.Body, Theme.Colors.TextDim)
	for _, effect in info.effects do
		add(`•  {effect}`, 12, Theme.Fonts.Body, Theme.Colors.Text)
	end
	if info.combo then
		add(`🔗  {info.combo}`, 12, Theme.Fonts.BodyBold, COMBO_COLOR)
	end
	local options_: Options = options or {} :: Options
	if not options_.compact and info.nextRank and #info.nextRank > 0 then
		add("Next rank:", 12, Theme.Fonts.BodyBold, NEXT_COLOR)
		for _, text in info.nextRank do
			add(`   {text}`, 12, Theme.Fonts.Body, NEXT_COLOR)
		end
	end
	if options_.note then
		add(options_.note, 12, Theme.Fonts.BodyBold, options_.noteColor or Color3.fromRGB(255, 190, 150))
	end
end

return SkillInfo
