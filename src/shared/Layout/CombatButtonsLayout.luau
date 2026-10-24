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

	  row     landscape / wide: all six regular skills and the special in
	          two rows left of the attack button
	  column  narrow portrait: three regular buttons plus the special above
	          run / crouch; a small `page` button flips the three between
	          slots 1-3 and 4-6 (`paged`), so a phone held upright never
	          gets a wall of buttons (D-75)

	Checked on real device sizes in tests/pure/specs/combat_buttons_layout.spec.luau.
	Pure module.
]]

export type Slot = { right: number, bottom: number, size: number }
export type Layout = {
	mode: "row" | "column",
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
CombatButtonsLayout.SKILL_KEYS =
	table.freeze({ "skill1", "skill2", "skill3", "skill4", "skill5", "skill6", "special" })

local function slot(right: number, bottom: number, size: number): Slot
	return { right = right, bottom = bottom, size = size }
end

function CombatButtonsLayout.compute(width: number, height: number): Layout
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
