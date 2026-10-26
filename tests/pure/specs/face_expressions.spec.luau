--[[
	Facial expression states (Phase 15, D-79): which expression a character
	shows, how the face eases toward it, and blinking.
]]

local load = require("../loader")
local FaceExpressions = load("src/shared/Logic/FaceExpressions")

local NONE = math.huge

local function situation(overrides: { [string]: any }?): any
	local s = { defeated = false, hurtFor = NONE, acting = false, happyFor = NONE, fightingFor = NONE }
	for key, value in overrides or {} do
		s[key] = value
	end
	return s
end

return function(t)
	t.describe("FaceExpressions", function()
		t.it("picks by priority: defeated > pain > effort > happy > focused > neutral", function()
			t.eq(FaceExpressions.pick(situation()), "Neutral")
			t.eq(FaceExpressions.pick(situation({ fightingFor = 2 })), "Focused")
			t.eq(FaceExpressions.pick(situation({ fightingFor = 9 })), "Neutral", "focus fades")
			t.eq(FaceExpressions.pick(situation({ happyFor = 1, fightingFor = 2 })), "Happy")
			t.eq(FaceExpressions.pick(situation({ acting = true, happyFor = 1 })), "Effort")
			t.eq(FaceExpressions.pick(situation({ hurtFor = 0.2, acting = true })), "Pain")
			t.eq(FaceExpressions.pick(situation({ hurtFor = 1, acting = true })), "Effort", "pain is short")
			t.eq(FaceExpressions.pick(situation({ defeated = true, hurtFor = 0 })), "Defeated")
		end)

		t.it("every expression only uses known controls with weights in 0..1", function()
			local known = {}
			for _, control in FaceExpressions.CONTROLS do
				known[control] = true
			end
			for _, name in FaceExpressions.NAMES do
				local weights = FaceExpressions.EXPRESSIONS[name]
				t.ok(weights ~= nil, name)
				for control, value in weights do
					t.ok(known[control], `{name}.{control}`)
					t.ok(value >= 0 and value <= 1, `{name}.{control} range`)
				end
			end
		end)

		t.it("eases toward the target without overshoot and clears unused controls", function()
			local face = FaceExpressions.step({ JawDrop = 0.5 }, "Happy", 0.05, 0)
			local smile = face.LeftLipCornerPuller
			t.ok(smile > 0 and smile < 0.8, "partway after one frame")
			t.ok(face.JawDrop < 0.5, "unused control eases back to 0")
			for _ = 1, 200 do
				FaceExpressions.step(face, "Happy", 0.05, 0)
			end
			t.ok(math.abs(face.LeftLipCornerPuller - 0.8) < 1e-3, "settles on the target")
			t.ok(face.JawDrop < 1e-3)
			-- A huge frame lands exactly on the target, never past it.
			FaceExpressions.step(face, "Neutral", 100, 0)
			t.ok(face.LeftLipCornerPuller >= 0 and face.LeftLipCornerPuller < 1e-6)
		end)

		t.it("blinks close then open, and never open eyes the expression keeps shut", function()
			t.eq(FaceExpressions.blinkAt(-0.1), 0)
			t.eq(FaceExpressions.blinkAt(FaceExpressions.BLINK_SECONDS + 0.01), 0)
			t.ok(
				math.abs(FaceExpressions.blinkAt(FaceExpressions.BLINK_SECONDS / 2) - 1) < 1e-9,
				"shut mid-blink"
			)
			local face = FaceExpressions.step({}, "Neutral", 0.05, 1)
			t.eq(face.LeftEyeClosed, 1)
			t.eq(face.RightEyeClosed, 1)
			local shut = { LeftEyeClosed = 0.95, RightEyeClosed = 0.95 }
			FaceExpressions.step(shut, "Defeated", 0.05, 0.2)
			t.ok(shut.LeftEyeClosed >= 0.9, "a blink never opens fainted eyes")
		end)

		t.it("pain and defeat react faster than the other states", function()
			t.ok(FaceExpressions.rateFor("Pain") > FaceExpressions.rateFor("Focused"))
			t.ok(FaceExpressions.rateFor("Defeated") > FaceExpressions.rateFor("Happy"))
		end)

		t.it("anime faces (D-103): every expression reads clearly on the Part-built face", function()
			local function pose(name)
				return FaceExpressions.animePose(FaceExpressions.EXPRESSIONS[name])
			end
			local neutral = pose("Neutral")
			t.eq(neutral.eye, 1)
			t.eq(neutral.mouthOpen, 1)
			t.eq(neutral.browTilt, 0)
			t.ok(pose("Defeated").eye <= 0.1, "fainted: eyes shut")
			t.ok(pose("Pain").eye < 0.5 and pose("Pain").mouthOpen > 2, "pain: squint and open mouth")
			t.ok(pose("Pain").browTilt < 0, "pain: worried brows")
			t.ok(pose("Effort").browTilt > 10 and pose("Effort").mouthOpen > 2, "effort: angry brows, shout")
			t.ok(pose("Happy").mouthLift > 0 and pose("Happy").mouthWide > 1, "happy: smile")
			t.ok(pose("Focused").browTilt > 0 and pose("Focused").eye < 1, "focused: brows down")
			-- A blink shuts the eyes whatever the expression.
			local w = FaceExpressions.step({}, "Neutral", 1, 1)
			t.ok(FaceExpressions.animePose(w).eye <= 0.05)
			-- Never out of range, even for wild weights.
			local wild = FaceExpressions.animePose({ JawDrop = 5, LeftEyeClosed = -3, LeftLipStretcher = 9 })
			t.ok(wild.mouthOpen <= 6 and wild.eye <= 1 and wild.mouthWide <= 1.8)
		end)
	end)
end
