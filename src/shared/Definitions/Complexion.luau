--!strict
--[[
	Complexion — the skin tones and hair colours a player can pick for the
	anime look (PLAN.md D-101; creator review 2026-10-26: the angels' hair
	and every realm's skin read too white; defaults should be human skin and
	hair colours, and players should be able to customise both).

	A fixed allowlist: the client sends an id, never a colour (remote
	SetComplexion; profile SkinTone / HairColor). "Default" resolves to the
	realm's default (Angels: warm skin, blonde hair; Devils: tan skin,
	black hair), so a profile never stores a colour. Pure module, tested
	(tests/pure/specs/complexion.spec.luau).
]]

export type RGB = { number }
export type Skin = { id: string, name: string, rgb: RGB }
export type Hair = { id: string, name: string, rgb: RGB, tip: RGB }

local Complexion = {}

Complexion.DEFAULT = "Default"

-- Human skin tones, light to deep.
Complexion.SKINS = table.freeze({
	{ id = "Fair", name = "Fair", rgb = { 245, 212, 186 } },
	{ id = "Light", name = "Light", rgb = { 235, 190, 155 } },
	{ id = "Warm", name = "Warm", rgb = { 224, 170, 128 } },
	{ id = "Tan", name = "Tan", rgb = { 200, 144, 100 } },
	{ id = "Olive", name = "Olive", rgb = { 186, 138, 92 } },
	{ id = "Bronze", name = "Bronze", rgb = { 160, 108, 70 } },
	{ id = "Brown", name = "Brown", rgb = { 124, 82, 54 } },
	{ id = "Deep", name = "Deep", rgb = { 88, 56, 38 } },
} :: { Skin })

-- Natural hair colours first, then a few fantasy ones.
Complexion.HAIRS = table.freeze({
	{ id = "Black", name = "Black", rgb = { 28, 24, 26 }, tip = { 60, 52, 58 } },
	{ id = "DarkBrown", name = "Dark brown", rgb = { 58, 38, 28 }, tip = { 94, 64, 46 } },
	{ id = "Brown", name = "Brown", rgb = { 110, 72, 44 }, tip = { 150, 104, 64 } },
	{ id = "Chestnut", name = "Chestnut", rgb = { 140, 76, 40 }, tip = { 180, 110, 60 } },
	{ id = "Auburn", name = "Auburn", rgb = { 130, 44, 30 }, tip = { 176, 72, 48 } },
	{ id = "Ginger", name = "Ginger", rgb = { 196, 96, 44 }, tip = { 232, 140, 72 } },
	{ id = "Blonde", name = "Blonde", rgb = { 214, 170, 92 }, tip = { 240, 206, 132 } },
	{ id = "Ash", name = "Ash blonde", rgb = { 170, 158, 136 }, tip = { 204, 194, 174 } },
	{ id = "Silver", name = "Silver", rgb = { 186, 190, 202 }, tip = { 222, 224, 234 } },
	{ id = "Pink", name = "Rose pink", rgb = { 232, 136, 172 }, tip = { 248, 186, 208 } },
	{ id = "Blue", name = "Sky blue", rgb = { 70, 110, 200 }, tip = { 120, 160, 240 } },
	{ id = "Violet", name = "Violet", rgb = { 110, 70, 170 }, tip = { 160, 120, 220 } },
	{ id = "Crimson", name = "Crimson", rgb = { 150, 24, 40 }, tip = { 210, 60, 70 } },
} :: { Hair })

-- The realm defaults ("Default" in a profile).
Complexion.REALM_DEFAULTS = table.freeze({
	Angel = table.freeze({ skin = "Warm", hair = "Blonde" }),
	Devil = table.freeze({ skin = "Tan", hair = "Black" }),
})

local SKIN_BY_ID: { [string]: Skin } = {}
local HAIR_BY_ID: { [string]: Hair } = {}
local skinIds, hairIds = { Complexion.DEFAULT }, { Complexion.DEFAULT }
for _, skin in Complexion.SKINS do
	SKIN_BY_ID[skin.id] = skin
	table.insert(skinIds, skin.id)
end
for _, hair in Complexion.HAIRS do
	HAIR_BY_ID[hair.id] = hair
	table.insert(hairIds, hair.id)
end
local allIds = table.clone(skinIds)
for _, id in hairIds do
	if not table.find(allIds, id) then
		table.insert(allIds, id)
	end
end

-- Every id a profile / remote may hold ("Default" included).
Complexion.SKIN_IDS = table.freeze(skinIds)
Complexion.HAIR_IDS = table.freeze(hairIds)
Complexion.ALL_IDS = table.freeze(allIds)
Complexion.KINDS = table.freeze({ "Skin", "Hair" })

function Complexion.isValid(kind: string, id: string): boolean
	if kind == "Skin" then
		return table.find(skinIds, id) ~= nil
	elseif kind == "Hair" then
		return table.find(hairIds, id) ~= nil
	end
	return false
end

local function defaults(race: string?): { skin: string, hair: string }
	return Complexion.REALM_DEFAULTS[race or ""] or Complexion.REALM_DEFAULTS.Angel
end

-- The skin tone for a realm and a profile id ("Default" / unknown = the realm's).
function Complexion.skin(race: string?, id: string?): Skin
	return SKIN_BY_ID[id or ""] or SKIN_BY_ID[defaults(race).skin]
end

function Complexion.hair(race: string?, id: string?): Hair
	return HAIR_BY_ID[id or ""] or HAIR_BY_ID[defaults(race).hair]
end

-- The cheeks' blush: the skin tone warmed toward rose.
function Complexion.blush(skin: RGB): RGB
	local rose = { 255, 120, 130 }
	local out = {}
	for i = 1, 3 do
		out[i] = math.floor(skin[i] + (rose[i] - skin[i]) * 0.45 + 0.5)
	end
	return out
end

-- The id after `id` in the kind's list ("Default" first), wrapping;
-- `step` -1 goes back.
function Complexion.cycle(kind: string, id: string, step: number): string
	local ids = if kind == "Skin" then skinIds else hairIds
	local index = table.find(ids, id) or 1
	return ids[(index - 1 + step) % #ids + 1]
end

return Complexion
