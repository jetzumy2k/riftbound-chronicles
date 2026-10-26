local load = require("../loader")
local AnimeArchetypes = load("src/shared/Definitions/AnimeArchetypes")
local Enums = load("src/shared/Enums")

-- PLAN.md PC-1: fictional factions; titles stay clear of real-world religion.
local BANNED_WORDS = { "god", "satan", "lucifer", "heaven", "hell", "demon", "holy", "church", "worship" }

return function(t)
	t.describe("AnimeArchetypes", function()
		t.it("every archetype has a full palette of valid colours", function()
			for _, archetype in AnimeArchetypes.LIST do
				for _, role in AnimeArchetypes.ROLES do
					local rgb = archetype.palette[role]
					t.ok(rgb ~= nil, `{archetype.id} has {role}`)
					if rgb then
						t.eq(#rgb, 3)
						for _, channel in rgb do
							t.ok(
								channel >= 0 and channel <= 255 and channel % 1 == 0,
								`{archetype.id}.{role} in 0..255`
							)
						end
					end
				end
			end
		end)
		t.it("ids are unique and realms / jobs are real", function()
			local seen = {}
			local races, jobs = {}, {}
			for _, race in Enums.Race do
				races[race] = true
			end
			for _, job in Enums.Job do
				jobs[job] = true
			end
			for _, archetype in AnimeArchetypes.LIST do
				t.ok(not seen[archetype.id], `{archetype.id} unique`)
				seen[archetype.id] = true
				t.ok(races[archetype.race], `{archetype.id} race`)
				t.ok(archetype.job == nil or jobs[archetype.job], `{archetype.id} job`)
				t.ok(archetype.wingScale > 0 and archetype.wingScale <= 1.5, `{archetype.id} wing scale`)
				for _, word in BANNED_WORDS do
					t.ok(
						string.find(string.lower(archetype.title), `%f[%a]{word}%f[%A]`) == nil,
						`{archetype.id} title avoids "{word}"`
					)
				end
			end
		end)
		t.it("every realm has a look per job and a recruit look, each with both head styles", function()
			for _, race in Enums.Race do
				local recruit = AnimeArchetypes.forCharacter(race, nil)
				t.ok(recruit ~= nil and recruit.job == nil, `{race} recruit`)
				for _, job in Enums.Job do
					local archetype = AnimeArchetypes.forCharacter(race, job)
					t.ok(archetype ~= nil and archetype.race == race and archetype.job == job, `{race} {job}`)
				end
			end
			for _, archetype in AnimeArchetypes.LIST do
				for _, style in AnimeArchetypes.HEAD_STYLES do
					t.ok(archetype.hair[style] ~= nil, `{archetype.id} {style} hair`)
					t.ok(archetype.face[style] ~= nil, `{archetype.id} {style} face`)
				end
			end
			t.eq(AnimeArchetypes.forCharacter(nil, "Warrior"), nil)
			t.eq(AnimeArchetypes.get("AngelWarrior"), AnimeArchetypes.forCharacter("Angel", "Warrior"))
		end)
		t.it("the anime body stays inside the avatar ranges (D-80 lesson)", function()
			for name, range in AnimeArchetypes.BODY_RANGES do
				local value = AnimeArchetypes.BODY[name]
				t.ok(value ~= nil and value >= range[1] and value <= range[2], `{name} = {value}`)
			end
		end)
	end)
end
