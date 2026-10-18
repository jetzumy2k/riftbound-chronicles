--[[
	Creature overhaul stage 1 (PLAN.md D-51): the leg IK every legged
	creature walks with. Planting and sliding over whole gait cycles are
	checked by tools/world/check_gait.luau (needs @lune/roblox).
]]

local load = require("../loader")
local CreatureIK = load("src/shared/Logic/CreatureIK")
local EnemyDefinitions = load("src/shared/Definitions/EnemyDefinitions")

return function(t)
	t.describe("CreatureIK", function()
		t.it("reaches every target in range, knee forward or back, any foot angle", function()
			local seed = 7
			local function rand(lo: number, hi: number): number
				seed = (seed * 48271) % 2147483647
				return lo + (hi - lo) * seed / 2147483647
			end
			for _ = 1, 400 do
				local lengths = { rand(0.8, 2), rand(0.8, 2), rand(0.2, 0.9) }
				local bend = if rand(0, 1) < 0.5 then -1 else 1
				local footAngle = math.rad(rand(-20, 30))
				-- A target the ankle can reach comfortably.
				local reach = (lengths[1] + lengths[2]) * rand(0.45, 0.95)
				local dir = math.rad(rand(-50, 50))
				local forward = reach * math.sin(dir) + lengths[3] * math.sin(footAngle)
				local down = reach * math.cos(dir) + lengths[3] * math.cos(footAngle)
				local a1, a2, a3 = CreatureIK.solve(lengths, bend, footAngle, forward, down)
				local f, d = CreatureIK.tip(lengths, a1, a2, a3)
				t.near(f, forward, 1e-6, "forward")
				t.near(d, down, 1e-6, "down")
				-- The foot bone keeps its angle; the knee bends the asked way.
				t.near(a1 + a2 + a3, footAngle, 1e-9, "foot angle")
				t.ok(bend * a2 <= 0, "knee direction")
			end
		end)

		t.it("out of reach the leg straightens towards the target, never NaN", function()
			local lengths = { 1, 1, 0.4 }
			local a1, a2, a3 = CreatureIK.solve(lengths, 1, 0, 0, 10)
			for _, a in { a1, a2, a3 } do
				t.ok(a == a, "not NaN")
			end
			local _, d = CreatureIK.tip(lengths, a1, a2, a3)
			t.ok(d > 2.2, "nearly straight down")
			-- A target inside the hip folds the leg without breaking.
			local b1, b2 = CreatureIK.solve(lengths, -1, 0, 0, 0.3)
			t.ok(b1 == b1 and b2 == b2, "folded, not NaN")
		end)

		t.it("every legged creature has a skeleton and a gait", function()
			local legged = { Wolf = true, Beetle = true, Golem = true, Guardian = true }
			local count = 0
			for _, enemy in EnemyDefinitions.ById do
				if legged[enemy.body] then
					count += 1
				end
			end
			t.ok(count >= 50, `{count} legged creatures`)
		end)
	end)
end
