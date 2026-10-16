local load = require("../loader")
local PvPRules = load("src/shared/Logic/PvPRules")
local DesertTerrain = load("src/shared/Logic/DesertTerrain")
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
end
