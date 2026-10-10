local load = require("../loader")
local Layout = load("src/shared/Layout/RaceSelectLayout")

local DEVICES = require("../devices")

local function visibleRects(layout)
	local list = {}
	for name, r in layout.rects do
		list[name] = r
	end
	return list
end

local function overlaps(a, b): boolean
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

return function(t)
	for _, device in DEVICES do
		local name, width, height = device[1], device[2], device[3]

		t.describe(name, function()
			local layout = Layout.compute(width, height)

			t.it("fits on screen", function()
				t.ok(
					layout.canvas.w * layout.scale <= width + 0.5,
					`canvas width {layout.canvas.w * layout.scale} > {width}`
				)
				t.ok(
					layout.canvas.h * layout.scale <= height + 0.5,
					`canvas height {layout.canvas.h * layout.scale} > {height}`
				)
				for rectName, r in layout.rects do
					t.ok(r.x >= 0 and r.y >= 0, `{rectName} starts off-canvas`)
					t.ok(
						r.x + r.w <= layout.canvas.w and r.y + r.h <= layout.canvas.h,
						`{rectName} ends off-canvas`
					)
				end
			end)

			t.it("elements do not overlap", function()
				local rects = visibleRects(layout)
				local names = {}
				for rectName in rects do
					table.insert(names, rectName)
				end
				table.sort(names)
				for i = 1, #names do
					for j = i + 1, #names do
						local a, b = rects[names[i]], rects[names[j]]
						t.ok(not overlaps(a, b), `{names[i]} overlaps {names[j]} ({layout.mode})`)
					end
				end
			end)

			t.it("text is at least 11 px", function()
				t.ok(
					Layout.minFont(layout) * layout.scale >= Layout.MIN_FONT_PX,
					`smallest font {Layout.minFont(layout) * layout.scale} px ({layout.mode})`
				)
			end)

			t.it("touch targets are at least 44 px", function()
				t.ok(
					Layout.minTouch(layout) * layout.scale >= Layout.MIN_TOUCH_PX,
					`smallest target {Layout.minTouch(layout) * layout.scale} px ({layout.mode})`
				)
			end)

			t.it("uses a mode matching the orientation", function()
				if width >= height then
					t.ok(layout.mode == "wide" or layout.mode == "compactLandscape", layout.mode)
				else
					t.ok(layout.mode == "tall" or layout.mode == "compactPortrait", layout.mode)
				end
				if layout.showBothCards then
					t.ok(layout.rects.cardAngel ~= nil and layout.rects.cardDevil ~= nil)
				else
					t.ok(layout.rects.card ~= nil and layout.rects.toggle ~= nil)
				end
			end)
		end)
	end

	t.it("phones get compact layouts, desktops get the wide layout", function()
		t.eq(Layout.compute(320, 510).mode, "compactPortrait")
		t.eq(Layout.compute(568, 284).mode, "compactLandscape")
		t.eq(Layout.compute(1920, 1024).mode, "wide")
		t.eq(Layout.compute(768, 968).mode, "tall")
	end)
end
