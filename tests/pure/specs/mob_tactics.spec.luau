--[[
	Creature behaviour (PLAN.md D-52): how each kind closes in while
	chasing (Logic/MobTactics).
]]

local load = require("../loader")
local MobTactics = load("src/shared/Logic/MobTactics")

return function(t)
	t.describe("MobTactics", function()
		t.it("each body plan gets its own way of closing in", function()
			t.eq(MobTactics.kindFor("Wolf"), "Pack")
			t.eq(MobTactics.kindFor("Serpent"), "Ambush")
			t.eq(MobTactics.kindFor("Golem"), "Brute")
			t.eq(MobTactics.kindFor("Guardian"), "Brute")
			t.eq(MobTactics.kindFor("Beetle"), "Skitter")
			t.eq(MobTactics.kindFor("Sprite"), "Direct")
		end)

		t.it("a pack predator circles, then pounces, then won't circle again for a while", function()
			local state = MobTactics.initial()
			local reach = 6
			state = MobTactics.step("Pack", state, 0, reach * 2.5, reach, 0.3)
			t.eq(state.mode, "Circle")
			t.eq(state.orbitDir, -1)
			t.eq(MobTactics.speedScale("Pack", state.mode), 0.75)
			state = MobTactics.step("Pack", state, 0.5, reach * 2.5, reach, 0.3)
			t.eq(state.mode, "Circle", "still stalking")
			state = MobTactics.step("Pack", state, 3, reach * 2.5, reach, 0.3)
			t.eq(state.mode, "Pounce")
			t.ok(MobTactics.speedScale("Pack", "Pounce") > 1.5, "pounce is a burst")
			-- In reach: back to the normal approach (MobBrain winds up).
			state = MobTactics.step("Pack", state, 3.2, reach, reach, 0.3)
			t.eq(state.mode, "Approach")
			state = MobTactics.step("Pack", state, 4, reach * 2.5, reach, 0.3)
			t.eq(state.mode, "Approach", "cooldown: no endless circling")
			state =
				MobTactics.step("Pack", state, 3 + MobTactics.TACTIC_COOLDOWN + 0.1, reach * 2.5, reach, 0.7)
			t.eq(state.mode, "Circle")
			t.eq(state.orbitDir, 1)
		end)

		t.it("a pack predator out of stalking range just runs in", function()
			local state = MobTactics.step("Pack", MobTactics.initial(), 0, 6 * 5, 6, 0.3)
			t.eq(state.mode, "Approach")
		end)

		t.it("a serpent holds coiled just out of reach, then lunges", function()
			local state = MobTactics.step("Ambush", MobTactics.initial(), 0, 9, 7, 0.5)
			t.eq(state.mode, "Hold")
			t.eq(MobTactics.speedScale("Ambush", "Hold"), 0)
			state = MobTactics.step("Ambush", state, 2, 9, 7, 0.5)
			t.eq(state.mode, "Pounce")
			t.ok(MobTactics.speedScale("Ambush", "Approach") < 1, "glides in")
		end)

		t.it("a brute charges a target that keeps its distance, and stops near it", function()
			local state = MobTactics.step("Brute", MobTactics.initial(), 0, 40, 9, 0.5)
			t.eq(state.mode, "Charge")
			state = MobTactics.step("Brute", state, 0.5, 9, 9, 0.5)
			t.eq(state.mode, "Approach")
			state = MobTactics.step("Brute", state, 1, 40, 9, 0.5)
			t.eq(state.mode, "Approach", "charge cooldown")
		end)

		t.it("modes never stick: every timed mode ends", function()
			for _, kind in { "Pack", "Ambush", "Brute", "Skitter", "Direct" } do
				local state = MobTactics.initial()
				for step = 0, 400 do
					local now = step * 0.125
					state =
						MobTactics.step(kind :: any, state, now, 6 * (2 + math.sin(now)), 6, (step % 10) / 10)
					if state.mode ~= "Approach" then
						t.ok(state.untilTime - now <= 3, `{kind} {state.mode} ends`)
					end
				end
			end
		end)
	end)
end
