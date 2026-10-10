--!strict
--[[
	RaceDefinitions (CLAUDE.md §3.1)
	Angels and Devils are fictional fantasy factions. Text here must stay clear
	of real-world religious instruction, worship or demonology (enforced by
	tests/pure/specs/race_definitions.spec.luau).

	Display-safe data only. Pure module.
]]

export type RaceDefinition = {
	id: string,
	displayName: string,
	tagline: string,
	description: string,
	realmName: string,
	-- Single glyph shown in the race emblem.
	glyph: string,
	-- Short trait chips on the selection card.
	traits: { string },
	enterLabel: string,
	-- Colours as {r, g, b} 0..255 (Color3 is not available to pure modules).
	uiColor: { number },
	uiAccent: { number },
}

local RaceDefinitions = {}

RaceDefinitions.Angel = table.freeze({
	id = "Angel",
	displayName = "Angels",
	tagline = "Light, Order, and Hope",
	description = "Radiant guardians whose citadels drift above the clouds. Swift, bright and proud.",
	realmName = "The Skyreach",
	glyph = "☀",
	traits = table.freeze({ "Swift", "Radiant", "Aerial" }),
	enterLabel = "ENTER THE SKYREACH",
	uiColor = table.freeze({ 236, 232, 220 }),
	uiAccent = table.freeze({ 255, 206, 110 }),
} :: RaceDefinition)

RaceDefinitions.Devil = table.freeze({
	id = "Devil",
	displayName = "Devils",
	tagline = "Power, Freedom, and Ambition",
	description = "Fierce wardens of obsidian halls forged in volcanic light. Bold, steadfast and fiery.",
	realmName = "The Emberdeep",
	glyph = "✶",
	traits = table.freeze({ "Bold", "Fiery", "Steadfast" }),
	enterLabel = "ENTER THE EMBERDEEP",
	uiColor = table.freeze({ 52, 40, 48 }),
	uiAccent = table.freeze({ 255, 112, 64 }),
} :: RaceDefinition)

-- Display order on the selection screen.
RaceDefinitions.Order = table.freeze({ "Angel", "Devil" })

function RaceDefinitions.get(race: string): RaceDefinition?
	if race == "Angel" or race == "Devil" then
		return (RaceDefinitions :: any)[race]
	end
	return nil
end

return table.freeze(RaceDefinitions)
