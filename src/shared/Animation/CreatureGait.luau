--!strict
--[[
	CreatureGait — where a creature's foot goes and how its leg bones reach
	it (creature overhaul stage 1, PLAN.md D-51). Used by the client
	animator (MobVisualController) and the offline gait check
	(tools/world/check_gait.luau), so both run the same maths.

	  footTarget  the foot's target in root space: planted and sliding back
	              under the body through the stance (`t` < `duty`) at
	              exactly the body's speed, lifted along an arc and carried
	              forward through the swing. `stride` is the distance the
	              body travels during one stance. Returns the target and the
	              swing arc (0..1) for paw curl.
	  solveLeg    the three bones' Motor6D Transforms that put the foot tip
	              on `target`, given the Body part's frame in root space.
	              Upright legs also lean sideways (abduction) to follow the
	              target as the body rolls; splayed insect legs swing round.
	  state       the gait at a speed: walk-run blend, cycle length, duty,
	              stance length and lift. Stances never exceed what the
	              legs can reach (`maxStance`), and the cycle follows the
	              stance, so a planted foot moves exactly with the ground.
	              At a run the body sinks (`crouch`, the animator lowers the
	              Body by it) so the bent legs reach far enough for long,
	              natural strides instead of a rapid patter.
]]

local CreatureIK = require(script.Parent.Parent.Logic.CreatureIK)
local CreatureRigs = require(script.Parent.CreatureRigs)

local CreatureGait = {}

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

function CreatureGait.footTarget(
	home: Vector3,
	t: number,
	duty: number,
	stride: number,
	lift: number,
	amp: number,
	ground: number
): (Vector3, number)
	local zOff, up, arc = 0, 0, 0
	if t < duty then
		zOff = (-0.5 + t / duty) * stride
	else
		local u = (t - duty) / (1 - duty)
		zOff = (0.5 - smooth(u)) * stride
		arc = math.sin(math.pi * u)
		up = lift * arc
	end
	return home + Vector3.new(0, up * amp + ground, zOff * amp), arc
end

--[[
	Longest stance (studs at size 1) every leg can cover: the foot slides
	from `h` ahead of its home to `h` behind while the ankle stays within
	90% of the upper and lower bones' reach of the hip (room for the
	body to bob and pitch over it), with the body lowered by `crouch`.
]]
function CreatureGait.maxStance(plan: CreatureRigs.Plan, crouch: number?): number
	local best = math.huge
	for _, leg in plan.legs do
		local hip = plan.bodyCenter + leg.hip
		local tipY = -plan.height + CreatureRigs.FOOT_CLEARANCE
		local ankleY = tipY + leg.lengths[3] * math.cos(math.rad(leg.footAngle))
		local dx = leg.reach.X
		local dy = hip.Y - ankleY - (crouch or 0)
		local dz = leg.reach.Y
		local reach = (leg.lengths[1] + leg.lengths[2]) * 0.9
		local room = reach * reach - dx * dx - dy * dy
		local h = if room > 0 then math.sqrt(room) - math.abs(dz) else 0
		best = math.min(best, math.max(h, 0.1) * 2)
	end
	return best
end

export type GaitState = {
	run: number,
	cycle: number,
	duty: number,
	stride: number,
	lift: number,
	amp: number,
	-- How far the body is lowered (studs).
	crouch: number,
}

-- `speed` in studs/s (turning counts as speed too).
function CreatureGait.state(
	gait: CreatureRigs.Gait,
	plan: CreatureRigs.Plan,
	scale: number,
	speed: number
): GaitState
	local run = smooth((speed - gait.runSpeed * 0.4) / (gait.runSpeed * 0.6))
	local duty = gait.duty + (gait.runDuty - gait.duty) * run
	local crouch = gait.crouch * run
	local cycle = (gait.stride + (gait.runStride - gait.stride) * run) * scale
	cycle = math.min(cycle, CreatureGait.maxStance(plan, crouch) * scale / duty)
	return {
		run = run,
		cycle = cycle,
		duty = duty,
		stride = cycle * duty,
		lift = (gait.lift + (gait.runLift - gait.lift) * run) * scale,
		-- Feet settle home as the creature stops.
		amp = math.clamp(speed / 1, 0, 1),
		crouch = crouch * scale,
	}
end

export type LegBones = {
	-- Upper joint's C0 without its rest bend, and the rest angles.
	base: CFrame,
	rest: Vector3,
	lengths: { number },
	bend: number,
	splay: number,
}

--[[
	Transforms for the upper, lower and foot joints. `body` is the Body
	part's CFrame relative to the root; `target` is in root space;
	`footAngle` in radians.
]]
function CreatureGait.solveLeg(
	body: CFrame,
	leg: LegBones,
	target: Vector3,
	footAngle: number
): (CFrame, CFrame, CFrame)
	local joint = body * leg.base
	local t = joint:PointToObjectSpace(target)
	local swivel = CFrame.identity
	if leg.splay ~= 0 then
		local yaw = math.atan2(-t.X, -t.Z)
		swivel = CFrame.Angles(0, yaw, 0)
		t = CFrame.Angles(0, -yaw, 0) * t
	else
		local roll = math.atan2(t.X, -t.Y)
		swivel = CFrame.Angles(0, 0, roll)
		t = CFrame.Angles(0, 0, -roll) * t
	end
	local a1, a2, a3 = CreatureIK.solve(leg.lengths, leg.bend, footAngle, -t.Z, -t.Y)
	return CFrame.Angles(-leg.rest.X, 0, 0) * swivel * CFrame.Angles(a1, 0, 0),
		CFrame.Angles(a2 - leg.rest.Y, 0, 0),
		CFrame.Angles(a3 - leg.rest.Z, 0, 0)
end

return table.freeze(CreatureGait)
