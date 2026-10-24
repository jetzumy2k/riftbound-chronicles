--!strict
--[[
	HudSlots — the HUD pieces a player may move (creator request
	2026-10-24, PLAN.md D-74) and the rules for where a moved piece goes.
	Pure module (tests: tests/pure/specs/hud_slots.spec.luau).

	A moved piece is saved as the screen fraction {X, Y} (0..1) of its
	centre inside the safe area, so a layout made on one screen fits any
	other. When drawn, the piece is kept fully on screen.

	Saved in the profile (Settings.HudLayout) through `SetHudLayout`, which
	accepts only these ids and numbers in 0..1.
]]

export type Saved = { [string]: { X: number, Y: number } }

local HudSlots = {}

HudSlots.IDS = table.freeze({
	"Level",
	"Vitals",
	"Zone",
	"Party",
	"Skills",
	"Bag",
	"Potion",
	"Quest",
	"Edit",
})

HudSlots.LABELS = table.freeze({
	Level = "Level & EXP",
	Vitals = "HP & Focus",
	Zone = "Zone badge",
	Party = "Party",
	Skills = "Skills",
	Bag = "Bag",
	Potion = "Potion",
	Quest = "Quest",
	Edit = "Edit HUD",
} :: { [string]: string })

local MARGIN = 4

--[[
	The centre fraction to draw a piece `w` x `h` px whose saved centre is
	(x, y), on a `screenW` x `screenH` safe area: clamped so the whole piece
	stays on screen (a piece wider than the screen is centred).
]]
function HudSlots.clampCenter(
	x: number,
	y: number,
	w: number,
	h: number,
	screenW: number,
	screenH: number
): (number, number)
	local function axis(value: number, size: number, screen: number): number
		if screen <= 0 then
			return 0.5
		end
		local half = (size / 2 + MARGIN) / screen
		if half >= 0.5 then
			return 0.5
		end
		return math.clamp(value, half, 1 - half)
	end
	return axis(x, w, screenW), axis(y, h, screenH)
end

-- Keeps only known ids with finite numbers in 0..1.
function HudSlots.sanitize(saved: any): Saved
	local out: Saved = {}
	if type(saved) ~= "table" then
		return out
	end
	for _, id in HudSlots.IDS do
		local entry = saved[id]
		if type(entry) == "table" then
			local x, y = entry.X, entry.Y
			if
				type(x) == "number"
				and type(y) == "number"
				and x == x
				and y == y
				and x >= 0
				and x <= 1
				and y >= 0
				and y <= 1
			then
				out[id] = { X = x, Y = y }
			end
		end
	end
	return out
end

return table.freeze(HudSlots)
