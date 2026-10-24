--[[
	Story quests (Phase 11, D-73): definitions, prerequisites, in-order
	progress, idempotent rewards, repair on rejoin, and the remote surface
	(no progress remote, T-13).
]]

local load = require("../loader")
local QuestDefinitions = load("src/shared/Definitions/QuestDefinitions")
local QuestRules = load("src/shared/Logic/QuestRules")
local EnemyDefinitions = load("src/shared/Definitions/EnemyDefinitions")
local ItemDefinitions = load("src/shared/Definitions/ItemDefinitions")
local DungeonDefinitions = load("src/shared/Definitions/DungeonDefinitions")
local WorldLayout = load("src/shared/Definitions/WorldLayout")
local XPTable = load("src/shared/Logic/XPTable")
local RewardClaims = load("src/server/Persistence/RewardClaims")
local Schema = load("src/shared/Logic/Schema")
local Registry = load("src/shared/Net/Registry")(Schema)

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in value do
		out[k] = deepCopy(v)
	end
	return out
end

-- Completes every quest before `id` in a fresh state.
local function stateBefore(id: string): any
	local state = {}
	for _, quest in QuestDefinitions.List do
		if quest.id == id then
			break
		end
		state[quest.id] =
			{ Status = "Completed", Objectives = {}, Found = {}, AcceptedAt = 0, CompletedAt = 0 }
	end
	return state
end

return function(t)
	t.describe("QuestDefinitions", function()
		t.it("the 11 story quests of CLAUDE.md §17, in order", function()
			local names = {
				"First Spark",
				"Into the Rift",
				"Echoes of the Other Realm",
				"The Broken Gate",
				"Two Paths, One Rift",
				"Trial of the Desert",
				"Trial of the Jungle",
				"Rival Encounter",
				"The False War",
				"Guardian of the Rift",
				"The Nullborn Gate",
			}
			t.eq(#QuestDefinitions.List, #names)
			for index, quest in QuestDefinitions.List do
				t.eq(quest.name, names[index])
			end
			t.eq(QuestDefinitions.List[#names].level, 30)
		end)

		t.it("every definition is valid (enemies, objects, rewards, flags)", function()
			local errors = QuestRules.validateDefinitions(function(id)
				return EnemyDefinitions.get(id) ~= nil
			end, function(id)
				return ItemDefinitions.stackable(id) ~= nil
			end)
			t.eq(#errors, 0, table.concat(errors, "; "))
		end)

		t.it("every quest object has a real place", function()
			local floors = DungeonDefinitions.get("RiftHollow").floors
			for id, object in QuestDefinitions.Interactables do
				local place = object.place
				if place.kind == "dungeon" then
					local floor = floors[place.floor]
					local found = false
					for _, room in (floor and floor.rooms or {}) do
						found = found or room.id == place.room
					end
					t.ok(found, `{id}: room {place.room} on floor {place.floor}`)
				elseif place.kind == "gate" then
					t.ok(WorldLayout.gateFront(WorldLayout.Realms.Angel, place.gate, 1) ~= nil, `{id}: gate`)
				elseif place.kind == "warZone" then
					t.ok(WorldLayout.WarZones[place.zone] ~= nil, `{id}: zone`)
				end
			end
		end)

		t.it("fills realm names into dialogue", function()
			t.eq(
				QuestDefinitions.fill("{giver} vs {rival}", "Angel"),
				"Seraph Commander Aurelia vs the Devils"
			)
			t.eq(QuestDefinitions.fill("{rival}, {player}", "Devil", "Kai"), "the Angels, Kai")
		end)
	end)

	t.describe("QuestRules", function()
		t.it("prerequisites and level gate accepting; never twice", function()
			local state = {}
			t.ok(QuestRules.canAccept(state, "FirstSpark", 0))
			t.eq(select(2, QuestRules.canAccept(state, "IntoTheRift", 5)), "prerequisite")
			t.eq(select(2, QuestRules.canAccept(state, "Nope", 5)), "unknown")
			state = stateBefore("TheNullbornGate")
			t.eq(select(2, QuestRules.canAccept(state, "TheNullbornGate", 29)), "level")
			t.ok(QuestRules.canAccept(state, "TheNullbornGate", 30))
			state.TheNullbornGate = QuestRules.newProgress(QuestDefinitions.get("TheNullbornGate"), 0)
			t.eq(select(2, QuestRules.canAccept(state, "TheNullbornGate", 30)), "accepted")
			-- The False War needs all three trials.
			state = stateBefore("TrialOfTheDesert")
			state.TrialOfTheDesert = { Status = "Completed", Objectives = {}, Found = {}, AcceptedAt = 0 }
			t.eq(select(2, QuestRules.canAccept(state, "TheFalseWar", 30)), "prerequisite")
		end)

		t.it("steps count in order; the right events only", function()
			local quest = QuestDefinitions.get("FirstSpark")
			local p = QuestRules.newProgress(quest, 0)
			-- Sprites before reaching the yard don't count.
			t.ok(
				not QuestRules.advance(quest, p, { type = "Kill", enemy = "RiftSprite", owner = "training" })
			)
			t.ok(QuestRules.advance(quest, p, { type = "Visit", objective = "train" }))
			t.ok(not QuestRules.advance(quest, p, { type = "Kill", enemy = "RiftWolf", owner = "training" }))
			t.ok(not QuestRules.advance(quest, p, { type = "Kill", enemy = "RiftSprite", owner = "dungeon" }))
			for _ = 1, 4 do
				t.ok(
					QuestRules.advance(quest, p, { type = "Kill", enemy = "RiftSprite", owner = "training" })
				)
			end
			t.eq(p.Status, "Active")
			t.ok(QuestRules.advance(quest, p, { type = "Kill", enemy = "RiftSprite", owner = "training" }))
			t.eq(p.Status, "ReadyToTurnIn")
			t.eq(p.Objectives.sprites, 5)
			-- Nothing more once ready.
			t.ok(
				not QuestRules.advance(quest, p, { type = "Kill", enemy = "RiftSprite", owner = "training" })
			)
			t.eq(p.Objectives.sprites, 5)
		end)

		t.it("each quest object counts once", function()
			local quest = QuestDefinitions.get("EchoesOfTheOtherRealm")
			local p = QuestRules.newProgress(quest, 0)
			t.ok(QuestRules.advance(quest, p, { type = "Interact", target = "FragmentNave" }))
			t.ok(not QuestRules.advance(quest, p, { type = "Interact", target = "FragmentNave" }))
			t.ok(not QuestRules.advance(quest, p, { type = "Interact", target = "ClueOasis" }))
			t.ok(QuestRules.advance(quest, p, { type = "Interact", target = "FragmentChapel" }))
			t.ok(QuestRules.advance(quest, p, { type = "Interact", target = "FragmentCloister" }))
			t.eq(p.Status, "ReadyToTurnIn")
		end)

		t.it("trials: enter, hunt, then return through the portal", function()
			local quest = QuestDefinitions.get("TrialOfTheDesert")
			local p = QuestRules.newProgress(quest, 0)
			t.ok(not QuestRules.advance(quest, p, { type = "ReturnSafely", zone = "DesertRift" }))
			t.ok(not QuestRules.advance(quest, p, { type = "EnterZone", zone = "JungleRift" }))
			t.ok(QuestRules.advance(quest, p, { type = "EnterZone", zone = "DesertRift" }))
			for _ = 1, 6 do
				t.ok(QuestRules.advance(quest, p, { type = "Kill", enemy = "DuneStalker" }))
			end
			t.ok(not QuestRules.advance(quest, p, { type = "ReturnSafely", zone = "JungleRift" }))
			t.ok(QuestRules.advance(quest, p, { type = "ReturnSafely", zone = "DesertRift" }))
			t.eq(p.Status, "ReadyToTurnIn")
		end)

		t.it("rewards are claimed once (Q:<id>)", function()
			local data = { ClaimedRewardIds = {} }
			local grants = 0
			local first = RewardClaims.claim(data, "Q:FirstSpark", 0, function()
				grants += 1
			end)
			local second = RewardClaims.claim(data, "Q:FirstSpark", 1, function()
				grants += 1
			end)
			t.eq(first, "granted")
			t.eq(second, "already")
			t.eq(grants, 1)
			t.eq(RewardClaims.RETENTION_SECONDS.Q, false)
		end)

		t.it("rejoin mid-quest: saved progress survives repair; bad data is fixed", function()
			local quest = QuestDefinitions.get("IntoTheRift")
			local state = stateBefore("IntoTheRift")
			local p = QuestRules.newProgress(quest, 5)
			QuestRules.advance(quest, p, { type = "EnterZone", zone = "Dungeon" })
			QuestRules.advance(quest, p, { type = "Kill", enemy = "RiftWolf" })
			state.IntoTheRift = p
			local saved = deepCopy(state)
			t.eq(#QuestRules.repair(saved), 0)
			t.eq(saved.IntoTheRift.Objectives.halls, 1)
			t.eq(saved.IntoTheRift.Status, "Active")
			-- Tampered or stale saves.
			saved.IntoTheRift.Objectives.halls = 999
			saved.IntoTheRift.Objectives.guardian = 1
			saved.Ghost = { Status = "Active", Objectives = {} }
			saved.EchoesOfTheOtherRealm = { Status = "Weird" }
			local notes = QuestRules.repair(saved)
			t.ok(#notes >= 2)
			t.eq(saved.Ghost, nil)
			t.eq(saved.EchoesOfTheOtherRealm, nil)
			t.eq(saved.IntoTheRift.Objectives.halls, 8)
			t.eq(saved.IntoTheRift.Status, "ReadyToTurnIn")
		end)

		t.it("EXP and rarity rolls", function()
			t.eq(QuestRules.xpFor(QuestDefinitions.get("FirstSpark")), XPTable.toNext(0))
			t.eq(QuestRules.xpFor(QuestDefinitions.get("TheNullbornGate")), 0)
			local counts = { Mythical = 0, Legendary = 0 }
			local n = 100000
			for i = 1, n do
				local r = QuestRules.rollRarity({ Mythical = 20, Legendary = 80 }, (i - 0.5) / n)
				counts[r] += 1
			end
			t.near(counts.Mythical / n, 0.2, 0.005)
			t.eq(QuestRules.rollRarity({ Rare = 100 }, 0.999), "Rare")
		end)

		t.it("quest unlocks: gated needs the flag, ungated is open", function()
			t.ok(not QuestRules.unlocked({ StoryFlags = {} }, "PortalAccess", true))
			t.ok(QuestRules.unlocked({ StoryFlags = { PortalAccess = true } }, "PortalAccess", true))
			t.ok(QuestRules.unlocked({ StoryFlags = {} }, "PortalAccess", false))
		end)

		t.it("no remote can forge quest progress (T-13)", function()
			for name, spec in Registry do
				if spec.direction == "ClientToServer" then
					local lower = string.lower(name)
					t.ok(
						not (
								string.find(lower, "progress")
								or string.find(lower, "objective")
								or string.find(lower, "questcomplete")
							),
						`{name} looks like a progress remote`
					)
				end
			end
			for _, name in { "QuestAccept", "QuestTurnIn" } do
				t.eq(#Registry[name].args, 1, `{name} takes only a quest id`)
			end
		end)
	end)
end
