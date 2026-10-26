--!strict
--[[
	FaceExpressions — facial expression states for the animated heads
	(Phase 15, PLAN.md D-79; CLAUDE.md §19 "facial expression states").

	Every character wears a realistic animated head (BodyStyle, D-72). Its
	face is moved through FaceControls: each expression below is a set of
	FaceControls weights (0..1); the client eases the face toward the
	expression the character is in (ExpressionController) and blinks on
	its own.

	States, highest priority first:
	  Defeated  eyes closed, brows soft: a stylized faint (no injury, §14)
	  Pain      a short squint and wince after taking a hit
	  Effort    gritted focus during an attack or skill
	  Happy     a smile after levelling up
	  Focused   brows down while in a fight (recent action or hit)
	  Neutral   relaxed

	Display only. Pure module, unit-tested.
]]

local FaceExpressions = {}

export type Weights = { [string]: number }
export type Situation = {
	defeated: boolean,
	hurtFor: number, -- seconds since the last hit (math.huge = none)
	acting: boolean, -- an attack / skill animation is playing
	happyFor: number, -- seconds since the last level-up (math.huge = none)
	fightingFor: number, -- seconds since the last hit or action (math.huge = none)
}

-- How long the short-lived states last (seconds).
FaceExpressions.PAIN_SECONDS = 0.6
FaceExpressions.HAPPY_SECONDS = 3
FaceExpressions.FOCUS_SECONDS = 8

-- Easing rate toward the target face (per second); pain snaps in faster.
FaceExpressions.RATE = 10
FaceExpressions.FAST_RATE = 22

-- Blinks: one every BLINK_MIN..BLINK_MAX seconds, BLINK_SECONDS long.
FaceExpressions.BLINK_MIN = 2.5
FaceExpressions.BLINK_MAX = 5.5
FaceExpressions.BLINK_SECONDS = 0.16

-- Every FaceControls property an expression may move (reset to 0 when
-- unused, so states never leave traces behind).
FaceExpressions.CONTROLS = table.freeze({
	"LeftEyeClosed",
	"RightEyeClosed",
	"LeftLidTightener",
	"RightLidTightener",
	"LeftBrowLowerer",
	"RightBrowLowerer",
	"LeftInnerBrowRaiser",
	"RightInnerBrowRaiser",
	"LeftLipCornerPuller",
	"RightLipCornerPuller",
	"LeftLipCornerDown",
	"RightLipCornerDown",
	"LeftCheekRaiser",
	"RightCheekRaiser",
	"LeftLipStretcher",
	"RightLipStretcher",
	"LeftNoseWrinkler",
	"RightNoseWrinkler",
	"LipsTogether",
	"JawDrop",
})

-- Both sides of the face from one value.
local function both(weights: { [string]: number }): Weights
	local out = {}
	for name, value in weights do
		if name == "LipsTogether" or name == "JawDrop" then
			out[name] = value
		else
			out[`Left{name}`] = value
			out[`Right{name}`] = value
		end
	end
	return table.freeze(out)
end

FaceExpressions.EXPRESSIONS = table.freeze({
	Neutral = both({}),
	Focused = both({ BrowLowerer = 0.45, LidTightener = 0.25, LipsTogether = 0.2 }),
	Effort = both({
		BrowLowerer = 0.8,
		LidTightener = 0.45,
		LipStretcher = 0.45,
		NoseWrinkler = 0.2,
		JawDrop = 0.12,
	}),
	Pain = both({
		LidTightener = 0.75,
		EyeClosed = 0.35,
		BrowLowerer = 0.55,
		InnerBrowRaiser = 0.5,
		LipStretcher = 0.55,
		JawDrop = 0.15,
	}),
	Happy = both({ LipCornerPuller = 0.8, CheekRaiser = 0.5, LidTightener = 0.15 }),
	Defeated = both({ EyeClosed = 0.95, InnerBrowRaiser = 0.35, LipCornerDown = 0.25 }),
}) :: { [string]: Weights }

FaceExpressions.NAMES = table.freeze({ "Defeated", "Pain", "Effort", "Happy", "Focused", "Neutral" })

-- The expression for what the character is doing right now.
function FaceExpressions.pick(s: Situation): string
	if s.defeated then
		return "Defeated"
	elseif s.hurtFor < FaceExpressions.PAIN_SECONDS then
		return "Pain"
	elseif s.acting then
		return "Effort"
	elseif s.happyFor < FaceExpressions.HAPPY_SECONDS then
		return "Happy"
	elseif s.fightingFor < FaceExpressions.FOCUS_SECONDS then
		return "Focused"
	end
	return "Neutral"
end

-- The easing rate toward `name` (pain and defeat react at once).
function FaceExpressions.rateFor(name: string): number
	return if name == "Pain" or name == "Defeated" then FaceExpressions.FAST_RATE else FaceExpressions.RATE
end

--[[
	Eases `current` (every CONTROLS value) toward expression `name` by `dt`
	seconds, in place, and returns it. `blink` (0..1) closes the eyes on top
	(never opening eyes the expression keeps shut).
]]
function FaceExpressions.step(current: Weights, name: string, dt: number, blink: number): Weights
	local target = FaceExpressions.EXPRESSIONS[name] or FaceExpressions.EXPRESSIONS.Neutral
	local k = 1 - math.exp(-FaceExpressions.rateFor(name) * math.max(dt, 0))
	for _, control in FaceExpressions.CONTROLS do
		local value = current[control] or 0
		local goal = target[control] or 0
		current[control] = value + (goal - value) * k
	end
	if blink > 0 then
		for _, eye in { "LeftEyeClosed", "RightEyeClosed" } do
			current[eye] = math.max(current[eye], math.clamp(blink, 0, 1))
		end
	end
	return current
end

--[[
	D-103: the Part-built anime faces (Appearance/Anime/HeadBuilder) have no
	FaceControls, so the same weights are turned into a pose of their parts:
	  eye        how open the eyes are (1 = as built, 0.05 = shut)
	  browLift   brows up (+) / down (-), in eye heights
	  browTilt   extra brow angle in degrees (+ = inner ends down, angry;
	             - = inner ends up, worried)
	  mouthOpen  mouth height multiplier (1 = the built line)
	  mouthWide  mouth width multiplier
	  mouthLift  mouth up (+, smile) / down (-), in eye heights
	The anime style exaggerates: a wince squeezes the eyes, a shout opens
	the mouth wide.
]]
export type AnimePose = {
	eye: number,
	browLift: number,
	browTilt: number,
	mouthOpen: number,
	mouthWide: number,
	mouthLift: number,
}

function FaceExpressions.animePose(w: Weights): AnimePose
	local function get(name: string): number
		return math.clamp(w[name] or 0, 0, 1)
	end
	local closed = math.max(get("LeftEyeClosed"), get("RightEyeClosed"))
	local tight = get("LeftLidTightener")
	local cheek = get("LeftCheekRaiser")
	local lower = get("LeftBrowLowerer")
	local inner = get("LeftInnerBrowRaiser")
	local smile = get("LeftLipCornerPuller")
	local frown = get("LeftLipCornerDown")
	local stretch = get("LeftLipStretcher")
	local jaw = get("JawDrop")
	local together = get("LipsTogether")
	return {
		eye = math.clamp(1 - closed - tight * 0.6 - cheek * 0.45, 0.05, 1),
		browLift = inner * 0.4 - lower * 0.3,
		browTilt = lower * 26 - inner * 36,
		mouthOpen = math.clamp(1 + jaw * 26 + stretch * 3, 1, 6),
		mouthWide = math.clamp(1 + stretch * 0.6 + smile * 0.6 - together * 0.3, 0.6, 1.8),
		mouthLift = (smile - frown) * 0.12,
	}
end

-- Eye closure (0..1) `t` seconds into a blink: closes, then opens.
function FaceExpressions.blinkAt(t: number): number
	local length = FaceExpressions.BLINK_SECONDS
	if t < 0 or t > length then
		return 0
	end
	return 1 - math.abs(t / length * 2 - 1)
end

return table.freeze(FaceExpressions)
