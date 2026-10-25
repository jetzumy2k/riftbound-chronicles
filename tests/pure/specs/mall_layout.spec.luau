local load = require("../loader")
local MallLayout = load("src/shared/Layout/MallLayout")
local DEVICES = require("../devices")

local function overlaps(a, b)
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

local function inside(r, w, h)
	return r.x >= 0 and r.y >= 0 and r.x + r.w <= w and r.y + r.h <= h
end

return function(t)
	t.describe("MallLayout", function()
		for _, device in DEVICES do
			local name, w, h = device[1], device[2], device[3]
			t.it(`{name}: the Mall fits, nothing overlaps, cards keep room`, function()
				local l = MallLayout.compute(w, h)
				t.ok(inside(l.panel, w, h), "panel on screen")
				local pw, ph = l.panel.w, l.panel.h
				for key, r in
					{ back = l.back, tabs = l.tabs, right = l.right, content = l.content, footer = l.footer }
				do
					t.ok(inside(r, pw, ph), `{key} inside the panel`)
				end
				t.ok(l.back.h >= 44 and l.tabs.h >= 44 and l.right.h >= 44, "44 px rows")
				t.ok(not overlaps(l.back, l.right), "back and the right buttons apart")
				t.ok(
					not overlaps(l.tabs, l.back) and not overlaps(l.tabs, l.right),
					"tabs clear of the header buttons"
				)
				t.ok(not overlaps(l.tabs, l.content) and not overlaps(l.content, l.footer), "rows stacked")
				t.ok(l.tabs.w >= 140, `tabs row wide enough ({l.tabs.w})`)
				-- At least one full card row plus its heading.
				t.ok(l.content.h >= l.cardH + 24, `cards fit ({l.content.h} for {l.cardH})`)
				if l.wide then
					t.ok(not overlaps(l.grid, l.detail), "cards and details side by side")
					t.ok(l.detail.w >= 220, "detail pane readable")
				end
				t.eq(l.short, h < MallLayout.SHORT_HEIGHT)
			end)
		end
	end)
end
