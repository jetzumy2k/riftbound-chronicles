local load = require("../loader")
local CapitalTerrain = load("src/shared/Logic/CapitalTerrain")
local WorldLayout = load("src/shared/Definitions/WorldLayout")

return function(t)
	t.describe("CapitalTerrain", function()
		local angel = WorldLayout.Realms.Angel
		local c = angel.platformCenter
		local bottom = c[2] - angel.platformSize[2] / 2
		local half = angel.platformSize[1] / 2
		local balls, tips = CapitalTerrain.island(c[1], bottom, c[3], half)

		t.it("the floating island never pokes through the platform", function()
			t.ok(#balls > 100, `balls: {#balls}`)
			for _, b in balls do
				t.ok(b.y + b.r <= bottom + 1.001, `ball top {b.y + b.r} above {bottom + 1}`)
				local d = math.sqrt((b.x - c[1]) ^ 2 + (b.z - c[3]) ^ 2)
				t.ok(d + b.r < half * 1.3, `ball reaches {d + b.r} from the centre`)
				t.ok(b.material == "Slate" or b.material == "Rock" or b.material == "Basalt", b.material)
			end
		end)

		t.it("the island tapers down to hanging spires", function()
			local lowest = math.huge
			for _, b in balls do
				lowest = math.min(lowest, b.y - b.r)
			end
			t.ok(bottom - lowest > CapitalTerrain.ISLAND_DEPTH * 0.8, `depth {bottom - lowest}`)
			t.eq(#tips, CapitalTerrain.SPIRES)
			for _, tip in tips do
				t.ok(tip[2] < bottom - 60, `spire tip at {tip[2]}`)
			end
			-- Same input, same island.
			local again = CapitalTerrain.island(c[1], bottom, c[3], half)
			t.eq(#again, #balls)
			t.eq(again[10].x, balls[10].x)
		end)

		t.it("the volcano has a crater below its rim and ends at its foot", function()
			local v = CapitalTerrain.VOLCANO
			local centre = CapitalTerrain.volcano(0, 0)
			local rimHigh = 0
			for i = 0, 11 do
				local a = i / 12 * math.pi * 2
				local h = CapitalTerrain.volcano(math.cos(a) * v.craterRadius, math.sin(a) * v.craterRadius)
				rimHigh = math.max(rimHigh, h)
				local far =
					CapitalTerrain.volcano(math.cos(a) * v.radius * 1.15, math.sin(a) * v.radius * 1.15)
				t.eq(far, 0)
			end
			t.ok(centre < rimHigh - 20, `crater {centre} vs rim {rimHigh}`)
			t.ok(rimHigh > v.height * 0.6 and rimHigh <= v.height, `rim {rimHigh}`)
		end)

		t.it("lava channels run down the flanks", function()
			local v = CapitalTerrain.VOLCANO
			for n = 0, v.channels - 1 do
				local r = v.radius * 0.5
				local a = CapitalTerrain.channelAngle(n, r)
				local _, material = CapitalTerrain.volcano(math.cos(a) * r, math.sin(a) * r)
				t.eq(material, "CrackedLava")
			end
		end)

		t.it("Emberdeep's volcano stands beyond the training yard", function()
			local devil = WorldLayout.Realms.Devil
			local yardEnd = devil.platformSize[3] / 2 + WorldLayout.TrainingYard.depth
			-- CapitalBuilder places it 700 studs forward; the foot can swell 12%.
			t.ok(700 - CapitalTerrain.VOLCANO.radius * 1.12 > yardEnd + 40, "clear of the yard")
		end)
	end)
end
