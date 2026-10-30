--[[
	Creator review 2026-10-17: the 4-floor dungeon (D-47), boss killability
	(Logic/BossBalance), war-zone creatures and bosses (D-49) and unions
	(D-48).
]]

local load = require("../loader")
local DungeonDefinitions = load("src/shared/Definitions/DungeonDefinitions")
local EnemyDefinitions = load("src/shared/Definitions/EnemyDefinitions")
local WorldLayout = load("src/shared/Definitions/WorldLayout")
local WarZoneTerrain = load("src/shared/Logic/WarZoneTerrain")
local BossBalance = load("src/shared/Logic/BossBalance")
local StatFormulas = load("src/shared/Logic/StatFormulas")
local PartyRules = load("src/shared/Logic/PartyRules")
local Defaults = load("src/server/Config/Defaults")
local Schema = load("src/shared/Logic/Schema")
local Registry = load("src/shared/Net/Registry")(Schema)

local dungeon = DungeonDefinitions.get("RiftHollow")

local function overlaps(a, b): boolean
	-- Rects {cx, cz, w, d}; touching edges don't count.
	return math.abs(a[1] - b[1]) * 2 < a[3] + b[3] - 0.01 and math.abs(a[2] - b[2]) * 2 < a[4] + b[4] - 0.01
end

local function verdicts(enemyId: string): { [number]: string }
	local enemy = EnemyDefinitions.get(enemyId)
	local hp = StatFormulas.forCreatureLevel(enemy.level).MaxHP * enemy.hpScale
	local enrage = DungeonDefinitions.boss(enemyId).enrageSeconds
	local out = {}
	for _, n in { 1, 2, 4, 8, 16 } do
		out[n] = BossBalance.verdict(BossBalance.timeToKill(hp, n, enemy.level, enemy.defenseScale), enrage)
	end
	return out
end

return function(t)
	t.describe("floors (D-47)", function()
		t.it(
			"4 floors: 3 with a landing, 7 rooms and a lair, then the Hall of Thirty and the sanctum",
			function()
				t.eq(#dungeon.floors, 4)
				for index = 1, 3 do
					local floor = dungeon.floors[index]
					local rooms, lairs = 0, 0
					for _, room in floor.rooms do
						rooms += if room.kind == "Room" then 1 else 0
						lairs += if room.kind == "Lair" then 1 else 0
					end
					t.ok(rooms >= 7, `floor {index}: {rooms} rooms`)
					t.eq(lairs, 1, `floor {index}: one lair`)
					t.eq(floor.rooms[floor.bossRoom].kind, "Lair")
					t.ok(floor.downPortal ~= nil, `floor {index}: a way down`)
				end
				local fourth = dungeon.floors[4]
				local chambers = 0
				for _, room in fourth.rooms do
					chambers += if room.kind == "Chamber" then 1 else 0
				end
				t.eq(chambers, 30)
				t.eq(fourth.rooms[fourth.bossRoom].kind, "Sanctum")
				t.eq(fourth.downPortal, nil)
			end
		)

		t.it("creature levels: 10 levels per floor, floor bosses at 10 / 20 / 30", function()
			local expected = { { 1, 10, "Cerberus" }, { 11, 20, "Chimera" }, { 21, 30, "Basilisk" } }
			for index, want in expected do
				local floor = dungeon.floors[index]
				t.eq(floor.levels[1], want[1])
				t.eq(floor.levels[2], want[2])
				for _, room in floor.rooms do
					for _, camp in room.camps do
						local level = camp.level or EnemyDefinitions.get(camp.enemy).level
						t.ok(level >= want[1] and level <= want[2], `{room.id}: {camp.enemy} level {level}`)
					end
				end
				local boss = floor.rooms[floor.bossRoom].camps[1]
				t.eq(boss.enemy, want[3])
				t.eq(boss.class, "FloorBoss")
				t.eq(EnemyDefinitions.get(want[3]).level, want[2])
			end
		end)

		t.it(
			"floor 4: 30 different mini bosses (levels 31-40), each alone in its chamber, and Typhon (40)",
			function()
				local seen = {}
				for _, room in dungeon.floors[4].rooms do
					if room.kind == "Chamber" then
						t.eq(#room.camps, 1)
						local camp = room.camps[1]
						t.eq(camp.class, "MiniBoss")
						t.ok(not seen[camp.enemy], `{camp.enemy} appears once`)
						seen[camp.enemy] = true
						local enemy = EnemyDefinitions.get(camp.enemy)
						t.ok(enemy.level >= 31 and enemy.level <= 40, camp.enemy)
						t.eq(enemy.tier, "Mini")
					elseif room.kind == "Sanctum" then
						t.eq(room.camps[1].enemy, "Typhon")
						t.eq(room.camps[1].class, "Boss")
					else
						t.eq(#room.camps, 0, `{room.id} is empty`)
					end
				end
				t.eq(EnemyDefinitions.get("Typhon").level, 40)
			end
		)

		t.it("rooms and passages never overlap; every door opens onto a passage", function()
			for _, floor in dungeon.floors do
				local rects = {}
				for _, room in floor.rooms do
					-- Walls are 3 studs thick around each room.
					table.insert(
						rects,
						{ room.center[1], room.center[2], room.size[1] + 6, room.size[3] + 6, room.id }
					)
				end
				for i = 1, #rects do
					for j = i + 1, #rects do
						t.ok(
							not overlaps(rects[i], rects[j]),
							`floor {floor.index}: {rects[i][5]} / {rects[j][5]}`
						)
					end
				end
				for _, room in floor.rooms do
					for _, door in room.doors do
						local cx, cz = room.center[1], room.center[2]
						local w, d = room.size[1], room.size[3]
						local x, z
						if door.side == "N" then
							x, z = cx + door.offset, cz - d / 2 - 1.5
						elseif door.side == "S" then
							x, z = cx + door.offset, cz + d / 2 + 1.5
						elseif door.side == "E" then
							x, z = cx + w / 2 + 1.5, cz + door.offset
						else
							x, z = cx - w / 2 - 1.5, cz + door.offset
						end
						local linked = false
						for _, p in floor.passages do
							if
								math.abs(x - p.center[1]) <= p.size[1] / 2 + 3.1
								and math.abs(z - p.center[2]) <= p.size[2] / 2 + 3.1
							then
								linked = true
							end
						end
						t.ok(
							linked,
							`floor {floor.index}: {room.id} door {door.side} {door.offset} leads somewhere`
						)
					end
				end
			end
		end)

		t.it("floors fit side by side inside one dungeon slot", function()
			local last = dungeon.floors[#dungeon.floors]
			local b = DungeonDefinitions.floorBounds(last)
			t.ok(last.offsetX + b[2] + 100 < WorldLayout.DungeonSlots.spacing, "fits the slot")
			for i = 2, #dungeon.floors do
				local left = DungeonDefinitions.floorBounds(dungeon.floors[i - 1])
				local right = DungeonDefinitions.floorBounds(dungeon.floors[i])
				t.ok(
					dungeon.floors[i - 1].offsetX + left[2] + 80 < dungeon.floors[i].offsetX + right[1],
					`floors {i - 1} and {i} are apart`
				)
			end
		end)
	end)

	t.describe("open, guarded floors (creator review 2026-10-17)", function()
		t.it("no floor is sealed: the way down never checks the floor boss", function()
			local fs = require("@lune/fs")
			local source = fs.readFile("src/server/Services/DungeonService.luau")
			t.ok(string.find(source, "dungeon.sealed", 1, true) == nil, "no sealed toast")
			t.ok(string.find(source, "gatekeepers", 1, true) == nil, "no gatekeeper check")
		end)

		t.it("floors 1-3 are packed with creatures and the lairs are guarded", function()
			for index = 1, 3 do
				local floor = dungeon.floors[index]
				local creatures = 0
				for _, room in floor.rooms do
					for _, camp in room.camps do
						creatures += camp.count or 1
					end
				end
				t.ok(creatures >= 90, `floor {index}: {creatures} creatures`)
				local lair = floor.rooms[floor.bossRoom]
				local guards = 0
				for _, camp in lair.camps do
					if camp.class == "Mob" then
						guards += camp.count or 1
						t.ok(camp.level >= floor.levels[1] and camp.level <= floor.levels[2], "guard level")
					end
				end
				t.ok(guards >= 10, `floor {index}: {guards} lair guards`)
			end
		end)

		t.it("bosses carry their myth's look; every trait and body plan is known", function()
			local traits = {
				ThreeHeads = true,
				Mane = true,
				Horns = true,
				Wings = true,
				SerpentTail = true,
				Spikes = true,
				Crest = true,
			}
			local bodies =
				{ Wolf = true, Beetle = true, Golem = true, Guardian = true, Sprite = true, Serpent = true }
			for id, enemy in EnemyDefinitions.ById do
				t.ok(bodies[enemy.body], `{id} body`)
				for _, trait in enemy.traits or {} do
					t.ok(traits[trait], `{id} trait {trait}`)
				end
			end
			local function hasTrait(id: string, trait: string): boolean
				return table.find(EnemyDefinitions.get(id).traits or {}, trait) ~= nil
			end
			t.ok(hasTrait("Cerberus", "ThreeHeads"), "Cerberus has three heads")
			t.ok(hasTrait("Chimera", "Wings") and hasTrait("Chimera", "SerpentTail"), "Chimera")
			t.eq(EnemyDefinitions.get("Basilisk").body, "Serpent")
			t.ok(DungeonDefinitions.boss("Basilisk") ~= nil, "serpent bosses get abilities")
		end)
	end)

	t.describe("boss killability (BossBalance)", function()
		t.it("the model matches the live combat config", function()
			for key, value in BossBalance.COMBAT do
				t.eq(Defaults.Combat[key], value, key)
			end
		end)

		t.it("Typhon: solo impossible, duo super hard, party very hard, union hard", function()
			local v = verdicts("Typhon")
			t.eq(v[1], "Impossible")
			t.eq(v[2], "SuperHard")
			t.eq(v[4], "VeryHard")
			t.eq(v[8], "Hard")
			t.eq(v[16], "Hard")
		end)

		t.it("floor bosses: no solo kill, a duo can, a party comfortably", function()
			for _, id in { "Cerberus", "Chimera", "Basilisk" } do
				local v = verdicts(id)
				t.eq(v[1], "Impossible", id)
				t.eq(v[2], "VeryHard", id)
				t.eq(v[4], "Hard", id)
			end
		end)

		t.it("war-zone bosses get harder with level; the level-50 ones match the Dungeon Boss", function()
			for _, id in { "OasisColossus", "Leviathan" } do
				local v = verdicts(id)
				t.eq(v[1], "Impossible", id)
				t.eq(v[2], "SuperHard", id)
				t.eq(v[4], "VeryHard", id)
				t.eq(v[8], "Hard", id)
			end
			for _, id in { "Ammit", "Camazotz" } do
				t.eq(verdicts(id)[1], "Impossible", id)
				t.eq(verdicts(id)[4], "Hard", id)
			end
		end)

		t.it("mini bosses are a duo's fight", function()
			for _, spec in EnemyDefinitions.MINI_BOSSES do
				local v = verdicts(spec[1])
				t.eq(v[2], "Hard", spec[1])
			end
		end)

		t.it("a boss's basic hit is a fair share of a reference player's HP", function()
			for id, enemy in EnemyDefinitions.ById do
				if enemy.tier then
					-- D-130: gentle bosses are balanced against players of their level.
					local ref = StatFormulas.forLevel(BossBalance.referenceLevel(enemy.level, enemy.gentle))
					local share =
						BossBalance.attackScaleFor(enemy.level, enemy.attackCoefficient, 1, enemy.gentle)
					local hit = enemy.attackScale / share
					t.ok(hit > 0.1 and hit < 0.4, `{id}: hit {hit} of HP`)
					t.ok(ref.MaxHP > 0)
				end
			end
		end)
	end)

	t.describe("war zones (D-49)", function()
		t.it("many creatures at levels 25-30 and five bosses at 30-50 in each zone", function()
			for id, zone in WorldLayout.WarZones do
				local creatures = 0
				for _, camp in zone.camps do
					creatures += camp.count
					local level = camp.level or EnemyDefinitions.get(camp.enemy).level
					t.ok(level >= 25 and level <= 30, `{id} {camp.enemy} level {level}`)
				end
				t.ok(creatures >= 40, `{id}: {creatures} creatures`)
				t.eq(#zone.bosses, 5, id)
				local levels = {}
				for _, boss in zone.bosses do
					local enemy = EnemyDefinitions.get(boss.enemy)
					t.ok(enemy ~= nil and enemy.tier == "Boss", boss.enemy)
					t.ok(enemy.level >= 30 and enemy.level <= 50, boss.enemy)
					t.ok(DungeonDefinitions.boss(boss.enemy) ~= nil, `{boss.enemy} abilities`)
					levels[enemy.level] = true
				end
				t.ok(levels[30] and levels[50], `{id}: from 30 up to 50`)
			end
		end)

		t.it("bosses stand on dry, flat ground in the contested middle, far from the realm camps", function()
			for id, zone in WorldLayout.WarZones do
				for _, boss in zone.bosses do
					t.ok(math.abs(boss.z) <= 220, `{id} {boss.enemy} in the middle band`)
					for race, base in zone.bases do
						local d = math.sqrt((boss.x - base.x) ^ 2 + (boss.z - base.z) ^ 2)
						t.ok(d > base.radius + 100, `{id} {boss.enemy} clear of the {race} camp`)
					end
					for _, o in { { 0, 0 }, { 14, 0 }, { -14, 0 }, { 0, 14 }, { 0, -14 } } do
						local h, _, water = WarZoneTerrain.sample(zone, boss.x + o[1], boss.z + o[2])
						t.ok(water == nil or h > water + 1, `{id} {boss.enemy} is dry`)
					end
				end
			end
		end)

		t.it("the zones still open at level 10 (creator decision)", function()
			t.eq(Defaults.PvP.MinLevel, 10)
		end)
	end)

	t.describe("unions (D-48)", function()
		local function facts(overrides)
			local f = {
				inviterHasParty = true,
				inviterIsLeader = true,
				inviterInUnion = false,
				inviterLeadsUnion = false,
				sameParty = false,
				targetIsLeader = true,
				targetInUnion = false,
				sameRace = true,
				unionSize = 1,
				maxParties = 4,
				alreadyInvited = false,
			}
			for k, v in overrides or {} do
				f[k] = v
			end
			return f
		end

		t.it("party leaders invite other parties' leaders of their realm, up to 4 parties", function()
			t.ok(PartyRules.canUnionInvite(facts()))
			t.ok(
				PartyRules.canUnionInvite(
					facts({ inviterInUnion = true, inviterLeadsUnion = true, unionSize = 3 })
				)
			)
			local function reason(o)
				return select(2, PartyRules.canUnionInvite(facts(o)))
			end
			t.eq(reason({ inviterHasParty = false }), "noParty")
			t.eq(reason({ inviterIsLeader = false }), "notLeader")
			t.eq(reason({ inviterInUnion = true }), "notUnionLeader")
			t.eq(reason({ sameParty = true }), "self")
			t.eq(reason({ targetIsLeader = false }), "targetNotLeader")
			t.eq(reason({ sameRace = false }), "otherRace")
			t.eq(reason({ targetInUnion = true }), "targetInUnion")
			t.eq(reason({ inviterInUnion = true, inviterLeadsUnion = true, unionSize = 4 }), "full")
			t.eq(reason({ alreadyInvited = true }), "alreadyInvited")
			t.eq(Defaults.Party.UnionMaxParties, 4)
		end)

		t.it("union remotes take only a Player (and a boolean)", function()
			t.eq(#Registry.UnionInvite.args, 1)
			t.eq(#Registry.UnionRespond.args, 2)
			t.eq(#Registry.UnionLeave.args, 0)
			t.eq(#Registry.UnionKick.args, 1)
			t.ok(
				not (Schema.validateArgs(Registry.UnionInvite.args, 1, { "Player2" })),
				"names are not accepted"
			)
			local state = {
				parties = {
					{ leaderUserId = -1, size = 4, leads = true },
					{ leaderUserId = -2, size = 2, leads = false },
				},
				maxParties = 4,
			}
			t.ok((Schema.validateArgs(Registry.UnionState.args, 1, { state })))
		end)
	end)
end
