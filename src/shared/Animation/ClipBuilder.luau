--!strict
--[[
	ClipBuilder — turns AnimationClips data into Roblox KeyframeSequences
	(PLAN.md D-36).

	Used by the client (AnimationController registers them for play-testing
	until the clips are published) and by tools/studio/ExportAnimations
	(builds them in Studio so the creator can "Save to Roblox").

	Variants:
	  Full   every joint the clip animates
	  Upper  waist, neck and arms only (played while walking, so the legs
	         keep their walk cycle)

	Pose tree follows the R15 part hierarchy. Parts that are only there to
	reach an animated child get Weight 0 (not animated).
]]

local AnimationClips = require(script.Parent.Parent.Definitions.AnimationClips)

local ClipBuilder = {}

export type Variant = "Full" | "Upper"

-- Joint -> the part it moves (Pose name), and each part's parent part.
local JOINT_PART: { [string]: string } = {
	Root = "LowerTorso",
	Waist = "UpperTorso",
	Neck = "Head",
	LeftShoulder = "LeftUpperArm",
	LeftElbow = "LeftLowerArm",
	LeftWrist = "LeftHand",
	RightShoulder = "RightUpperArm",
	RightElbow = "RightLowerArm",
	RightWrist = "RightHand",
	LeftHip = "LeftUpperLeg",
	LeftKnee = "LeftLowerLeg",
	LeftAnkle = "LeftFoot",
	RightHip = "RightUpperLeg",
	RightKnee = "RightLowerLeg",
	RightAnkle = "RightFoot",
}
local PARENT_PART: { [string]: string } = {
	LowerTorso = "HumanoidRootPart",
	UpperTorso = "LowerTorso",
	Head = "UpperTorso",
	LeftUpperArm = "UpperTorso",
	LeftLowerArm = "LeftUpperArm",
	LeftHand = "LeftLowerArm",
	RightUpperArm = "UpperTorso",
	RightLowerArm = "RightUpperArm",
	RightHand = "RightLowerArm",
	LeftUpperLeg = "LowerTorso",
	LeftLowerLeg = "LeftUpperLeg",
	LeftFoot = "LeftLowerLeg",
	RightUpperLeg = "LowerTorso",
	RightLowerLeg = "RightUpperLeg",
	RightFoot = "RightLowerLeg",
}
ClipBuilder.JOINT_PART = table.freeze(JOINT_PART)

local EASING: { [string]: { Enum.PoseEasingStyle | Enum.PoseEasingDirection } } = {
	Linear = { Enum.PoseEasingStyle.Linear, Enum.PoseEasingDirection.In },
	Constant = { Enum.PoseEasingStyle.Constant, Enum.PoseEasingDirection.In },
	-- CubicV2 uses the standard meaning of In / Out (the original Cubic is reversed).
	In = { Enum.PoseEasingStyle.CubicV2, Enum.PoseEasingDirection.In },
	Out = { Enum.PoseEasingStyle.CubicV2, Enum.PoseEasingDirection.Out },
	InOut = { Enum.PoseEasingStyle.CubicV2, Enum.PoseEasingDirection.InOut },
}

local function toCFrame(value: AnimationClips.JointKey): CFrame
	return CFrame.new(value.px or 0, value.py or 0, value.pz or 0)
		* CFrame.Angles(math.rad(value.x or 0), math.rad(value.y or 0), math.rad(value.z or 0))
end

-- Joints a variant of `clip` animates.
function ClipBuilder.joints(clip: AnimationClips.Clip, variant: Variant): { string }
	local joints = AnimationClips.jointsOf(clip)
	if variant == "Full" then
		return joints
	end
	local out = {}
	for _, joint in joints do
		if table.find(AnimationClips.UPPER_JOINTS, joint) then
			table.insert(out, joint)
		end
	end
	return out
end

-- Whether the Upper variant differs from Full (the clip moves the legs/hips).
function ClipBuilder.hasLowerBody(clip: AnimationClips.Clip): boolean
	return #ClipBuilder.joints(clip, "Full") ~= #ClipBuilder.joints(clip, "Upper")
end

function ClipBuilder.assetName(name: string, variant: Variant): string
	return if variant == "Upper" then name .. "_Upper" else name
end

function ClipBuilder.build(name: string, clip: AnimationClips.Clip, variant: Variant): KeyframeSequence
	local sequence = Instance.new("KeyframeSequence")
	sequence.Name = ClipBuilder.assetName(name, variant)
	sequence.Loop = clip.looped
	sequence.Priority = (Enum.AnimationPriority :: any)[clip.priority]

	local animated: { [string]: string } = {} -- part -> joint
	for _, joint in ClipBuilder.joints(clip, variant) do
		animated[JOINT_PART[joint]] = joint
	end

	for index, key in clip.keys do
		local keyframe = Instance.new("Keyframe")
		keyframe.Time = key.t
		-- Easing on a pose shapes the motion from this key to the next one.
		local nextKey = clip.keys[index + 1]
		local easing = EASING[(nextKey and nextKey.ease) or "Linear"]

		local poses: { [string]: Pose } = {}
		local function poseFor(part: string): Pose
			local existing = poses[part]
			if existing then
				return existing
			end
			local pose = Instance.new("Pose")
			pose.Name = part
			local joint = animated[part]
			if joint then
				pose.Weight = 1
				pose.CFrame = toCFrame(AnimationClips.valueAt(clip, index, joint))
				pose.EasingStyle = easing[1] :: Enum.PoseEasingStyle
				pose.EasingDirection = easing[2] :: Enum.PoseEasingDirection
			else
				pose.Weight = 0
			end
			poses[part] = pose
			local parentName = PARENT_PART[part]
			pose.Parent = if parentName then poseFor(parentName) else keyframe
			return pose
		end
		for part in animated do
			poseFor(part)
		end
		keyframe.Parent = sequence
	end

	local markers: { [string]: number } = clip.markers or {}
	for marker, time in markers do
		local keyframe = Instance.new("Keyframe")
		keyframe.Name = marker
		keyframe.Time = time
		local hasKey = false
		for _, key in clip.keys do
			if math.abs(key.t - time) < 1e-6 then
				hasKey = true
			end
		end
		if hasKey then
			-- Markers ride on the existing keyframe at that time.
			for _, existing in sequence:GetChildren() do
				if existing:IsA("Keyframe") and math.abs(existing.Time - time) < 1e-6 then
					local m = Instance.new("KeyframeMarker")
					m.Name = marker
					m.Parent = existing
				end
			end
			keyframe:Destroy()
		else
			local m = Instance.new("KeyframeMarker")
			m.Name = marker
			m.Parent = keyframe
			keyframe.Parent = sequence
		end
	end
	return sequence
end

return table.freeze(ClipBuilder)
