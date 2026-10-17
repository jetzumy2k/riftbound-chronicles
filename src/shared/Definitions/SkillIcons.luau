--!strict
--[[
	SkillIcons — drawn skill / branch icons (Phase 5, D-45 follow-up).

	Font glyphs such as ⛨ ⚚ ♜ ☣ don't render in Roblox's fonts (they showed
	as empty boxes), so every skill icon is drawn from simple UI shapes
	instead: no uploaded images needed. UI/SkillIcon builds the frames;
	tools/icons/render_icons.py draws the same data to a PNG sheet for review.

	Coordinates are a 100 x 100 box, y down. Shapes, drawn in order:
	  bar   centre x, y, width w, height h, rotation r (degrees, clockwise),
	        corner rounding `round` (0-50, % of the shorter side)
	  dot   centre x, y, diameter d
	  ring  centre x, y, outer diameter d, thickness t
	  arc   half of a ring: `side` Top / Bottom / Left / Right
	Colours: "a" bright fill, "m" element colour, "g" gold, "d" dark
	element shade, "bg" the icon's background (cut-outs).

	Pure data; shared so tests can check every skill has a known icon.
]]

local SkillIcons = {}

export type Color = "a" | "m" | "g" | "d" | "bg"

export type Shape = {
	kind: "bar" | "dot" | "ring" | "arc",
	x: number,
	y: number,
	w: number?,
	h: number?,
	r: number?,
	round: number?,
	d: number?,
	t: number?,
	side: ("Top" | "Bottom" | "Left" | "Right")?,
	c: Color,
}

local function bar(x: number, y: number, w: number, h: number, r: number?, c: Color?, round: number?): Shape
	return { kind = "bar", x = x, y = y, w = w, h = h, r = r or 0, c = c or "a", round = round or 0 }
end

local function dot(x: number, y: number, d: number, c: Color?): Shape
	return { kind = "dot", x = x, y = y, d = d, c = c or "a" }
end

local function ring(x: number, y: number, d: number, t: number, c: Color?): Shape
	return { kind = "ring", x = x, y = y, d = d, t = t, c = c or "a" }
end

local function arc(x: number, y: number, d: number, t: number, side: any, c: Color?): Shape
	return { kind = "arc", x = x, y = y, d = d, t = t, side = side, c = c or "a" }
end

-- A bar from (x1, y1) to (x2, y2).
local function seg(
	x1: number,
	y1: number,
	x2: number,
	y2: number,
	thick: number,
	c: Color?,
	round: number?
): Shape
	local dx, dy = x1 - x2, y1 - y2
	local length = math.sqrt(dx * dx + dy * dy)
	local r = math.deg(math.atan2(dx, -dy))
	return bar((x1 + x2) / 2, (y1 + y2) / 2, thick, length, r, c, round)
end

-- Rotates / scales / moves a list of shapes about the box centre. Arcs only
-- turn in 90 degree steps (they're clipped halves).
local SIDES = { "Top", "Right", "Bottom", "Left" }
local function place(shapes: { Shape }, rotate: number, scale: number?, dx: number?, dy: number?): { Shape }
	local s = scale or 1
	local a = math.rad(rotate)
	local cos, sin = math.cos(a), math.sin(a)
	local out = {}
	for _, shape in shapes do
		local px, py = shape.x - 50, shape.y - 50
		local copy = table.clone(shape)
		copy.x = 50 + (px * cos - py * sin) * s + (dx or 0)
		copy.y = 50 + (px * sin + py * cos) * s + (dy or 0)
		for _, key in { "w", "h", "d", "t" } do
			local value = (shape :: any)[key]
			if value then
				(copy :: any)[key] = value * s
			end
		end
		if shape.kind == "bar" then
			copy.r = (shape.r or 0) + rotate
		elseif shape.kind == "arc" then
			local steps = math.round(rotate / 90)
			assert(math.abs(rotate - steps * 90) < 0.01, "arcs turn in 90 degree steps")
			local index = table.find(SIDES, (shape :: any).side) or 1
			copy.side = SIDES[(index - 1 + steps) % 4 + 1] :: any
		end
		table.insert(out, copy)
	end
	return out
end

local function join(...: { Shape }): { Shape }
	local out = {}
	for _, list in { ... } do
		for _, shape in list do
			table.insert(out, shape)
		end
	end
	return out
end

--------------------------------------------------------------------------------
-- Motifs
--------------------------------------------------------------------------------

local SWORD = {
	bar(50, 40, 12, 50, 0, "a", 10),
	bar(50, 15, 8.5, 8.5, 45, "a"),
	bar(50, 40, 3, 44, 0, "m"),
	bar(50, 67, 36, 8, 0, "g", 50),
	bar(50, 78, 7, 16, 0, "d"),
	dot(50, 89, 11, "g"),
}

local SHIELD = {
	bar(50, 38, 56, 40, 0, "a", 18),
	bar(50, 58, 39.6, 39.6, 45, "a", 8),
	bar(50, 50, 7, 40, 0, "g"),
	bar(50, 42, 30, 7, 0, "g"),
}

local ARROW = {
	bar(50, 56, 6, 62, 0, "a"),
	bar(50, 22, 20, 20, 45, "a"),
	seg(50, 74, 40, 90, 6, "m"),
	seg(50, 74, 60, 90, 6, "m"),
	seg(50, 64, 40, 80, 6, "m"),
	seg(50, 64, 60, 80, 6, "m"),
}

local DROP = {
	dot(50, 62, 50, "a"),
	bar(50, 42, 35.4, 35.4, 45, "a"),
	dot(40, 64, 11, "m"),
}

local FLAME = {
	dot(50, 64, 54, "m"),
	bar(50, 42, 38, 38, 45, "m"),
	dot(50, 70, 30, "a"),
	bar(50, 58, 21, 21, 45, "a"),
}

local BOLT = {
	seg(68, 6, 44, 48, 12, "g"),
	seg(38, 46, 64, 54, 12, "g"),
	seg(60, 52, 34, 94, 12, "g"),
}

local RAYS = {
	bar(50, 50, 9, 88, 0, "g"),
	bar(50, 50, 9, 88, 45, "g"),
	bar(50, 50, 9, 88, 90, "g"),
	bar(50, 50, 9, 88, 135, "g"),
}

local function snowflake(): { Shape }
	local out = {
		bar(50, 50, 8, 86, 0),
		bar(50, 50, 8, 86, 60),
		bar(50, 50, 8, 86, 120),
	}
	for i = 0, 5 do
		local a = math.rad(i * 60)
		table.insert(out, bar(50 + 28 * math.sin(a), 50 - 28 * math.cos(a), 22, 6, i * 60))
	end
	table.insert(out, dot(50, 50, 16, "m"))
	return out
end

local MOTIFS: { [string]: { Shape } } = {
	sword = place(SWORD, 45, 1.12),
	swords = join(place(SWORD, 45, 1.05), place(SWORD, -45, 1.05)),
	axe = place({
		bar(50, 54, 8, 84, 0, "d"),
		bar(68, 28, 34, 46, 0, "a", 50),
		bar(56, 28, 16, 26, 0, "a"),
		bar(36, 28, 14, 12, 0, "a", 20),
		bar(50, 28, 10, 14, 0, "g"),
		dot(50, 94, 9, "g"),
	}, 30),
	hammer = place({
		bar(50, 60, 9, 64, 0, "d"),
		bar(50, 26, 50, 24, 0, "a", 15),
		bar(50, 26, 8, 26, 0, "g"),
		dot(50, 93, 10, "g"),
	}, -30),
	shield = SHIELD,
	crack = join(SHIELD, {
		seg(54, 18, 44, 40, 5, "bg"),
		seg(44, 40, 58, 58, 5, "bg"),
		seg(58, 58, 48, 82, 5, "bg"),
	}),
	tower = {
		bar(50, 60, 50, 50, 0, "a"),
		bar(30, 32, 10, 14, 0, "a"),
		bar(50, 32, 10, 14, 0, "a"),
		bar(70, 32, 10, 14, 0, "a"),
		bar(50, 72, 14, 26, 0, "d", 50),
		bar(50, 50, 6, 10, 0, "d"),
	},
	whirl = {
		ring(50, 50, 84, 6),
		ring(50, 50, 56, 6, "m"),
		ring(50, 50, 28, 6),
		dot(50, 9, 13, "g"),
		dot(86, 70, 13, "g"),
		dot(14, 70, 13, "g"),
	},
	burst = join(RAYS, { dot(50, 50, 36), dot(50, 50, 16, "m") }),
	star = {
		bar(50, 50, 14, 84, 0),
		bar(50, 50, 84, 14, 0),
		bar(50, 50, 34, 34, 45),
		dot(50, 50, 16, "g"),
	},
	banner = {
		bar(28, 52, 7, 84, 0, "d"),
		dot(28, 10, 11, "g"),
		bar(54, 34, 46, 36, 0, "a"),
		bar(54, 56, 26, 26, 45, "a"),
		bar(54, 60, 18, 18, 45, "bg"),
		dot(54, 34, 15, "g"),
	},
	roar = {
		dot(26, 50, 26),
		arc(26, 50, 54, 7, "Right"),
		arc(26, 50, 84, 7, "Right", "m"),
		arc(26, 50, 112, 7, "Right"),
	},
	quake = {
		bar(50, 84, 90, 10, 0, "d", 50),
		seg(50, 80, 50, 38, 6),
		seg(48, 76, 30, 52, 5),
		seg(52, 76, 70, 52, 5),
		dot(24, 34, 13),
		dot(76, 30, 11),
		dot(50, 18, 12),
	},
	speed = {
		bar(48, 30, 52, 8, 0, "a", 50),
		bar(40, 50, 64, 8, 0, "m", 50),
		bar(48, 70, 52, 8, 0, "a", 50),
		seg(70, 28, 88, 50, 9, "g", 50),
		seg(88, 50, 70, 72, 9, "g", 50),
	},
	chain = {
		ring(26, 66, 34, 7),
		ring(50, 50, 34, 7, "m"),
		ring(74, 34, 34, 7),
	},
	crown = {
		bar(50, 64, 64, 24, 0, "g"),
		bar(26, 42, 15, 15, 45, "g"),
		bar(50, 36, 18, 18, 45, "g"),
		bar(74, 42, 15, 15, 45, "g"),
		bar(50, 80, 64, 6, 0, "d"),
		dot(50, 64, 11, "m"),
		dot(32, 64, 8, "a"),
		dot(68, 64, 8, "a"),
	},
	heart = {
		dot(36, 40, 36),
		dot(64, 40, 36),
		bar(50, 56, 36, 36, 45),
		dot(36, 36, 9, "m"),
	},
	cross = {
		bar(50, 50, 26, 76, 0, "a", 18),
		bar(50, 50, 76, 26, 0, "a", 18),
		bar(50, 50, 9, 54, 0, "m"),
		bar(50, 50, 54, 9, 0, "m"),
	},
	drop = DROP,
	spring = join({ ring(50, 54, 92, 6, "m") }, place(DROP, 0, 0.8, 0, 4)),
	sun = join(RAYS, { dot(50, 50, 44), dot(50, 50, 24, "g") }),
	halo = {
		ring(50, 24, 50, 7, "g"),
		dot(50, 54, 22),
		bar(50, 82, 40, 28, 0, "a", 45),
	},
	wings = {
		seg(44, 46, 10, 20, 11, "a", 50),
		seg(44, 52, 8, 40, 11, "a", 50),
		seg(44, 58, 12, 62, 11, "a", 50),
		seg(56, 46, 90, 20, 11, "a", 50),
		seg(56, 52, 92, 40, 11, "a", 50),
		seg(56, 58, 88, 62, 11, "a", 50),
		dot(50, 52, 18, "g"),
	},
	feather = place({
		bar(50, 52, 5, 86, 0, "d"),
		bar(50, 42, 28, 64, 0, "a", 50),
		bar(50, 42, 3, 58, 0, "m"),
	}, 35),
	arrow = place(ARROW, 45, 1.1),
	arrows = join(
		place(ARROW, 45, 0.72, -24, 12),
		place(ARROW, 45, 0.72, -2, 0),
		place(ARROW, 45, 0.72, 20, -12)
	),
	bow = {
		arc(60, 50, 80, 7, "Left"),
		bar(60, 50, 3, 80, 0, "g"),
		bar(52, 50, 60, 5, 0, "a"),
		bar(82, 50, 14, 14, 45, "a"),
		seg(26, 50, 18, 42, 4, "m"),
		seg(26, 50, 18, 58, 4, "m"),
	},
	target = {
		ring(50, 50, 84, 7),
		ring(50, 50, 50, 7, "m"),
		dot(50, 50, 16, "g"),
		bar(50, 9, 5, 18, 0),
		bar(50, 91, 5, 18, 0),
		bar(9, 50, 18, 5, 0),
		bar(91, 50, 18, 5, 0),
	},
	eye = {
		bar(50, 50, 52, 52, 45),
		dot(50, 50, 34, "m"),
		dot(50, 50, 14, "d"),
		dot(44, 44, 7, "a"),
	},
	flask = {
		dot(50, 64, 56),
		bar(50, 30, 18, 28),
		bar(50, 16, 28, 7, 0, "a", 50),
		dot(50, 67, 42, "m"),
		dot(43, 62, 9),
		dot(57, 72, 6),
		dot(52, 54, 5),
	},
	vine = {
		seg(30, 88, 44, 62, 8, "a", 50),
		seg(44, 62, 56, 40, 8, "a", 50),
		seg(56, 40, 66, 12, 8, "a", 50),
		bar(28, 54, 14, 26, -60, "m", 50),
		bar(70, 36, 14, 26, 60, "m", 50),
		bar(40, 26, 12, 22, -50, "m", 50),
	},
	leaf = place({ bar(50, 50, 42, 76, 0, "a", 50), bar(50, 52, 4, 70, 0, "d") }, 35),
	snowflake = snowflake(),
	shard = place({
		bar(50, 50, 18, 54),
		bar(50, 23, 12.7, 12.7, 45),
		bar(50, 77, 12.7, 12.7, 45),
		bar(46, 50, 4, 50, 0, "m"),
	}, 45),
	icenova = join(snowflake(), { ring(50, 50, 98, 5, "m") }),
	flame = FLAME,
	meteor = {
		seg(14, 86, 56, 44, 12, "m", 50),
		seg(10, 66, 46, 34, 7, "m", 50),
		seg(34, 90, 66, 54, 7, "m", 50),
		dot(64, 36, 40),
		dot(70, 30, 14, "g"),
	},
	bomb = {
		dot(46, 60, 60),
		seg(62, 36, 74, 18, 6, "d"),
		dot(78, 14, 14, "g"),
		dot(78, 14, 7, "m"),
		dot(34, 50, 12, "m"),
	},
	bolt = BOLT,
	storm = join({
		dot(34, 40, 34),
		dot(56, 32, 42),
		dot(74, 44, 30),
		bar(52, 48, 62, 22, 0, "a", 50),
	}, place(BOLT, 0, 0.5, 4, 30)),
	orb = {
		ring(50, 50, 88, 5),
		dot(50, 50, 64, "m"),
		dot(40, 40, 20),
	},
	missiles = {
		seg(30, 30, 12, 48, 7, "m", 50),
		seg(64, 44, 46, 62, 7, "m", 50),
		seg(40, 72, 22, 90, 7, "m", 50),
		dot(32, 28, 20),
		dot(66, 42, 20),
		dot(42, 70, 20),
	},
	barrier = {
		dot(50, 50, 90, "m"),
		ring(50, 50, 90, 6),
		ring(50, 50, 58, 4),
		dot(36, 34, 14),
	},
	rune = {
		ring(50, 50, 88, 5),
		bar(50, 50, 46, 46, 45, "m"),
		bar(50, 50, 26, 26, 45, "bg"),
		dot(50, 50, 12),
	},
	moon = {
		dot(48, 52, 70),
		dot(64, 40, 58, "bg"),
		dot(78, 76, 10, "g"),
	},
	wave = {
		arc(30, 40, 36, 7, "Top"),
		arc(66, 40, 36, 7, "Bottom", "m"),
		arc(30, 68, 36, 7, "Top"),
		arc(66, 68, 36, 7, "Bottom", "m"),
	},
	tornado = {
		bar(50, 18, 76, 10, 0, "a", 50),
		bar(54, 36, 60, 10, 0, "m", 50),
		bar(48, 52, 46, 10, 0, "a", 50),
		bar(55, 68, 30, 10, 0, "m", 50),
		bar(50, 84, 14, 10, 0, "a", 50),
	},
	pillar = {
		bar(50, 44, 30, 88, 0),
		bar(50, 44, 10, 88, 0, "g"),
		bar(50, 90, 76, 9, 0, "m", 50),
		dot(22, 30, 9, "g"),
		dot(78, 46, 9, "g"),
	},
	hand = {
		bar(50, 64, 40, 36, 0, "a", 30),
		bar(35, 38, 9, 28, 0, "a", 50),
		bar(46, 32, 9, 36, 0, "a", 50),
		bar(57, 32, 9, 36, 0, "a", 50),
		bar(67, 40, 9, 26, 0, "a", 50),
		seg(30, 66, 18, 50, 9, "a", 50),
		dot(50, 12, 12, "g"),
	},
	dome = {
		arc(50, 70, 84, 8, "Top"),
		bar(50, 72, 92, 8, 0, "a", 50),
		bar(50, 52, 6, 22, 0, "g"),
		bar(50, 50, 18, 6, 0, "g"),
	},
	fist = {
		bar(50, 56, 52, 44, 0, "a", 25),
		bar(30, 36, 13, 16, 0, "a", 40),
		bar(44, 34, 13, 16, 0, "a", 40),
		bar(58, 34, 13, 16, 0, "a", 40),
		bar(72, 38, 13, 16, 0, "a", 40),
		bar(50, 86, 40, 12, 0, "d"),
		dot(36, 58, 8, "m"),
	},
	lock = {
		arc(50, 42, 44, 9, "Top"),
		bar(32.5, 48, 9, 14),
		bar(67.5, 48, 9, 14),
		bar(50, 68, 58, 40, 0, "a", 14),
		dot(50, 63, 12, "d"),
		bar(50, 74, 6, 14, 0, "d"),
	},
}

-- Background shade per element as {r, g, b} 0..255 (Color3 is not available
-- to pure modules; matches Effects/SkillVfx palettes).
SkillIcons.Elements = table.freeze({
	Steel = { main = { 215, 228, 255 }, dark = { 60, 72, 110 } },
	Earth = { main = { 214, 160, 92 }, dark = { 86, 58, 32 } },
	Holy = { main = { 255, 226, 140 }, dark = { 150, 104, 30 } },
	Nature = { main = { 120, 230, 110 }, dark = { 30, 92, 44 } },
	Frost = { main = { 140, 210, 255 }, dark = { 34, 80, 150 } },
	Fire = { main = { 255, 140, 50 }, dark = { 130, 34, 14 } },
	Arcane = { main = { 190, 140, 255 }, dark = { 64, 34, 140 } },
	Shadow = { main = { 200, 120, 240 }, dark = { 56, 24, 90 } },
	Wind = { main = { 150, 240, 220 }, dark = { 28, 110, 104 } },
	Storm = { main = { 150, 200, 255 }, dark = { 36, 50, 120 } },
})

SkillIcons.Motifs = table.freeze(MOTIFS)

-- Shapes of a motif (nil for an unknown name).
function SkillIcons.get(name: any): { Shape }?
	if type(name) ~= "string" then
		return nil
	end
	return MOTIFS[name]
end

return table.freeze(SkillIcons)
