--!strict
--[[
	AnimationClips — authored keyframe animation for every character
	(CLAUDE.md §19, PLAN.md D-36).

	Each clip is turned into a Roblox KeyframeSequence (Animation/ClipBuilder)
	and played through the Humanoid's Animator, so Roblox blends it with the
	walk / run / jump animations by priority:

	  Idle      job idle (standing still, full body) / weapon hold (moving,
	            upper body only, so the legs keep walking)
	  Movement  sprint and crouch loops
	  Action    attacks and hit reactions
	  Action4   defeat (held)

	Angles are degrees on R15 joints, positions (px/py/pz) are studs. A joint
	missing from a key is at rest (0) in that key; a joint never mentioned in
	a clip is not animated by it. `ease` shapes the motion *into* that key:
	  In     slow start, fast arrival (strikes)
	  Out    fast start, soft arrival (wind-ups, follow-through)
	  InOut  smooth both ends (recoveries, breathing)
	  Linear / Constant

	Axes (character faces -Z):
	  Shoulder / Hip  +x swings the limb forward/up; Right +z raises it
	                  sideways (Left uses -z); y turns it around the vertical.
	  Elbow           +x bends the forearm forward.   Knee  -x bends back.
	  Wrist           +x tips a held weapon down/forward, -x up/back.
	  Ankle           +x lifts the toes.
	  Waist / Neck    +x leans back / looks up; +y turns left.
	  Root            whole body: -x leans forward, +y turns left; py drops,
	                  pz < 0 steps forward.

	A foot is flat when Root.x + Hip.x + Knee.x + Ankle.x is about 0.

	Markers: `Hit` is when an attack lands or its projectile leaves (server
	damage and VFX timing use it).

	Pure module.
]]

export type JointKey = {
	x: number?,
	y: number?,
	z: number?,
	px: number?,
	py: number?,
	pz: number?,
}
export type Pose = { [string]: JointKey }
export type Ease = "Linear" | "Constant" | "In" | "Out" | "InOut"
export type Key = { t: number, ease: Ease?, pose: Pose }
export type Priority = "Idle" | "Movement" | "Action" | "Action2" | "Action3" | "Action4"
export type Clip = {
	duration: number,
	looped: boolean,
	priority: Priority,
	keys: { Key },
	markers: { [string]: number }?,
	-- Freeze on the last frame instead of ending (defeat).
	hold: boolean?,
}

local AnimationArms = require(script.Parent.AnimationArms)

local AnimationClips = {}

AnimationClips.JOINTS = table.freeze({
	"Root",
	"Waist",
	"Neck",
	"LeftShoulder",
	"RightShoulder",
	"LeftElbow",
	"RightElbow",
	"LeftWrist",
	"RightWrist",
	"LeftHip",
	"RightHip",
	"LeftKnee",
	"RightKnee",
	"LeftAnkle",
	"RightAnkle",
})

-- Joints kept in "upper body" variants (played while walking).
AnimationClips.UPPER_JOINTS = table.freeze({
	"Waist",
	"Neck",
	"LeftShoulder",
	"RightShoulder",
	"LeftElbow",
	"RightElbow",
	"LeftWrist",
	"RightWrist",
})

AnimationClips.EASES = table.freeze({ "Linear", "Constant", "In", "Out", "InOut" })
AnimationClips.PRIORITIES = table.freeze({ "Idle", "Movement", "Action", "Action2", "Action3", "Action4" })

--------------------------------------------------------------------------------
-- Authoring helpers
--------------------------------------------------------------------------------

-- New pose: every joint of `base`, with joints in `over` replaced or merged
-- (`over` axes win, missing axes keep the base value).
local function with(base: Pose, over: Pose?): Pose
	local out: Pose = {}
	for joint, value in base do
		out[joint] = table.clone(value)
	end
	if over then
		for joint, value in over do
			local merged = out[joint] or {}
			for axis, amount in value :: any do
				(merged :: any)[axis] = amount
			end
			out[joint] = merged
		end
	end
	return out
end

-- Mirror of a pose: left <-> right, turns and sideways tilts flipped.
local function mirror(pose: Pose): Pose
	local out: Pose = {}
	for joint, value in pose do
		local other = string.gsub(joint, "^Left", "\0")
		other = string.gsub(other, "^Right", "Left")
		other = string.gsub(other, "%z", "Right")
		local flipped: JointKey = table.clone(value)
		if flipped.y then
			flipped.y = -flipped.y
		end
		if flipped.z then
			flipped.z = -flipped.z
		end
		if flipped.px then
			flipped.px = -flipped.px
		end
		out[other] = flipped
	end
	return out
end

-- New pose with the solved arm joints of `id` (AnimationArms) replacing the
-- same joints of `pose` entirely.
local function armed(pose: Pose, id: string): Pose
	local out: Pose = {}
	for joint, value in pose do
		out[joint] = table.clone(value)
	end
	local solved = (AnimationArms.Poses :: any)[id]
	if solved then
		for joint, value in solved do
			out[joint] = table.clone(value)
		end
	end
	return out
end

AnimationClips.with = with
AnimationClips.mirror = mirror

--------------------------------------------------------------------------------
-- Shared stances
--------------------------------------------------------------------------------

-- Relaxed ready legs: weight slightly on the back foot, knees soft.
local READY_LEGS: Pose = {
	Root = { py = -0.12, y = -8 },
	LeftHip = { x = 12, z = -4 },
	LeftKnee = { x = -16 },
	LeftAnkle = { x = 4 },
	RightHip = { x = -8, z = 4 },
	RightKnee = { x = -14 },
	RightAnkle = { x = 22 },
}

-- Upper-body weapon holds (also the start/end of every attack).
local HOLD: { [string]: Pose } = {
	-- Sword up in guard, blade angled forward and up.
	Warrior = {
		Waist = { y = 6 },
		Neck = { y = 4 },
		RightShoulder = { x = 22, z = 12 },
		RightElbow = { x = 58 },
		RightWrist = { x = -12 },
		LeftShoulder = { x = 16, z = -12 },
		LeftElbow = { x = 34 },
	},
	-- Staff upright in the right hand, left hand open.
	Healer = {
		RightShoulder = { x = 14, z = 12 },
		RightElbow = { x = 76 },
		LeftShoulder = { x = 6, z = -8 },
		LeftElbow = { x = 22 },
	},
	-- Bow low in the left hand, right hand near the quiver line.
	Archer = {
		LeftShoulder = { x = 18, z = -10 },
		LeftElbow = { x = 38 },
		RightShoulder = { x = 6, z = 6 },
		RightElbow = { x = 18 },
	},
	-- Wand pointed down-forward, left hand raised with an open palm.
	Mage = {
		RightShoulder = { x = 16, z = 10 },
		RightElbow = { x = 38 },
		LeftShoulder = { x = 22, z = -14 },
		LeftElbow = { x = 62 },
		LeftWrist = { x = -18 },
	},
}

-- Weapon arms come from the solver (tools/anim/generate_arms.py).
for job, pose in HOLD do
	HOLD[job] = armed(pose, job .. ".hold")
end

local function idle(job: string): Clip
	local stand = with(READY_LEGS, HOLD[job])
	local inhale = with(stand, {
		Root = { py = -0.16, y = -8 },
		Waist = { x = -2.5, y = (HOLD[job].Waist and HOLD[job].Waist.y or 0) },
		Neck = { x = 2, y = (HOLD[job].Neck and HOLD[job].Neck.y or 0) },
		LeftKnee = { x = -19 },
		RightKnee = { x = -17 },
	})
	-- Arms lag the breath slightly.
	for _, side in { "Left", "Right" } do
		local shoulder = inhale[side .. "Shoulder"]
		if shoulder then
			shoulder.x = (shoulder.x or 0) + 3
		end
	end
	return {
		duration = 2.4,
		looped = true,
		priority = "Idle",
		keys = {
			{ t = 0, pose = stand },
			{ t = 1.2, ease = "InOut", pose = inhale },
			{ t = 2.4, ease = "InOut", pose = stand },
		},
	}
end

local function hold(job: string): Clip
	local pose = HOLD[job]
	return {
		duration = 1,
		looped = true,
		priority = "Idle",
		keys = {
			{ t = 0, pose = pose },
			{ t = 1, ease = "Linear", pose = pose },
		},
	}
end

--------------------------------------------------------------------------------
-- Warrior: forehand slash -> backhand rising slash -> overhead cleave
--------------------------------------------------------------------------------

local W = HOLD.Warrior

local Warrior_Attack1: Clip = {
	duration = 0.58,
	looped = false,
	priority = "Action",
	markers = { Hit = 0.21 },
	keys = {
		{ t = 0, pose = with(READY_LEGS, W) },
		-- Wind-up: hips and chest coil right, sword drawn back past the shoulder.
		{
			t = 0.13,
			ease = "Out",
			pose = with(READY_LEGS, {
				Root = { py = -0.22, y = -18 },
				Waist = { y = -32, x = 2 },
				Neck = { y = 34 },
				RightShoulder = { x = 70, z = 72, y = -20 },
				RightElbow = { x = 82 },
				RightWrist = { x = -40 },
				LeftShoulder = { x = 48, z = -18 },
				LeftElbow = { x = 40 },
				RightKnee = { x = -26 },
				RightAnkle = { x = 34 },
			}),
		},
		-- Strike: hips lead, chest whips round, arm extends across the target.
		{
			t = 0.21,
			ease = "In",
			pose = {
				Root = { py = -0.3, y = 10, x = -6, pz = -0.35 },
				Waist = { y = 22, x = -6 },
				Neck = { y = -26, x = 6 },
				RightShoulder = { x = 88, z = 14, y = 30 },
				RightElbow = { x = 8 },
				RightWrist = { x = -55 },
				LeftShoulder = { x = 10, z = -40 },
				LeftElbow = { x = 30 },
				LeftHip = { x = 34, z = -4 },
				LeftKnee = { x = -40 },
				LeftAnkle = { x = 12 },
				RightHip = { x = -16, z = 4 },
				RightKnee = { x = -24 },
				RightAnkle = { x = 46 },
			},
		},
		-- Follow-through: the blade carries on past the left shoulder.
		{
			t = 0.3,
			ease = "Out",
			pose = {
				Root = { py = -0.32, y = 16, x = -7, pz = -0.4 },
				Waist = { y = 40, x = -5 },
				Neck = { y = -36, x = 6 },
				RightShoulder = { x = 70, z = -30, y = 55 },
				RightElbow = { x = 26 },
				RightWrist = { x = -30 },
				LeftShoulder = { x = -10, z = -46 },
				LeftElbow = { x = 26 },
				LeftHip = { x = 36, z = -4 },
				LeftKnee = { x = -42 },
				LeftAnkle = { x = 13 },
				RightHip = { x = -18, z = 4 },
				RightKnee = { x = -26 },
				RightAnkle = { x = 50 },
			},
		},
		{ t = 0.58, ease = "InOut", pose = with(READY_LEGS, W) },
	},
}

local Warrior_Attack2: Clip = {
	duration = 0.58,
	looped = false,
	priority = "Action",
	markers = { Hit = 0.2 },
	keys = {
		{ t = 0, pose = with(READY_LEGS, W) },
		-- Wind-up: sword drops to the left hip, chest turns left.
		{
			t = 0.12,
			ease = "Out",
			pose = with(READY_LEGS, {
				Root = { py = -0.24, y = 14 },
				Waist = { y = 30, x = -4 },
				Neck = { y = -30 },
				RightShoulder = { x = 40, z = -42, y = 40 },
				RightElbow = { x = 74 },
				RightWrist = { x = 10 },
				LeftShoulder = { x = 20, z = -30 },
				LeftElbow = { x = 48 },
				LeftKnee = { x = -24 },
			}),
		},
		-- Strike: rising backhand from low-left to high-right.
		{
			t = 0.2,
			ease = "In",
			pose = {
				Root = { py = -0.28, y = -14, x = -5, pz = -0.3 },
				Waist = { y = -20, x = -4 },
				Neck = { y = 24, x = 4 },
				RightShoulder = { x = 100, z = 40, y = -20 },
				RightElbow = { x = 10 },
				RightWrist = { x = -45 },
				LeftShoulder = { x = 30, z = -50 },
				LeftElbow = { x = 22 },
				RightHip = { x = 32, z = 4 },
				RightKnee = { x = -38 },
				RightAnkle = { x = 11 },
				LeftHip = { x = -14, z = -4 },
				LeftKnee = { x = -22 },
				LeftAnkle = { x = 41 },
			},
		},
		-- Follow-through: blade high over the right shoulder.
		{
			t = 0.3,
			ease = "Out",
			pose = {
				Root = { py = -0.26, y = -20, x = -3, pz = -0.34 },
				Waist = { y = -36, x = 2 },
				Neck = { y = 36, x = 2 },
				RightShoulder = { x = 140, z = 70, y = -30 },
				RightElbow = { x = 24 },
				RightWrist = { x = -30 },
				LeftShoulder = { x = 26, z = -58 },
				LeftElbow = { x = 20 },
				RightHip = { x = 34, z = 4 },
				RightKnee = { x = -40 },
				RightAnkle = { x = 9 },
				LeftHip = { x = -16, z = -4 },
				LeftKnee = { x = -24 },
				LeftAnkle = { x = 43 },
			},
		},
		{ t = 0.58, ease = "InOut", pose = with(READY_LEGS, W) },
	},
}

local Warrior_Attack3: Clip = {
	duration = 0.86,
	looped = false,
	priority = "Action",
	markers = { Hit = 0.4 },
	keys = {
		{ t = 0, pose = with(READY_LEGS, W) },
		-- Big wind-up: rise and lean back, sword high behind the head.
		{
			t = 0.24,
			ease = "Out",
			pose = {
				Root = { py = 0.04, x = 8, y = -6 },
				Waist = { x = 10, y = -8 },
				Neck = { x = -10, y = 8 },
				RightShoulder = { x = 168, z = 18 },
				RightElbow = { x = 46 },
				RightWrist = { x = -36 },
				LeftShoulder = { x = 70, z = -42 },
				LeftElbow = { x = 30 },
				LeftHip = { x = 4 },
				LeftKnee = { x = -6 },
				LeftAnkle = { x = -6 },
				RightHip = { x = -12 },
				RightKnee = { x = -8 },
				RightAnkle = { x = 12 },
			},
		},
		-- Brief hang at the top (anticipation).
		{
			t = 0.32,
			ease = "Linear",
			pose = {
				Root = { py = 0.06, x = 10, y = -6 },
				Waist = { x = 12, y = -8 },
				Neck = { x = -12, y = 8 },
				RightShoulder = { x = 176, z = 18 },
				RightElbow = { x = 52 },
				RightWrist = { x = -40 },
				LeftShoulder = { x = 76, z = -44 },
				LeftElbow = { x = 30 },
				LeftHip = { x = 4 },
				LeftKnee = { x = -6 },
				LeftAnkle = { x = -8 },
				RightHip = { x = -12 },
				RightKnee = { x = -8 },
				RightAnkle = { x = 10 },
			},
		},
		-- Cleave: drop the weight into a deep lunge as the blade comes down.
		{
			t = 0.4,
			ease = "In",
			pose = {
				Root = { py = -0.62, x = -14, pz = -0.7 },
				Waist = { x = -20, y = 4 },
				Neck = { x = 24 },
				RightShoulder = { x = 72, z = 6 },
				RightElbow = { x = 2 },
				RightWrist = { x = -52 },
				LeftShoulder = { x = -16, z = -36 },
				LeftElbow = { x = 22 },
				LeftHip = { x = 58 },
				LeftKnee = { x = -72 },
				LeftAnkle = { x = 28 },
				RightHip = { x = -6 },
				RightKnee = { x = -48 },
				RightAnkle = { x = 40 },
			},
		},
		-- Weight settles on the impact.
		{
			t = 0.52,
			ease = "Out",
			pose = {
				Root = { py = -0.7, x = -15, pz = -0.72 },
				Waist = { x = -22, y = 4 },
				Neck = { x = 26 },
				RightShoulder = { x = 64, z = 6 },
				RightElbow = { x = 4 },
				RightWrist = { x = -46 },
				LeftShoulder = { x = -20, z = -38 },
				LeftElbow = { x = 24 },
				LeftHip = { x = 62 },
				LeftKnee = { x = -78 },
				LeftAnkle = { x = 31 },
				RightHip = { x = -4 },
				RightKnee = { x = -52 },
				RightAnkle = { x = 40 },
			},
		},
		{ t = 0.86, ease = "InOut", pose = with(READY_LEGS, W) },
	},
}

--------------------------------------------------------------------------------
-- Archer: quick shot -> quick shot -> charged power shot
--------------------------------------------------------------------------------

local A = HOLD.Archer

-- Side-on shooting stance: hips turned right, head turned to the target,
-- bow arm straight at the target.
local AIM_BODY: Pose = {
	Root = { y = -42, py = -0.14 },
	Waist = { y = -22, x = -2 },
	Neck = { y = 60 },
	LeftHip = { x = 10, z = -8 },
	LeftKnee = { x = -12 },
	LeftAnkle = { x = 2 },
	RightHip = { x = -6, z = 8 },
	RightKnee = { x = -14 },
	RightAnkle = { x = 20 },
}
local BOW_ARM: Pose = {
	LeftShoulder = { x = 90, z = -64 },
	LeftElbow = { x = 4 },
	LeftWrist = { x = 0 },
}
local NOCK: Pose = with(
	AIM_BODY,
	with(BOW_ARM, {
		RightShoulder = { x = 84, z = -36 },
		RightElbow = { x = 46 },
	})
)
local DRAWN: Pose = with(
	AIM_BODY,
	with(BOW_ARM, {
		RightShoulder = { x = 6, z = 88, y = -24 },
		RightElbow = { x = 138 },
		Waist = { y = -24, x = 2 },
	})
)
local RELEASED: Pose = with(
	AIM_BODY,
	with(BOW_ARM, {
		LeftShoulder = { x = 94, z = -64 },
		RightShoulder = { x = 4, z = 96, y = -46 },
		RightElbow = { x = 64 },
		RightWrist = { x = -20 },
	})
)

local Archer_Attack1: Clip = {
	duration = 0.6,
	looped = false,
	priority = "Action",
	markers = { Hit = 0.3 },
	keys = {
		{ t = 0, pose = with(READY_LEGS, A) },
		{ t = 0.12, ease = "Out", pose = NOCK },
		{ t = 0.25, ease = "Out", pose = DRAWN },
		-- A short steady aim, then release.
		{ t = 0.3, ease = "Linear", pose = with(DRAWN, { RightShoulder = { x = 6, z = 90, y = -26 } }) },
		{ t = 0.36, ease = "Out", pose = RELEASED },
		{ t = 0.6, ease = "InOut", pose = with(READY_LEGS, A) },
	},
}

-- Second shot is quicker: the bow is already up.
local Archer_Attack2: Clip = {
	duration = 0.52,
	looped = false,
	priority = "Action",
	markers = { Hit = 0.24 },
	keys = {
		{ t = 0, pose = NOCK },
		{ t = 0.19, ease = "Out", pose = DRAWN },
		{ t = 0.24, ease = "Linear", pose = with(DRAWN, { RightShoulder = { x = 6, z = 90, y = -26 } }) },
		{ t = 0.3, ease = "Out", pose = RELEASED },
		{ t = 0.52, ease = "InOut", pose = with(READY_LEGS, A) },
	},
}

-- Power shot: wide stance, long draw with the body leaning back, big release.
local POWER_LEGS: Pose = {
	Root = { y = -48, py = -0.36 },
	LeftHip = { x = 22, z = -14 },
	LeftKnee = { x = -30 },
	LeftAnkle = { x = 8 },
	RightHip = { x = -12, z = 14 },
	RightKnee = { x = -30 },
	RightAnkle = { x = 42 },
}
local Archer_Attack3: Clip = {
	duration = 1.0,
	looped = false,
	priority = "Action",
	markers = { Hit = 0.62 },
	keys = {
		{ t = 0, pose = with(READY_LEGS, A) },
		{ t = 0.16, ease = "Out", pose = with(NOCK, POWER_LEGS) },
		{
			t = 0.46,
			ease = "InOut",
			pose = with(with(DRAWN, POWER_LEGS), {
				Waist = { y = -26, x = 6 },
				Neck = { y = 62, x = -4 },
				RightShoulder = { x = 4, z = 94, y = -34 },
				RightElbow = { x = 145 },
			}),
		},
		-- Trembling full draw.
		{
			t = 0.62,
			ease = "Linear",
			pose = with(with(DRAWN, POWER_LEGS), {
				Waist = { y = -27, x = 7 },
				Neck = { y = 62, x = -4 },
				RightShoulder = { x = 4, z = 96, y = -36 },
				RightElbow = { x = 146 },
			}),
		},
		{
			t = 0.7,
			ease = "Out",
			pose = with(with(RELEASED, POWER_LEGS), {
				Root = { y = -48, py = -0.36, pz = 0.25 },
				Waist = { y = -20, x = 8 },
				LeftShoulder = { x = 102, z = -64 },
				RightShoulder = { x = 8, z = 110, y = -60 },
				RightElbow = { x = 40 },
			}),
		},
		{ t = 1.0, ease = "InOut", pose = with(READY_LEGS, A) },
	},
}

--------------------------------------------------------------------------------
-- Healer: staff thrust -> staff point -> radiant slam (finisher)
--------------------------------------------------------------------------------

local H = HOLD.Healer

local Healer_Attack1: Clip = {
	duration = 0.6,
	looped = false,
	priority = "Action",
	markers = { Hit = 0.27 },
	keys = {
		{ t = 0, pose = with(READY_LEGS, H) },
		-- Draw the staff back beside the shoulder, left hand gathers light.
		{
			t = 0.14,
			ease = "Out",
			pose = with(READY_LEGS, {
				Root = { py = -0.16, y = -14, x = 3 },
				Waist = { y = -22, x = 4 },
				Neck = { y = 24 },
				RightShoulder = { x = 30, z = 20 },
				RightElbow = { x = 108 },
				RightWrist = { x = 6 },
				LeftShoulder = { x = 40, z = -6 },
				LeftElbow = { x = 70 },
				LeftWrist = { x = -20 },
			}),
		},
		-- Thrust: staff head drives forward at the target, palm follows.
		{
			t = 0.27,
			ease = "In",
			pose = with(READY_LEGS, {
				Root = { py = -0.22, y = 8, x = -6, pz = -0.18 },
				Waist = { y = 14, x = -8 },
				Neck = { y = -10, x = 8 },
				RightShoulder = { x = 64, z = 6 },
				RightElbow = { x = 6 },
				RightWrist = { x = -22 },
				LeftShoulder = { x = 78, z = -20 },
				LeftElbow = { x = 12 },
				LeftWrist = { x = -40 },
				LeftHip = { x = 24, z = -4 },
				LeftKnee = { x = -30 },
				LeftAnkle = { x = 12 },
			}),
		},
		{
			t = 0.36,
			ease = "Out",
			pose = with(READY_LEGS, {
				Root = { py = -0.22, y = 10, x = -7, pz = -0.2 },
				Waist = { y = 18, x = -8 },
				Neck = { y = -14, x = 8 },
				RightShoulder = { x = 68, z = 4 },
				RightElbow = { x = 4 },
				RightWrist = { x = -26 },
				LeftShoulder = { x = 72, z = -22 },
				LeftElbow = { x = 16 },
				LeftWrist = { x = -36 },
				LeftHip = { x = 24, z = -4 },
				LeftKnee = { x = -30 },
				LeftAnkle = { x = 12 },
			}),
		},
		{ t = 0.6, ease = "InOut", pose = with(READY_LEGS, H) },
	},
}

local Healer_Attack2: Clip = {
	duration = 0.62,
	looped = false,
	priority = "Action",
	markers = { Hit = 0.28 },
	keys = {
		{ t = 0, pose = with(READY_LEGS, H) },
		-- Raise the staff upright above the shoulder, lean back.
		{
			t = 0.15,
			ease = "Out",
			pose = with(READY_LEGS, {
				Root = { py = -0.1, x = 6 },
				Waist = { x = 8, y = -10 },
				Neck = { x = -6, y = 10 },
				RightShoulder = { x = 128, z = 14 },
				RightElbow = { x = 26 },
				RightWrist = { x = -64 },
				LeftShoulder = { x = 30, z = -48 },
				LeftElbow = { x = 26 },
			}),
		},
		-- Point the staff head down at the target and lean in.
		{
			t = 0.28,
			ease = "In",
			pose = with(READY_LEGS, {
				Root = { py = -0.24, x = -8, pz = -0.16 },
				Waist = { x = -10, y = 6 },
				Neck = { x = 12, y = -4 },
				RightShoulder = { x = 84, z = 6 },
				RightElbow = { x = 2 },
				RightWrist = { x = -60 },
				LeftShoulder = { x = -10, z = -52 },
				LeftElbow = { x = 18 },
				RightHip = { x = 22, z = 4 },
				RightKnee = { x = -28 },
				RightAnkle = { x = 14 },
			}),
		},
		{
			t = 0.38,
			ease = "Out",
			pose = with(READY_LEGS, {
				Root = { py = -0.26, x = -9, pz = -0.18 },
				Waist = { x = -11, y = 6 },
				Neck = { x = 13, y = -4 },
				RightShoulder = { x = 80, z = 6 },
				RightElbow = { x = 4 },
				RightWrist = { x = -56 },
				LeftShoulder = { x = -12, z = -54 },
				LeftElbow = { x = 18 },
				RightHip = { x = 22, z = 4 },
				RightKnee = { x = -28 },
				RightAnkle = { x = 14 },
			}),
		},
		{ t = 0.62, ease = "InOut", pose = with(READY_LEGS, H) },
	},
}

local Healer_Attack3: Clip = {
	duration = 0.96,
	looped = false,
	priority = "Action",
	markers = { Hit = 0.5 },
	keys = {
		{ t = 0, pose = with(READY_LEGS, H) },
		-- Lift the staff high with both hands, rise onto the toes.
		{
			t = 0.26,
			ease = "Out",
			pose = {
				Root = { py = 0.12, x = 4 },
				Waist = { x = 8 },
				Neck = { x = -14 },
				RightShoulder = { x = 132, z = 4 },
				RightElbow = { x = 40 },
				RightWrist = { x = -82 },
				LeftShoulder = { x = 140, z = 22 },
				LeftElbow = { x = 44 },
				LeftHip = { x = 2 },
				LeftAnkle = { x = -14 },
				RightHip = { x = 2 },
				RightAnkle = { x = -14 },
			},
		},
		{
			t = 0.42,
			ease = "Linear",
			pose = {
				Root = { py = 0.16, x = 5 },
				Waist = { x = 9 },
				Neck = { x = -16 },
				RightShoulder = { x = 136, z = 4 },
				RightElbow = { x = 42 },
				RightWrist = { x = -84 },
				LeftShoulder = { x = 144, z = 22 },
				LeftElbow = { x = 46 },
				LeftHip = { x = 2 },
				LeftAnkle = { x = -16 },
				RightHip = { x = 2 },
				RightAnkle = { x = -16 },
			},
		},
		-- Slam the staff down; the body drops into the strike.
		{
			t = 0.5,
			ease = "In",
			pose = {
				Root = { py = -0.62, x = -8 },
				Waist = { x = -12 },
				Neck = { x = 14 },
				RightShoulder = { x = 44, z = 14 },
				RightElbow = { x = 46 },
				RightWrist = { x = 0 },
				LeftShoulder = { x = 70, z = -24 },
				LeftElbow = { x = 10 },
				LeftWrist = { x = -40 },
				LeftHip = { x = 46, z = -6 },
				LeftKnee = { x = -60 },
				LeftAnkle = { x = 22 },
				RightHip = { x = 40, z = 6 },
				RightKnee = { x = -56 },
				RightAnkle = { x = 24 },
			},
		},
		{
			t = 0.66,
			ease = "Out",
			pose = {
				Root = { py = -0.66, x = -9 },
				Waist = { x = -13 },
				Neck = { x = 15 },
				RightShoulder = { x = 42, z = 14 },
				RightElbow = { x = 48 },
				LeftShoulder = { x = 66, z = -26 },
				LeftElbow = { x = 12 },
				LeftWrist = { x = -36 },
				LeftHip = { x = 48, z = -6 },
				LeftKnee = { x = -62 },
				LeftAnkle = { x = 23 },
				RightHip = { x = 42, z = 6 },
				RightKnee = { x = -58 },
				RightAnkle = { x = 25 },
			},
		},
		{ t = 0.96, ease = "InOut", pose = with(READY_LEGS, H) },
	},
}

--------------------------------------------------------------------------------
-- Mage: wand flick -> palm blast -> two-handed arcane burst (finisher)
--------------------------------------------------------------------------------

local M = HOLD.Mage

local Mage_Attack1: Clip = {
	duration = 0.48,
	looped = false,
	priority = "Action",
	markers = { Hit = 0.18 },
	keys = {
		{ t = 0, pose = with(READY_LEGS, M) },
		-- Cock the wand back over the shoulder.
		{
			t = 0.1,
			ease = "Out",
			pose = with(
				READY_LEGS,
				with(M, {
					Root = { py = -0.14, y = -12 },
					Waist = { y = -16, x = 3 },
					Neck = { y = 18 },
					RightShoulder = { x = 104, z = 26 },
					RightElbow = { x = 112 },
					RightWrist = { x = -20 },
				})
			),
		},
		-- Flick: arm snaps out straight, wand points at the target.
		{
			t = 0.18,
			ease = "In",
			pose = with(
				READY_LEGS,
				with(M, {
					Root = { py = -0.18, y = 6, pz = -0.12 },
					Waist = { y = 12, x = -5 },
					Neck = { y = -10, x = 4 },
					RightShoulder = { x = 86, z = 2 },
					RightElbow = { x = 2 },
					RightWrist = { x = -12 },
				})
			),
		},
		{
			t = 0.25,
			ease = "Out",
			pose = with(
				READY_LEGS,
				with(M, {
					Root = { py = -0.18, y = 8, pz = -0.12 },
					Waist = { y = 14, x = -5 },
					Neck = { y = -12, x = 4 },
					RightShoulder = { x = 82, z = 0 },
					RightElbow = { x = 4 },
					RightWrist = { x = 8 },
				})
			),
		},
		{ t = 0.48, ease = "InOut", pose = with(READY_LEGS, M) },
	},
}

local Mage_Attack2: Clip = {
	duration = 0.52,
	looped = false,
	priority = "Action",
	markers = { Hit = 0.21 },
	keys = {
		{ t = 0, pose = with(READY_LEGS, M) },
		-- Left hand pulls back to the hip, chest turns left.
		{
			t = 0.11,
			ease = "Out",
			pose = with(READY_LEGS, {
				Root = { py = -0.16, y = 12 },
				Waist = { y = 24, x = 2 },
				Neck = { y = -24 },
				LeftShoulder = { x = -24, z = -16 },
				LeftElbow = { x = 96 },
				LeftWrist = { x = -10 },
				RightShoulder = { x = 30, z = 14 },
				RightElbow = { x = 60 },
			}),
		},
		-- Palm blast: the left arm drives straight out, wand pulls back.
		{
			t = 0.21,
			ease = "In",
			pose = with(READY_LEGS, {
				Root = { py = -0.22, y = -12, x = -4, pz = -0.16 },
				Waist = { y = -22, x = -5 },
				Neck = { y = 30, x = 4 },
				LeftShoulder = { x = 88, z = -10, y = -10 },
				LeftElbow = { x = 2 },
				LeftWrist = { x = -50 },
				RightShoulder = { x = -10, z = 22 },
				RightElbow = { x = 70 },
				LeftHip = { x = 26, z = -4 },
				LeftKnee = { x = -32 },
				LeftAnkle = { x = 12 },
			}),
		},
		{
			t = 0.29,
			ease = "Out",
			pose = with(READY_LEGS, {
				Root = { py = -0.22, y = -14, x = -4, pz = -0.18 },
				Waist = { y = -24, x = -5 },
				Neck = { y = 32, x = 4 },
				LeftShoulder = { x = 84, z = -12, y = -10 },
				LeftElbow = { x = 6 },
				LeftWrist = { x = -44 },
				RightShoulder = { x = -12, z = 22 },
				RightElbow = { x = 72 },
				LeftHip = { x = 26, z = -4 },
				LeftKnee = { x = -32 },
				LeftAnkle = { x = 12 },
			}),
		},
		{ t = 0.52, ease = "InOut", pose = with(READY_LEGS, M) },
	},
}

local GATHER: Pose = {
	Root = { py = -0.34, x = 2 },
	Waist = { x = -6 },
	Neck = { x = 8 },
	RightShoulder = { x = 54, z = -22 },
	RightElbow = { x = 104 },
	RightWrist = { x = -10 },
	LeftShoulder = { x = 54, z = 22 },
	LeftElbow = { x = 104 },
	LeftWrist = { x = -10 },
	LeftHip = { x = 26, z = -8 },
	LeftKnee = { x = -36 },
	LeftAnkle = { x = 8 },
	RightHip = { x = 22, z = 8 },
	RightKnee = { x = -34 },
	RightAnkle = { x = 10 },
}

local Mage_Attack3: Clip = {
	duration = 1.0,
	looped = false,
	priority = "Action",
	markers = { Hit = 0.56 },
	keys = {
		{ t = 0, pose = with(READY_LEGS, M) },
		-- Gather power between the hands, sinking into the legs.
		{ t = 0.3, ease = "Out", pose = GATHER },
		{
			t = 0.46,
			ease = "Linear",
			pose = with(GATHER, {
				Root = { py = -0.4, x = 3 },
				RightShoulder = { x = 50, z = -24 },
				LeftShoulder = { x = 50, z = 24 },
			}),
		},
		-- Burst: both arms thrust out, body drives forward.
		{
			t = 0.56,
			ease = "In",
			pose = {
				Root = { py = -0.3, x = -6, pz = -0.28 },
				Waist = { x = -8 },
				Neck = { x = 8 },
				RightShoulder = { x = 92, z = 18 },
				RightElbow = { x = 4 },
				RightWrist = { x = -30 },
				LeftShoulder = { x = 92, z = -18 },
				LeftElbow = { x = 4 },
				LeftWrist = { x = -50 },
				LeftHip = { x = 30, z = -8 },
				LeftKnee = { x = -34 },
				LeftAnkle = { x = 10 },
				RightHip = { x = 4, z = 8 },
				RightKnee = { x = -26 },
				RightAnkle = { x = 28 },
			},
		},
		{
			t = 0.72,
			ease = "Out",
			pose = {
				Root = { py = -0.3, x = -7, pz = -0.3 },
				Waist = { x = -9 },
				Neck = { x = 9 },
				RightShoulder = { x = 88, z = 22 },
				RightElbow = { x = 8 },
				RightWrist = { x = -26 },
				LeftShoulder = { x = 88, z = -22 },
				LeftElbow = { x = 8 },
				LeftWrist = { x = -44 },
				LeftHip = { x = 30, z = -8 },
				LeftKnee = { x = -34 },
				LeftAnkle = { x = 10 },
				RightHip = { x = 4, z = 8 },
				RightKnee = { x = -26 },
				RightAnkle = { x = 28 },
			},
		},
		{ t = 1.0, ease = "InOut", pose = with(READY_LEGS, M) },
	},
}

--------------------------------------------------------------------------------
-- Movement
--------------------------------------------------------------------------------

-- Sprint cycle (full body): contact / passing / opposite contact / passing.
local SPRINT_A: Pose = {
	Root = { x = -14, y = 8, py = 0.02 },
	Waist = { x = -4, y = -14 },
	Neck = { x = 12, y = 6 },
	RightHip = { x = 58 },
	RightKnee = { x = -24 },
	RightAnkle = { x = 8 },
	LeftHip = { x = -34 },
	LeftKnee = { x = -78 },
	LeftAnkle = { x = -26 },
	LeftShoulder = { x = 58, z = -8 },
	LeftElbow = { x = 92 },
	RightShoulder = { x = -42, z = 10 },
	RightElbow = { x = 74 },
}
local SPRINT_PASS: Pose = {
	Root = { x = -14, py = -0.22 },
	Waist = { x = -4 },
	Neck = { x = 12 },
	RightHip = { x = 6 },
	RightKnee = { x = -12 },
	RightAnkle = { x = 20 },
	LeftHip = { x = 30 },
	LeftKnee = { x = -110 },
	LeftAnkle = { x = -10 },
	LeftShoulder = { x = 8, z = -8 },
	LeftElbow = { x = 84 },
	RightShoulder = { x = 4, z = 10 },
	RightElbow = { x = 80 },
}
local Sprint: Clip = {
	duration = 0.62,
	looped = true,
	priority = "Movement",
	keys = {
		{ t = 0, pose = SPRINT_A },
		{ t = 0.155, ease = "InOut", pose = SPRINT_PASS },
		{ t = 0.31, ease = "InOut", pose = mirror(SPRINT_A) },
		{ t = 0.465, ease = "InOut", pose = mirror(SPRINT_PASS) },
		{ t = 0.62, ease = "InOut", pose = SPRINT_A },
	},
}

-- Crouch (legs and torso only, so the job's weapon hold stays on the arms).
local CROUCH: Pose = {
	Root = { x = -10, py = -0.95 },
	Waist = { x = -16 },
	Neck = { x = 16 },
	LeftHip = { x = 62, z = -6 },
	LeftKnee = { x = -84 },
	LeftAnkle = { x = 32 },
	RightHip = { x = 46, z = 6 },
	RightKnee = { x = -92 },
	RightAnkle = { x = 56 },
}
local CrouchIdle: Clip = {
	duration = 2.4,
	looped = true,
	priority = "Movement",
	keys = {
		{ t = 0, pose = CROUCH },
		{
			t = 1.2,
			ease = "InOut",
			pose = with(CROUCH, { Root = { x = -10, py = -1.0 }, Waist = { x = -18 }, Neck = { x = 18 } }),
		},
		{ t = 2.4, ease = "InOut", pose = CROUCH },
	},
}

local CROUCH_STEP: Pose = {
	Root = { x = -10, py = -0.92, y = 6 },
	Waist = { x = -16, y = -8 },
	Neck = { x = 16 },
	RightHip = { x = 78, z = 4 },
	RightKnee = { x = -70 },
	RightAnkle = { x = 2 },
	LeftHip = { x = 28, z = -4 },
	LeftKnee = { x = -94 },
	LeftAnkle = { x = 50 },
}
local CROUCH_PASS: Pose = {
	Root = { x = -10, py = -1.0 },
	Waist = { x = -16 },
	Neck = { x = 16 },
	RightHip = { x = 50, z = 4 },
	RightKnee = { x = -84 },
	RightAnkle = { x = 44 },
	LeftHip = { x = 62, z = -4 },
	LeftKnee = { x = -110 },
	LeftAnkle = { x = 40 },
}
local CrouchWalk: Clip = {
	duration = 1.0,
	looped = true,
	priority = "Movement",
	keys = {
		{ t = 0, pose = CROUCH_STEP },
		{ t = 0.25, ease = "InOut", pose = CROUCH_PASS },
		{ t = 0.5, ease = "InOut", pose = mirror(CROUCH_STEP) },
		{ t = 0.75, ease = "InOut", pose = mirror(CROUCH_PASS) },
		{ t = 1.0, ease = "InOut", pose = CROUCH_STEP },
	},
}

--------------------------------------------------------------------------------
-- Reactions
--------------------------------------------------------------------------------

local HitLight: Clip = {
	duration = 0.36,
	looped = false,
	priority = "Action",
	keys = {
		{ t = 0, pose = {} },
		{
			t = 0.06,
			ease = "Out",
			pose = {
				Root = { x = 6, pz = 0.12 },
				Waist = { x = 10, y = 6 },
				Neck = { x = -10, y = -6 },
				LeftShoulder = { z = -14, x = 10 },
				RightShoulder = { z = 14, x = 10 },
				LeftElbow = { x = 20 },
				RightElbow = { x = 20 },
			},
		},
		{ t = 0.36, ease = "InOut", pose = {} },
	},
}

local HitHeavy: Clip = {
	duration = 0.7,
	looped = false,
	priority = "Action",
	keys = {
		{ t = 0, pose = {} },
		{
			t = 0.08,
			ease = "Out",
			pose = {
				Root = { x = 14, pz = 0.45, py = -0.15 },
				Waist = { x = 16, y = 10 },
				Neck = { x = -14, y = -10 },
				LeftShoulder = { z = -34, x = 30 },
				RightShoulder = { z = 34, x = 24 },
				LeftElbow = { x = 30 },
				RightElbow = { x = 30 },
				LeftHip = { x = 20 },
				LeftKnee = { x = -10 },
				RightHip = { x = -10 },
				RightKnee = { x = -24 },
				RightAnkle = { x = 20 },
			},
		},
		-- Stagger: catch the weight on bent knees.
		{
			t = 0.3,
			ease = "Out",
			pose = {
				Root = { x = -4, pz = 0.5, py = -0.4 },
				Waist = { x = -8, y = 4 },
				Neck = { x = 8 },
				LeftShoulder = { z = -18, x = 16 },
				RightShoulder = { z = 18, x = 12 },
				LeftElbow = { x = 26 },
				RightElbow = { x = 26 },
				LeftHip = { x = 34 },
				LeftKnee = { x = -44 },
				LeftAnkle = { x = 14 },
				RightHip = { x = 10 },
				RightKnee = { x = -40 },
				RightAnkle = { x = 34 },
			},
		},
		{ t = 0.7, ease = "InOut", pose = {} },
	},
}

-- Non-graphic defeat: stagger back, drop to one knee, head bowed (held).
local Defeat: Clip = {
	duration = 1.1,
	looped = false,
	priority = "Action4",
	hold = true,
	keys = {
		{ t = 0, pose = {} },
		{
			t = 0.16,
			ease = "Out",
			pose = {
				Root = { x = 12, pz = 0.3 },
				Waist = { x = 12 },
				Neck = { x = -12 },
				LeftShoulder = { x = 20, z = -30 },
				RightShoulder = { x = 20, z = 30 },
			},
		},
		{
			t = 0.62,
			ease = "In",
			pose = {
				Root = { x = -8, py = -1.35, pz = 0.3 },
				Waist = { x = -24 },
				Neck = { x = -18 },
				LeftHip = { x = 8 },
				LeftKnee = { x = -96 },
				LeftAnkle = { x = -40 },
				RightHip = { x = 92 },
				RightKnee = { x = -88 },
				RightAnkle = { x = 4 },
				LeftShoulder = { x = 10, z = -6 },
				RightShoulder = { x = 30, z = 8 },
				LeftElbow = { x = 16 },
				RightElbow = { x = 50 },
			},
		},
		{
			t = 1.1,
			ease = "Out",
			pose = {
				Root = { x = -10, py = -1.4, pz = 0.3 },
				Waist = { x = -32 },
				Neck = { x = -26 },
				LeftHip = { x = 8 },
				LeftKnee = { x = -98 },
				LeftAnkle = { x = -40 },
				RightHip = { x = 94 },
				RightKnee = { x = -90 },
				RightAnkle = { x = 4 },
				LeftShoulder = { x = 6, z = -4 },
				RightShoulder = { x = 34, z = 8 },
				LeftElbow = { x = 14 },
				RightElbow = { x = 56 },
			},
		},
	},
}

--------------------------------------------------------------------------------
-- Catalogue
--------------------------------------------------------------------------------

local clips: { [string]: Clip } = {
	Warrior_Attack1 = Warrior_Attack1,
	Warrior_Attack2 = Warrior_Attack2,
	Warrior_Attack3 = Warrior_Attack3,
	Archer_Attack1 = Archer_Attack1,
	Archer_Attack2 = Archer_Attack2,
	Archer_Attack3 = Archer_Attack3,
	Healer_Attack1 = Healer_Attack1,
	Healer_Attack2 = Healer_Attack2,
	Healer_Attack3 = Healer_Attack3,
	Mage_Attack1 = Mage_Attack1,
	Mage_Attack2 = Mage_Attack2,
	Mage_Attack3 = Mage_Attack3,
	Sprint = Sprint,
	CrouchIdle = CrouchIdle,
	CrouchWalk = CrouchWalk,
	HitLight = HitLight,
	HitHeavy = HitHeavy,
	Defeat = Defeat,
}
for _, job in { "Warrior", "Healer", "Archer", "Mage" } do
	clips[job .. "_Idle"] = idle(job)
	clips[job .. "_Hold"] = hold(job)
end

-- Merge the solved weapon arms into their keys.
for name, perKey in AnimationArms.Keys :: any do
	local clip = clips[name]
	if clip == nil then
		continue
	end
	for _, key in clip.keys do
		local ids = perKey[string.format("%.3f", key.t)]
		if ids then
			for _, id in ids do
				key.pose = armed(key.pose, id)
			end
		end
	end
end

local function deepFreeze(value: any): any
	if type(value) == "table" and not table.isfrozen(value) then
		for _, child in value do
			deepFreeze(child)
		end
		table.freeze(value)
	end
	return value
end

AnimationClips.Clips = deepFreeze(clips) :: { [string]: Clip }

-- Clip names in a stable order (remote schemas, exports).
local names = {}
for name in clips do
	table.insert(names, name)
end
table.sort(names)
AnimationClips.NAMES = table.freeze(names)

function AnimationClips.get(name: any): Clip?
	if type(name) ~= "string" then
		return nil
	end
	return AnimationClips.Clips[name]
end

-- Joints a clip animates (union over its keys), in JOINTS order.
function AnimationClips.jointsOf(clip: Clip): { string }
	local seen: { [string]: boolean } = {}
	for _, key in clip.keys do
		for joint in key.pose do
			seen[joint] = true
		end
	end
	local out = {}
	for _, joint in AnimationClips.JOINTS do
		if seen[joint] then
			table.insert(out, joint)
		end
	end
	return out
end

-- The value of every axis of `joint` at key `index` (missing = rest).
function AnimationClips.valueAt(clip: Clip, index: number, joint: string): JointKey
	return clip.keys[index].pose[joint] or {}
end

return table.freeze(AnimationClips)
