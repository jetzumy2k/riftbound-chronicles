--!strict
--[[
	QuestLayout — where the quest UI sits (Phase 11, D-73). Pure function of
	the safe-area size; checked on real device sizes in
	tests/pure/specs/quest_layout.spec.luau.

	  tracker  the current quest. "full": a card with the quest and its next
	           step in the top-right corner, above the SKILLS / BAG column
	           (the left side holds the HUD and the party panel, the bottom
	           corners the thumbstick and combat buttons). Where the card
	           would cover something (phones in portrait, very short
	           landscape screens) it becomes a "pill" the size of the
	           SKILLS / BAG toggles: top-right if free, else in the right
	           column under the potion button. Tap either to open the log.
	  panel    the quest log and the quest giver's dialogue: a centred
	           panel over everything while open.
]]

local CombatButtonsLayout = require(script.Parent.CombatButtonsLayout)

export type Rect = { x: number, y: number, w: number, h: number }

export type Layout = {
	tracker: Rect,
	trackerMode: "full" | "pill",
	panel: Rect,
	compact: boolean, -- one-column log (phones)
}

local QuestLayout = {}

QuestLayout.MIN_TOUCH_PX = 44
QuestLayout.MARGIN = 8
QuestLayout.TRACKER_MAX_W = 270
QuestLayout.TRACKER_MIN_W = 180
QuestLayout.TRACKER_H = 52
QuestLayout.PILL = table.freeze({ w = 110, h = 44 })

local function overlaps(a: Rect, b: Rect): boolean
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

local function inside(r: Rect, w: number, h: number): boolean
	return r.x >= 0 and r.y >= 0 and r.x + r.w <= w and r.y + r.h <= h
end

-- Everything the tracker must not cover.
function QuestLayout.obstacles(width: number, height: number): { Rect }
	-- The left column: buff badges and the party panel under them (D-98:
	-- the HUD panels moved to Roblox's top bar).
	local toggles = CombatButtonsLayout.toggles(width, height)
	local list: { Rect } = {
		{ x = 0, y = 0, w = 246, h = 214 },
		-- The SKILLS and BAG toggles.
		CombatButtonsLayout.toggleRect(toggles.skills, width, height),
		CombatButtonsLayout.toggleRect(toggles.bag, width, height),
		-- Roblox's jump button corner.
		{
			x = width - CombatButtonsLayout.JUMP_ZONE,
			y = height - CombatButtonsLayout.JUMP_ZONE,
			w = CombatButtonsLayout.JUMP_ZONE,
			h = CombatButtonsLayout.JUMP_ZONE,
		},
	}
	local combat = CombatButtonsLayout.compute(width, height)
	for _, key in CombatButtonsLayout.shownKeys(combat) do
		table.insert(list, CombatButtonsLayout.rect((combat :: any)[key], width, height))
	end
	return list
end

function QuestLayout.compute(width: number, height: number): Layout
	local m = QuestLayout.MARGIN
	local blocked = QuestLayout.obstacles(width, height)
	local function free(r: Rect): boolean
		if not inside(r, width, height) then
			return false
		end
		for _, other in blocked do
			if overlaps(r, other) then
				return false
			end
		end
		return true
	end

	local trackerW = math.floor(math.min(QuestLayout.TRACKER_MAX_W, width * 0.45))
	local full = { x = width - m - trackerW, y = m, w = trackerW, h = QuestLayout.TRACKER_H }
	local pill = QuestLayout.PILL
	local candidates: { { rect: Rect, mode: "full" | "pill" } } = {
		{ rect = full, mode = "full" },
		{ rect = { x = width - m - pill.w, y = m, w = pill.w, h = pill.h }, mode = "pill" },
		-- Phone landscape: the card, then the pill, left of the icon column.
		{
			rect = { x = width - 60 - m - trackerW, y = m, w = trackerW, h = QuestLayout.TRACKER_H },
			mode = "full",
		},
		{ rect = { x = width - 60 - m - pill.w, y = m, w = pill.w, h = pill.h }, mode = "pill" },
	}
	-- Under the potion button in the right column (portrait).
	local combat = CombatButtonsLayout.compute(width, height)
	local potion = CombatButtonsLayout.rect(combat.potion, width, height)
	table.insert(candidates, {
		rect = { x = width - m - pill.w, y = potion.y + potion.h + m, w = pill.w, h = pill.h },
		mode = "pill",
	})
	local chosen = candidates[#candidates]
	for _, candidate in candidates do
		if (candidate.mode ~= "full" or trackerW >= QuestLayout.TRACKER_MIN_W) and free(candidate.rect) then
			chosen = candidate
			break
		end
	end

	local panelW = math.min(width - 16, 720)
	local panelH = math.min(height - 16, 560)
	local panel = { x = (width - panelW) / 2, y = (height - panelH) / 2, w = panelW, h = panelH }
	return { tracker = chosen.rect, trackerMode = chosen.mode, panel = panel, compact = panelW < 560 }
end

return table.freeze(QuestLayout)
