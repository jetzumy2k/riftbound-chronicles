--!strict
--[[
	RaceSelectLayout — responsive layout for the realm selection screen.

	Pure function of the available area (the safe-area-inset ScreenGui
	AbsoluteSize, in pixels). Returns a uniform `scale`, a design-unit `canvas`
	that exactly covers the area (canvas * scale == area), and element rects in
	canvas units. Fixed-size controls are stacked; the 3D preview absorbs the
	remaining space, so nothing is ever cropped or overlapped.

	Layouts:
	  wide             landscape, tablet/desktop  (two cards + centre preview)
	  tall             portrait, tablet           (preview on top, two cards)
	  compactLandscape landscape, phone           (preview left, one card right)
	  compactPortrait  portrait, phone            (stacked, one card)

	A regular layout is used only if it keeps every font >= MIN_FONT_PX and
	every touch target >= MIN_TOUCH_PX at its scale; otherwise the compact
	layout for that orientation is used. Checked across real device sizes in
	tests/pure/specs/race_select_layout.spec.luau.

	Pure module.
]]

export type Rect = { x: number, y: number, w: number, h: number }

export type Fonts = {
	title: number,
	subtitle: number,
	cardName: number,
	tagline: number,
	description: number,
	chip: number,
	looksTitle: number,
	button: number,
	note: number,
}

export type Mode = "wide" | "tall" | "compactLandscape" | "compactPortrait"

export type Layout = {
	mode: Mode,
	canvas: { w: number, h: number },
	scale: number,
	-- Both race cards visible, or only the selected one with a race toggle.
	showBothCards: boolean,
	showSubtitle: boolean,
	showMedallion: boolean,
	showDescription: boolean,
	swatchSize: number,
	fonts: Fonts,
	rects: { [string]: Rect },
}

local RaceSelectLayout = {}

RaceSelectLayout.MIN_FONT_PX = 11
RaceSelectLayout.MIN_TOUCH_PX = 44
RaceSelectLayout.MAX_SCALE = 2.4

local GAP = 8

local function rect(x: number, y: number, w: number, h: number): Rect
	return { x = x, y = y, w = w, h = h }
end

local function clampScale(value: number): number
	return math.min(value, RaceSelectLayout.MAX_SCALE)
end

local FONTS: { [Mode]: Fonts } = {
	wide = {
		title = 40,
		subtitle = 18,
		cardName = 28,
		tagline = 18,
		description = 16,
		chip = 14,
		looksTitle = 16,
		button = 19,
		note = 14,
	},
	tall = {
		title = 36,
		subtitle = 18,
		cardName = 26,
		tagline = 17,
		description = 15,
		chip = 14,
		looksTitle = 17,
		button = 20,
		note = 15,
	},
	compactLandscape = {
		title = 22,
		subtitle = 14,
		cardName = 20,
		tagline = 14,
		description = 14,
		chip = 14,
		looksTitle = 15,
		button = 17,
		note = 14,
	},
	compactPortrait = {
		title = 24,
		subtitle = 14,
		cardName = 22,
		tagline = 15,
		description = 14,
		chip = 14,
		looksTitle = 16,
		button = 18,
		note = 14,
	},
}

local function minFont(layout: Layout): number
	local smallest = math.huge
	for key, size in layout.fonts :: any do
		local used = (key ~= "description" or layout.showDescription)
			and (key ~= "subtitle" or layout.showSubtitle)
		if used then
			smallest = math.min(smallest, size)
		end
	end
	return smallest
end

local function minTouch(layout: Layout): number
	local smallest = layout.swatchSize
	for _, name in { "confirm", "toggle" } do
		local r = layout.rects[name]
		if r then
			smallest = math.min(smallest, r.h)
		end
	end
	return smallest
end

local function readable(layout: Layout): boolean
	return minFont(layout) * layout.scale >= RaceSelectLayout.MIN_FONT_PX
		and minTouch(layout) * layout.scale >= RaceSelectLayout.MIN_TOUCH_PX
end

local function base(mode: Mode, scale: number, width: number, height: number): Layout
	return {
		mode = mode,
		canvas = { w = width / scale, h = height / scale },
		scale = scale,
		showBothCards = mode == "wide" or mode == "tall",
		showSubtitle = mode == "wide" or mode == "tall",
		showMedallion = mode == "wide" or mode == "tall",
		showDescription = true,
		swatchSize = 56,
		fonts = FONTS[mode],
		rects = {},
	}
end

--------------------------------------------------------------------------------
-- Builders
--------------------------------------------------------------------------------

-- 1280 x 720 block, centred.
local function buildWide(width: number, height: number): Layout
	local scale = clampScale(math.min(width / 1280, height / 720))
	local layout = base("wide", scale, width, height)
	local ox = (layout.canvas.w - 1280) / 2
	local oy = (layout.canvas.h - 720) / 2
	layout.rects = {
		header = rect(ox + 190, oy + 18, 900, 104),
		cardAngel = rect(ox + 60, oy + 136, 330, 420),
		cardDevil = rect(ox + 890, oy + 136, 330, 420),
		preview = rect(ox + 420, oy + 132, 440, 392),
		looks = rect(ox + 420, oy + 534, 440, 100),
		confirm = rect(ox + 460, oy + 644, 360, 56),
		note = rect(ox + 340, oy + 702, 600, 18),
	}
	return layout
end

-- 720-wide column; the preview takes the spare height.
local function buildTall(width: number, height: number): Layout
	local headerH, cardsH, looksH, confirmH, noteH = 104, 380, 104, 60, 20
	local fixed = 24 + headerH + 14 + 16 + cardsH + 16 + looksH + 14 + confirmH + 12 + noteH + 12
	local minPreview, maxPreview = 260, 560
	local scale = clampScale(math.min(width / 720, height / (fixed + minPreview)))
	local layout = base("tall", scale, width, height)
	layout.swatchSize = 60

	local preview = math.min(layout.canvas.h - fixed, maxPreview)
	local ox = (layout.canvas.w - 720) / 2
	local y = (layout.canvas.h - (fixed + preview)) / 2 + 24

	layout.rects.header = rect(ox + 30, y, 660, headerH)
	y += headerH + 14
	layout.rects.preview = rect(ox + 100, y, 520, preview)
	y += preview + 16
	layout.rects.cardAngel = rect(ox + 20, y, 330, cardsH)
	layout.rects.cardDevil = rect(ox + 370, y, 330, cardsH)
	y += cardsH + 16
	layout.rects.looks = rect(ox + 100, y, 520, looksH)
	y += looksH + 14
	layout.rects.confirm = rect(ox + 150, y, 420, confirmH)
	y += confirmH + 12
	layout.rects.note = rect(ox + 60, y, 600, noteH)
	return layout
end

-- 360-wide column; the description folds away before the preview gets too small.
local function buildCompactPortrait(width: number, height: number): Layout
	local columnW = 360
	local titleH, toggleH, looksH, confirmH, noteH = 32, 56, 94, 56, 28
	local cardWithDescription, cardWithout = 166, 112
	local minPreview, maxPreview = 120, 340

	local function fixedFor(cardH: number): number
		return 8 + titleH + 6 + toggleH + GAP + GAP + cardH + GAP + looksH + GAP + confirmH + 6 + noteH + 6
	end

	local scale = clampScale(width / columnW)
	local showDescription = true
	local cardH = cardWithDescription
	if height / scale - fixedFor(cardH) < minPreview + 20 then
		showDescription = false
		cardH = cardWithout
	end
	if height / scale - fixedFor(cardH) < minPreview then
		scale = clampScale(height / (fixedFor(cardH) + minPreview))
	end

	local layout = base("compactPortrait", scale, width, height)
	layout.showDescription = showDescription

	local fixed = fixedFor(cardH)
	local preview = math.min(layout.canvas.h - fixed, maxPreview)
	local ox = (layout.canvas.w - columnW) / 2
	local y = (layout.canvas.h - (fixed + preview)) / 2 + 8
	local innerX, innerW = ox + 16, columnW - 32

	layout.rects.header = rect(ox, y, columnW, titleH)
	y += titleH + 6
	layout.rects.toggle = rect(innerX, y, innerW, toggleH)
	y += toggleH + GAP
	layout.rects.preview = rect(innerX, y, innerW, preview)
	y += preview + GAP
	layout.rects.card = rect(innerX, y, innerW, cardH)
	y += cardH + GAP
	layout.rects.looks = rect(innerX, y, innerW, looksH)
	y += looksH + GAP
	layout.rects.confirm = rect(innerX, y, innerW, confirmH)
	y += confirmH + 6
	layout.rects.note = rect(innerX, y, innerW, noteH)
	return layout
end

-- 360-tall right column; the preview fills the space on the left.
local function buildCompactLandscape(width: number, height: number): Layout
	local columnW, columnH = 354, 354
	local minPreviewW, maxPreviewW = 200, 460
	local scale = clampScale(math.min(height / 360, width / (columnW + minPreviewW + 36)))
	local layout = base("compactLandscape", scale, width, height)
	layout.showDescription = false

	local canvasW, canvasH = layout.canvas.w, layout.canvas.h
	local columnX = canvasW - columnW - 12
	local top = 38
	local columnY = top + math.max(0, (canvasH - top - columnH) / 2)

	local previewW = math.min(columnX - 24, maxPreviewW)
	local previewX = 12 + (columnX - 24 - previewW) / 2
	local noteH = 40
	local previewH = canvasH - top - noteH - 14

	layout.rects.header = rect(0, 4, canvasW, 28)
	layout.rects.preview = rect(previewX, top, previewW, previewH)
	layout.rects.note = rect(previewX, top + previewH + 6, previewW, noteH)

	local y = columnY
	layout.rects.toggle = rect(columnX, y, columnW, 56)
	y += 56 + 6
	layout.rects.card = rect(columnX, y, columnW, 96)
	y += 96 + 6
	layout.rects.looks = rect(columnX, y, columnW, 90)
	y += 90 + 6
	layout.rects.confirm = rect(columnX, y, columnW, 56)
	return layout
end

--------------------------------------------------------------------------------

--[[
	Picks and builds the layout for an available area of `width` x `height`
	pixels (already inside the safe area).
]]
function RaceSelectLayout.compute(width: number, height: number): Layout
	if width >= height then
		local wide = buildWide(width, height)
		return if readable(wide) then wide else buildCompactLandscape(width, height)
	end
	local tall = buildTall(width, height)
	return if readable(tall) then tall else buildCompactPortrait(width, height)
end

RaceSelectLayout.minFont = minFont
RaceSelectLayout.minTouch = minTouch

return table.freeze(RaceSelectLayout)
