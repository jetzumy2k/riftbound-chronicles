--[[
	Movable HUD pieces (D-74): saved centres stay on screen on any device,
	and only known ids with numbers in 0..1 are kept.
]]

local load = require("../loader")
local HudSlots = load("src/shared/Layout/HudSlots")
local DEVICES = require("../devices")

return function(t)
	t.describe("HudSlots", function()
		t.it("a moved piece stays fully on every screen", function()
			for _, device in DEVICES do
				local w, h = device[2], device[3]
				for _, spot in { { 0, 0 }, { 1, 1 }, { 0.5, 0.5 }, { 1, 0 }, { 0, 1 } } do
					local x, y = HudSlots.clampCenter(spot[1], spot[2], 250, 60, w, h)
					local left, top = x * w - 125, y * h - 30
					t.ok(left >= 0 and left + 250 <= w + 0.01, `{device[1]} x`)
					t.ok(top >= 0 and top + 60 <= h + 0.01, `{device[1]} y`)
				end
			end
			-- Wider than the screen: centred.
			t.eq(HudSlots.clampCenter(0, 0, 999, 10, 300, 300), 0.5)
		end)

		t.it("sanitize keeps known ids with numbers in 0..1 only", function()
			local out = HudSlots.sanitize({
				Bag = { X = 0.2, Y = 0.9 },
				Potion = { X = 1.5, Y = 0.5 },
				Quest = { X = 0 / 0, Y = 0.5 },
				Hacker = { X = 0.5, Y = 0.5 },
				Level = "nope",
			})
			t.eq(out.Bag.X, 0.2)
			t.eq(out.Potion, nil)
			t.eq(out.Quest, nil)
			t.eq(out.Hacker, nil)
			t.eq(out.Level, nil)
			t.eq(next(HudSlots.sanitize(nil)), nil)
		end)

		t.it("every id has a label", function()
			for _, id in HudSlots.IDS do
				t.ok(HudSlots.LABELS[id] ~= nil, id)
			end
		end)
	end)
end
