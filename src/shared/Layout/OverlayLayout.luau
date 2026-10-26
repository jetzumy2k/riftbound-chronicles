--!strict
--[[
	OverlayLayout — where the overlays in the play area sit (Phase 19, D-94;
	reorganised with the top bar, D-98). Pure function of the safe-area size
	(below Roblox's top bar); tested on every device size
	(tests/pure/specs/overlay_layout.spec.luau).

	The status row (level, HP, zone, events, 📐, 🛠) lives in Roblox's top
	bar now (TopBarLayout), so the play area keeps only:
	  - the buff badges, top-left (only while a buff runs);
	  - the party panel under them (only in a party);
	  - the toasts, in the first free spot of: the top gap between the badges
	    and the quest tracker, under the tracker, under the party panel.
	Toasts never cover the badges, the tracker, the SKILLS / BAG toggles,
	the combat buttons or Roblox's jump corner; one at a time on short
	screens.
]]

local QuestLayout = require(script.Parent.QuestLayout)

export type Rect = { x: number, y: number, w: number, h: number }
export type Layout = {
	-- The buff badges' row.
	chips: Rect,
	compact: boolean,
	-- The party panel's default place.
	party: Rect,
	-- Where toasts stack (top down), width included.
	toasts: Rect,
	-- How many toasts may show at once (1 on short screens).
	maxToasts: number,
}

local OverlayLayout = {}

OverlayLayout.MARGIN = 8
OverlayLayout.BADGE_W = 52
OverlayLayout.BADGE_H = 44
-- The badge row's widest (4 badges) and the party panel's size.
OverlayLayout.CHIP_W = 220
OverlayLayout.PARTY_W = 230
OverlayLayout.PARTY_H = 150
OverlayLayout.TOAST_W = 420
OverlayLayout.TOAST_MIN_W = 220
-- Two toasts of up to ~52 px with a gap; one on short screens.
OverlayLayout.TOASTS_H = 112
OverlayLayout.SHORT_TOASTS_H = 56
OverlayLayout.SHORT_HEIGHT = 420
OverlayLayout.NARROW_WIDTH = 480

local function overlaps(a: Rect, b: Rect): boolean
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

local function inside(r: Rect, w: number, h: number): boolean
	return r.x >= 0 and r.y >= 0 and r.x + r.w <= w and r.y + r.h <= h
end

-- The badge row and the party panel (top-left).
local function corner(width: number): (Rect, Rect)
	local m = OverlayLayout.MARGIN
	local chips =
		{ x = m, y = m, w = math.min(OverlayLayout.CHIP_W, width - 2 * m), h = OverlayLayout.BADGE_H }
	local party = { x = m, y = chips.y + chips.h + m, w = OverlayLayout.PARTY_W, h = OverlayLayout.PARTY_H }
	return chips, party
end

-- Everything a toast must not cover: QuestLayout's obstacles (the left
-- column, toggles, combat buttons, jump corner) plus the quest tracker.
function OverlayLayout.obstacles(width: number, height: number): { Rect }
	local list = table.clone(QuestLayout.obstacles(width, height))
	table.insert(list, QuestLayout.compute(width, height).tracker)
	return list
end

function OverlayLayout.compute(width: number, height: number): Layout
	local m = OverlayLayout.MARGIN
	local chips, party = corner(width)
	local blocked = OverlayLayout.obstacles(width, height)
	-- Short or narrow (portrait phone) screens: one toast at a time.
	local short = height < OverlayLayout.SHORT_HEIGHT or width < OverlayLayout.NARROW_WIDTH
	local toastH = if short then OverlayLayout.SHORT_TOASTS_H else OverlayLayout.TOASTS_H
	local tracker = QuestLayout.compute(width, height).tracker
	local trackerTop = tracker.y < 60
	local left = chips.x + chips.w + m
	local right = if trackerTop then tracker.x - m else width - m
	local candidates: { Rect } = {}
	for _, w in { OverlayLayout.TOAST_W, OverlayLayout.TOAST_MIN_W } do
		-- 1. The top gap between the badges and the tracker.
		if right - left >= w then
			table.insert(
				candidates,
				{ x = math.floor(left + (right - left - w) / 2), y = m, w = w, h = toastH }
			)
		end
	end
	for _, w in { OverlayLayout.TOAST_W, OverlayLayout.TOAST_MIN_W } do
		-- 2. Under the tracker, right-aligned with it.
		if trackerTop then
			table.insert(candidates, {
				x = math.floor(tracker.x + tracker.w - w),
				y = tracker.y + tracker.h + 6,
				w = w,
				h = toastH,
			})
		end
	end
	for _, w in { OverlayLayout.TOAST_W, OverlayLayout.TOAST_MIN_W } do
		-- 3. Under the party panel's place.
		table.insert(candidates, { x = m, y = party.y + party.h + m, w = w, h = toastH })
	end
	local toasts: Rect? = nil
	for _, r in candidates do
		if inside(r, width, height) then
			local free = true
			for _, other in blocked do
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
	if toasts == nil then
		-- Last resort on crowded phones: over the party panel's place (toasts
		-- take no input and fade in seconds), still clear of every button.
		local rest = table.clone(blocked)
		table.remove(rest, 1)
		for _, w in { OverlayLayout.TOAST_W, OverlayLayout.TOAST_MIN_W } do
			local r = { x = m, y = party.y, w = math.min(w, width - 2 * m), h = toastH }
			local free = inside(r, width, height)
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
		chips = chips,
		compact = chips.w < 180,
		party = party,
		toasts = toasts or { x = m, y = party.y, w = OverlayLayout.TOAST_MIN_W, h = toastH },
		maxToasts = if short then 1 else 2,
	}
end

return OverlayLayout
