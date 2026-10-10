local load = require("../loader")
local Layout = load("src/shared/Layout/JobSelectLayout")

local DEVICES = require("../devices")

local function overlaps(a, b): boolean
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

return function(t)
	for _, device in DEVICES do
		local name, width, height = device[1], device[2], device[3]

		t.describe(name, function()
			local layout = Layout.compute(width, height)

			t.it("fits on screen", function()
				t.ok(layout.canvas.w * layout.scale <= width + 0.5)
				t.ok(layout.canvas.h * layout.scale <= height + 0.5)
				for rectName, r in layout.rects do
					t.ok(r.x >= 0 and r.y >= 0, `{rectName} starts off-canvas`)
					t.ok(
						r.x + r.w <= layout.canvas.w + 0.01 and r.y + r.h <= layout.canvas.h + 0.01,
						`{rectName} ends off-canvas`
					)
				end
			end)

			t.it("has a card for every job and no overlaps", function()
				for _, key in Layout.CARD_KEYS do
					t.ok(layout.rects[key] ~= nil, key)
				end
				local names = {}
				for rectName in layout.rects do
					table.insert(names, rectName)
				end
				table.sort(names)
				for i = 1, #names do
					for j = i + 1, #names do
						t.ok(
							not overlaps(layout.rects[names[i]], layout.rects[names[j]]),
							`{names[i]} overlaps {names[j]} ({layout.mode})`
						)
					end
				end
			end)

			t.it("text >= 11 px and touch targets >= 44 px", function()
				t.ok(
					Layout.minFont(layout) * layout.scale >= Layout.MIN_FONT_PX,
					`font {Layout.minFont(layout) * layout.scale}`
				)
				t.ok(
					Layout.minTouch(layout) * layout.scale >= Layout.MIN_TOUCH_PX,
					`touch {Layout.minTouch(layout) * layout.scale}`
				)
			end)
		end)
	end

	t.it("phones get compact layouts, desktops the wide layout", function()
		t.eq(Layout.compute(320, 510).mode, "compactPortrait")
		t.eq(Layout.compute(568, 284).mode, "compactLandscape")
		t.eq(Layout.compute(1920, 1024).mode, "wide")
		t.eq(Layout.compute(768, 968).mode, "tall")
	end)
end
