--!strict
--[[
	InventoryLayout — responsive layout of the inventory screen (Phase 7,
	D-64). Pure function of the safe-area size; checked on real device
	sizes in tests/pure/specs/inventory_layout.spec.luau.

	  header   title, item count, wallet, Close
	  side     equipment slots, gear bonus, stackables (wide: own column)
	  filters  All / Weapons / Armor / Accessories, bulk salvage
	  grid     the bag (scrolls)
	  detail   the selected item and its buttons

	Modes:
	  wide     side | filters + grid | detail  (tablet / desktop)
	  stacked  one scrolling column (side, filters, grid); the detail is a
	           sheet over the bottom of the panel while an item is selected
	           (phones)

	All rects are in panel coordinates (pixels). Pure module.
]]

export type Rect = { x: number, y: number, w: number, h: number }

export type Layout = {
	mode: "wide" | "stacked",
	panel: Rect, -- in safe-area coordinates
	header: Rect,
	-- wide: the side column (scrolls); stacked: the scrolling body.
	body: Rect,
	side: Rect, -- wide: panel coordinates; stacked: inside `body`
	filters: Rect, -- wide: panel coordinates; stacked: inside `body`
	grid: Rect, -- wide: panel coordinates (scrolls); stacked: inside `body` (height grows)
	detail: Rect, -- wide: a column; stacked: the bottom sheet
	tile: number,
	gap: number,
	slotColumns: number, -- equipment slots per row
}

local InventoryLayout = {}

InventoryLayout.MIN_TOUCH_PX = 44
InventoryLayout.WIDE_MIN_WIDTH = 760
InventoryLayout.TILE = 64
InventoryLayout.GAP = 8
InventoryLayout.SIDE_WIDTH = 220
InventoryLayout.DETAIL_WIDTH = 270
InventoryLayout.FILTERS_HEIGHT = 48
-- Equipment block: rows of slot tiles with a label under each.
InventoryLayout.SLOT_LABEL = 16
-- Gear bonus text and the stackables list under the slots.
InventoryLayout.SIDE_EXTRA = 420

-- The "BAG" toggle on the HUD: right edge, just below the SKILLS toggle
-- (centre `offset` px from the screen's middle). Every combat button sits
-- at least 120 px from the right edge, so this column stays clear of them
-- and of the jump button corner.
InventoryLayout.TOGGLE = table.freeze({ right = 8, offset = -4, w = 110, h = 44 })

function InventoryLayout.toggleRect(width: number, height: number): Rect
	local t = InventoryLayout.TOGGLE
	return { x = width - t.right - t.w, y = height / 2 + t.offset - t.h / 2, w = t.w, h = t.h }
end

local HEADER = 52
local PAD = 10

local function rect(x: number, y: number, w: number, h: number): Rect
	return { x = x, y = y, w = w, h = h }
end

-- Height of the equipment block for `columns` slots per row (6 slots).
function InventoryLayout.slotsHeight(columns: number): number
	local rows = math.ceil(6 / columns)
	return rows * (InventoryLayout.TILE + InventoryLayout.SLOT_LABEL + InventoryLayout.GAP)
end

-- Bag tiles per row in a grid `width` wide.
function InventoryLayout.columns(width: number): number
	return math.max(
		1,
		math.floor((width + InventoryLayout.GAP) / (InventoryLayout.TILE + InventoryLayout.GAP))
	)
end

function InventoryLayout.compute(width: number, height: number): Layout
	local panelW = math.min(width - 16, 960)
	local panelH = math.min(height - 16, 660)
	local panel = rect((width - panelW) / 2, (height - panelH) / 2, panelW, panelH)
	local header = rect(PAD, 0, panelW - PAD * 2, HEADER)
	local top = HEADER + 4
	local bodyH = panelH - top - PAD
	local tile, gap = InventoryLayout.TILE, InventoryLayout.GAP

	if panelW >= InventoryLayout.WIDE_MIN_WIDTH then
		local side = rect(PAD, top, InventoryLayout.SIDE_WIDTH, bodyH)
		local detailW = InventoryLayout.DETAIL_WIDTH
		local detail = rect(panelW - PAD - detailW, top, detailW, bodyH)
		local middleX = side.x + side.w + PAD
		local middleW = detail.x - PAD - middleX
		local filters = rect(middleX, top, middleW, InventoryLayout.FILTERS_HEIGHT)
		local gridY = top + InventoryLayout.FILTERS_HEIGHT + 4
		return {
			mode = "wide",
			panel = panel,
			header = header,
			body = side,
			side = side,
			filters = filters,
			grid = rect(middleX, gridY, middleW, panelH - gridY - PAD),
			detail = detail,
			tile = tile,
			gap = gap,
			slotColumns = 3,
		}
	end

	local body = rect(PAD, top, panelW - PAD * 2, bodyH)
	local innerW = body.w - 8 -- room for the scroll bar
	local slotColumns = if innerW >= 6 * (tile + gap) then 6 else 3
	local sideH = InventoryLayout.slotsHeight(slotColumns) + InventoryLayout.SIDE_EXTRA
	local side = rect(0, 0, innerW, sideH)
	local filters = rect(0, sideH + gap, innerW, InventoryLayout.FILTERS_HEIGHT)
	local grid = rect(0, filters.y + filters.h + 4, innerW, 0)
	local sheetH = math.floor(math.clamp(panelH * 0.55, 200, 340))
	return {
		mode = "stacked",
		panel = panel,
		header = header,
		body = body,
		side = side,
		filters = filters,
		grid = grid,
		detail = rect(PAD, panelH - PAD - sheetH, panelW - PAD * 2, sheetH),
		tile = tile,
		gap = gap,
		slotColumns = slotColumns,
	}
end

return table.freeze(InventoryLayout)
