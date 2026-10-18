--[[
	Creature flight (PLAN.md D-60): when winged creatures take off, wheel,
	dive and land (Logic/MobFlight).
]]

local load = require("../loader")
local MobFlight = load("src/shared/Logic/MobFlight")

local function input(overrides: { [string]: any }): any
	local base = {
		now = 0,
		chasing = true,
		stunned = false,
		altitude = 0,
		headroom = 40,
		scale = 2,
		arrived = false,
		roll = 0.3,
	}
	for k, v in overrides do
		base[k] = v
	end
	return base
end

return function(t)
	t.describe("MobFlight", function()
		t.it("only winged creatures fly; the sprite just hovers", function()
			t.ok(MobFlight.canFly("Guardian", { "Wings", "Horns" }))
			t.ok(MobFlight.canFly("Wolf", { "Mane", "Wings" }))
			t.ok(not MobFlight.canFly("Wolf", { "Mane" }))
			t.ok(not MobFlight.canFly("Golem", nil))
			t.ok(not MobFlight.canFly("Sprite", { "Wings" }))
		end)

		t.it("takes off only once ready, while chasing, with room overhead", function()
			local state = MobFlight.initial(0, 0.5)
			t.eq(state.mode, "Ground")
			t.ok(state.readyAt >= 3, "not straight away")
			t.eq(MobFlight.step(state, input({ now = 1 })).mode, "Ground", "not ready yet")
			t.eq(
				MobFlight.step(state, input({ now = 10, chasing = false })).mode,
				"Ground",
				"nothing to chase"
			)
			t.eq(MobFlight.step(state, input({ now = 10, headroom = 6 })).mode, "Ground", "low ceiling")
			t.eq(MobFlight.step(state, input({ now = 10, stunned = true })).mode, "Ground", "stunned")
			local up = MobFlight.step(state, input({ now = 10 }))
			t.eq(up.mode, "Rise")
			t.ok(MobFlight.isAirborne(up.mode))
			t.eq(up.orbitDir, -1)
		end)

		t.it("rises, wheels, warns, dives, lands, then stays grounded a while", function()
			local state = MobFlight.step(MobFlight.initial(0, 0), input({ now = 10 }))
			local cruise = MobFlight.cruiseHeight(2, 40)
			state = MobFlight.step(state, input({ now = 10.5, altitude = cruise * 0.5 }))
			t.eq(state.mode, "Rise", "still climbing")
			state = MobFlight.step(state, input({ now = 11, altitude = cruise }))
			t.eq(state.mode, "Circle")
			state = MobFlight.step(state, input({ now = 12, altitude = cruise }))
			t.eq(state.mode, "Circle", "wheels a few seconds")
			state = MobFlight.step(state, input({ now = 16, altitude = cruise }))
			t.eq(state.mode, "Warn", "the landing spot is marked first")
			state =
				MobFlight.step(state, input({ now = 16 + MobFlight.WARN_SECONDS * 0.5, altitude = cruise }))
			t.eq(state.mode, "Warn")
			state =
				MobFlight.step(state, input({ now = 16 + MobFlight.WARN_SECONDS + 0.01, altitude = cruise }))
			t.eq(state.mode, "Dive")
			state = MobFlight.step(state, input({ now = 17.3, altitude = 1, arrived = true }))
			t.eq(state.mode, "Land")
			state = MobFlight.step(state, input({ now = 17.6, altitude = 0.2 }))
			t.eq(state.mode, "Ground")
			t.ok(state.readyAt >= 17.6 + MobFlight.GROUND_SECONDS, "grounded long enough for melee to answer")
			t.eq(MobFlight.step(state, input({ now = 20 })).mode, "Ground")
		end)

		t.it("comes down when stunned or when the target is gone", function()
			local airborne = { mode = "Circle", untilTime = 99, readyAt = 0, orbitDir = 1 } :: any
			t.eq(MobFlight.step(airborne, input({ now = 5, altitude = 10, stunned = true })).mode, "Land")
			t.eq(MobFlight.step(airborne, input({ now = 5, altitude = 10, chasing = false })).mode, "Land")
			-- A dive that never arrives still ends.
			local diving = { mode = "Dive", untilTime = 6, readyAt = 0, orbitDir = 1 } :: any
			t.eq(MobFlight.step(diving, input({ now = 6.1, altitude = 4 })).mode, "Land")
			-- A landing that can't reach the ground still ends.
			local landing = { mode = "Land", untilTime = 8, readyAt = 0, orbitDir = 1 } :: any
			t.eq(MobFlight.step(landing, input({ now = 8.1, altitude = 3 })).mode, "Ground")
		end)

		t.it("cruises higher when bigger, but never into the ceiling", function()
			t.ok(MobFlight.cruiseHeight(3, 100) > MobFlight.cruiseHeight(1, 100))
			t.ok(MobFlight.cruiseHeight(4, 14) <= 11)
		end)
	end)
end
