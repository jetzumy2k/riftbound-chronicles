--!strict
--[[
	JobSelectLayout — responsive layout for the "Choose your path" screen.
	Same contract as RaceSelectLayout: pure function of the safe-area size,
	returning `scale`, a canvas exactly covering the area, and element rects in
	canvas units. Checked across real device sizes in
	tests/pure/specs/job_select_layout.spec.luau.

	Layouts:
	  wide             three cards side by side (tablet/desktop landscape)
	  tall             three cards stacked     (tablet portrait)
	  compactLandscape three compact cards side by side (phone landscape)
	  compactPortrait  three compact cards stacked      (phone portrait)

	Pure module.
]]

export type Rect = { x: number, y: number, w: number, h: number }

export type Fonts = {
	title: number,
	subtitle: number,
	cardName: number,
	role: number,
	description: number,
	weapons: number,
	button: number,
	note: number,
}

export type Mode = "wide" | "tall" | "compactLandscape" | "compactPortrait"

export type Layout = {
	mode: Mode,
	canvas: { w: number, h: number },
	scale: number,
	showSubtitle: boolean,
	showMedallion: boolean,
	showDescription: boolean,
	-- Cards laid out in a row (true) or stacked (false).
	cardsInRow: boolean,
	fonts: Fonts,
	rects: { [string]: Rect },
}

local JobSelectLayout = {}

JobSelectLayout.MIN_FONT_PX = 11
JobSelectLayout.MIN_TOUCH_PX = 44
JobSelectLayout.MAX_SCALE = 2.4
-- One card per job, in JobDefinitions.Order (Mage added in D-30).
JobSelectLayout.CARD_KEYS = table.freeze({ "cardWarrior", "cardHealer", "cardArcher", "cardMage" })
local CARD_COUNT = #JobSelectLayout.CARD_KEYS

local function rect(x: number, y: number, w: number, h: number): Rect
	return { x = x, y = y, w = w, h = h }
end

local function clampScale(value: number): number
	return math.min(value, JobSelectLayout.MAX_SCALE)
end

local FONTS: { [Mode]: Fonts } = {
	wide = {
		title = 40,
		subtitle = 18,
		cardName = 28,
		role = 16,
		description = 15,
		weapons = 14,
		button = 19,
		note = 14,
	},
	tall = {
		title = 36,
		subtitle = 18,
		cardName = 26,
		role = 16,
		description = 15,
		weapons = 14,
		button = 20,
		note = 15,
	},
	compactLandscape = {
		title = 22,
		subtitle = 14,
		cardName = 20,
		role = 14,
		description = 14,
		weapons = 14,
		button = 17,
		note = 14,
	},
	compactPortrait = {
		title = 24,
		subtitle = 14,
		cardName = 22,
		role = 14,
		description = 14,
		weapons = 14,
		button = 18,
		note = 14,
	},
}

local function base(mode: Mode, scale: number, width: number, height: number): Layout
	local regular = mode == "wide" or mode == "tall"
	return {
		mode = mode,
		canvas = { w = width / scale, h = height / scale },
		scale = scale,
		showSubtitle = regular,
		showMedallion = mode == "wide",
		showDescription = true,
		cardsInRow = mode == "wide" or mode == "compactLandscape",
		fonts = FONTS[mode],
		rects = {},
	}
end

local function minFont(layout: Layout): number
	local smallest = math.huge
	for key, size in layout.fonts :: any do
		local used = (key ~= "description" or layout.showDescription)
			and (key ~= "subtitle" or layout.showSubtitle)
			and (key ~= "note" or layout.rects.note ~= nil)
		if used then
			smallest = math.min(smallest, size)
		end
	end
	return smallest
end

local function minTouch(layout: Layout): number
	local smallest = layout.rects.confirm.h
	for _, key in JobSelectLayout.CARD_KEYS do
		local r = layout.rects[key]
		smallest = math.min(smallest, r.h, r.w)
	end
	return smallest
end

local function readable(layout: Layout): boolean
	return minFont(layout) * layout.scale >= JobSelectLayout.MIN_FONT_PX
		and minTouch(layout) * layout.scale >= JobSelectLayout.MIN_TOUCH_PX
end

--------------------------------------------------------------------------------

local function buildWide(width: number, height: number): Layout
	local scale = clampScale(math.min(width / 1280, height / 720))
	local layout = base("wide", scale, width, height)
	local ox = (layout.canvas.w - 1280) / 2
	local oy = (layout.canvas.h - 720) / 2
	local cardW, gap = 280, 26
	local rowW = CARD_COUNT * cardW + (CARD_COUNT - 1) * gap
	local startX = ox + (1280 - rowW) / 2
	layout.rects = {
		header = rect(ox + 190, oy + 20, 900, 96),
		confirm = rect(ox + 460, oy + 600, 360, 56),
		note = rect(ox + 340, oy + 668, 600, 20),
	}
	for index, key in JobSelectLayout.CARD_KEYS do
		layout.rects[key] = rect(startX + (index - 1) * (cardW + gap), oy + 136, cardW, 440)
	end
	return layout
end

local function buildTall(width: number, height: number): Layout
	local headerH, cardH, gap, confirmH, noteH = 96, 190, 14, 60, 20
	local fixed = 24
		+ headerH
		+ gap
		+ CARD_COUNT * cardH
		+ (CARD_COUNT - 1) * gap
		+ 18
		+ confirmH
		+ 12
		+ noteH
		+ 12
	local scale = clampScale(math.min(width / 720, height / fixed))
	local layout = base("tall", scale, width, height)
	local ox = (layout.canvas.w - 720) / 2
	local y = (layout.canvas.h - fixed) / 2 + 24

	layout.rects.header = rect(ox + 30, y, 660, headerH)
	y += headerH + gap
	for _, key in JobSelectLayout.CARD_KEYS do
		layout.rects[key] = rect(ox + 40, y, 640, cardH)
		y += cardH + gap
	end
	y += 18 - gap
	layout.rects.confirm = rect(ox + 150, y, 420, confirmH)
	y += confirmH + 12
	layout.rects.note = rect(ox + 60, y, 600, noteH)
	return layout
end

local function buildCompactPortrait(width: number, height: number): Layout
	local columnW, titleH, gap, confirmH, noteH = 360, 32, 8, 56, 28
	local cardWith, cardWithout = 150, 104

	local function fixedFor(cardH: number): number
		return 8 + titleH + 6 + CARD_COUNT * cardH + (CARD_COUNT - 1) * gap + 8 + confirmH + 6 + noteH + 6
	end

	local scale = clampScale(width / columnW)
	local showDescription = true
	local cardH = cardWith
	if height / scale < fixedFor(cardH) then
		showDescription = false
		cardH = cardWithout
	end
	if height / scale < fixedFor(cardH) then
		scale = clampScale(height / fixedFor(cardH))
	end

	local layout = base("compactPortrait", scale, width, height)
	layout.showDescription = showDescription
	local fixed = fixedFor(cardH)
	local ox = (layout.canvas.w - columnW) / 2
	local y = (layout.canvas.h - fixed) / 2 + 8
	local innerX, innerW = ox + 16, columnW - 32

	layout.rects.header = rect(ox, y, columnW, titleH)
	y += titleH + 6
	for _, key in JobSelectLayout.CARD_KEYS do
		layout.rects[key] = rect(innerX, y, innerW, cardH)
		y += cardH + gap
	end
	y += 8 - gap
	layout.rects.confirm = rect(innerX, y, innerW, confirmH)
	y += confirmH + 6
	layout.rects.note = rect(innerX, y, innerW, noteH)
	return layout
end

local function buildCompactLandscape(width: number, height: number): Layout
	local scale = clampScale(math.min(height / 360, width / 640))
	local layout = base("compactLandscape", scale, width, height)
	local canvasW, canvasH = layout.canvas.w, layout.canvas.h
	local gap, top, confirmH = 10, 38, 56

	local confirmY = canvasH - confirmH - 6
	local cardsH = confirmY - 8 - top
	local cardW = (canvasW - 24 - (CARD_COUNT - 1) * gap) / CARD_COUNT
	layout.showDescription = cardW >= 190 and cardsH >= 200

	layout.rects.header = rect(0, 4, canvasW, 28)
	for index, key in JobSelectLayout.CARD_KEYS do
		layout.rects[key] = rect(12 + (index - 1) * (cardW + gap), top, cardW, cardsH)
	end
	layout.rects.confirm = rect((canvasW - 320) / 2, confirmY, 320, confirmH)
	return layout
end

--------------------------------------------------------------------------------

function JobSelectLayout.compute(width: number, height: number): Layout
	if width >= height then
		local wide = buildWide(width, height)
		return if readable(wide) then wide else buildCompactLandscape(width, height)
	end
	local tall = buildTall(width, height)
	return if readable(tall) then tall else buildCompactPortrait(width, height)
end

JobSelectLayout.minFont = minFont
JobSelectLayout.minTouch = minTouch

return table.freeze(JobSelectLayout)
