--!strict
--[[
	AnimeArchetypes — the modern fantasy anime looks (PLAN.md D-100; the
	creator's reference: docs/screenshots-ai-to-review "Riftbound Chronicles
	Class Showcase").

	Each archetype is data only: a palette (RGB per colour role) and the
	builder style for every layer (hair and face per head style, armour,
	wings, crown, weapon, aura). The server builds the character from
	Roblox Parts on a hidden R15 rig (Appearance/Anime/CharacterFactory); no
	meshes, textures or Creator Store assets.

	Every realm has a look per job and a recruit look (no job yet: the realm
	choice preview and new characters). A palette is the realm's base
	colours with the job's own on top. Pure module, unit-tested
	(tests/pure/specs/anime_archetypes.spec.luau).
]]

export type RGB = { number }
export type Archetype = {
	id: string,
	title: string,
	race: string,
	job: string?, -- nil = the recruit look
	palette: { [string]: RGB },
	hair: { [string]: string }, -- head style (Enums.HeadStyle) -> HairBuilder style
	face: { [string]: string }, -- head style -> HeadBuilder face style
	armor: string, -- ArmorBuilder set
	wings: string?, -- WingBuilder style
	crown: string?, -- CrownBuilder style (halo / horns)
	weapon: string?, -- WeaponBuilder sword style (other weapons: classic builder)
	offHand: string?, -- off-hand drawn on the full look (previews / NPCs)
	aura: string?, -- AuraBuilder style
	wingScale: number,
}

local AnimeArchetypes = {}

-- Every palette must define these colour roles.
AnimeArchetypes.ROLES = table.freeze({
	"skin",
	"blush",
	"hair",
	"hairTip",
	"eyeWhite",
	"iris",
	"irisDeep",
	"line",
	"suit",
	"plate",
	"plateShade",
	"trim",
	"cloth",
	"gem",
	"glow",
	"feather",
	"featherTip",
	"horn",
	"blade",
	"grip",
})

AnimeArchetypes.HEAD_STYLES = table.freeze({ "Man", "Woman" })

--[[
	The anime body applied to the R15 rig (HumanoidDescription scales).
	Kept inside the avatar editor's ranges (D-80 lesson: widths far outside
	them broke the movement poses). The rig itself is hidden; the visible
	head is a large Part head sized from the torso (chibi proportions).
]]
AnimeArchetypes.BODY = table.freeze({
	Height = 0.95,
	Width = 0.9,
	Depth = 0.9,
	Head = 1,
	Proportion = 0,
	BodyType = 0,
})
-- The avatar editor's ranges the body must stay inside.
AnimeArchetypes.BODY_RANGES = table.freeze({
	Height = { 0.9, 1.05 },
	Width = { 0.7, 1 },
	Depth = { 0.7, 1 },
	Head = { 0.95, 1 },
	Proportion = { 0, 1 },
	BodyType = { 0, 1 },
})

-- Realm base colours.
local RACE: { [string]: { [string]: RGB } } = {
	Angel = {
		skin = { 255, 228, 212 },
		blush = { 255, 190, 190 },
		eyeWhite = { 255, 255, 255 },
		line = { 46, 36, 52 },
		trim = { 232, 186, 74 },
		gem = { 120, 214, 255 },
		glow = { 255, 214, 110 },
		feather = { 255, 255, 255 },
		featherTip = { 255, 236, 178 },
		horn = { 250, 246, 236 },
		blade = { 232, 238, 250 },
		grip = { 110, 74, 50 },
	},
	Devil = {
		skin = { 250, 224, 214 },
		blush = { 255, 160, 170 },
		eyeWhite = { 255, 250, 250 },
		line = { 30, 18, 26 },
		trim = { 178, 36, 48 },
		gem = { 255, 60, 60 },
		glow = { 255, 70, 50 },
		feather = { 38, 24, 32 },
		featherTip = { 255, 66, 40 },
		horn = { 34, 26, 32 },
		blade = { 70, 60, 72 },
		grip = { 52, 36, 34 },
	},
}

-- Job colours per realm (on top of the realm's).
local JOB: { [string]: { [string]: { [string]: RGB } } } = {
	Angel = {
		Warrior = {
			hair = { 228, 232, 246 },
			hairTip = { 196, 210, 240 },
			iris = { 255, 196, 72 },
			irisDeep = { 178, 104, 24 },
			suit = { 34, 40, 70 },
			plate = { 246, 246, 252 },
			plateShade = { 214, 220, 236 },
			cloth = { 52, 92, 186 },
		},
		Healer = {
			hair = { 255, 172, 202 },
			hairTip = { 255, 208, 226 },
			iris = { 240, 96, 170 },
			irisDeep = { 150, 40, 110 },
			suit = { 250, 246, 240 },
			plate = { 252, 250, 246 },
			plateShade = { 240, 226, 232 },
			cloth = { 200, 40, 62 },
			gem = { 255, 120, 180 },
			glow = { 255, 170, 210 },
		},
		Archer = {
			hair = { 122, 80, 46 },
			hairTip = { 164, 112, 62 },
			iris = { 96, 204, 112 },
			irisDeep = { 30, 110, 50 },
			suit = { 238, 236, 228 },
			plate = { 120, 84, 52 },
			plateShade = { 84, 58, 38 },
			cloth = { 46, 122, 62 },
			gem = { 120, 255, 140 },
			glow = { 150, 255, 120 },
		},
		Mage = {
			hair = { 240, 240, 250 },
			hairTip = { 204, 194, 242 },
			iris = { 172, 122, 255 },
			irisDeep = { 90, 50, 180 },
			suit = { 28, 28, 44 },
			plate = { 36, 44, 112 },
			plateShade = { 26, 32, 80 },
			cloth = { 240, 240, 250 },
			gem = { 120, 170, 255 },
			glow = { 150, 140, 255 },
		},
		Recruit = {
			hair = { 206, 164, 112 },
			hairTip = { 230, 196, 140 },
			iris = { 96, 170, 255 },
			irisDeep = { 36, 80, 170 },
			suit = { 92, 110, 150 },
			plate = { 246, 242, 232 },
			plateShade = { 220, 214, 200 },
			cloth = { 70, 110, 196 },
		},
	},
	Devil = {
		Warrior = {
			hair = { 30, 28, 34 },
			hairTip = { 80, 30, 40 },
			iris = { 255, 52, 52 },
			irisDeep = { 140, 10, 20 },
			suit = { 22, 18, 24 },
			plate = { 44, 38, 46 },
			plateShade = { 26, 22, 28 },
			cloth = { 140, 20, 30 },
		},
		Healer = {
			hair = { 128, 22, 44 },
			hairTip = { 206, 54, 84 },
			iris = { 255, 84, 124 },
			irisDeep = { 140, 20, 60 },
			suit = { 32, 20, 28 },
			plate = { 64, 26, 44 },
			plateShade = { 40, 16, 28 },
			cloth = { 150, 22, 54 },
			trim = { 204, 144, 72 },
			gem = { 255, 90, 150 },
			glow = { 255, 96, 146 },
		},
		Archer = {
			hair = { 56, 52, 58 },
			hairTip = { 120, 44, 40 },
			iris = { 255, 154, 44 },
			irisDeep = { 160, 70, 10 },
			suit = { 40, 30, 30 },
			plate = { 66, 44, 38 },
			plateShade = { 42, 28, 24 },
			cloth = { 92, 30, 30 },
			trim = { 196, 120, 60 },
			gem = { 255, 150, 40 },
			glow = { 255, 130, 40 },
		},
		Mage = {
			hair = { 62, 32, 92 },
			hairTip = { 152, 72, 204 },
			iris = { 196, 96, 255 },
			irisDeep = { 96, 30, 160 },
			suit = { 20, 16, 28 },
			plate = { 42, 24, 62 },
			plateShade = { 28, 16, 42 },
			cloth = { 92, 30, 132 },
			trim = { 196, 150, 220 },
			gem = { 200, 100, 255 },
			glow = { 190, 90, 255 },
		},
		Recruit = {
			hair = { 46, 30, 36 },
			hairTip = { 120, 36, 44 },
			iris = { 255, 100, 60 },
			irisDeep = { 150, 40, 20 },
			suit = { 40, 32, 36 },
			plate = { 78, 66, 70 },
			plateShade = { 54, 44, 48 },
			cloth = { 150, 30, 40 },
		},
	},
}

-- Builder styles per job (realm-specific parts come from the realm).
type JobStyle = {
	title: string,
	armor: string,
	hairMan: { [string]: string },
	hairWoman: string,
	sword: boolean,
	wingScale: number,
}
local STYLE: { [string]: JobStyle } = {
	Warrior = {
		title = "Warrior",
		armor = "Plate",
		hairMan = { Angel = "HeroSpikes", Devil = "WildSpikes" },
		hairWoman = "LongFlow",
		sword = true,
		wingScale = 1.1,
	},
	Healer = {
		title = "Healer",
		armor = "Robe",
		hairMan = { Angel = "SoftFluff", Devil = "SoftFluff" },
		hairWoman = "LongFlow",
		sword = false,
		wingScale = 1.0,
	},
	Archer = {
		title = "Archer",
		armor = "Ranger",
		hairMan = { Angel = "Tousled", Devil = "Tousled" },
		hairWoman = "LongFlow",
		sword = false,
		wingScale = 0.95,
	},
	Mage = {
		title = "Mage",
		armor = "Coat",
		hairMan = { Angel = "SoftFluff", Devil = "WildSpikes" },
		hairWoman = "LongFlow",
		sword = false,
		wingScale = 1.0,
	},
	Recruit = {
		title = "Recruit",
		armor = "Tunic",
		hairMan = { Angel = "Tousled", Devil = "Tousled" },
		hairWoman = "LongFlow",
		sword = false,
		wingScale = 0.85,
	},
}

local REALM_TITLE = { Angel = "Divine Angel", Devil = "Infernal Devil" }
local REALM_PARTS = {
	Angel = {
		wings = "Feather",
		crown = "Halo",
		sword = "DivineSword",
		aura = "Radiant",
		faceMan = "Valiant",
		faceWoman = "Gentle",
	},
	Devil = {
		wings = "Bat",
		crown = "Horns",
		sword = "InfernalSword",
		aura = "Infernal",
		faceMan = "Fierce",
		faceWoman = "Sly",
	},
}

local LIST: { Archetype } = {}
local BY_ID: { [string]: Archetype } = {}

for _, race in { "Angel", "Devil" } do
	for _, job in { "Warrior", "Healer", "Archer", "Mage", "Recruit" } do
		local palette: { [string]: RGB } = table.clone(RACE[race])
		for role, rgb in JOB[race][job] do
			palette[role] = rgb
		end
		local style = STYLE[job]
		local realm = REALM_PARTS[race]
		local archetype: Archetype = {
			id = `{race}{job}`,
			title = `{REALM_TITLE[race]} {style.title}`,
			race = race,
			job = if job == "Recruit" then nil else job,
			palette = palette,
			hair = { Man = style.hairMan[race], Woman = style.hairWoman },
			face = { Man = realm.faceMan, Woman = realm.faceWoman },
			armor = style.armor,
			wings = realm.wings,
			crown = realm.crown,
			weapon = if style.sword then realm.sword else nil,
			offHand = if style.sword then "KiteShield" else nil,
			aura = if job == "Recruit" then nil else realm.aura,
			wingScale = style.wingScale,
		}
		table.insert(LIST, archetype)
		BY_ID[archetype.id] = archetype
	end
end

AnimeArchetypes.LIST = LIST

function AnimeArchetypes.get(id: string): Archetype?
	return BY_ID[id]
end

-- The archetype a character of this realm and job wears (no job = the
-- realm's recruit look), or nil for an unknown realm.
function AnimeArchetypes.forCharacter(race: string?, job: string?): Archetype?
	if race == nil then
		return nil
	end
	return BY_ID[`{race}{job or "Recruit"}`]
end

return AnimeArchetypes
