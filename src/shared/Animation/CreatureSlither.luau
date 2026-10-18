--!strict
--[[
	CreatureSlither — how a serpent's body follows its chest (creature
	overhaul, PLAN.md D-54). Used by the client animator
	(MobVisualController) and the offline check
	(tools/world/check_slither.luau), so both run the same maths.

	Follow the leader: the chest weaves side to side as it goes (the
	animator's serpent body plan), leaving a trail on the ground (the
	point under the chest at the root's height, so the body keeps the
	height the Humanoid holds over the ground it passed), and
	every body segment (Seg1 .. SegN, Motor6Ds or Bones) is turned so its
	next joint lies on that trail exactly as far back as it sits along the
	body. Each part of the body so passes through the same S-shaped path
	the chest took, over the same bumps, the way a real snake moves: no
	part slides sideways or floats over a dip. At rest the trail stays
	put, so the snake lies in the curve it stopped in.

	  layout  the body's rest layout from its joints (once per rig)
	  weave   the chest's side offset after `travelled` studs (one S per
	          body length, so every curve bends through several segments)
	  heading the chest's yaw: pointing from the trail behind it, so the
	          back of the chest stays on the path too
	  step    updates the trail (world space, newest point first) and sets
	          every segment's Transform
]]

local CreatureSlither = {}

export type Layout = {
	count: number,
	-- Per segment: rest direction to the next joint (in its joint frame),
	-- that distance, and each joint's rest height in root space (count + 1
	-- entries, the last the tail tip).
	restDir: { Vector3 },
	restLen: { number },
	restY: { number },
	total: number,
	-- Flat distance from the chest (Body) back to the first joint.
	lead: number,
}

local MAX_SEGMENT_YAW = math.rad(65)
local MAX_SEGMENT_PITCH = math.rad(40)
-- A new trail point every this many studs (at size 1).
local TRAIL_STEP = 0.3

-- Joint offset from the parent frame (Motor6D C0, Bone CFrame).
local function jointOffset(joint: any): CFrame
	return if joint:IsA("Bone") then joint.CFrame else joint.C0
end

-- The segment's own frame after its Transform (children hang off it).
local function segmentFrame(joint: any, jointFrame: CFrame, transform: CFrame): CFrame
	return if joint:IsA("Bone") then jointFrame * transform else jointFrame * transform * joint.C1:Inverse()
end

-- `bodyRest`: the Body joint's rest frame in root space.
function CreatureSlither.layout(motors: { [string]: any }, count: number, bodyRest: CFrame): Layout?
	local joints = {}
	for i = 1, count do
		local joint = motors[`Seg{i}`]
		if joint == nil then
			return nil
		end
		joints[i] = joint
	end
	local restDir: { Vector3 }, restLen: { number }, restY: { number } = {}, {}, {}
	local parent = bodyRest
	local total = 0
	local first = (bodyRest * jointOffset(joints[1])).Position - bodyRest.Position
	local lead = Vector2.new(first.X, first.Z).Magnitude
	for i, joint in joints do
		local jointFrame = parent * jointOffset(joint)
		local dir: Vector3
		if i < count then
			local nextOffset = jointOffset(joints[i + 1]).Position
			dir = if joint:IsA("Bone")
				then nextOffset
				else (joint.C1:Inverse() * CFrame.new(nextOffset)).Position
		elseif joint:IsA("Bone") then
			dir = restDir[i - 1] or Vector3.new(0, 0, 1)
		else
			dir = joint.C1:Inverse().Position * 2
		end
		if dir.Magnitude < 1e-3 then
			dir = Vector3.new(0, 0, 0.5)
		end
		restDir[i] = dir
		restLen[i] = dir.Magnitude
		restY[i] = jointFrame.Position.Y
		total += dir.Magnitude
		if i == count then
			restY[i + 1] = (jointFrame * CFrame.new(dir)).Position.Y
		end
		parent = segmentFrame(joint, jointFrame, CFrame.identity)
	end
	return { count = count, restDir = restDir, restLen = restLen, restY = restY, total = total, lead = lead }
end

-- Weave wavelength and amplitude as shares of the body's length.
local WAVE_PER_LENGTH = 1
local AMPLITUDE_PER_WAVE = 0.08

-- Side offset of the chest (studs, root space X).
function CreatureSlither.weave(layout: Layout, travelled: number): number
	local wavelength = layout.total * WAVE_PER_LENGTH
	return math.sin(travelled / wavelength * math.pi * 2) * wavelength * AMPLITUDE_PER_WAVE
end

-- Point `distance` back along the trail (newest point first).
function CreatureSlither.trailPoint(trail: { Vector3 }, distance: number): Vector3
	local left = distance
	for i = 1, #trail - 1 do
		local a, b = trail[i], trail[i + 1]
		local length = (b - a).Magnitude
		if left <= length and length > 1e-4 then
			return a:Lerp(b, left / length)
		end
		left -= length
	end
	local last = trail[#trail]
	local before = trail[#trail - 1]
	if before and (last - before).Magnitude > 1e-4 then
		return last + (last - before).Unit * left
	end
	return last
end

--[[
	The chest's yaw (radians, about the root's Y; 0 = straight ahead) when
	it sits `x` studs to the side: it points from the trail `lead` studs
	behind to itself. Nil until there is a trail to point along.
]]
function CreatureSlither.heading(layout: Layout, trail: { Vector3 }, root: CFrame, x: number): number?
	if #trail < 2 then
		return nil
	end
	local chest = root * Vector3.new(x, 0, 0)
	local dir = root:VectorToObjectSpace(chest - CreatureSlither.trailPoint(trail, layout.lead))
	if Vector2.new(dir.X, dir.Z).Magnitude < 0.2 * layout.lead then
		return nil
	end
	return math.atan2(-dir.X, -dir.Z)
end

-- Yaw (about Y) and pitch (about X) that turn +Z to `v`.
local function aim(v: Vector3): (number, number)
	return math.atan2(v.X, v.Z), math.atan2(-v.Y, Vector2.new(v.X, v.Z).Magnitude)
end

local function wrap(a: number): number
	return (a + math.pi) % (math.pi * 2) - math.pi
end

--[[
	`body`: the Body joint's frame in root space this frame (after the
	animator moved it); `root`: the root's world CFrame; `sway(i)`: extra
	yaw in degrees for segment i (idle sway, coil).
]]
function CreatureSlither.step(
	layout: Layout,
	motors: { [string]: any },
	body: CFrame,
	root: CFrame,
	trail: { Vector3 },
	scale: number,
	sway: (number) -> number
)
	local parent = body
	-- The trail: where the chest has been, at the root's height.
	local head = root * Vector3.new(body.Position.X, 0, body.Position.Z)
	if #trail == 0 or (head - trail[1]).Magnitude > 10 * scale then
		-- New, or teleported: lay the body straight out behind.
		local back = root:VectorToWorldSpace(Vector3.new(0, 0, 1))
		table.clear(trail)
		trail[1] = head
		trail[2] = head + back * (layout.lead + layout.total + 2 * scale)
	elseif #trail >= 2 and (head - trail[2]).Magnitude < TRAIL_STEP * scale then
		trail[1] = head
	else
		table.insert(trail, 1, head)
	end
	-- Forget the trail beyond the tail.
	local along = 0
	for i = 1, #trail - 1 do
		along += (trail[i + 1] - trail[i]).Magnitude
		if along > layout.lead + layout.total + 2 * scale then
			for j = #trail, i + 2, -1 do
				trail[j] = nil
			end
			break
		end
	end
	local behind = layout.lead
	for i = 1, layout.count do
		local joint = motors[`Seg{i}`]
		local jointFrame = parent * jointOffset(joint)
		behind += layout.restLen[i]
		-- Where the next joint should be: on the trail, at its rest height
		-- over the ground (the body tapers down to the tail).
		local goal = CreatureSlither.trailPoint(trail, behind) + Vector3.new(0, layout.restY[i + 1], 0)
		local wanted = jointFrame:VectorToObjectSpace(root:PointToObjectSpace(goal) - jointFrame.Position)
		local restYaw, restPitch = aim(layout.restDir[i])
		local yaw, pitch = restYaw, restPitch
		if wanted.Magnitude > 1e-3 then
			local wantYaw, wantPitch = aim(wanted)
			yaw = restYaw + math.clamp(wrap(wantYaw - restYaw), -MAX_SEGMENT_YAW, MAX_SEGMENT_YAW)
			pitch = restPitch + math.clamp(wantPitch - restPitch, -MAX_SEGMENT_PITCH, MAX_SEGMENT_PITCH)
		end
		local transform = CFrame.Angles(0, yaw + math.rad(sway(i)), 0)
			* CFrame.Angles(pitch, 0, 0)
			* (CFrame.Angles(0, restYaw, 0) * CFrame.Angles(restPitch, 0, 0)):Inverse()
		joint.Transform = transform
		parent = segmentFrame(joint, jointFrame, transform)
	end
end

return table.freeze(CreatureSlither)
