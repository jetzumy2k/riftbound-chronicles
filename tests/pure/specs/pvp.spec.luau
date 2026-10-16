local load = require("../loader")
local PvPRules = load("src/shared/Logic/PvPRules")
local DesertTerrain = load("src/shared/Logic/DesertTerrain")
local JungleTerrain = load("src/shared/Logic/JungleTerrain")
local WarZoneTerrain = load("src/shared/Logic/WarZoneTerrain")
local WorldLayout = load("src/shared/Definitions/WorldLayout")
local ZoneGeometry = load("src/shared/Logic/ZoneGeometry")
local EnemyDefinitions = load("src/shared/Definitions/EnemyDefinitions")
local ZoneAtmosphere = load("src/shared/Definitions/ZoneAtmosphere")
local Defaults = load("src/server/Config/Defaults")

local function credit(over)
	local f = {
		attackerLevel = 12,
		victimLevel = 12,
		levelGap = 5,
		sinceLastCredit = nil,
		repeatWindowSeconds = 1800,
		creditsToday = 0,
		dailyCap = 50,
	}
	for k, v in over do
		f[k] = v
	end
	return PvPRules.creditVictory(f)
end

local function portal(over)
	local f = { distance = 5, reach = 18, level = 12, minLevel = 10, combatTagged = false, defeated = false }
	for k, v in over do
		f[k] = v
	end
	return PvPRules.canUsePortal(f)
end

return function(t)
	t.describe("PvPRules", function()
		t.it("D-16: attackers are scaled down to the victim's level + gap", function()
			t.eq(PvPRules.normalizedLevel(30, 10, 5), 15)
			t.eq(PvPRules.normalizedLevel(12, 10, 5), 12)
			t.eq(PvPRules.normalizedLevel(10, 30, 5), 10, "lower-level attackers are never scaled up")
		end)

		t.it("T-18: victory credit rules", function()
			t.ok((credit({})))
			t.eq(select(2, credit({ victimLevel = 6 })), "victimTooLow")
			t.ok((credit({ victimLevel = 7 })), "within the gap still counts")
			t.eq(select(2, credit({ sinceLastCredit = 600 })), "repeatVictim")
			t.ok((credit({ sinceLastCredit = 1800 })), "after the window it counts again")
			t.eq(select(2, credit({ creditsToday = 50 })), "dailyCap")
		end)

		t.it("T-15: portals need reach, level and no combat tag", function()
			t.ok((portal({})))
			t.eq(select(2, portal({ distance = 30 })), "reach")
			t.eq(select(2, portal({ defeated = true })), "reach")
			t.eq(select(2, portal({ combatTagged = true })), "inCombat")
			t.eq(select(2, portal({ level = 9 })), "level")
			t.ok((portal({ level = 0, minLevel = 0 })), "the return portal has no level requirement")
		end)

		t.it("daily credit days are UTC days", function()
			t.eq(PvPRules.day(0), 0)
			t.eq(PvPRules.day(86399), 0)
			t.eq(PvPRules.day(86400), 1)
		end)

		t.it("live servers use the D-16 level; only Studio may lower it", function()
			t.eq(Defaults.PvP.MinLevel, 10)
			t.ok(Defaults.PvP.StudioMinLevel <= Defaults.PvP.MinLevel)
			t.eq(Defaults.PvP.LevelGap, 5)
		end)
	end)

	t.describe("Desert Rift", function()
		local zone = WorldLayout.WarZones.DesertRift

		t.it("the oasis plaza is flat and the pool sits below the water line", function()
			for _, r in { 42, 50, 58 } do
				for i = 0, 7 do
					local a = i / 8 * math.pi * 2
					local h = DesertTerrain.sample(math.cos(a) * r, math.sin(a) * r, zone.size)
					t.ok(math.abs(h) < 1, `plaza at r={r}: {h}`)
				end
			end
			t.ok(DesertTerrain.sample(0, 0, zone.size) < DesertTerrain.WATER_LEVEL - 3, "pool is deep enough")
		end)

		t.it("dunes rise away from the oasis and rim cliffs close the edges", function()
			local edge = zone.size / 2 - 5
			for _, p in { { edge, 0 }, { -edge, 0 }, { 0, edge }, { 0, -edge } } do
				local h = DesertTerrain.sample(p[1], p[2], zone.size)
				t.ok(h > 50, `rim at {p[1]},{p[2]}: {h}`)
			end
			local highest = 0
			for x = -400, 400, 40 do
				for z = -400, 400, 40 do
					local h = DesertTerrain.sample(x, z, zone.size)
					t.ok(h > -20 and h < 90, `height range at {x},{z}: {h}`)
					highest = math.max(highest, h)
				end
			end
			t.ok(highest > 30, "mesas and rim stand out")
		end)

		local function safeZone(id)
			for _, z in WorldLayout.SafeZones do
				if z.id == id then
					return z
				end
			end
			return nil
		end

		t.it("each realm has its own camp at opposite edges; the oasis is open ground", function()
			local angel, devil = zone.bases.Angel, zone.bases.Devil
			t.ok(angel ~= nil and devil ~= nil, "both realms have a base")
			local apart = math.sqrt((angel.x - devil.x) ^ 2 + (angel.z - devil.z) ^ 2)
			t.ok(apart >= 600, `camps are {apart} studs apart`)
			for race, base in zone.bases do
				local safe = safeZone(base.safeZone)
				t.ok(safe ~= nil and safe.race == race, `{race} camp safe zone belongs to {race}`)
				t.ok(
					math.sqrt(base.x ^ 2 + base.z ^ 2) > DesertTerrain.PLAZA_RADIUS + 150,
					`{race} camp far from the oasis`
				)
			end
			for _, z in WorldLayout.SafeZones do
				local c = z.volume.center
				t.ok(
					not ZoneGeometry.contains(
							z.volume,
							{ zone.center[1], zone.center[2] + 2, zone.center[3] }
						) or c == nil,
					`the oasis is not inside {z.id}`
				)
			end
		end)

		t.it("terrain plateaus match the camps", function()
			t.eq(zone.baseHeight, DesertTerrain.BASE_HEIGHT)
			t.eq(#DesertTerrain.BASES, 2)
			for _, b in DesertTerrain.BASES do
				local matched = false
				for _, base in zone.bases do
					if base.x == b[1] and base.z == b[2] then
						matched = true
					end
				end
				t.ok(matched, `plateau {b[1]},{b[2]} has a camp`)
			end
			for race, base in zone.bases do
				for _, offset in { { 0, 0 }, { 30, 0 }, { 0, -30 }, { -25, 20 } } do
					local h = DesertTerrain.sample(base.x + offset[1], base.z + offset[2], zone.size)
					t.ok(math.abs(h - DesertTerrain.BASE_HEIGHT) < 0.6, `{race} camp is flat: {h}`)
				end
				t.ok(base.radius < DesertTerrain.BASE_RADIUS, `{race} barrier inside the plateau`)
			end
		end)

		t.it("arrival and the return portal are inside your own camp's safe zone", function()
			for race, base in zone.bases do
				local safe = safeZone(base.safeZone)
				for _, spot in { { 12, -6 }, { 12, 6 }, { -(base.radius - 14), 0 } } do
					local p = WorldLayout.basePoint(zone, race, spot[1], spot[2])
					t.ok(
						p ~= nil and ZoneGeometry.contains(safe.volume, { p[1], p[2] + 3, p[3] }),
						`{race} spot {spot[1]},{spot[2]}`
					)
				end
			end
			t.eq(WorldLayout.basePoint(zone, "Nobody", 0, 0), nil)
		end)

		t.it("creatures roam the oasis and the dunes, never inside a camp", function()
			local half = zone.size / 2 - DesertTerrain.RIM_WIDTH
			local inOasis = 0
			for _, camp in zone.camps do
				t.ok(EnemyDefinitions.get(camp.enemy) ~= nil, camp.enemy)
				t.ok(math.abs(camp.x) < half and math.abs(camp.z) < half, `{camp.enemy} inside the rim`)
				t.ok(camp.count >= 1 and camp.count <= 4)
				for race, base in zone.bases do
					local d = math.sqrt((camp.x - base.x) ^ 2 + (camp.z - base.z) ^ 2)
					t.ok(d > base.radius + 60, `{camp.enemy} clear of the {race} camp`)
				end
				if math.sqrt(camp.x ^ 2 + camp.z ^ 2) < DesertTerrain.PLAZA_RADIUS then
					inOasis += 1
					t.ok(
						math.abs(DesertTerrain.sample(camp.x, camp.z, zone.size)) < 1,
						"oasis creatures stand on the plaza"
					)
				end
			end
			t.ok(inOasis >= 2, "creatures guard the oasis")
		end)

		t.it("the zone is far from the capitals and the dungeon slots", function()
			for _, realm in WorldLayout.Realms do
				t.eq(WorldLayout.warZoneAt(realm.platformCenter[1], realm.platformCenter[3]), nil, realm.race)
			end
			t.ok(not WorldLayout.isInDungeonRegion(zone.center[1] + zone.size / 2))
			t.eq(WorldLayout.warZoneAt(zone.center[1], zone.center[3]), zone)
			t.ok(ZoneAtmosphere.Presets[zone.atmosphere] ~= nil, "has an atmosphere")
		end)
	end)

	t.describe("War zones (shared rules)", function()
		local function safeZone(id)
			for _, z in WorldLayout.SafeZones do
				if z.id == id then
					return z
				end
			end
			return nil
		end

		t.it("every zone has a known terrain, an atmosphere and both realms' camps", function()
			local count = 0
			for id, zone in WorldLayout.WarZones do
				count += 1
				t.eq(zone.id, id)
				t.ok(zone.terrain == "Desert" or zone.terrain == "Jungle", `{id} terrain`)
				t.ok(ZoneAtmosphere.Presets[zone.atmosphere] ~= nil, `{id} atmosphere`)
				for race in WorldLayout.Realms do
					local base = zone.bases[race]
					t.ok(base ~= nil, `{id} has a {race} camp`)
					local safe = safeZone(base.safeZone)
					t.ok(safe ~= nil and safe.race == race, `{id} {race} camp safe zone belongs to {race}`)
				end
			end
			t.eq(count, 2, "Desert and Jungle")
		end)

		t.it("zones never overlap each other, the capitals or the dungeon slots", function()
			local list = {}
			for _, zone in WorldLayout.WarZones do
				table.insert(list, zone)
				t.ok(not WorldLayout.isInDungeonRegion(zone.center[1] + zone.size / 2), zone.id)
				t.eq(WorldLayout.warZoneAt(zone.center[1], zone.center[3]), zone)
			end
			for i = 1, #list do
				for j = i + 1, #list do
					local a, b = list[i], list[j]
					local gap = math.abs(a.center[1] - b.center[1]) - (a.size + b.size) / 2
					t.ok(gap > 1000, `{a.id} and {b.id} are {gap} studs apart`)
				end
			end
			for _, realm in WorldLayout.Realms do
				t.eq(WorldLayout.warZoneAt(realm.platformCenter[1], realm.platformCenter[3]), nil, realm.race)
			end
		end)

		t.it("camps sit on flat, dry plateaus at the zone's base height", function()
			for id, zone in WorldLayout.WarZones do
				for race, base in zone.bases do
					for _, offset in { { 0, 0 }, { 30, 0 }, { 0, -30 }, { -25, 20 }, { 0, 38 } } do
						local h, _, water =
							WarZoneTerrain.sample(zone, base.x + offset[1], base.z + offset[2])
						t.ok(math.abs(h - zone.baseHeight) < 0.6, `{id} {race} camp is flat: {h}`)
						t.ok(water == nil or h > water + 2, `{id} {race} camp is dry`)
					end
				end
			end
		end)

		t.it("arrival and the return portal are inside your own camp's safe zone", function()
			for id, zone in WorldLayout.WarZones do
				for race, base in zone.bases do
					local safe = safeZone(base.safeZone)
					for _, spot in { { 12, -6 }, { 12, 6 }, { -(base.radius - 14), 0 } } do
						local p = WorldLayout.basePoint(zone, race, spot[1], spot[2])
						t.ok(
							p ~= nil and ZoneGeometry.contains(safe.volume, { p[1], p[2] + 3, p[3] }),
							`{id} {race} spot {spot[1]},{spot[2]}`
						)
					end
				end
			end
		end)

		t.it("creature camps stand on dry ground, inside the rim, clear of the realm camps", function()
			for id, zone in WorldLayout.WarZones do
				local half = zone.size / 2 - 70
				for _, camp in zone.camps do
					t.ok(EnemyDefinitions.get(camp.enemy) ~= nil, `{id}: {camp.enemy}`)
					t.ok(camp.count >= 1 and camp.count <= 4)
					t.ok(
						math.abs(camp.x) < half and math.abs(camp.z) < half,
						`{id} {camp.enemy} inside the rim`
					)
					for race, base in zone.bases do
						local d = math.sqrt((camp.x - base.x) ^ 2 + (camp.z - base.z) ^ 2)
						t.ok(d > base.radius + 60, `{id} {camp.enemy} clear of the {race} camp`)
					end
					-- The camp spreads its creatures up to 7 studs around the spot.
					for _, o in { { 0, 0 }, { 7, 0 }, { -7, 0 }, { 0, 7 }, { 0, -7 } } do
						local h, _, water = WarZoneTerrain.sample(zone, camp.x + o[1], camp.z + o[2])
						t.ok(water == nil or h > water + 1, `{id} {camp.enemy} at {camp.x},{camp.z} is dry`)
					end
				end
			end
		end)
	end)

	t.describe("Jungle Rift", function()
		local zone = WorldLayout.WarZones.JungleRift
		local T = JungleTerrain

		t.it("uses the jungle terrain, atmosphere and plateau height", function()
			t.eq(zone.terrain, "Jungle")
			t.eq(zone.atmosphere, "Jungle")
			t.eq(zone.baseHeight, T.BASE_HEIGHT)
			for _, b in T.BASES do
				local matched = false
				for _, base in zone.bases do
					matched = matched or (base.x == b[1] and base.z == b[2])
				end
				t.ok(matched, `plateau {b[1]},{b[2]} has a camp`)
			end
			for race, base in zone.bases do
				t.ok(base.radius < T.BASE_RADIUS, `{race} barrier inside the plateau`)
			end
		end)

		t.it("the upper river runs across the highland to the waterfall lip", function()
			for x = T.SPRING_X + 40, T.LIP_X, 20 do
				local riverZ, halfWidth, upper = T.riverAt(x)
				t.ok(riverZ ~= nil and upper, `upper river at {x}`)
				local h, _, water = T.sample(x, riverZ, zone.size)
				t.eq(water, T.HIGH_WATER, `upper water at {x}`)
				t.ok(h < water - 3, `upper channel deep enough at {x}: {h}`)
				-- Banks hold the water in.
				local bank = T.sample(x, riverZ + halfWidth + 8, zone.size)
				t.ok(bank > T.HIGH_WATER, `upper bank at {x}: {bank}`)
			end
		end)

		t.it("the waterfall drops at least 40 studs into a deep plunge pool", function()
			local lip, _, lipWater = T.sample(T.LIP_X - 4, 0, zone.size)
			local below, _, poolWater = T.sample(T.CLIFF_X + 10, 0, zone.size)
			t.ok(lipWater ~= nil and poolWater ~= nil and lipWater - poolWater >= 40, "drop height")
			t.ok(lipWater ~= nil and lip < lipWater, "water at the lip")
			t.ok(below < T.WATER_LEVEL - 6, `pool below the falls: {below}`)
			local pc = T.POOL_CENTER
			t.ok(T.sample(pc[1], pc[2], zone.size) < T.WATER_LEVEL - 6, "pool centre is deep")
			-- The cliff stands beside the falls.
			t.ok(T.sample(T.CLIFF_X - 10, 40, zone.size) > 40, "cliff north of the falls")
			t.ok(T.sample(T.CLIFF_X - 10, -40, zone.size) > 40, "cliff south of the falls")
		end)

		t.it("the lower river flows from the pool to the east rim", function()
			for x = T.POOL_CENTER[1] + T.POOL_RADIUS, T.RIVER_END_X - 50, 20 do
				local riverZ, _, upper = T.riverAt(x)
				t.ok(riverZ ~= nil and not upper, `lower river at {x}`)
				local h, _, water = T.sample(x, riverZ, zone.size)
				t.eq(water, T.WATER_LEVEL)
				t.ok(h < T.WATER_LEVEL - 3, `lower channel deep at {x}: {h}`)
			end
		end)

		t.it("nothing floods: only the river and the pool lie below their water line", function()
			local pc = T.POOL_CENTER
			for x = -430, 430, 10 do
				for z = -430, 430, 10 do
					local h, _, water = T.sample(x, z, zone.size)
					if water and h < water then
						local riverZ, halfWidth = T.riverAt(x)
						local inRiver = riverZ ~= nil and math.abs(z - riverZ) < halfWidth + 6
						local inPool = math.sqrt((x - pc[1]) ^ 2 + (z - pc[2]) ^ 2) < T.POOL_RADIUS + 6
						t.ok(inRiver or inPool, `unexpected water at {x},{z} (ground {h}, water {water})`)
					end
				end
			end
		end)

		t.it("the plaza around the pool is flat open ground", function()
			for _, angle in { -60, -30, 30, 60, 90, -90 } do
				local a = math.rad(angle)
				local x, z = T.POOL_CENTER[1] + math.cos(a) * 54, math.sin(a) * 54
				local riverZ, halfWidth = T.riverAt(x)
				if riverZ == nil or math.abs(z - riverZ) > halfWidth + 8 then
					local h = T.sample(x, z, zone.size)
					t.ok(math.abs(h) < 1, `plaza at {angle} degrees: {h}`)
				end
			end
		end)

		t.it("every bridge spans the river between dry banks", function()
			t.ok(#T.BRIDGES >= 4, "enough crossings")
			local upper, lower = 0, 0
			for _, b in T.BRIDGES do
				local riverZ, halfWidth, isUpper = T.riverAt(b.x)
				t.ok(riverZ ~= nil, `bridge at {b.x} is over the river`)
				t.eq(isUpper, b.upper, `bridge at {b.x} stretch`)
				if isUpper then
					upper += 1
				else
					lower += 1
				end
				local level = if isUpper then T.HIGH_WATER else T.WATER_LEVEL
				for _, side in { -1, 1 } do
					local h = T.sample(b.x, riverZ + side * (halfWidth + 7), zone.size)
					t.ok(h > level and h < level + 14, `bridge {b.x} bank {side}: {h}`)
				end
			end
			t.ok(upper >= 1 and lower >= 2, "crossings on both stretches")
		end)

		t.it("the rim closes the zone and the camps are far from the falls", function()
			local edge = zone.size / 2 - 5
			for _, p in { { edge, 0 }, { -edge, 0 }, { 0, edge }, { 0, -edge } } do
				t.ok(T.sample(p[1], p[2], zone.size) > 50, `rim at {p[1]},{p[2]}`)
			end
			for race, base in zone.bases do
				t.ok(
					math.sqrt(base.x ^ 2 + base.z ^ 2) > T.PLAZA_RADIUS + 150,
					`{race} camp far from the pool`
				)
			end
		end)

		t.it("the jungle creatures are fair level 10+ field creatures", function()
			for _, id in { "JungleProwler", "Thorncrawler", "MossbackGolem" } do
				local enemy = EnemyDefinitions.get(id)
				t.ok(enemy ~= nil, id)
				t.ok(enemy.level >= Defaults.PvP.MinLevel and enemy.level <= 15, `{id} level`)
			end
		end)
	end)
end
