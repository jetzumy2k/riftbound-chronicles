--!strict
--[[
	CreatureIK — leg inverse kinematics for procedural creatures (creature
	overhaul stage 1, PLAN.md D-51). Pure: no Roblox objects.

	A leg is three bones in a plane: upper (thigh / humerus / femur), lower
	(shin / forearm / tibia) and foot (metatarsus / metacarpus / tarsus).
	Angles are in radians, measured from straight down, positive towards
	"forward" in the leg's plane (the joint's -Z): rotating a down-pointing
	bone by `CFrame.Angles(a, 0, 0)` points it at angle `a`.

	  solve       foot tip at (`forward`, `down`) from the hip: the upper and
	              lower bones meet it with the knee bent towards `bend`
	              (+1 forward / outward, -1 back) and the foot bone held at
	              `footAngle` (absolute). Returns the upper bone's absolute
	              angle and the lower and foot bones' angles relative to
	              their parent bone. Out of reach: the leg straightens
	              towards the target.
	  tip         forward kinematics (tests and previews).
]]

local CreatureIK = {}

export type Lengths = { number } -- upper, lower, foot

-- Never fully straight or fully folded (keeps the knee direction stable).
local MIN_FOLD = 0.04
local MAX_REACH = 0.995

function CreatureIK.solve(
	lengths: Lengths,
	bend: number,
	footAngle: number,
	forward: number,
	down: number
): (number, number, number)
	local l1, l2, l3 = lengths[1], lengths[2], lengths[3]
	-- Where the ankle must be so the foot bone, at its angle, ends on the target.
	local af = forward - l3 * math.sin(footAngle)
	local ad = down - l3 * math.cos(footAngle)
	local d = math.sqrt(af * af + ad * ad)
	local minD = math.abs(l1 - l2) + (l1 + l2) * MIN_FOLD
	local maxD = (l1 + l2) * MAX_REACH
	d = math.clamp(d, minD, maxD)
	local toAnkle = math.atan2(af, ad)
	local cosHip = math.clamp((l1 * l1 + d * d - l2 * l2) / (2 * l1 * d), -1, 1)
	local cosKnee = math.clamp((l1 * l1 + l2 * l2 - d * d) / (2 * l1 * l2), -1, 1)
	local upper = toAnkle + bend * math.acos(cosHip)
	local lower = -bend * (math.pi - math.acos(cosKnee))
	local foot = footAngle - (upper + lower)
	return upper, lower, foot
end

-- Foot tip (forward, down) from the hip for the given joint angles.
function CreatureIK.tip(lengths: Lengths, upper: number, lower: number, foot: number): (number, number)
	local a1 = upper
	local a2 = a1 + lower
	local a3 = a2 + foot
	local f = lengths[1] * math.sin(a1) + lengths[2] * math.sin(a2) + lengths[3] * math.sin(a3)
	local d = lengths[1] * math.cos(a1) + lengths[2] * math.cos(a2) + lengths[3] * math.cos(a3)
	return f, d
end

-- Knee position (forward, down) from the hip.
function CreatureIK.knee(lengths: Lengths, upper: number): (number, number)
	return lengths[1] * math.sin(upper), lengths[1] * math.cos(upper)
end

return table.freeze(CreatureIK)
