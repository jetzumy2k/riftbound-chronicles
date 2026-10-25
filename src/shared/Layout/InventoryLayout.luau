--!strict
--[[
	InventoryLayout — responsive layout of the inventory screen (Phase 7,
	D-64; stage 6 of the equipment overhaul, D-72: the equipment "doll").
	Pure function of the safe-area size; checked on real device sizes in
	tests/pure/specs/inventory_layout.spec.luau.

	  header   title, item count, wallet, Close
	  side     the doll (armor slots | live character preview | weapons and
	           jewellery), character stats, stackables (wide: own column)
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
	doll: Doll, -- at the top of `side`
}

-- The equipment block: two columns of slot tiles around the preview. All
-- rects relative to the doll's top-left corner.
export type Doll = {
	w: number,
	h: number,
	tile: number,
	label: number, -- slot label height under each tile (0 when short)
	preview: Rect,
	slots: { [string]: Rect },
}

local CombatButtonsLayout = require(script.Parent.CombatButtonsLayout)

local InventoryLayout = {}

InventoryLayout.MIN_TOUCH_PX = 44
InventoryLayout.WIDE_MIN_WIDTH = 760
InventoryLayout.TILE = 64
InventoryLayout.GAP = 8
InventoryLayout.SIDE_WIDTH = 220
InventoryLayout.SIDE_MAX = 300
InventoryLayout.DETAIL_WIDTH = 270
InventoryLayout.DETAIL_MIN = 230
InventoryLayout.FILTERS_HEIGHT = 48
-- Slot label under each doll tile (dropped on short screens).
InventoryLayout.SLOT_LABEL = 16
InventoryLayout.PREVIEW_MIN = 96
InventoryLayout.PREVIEW_MAX = 200
-- Character stats and the stackables list under the doll (stacked mode).
InventoryLayout.SIDE_EXTRA = 520
-- Doll columns, top to bottom: armor left, weapons and jewellery right.
InventoryLayout.LEFT_SLOTS = table.freeze({ "Helm", "Shoulders", "Chest", "Hands", "Legs", "Boots" })
InventoryLayout.RIGHT_SLOTS = table.freeze({ "Weapon", "OffHand", "Necklace", "Earrings", "Ring1", "Ring2" })

-- The "BAG" toggle on the HUD: right edge, just below the SKILLS toggle
-- (centre `offset` px from the screen's middle). Every combat button sits
-- at least 120 px from the right edge, so this column stays clear of them
-- and of the jump button corner.
InventoryLayout.TOGGLE = table.freeze({ right = 8, offset = -4, w = 110, h = 44 })

-- Where the toggle is drawn: CombatButtonsLayout.toggles places it with the
-- SKILLS toggle (an icon button in the right column on phone landscape).
function InventoryLayout.toggleRect(width: number, height: number): Rect
	local toggles = CombatButtonsLayout.toggles(width, height)
	return CombatButtonsLayout.toggleRect(toggles.bag, width, height)
end

local HEADER = 52
local PAD = 10

local function rect(x: number, y: number, w: number, h: number): Rect
	return { x = x, y = y, w = w, h = h }
end

--[[
	The doll `width` wide, fitting `height` when it can (tiles shrink to
	the touch minimum and labels drop; below that the side column scrolls).
]]
function InventoryLayout.doll(width: number, height: number): Doll
	local gap = InventoryLayout.GAP
	local rows = #InventoryLayout.LEFT_SLOTS
	local perRow = math.floor((height + gap) / rows)
	local label = if perRow >= InventoryLayout.MIN_TOUCH_PX + InventoryLayout.SLOT_LABEL + gap
		then InventoryLayout.SLOT_LABEL
		else 0
	local widest = math.floor((width - 2 * gap - InventoryLayout.PREVIEW_MIN) / 2)
	local tile =
		math.clamp(math.min(perRow - label - gap, widest), InventoryLayout.MIN_TOUCH_PX, InventoryLayout.TILE)
	local step = tile + label + gap
	local h = rows * step - gap
	local previewW = math.min(width - 2 * (tile + gap), InventoryLayout.PREVIEW_MAX)
	local previewX = math.floor((width - previewW) / 2)
	local slots = {}
	for index, slot in InventoryLayout.LEFT_SLOTS do
		slots[slot] = rect(0, (index - 1) * step, tile, tile)
	end
	for index, slot in InventoryLayout.RIGHT_SLOTS do
		slots[slot] = rect(width - tile, (index - 1) * step, tile, tile)
	end
	return {
		w = width,
		h = h,
		tile = tile,
		label = label,
		preview = rect(previewX, 0, previewW, h),
		slots = slots,
	}
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
		local detailW =
			math.floor(math.clamp(panelW * 0.28, InventoryLayout.DETAIL_MIN, InventoryLayout.DETAIL_WIDTH))
		-- The bag keeps room for 3 tiles a row (plus its scroll bar).
		local bagMin = 3 * (tile + gap) - gap + 12
		local sideW = math.clamp(
			panelW - PAD * 4 - detailW - bagMin,
			InventoryLayout.SIDE_WIDTH,
			InventoryLayout.SIDE_MAX
		)
		local side = rect(PAD, top, sideW, bodyH)
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
			doll = InventoryLayout.doll(sideW - 8, bodyH - 4),
		}
	end

	local body = rect(PAD, top, panelW - PAD * 2, bodyH)
	local innerW = body.w - 8 -- room for the scroll bar
	local doll = InventoryLayout.doll(innerW, math.huge)
	local sideH = doll.h + InventoryLayout.SIDE_EXTRA
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
		doll = doll,
	}
end

return table.freeze(InventoryLayout)
