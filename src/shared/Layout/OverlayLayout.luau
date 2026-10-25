--!strict
--[[
	OverlayLayout — where the top overlays sit (Phase 19, PLAN.md D-94): the
	🎉 event chip with the buff chip under it, and the notification toasts.
	Pure function of the safe-area size; tested on every device size
	(tests/pure/specs/overlay_layout.spec.luau) to stay clear of the HUD,
	the quest tracker, the SKILLS / BAG toggles, the combat buttons and
	Roblox's jump corner.

	Each overlay tries, in order: the gap at the top between the HUD and the
	quest tracker; the right side under the quest tracker; under the HUD on
	the left. The first spot that is free wins (chips first, then the toasts
	so they never cover the chips). `compact` asks the chips for their short
	form (icons and time only) when the spot is narrow.
]]

local QuestLayout = require(script.Parent.QuestLayout)

export type Rect = { x: number, y: number, w: number, h: number }
export type Layout = {
	-- The two chips stacked: events on top, buffs under it.
	chips: Rect,
	compact: boolean,
	-- Where toasts stack (top down), width included.
	toasts: Rect,
	-- How many toasts may show at once (1 on short screens).
	maxToasts: number,
}

local OverlayLayout = {}

OverlayLayout.MARGIN = 8
OverlayLayout.CHIP_W = 200
-- The chips' short form (icons only) fits this.
OverlayLayout.CHIP_MIN_W = 76
-- Events chip 44 (a touch target) + gap 4 + buff chip 26.
OverlayLayout.EVENT_CHIP_H = 44
OverlayLayout.CHIPS_H = 74
OverlayLayout.TOAST_W = 420
OverlayLayout.TOAST_MIN_W = 220
-- Two toasts of up to ~52 px with a gap; one on short screens.
OverlayLayout.TOASTS_H = 112
OverlayLayout.SHORT_TOASTS_H = 56
OverlayLayout.SHORT_HEIGHT = 420

local function overlaps(a: Rect, b: Rect): boolean
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

local function inside(r: Rect, w: number, h: number): boolean
	return r.x >= 0 and r.y >= 0 and r.x + r.w <= w and r.y + r.h <= h
end

-- Everything an overlay must not cover: QuestLayout's obstacles (HUD,
-- toggles, combat buttons, jump corner) plus the quest tracker itself.
function OverlayLayout.obstacles(width: number, height: number): { Rect }
	local list = table.clone(QuestLayout.obstacles(width, height))
	table.insert(list, QuestLayout.compute(width, height).tracker)
	-- The party panel's place under the HUD (PartyController, scaled).
	local scale = math.clamp(height / 720, 0.85, 1.35)
	table.insert(list, { x = 0, y = 160 * scale, w = 240 * scale, h = 150 * scale })
	return list
end

--[[
	The first free spot of size (w, h) between `minW` and `maxW` wide, from
	the candidate places, or nil. `taken` are rects already placed.
]]
local function place(
	width: number,
	height: number,
	maxW: number,
	minW: number,
	h: number,
	blocked: { Rect }
): Rect?
	local m = OverlayLayout.MARGIN
	local scale = math.clamp(height / 720, 0.85, 1.35)
	local hudW, hudH = 260 * scale, 160 * scale
	local tracker = QuestLayout.compute(width, height).tracker
	local trackerTop = tracker.y < 60
	local candidates: { Rect } = {}
	local left = hudW + m
	local right = if trackerTop then tracker.x - m else width - m
	local gap = right - left
	local widths = { maxW, minW }
	-- 1. The top gap between the HUD and the tracker (or the right edge).
	for _, w in widths do
		if gap >= w then
			table.insert(candidates, { x = math.floor(left + (gap - w) / 2), y = m, w = w, h = h })
		end
	end
	-- 2. Under the tracker on the right, right-aligned with it (or the
	-- top-right corner when the tracker sits lower).
	for _, w in widths do
		if trackerTop then
			local y = tracker.y + tracker.h + 6
			table.insert(candidates, { x = math.floor(tracker.x + tracker.w - w), y = y, w = w, h = h })
			-- Left-aligned with it (clear of buttons on the far right).
			table.insert(candidates, { x = tracker.x, y = y, w = w, h = h })
		else
			table.insert(candidates, { x = width - m - w, y = m, w = w, h = h })
		end
	end
	-- 3. Under the HUD on the left (below the party panel's place).
	for _, w in widths do
		table.insert(candidates, { x = m, y = math.floor(hudH + m), w = w, h = h })
	end
	for _, r in candidates do
		if r.w >= minW and inside(r, width, height) then
			local free = true
			for _, other in blocked do
				if overlaps(r, other) then
					free = false
					break
				end
			end
			if free then
				return r
			end
		end
	end
	return nil
end

function OverlayLayout.compute(width: number, height: number): Layout
	local blocked = OverlayLayout.obstacles(width, height)
	local m = OverlayLayout.MARGIN
	local chips =
		place(width, height, OverlayLayout.CHIP_W, OverlayLayout.CHIP_MIN_W, OverlayLayout.CHIPS_H, blocked)
	if chips == nil then
		-- The smallest phones: allow the party panel's place (only used in
		-- a party, and the player can move that panel).
		local noParty = table.clone(blocked)
		table.remove(noParty, #noParty)
		chips = place(
			width,
			height,
			OverlayLayout.CHIP_W,
			OverlayLayout.CHIP_MIN_W,
			OverlayLayout.CHIPS_H,
			noParty
		)
	end
	local placed: Rect = chips
		or {
			x = width - m - OverlayLayout.CHIP_MIN_W,
			y = m,
			w = OverlayLayout.CHIP_MIN_W,
			h = OverlayLayout.CHIPS_H,
		}
	local short = height < OverlayLayout.SHORT_HEIGHT
	local toastH = if short then OverlayLayout.SHORT_TOASTS_H else OverlayLayout.TOASTS_H
	local withChips = table.clone(blocked)
	table.insert(withChips, placed)
	local toasts = place(width, height, OverlayLayout.TOAST_W, OverlayLayout.TOAST_MIN_W, toastH, withChips)
	if toasts == nil then
		-- Last resort on crowded phones: over the HUD's top-left corner
		-- (toasts take no input and fade in seconds), still clear of the
		-- chips, the tracker and every button.
		local rest = table.clone(withChips)
		table.remove(rest, 1)
		local w = math.min(OverlayLayout.TOAST_W, width - 2 * m)
		for _, tryW in { w, OverlayLayout.TOAST_MIN_W } do
			local r = { x = m, y = m, w = tryW, h = toastH }
			local free = true
			for _, other in rest do
				if overlaps(r, other) then
					free = false
					break
				end
			end
			if free then
				toasts = r
				break
			end
		end
	end
	return {
		chips = placed,
		compact = placed.w < 180,
		toasts = toasts or { x = m, y = m, w = OverlayLayout.TOAST_MIN_W, h = toastH },
		maxToasts = if short then 1 else 2,
	}
end

return OverlayLayout
