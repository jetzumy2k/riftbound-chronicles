--[[
	Inventory screen layout (Phase 7, D-64) on real device sizes.
]]

local load = require("../loader")
local InventoryLayout = load("src/shared/Layout/InventoryLayout")
local CombatButtonsLayout = load("src/shared/Layout/CombatButtonsLayout")
local DEVICES = require("../devices")

local function inside(r: any, w: number, h: number): boolean
	return r.x >= 0 and r.y >= 0 and r.x + r.w <= w + 0.01 and r.y + r.h <= h + 0.01
end

local function overlaps(a: any, b: any): boolean
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

return function(t)
	t.describe("InventoryLayout", function()
		for _, device in DEVICES do
			local name, width, height = device[1], device[2], device[3]
			t.it(`{name}: fits, touch-sized, no overlaps`, function()
				local layout = InventoryLayout.compute(width, height)
				local p = layout.panel
				t.ok(inside(p, width, height), "panel on screen")
				t.ok(layout.tile >= InventoryLayout.MIN_TOUCH_PX, "tile size")
				t.ok(inside(layout.header, p.w, p.h), "header")
				t.ok(inside(layout.detail, p.w, p.h), "detail")
				t.ok(layout.detail.y >= layout.header.y + layout.header.h, "detail below header")
				if layout.mode == "wide" then
					for _, key in { "side", "filters", "grid" } do
						t.ok(inside((layout :: any)[key], p.w, p.h), key)
					end
					t.ok(not overlaps(layout.side, layout.grid), "side / grid")
					t.ok(not overlaps(layout.grid, layout.detail), "grid / detail")
					t.ok(not overlaps(layout.filters, layout.grid), "filters / grid")
					t.ok(InventoryLayout.columns(layout.grid.w) >= 3, "3+ tiles a row")
				else
					t.ok(inside(layout.body, p.w, p.h), "body")
					t.ok(layout.side.w <= layout.body.w and layout.grid.w <= layout.body.w, "inside body")
					t.ok(InventoryLayout.columns(layout.grid.w) >= 3, "3+ tiles a row")
					t.ok(
						layout.side.w >= layout.slotColumns * (layout.tile + layout.gap) - layout.gap,
						"slots fit"
					)
				end
			end)

			t.it(`{name}: the BAG toggle clears the combat buttons and jump corner`, function()
				local toggle = InventoryLayout.toggleRect(width, height)
				t.ok(inside(toggle, width, height), "on screen")
				t.ok(toggle.h >= InventoryLayout.MIN_TOUCH_PX, "touch size")
				local combat = CombatButtonsLayout.compute(width, height)
				for _, key in { "attack", "sprint", "crouch", "skill1", "skill2", "skill3", "special" } do
					local r = CombatButtonsLayout.rect((combat :: any)[key], width, height)
					t.ok(not overlaps(toggle, r), key)
				end
				local jump = CombatButtonsLayout.JUMP_ZONE
				t.ok(
					not overlaps(toggle, { x = width - jump, y = height - jump, w = jump, h = jump }),
					"jump"
				)
				-- The SKILLS toggle sits just above (centre -56, 44 tall).
				local skills = { x = width - 118, y = height / 2 - 56 - 22, w = 110, h = 44 }
				t.ok(not overlaps(toggle, skills), "skills toggle")
			end)
		end
	end)
end
