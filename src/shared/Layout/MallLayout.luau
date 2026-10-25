--!strict
--[[
	MallLayout — the Item Mall panel's regions (Phase 19, PLAN.md D-94).
	Pure function of the safe-area size; tested on every device size
	(tests/pure/specs/mall_layout.spec.luau).

	  normal   header row (← Bag, title, balance, Get MP, Close), then the
	           tab row, then the cards (and the detail pane beside them when
	           the panel is wide), then the status line
	  short    (phone landscape) the tabs share the header row so the cards
	           keep their height: ← Bag, tabs, balance, Close; no title

	Rects are inside the panel (panel-relative), except `panel` itself.
]]

export type Rect = { x: number, y: number, w: number, h: number }
export type Layout = {
	panel: Rect,
	short: boolean,
	wide: boolean,
	back: Rect,
	tabs: Rect,
	right: Rect,
	content: Rect,
	-- When wide: the cards on the left, the detail pane on the right.
	grid: Rect,
	detail: Rect,
	footer: Rect,
	cardH: number,
	showTitle: boolean,
	showGetMp: boolean,
}

local MallLayout = {}

MallLayout.MARGIN = 8
MallLayout.ROW = 44
MallLayout.SHORT_HEIGHT = 420
MallLayout.WIDE = 620
MallLayout.MAX_W = 760
MallLayout.MAX_H = 580

function MallLayout.compute(width: number, height: number): Layout
	local m = MallLayout.MARGIN
	local w = math.min(width - 2 * m, MallLayout.MAX_W)
	local h = math.min(height - 2 * m, MallLayout.MAX_H)
	local panel = { x = math.floor((width - w) / 2), y = math.floor((height - h) / 2), w = w, h = h }
	local short = height < MallLayout.SHORT_HEIGHT
	local wide = w >= MallLayout.WIDE
	local row = MallLayout.ROW
	local back = { x = 10, y = m, w = 84, h = row }
	local showGetMp = w >= 420 and not short
	-- Balance (~90) + Get MP (80) + Close (70) + gaps.
	local rightW = if showGetMp then 260 else 170
	local right = { x = w - 10 - rightW, y = m, w = rightW, h = row }
	local tabs: Rect
	local top: number
	if short then
		tabs = { x = back.x + back.w + 6, y = m, w = right.x - 6 - (back.x + back.w + 6), h = row }
		top = m + row + 6
	else
		tabs = { x = 10, y = m + row + 8, w = w - 20, h = row + 4 }
		top = tabs.y + tabs.h + 8
	end
	local footerH = if short then 22 else 26
	local content = { x = 10, y = top, w = w - 20, h = h - top - footerH - 8 }
	local gridW = if wide then math.floor((content.w - 10) * 0.58) else content.w
	local grid = { x = content.x, y = content.y, w = gridW, h = content.h }
	local detail = if wide
		then { x = content.x + gridW + 10, y = content.y, w = content.w - gridW - 10, h = content.h }
		else content
	return {
		panel = panel,
		short = short,
		wide = wide,
		back = back,
		tabs = tabs,
		right = right,
		content = content,
		grid = grid,
		detail = detail,
		footer = { x = 14, y = h - footerH - 4, w = w - 28, h = footerH },
		cardH = if short then 96 else 112,
		showTitle = not short and w >= 480,
		showGetMp = showGetMp,
	}
end

return MallLayout
