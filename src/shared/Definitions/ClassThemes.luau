--!strict
--[[
	ClassThemes — each class's colours and each skill branch's role label for
	the skill tree screen (D-103 stage A, creator art direction 2026-10-26).

	  Warrior  crimson, black, gold, metallic steel
	  Archer   emerald, teal, silver
	  Mage     violet, blue, cyan
	  Healer   white, gold, celestial blue

	Colours are { r, g, b } (0-255) so this stays a pure, testable module;
	the client turns them into Color3 (UI/ClassTheme). Display only.
]]

export type RGB = { number }
export type Theme = {
	primary: RGB, -- main class colour (frames, learned links)
	secondary: RGB, -- second colour (gradients)
	accent: RGB, -- highlights, ultimate glow
	dark: RGB, -- panel tint
	text: RGB, -- titles
}

local ClassThemes = {}

ClassThemes.THEMES = table.freeze({
	Warrior = table.freeze({
		primary = { 196, 36, 48 },
		secondary = { 150, 156, 170 },
		accent = { 255, 196, 72 },
		dark = { 26, 8, 12 },
		text = { 255, 214, 140 },
	}),
	Archer = table.freeze({
		primary = { 34, 178, 110 },
		secondary = { 40, 190, 190 },
		accent = { 210, 236, 230 },
		dark = { 6, 24, 20 },
		text = { 190, 255, 220 },
	}),
	Mage = table.freeze({
		primary = { 140, 70, 230 },
		secondary = { 60, 110, 240 },
		accent = { 90, 230, 255 },
		dark = { 16, 10, 34 },
		text = { 205, 190, 255 },
	}),
	Healer = table.freeze({
		primary = { 245, 240, 225 },
		secondary = { 110, 180, 255 },
		accent = { 255, 210, 90 },
		dark = { 12, 18, 34 },
		text = { 255, 236, 180 },
	}),
} :: { [string]: Theme })

-- Fallback before a class is chosen.
ClassThemes.DEFAULT = table.freeze({
	primary = { 214, 168, 72 },
	secondary = { 120, 110, 140 },
	accent = { 255, 214, 110 },
	dark = { 14, 12, 22 },
	text = { 255, 220, 140 },
} :: Theme)

-- What each branch is for, shown under its name (builds at a glance).
ClassThemes.ROLES = table.freeze({
	-- Warrior: Blademaster + Warlord = attack build, Ironclad + Vanguard = defense build.
	Blademaster = "ATTACK BUILD",
	Ironclad = "DEFENSE BUILD",
	Warlord = "ATTACK · CONTROL",
	Vanguard = "DEFENSE · PARTY",
	Light = "HEALING",
	Sanctity = "PROTECTION",
	Judgment = "HOLY DAMAGE",
	Seraph = "BATTLE PRIEST",
	Marksman = "PRECISION",
	Venom = "POISON",
	Ranger = "AREA · CONTROL",
	Windrunner = "MOBILITY",
	Pyromancy = "FIRE",
	Cryomancy = "ICE · CONTROL",
	Arcanist = "ARCANE · BARRIER",
	Stormcaller = "STORM",
} :: { [string]: string })

function ClassThemes.forJob(job: string?): Theme
	return (ClassThemes.THEMES :: any)[job or ""] or ClassThemes.DEFAULT
end

function ClassThemes.role(branchId: string): string?
	return (ClassThemes.ROLES :: any)[branchId]
end

return table.freeze(ClassThemes)
