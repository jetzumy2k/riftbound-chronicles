--!strict
--[[
	Theme — "dark glass + gold" fantasy UI (PLAN.md UI decision, 2026-10-11).
	Every screen pulls colours, fonts and sizes from here so the look stays
	consistent and can be tuned in one place.
]]

local function family(font: Enum.Font): string
	return Font.fromEnum(font).Family
end

local Theme = {}

Theme.Colors = table.freeze({
	Ink = Color3.fromRGB(8, 7, 14),
	Glass = Color3.fromRGB(16, 14, 26),
	GlassRaised = Color3.fromRGB(28, 24, 42),
	GlassHighlight = Color3.fromRGB(60, 52, 84),
	Gold = Color3.fromRGB(226, 186, 104),
	GoldBright = Color3.fromRGB(255, 230, 160),
	GoldDeep = Color3.fromRGB(138, 98, 40),
	Text = Color3.fromRGB(246, 240, 228),
	TextDim = Color3.fromRGB(186, 178, 164),
	TextMuted = Color3.fromRGB(128, 122, 116),
	Safe = Color3.fromRGB(124, 230, 168),
	SafeDeep = Color3.fromRGB(22, 60, 44),
	Disabled = Color3.fromRGB(70, 66, 82),
})

Theme.Fonts = table.freeze({
	-- Serif display face for titles and names.
	Display = Font.new(family(Enum.Font.Merriweather), Enum.FontWeight.Bold),
	DisplayHeavy = Font.new(family(Enum.Font.Merriweather), Enum.FontWeight.Heavy),
	-- Calligraphic accent for taglines.
	Accent = Font.new(family(Enum.Font.Fondamento), Enum.FontWeight.Regular, Enum.FontStyle.Italic),
	-- Clean sans for body copy and buttons (readable on small screens).
	Body = Font.new(family(Enum.Font.GothamMedium), Enum.FontWeight.Medium),
	BodyBold = Font.new(family(Enum.Font.GothamBold), Enum.FontWeight.Bold),
})

Theme.Radius = table.freeze({
	Panel = 16,
	Card = 14,
	Button = 12,
	Chip = 10,
})

-- Minimum touch target (CLAUDE.md §28).
Theme.MinTouch = 44

-- Gold sheen used on strokes, buttons and titles.
Theme.GoldSequence = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(150, 104, 40)),
	ColorSequenceKeypoint.new(0.35, Color3.fromRGB(255, 226, 150)),
	ColorSequenceKeypoint.new(0.6, Color3.fromRGB(214, 168, 84)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 104, 40)),
})

return Theme
