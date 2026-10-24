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
}

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
	local name = Kit.label(skill.name, 17, Theme.Fonts.Display, Theme.Colors.GoldBright)
	name.AutomaticSize = Enum.AutomaticSize.None
	name.Position = UDim2.fromOffset(42, 0)
	name.Size = UDim2.new(1, -42, 1, 0)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Parent = title
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
