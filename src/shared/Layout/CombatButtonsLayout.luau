--!strict
--[[
	CombatButtonsLayout — where the touch combat buttons sit (Phase 5).
	One source of truth for the attack button (CombatController), the run /
	crouch toggles (MovementModeController), the four skill buttons
	(SkillBarController) and the quick Healing Potion button
	(InventoryController, D-72), so they never overlap (CLAUDE.md §28).

	Every button is placed by its distance from the bottom-right corner of
	the device safe area: `right` / `bottom` are the gaps to that corner and
	`size` the button's width and height (all in pixels). The corner itself
	(`JUMP_ZONE`) is left for Roblox's jump button.

	  row     landscape / wide: skills in two rows left of the attack button
	  column  narrow portrait: skills stacked above run / crouch

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
	special: Slot,
	potion: Slot,
}

local CombatButtonsLayout = {}

CombatButtonsLayout.MIN_TOUCH_PX = 44
-- Roblox's touch jump button lives inside this square at the corner.
CombatButtonsLayout.JUMP_ZONE = 110
-- Below this width the skills stack in a column (phone portrait).
CombatButtonsLayout.ROW_MIN_WIDTH = 480
CombatButtonsLayout.SKILL_KEYS = table.freeze({ "skill1", "skill2", "skill3", "special" })

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
			-- A compact 2 x 2 block: on a 284 px tall phone the top row still
			-- clears the HUD (top-left) and the bottom row the thumbstick.
			skill1 = slot(222, 28, 52),
			skill2 = slot(284, 28, 52),
			skill3 = slot(270, 90, 52),
			special = slot(332, 90, 56),
			-- Above the run toggle, next to the SKILLS / BAG column.
			potion = slot(120, 208, 52),
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
		special = slot(192, 280, 66),
		-- The right-edge column, just under the BAG toggle (centre at
		-- height / 2 - 4, 44 tall): the skills fill the space above run.
		potion = slot(8, math.max(CombatButtonsLayout.JUMP_ZONE, math.floor(height / 2) - 78), 52),
	}
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
