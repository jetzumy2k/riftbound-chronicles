local load = require("../loader")
local MobBrain = load("src/shared/Logic/MobBrain")
local DungeonRules = load("src/shared/Logic/DungeonRules")
local Telegraph = load("src/shared/Logic/Telegraph")
local PartyRules = load("src/shared/Logic/PartyRules")
local EnemyDefinitions = load("src/shared/Definitions/EnemyDefinitions")
local DungeonDefinitions = load("src/shared/Definitions/DungeonDefinitions")
local WorldLayout = load("src/shared/Definitions/WorldLayout")
local XPTable = load("src/shared/Logic/XPTable")
local Defaults = load("src/server/Config/Defaults")
local Schema = load("src/shared/Logic/Schema")
local Registry = load("src/shared/Net/Registry")(Schema)

local PROFILE = { aggroRadius = 30, leashRadius = 90, attackRange = 6 }

local function input(overrides)
	local base = {
		state = "Idle",
		now = 10,
		targetDistance = nil,
		distanceFromHome = 0,
		attackReadyAt = 0,
		windupEndsAt = 0,
	}
	for k, v in overrides do
		base[k] = v
	end
	return base
end

return function(t)
	t.describe("MobBrain", function()
		t.it("idles until a player comes within aggro range", function()
			t.eq(select(2, MobBrain.step(input({}), PROFILE)), "None")
			t.eq(select(2, MobBrain.step(input({ targetDistance = 40 }), PROFILE)), "None")
			local state, action = MobBrain.step(input({ targetDistance = 20 }), PROFILE)
			t.eq(state, "Chase")
			t.eq(action, "MoveToTarget")
		end)

		t.it("winds up in range when ready, waits when not", function()
			local state, action = MobBrain.step(input({ state = "Chase", targetDistance = 5 }), PROFILE)
			t.eq(state, "Windup")
			t.eq(action, "StartWindup")
			state, action =
				MobBrain.step(input({ state = "Chase", targetDistance = 5, attackReadyAt = 11 }), PROFILE)
			t.eq(state, "Chase")
			t.eq(action, "Stop")
		end)

		t.it("a wind-up always resolves into a strike when it ends", function()
			local _, action = MobBrain.step(input({ state = "Windup", windupEndsAt = 11 }), PROFILE)
			t.eq(action, "None")
			local state, strike = MobBrain.step(input({ state = "Windup", windupEndsAt = 9.9 }), PROFILE)
			t.eq(strike, "Strike")
			t.eq(state, "Chase")
		end)

		t.it("leashes home past its leash and restores on arrival", function()
			local state, action =
				MobBrain.step(input({ state = "Chase", targetDistance = 5, distanceFromHome = 95 }), PROFILE)
			t.eq(state, "Return")
			t.eq(action, "MoveHome")
			-- Returning mobs ignore players until home.
			state, action =
				MobBrain.step(input({ state = "Return", targetDistance = 2, distanceFromHome = 20 }), PROFILE)
			t.eq(action, "MoveHome")
			state, action = MobBrain.step(input({ state = "Return", distanceFromHome = 1 }), PROFILE)
			t.eq(state, "Idle")
			t.eq(action, "Restore")
		end)

		t.it("drops a target that runs far away", function()
			local _, action = MobBrain.step(input({ state = "Chase", targetDistance = 30 * 2.6 }), PROFILE)
			t.eq(action, "MoveHome")
			_, action = MobBrain.step(input({ state = "Chase" }), PROFILE)
			t.eq(action, "MoveHome")
		end)
	end)

	t.describe("DungeonRules", function()
		t.it("entry needs the level and room in the party", function()
			t.ok((DungeonRules.canEnter(1, 1, 1, 4)))
			t.eq(select(2, DungeonRules.canEnter(0, 1, 1, 4)), "level")
			t.eq(select(2, DungeonRules.canEnter(5, 5, 1, 4)), "partySize")
			t.eq(select(2, DungeonRules.canEnter(5, 0, 1, 4)), "partySize")
		end)

		t.it("D-32: party EXP gets a bonus, then splits evenly", function()
			t.eq(DungeonRules.shareXp(100, 1), 100)
			t.eq(DungeonRules.shareXp(100, 2), 58) -- 115 / 2
			t.eq(DungeonRules.shareXp(100, 4), 36) -- 145 / 4
			t.eq(DungeonRules.shareXp(100, 0), 0)
			t.eq(DungeonRules.shareXp(0, 3), 0)
			-- The whole party always earns more than a solo kill in total.
			for n = 2, 4 do
				t.ok(DungeonRules.shareXp(100, n) * n > 100, `party of {n}`)
			end
		end)

		t.it("D-39: respawn beside the leader, else an ally, else at the gate", function()
			t.eq(PartyRules.respawnChoice(true, true), "Leader")
			t.eq(PartyRules.respawnChoice(true, false), "Leader")
			t.eq(PartyRules.respawnChoice(false, true), "Ally")
			t.eq(PartyRules.respawnChoice(false, false), "Gate")
		end)

		t.it("boss phases follow HP", function()
			local phases = DungeonDefinitions.boss("Cerberus").phases
			t.eq(DungeonRules.phaseFor(phases, 1), 1)
			t.eq(DungeonRules.phaseFor(phases, 0.66), 1)
			t.eq(DungeonRules.phaseFor(phases, 0.65), 2)
			t.eq(DungeonRules.phaseFor(phases, 0.31), 2)
			t.eq(DungeonRules.phaseFor(phases, 0.3), 3)
			t.eq(DungeonRules.phaseFor(phases, 0), 3)
		end)

		t.it("run ids are unique per server and valid reward ids", function()
			local RewardClaims = load("src/server/Persistence/RewardClaims")
			local a = DungeonRules.runId("abc-123", 1)
			t.ok(a ~= DungeonRules.runId("abc-123", 2))
			t.ok(RewardClaims.isValidId(`D:{a}`), a)
			t.ok(RewardClaims.isValidId(`D:{DungeonRules.runId("", 7)}`))
			local guid = "8B6C3C1E-4F2A-4C47-9E0F-3D1B2A7C9E10"
			t.ok(RewardClaims.isValidId(`D:{DungeonRules.runId(guid, 12)}`))
		end)
	end)

	t.describe("PartyRules", function()
		local function facts(over)
			local f = {
				isSelf = false,
				inviterInParty = false,
				inviterIsLeader = false,
				partySize = 1,
				maxMembers = 4,
				sameRace = true,
				targetInParty = false,
				targetLoaded = true,
				alreadyInvited = false,
				partyInDungeon = false,
			}
			for k, v in over do
				f[k] = v
			end
			return f
		end

		t.it("anyone may start a party by inviting; then only the leader invites", function()
			t.ok((PartyRules.canInvite(facts({}))))
			t.ok(
				(
					PartyRules.canInvite(
						facts({ inviterInParty = true, inviterIsLeader = true, partySize = 2 })
					)
				)
			)
			t.eq(
				select(2, PartyRules.canInvite(facts({ inviterInParty = true, inviterIsLeader = false }))),
				"notLeader"
			)
		end)

		t.it("rejects bad targets and full or busy parties", function()
			t.eq(select(2, PartyRules.canInvite(facts({ isSelf = true }))), "self")
			t.eq(select(2, PartyRules.canInvite(facts({ sameRace = false }))), "otherRace")
			t.eq(select(2, PartyRules.canInvite(facts({ targetInParty = true }))), "targetInParty")
			t.eq(select(2, PartyRules.canInvite(facts({ targetLoaded = false }))), "unavailable")
			t.eq(select(2, PartyRules.canInvite(facts({ partySize = 4 }))), "full")
			t.eq(select(2, PartyRules.canInvite(facts({ alreadyInvited = true }))), "alreadyInvited")
			t.eq(select(2, PartyRules.canInvite(facts({ partyInDungeon = true }))), "inDungeon")
		end)

		t.it("leadership passes to the longest-standing member", function()
			t.eq(PartyRules.nextLeader({ "a", "b", "c" }, "a"), "b")
			t.eq(PartyRules.nextLeader({ "a", "b", "c" }, "b"), "a")
			t.eq(PartyRules.nextLeader({ "a" }, "a"), nil)
		end)
	end)

	t.describe("Telegraph", function()
		t.it("circle, ring and cone hit tests", function()
			t.ok(Telegraph.inCircle({ 0, 0 }, 5, { 3, 4 }))
			t.ok(not Telegraph.inCircle({ 0, 0 }, 5, { 3, 4.1 }))
			t.ok(Telegraph.inRing({ 0, 0 }, 9, 30, { 20, 0 }))
			t.ok(not Telegraph.inRing({ 0, 0 }, 9, 30, { 3, 0 }), "standing close is safe")
			t.ok(not Telegraph.inRing({ 0, 0 }, 9, 30, { 31, 0 }))
			-- Cone facing -Z, 100 degrees wide, radius 16.
			local facing = { 0, -1 }
			t.ok(Telegraph.inCone({ 0, 0 }, facing, 16, 100, { 0, -10 }))
			t.ok(Telegraph.inCone({ 0, 0 }, facing, 16, 100, { 7, -7 }), "45 degrees off")
			t.ok(not Telegraph.inCone({ 0, 0 }, facing, 16, 100, { 10, -2 }), "too far to the side")
			t.ok(not Telegraph.inCone({ 0, 0 }, facing, 16, 100, { 0, 10 }), "behind")
			t.ok(not Telegraph.inCone({ 0, 0 }, facing, 16, 100, { 0, -17 }), "out of reach")
		end)
	end)

	t.describe("dungeon and enemy data", function()
		t.it("every enemy is sane", function()
			for id, enemy in EnemyDefinitions.ById do
				t.eq(enemy.id, id)
				t.ok(enemy.level >= 0 and enemy.level <= 50, id)
				t.ok(enemy.attackRange < enemy.aggroRadius, `{id}: range < aggro`)
				t.ok(enemy.aggroRadius < enemy.leashRadius, `{id}: aggro < leash`)
				t.ok(enemy.windup >= 0.3, `{id}: readable wind-up`)
				t.ok(enemy.attackCooldown > enemy.windup, id)
				t.ok(enemy.xp > 0 and enemy.moveSpeed > 0, id)
				t.ok(enemy.attackCoefficient > 0 and enemy.attackCoefficient <= 1, id)
			end
		end)

		t.it("every room spawn, boss and ability resolves", function()
			for id, dungeon in DungeonDefinitions.ById do
				t.eq(dungeon.id, id)
				for _, floor in dungeon.floors do
					for _, room in floor.rooms do
						for _, camp in room.camps do
							t.ok(EnemyDefinitions.get(camp.enemy) ~= nil, `{room.id}: {camp.enemy}`)
							-- Camps spread their creatures up to 7 studs around the spot.
							t.ok(math.abs(camp.x) + 7 < room.size[1] / 2 - 2, `{room.id}: camp inside width`)
							t.ok(math.abs(camp.z) + 7 < room.size[3] / 2 - 2, `{room.id}: camp inside depth`)
							if camp.class ~= "Mob" and EnemyDefinitions.get(camp.enemy).tier then
								t.ok(
									DungeonDefinitions.boss(camp.enemy) ~= nil,
									`{room.id}: {camp.enemy} boss def`
								)
							end
						end
						if room.boss then
							local boss = DungeonDefinitions.boss(room.boss)
							t.ok(boss ~= nil, room.boss)
							for _, phase in boss.phases do
								for _, ability in phase.abilities do
									t.ok(boss.abilities[ability] ~= nil, `{room.boss}: ability {ability}`)
								end
							end
						end
					end
				end
				t.ok(dungeon.bonusXp.Boss > dungeon.bonusXp.FloorBoss, id)
				t.ok(dungeon.bonusXp.FloorBoss > dungeon.bonusXp.MiniBoss, id)
			end
		end)

		t.it("boss phases step down and summons name real enemies", function()
			for id, boss in DungeonDefinitions.Bosses do
				t.ok(EnemyDefinitions.get(boss.enemy) ~= nil, id)
				local last = 1
				for _, phase in boss.phases do
					t.ok(phase.untilHpFraction < last, `{id}: phases ordered`)
					last = phase.untilHpFraction
				end
				t.eq(boss.phases[#boss.phases].untilHpFraction, 0)
				for name, ability in boss.abilities do
					t.ok(ability.telegraph >= 0.8, `{id}.{name}: readable telegraph`)
					if ability.shape == "Summon" then
						t.ok(EnemyDefinitions.get(ability.enemy) ~= nil, `{id}.{name}`)
					elseif ability.shape == "Ring" then
						t.ok(ability.inner and ability.inner < ability.radius, `{id}.{name}: safe centre`)
					end
				end
			end
		end)

		t.it("D-42 respawn timers: mobs in seconds, mini boss in minutes, boss in hours", function()
			local d = Defaults.Dungeon
			t.ok(d.MobRespawnSeconds >= 10 and d.MobRespawnSeconds <= 300)
			t.ok(d.MiniBossRespawnMinutes >= 15 and d.MiniBossRespawnMinutes <= 30)
			t.ok(d.BossRespawnHours >= 1 and d.BossRespawnHours <= 12)
			-- Studio overrides are only shortcuts for testing.
			t.ok(d.FloorBossRespawnMinutes >= d.MiniBossRespawnMinutes)
			t.ok(d.FloorBossRespawnMinutes * 60 < d.BossRespawnHours * 3600)
			t.ok(d.StudioMiniBossRespawnSeconds < d.MiniBossRespawnMinutes * 60)
			t.ok(d.StudioFloorBossRespawnSeconds < d.FloorBossRespawnMinutes * 60)
			t.ok(d.StudioBossRespawnSeconds < d.BossRespawnHours * 3600)
		end)

		t.it("roomAt / floorAt find rooms and floors, nil in passages", function()
			local dungeon = DungeonDefinitions.get("RiftHollow")
			local floor = dungeon.floors[1]
			local first = floor.rooms[2]
			t.eq(DungeonDefinitions.roomAt(floor, 0, first.center[2]), 2)
			-- The passage before it.
			local passage = floor.passages[1]
			t.eq(DungeonDefinitions.roomAt(floor, 0, passage.center[2]), nil, "passage")
			t.eq(DungeonDefinitions.roomAt(floor, 500, first.center[2]), nil)
			for index, f in dungeon.floors do
				local b = DungeonDefinitions.floorBounds(f)
				local midX, midZ = (b[1] + b[2]) / 2, (b[3] + b[4]) / 2
				local found = DungeonDefinitions.floorAt(dungeon, f.offsetX + midX, midZ)
				t.eq(found, index, `floor {index}`)
			end
			t.eq((DungeonDefinitions.floorAt(dungeon, -900, 50)), nil)
		end)

		t.it("Training Grounds sprites can earn the first dungeon's level", function()
			-- Quest 1: defeating 5 training creatures takes a new player to level 1.
			local sprite = EnemyDefinitions.get("RiftSprite")
			local needed = XPTable.totalToReach(DungeonDefinitions.get("RiftHollow").minLevel)
			t.ok(sprite.xp * 5 >= needed, `5 sprites give {sprite.xp * 5} of {needed} EXP`)
		end)

		t.it("dungeon slots are far apart and away from the world", function()
			local slots = WorldLayout.DungeonSlots
			t.ok(slots.spacing >= 2000)
			t.ok(slots.maxSlots >= 2, "one slot per realm")
			for _, realm in WorldLayout.Realms do
				t.ok(
					not WorldLayout.isInDungeonRegion(realm.platformCenter[1] + realm.platformSize[1]),
					realm.race
				)
			end
			local first = WorldLayout.dungeonSlotOrigin(1)
			t.ok(
				WorldLayout.isInDungeonRegion(first[1]) and first[2] > 0,
				"slot 1 above ground, in the region"
			)
		end)

		t.it("party remotes take only a Player (and a boolean)", function()
			t.eq(#Registry.PartyInvite.args, 1)
			t.eq(#Registry.PartyRespond.args, 2)
			t.eq(#Registry.PartyLeave.args, 0)
			t.eq(#Registry.PartyKick.args, 1)
			t.ok(
				not (Schema.validateArgs(Registry.PartyInvite.args, 1, { "Player2" })),
				"names are not accepted"
			)
		end)

		t.it("party payloads accept Studio test players (negative user ids)", function()
			-- Local test servers use Player1 = -1, Player2 = -2.
			local invite = { fromUserId = -2, expiresIn = 45 }
			t.ok((Schema.validateArgs(Registry.PartyInvited.args, 1, { invite })))
			local roster = {
				members = { { userId = -1, leader = true }, { userId = -2, leader = false } },
				maxMembers = 4,
			}
			t.ok((Schema.validateArgs(Registry.PartyState.args, 1, { roster })))
			local real = { members = { { userId = 11763195295, leader = true } }, maxMembers = 4 }
			t.ok((Schema.validateArgs(Registry.PartyState.args, 1, { real })))
		end)

		t.it("DungeonLeave takes no arguments", function()
			t.ok((Schema.validateArgs(Registry.DungeonLeave.args, 0, {})))
			local ok = Schema.validateArgs(Registry.DungeonLeave.args, 1, { "someoneElse" })
			t.ok(not ok)
		end)
	end)
end
