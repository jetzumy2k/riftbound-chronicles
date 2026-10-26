local load = require("../loader")
local TopBarLayout = load("src/shared/Layout/TopBarLayout")
local CombatButtonsLayout = load("src/shared/Layout/CombatButtonsLayout")
local DEVICES = require("../devices")

local function overlaps(a, b)
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

-- Free top-bar widths, phone landscape (Roblox's buttons take ~150 px) to desktop.
local WIDTHS = { 420, 460, 520, 600, 700, 900, 1200, 1750, 3600 }
local HEIGHTS = { 36, 44, 58 }

return function(t)
	t.describe("Desktop corner column (D-98)", function()
		for _, device in DEVICES do
			local name, w, h = device[1], device[2], device[3]
			if w < 900 then
				continue
			end
			t.it(`{name}: SKILLS, BAG and the potion stack in the bottom-right corner`, function()
				local toggles = CombatButtonsLayout.toggles(w, h, false)
				local skills = CombatButtonsLayout.toggleRect(toggles.skills, w, h)
				local bag = CombatButtonsLayout.toggleRect(toggles.bag, w, h)
				local potion = CombatButtonsLayout.rect(CombatButtonsLayout.desktopPotion(), w, h)
				for label, r in { skills = skills, bag = bag, potion = potion } do
					t.ok(r.x >= 0 and r.y >= 0 and r.x + r.w <= w and r.y + r.h <= h, `{label} on screen`)
					t.ok(r.x > w * 0.85 and r.y > h * 0.6, `{label} in the bottom-right corner`)
					t.ok(r.w >= 44 and r.h >= 44, `{label} 44 px`)
				end
				t.ok(
					not overlaps(skills, bag) and not overlaps(skills, potion) and not overlaps(bag, potion),
					"no overlaps"
				)
				t.ok(bag.y > skills.y and skills.y > potion.y, "BAG lowest, then SKILLS, then the potion")
			end)
		end
	end)

	t.describe("TopBarLayout", function()
		for _, staff in { false, true } do
			for _, h in HEIGHTS do
				for _, w in WIDTHS do
					if staff and w < 460 then
						continue
					end
					t.it(
						`{w} x {h}{if staff then " (staff)" else ""}: every piece fits, none overlap`,
						function()
							local l = TopBarLayout.compute(w, h, staff)
							local pieces = {
								level = l.level,
								vitals = l.vitals,
								zone = l.zone,
								events = l.events,
								edit = l.edit,
							}
							if staff then
								pieces.admin = l.admin
								t.ok(l.admin ~= nil, "staff get the admin button")
							else
								t.eq(l.admin, nil)
							end
							local list = {}
							for name, r in pieces do
								t.ok(
									r.x >= 0 and r.y >= 0 and r.x + r.w <= w and r.y + r.h <= h,
									`{name} inside`
								)
								t.ok(r.h >= TopBarLayout.MIN_H, `{name} tall enough to tap / read`)
								table.insert(list, { name, r })
							end
							for i = 1, #list do
								for j = i + 1, #list do
									t.ok(not overlaps(list[i][2], list[j][2]), `{list[i][1]} vs {list[j][1]}`)
								end
							end
							t.ok(
								l.level.w >= TopBarLayout.LEVEL_W.min
									and l.vitals.w >= TopBarLayout.VITALS_W.min,
								"bars readable"
							)
							t.eq(l.compact, w < TopBarLayout.WIDE_W)
							if l.compact then
								-- Phones: short, low bars leave the strip for controls.
								t.ok(l.level.w <= TopBarLayout.COMPACT_LEVEL_MAX, "short EXP bar")
								t.ok(l.vitals.w <= TopBarLayout.COMPACT_VITALS_MAX, "short HP bar")
								t.ok(l.level.h <= TopBarLayout.COMPACT_H, "low bars")
							end
						end
					)
				end
			end
		end
	end)
end
