--!strict
--[[
	CreatureLanguage — the visual rules every creature follows (Phase 16
	stage 6, D-88), so a player can read a creature before it attacks:

	  Element   the glow (eyes, crystals, spikes) is the creature's element:
	            Fire orange-red, Sun gold, Wild green, Tide teal, Sky pale
	            blue (storm, frost, air), Void violet (the Nullborn),
	            Shadow crimson. Every boss has one; its body takes the
	            element's tone where the myth gives no colour of its own.
	            Regular creatures wear their dungeon floor's / zone's tones.
	  Rank      Normal (no mark), Elite (⭐ after the name), Mini boss,
	            Floor boss and Boss (👑 after the name, a glowing sigil on
	            the ground under it in its element's colour: one ring for a
	            mini boss, two rings with rune marks for floor bosses and
	            Bosses, which also wear a crown of rift shards circling over
	            the head). An enraged boss's sigil turns red and spins fast.
	  Silhouette mini bosses come in three weights (light, standard,
	            heavy), and no two bosses of a place share body plan,
	            anatomy, element and weight (tested).

	Display data only. Pure module.
]]

local CreatureLanguage = {}

export type Element = "Fire" | "Sun" | "Wild" | "Tide" | "Sky" | "Void" | "Shadow"
export type Rank = "Normal" | "Elite" | "Mini" | "Floor" | "Boss"

-- body / glow {r, g, b}
export type Palette = { body: { number }, glow: { number } }

CreatureLanguage.ELEMENTS = table.freeze({
	Fire = table.freeze({ body = { 96, 56, 46 }, glow = { 255, 110, 50 } }),
	Sun = table.freeze({ body = { 176, 138, 88 }, glow = { 255, 220, 80 } }),
	Wild = table.freeze({ body = { 62, 88, 58 }, glow = { 160, 255, 110 } }),
	Tide = table.freeze({ body = { 44, 76, 90 }, glow = { 90, 225, 235 } }),
	Sky = table.freeze({ body = { 150, 166, 190 }, glow = { 150, 210, 255 } }),
	Void = table.freeze({ body = { 64, 48, 86 }, glow = { 185, 105, 255 } }),
	Shadow = table.freeze({ body = { 58, 44, 54 }, glow = { 255, 90, 150 } }),
}) :: { [Element]: Palette }

-- A boss's glow must sit within this many degrees of hue of its element's.
CreatureLanguage.HUE_TOLERANCE = 25

-- The mark after a creature's name.
local BADGE: { [Rank]: string } = { Normal = "", Elite = "⭐", Mini = "👑", Floor = "👑", Boss = "👑" }

--[[
	The ground sigil per rank (nil: none). `radius` in studs at size 1 (the
	creature's scale multiplies it), `rings` 1 or 2, `runes` marks around
	the outer ring, `crown` rift shards circling over the head.
]]
export type Sigil = { radius: number, rings: number, runes: number, crown: number }
local SIGIL: { [string]: Sigil } = {
	Mini = table.freeze({ radius = 2.2, rings = 1, runes = 0, crown = 0 }),
	Floor = table.freeze({ radius = 2.6, rings = 2, runes = 6, crown = 5 }),
	Boss = table.freeze({ radius = 2.8, rings = 2, runes = 8, crown = 6 }),
}

-- Seconds per turn of the sigil, calm and enraged.
CreatureLanguage.SIGIL_TURN = 14
CreatureLanguage.SIGIL_TURN_ENRAGED = 3
-- Enraged colour (mixed into the element's glow).
CreatureLanguage.ENRAGED = { 255, 60, 40 }

-- `enemy`: anything with `elite` and an optional boss `tier`.
function CreatureLanguage.rankOf(enemy: { elite: boolean, tier: string? }): Rank
	local tier = enemy.tier
	if tier == "Mini" then
		return "Mini"
	elseif tier == "Floor" then
		return "Floor"
	elseif tier == "Boss" then
		return "Boss"
	end
	return if enemy.elite then "Elite" else "Normal"
end

function CreatureLanguage.badge(rank: Rank): string
	return BADGE[rank]
end

-- "Name ⭐" / "Name 👑" / "Name".
function CreatureLanguage.displayName(name: string, rank: Rank): string
	local badge = BADGE[rank]
	return if badge == "" then name else `{name} {badge}`
end

-- `rank` as from rankOf (typed string: literal unions widen across modules).
function CreatureLanguage.sigil(rank: string): Sigil?
	return SIGIL[rank]
end

-- Hue of an {r, g, b} colour in degrees (0-360).
function CreatureLanguage.hue(color: { number }): number
	local r, g, b = color[1] / 255, color[2] / 255, color[3] / 255
	local high, low = math.max(r, g, b), math.min(r, g, b)
	if high == low then
		return 0
	end
	local d = high - low
	local h
	if high == r then
		h = ((g - b) / d) % 6
	elseif high == g then
		h = (b - r) / d + 2
	else
		h = (r - g) / d + 4
	end
	return (h * 60) % 360
end

-- Shortest distance between two hues, in degrees.
function CreatureLanguage.hueGap(a: number, b: number): number
	local d = math.abs(a - b) % 360
	return math.min(d, 360 - d)
end

return CreatureLanguage
