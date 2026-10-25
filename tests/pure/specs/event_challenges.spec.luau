local load = require("../loader")
local EventChallenges = load("src/shared/Logic/EventChallenges")
local WorldLayout = load("src/shared/Definitions/WorldLayout")
local QuestDefinitions = load("src/shared/Definitions/QuestDefinitions")
local RewardClaims = load("src/server/Persistence/RewardClaims")
local EnemyDefinitions = load("src/shared/Definitions/EnemyDefinitions")

return function(t)
	t.describe("EventChallenges", function()
		t.it("chests sit inside the war zones, clear of camps and boss posts", function()
			for _, id in { "TreasureHunt", "HiddenChestHunt" } do
				local chests = EventChallenges.chests(id)
				t.eq(#chests, if id == "TreasureHunt" then 5 else 12)
				for _, chest in chests do
					local zone = WorldLayout.WarZones[chest.zone]
					t.ok(zone ~= nil, chest.zone)
					local half = zone.size / 2 - 30
					t.ok(
						math.abs(chest.x) <= half and math.abs(chest.z) <= half,
						`{chest.x},{chest.z} inside`
					)
					for race, base in zone.bases do
						local d = math.sqrt((chest.x - base.x) ^ 2 + (chest.z - base.z) ^ 2)
						t.ok(d >= base.radius + 40, `{id} chest {math.floor(d)} studs from the {race} camp`)
					end
					for _, post in zone.bosses do
						local d = math.sqrt((chest.x - post.x) ^ 2 + (chest.z - post.z) ^ 2)
						t.ok(d >= 40, `{id} chest {math.floor(d)} studs from {post.enemy}`)
					end
					t.ok(math.sqrt(chest.x ^ 2 + chest.z ^ 2) >= 80, "off the oasis")
					t.eq(chest.treasure, id == "TreasureHunt")
				end
			end
			t.eq(#EventChallenges.chests("DoubleExp"), 0)
		end)

		t.it("treasure clues name the zone, the half and the nearest lair", function()
			for _, chest in EventChallenges.chests("TreasureHunt") do
				local clue = chest.clue :: string
				t.ok(
					string.find(
						clue,
						if chest.zone == "DesertRift" then "Desert Rift" else "Jungle Rift",
						1,
						true
					) ~= nil,
					clue
				)
				t.ok(string.find(clue, "lair", 1, true) ~= nil, clue)
			end
			local clue = EventChallenges.clue("DesertRift", 300, -300)
			t.ok(string.find(clue, "Angel camp's half", 1, true) ~= nil, clue)
			t.ok(string.find(clue, "far from the oasis", 1, true) ~= nil, clue)
		end)

		t.it("contests: realm winner, ranking and ties", function()
			t.eq(EventChallenges.raceWinner({ Angel = 4, Devil = 2 }), "Angel")
			t.eq(EventChallenges.raceWinner({ Devil = 1 }), "Devil")
			t.eq(EventChallenges.raceWinner({ Angel = 3, Devil = 3 }), nil)
			t.eq(EventChallenges.raceWinner({}), nil)
			local ranked = EventChallenges.rank({ a = 3, b = 5, c = 3, d = 0 }, { a = 2, b = 9, c = 1 })
			t.eq(#ranked, 3, "zero scores left out")
			t.eq(ranked[1], "b")
			t.eq(ranked[2], "c", "a tie goes to who got there first")
			t.eq(ranked[3], "a")
		end)

		t.it("defense waves: level from the defenders, inside the training yard", function()
			t.eq(EventChallenges.waveLevel({}), 5)
			t.eq(EventChallenges.waveLevel({ 10, 20 }), 15)
			t.eq(EventChallenges.waveLevel({ 40 }), 30)
			for _, race in { "Angel", "Devil" } do
				local realm = WorldLayout.Realms[race]
				local center, size = WorldLayout.trainingYard(realm)
				local points = EventChallenges.wavePoints(race, EventChallenges.WAVE_SIZE)
				t.eq(#points, EventChallenges.WAVE_SIZE)
				for _, p in points do
					t.ok(math.abs(p[1] - center[1]) <= size[1] / 2, "x in the yard")
					t.ok(math.abs(p[3] - center[3]) <= size[3] / 2, "z in the yard")
				end
			end
			for _, enemy in EventChallenges.WAVE_CREATURES do
				t.ok(EnemyDefinitions.get(enemy) ~= nil, enemy)
			end
			t.eq(#EventChallenges.WAVE_CREATURES, EventChallenges.WAVES)
		end)

		t.it("rewards, titles and claim ids are valid", function()
			for _, key in
				{
					"TreasureChest",
					"HiddenChest",
					"RaceWinner",
					"RaceTaking",
					"Tournament1",
					"Tournament2",
					"Tournament3",
					"Defender",
					"Parade",
				}
			do
				local reward = EventChallenges.REWARDS[key]
				t.ok(reward ~= nil and reward.gold > 0, key)
				if reward and reward.title then
					t.ok(QuestDefinitions.Titles[reward.title] ~= nil, `{reward.title} is a title`)
				end
			end
			for _, title in
				{
					EventChallenges.TREASURE_TITLE,
					EventChallenges.HIDDEN_TITLE,
					EventChallenges.DEFENDER_TITLE,
					EventChallenges.TOURNAMENT_TITLE,
					EventChallenges.PARADE_TITLE,
				}
			do
				t.ok(QuestDefinitions.Titles[title] ~= nil, title)
			end
			t.ok(
				RewardClaims.isValidId(EventChallenges.claimId("TreasureHunt", 1800000000, "chest3")),
				"chest claim"
			)
			t.ok(
				RewardClaims.isValidId(EventChallenges.claimId("CosmeticParade", 1800000000, "parade")),
				"parade claim"
			)
		end)
	end)
end
