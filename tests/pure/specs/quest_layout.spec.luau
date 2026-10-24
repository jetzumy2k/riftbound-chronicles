--[[
	Quest UI layout (Phase 11, D-73) on real device sizes: the tracker stays
	clear of the HUD, the SKILLS / BAG toggles and every combat button.
]]

local load = require("../loader")
local QuestLayout = load("src/shared/Layout/QuestLayout")
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
	t.describe("QuestLayout", function()
		for _, device in DEVICES do
			local name, width, height = device[1], device[2], device[3]
			t.it(`{name}: tracker and panel fit and clear the HUD and buttons`, function()
				local layout = QuestLayout.compute(width, height)
				t.ok(inside(layout.tracker, width, height), "tracker on screen")
				t.ok(inside(layout.panel, width, height), "panel on screen")
				t.ok(layout.tracker.h >= QuestLayout.MIN_TOUCH_PX, "tracker touch size")
				t.ok(layout.tracker.w >= 100, "tracker width")
				for index, other in QuestLayout.obstacles(width, height) do
					t.ok(
						not overlaps(layout.tracker, other),
						`tracker overlaps obstacle {index} ({layout.trackerMode})`
					)
				end
				-- Independent of the module's own list: the HUD and toggles.
				local scale = math.clamp(height / 720, 0.85, 1.35)
				t.ok(not overlaps(layout.tracker, { x = 0, y = 0, w = 260 * scale, h = 160 * scale }), "HUD")
				t.ok(not overlaps(layout.tracker, InventoryLayout.toggleRect(width, height)), "bag toggle")
				local potion =
					CombatButtonsLayout.rect(CombatButtonsLayout.compute(width, height).potion, width, height)
				t.ok(not overlaps(layout.tracker, potion), "potion")
			end)
		end
	end)
end
