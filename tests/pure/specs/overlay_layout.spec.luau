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
			t.it(`{name}: chips and toasts on screen, clear of the HUD, tracker and buttons`, function()
				local layout = OverlayLayout.compute(w, h)
				local obstacles = OverlayLayout.obstacles(w, h)
				local hud, party = obstacles[1], obstacles[#obstacles]
				t.ok(inside(layout.chips, w, h), "chips on screen")
				t.ok(inside(layout.toasts, w, h), "toasts on screen")
				t.ok(layout.chips.w >= OverlayLayout.CHIP_MIN_W, "chips wide enough")
				t.ok(layout.toasts.w >= OverlayLayout.TOAST_MIN_W, "toasts wide enough")
				t.ok(not overlaps(layout.chips, layout.toasts), "toasts never cover the chips")
				for index, other in obstacles do
					-- Chips may use the party panel's place on the smallest phones.
					if other ~= party then
						t.ok(not overlaps(layout.chips, other), `chips clear of obstacle {index}`)
					end
					-- Toasts (no input, a few seconds) may pass over the HUD
					-- and the party panel's place on crowded phones.
					if other ~= hud and other ~= party then
						t.ok(not overlaps(layout.toasts, other), `toasts clear of obstacle {index}`)
					end
				end
				t.eq(layout.maxToasts, if h < OverlayLayout.SHORT_HEIGHT then 1 else 2)
				t.eq(layout.compact, layout.chips.w < 180)
				t.ok(OverlayLayout.EVENT_CHIP_H >= 44, "the tappable event chip is a 44 px target")
			end)
		end
		t.it("tablets and desktops keep the full chips and toasts clear of the HUD", function()
			for _, device in DEVICES do
				if device[2] >= 1024 then
					local layout = OverlayLayout.compute(device[2], device[3])
					local hud = OverlayLayout.obstacles(device[2], device[3])[1]
					t.ok(not layout.compact, `{device[1]} full chips`)
					t.ok(not overlaps(layout.toasts, hud), `{device[1]} toasts off the HUD`)
				end
			end
		end)
	end)
end
