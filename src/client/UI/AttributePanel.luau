--!strict
--[[
	AttributePanel — the Attributes page of the skill screen (PLAN.md D-90).
	Display only: every press is a `SpendAttributes` intent the server
	checks against the level (Logic/AttributeRules).

	Shows the points left to spend (5 a level), and for each attribute its
	value, what it gives this character right now (worked out with the same
	shared rules the server uses) and +1 / +5 buttons (44 px, disabled
	without points). Physical classes are told INT does nothing for their
	damage, magic classes the same of STR.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AttributeRules = require(Shared.Logic.AttributeRules)

local UI = script.Parent
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)

local AttributePanel = {}

local ICONS = { REC = "💗", INT = "🔮", WIS = "📖", STR = "💪", AGI = "💨" }
local BLURBS = {
	REC = "Recovery: more Max HP and Defense. Helps you survive attacks.",
	INT = "Intelligence: more magic damage. Best for Mages and Healers.",
	WIS = "Wisdom: more Focus (your MP), magic resistance, magic accuracy and healing.",
	STR = "Strength: more physical damage. Best for Warriors and Archers.",
	AGI = "Agility: a chance to dodge enemy hits completely.",
}
local GOOD = Color3.fromRGB(140, 235, 160)

local function fmt(n: number): string
	local text = string.format("%.1f", n)
	return (string.gsub(text, "%.0$", ""))
end

-- What `id` gives at `attributes` for `job`, in words.
local function effect(id: string, attributes: AttributeRules.Attributes, job: string?): string
	local b = AttributeRules.bonuses(attributes, job)
	local magic = AttributeRules.isMagic(job)
	if id == "REC" then
		return `+{fmt(b.hpPct)}% Max HP · +{fmt(b.defensePct)}% Defense`
	elseif id == "INT" then
		if not magic then
			return "Your class deals physical damage: Intelligence does not raise it."
		end
		return `+{fmt(b.damagePct)}% damage`
	elseif id == "STR" then
		if magic then
			return "Your class deals magic damage: Strength does not raise it."
		end
		return `+{fmt(b.damagePct)}% damage`
	elseif id == "WIS" then
		return `+{fmt(b.focus)} max Focus · {fmt(b.magicResistPct)}% magic resistance · -{fmt(
			b.magicAccuracyPct
		)}% target dodge vs your magic · +{fmt(b.healingPct)}% healing`
	end
	return `{fmt(b.evasionPct)}% chance to dodge (at most {AttributeRules.EVASION_CAP_PCT}%)`
end

--[[
	Draws the page into `parent` (a frame of the given size). `attributes`
	spent, `level`, `job`, `resetIn` seconds until the free reset;
	`spend(id, points)` sends the intent.
]]
function AttributePanel.draw(
	parent: Instance,
	size: Vector2,
	attributes: AttributeRules.Attributes,
	level: number,
	job: string?,
	resetIn: number,
	spend: (string, number) -> ()
)
	local left = AttributeRules.unspent(attributes, level)
	local scroll = Kit.new("ScrollingFrame", {
		Name = "Attributes",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size.X, size.Y),
		CanvasSize = UDim2.fromScale(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = parent,
	})
	local list = Kit.list(scroll, Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Left)
	list.VerticalAlignment = Enum.VerticalAlignment.Top
	Kit.padding(scroll, 4, 8)

	local summary = Kit.label(
		`Points to spend: {left}   ·   {AttributeRules.POINTS_PER_LEVEL} every level   ·   Free reset: {if resetIn
				<= 0
			then "ready"
			else `in {math.ceil(resetIn / 3600)} h`}`,
		14,
		Theme.Fonts.BodyBold,
		if left > 0 then GOOD else Theme.Colors.TextDim
	)
	summary.Size = UDim2.new(1, -16, 0, 0)
	summary.AutomaticSize = Enum.AutomaticSize.Y
	summary.TextWrapped = true
	summary.TextXAlignment = Enum.TextXAlignment.Left
	summary.Parent = scroll

	for order, id in AttributeRules.IDS do
		local value = (attributes :: any)[id] :: number
		local card = Kit.new("Frame", {
			BackgroundColor3 = Theme.Colors.Ink,
			BackgroundTransparency = 0.45,
			Size = UDim2.new(1, -16, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = order,
			Parent = scroll,
		})
		Kit.corner(card, 10)
		Kit.padding(card, 8, 10)
		-- Text on the left, buttons on the right.
		local text = Kit.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -112, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = card,
		})
		Kit.list(text, Enum.FillDirection.Vertical, 2, Enum.HorizontalAlignment.Left)
		local function line(content: string, textSize: number, font: Font, color: Color3)
			local l = Kit.label(content, textSize, font, color)
			l.Size = UDim2.fromScale(1, 0)
			l.AutomaticSize = Enum.AutomaticSize.Y
			l.TextWrapped = true
			l.TextXAlignment = Enum.TextXAlignment.Left
			l.Parent = text
		end
		line(
			`{ICONS[id]} {AttributeRules.NAMES[id]} ({id}): {value}`,
			15,
			Theme.Fonts.BodyBold,
			Theme.Colors.GoldBright
		)
		line(BLURBS[id], 12, Theme.Fonts.Body, Theme.Colors.TextDim)
		line(effect(id, attributes, job), 12, Theme.Fonts.BodyBold, Theme.Colors.Text)
		local buttons = Kit.new("Frame", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.fromOffset(104, 44),
			Parent = card,
		})
		Kit.list(buttons, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Right)
		for _, step in { 1, 5 } do
			local usable = left >= step
			local b = Kit.new("TextButton", {
				Size = UDim2.fromOffset(48, 44),
				BackgroundColor3 = if usable then Theme.Colors.Gold else Theme.Colors.GlassHighlight,
				BackgroundTransparency = if usable then 0.05 else 0.6,
				Text = `+{step}`,
				TextSize = 15,
				FontFace = Theme.Fonts.BodyBold,
				TextColor3 = if usable then Color3.fromRGB(30, 20, 8) else Theme.Colors.TextMuted,
				AutoButtonColor = usable,
				Active = usable,
				Parent = buttons,
			})
			Kit.corner(b, 8)
			if usable then
				b.Activated:Connect(function()
					spend(id, step)
				end)
			end
		end
	end
end

return AttributePanel
