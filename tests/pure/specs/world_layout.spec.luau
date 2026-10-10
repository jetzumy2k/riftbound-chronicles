local load = require("../loader")
local Enums = load("src/shared/Enums")
local WorldLayout = load("src/shared/Definitions/WorldLayout")
local ZoneGeometry = load("src/shared/Logic/ZoneGeometry")

local function distance(a, b)
	local dx, dy, dz = a[1] - b[1], a[2] - b[2], a[3] - b[3]
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

return function(t)
	t.describe("ZoneGeometry", function()
		local cylinder = { kind = "cylinder", center = { 0, 0, 0 }, radius = 10, halfHeight = 5 }
		local box = { kind = "box", center = { 0, 0, 0 }, size = { 10, 4, 20 } }

		t.it("cylinder containment includes the boundary and excludes outside", function()
			t.ok(ZoneGeometry.contains(cylinder, { 0, 0, 0 }))
			t.ok(ZoneGeometry.contains(cylinder, { 10, 5, 0 }))
			t.ok(not ZoneGeometry.contains(cylinder, { 7.1, 0, 7.1 }))
			t.ok(not ZoneGeometry.contains(cylinder, { 0, 5.01, 0 }))
		end)

		t.it("box containment checks each axis", function()
			t.ok(ZoneGeometry.contains(box, { 5, 2, 10 }))
			t.ok(not ZoneGeometry.contains(box, { 5.1, 0, 0 }))
			t.ok(not ZoneGeometry.contains(box, { 0, 2.1, 0 }))
			t.ok(not ZoneGeometry.contains(box, { 0, 0, -10.1 }))
		end)

		t.it("unknown volume kinds raise", function()
			t.throws(function()
				ZoneGeometry.contains({ kind = "sphere", center = { 0, 0, 0 } }, { 0, 0, 0 })
			end, "unknown volume kind")
		end)

		t.it("findZone returns the containing zone or nil", function()
			local zones = { { id = "A", volume = cylinder }, { id = "B", volume = box } }
			t.eq(ZoneGeometry.findZone(zones, { 0, 0, 0 }).id, "A")
			t.eq(ZoneGeometry.findZone(zones, { 4, 0, 9.9 }).id, "B") -- outside the cylinder, inside the box
			t.eq(ZoneGeometry.findZone(zones, { 100, 0, 0 }), nil)
		end)
	end)

	t.describe("WorldLayout", function()
		t.it("every race has a realm with a matching zone id", function()
			for _, race in Enums.Race do
				local realm = WorldLayout.realmFor(race)
				t.ok(realm ~= nil, race)
				t.eq(realm.race, race)
				t.ok(Enums.has(Enums.Zone, realm.zone), realm.zone)
			end
		end)

		t.it("spawns are deterministic and inside their own race's safe zone", function()
			for _, race in Enums.Race do
				local realm = WorldLayout.realmFor(race)
				local zone = ZoneGeometry.findZone(WorldLayout.SafeZones, realm.spawnPosition)
				t.ok(zone ~= nil, `{race} spawn is not in a safe zone`)
				t.eq(zone.race, race)
				t.eq(zone.id, realm.zone)
				-- Same input, same answer: no randomness in spawn selection.
				t.eq(WorldLayout.realmFor(race), realm)
			end
		end)

		t.it("spawns stand on their platform", function()
			for _, race in Enums.Race do
				local realm = WorldLayout.realmFor(race)
				local top = realm.platformCenter[2] + realm.platformSize[2] / 2
				t.ok(realm.spawnPosition[2] >= top and realm.spawnPosition[2] <= top + 1, race)
				t.ok(math.abs(realm.spawnPosition[1] - realm.platformCenter[1]) < realm.platformSize[1] / 2)
				t.ok(math.abs(realm.spawnPosition[3] - realm.platformCenter[3]) < realm.platformSize[3] / 2)
			end
		end)

		t.it("the two capitals are far apart and their safe zones do not overlap", function()
			local angel = WorldLayout.realmFor("Angel")
			local devil = WorldLayout.realmFor("Devil")
			t.ok(distance(angel.spawnPosition, devil.spawnPosition) > 500)
			t.eq(ZoneGeometry.findZone({ WorldLayout.SafeZones[1] }, devil.spawnPosition), nil)
			t.eq(ZoneGeometry.findZone({ WorldLayout.SafeZones[2] }, angel.spawnPosition), nil)
		end)

		t.it("training dummies stand in the yard, far enough from the safe zone for ranged jobs", function()
			for _, race in Enums.Race do
				local realm = WorldLayout.realmFor(race)
				local center, size = WorldLayout.trainingYard(realm)
				local positions = WorldLayout.dummyPositions(realm)
				t.eq(#positions, WorldLayout.TrainingDummy.countPerRealm)
				local zone = WorldLayout.SafeZones[if race == "Angel" then 1 else 2]
				for _, p in positions do
					t.eq(ZoneGeometry.findZone(WorldLayout.SafeZones, { p[1], p[2] + 3, p[3] }), nil, race)
					t.ok(math.abs(p[1] - center[1]) < size[1] / 2, race)
					t.ok(math.abs(p[3] - center[3]) < size[3] / 2, race)
					-- Open ground outside the safe zone must exceed the longest basic attack (48).
					local dx, dz = p[1] - zone.volume.center[1], p[3] - zone.volume.center[3]
					local gap = math.sqrt(dx * dx + dz * dz) - zone.volume.radius
					t.ok(gap >= 60, `{race}: only {gap} studs outside the safe zone`)
				end
			end
		end)

		t.it("the yard touches the capital platform on the spawn-facing side", function()
			for _, race in Enums.Race do
				local realm = WorldLayout.realmFor(race)
				local center, size = WorldLayout.trainingYard(realm)
				local edgeGap = math.abs(center[3] - realm.platformCenter[3])
					- (size[3] / 2 + realm.platformSize[3] / 2)
				t.near(edgeGap, 0, 1e-6, race)
				local dir = WorldLayout.yardDirection(realm)
				t.ok((center[3] - realm.platformCenter[3]) * dir > 0, race)
			end
		end)

		t.it("the selection camera is outside both safe zones", function()
			t.eq(ZoneGeometry.findZone(WorldLayout.SafeZones, WorldLayout.SelectionCamera.position), nil)
		end)
	end)
end
