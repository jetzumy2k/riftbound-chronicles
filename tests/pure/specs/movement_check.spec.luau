local load = require("../loader")
local MovementCheck = load("src/shared/Logic/MovementCheck")
local Defaults = load("src/server/Config/Defaults")

local C = Defaults.AntiExploit
local DT = 0.1
local WALK = 16

local function sample(x, y, z, grounded, airTime)
	return { position = { x, y, z }, grounded = grounded ~= false, airTime = airTime or 0 }
end

return function(t)
	t.it("normal walking produces no points", function()
		local r = MovementCheck.evaluate(sample(0, 0, 0), sample(1.6, 0, 0), DT, WALK, nil, C)
		t.eq(r.points, 0)
	end)

	t.it("tolerates lag bursts up to the tolerance", function()
		-- 0.1 s at 16 studs/s = 1.6 studs; tolerance adds 1.6 studs at 0.1 s.
		local r = MovementCheck.evaluate(sample(0, 0, 0), sample(3.5, 0, 0), DT, WALK, nil, C)
		t.eq(r.points, 0)
	end)

	t.it("flags speed hacks (WalkSpeed 100)", function()
		local r = MovementCheck.evaluate(sample(0, 0, 0), sample(10, 0, 0), DT, WALK, nil, C)
		t.eq(r.points, 1)
		t.ok(string.find(r.reasons[1], "speed", 1, true) ~= nil)
	end)

	t.it("flags teleports as a heavy violation", function()
		local r = MovementCheck.evaluate(sample(0, 0, 0), sample(500, 0, 0), DT, WALK, nil, C)
		t.eq(r.teleport, true)
		t.ok(r.points >= C.StrikePoints)
	end)

	t.it("grants allowances: dashes and travel grace", function()
		local dash = MovementCheck.evaluate(
			sample(0, 0, 0),
			sample(6, 0, 0),
			DT,
			WALK,
			{ extraSpeed = 50, grace = false },
			C
		)
		t.eq(dash.points, 0)
		local travel = MovementCheck.evaluate(
			sample(0, 0, 0),
			sample(900, 0, 0),
			DT,
			WALK,
			{ extraSpeed = 0, grace = true },
			C
		)
		t.eq(travel.points, 0)
	end)

	t.it("flags hovering after the airtime limit, but not falling", function()
		local hover =
			MovementCheck.evaluate(sample(0, 10, 0, false, 3), sample(0, 10, 0, false, 3.5), DT, WALK, nil, C)
		t.eq(hover.points, 1)
		local fall =
			MovementCheck.evaluate(sample(0, 50, 0, false, 3), sample(0, 45, 0, false, 3.5), DT, WALK, nil, C)
		t.eq(fall.points, 0)
	end)

	t.it("ignores vertical speed (jumps and falls are not speed violations)", function()
		local r = MovementCheck.evaluate(sample(0, 0, 0), sample(0, -30, 0, false, 0.2), DT, WALK, nil, C)
		t.eq(r.points, 0)
	end)

	t.it("points drain over time and never go negative", function()
		t.eq(MovementCheck.drain(3, 1), 2)
		t.eq(MovementCheck.drain(0.5, 2), 0)
	end)
end
