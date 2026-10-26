--!strict
--[[
	TopBarLayout — the status row in Roblox's top bar (PLAN.md D-98;
	creator review 2026-10-26: the HUD took the left side and the middle of
	the view while the top strip stood empty). Pure function of the free
	top-bar area (ScreenInsets.TopbarSafeInsets: right of Roblox's own
	buttons), tested on phone to desktop widths
	(tests/pure/specs/top_bar_layout.spec.luau).

	Left to right: the level medallion with the EXP bar, the HP bar with
	Focus under it, the zone badge (SAFE ZONE / WAR ZONE / PROTECTED);
	right-aligned: the 🎉 events chip, 📐 Edit HUD and, for staff, 🛠 Admin.
	The level and HP bars share what is left and shrink on phones
	("compact": at most 112 + 124 px wide and 32 px tall, the zone badge an
	icon, the events chip shorter, the numbers without units), leaving
	most of the strip free on phones; full details are in each tooltip.
]]

export type Rect = { x: number, y: number, w: number, h: number }
export type Layout = {
	compact: boolean,
	level: Rect,
	vitals: Rect,
	zone: Rect,
	events: Rect,
	edit: Rect,
	admin: Rect?,
}

local TopBarLayout = {}

TopBarLayout.GAP = 6
TopBarLayout.MAX_H = 44
TopBarLayout.MIN_H = 30
-- Width from which the wide form (labelled zone badge, long chip) fits.
TopBarLayout.WIDE_W = 700
TopBarLayout.LEVEL_W = { min = 96, max = 210 }
TopBarLayout.VITALS_W = { min = 112, max = 230 }
-- Phones (creator request 2026-10-26: the bars took too much of a small
-- screen): short, low bars that leave the rest of the strip free.
TopBarLayout.COMPACT_LEVEL_MAX = 112
TopBarLayout.COMPACT_VITALS_MAX = 124
TopBarLayout.COMPACT_H = 32

function TopBarLayout.compute(width: number, height: number, staff: boolean?): Layout
	local gap = TopBarLayout.GAP
	local compact = width < TopBarLayout.WIDE_W
	local h = math.clamp(
		height - 8,
		TopBarLayout.MIN_H,
		if compact then TopBarLayout.COMPACT_H else TopBarLayout.MAX_H
	)
	local y = math.floor((height - h) / 2)
	local icon = h
	local zoneW = if compact then h else 136
	local eventsW = if compact then 64 else 150
	-- Fixed pieces and the gaps between all of them.
	local fixed = zoneW + eventsW + icon + (if staff then icon else 0) + gap * (if staff then 7 else 6)
	local free = math.max(0, width - fixed)
	local levelMax = if compact then TopBarLayout.COMPACT_LEVEL_MAX else TopBarLayout.LEVEL_W.max
	local vitalsMax = if compact then TopBarLayout.COMPACT_VITALS_MAX else TopBarLayout.VITALS_W.max
	local levelW = math.clamp(math.floor(free * 0.45), TopBarLayout.LEVEL_W.min, levelMax)
	local vitalsW = math.clamp(free - levelW, TopBarLayout.VITALS_W.min, vitalsMax)
	local level = { x = gap, y = y, w = levelW, h = h }
	local vitals = { x = level.x + levelW + gap, y = y, w = vitalsW, h = h }
	local zone = { x = vitals.x + vitalsW + gap, y = y, w = zoneW, h = h }
	local right = width - gap
	local admin: Rect? = nil
	if staff then
		admin = { x = right - icon, y = y, w = icon, h = h }
		right -= icon + gap
	end
	local edit = { x = right - icon, y = y, w = icon, h = h }
	local events = { x = edit.x - gap - eventsW, y = y, w = eventsW, h = h }
	return {
		compact = compact,
		level = level,
		vitals = vitals,
		zone = zone,
		events = events,
		edit = edit,
		admin = admin,
	}
end

return TopBarLayout
