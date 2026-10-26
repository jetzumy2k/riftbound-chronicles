local load = require("../loader")
local OverlayLayout = load("src/shared/Layout/OverlayLayout")
local DEVICES = require("../devices")

local function overlaps(a, b)
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

local function inside(r, w, h)
	return r.x >= 0 and r.y >= 0 and r.x + r.w <= w and r.y + r.h <= h
end

return function(t)
	t.describe("OverlayLayout", function()
		for _, device in DEVICES do
			local name, w, h = device[1], device[2], device[3]
			t.it(`{name}: badges, party and toasts on screen, toasts clear of buttons`, function()
				local layout = OverlayLayout.compute(w, h)
				local obstacles = OverlayLayout.obstacles(w, h)
				-- The first obstacle is the left column (badges + party).
				local leftColumn = obstacles[1]
				t.ok(inside(layout.chips, w, h), "badges on screen")
				t.ok(inside(layout.toasts, w, h), "toasts on screen")
				t.ok(layout.chips.x <= 8 and layout.chips.y <= 8, "badges in the top-left corner")
				t.ok(layout.party.y >= layout.chips.y + layout.chips.h, "party under the badges")
				t.ok(layout.chips.h >= 44, "badges are 44 px targets")
				t.ok(layout.toasts.w >= OverlayLayout.TOAST_MIN_W, "toasts wide enough")
				t.ok(not overlaps(layout.chips, layout.toasts), "toasts never cover the badges")
				for index, other in obstacles do
					-- Toasts (no input, a few seconds) may pass over the party
					-- panel's place on crowded phones, never over buttons.
					if other ~= leftColumn then
						t.ok(not overlaps(layout.toasts, other), `toasts clear of obstacle {index}`)
					end
				end
				t.eq(
					layout.maxToasts,
					if h < OverlayLayout.SHORT_HEIGHT or w < OverlayLayout.NARROW_WIDTH then 1 else 2
				)
			end)
		end
		t.it("tablets and desktops keep the toasts off the left column", function()
			for _, device in DEVICES do
				if device[2] >= 1024 then
					local layout = OverlayLayout.compute(device[2], device[3])
					local column = OverlayLayout.obstacles(device[2], device[3])[1]
					t.ok(not overlaps(layout.toasts, column), `{device[1]} toasts off the left column`)
				end
			end
		end)
	end)
end
