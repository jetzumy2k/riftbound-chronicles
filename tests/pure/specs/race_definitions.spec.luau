local load = require("../loader")
local Enums = load("src/shared/Enums")
local RaceDefinitions = load("src/shared/Definitions/RaceDefinitions")

-- CLAUDE.md §3.1 / PLAN.md PC-1: fictional factions, no real-world religious
-- instruction, worship or demonology in player-facing text.
local BANNED_WORDS = {
	"god",
	"gods",
	"satan",
	"lucifer",
	"heaven",
	"hell",
	"demon",
	"demons",
	"bible",
	"church",
	"pray",
	"prayer",
	"worship",
	"sin",
	"holy",
	"jesus",
	"allah",
	"scripture",
}

local function containsWord(text: string, word: string): boolean
	return string.find(string.lower(text), `%f[%a]{word}%f[%A]`) ~= nil
end

return function(t)
	t.it("defines exactly the two enum races, in display order", function()
		t.eq(#RaceDefinitions.Order, #Enums.Race)
		for _, race in Enums.Race do
			local def = RaceDefinitions.get(race)
			t.ok(def ~= nil, race)
			t.eq(def.id, race)
			t.ok(table.find(RaceDefinitions.Order, race) ~= nil, race)
		end
		t.eq(RaceDefinitions.get("Human"), nil)
	end)

	t.it("player-facing text avoids real-world religious terms", function()
		for _, race in RaceDefinitions.Order do
			local def = RaceDefinitions.get(race)
			local texts = { def.displayName, def.tagline, def.description, def.realmName, def.enterLabel }
			for _, trait in def.traits do
				table.insert(texts, trait)
			end
			for _, text in texts do
				for _, word in BANNED_WORDS do
					t.ok(not containsWord(text, word), `{race}: '{text}' contains '{word}'`)
				end
			end
		end
	end)

	t.it("the word check matches whole words only", function()
		t.ok(containsWord("Go to hell", "hell"))
		t.ok(not containsWord("a sea shell", "hell"))
	end)

	t.it("cards have a glyph, 1-4 traits and an enter label", function()
		for _, race in RaceDefinitions.Order do
			local def = RaceDefinitions.get(race)
			t.ok(#def.glyph > 0, race)
			t.ok(#def.traits >= 1 and #def.traits <= 4, race)
			t.ok(#def.enterLabel > 0 and #def.enterLabel <= 24, race)
		end
	end)

	t.it("colours are valid RGB triples", function()
		for _, race in RaceDefinitions.Order do
			local def = RaceDefinitions.get(race)
			for _, colorField in { def.uiColor, def.uiAccent } do
				t.eq(#colorField, 3)
				for _, channel in colorField do
					t.ok(channel >= 0 and channel <= 255 and channel % 1 == 0)
				end
			end
		end
	end)
end
