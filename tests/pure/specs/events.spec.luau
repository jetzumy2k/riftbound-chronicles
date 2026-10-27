local load = require("../loader")
local EventDefinitions = load("src/shared/Definitions/EventDefinitions")
local EventRules = load("src/shared/Logic/EventRules")
local LootRules = load("src/shared/Logic/LootRules")
local AdminRules = load("src/shared/Logic/AdminRules")
local WorldLayout = load("src/shared/Definitions/WorldLayout")
local EventSpawns = load("src/shared/Logic/EventSpawns")
local EnemyDefinitions = load("src/shared/Definitions/EnemyDefinitions")
local DungeonDefinitions = load("src/shared/Definitions/DungeonDefinitions")
local ZoneAtmosphere = load("src/shared/Definitions/ZoneAtmosphere")

local NOW = 1800000000

local function window(id: string, from: number, to: number)
	return { Id = id, StartsAt = NOW + from, EndsAt = NOW + to, By = 1 }
end

-- Stage 1 effects that the server applies (later stages add the rest).
local BUILT = {
	XP = true,
	QuestXP = true,
	BossXP = true,
	DropChance = true,
	RareWeight = true,
	LegendaryWeight = true,
	StoneChance = true,
	PerfectWeight = true,
	Healing = true,
	TrainingCooldown = true,
	AttributeRolls = true,
	-- Stage 2 (D-91).
	MythicalWeight = true,
	BossRespawn = true,
	-- Stage 3 (D-92).
	Marks = true,
}

return function(t)
	t.describe("Events", function()
		t.it("at least 30 templates with every section 23 field", function()
			t.ok(#EventDefinitions.List >= 30, `{#EventDefinitions.List} templates`)
			local zones = {
				All = true,
				Dungeon = true,
				Desert = true,
				Jungle = true,
				WarZones = true,
				Capitals = true,
				Training = true,
			}
			for _, e in EventDefinitions.List do
				t.ok(e.name ~= "" and e.icon ~= "" and e.blurb ~= "", `{e.id} text`)
				t.ok(e.minutes >= 1 and e.minutes <= e.maxMinutes, `{e.id} duration`)
				t.ok(e.cooldownMinutes >= 0, `{e.id} cooldown`)
				t.ok(zones[e.zone], `{e.id} zone {e.zone}`)
				for category, m in e.modifiers do
					t.ok(EventRules.CATEGORIES[category] ~= nil, `{e.id}: unknown category {category}`)
					t.ok(m > 0, `{e.id}: {category} {m}`)
					if EventDefinitions.isReady(e) then
						t.ok(BUILT[category], `{e.id} is startable but {category} is not built yet`)
					end
				end
			end
		end)

		t.it("a server joining mid-event sees it running (windows by UTC time)", function()
			local windows = { window("DoubleExp", -3600, 3600), window("HealingFestival", 600, 1200) }
			local running = EventRules.active(windows, NOW)
			t.eq(#running, 1)
			t.eq(running[1].Id, "DoubleExp")
			t.eq(#EventRules.active(windows, NOW + 700), 2)
			t.eq(#EventRules.active(windows, NOW + 3600), 0, "ended at EndsAt")
			t.eq(#EventRules.active({ window("NotAnEvent", -1, 10) }, NOW), 0, "unknown ids dropped")
		end)

		t.it("overlapping events add up and stay within the caps", function()
			local running = EventRules.active({
				window("DoubleExp", -10, 100),
				window("ClassMastery", -10, 100),
				window("ArcherChallenge", -10, 100),
			}, NOW)
			local archer = { job = "Archer", zone = "Desert", level = 20 }
			local healer = { job = "Healer", level = 20 }
			-- 1 + 1 + 0.25 + 0.5 = 2.75 for an Archer; 2.25 for others.
			t.near(EventRules.factor("XP", running, archer), 2.75, 1e-9)
			t.near(EventRules.factor("XP", running, healer), 2.25, 1e-9)
			local more = EventRules.active({
				window("DoubleExp", -10, 100),
				window("ClassMastery", -10, 100),
				window("ArcherChallenge", -10, 100),
				window("RiftEclipse", -10, 100),
			}, NOW)
			t.eq(EventRules.factor("XP", more, archer), 3, "capped at 3x")
			t.eq(EventRules.scaleXp(101, 2.75), 278)
			t.eq(EventRules.scaleXp(5, 1), 5)
			t.eq(EventRules.factor("XP", {}, archer), 1)
		end)

		t.it("zone and eligibility limit where an event applies", function()
			local running = EventRules.active(
				{ window("NoCooldownTraining", -10, 100), window("StoneRush", -10, 100) },
				NOW
			)
			t.near(EventRules.factor("TrainingCooldown", running, { zone = "Training" }), 0.1, 1e-9)
			t.eq(EventRules.factor("TrainingCooldown", running, { zone = "Dungeon" }), 1)
			t.eq(EventRules.factor("StoneChance", running, { zone = "Jungle" }), 2)
			t.eq(EventRules.factor("StoneChance", running, { zone = "Capitals" }), 1)
			t.eq(EventRules.factor("StoneChance", running, {}), 1, "no zone known: zoned events skip")
			local angel = EventRules.applies(
				EventDefinitions.get("AngelDefense"),
				{ zone = "Capitals", race = "Angel" }
			)
			local devil = EventRules.applies(
				EventDefinitions.get("AngelDefense"),
				{ zone = "Capitals", race = "Devil" }
			)
			t.ok(angel and not devil, "race eligibility")
		end)

		t.it("rarity weights re-normalize to 100", function()
			local running = EventRules.active({
				window("RareGearRush", -10, 100),
				window("LegendaryHunt", -10, 100),
				window("DoubleDrops", -10, 100),
			}, NOW)
			local ctx = { zone = "Dungeon" }
			local mob = { DropChancePct = 12, Rarity = { Standard = 45, Uncommon = 25, Rare = 30 } }
			local boosted = EventRules.lootTable(mob, running, ctx)
			t.ok(LootRules.validate(boosted), "still a valid table")
			t.near(boosted.DropChancePct, 24, 1e-9)
			t.near(boosted.Rarity.Rare, 60 / 130 * 100, 1e-9)
			local boss = { DropChancePct = 100, Rarity = { Rare = 80, Legendary = 20 } }
			local b = EventRules.lootTable(boss, running, ctx)
			t.ok(LootRules.validate(b), "boss table valid")
			t.eq(b.DropChancePct, 100, "chance never above 100")
			local sum = 0
			for _, w in b.Rarity do
				sum += w
			end
			t.near(sum, 100, 1e-9)
			t.ok(EventRules.lootTable(mob, {}, ctx) == mob, "no events: the same table")
			local stones = { DropChancePct = 25, Stones = { PerfectStone = 30, EnhancementStone = 70 } }
			local hunt = EventRules.active({ window("PerfectStoneHunt", -10, 100) }, NOW)
			local s = EventRules.stoneTable(stones, hunt, { zone = "Desert" })
			t.ok(LootRules.validateStones(s), "stone table valid")
			t.near(s.Stones.PerfectStone, 60 / 130 * 100, 1e-9)
		end)

		t.it("scheduling checks stage, length, time, overlap and cooldown", function()
			local function can(windows, id, from, minutes)
				local ok, reason = EventRules.canSchedule(windows, id, NOW + from, minutes, NOW)
				return if ok then "ok" else reason
			end
			t.eq(can({}, "DoubleExp", 0, 60), "ok")
			t.eq(can({}, "Nope", 0, 60), "unknown")
			t.eq(can({}, "DoubleExp", 0, 0), "duration")
			t.eq(can({}, "DoubleExp", 0, 5 * 24 * 60), "duration")
			t.eq(can({}, "DoubleExp", -3600, 60), "past")
			t.eq(can({}, "DoubleExp", 40 * 24 * 3600, 60), "ahead")
			local busy = { window("DoubleExp", -600, 600) }
			t.eq(can(busy, "DoubleExp", 0, 60), "running")
			-- Cooldown 60 min after it ends at +600 s.
			t.eq(can(busy, "DoubleExp", 600 + 1800, 60), "cooldown")
			t.eq(can(busy, "DoubleExp", 600 + 3600, 60), "ok")
			t.eq(can(busy, "HealingFestival", 0, 60), "ok", "other events may overlap")
			local many = {}
			for i = 1, EventRules.MAX_WINDOWS do
				table.insert(many, window("TripleQuestExp", i * 100000, i * 100000 + 60))
			end
			t.eq(can(many, "DoubleExp", 0, 60), "full")
		end)

		t.it("old windows are pruned after a day; ending never needs player data", function()
			local list = { window("DoubleExp", -200000, -100000), window("HealingFestival", -7200, -3600) }
			local kept = EventRules.prune(list, NOW)
			t.eq(#kept, 1)
			t.eq(kept[1].Id, "HealingFestival")
		end)

		t.it("event zones from world positions", function()
			local angel = WorldLayout.Realms.Angel
			local yard = WorldLayout.trainingYard(angel)
			t.eq(EventRules.zoneAt(yard[1], yard[3]), "Training")
			t.eq(EventRules.zoneAt(angel.platformCenter[1], angel.platformCenter[3]), "Capitals")
			local desert = WorldLayout.WarZones.DesertRift.center
			t.eq(EventRules.zoneAt(desert[1], desert[3]), "Desert")
			local jungle = WorldLayout.WarZones.JungleRift.center
			t.eq(EventRules.zoneAt(jungle[1], jungle[3]), "Jungle")
			t.eq(EventRules.zoneAt(WorldLayout.DungeonSlots.origin[1], 0), "Dungeon")
		end)

		t.it("world events spawn real creatures clear of camps and boss posts", function()
			for _, id in { "RiftBeastInvasion", "EliteSwarm", "MythicalInvasion", "NullbornWorldBoss" } do
				for _, zoneId in EventSpawns.ZONES do
					local zone = WorldLayout.WarZones[zoneId]
					local plan = EventSpawns.plan(id, zoneId)
					t.ok(#plan > 0, `{id} spawns nothing in {zoneId}`)
					for _, spawn in plan do
						local enemy = EnemyDefinitions.get(spawn.enemy)
						t.ok(enemy ~= nil, `{id}: unknown enemy {spawn.enemy}`)
						if spawn.kind == "Boss" then
							t.ok(
								enemy and enemy.tier ~= nil and DungeonDefinitions.boss(spawn.enemy) ~= nil,
								`{spawn.enemy} boss`
							)
						else
							t.ok(enemy and enemy.tier == nil, `{spawn.enemy} is a regular creature`)
						end
						local half = zone.size / 2 - 20
						t.ok(
							math.abs(spawn.x) <= half and math.abs(spawn.z) <= half,
							`{id} {spawn.x},{spawn.z} inside`
						)
						for race, base in zone.bases do
							local d = math.sqrt((spawn.x - base.x) ^ 2 + (spawn.z - base.z) ^ 2)
							t.ok(
								d >= base.radius + 40,
								`{id} {spawn.enemy} {math.floor(d)} studs from the {race} camp`
							)
						end
						if spawn.kind == "Boss" then
							for _, post in zone.bosses do
								local d = math.sqrt((spawn.x - post.x) ^ 2 + (spawn.z - post.z) ^ 2)
								t.ok(d >= 60, `{spawn.enemy} {math.floor(d)} studs from {post.enemy}`)
							end
						end
					end
				end
			end
			t.eq(#EventSpawns.plan("DoubleExp", "DesertRift"), 0, "reward events spawn nothing")
		end)

		t.it("weather shows in its own zone only", function()
			local name = ZoneAtmosphere.weatherFor("Desert", { "DesertStorm" })
			t.eq(name, "Sandstorm")
			t.eq(ZoneAtmosphere.weatherFor("Jungle", { "DesertStorm" }), nil)
			t.eq(ZoneAtmosphere.weatherFor("Jungle", { "JungleFlood" }), "Flood")
			t.eq(ZoneAtmosphere.weatherFor("Neutral", { "RiftEclipse" }), "Eclipse")
			t.eq(ZoneAtmosphere.weatherFor("Dungeon", { "RiftEclipse" }), nil, "no eclipse underground")
			t.eq(ZoneAtmosphere.weatherFor("Desert", {}), nil)
			for weatherName, weather in ZoneAtmosphere.Weather do
				for key in ZoneAtmosphere.Presets.Neutral do
					t.ok(weather.preset[key] ~= nil, `{weatherName} preset has {key}`)
				end
			end
		end)

		t.it("a Moderator needs the grant to run events", function()
			t.ok(not AdminRules.has("Moderator", "events.activate", {}), "no grant")
			t.ok(AdminRules.has("Moderator", "events.activate", { "events.activate" }), "granted")
			t.ok(AdminRules.has("Admin", "events.activate"), "admins can")
			t.ok(not AdminRules.has(nil, "events.activate"), "players can't")
		end)
		t.it(
			"daily random event: drawn 15 min ahead, once a day, only ticked events (D-113/D-114)",
			function()
				local ready = {}
				for _, id in EventDefinitions.IDS do
					if EventDefinitions.isReady(EventDefinitions.get(id)) then
						table.insert(ready, id)
					end
				end
				t.ok(#ready >= 2, "at least two events can be drawn")
				local day = 1793491200 -- 2026-11-01 00:00 UTC
				local daily = { Enabled = true, TimeUtcMinutes = 720, Minutes = 60, Excluded = {} }
				local at = day + 720 * 60
				local lead = EventRules.DAILY_LEAD_SECONDS
				t.eq(EventRules.dailyTime(daily, at + 5), at)
				t.eq(EventRules.dailyDue({}, daily, at - lead - 1), nil, "not before its lead time")
				t.eq(EventRules.dailyDue({}, daily, at - 60), at, "drawn ahead, starting at its time")
				t.eq(EventRules.dailyDue({}, daily, at + 30), at)
				t.eq(
					EventRules.dailyDue({}, daily, at + EventRules.DAILY_GRACE_SECONDS),
					nil,
					"a late server skips"
				)
				local started = { Id = ready[1], StartsAt = at, EndsAt = at + 3600, By = 0, Daily = true }
				t.eq(EventRules.dailyDue({ started }, daily, at + 60), nil, "only once a day")
				t.eq(
					EventRules.dailyDue({ started }, daily, at + 86400 - 60),
					at + 86400,
					"again the next day"
				)
				local manual = { Id = ready[1], StartsAt = at, EndsAt = at + 3600, By = 5 }
				t.eq(
					EventRules.dailyDue({ manual }, daily, at + 60),
					at,
					"an admin's own event doesn't count"
				)
				local midnight = { Enabled = true, TimeUtcMinutes = 5, Minutes = 60, Excluded = {} }
				t.eq(
					EventRules.dailyDue({}, midnight, day - 300),
					day + 300,
					"00:05 is drawn the evening before"
				)
				daily.Enabled = false
				t.eq(EventRules.dailyDue({}, daily, at + 30), nil, "off: nothing")
				daily.Enabled = true
				t.eq(#EventRules.dailyCandidates({}, daily, at, at - 60), #ready, "every ready event")
				daily.Excluded = table.clone(ready)
				table.remove(daily.Excluded, 1)
				local one = EventRules.dailyCandidates({}, daily, at, at - 60)
				t.eq(#one, 1)
				t.eq(one[1], ready[1])
				t.eq(
					#EventRules.dailyCandidates({ manual }, daily, at + 60, at + 60),
					0,
					"not drawn while running"
				)
				daily.Minutes = 1440
				t.ok(EventRules.dailyMinutes(daily, ready[1]) <= EventDefinitions.get(ready[1]).maxMinutes)
				-- D-114: what starts within 15 minutes is announced.
				local soon = EventRules.soon({
					manual,
					{ Id = ready[2], StartsAt = at + 600, EndsAt = at + 4200, By = 1 },
					{ Id = ready[1], StartsAt = at + 3600, EndsAt = at + 7200, By = 1 },
				}, at)
				t.eq(#soon, 1, "running and far-off events are not 'soon'")
				t.eq(soon[1].Id, ready[2])
			end
		)
	end)
end
