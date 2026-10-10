local load = require("../loader")
local MotionMath = load("src/shared/Logic/MotionMath")

local D = MotionMath.Defaults

return function(t)
	t.describe("easing", function()
		t.it("alpha is 0 at dt 0 and approaches 1", function()
			t.eq(MotionMath.alpha(8, 0), 0)
			t.ok(MotionMath.alpha(8, 1 / 60) > 0 and MotionMath.alpha(8, 1 / 60) < 0.2)
			t.ok(MotionMath.alpha(8, 5) > 0.999)
		end)

		t.it("is frame-rate independent (2 half steps == 1 full step)", function()
			local oneStep = MotionMath.damp(0, 1, 9, 1 / 30)
			local twoSteps = MotionMath.damp(MotionMath.damp(0, 1, 9, 1 / 60), 1, 9, 1 / 60)
			t.near(oneStep, twoSteps, 1e-9)
		end)

		t.it("acceleration reaches ~90% in about a third of a second, stopping is quicker", function()
			local speed = 0
			for _ = 1, 21 do -- 0.35 s at 60 fps
				speed = MotionMath.damp(speed, 1, D.accelRate, 1 / 60)
			end
			t.ok(speed > 0.88 and speed < 0.93, tostring(speed))
			local stopping = 1
			for _ = 1, 15 do -- 0.25 s
				stopping = MotionMath.damp(stopping, 0, D.decelRate, 1 / 60)
			end
			t.ok(stopping < 0.12, tostring(stopping))
		end)
	end)

	t.describe("angles", function()
		t.it("angleDelta takes the short way round", function()
			t.near(MotionMath.angleDelta(math.rad(170), math.rad(-170)), math.rad(20), 1e-9)
			t.near(MotionMath.angleDelta(math.rad(-170), math.rad(170)), math.rad(-20), 1e-9)
			t.near(MotionMath.angleDelta(0, math.rad(90)), math.rad(90), 1e-9)
		end)

		t.it("dampAngle never overshoots across the wrap", function()
			local yaw = math.rad(175)
			for _ = 1, 120 do
				yaw = MotionMath.dampAngle(yaw, math.rad(-175), D.turnRate, 1 / 60)
			end
			t.near(MotionMath.angleDelta(yaw, math.rad(-175)), 0, 1e-3)
		end)

		t.it("yawOf matches Roblox facing (-Z forward, +yaw = left)", function()
			t.near(MotionMath.yawOf(0, -1), 0, 1e-9)
			t.near(MotionMath.yawOf(-1, 0), math.rad(90), 1e-9)
			t.near(MotionMath.yawOf(1, 0), math.rad(-90), 1e-9)
		end)
	end)

	t.describe("lean", function()
		t.it("standing still does not lean", function()
			local pitch, roll = MotionMath.lean(0, 0, 0)
			t.eq(pitch, 0)
			t.eq(roll, 0)
		end)

		t.it("leans forward when running and accelerating, back when braking", function()
			local cruising = MotionMath.lean(1, 0, 0)
			local accelerating = MotionMath.lean(1, 20, 0)
			local braking = MotionMath.lean(0.5, -60, 0)
			t.ok(cruising > 0)
			t.ok(accelerating > cruising)
			t.ok(braking < 0)
		end)

		t.it("rolls into turns and is clamped", function()
			local _, left = MotionMath.lean(1, 0, 3)
			local _, right = MotionMath.lean(1, 0, -3)
			t.ok(left > 0 and right < 0)
			local pitch, roll = MotionMath.lean(1, 1000, 1000)
			t.near(pitch, D.maxLeanPitch, 1e-9)
			t.near(roll, D.maxLeanRoll, 1e-9)
		end)
	end)

	t.describe("head look", function()
		t.it("splits yaw between neck and waist", function()
			local neckYaw, _, waistYaw = MotionMath.headLook(0, math.rad(40), 0)
			t.near(neckYaw + waistYaw, math.rad(40), 1e-9)
			t.ok(waistYaw < neckYaw)
		end)

		t.it("clamps to natural limits and relaxes when the camera faces the character", function()
			local neckYaw, pitch, waistYaw = MotionMath.headLook(0, math.rad(100), math.rad(80))
			t.near(neckYaw + waistYaw, D.headYawLimit, 1e-9)
			t.near(pitch, D.headPitchLimit, 1e-9)
			local a, b, c = MotionMath.headLook(0, math.rad(170), 0)
			t.eq(a + b + c, 0)
		end)
	end)

	t.describe("landing", function()
		t.it("dips more for bigger falls, capped at the maximum", function()
			t.eq(MotionMath.landingDip(0), 0)
			t.ok(MotionMath.landingDip(10) < MotionMath.landingDip(40))
			t.near(MotionMath.landingDip(500), D.landingMaxDip, 1e-9)
		end)
	end)
end
