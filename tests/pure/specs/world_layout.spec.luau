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

	t.describe("city plan", function()
		local ZoneAtmosphere = load("src/shared/Definitions/ZoneAtmosphere")
		local City = WorldLayout.City

		t.it("toWorld maps the local frame onto each platform", function()
			for _, realm in WorldLayout.Realms do
				local origin = WorldLayout.toWorld(realm, { 0, 0, 0 })
				t.eq(origin[1], realm.platformCenter[1])
				t.eq(origin[2], realm.platformCenter[2] + realm.platformSize[2] / 2)
				-- "forward" points at the training yard.
				local ahead = WorldLayout.toWorld(realm, { 0, 0, 10 })
				local yard = WorldLayout.trainingYard(realm)
				t.ok(math.abs(ahead[3] - yard[3]) < math.abs(origin[3] - yard[3]), realm.race)
			end
		end)

		t.it("gates, towers and the landmark sit on the platform", function()
			for _, realm in WorldLayout.Realms do
				local half = realm.platformSize[1] / 2
				for _, gate in City.gates do
					t.ok(
						math.abs(gate.position[1]) <= half - 10 and math.abs(gate.position[3]) <= half - 10,
						gate.id
					)
				end
				for _, tower in City.towers do
					t.ok(math.abs(tower[1]) <= half - 10 and math.abs(tower[3]) <= half - 10)
				end
				local l = City.landmark
				t.ok(math.abs(l.position[3]) + l.depth / 2 <= half, "landmark fits")
			end
		end)

		t.it("gates are unique, away from the spawn and clear of the landmark", function()
			local seen = {}
			local l = City.landmark
			for _, gate in City.gates do
				t.ok(not seen[gate.id], `duplicate gate {gate.id}`)
				seen[gate.id] = true
				local x, z = gate.position[1], gate.position[3]
				t.ok(math.sqrt(x * x + z * z) > 60, `{gate.id} too close to the spawn`)
				local insideLandmark = math.abs(x - l.position[1]) < l.width / 2 + 15
					and math.abs(z - l.position[3]) < l.depth / 2 + 8
				t.ok(not insideLandmark, `{gate.id} overlaps the landmark`)
			end
			t.ok(seen.DesertRift and seen.JungleRift and seen.Dungeons, "all three gates")
		end)

		t.it("atmosphere presets blend and fade with distance", function()
			for _, name in { "Neutral", "Angel", "Devil" } do
				t.ok(ZoneAtmosphere.Presets[name] ~= nil, name)
			end
			t.eq(ZoneAtmosphere.weight(0), 1)
			t.eq(ZoneAtmosphere.weight(ZoneAtmosphere.FULL_RADIUS + ZoneAtmosphere.BLEND_DISTANCE + 1), 0)
			local mid = ZoneAtmosphere.blend(ZoneAtmosphere.get("Angel"), ZoneAtmosphere.get("Devil"), 0.5)
			local angel, devil = ZoneAtmosphere.get("Angel"), ZoneAtmosphere.get("Devil")
			t.near(mid.clockTime, (angel.clockTime + devil.clockTime) / 2, 1e-9)
			t.near(mid.tint[2], (angel.tint[2] + devil.tint[2]) / 2, 1e-9)
			t.eq(ZoneAtmosphere.get("Nowhere"), ZoneAtmosphere.Presets.Neutral)
			-- Readability guards (creator review 2026-10-16): the sun is up in
			-- every capital and glow never swamps the scene.
			for name, preset in ZoneAtmosphere.Presets do
				t.ok(preset.clockTime >= 7 and preset.clockTime <= 17.2, `{name}: sun up`)
				t.ok(preset.bloomIntensity <= 0.6 and preset.bloomThreshold >= 1.6, `{name}: bloom`)
				t.ok(preset.haze <= 1.6 and preset.glare <= 0.4, `{name}: haze`)
				t.ok(math.abs(preset.exposure) <= 0.5, `{name}: exposure`)
			end
			-- The capitals are far enough apart that their atmospheres never overlap.
			local a, d = WorldLayout.Realms.Angel.platformCenter, WorldLayout.Realms.Devil.platformCenter
			local gap = math.sqrt((a[1] - d[1]) ^ 2 + (a[2] - d[2]) ^ 2 + (a[3] - d[3]) ^ 2)
			t.ok(gap >= 2 * ZoneAtmosphere.FULL_RADIUS * 0.5, "capitals apart")
		end)
	end)
end
