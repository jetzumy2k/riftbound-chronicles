--!strict
--[[
	MotionMath — tuning maths for human-like character motion
	(CharacterMotionController). Pure and frame-rate independent: every easing
	uses exponential damping, so motion feels the same at 30, 60 or 144 fps.

	Angles are radians. Roblox conventions: yaw grows counter-clockwise seen
	from above (turning left); characters face -Z.

	Pure module.
]]

local MotionMath = {}

MotionMath.Defaults = table.freeze({
	-- Start/stop easing of movement input (higher = snappier).
	accelRate = 6.5, -- ~90% of target speed after ~0.35 s
	decelRate = 9.0, -- ~90% stopped after ~0.25 s
	-- Facing: how quickly the body turns toward the movement direction.
	turnRate = 11.0,
	-- Body lean.
	maxLeanPitch = math.rad(7),
	leanPitchPerSpeed = math.rad(4), -- at full speed
	leanPitchPerAccel = math.rad(0.12), -- per stud/s^2 of forward acceleration
	maxLeanRoll = math.rad(9),
	leanRollPerTurnRate = 0.085, -- radians of roll per radian/s of turning
	leanRate = 8.0,
	-- Head / upper body follow the camera.
	headYawLimit = math.rad(60),
	headPitchLimit = math.rad(28),
	headPitchShare = 0.55,
	waistShare = 0.35,
	-- Beyond this the camera is "behind the face" and the head relaxes forward.
	headIgnoreBeyond = math.rad(115),
	headRate = 7.0,
	-- Landing knee dip.
	landingMaxDip = 0.45, -- studs
	landingFallSpeedForMax = 70, -- studs/s
	landingRecoverRate = 7.5,
})

--[[
	Blend factor for exponential smoothing over `dt` seconds at `rate`.
	lerp(current, target, alpha(rate, dt)) is frame-rate independent.
]]
function MotionMath.alpha(rate: number, dt: number): number
	return 1 - math.exp(-rate * math.max(dt, 0))
end

function MotionMath.damp(current: number, target: number, rate: number, dt: number): number
	return target + (current - target) * math.exp(-rate * math.max(dt, 0))
end

-- Shortest signed difference b - a, wrapped to [-pi, pi].
function MotionMath.angleDelta(a: number, b: number): number
	local delta = (b - a) % (2 * math.pi)
	if delta > math.pi then
		delta -= 2 * math.pi
	end
	return delta
end

function MotionMath.dampAngle(current: number, target: number, rate: number, dt: number): number
	return current + MotionMath.angleDelta(current, target) * MotionMath.alpha(rate, dt)
end

-- Yaw of a horizontal direction (x, z) for a character that faces -Z.
function MotionMath.yawOf(x: number, z: number): number
	return math.atan2(-x, -z)
end

--[[
	Body lean targets.
	  speedRatio    0..1 horizontal speed / walk speed
	  forwardAccel  stud/s^2 along the facing direction (+ = speeding up)
	  turnRate      rad/s of facing change (+ = turning left)
	Returns (pitch, roll): pitch > 0 leans forward, roll > 0 leans left.
]]
function MotionMath.lean(
	speedRatio: number,
	forwardAccel: number,
	turnRate: number,
	config: any?
): (number, number)
	local c = config or MotionMath.Defaults
	local pitch = c.leanPitchPerSpeed * math.clamp(speedRatio, 0, 1) + c.leanPitchPerAccel * forwardAccel
	local roll = c.leanRollPerTurnRate * turnRate * math.clamp(speedRatio, 0, 1)
	return math.clamp(pitch, -c.maxLeanPitch, c.maxLeanPitch), math.clamp(roll, -c.maxLeanRoll, c.maxLeanRoll)
end

--[[
	Head/waist follow targets from the camera relative to the body.
	Returns (neckYaw, neckPitch, waistYaw).
]]
function MotionMath.headLook(
	bodyYaw: number,
	cameraYaw: number,
	cameraPitch: number,
	config: any?
): (number, number, number)
	local c = config or MotionMath.Defaults
	local relative = MotionMath.angleDelta(bodyYaw, cameraYaw)
	if math.abs(relative) > c.headIgnoreBeyond then
		return 0, 0, 0
	end
	local yaw = math.clamp(relative, -c.headYawLimit, c.headYawLimit)
	local pitch = math.clamp(cameraPitch * c.headPitchShare, -c.headPitchLimit, c.headPitchLimit)
	return yaw * (1 - c.waistShare), pitch, yaw * c.waistShare
end

-- Knee dip (studs) for a landing at `fallSpeed` studs/s (positive = downward).
function MotionMath.landingDip(fallSpeed: number, config: any?): number
	local c = config or MotionMath.Defaults
	local ratio = math.clamp(fallSpeed / c.landingFallSpeedForMax, 0, 1)
	-- Ease-out curve: small hops barely dip, big falls dip fully.
	return c.landingMaxDip * (1 - (1 - ratio) ^ 2)
end

return table.freeze(MotionMath)
