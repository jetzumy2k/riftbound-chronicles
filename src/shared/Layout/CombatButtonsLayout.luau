--!strict
--[[
	CombatButtonsLayout — where the touch combat buttons sit (Phase 5).
	One source of truth for the attack button (CombatController), the run /
	crouch toggles (MovementModeController), the skill buttons
	(SkillBarController) and the quick Healing Potion button
	(InventoryController, D-72), so they never overlap (CLAUDE.md §28).

	Every button is placed by its distance from the bottom-right corner of
	the device safe area: `right` / `bottom` are the gaps to that corner and
	`size` the button's width and height (all in pixels). The corner itself
	(`JUMP_ZONE`) is left for Roblox's jump button.

	  arc     phone landscape (short screens, D-86): the skills ring the
	          attack button in two arcs (four inside, two and the special
	          outside, with the potion and the Auto switch at the ends), so
	          the cluster stays in the right corner and off the character;
	          run / crouch sit side by side above the jump button, and the
	          SKILLS / BAG toggles shrink to icon buttons in the right
	          column above them (`toggles`)
	  row     tablets and desktops (tall landscape): all six regular skills
	          and the special in two rows left of the attack button
	  column  narrow portrait: three regular buttons plus the special above
	          run / crouch; a small `page` button flips the three between
	          slots 1-3 and 4-6 (`paged`), so a phone held upright never
	          gets a wall of buttons (D-75)

	Checked on real device sizes in tests/pure/specs/combat_buttons_layout.spec.luau.
	Pure module.
]]

export type Slot = { right: number, bottom: number, size: number }
-- The SKILLS / BAG toggles: `right` / `bottom` gaps like a Slot, w x h.
export type Toggle = { right: number, bottom: number, w: number, h: number }
export type Layout = {
	mode: "arc" | "row" | "column",
	attack: Slot,
	sprint: Slot,
	crouch: Slot,
	skill1: Slot,
	skill2: Slot,
	skill3: Slot,
	skill4: Slot,
	skill5: Slot,
	skill6: Slot,
	special: Slot,
	potion: Slot,
	-- The Auto-attack on / off switch.
	auto: Slot,
	-- Column mode only: skills 4-6 share the places of 1-3 (one page shows).
	paged: boolean,
	page: Slot?,
}

local CombatButtonsLayout = {}

CombatButtonsLayout.MIN_TOUCH_PX = 44
-- Roblox's touch jump button lives inside this square at the corner.
CombatButtonsLayout.JUMP_ZONE = 110
-- Below this width the skills stack in a column (phone portrait).
CombatButtonsLayout.ROW_MIN_WIDTH = 480
-- Landscape screens shorter than this are phones: the arc layout (D-86).
CombatButtonsLayout.ARC_MAX_HEIGHT = 480
CombatButtonsLayout.SKILL_KEYS =
	table.freeze({ "skill1", "skill2", "skill3", "skill4", "skill5", "skill6", "special" })

local function slot(right: number, bottom: number, size: number): Slot
	return { right = right, bottom = bottom, size = size }
end

-- A button of `size` centred at angle `degrees` (0 = right, 90 = up) and
-- `radius` px from the centre (cr, cb) given as gaps to the corner.
local function onArc(cr: number, cb: number, radius: number, degrees: number, size: number): Slot
	local a = math.rad(degrees)
	local right = cr - math.cos(a) * radius
	local bottom = cb + math.sin(a) * radius
	return slot(math.floor(right - size / 2 + 0.5), math.floor(bottom - size / 2 + 0.5), size)
end

-- Phone landscape: the skills in two arcs round the attack button.
local function arc(height: number): Layout
	local k = math.clamp(height / 376, 0.82, 1)
	local attackSize = math.floor(80 * k + 0.5)
	local size = if k >= 0.9 then 46 else 44
	local special = size + 6
	local attack = slot(118, 14, attackSize)
	local cr, cb = 118 + attackSize / 2, 14 + attackSize / 2
	-- Inner arc: four buttons from straight up round to just below level,
	-- spaced so neighbours keep a 4 px gap.
	local step = (190 - 90) / 3
	local inner = math.max(attackSize / 2 + size / 2 + 6, (size + 4) / (2 * math.sin(math.rad(step / 2))))
	local outer = inner + size / 2 + 6 + special / 2
	return {
		mode = "arc",
		attack = attack,
		-- Side by side above Roblox's jump button.
		sprint = slot(8, CombatButtonsLayout.JUMP_ZONE + 6, size),
		crouch = slot(8 + size + 4, CombatButtonsLayout.JUMP_ZONE + 6, size),
		skill1 = onArc(cr, cb, inner, 90, size),
		skill2 = onArc(cr, cb, inner, 90 + step, size),
		skill3 = onArc(cr, cb, inner, 90 + step * 2, size),
		skill4 = onArc(cr, cb, inner, 190, size),
		skill5 = onArc(cr, cb, outer, 102, size),
		skill6 = onArc(cr, cb, outer, 132, size),
		special = onArc(cr, cb, outer, 162, special),
		potion = onArc(cr, cb, outer, 188, size),
		auto = onArc(cr, cb, outer, 72, 44),
		paged = false,
		page = nil,
	}
end

function CombatButtonsLayout.compute(width: number, height: number): Layout
	if width >= CombatButtonsLayout.ROW_MIN_WIDTH and height < CombatButtonsLayout.ARC_MAX_HEIGHT then
		return arc(height)
	end
	local attack = slot(120, 28, 92)
	local sprint = slot(120, 136, 64)
	local crouch = slot(196, 136, 64)
	if width >= CombatButtonsLayout.ROW_MIN_WIDTH then
		return {
			mode = "row",
			attack = attack,
			sprint = sprint,
			crouch = crouch,
			-- Two compact rows (4 + 3): on a 284 px tall phone the top row
			-- still clears the HUD (top-left), the upper row starts right of
			-- crouch, and the special sits at the end of the upper row.
			skill1 = slot(222, 28, 50),
			skill2 = slot(280, 28, 50),
			skill3 = slot(338, 28, 50),
			skill4 = slot(396, 28, 50),
			skill5 = slot(270, 86, 50),
			skill6 = slot(328, 86, 50),
			special = slot(386, 86, 56),
			-- Above the run toggle, next to the SKILLS / BAG column.
			potion = slot(120, 208, 52),
			-- Left of the potion, above crouch.
			auto = slot(196, 208, 52),
			paged = false,
			page = nil,
		}
	end
	return {
		mode = "column",
		attack = attack,
		sprint = sprint,
		crouch = crouch,
		skill1 = slot(120, 212, 60),
		skill2 = slot(192, 212, 60),
		skill3 = slot(120, 282, 60),
		skill4 = slot(120, 212, 60),
		skill5 = slot(192, 212, 60),
		skill6 = slot(120, 282, 60),
		special = slot(192, 280, 66),
		paged = true,
		-- Flips the three regular buttons between slots 1-3 and 4-6.
		page = slot(264, 220, 44),
		-- Above the page button, right of the special.
		auto = slot(264, 282, 44),
		-- The right-edge column, just under the BAG toggle (centre at
		-- height / 2 - 4, 44 tall): the skills fill the space above run.
		potion = slot(8, math.max(CombatButtonsLayout.JUMP_ZONE, math.floor(height / 2) - 78), 52),
	}
end

--[[
	The SKILLS and BAG toggles. Phone landscape (arc): 44 px icon buttons
	in the right column above run / crouch. Elsewhere: the 110 x 44 labelled
	toggles on the right edge around the middle of the screen (SKILLS
	centred 56 px above it, BAG 4 px above; InventoryLayout.TOGGLE).
	`compact` tells the controllers to show the icon only.
]]
function CombatButtonsLayout.toggles(
	width: number,
	height: number
): { skills: Toggle, bag: Toggle, compact: boolean }
	local layout = CombatButtonsLayout.compute(width, height)
	if layout.mode == "arc" then
		local above = layout.sprint.bottom + layout.sprint.size + 6
		return {
			skills = { right = 8, bottom = above, w = 44, h = 44 },
			bag = { right = 8, bottom = above + 50, w = 44, h = 44 },
			compact = true,
		}
	end
	local function centred(offset: number): Toggle
		-- Centre `offset` px from the middle (negative = higher).
		return { right = 8, bottom = math.floor(height / 2 - offset - 22 + 0.5), w = 110, h = 44 }
	end
	return { skills = centred(-56), bag = centred(-4), compact = false }
end

-- A toggle as a top-left rectangle inside a `width` x `height` safe area.
function CombatButtonsLayout.toggleRect(
	t: Toggle,
	width: number,
	height: number
): { x: number, y: number, w: number, h: number }
	return { x = width - t.right - t.w, y = height - t.bottom - t.h, w = t.w, h = t.h }
end

-- The buttons on screen at once (a paged layout shows one page of skills).
function CombatButtonsLayout.shownKeys(layout: Layout): { string }
	local keys = { "attack", "sprint", "crouch", "potion", "special", "auto" }
	for index = 1, if layout.paged then 3 else 6 do
		table.insert(keys, `skill{index}`)
	end
	if layout.page then
		table.insert(keys, "page")
	end
	return keys
end

-- A slot as a top-left rectangle inside a `width` x `height` safe area.
function CombatButtonsLayout.rect(
	s: Slot,
	width: number,
	height: number
): { x: number, y: number, w: number, h: number }
	return { x = width - s.right - s.size, y = height - s.bottom - s.size, w = s.size, h = s.size }
end

return table.freeze(CombatButtonsLayout)
