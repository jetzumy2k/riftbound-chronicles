--!strict
--[[
	FacePresets — the only appearance choices a player can make
	(CLAUDE.md Phase 3: "face customization using controlled presets").

	The client sends a preset *id*; the server looks it up here. No client-sent
	asset id, colour or text ever reaches a character (SECURITY_MODEL.md T-30).

	Each preset defines the race look: an accent colour for the race cosmetics
	(halo / horns) and an optional face texture. `faceTexture = nil` keeps the
	player's own avatar face. The art pass (Phase 15/16) fills face textures
	with reviewed asset ids; only `rbxasset://` / `rbxassetid://` ids are allowed.

	Ids are stable: never renumber or reuse an id (they are saved in profiles).

	Display-safe data only. Pure module.
]]

export type Palette = {
	cloth: { number },
	metal: { number },
	glow: { number },
}

export type FacePreset = {
	id: number,
	race: string,
	name: string,
	-- {r, g, b} 0..255 — swatch colour in the UI (= glow).
	accent: { number },
	palette: Palette,
	faceTexture: string?,
}

local FacePresets = {}

local function preset(id: number, race: string, name: string, palette: Palette): FacePreset
	return table.freeze({
		id = id,
		race = race,
		name = name,
		accent = palette.glow,
		palette = table.freeze(palette),
	}) :: FacePreset
end

FacePresets.List = table.freeze({
	preset(
		1,
		"Angel",
		"Dawnlight",
		{ cloth = { 246, 240, 226 }, metal = { 226, 182, 92 }, glow = { 255, 214, 120 } }
	),
	preset(
		2,
		"Angel",
		"Moonsilver",
		{ cloth = { 228, 236, 248 }, metal = { 186, 196, 212 }, glow = { 190, 226, 255 } }
	),
	preset(
		3,
		"Angel",
		"Rosegleam",
		{ cloth = { 252, 232, 236 }, metal = { 214, 150, 134 }, glow = { 255, 172, 192 } }
	),
	preset(
		4,
		"Angel",
		"Skyward",
		{ cloth = { 214, 232, 250 }, metal = { 222, 196, 128 }, glow = { 120, 200, 255 } }
	),
	preset(
		5,
		"Devil",
		"Emberhorn",
		{ cloth = { 46, 36, 36 }, metal = { 150, 96, 54 }, glow = { 255, 112, 52 } }
	),
	preset(
		6,
		"Devil",
		"Obsidian",
		{ cloth = { 26, 24, 32 }, metal = { 88, 86, 104 }, glow = { 176, 150, 255 } }
	),
	preset(7, "Devil", "Crimson", { cloth = { 92, 18, 28 }, metal = { 52, 46, 50 }, glow = { 255, 60, 70 } }),
	preset(
		8,
		"Devil",
		"Violet Flame",
		{ cloth = { 52, 28, 70 }, metal = { 150, 120, 64 }, glow = { 186, 100, 255 } }
	),
})

-- Race-wide colours for outfit roles that do not vary per look.
local RACE_ROLE_COLORS: { [string]: { [string]: { number } } } = {
	Angel = {
		leather = { 196, 166, 124 },
		wing = { 250, 250, 255 },
		horn = { 250, 250, 255 },
		blade = { 236, 241, 250 },
		wood = { 238, 226, 196 },
	},
	Devil = {
		leather = { 44, 34, 32 },
		wing = { 40, 30, 38 },
		horn = { 30, 26, 28 },
		blade = { 46, 30, 34 },
		wood = { 34, 24, 26 },
	},
}

--[[
	Colour for an outfit part role ("cloth" | "metal" | "glow" | "leather" |
	"wing" | "horn" | "blade" | "wood"). Shared so the server outfit and the client preview agree.
]]
function FacePresets.roleColor(entry: FacePreset, role: string): { number }
	local palette = entry.palette :: any
	if palette[role] then
		return palette[role]
	end
	local raceColors = RACE_ROLE_COLORS[entry.race]
	return (raceColors and raceColors[role]) or entry.palette.cloth
end

local byId: { [number]: FacePreset } = {}
local byRace: { [string]: { FacePreset } } = {}
for _, entry in FacePresets.List do
	byId[entry.id] = entry
	local list = byRace[entry.race]
	if list == nil then
		list = {}
		byRace[entry.race] = list
	end
	table.insert(list, entry)
end

function FacePresets.get(id: any): FacePreset?
	if type(id) ~= "number" then
		return nil
	end
	return byId[id]
end

function FacePresets.forRace(race: string): { FacePreset }
	return byRace[race] or {}
end

function FacePresets.isValidFor(id: any, race: any): boolean
	local entry = FacePresets.get(id)
	return entry ~= nil and entry.race == race
end

-- First preset of a race (used when repairing a profile).
function FacePresets.defaultFor(race: string): number
	local list = byRace[race]
	assert(list and list[1], `no presets for race '{race}'`)
	return list[1].id
end

function FacePresets.maxId(): number
	local max = 0
	for id in byId do
		max = math.max(max, id)
	end
	return max
end

return table.freeze(FacePresets)
