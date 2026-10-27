--!strict
--[[
	SkillTreeLayout — responsive layout of the skill tree screen (Phase 5,
	D-45). Pure function of the safe-area size; checked on real device sizes
	in tests/pure/specs/skills.spec.luau.

	  header   title, skill points, Reset, Close
	  bar      the 6 + 1 skill bar (tap a slot to inspect it)
	  tree     4 branch columns x 6 tier rows of skill nodes (scrolls),
	           then a row of 3 class passives (D-104) at the bottom
	  detail   the selected skill's information and buttons

	Modes:
	  wide     tree on the left, details on the right (tablet / desktop /
	           wide phone landscape)
	  stacked  one scrolling column: tree, then details (narrow screens)

	All rects are in panel coordinates (pixels). Pure module.
]]

export type Rect = { x: number, y: number, w: number, h: number }

export type Layout = {
	mode: "wide" | "stacked",
	panel: Rect, -- in safe-area coordinates
	header: Rect,
	bar: Rect,
	barSlot: number,
	-- Scrolling body (stacked: tree + detail inside; wide: tree only).
	body: Rect,
	tree: Rect, -- inside `body`
	detail: Rect, -- wide: panel coordinates; stacked: inside `body` (height grows)
	node: number,
	-- Node centres by "branchIndex.tier" inside `tree`.
	nodes: { [string]: { x: number, y: number } },
	-- D-104: the passive row (title at `passiveTop`) and its 3 node centres.
	passiveTop: number,
	passives: { { x: number, y: number } },
	columnWidth: number,
	columnHeader: number,
}

local SkillTreeLayout = {}

SkillTreeLayout.MIN_TOUCH_PX = 44
SkillTreeLayout.BRANCHES = 4
SkillTreeLayout.TIERS = 6
SkillTreeLayout.WIDE_MIN_WIDTH = 620
-- Room under a node for its name (two short lines; the rank is a badge).
SkillTreeLayout.LABEL_HEIGHT = 26

local HEADER = 48
local BAR = 70
local PAD = 10
local COLUMN_HEADER = 34 -- branch name + role line (D-103)
SkillTreeLayout.PASSIVES = 3
local PASSIVE_TITLE = 26

-- Height of the passive row for a node size.
local function passiveRow(node: number): number
	return PASSIVE_TITLE + 8 + node + SkillTreeLayout.LABEL_HEIGHT + 12
end

local function rect(x: number, y: number, w: number, h: number): Rect
	return { x = x, y = y, w = w, h = h }
end

-- Tier nodes fill `tree` above the passive row.
local function placeNodes(tree: Rect, node: number): { [string]: { x: number, y: number } }
	local nodes = {}
	local columnWidth = tree.w / SkillTreeLayout.BRANCHES
	local rowHeight = (tree.h - passiveRow(node) - COLUMN_HEADER) / SkillTreeLayout.TIERS
	for branch = 1, SkillTreeLayout.BRANCHES do
		for tier = 1, SkillTreeLayout.TIERS do
			nodes[`{branch}.{tier}`] = {
				x = (branch - 0.5) * columnWidth,
				-- 8 px of room above the first row for the LEARN badge.
				y = COLUMN_HEADER + (tier - 1) * rowHeight + 8 + node / 2,
			}
		end
	end
	return nodes
end

local function placePassives(tree: Rect, node: number): (number, { { x: number, y: number } })
	local top = tree.h - passiveRow(node)
	local out = {}
	local step = tree.w / SkillTreeLayout.PASSIVES
	for index = 1, SkillTreeLayout.PASSIVES do
		table.insert(out, { x = (index - 0.5) * step, y = top + PASSIVE_TITLE + 8 + node / 2 })
	end
	return top, out
end

function SkillTreeLayout.compute(width: number, height: number): Layout
	local panelW = math.min(width - 16, 920)
	local panelH = math.min(height - 16, 640)
	local panel = rect((width - panelW) / 2, (height - panelH) / 2, panelW, panelH)
	local header = rect(PAD, 0, panelW - PAD * 2, HEADER)
	local bar = rect(PAD, HEADER, panelW - PAD * 2, BAR)
	local barSlot = 52
	local bodyY = HEADER + BAR + 4
	local body = rect(PAD, bodyY, panelW - PAD * 2, panelH - bodyY - PAD)

	if panelW >= SkillTreeLayout.WIDE_MIN_WIDTH then
		local treeW = math.floor(math.min(body.w * 0.56, 540))
		local rowRoom = (body.h - COLUMN_HEADER) / SkillTreeLayout.TIERS - SkillTreeLayout.LABEL_HEIGHT - 10
		local node = math.floor(
			math.clamp(
				math.min(treeW / SkillTreeLayout.BRANCHES - 30, rowRoom),
				SkillTreeLayout.MIN_TOUCH_PX,
				62
			)
		)
		-- Tall enough for every row of nodes even if the panel is short (scrolls).
		local treeH = math.max(
			body.h,
			COLUMN_HEADER
				+ SkillTreeLayout.TIERS * (node + SkillTreeLayout.LABEL_HEIGHT + 10)
				+ passiveRow(node)
		)
		local tree = rect(0, 0, treeW, treeH)
		local passiveTop, passives = placePassives(tree, node)
		return {
			mode = "wide",
			panel = panel,
			header = header,
			bar = bar,
			barSlot = barSlot,
			body = rect(body.x, body.y, treeW, body.h),
			tree = tree,
			detail = rect(body.x + treeW + PAD, body.y, body.w - treeW - PAD, body.h),
			node = node,
			nodes = placeNodes(tree, node),
			passiveTop = passiveTop,
			passives = passives,
			columnWidth = treeW / SkillTreeLayout.BRANCHES,
			columnHeader = COLUMN_HEADER,
		}
	end

	local node =
		math.floor(math.clamp((body.w - 8) / SkillTreeLayout.BRANCHES - 30, SkillTreeLayout.MIN_TOUCH_PX, 60))
	local treeH = COLUMN_HEADER
		+ SkillTreeLayout.TIERS * (node + SkillTreeLayout.LABEL_HEIGHT + 10)
		+ passiveRow(node)
	local tree = rect(0, 0, body.w - 8, treeH)
	local passiveTop, passives = placePassives(tree, node)
	return {
		mode = "stacked",
		panel = panel,
		header = header,
		bar = bar,
		barSlot = barSlot,
		body = body,
		tree = tree,
		detail = rect(0, treeH + PAD, body.w - 8, 0),
		node = node,
		nodes = placeNodes(tree, node),
		passiveTop = passiveTop,
		passives = passives,
		columnWidth = tree.w / SkillTreeLayout.BRANCHES,
		columnHeader = COLUMN_HEADER,
	}
end

return table.freeze(SkillTreeLayout)
