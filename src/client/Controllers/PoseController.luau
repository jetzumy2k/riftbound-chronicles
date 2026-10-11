--!strict
--[[
	PoseController — small procedural offsets layered on top of the authored
	animation (CLAUDE.md §19).

	Body animation (idle, weapon holds, sprint, crouch, attacks, reactions)
	is authored keyframe animation played through the Animator
	(AnimationController, PLAN.md D-36). This controller only adds named
	per-joint offset *layers* from other controllers, e.g. the local
	player's lean into turns and head look (CharacterMotionController).

	Each frame, per tracked joint:

	    C0 = pivot × layer offsets × base rotation

	Offsets apply in the parent part's space at the joint pivot, so they
	compose with whatever the Animator plays (Motor6D.Transform). Joints are
	driven by Motor6D or, with Roblox's avatar joint upgrade, by an
	AnimationConstraint (offset = Attachment0.CFrame); whichever is active is
	used. Joints are re-scanned when the rig changes after spawn.

	Display only.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Log = require(Shared.Util.Log)

-- Pose joint name -> joint names to look for (R15 first, then R6).
local JOINT_NAMES: { [string]: { string } } = {
	Root = { "Root", "RootJoint" },
	Waist = { "Waist" },
	Neck = { "Neck" },
}

local log = Log.new("Pose")

type Joint = {
	motor: Motor6D?,
	attachment: Attachment?,
	pivot: CFrame,
	rotation: CFrame,
}

type Track = {
	character: Model,
	joints: { [string]: Joint },
	dirty: boolean,
	layers: { [string]: { [string]: CFrame } },
	jointCount: number?,
}

local PoseController = {}

local tracks: { [Model]: Track } = {}

-- Original offset of every joint driver we have touched (weak keys), so a
-- re-scan never mistakes our own offset for the rig's rest offset.
local baseOffsets: { [Instance]: CFrame } = setmetatable({}, { __mode = "k" }) :: any

local function restOffset(driver: Instance, current: CFrame): CFrame
	local base: CFrame? = baseOffsets[driver]
	if base then
		return base
	end
	baseOffsets[driver] = current
	return current
end

-- The active driver for a joint: an enabled AnimationConstraint wins over a
-- Motor6D (which the avatar joint upgrade leaves inactive).
local function findJoint(character: Model, names: { string }): Joint?
	local motor: Motor6D? = nil
	for _, descendant in character:GetDescendants() do
		if table.find(names, descendant.Name) == nil then
			continue
		end
		if descendant:IsA("AnimationConstraint") and descendant.Enabled and descendant.Attachment0 then
			local attachment = descendant.Attachment0 :: Attachment
			local base = restOffset(attachment, attachment.CFrame)
			return { attachment = attachment, pivot = CFrame.new(base.Position), rotation = base.Rotation }
		elseif descendant:IsA("Motor6D") and motor == nil then
			motor = descendant
		end
	end
	if motor then
		local base = restOffset(motor, motor.C0)
		return { motor = motor, pivot = CFrame.new(base.Position), rotation = base.Rotation }
	end
	return nil
end

local function rescan(entry: Track)
	entry.dirty = false
	local joints: { [string]: Joint } = {}
	local count = 0
	for name, candidates in JOINT_NAMES do
		local joint = findJoint(entry.character, candidates)
		if joint then
			joints[name] = joint
			count += 1
		end
	end
	entry.joints = joints
	if count ~= entry.jointCount then
		entry.jointCount = count
		log:Debug("layering %s (%d joints)", entry.character.Name, count)
	end
end

local function track(character: Model): Track
	local existing = tracks[character]
	if existing then
		return existing
	end
	local created: Track = { character = character, joints = {}, dirty = true, layers = {} }
	tracks[character] = created
	local function onJointChanged(descendant: Instance)
		if descendant:IsA("Motor6D") or descendant:IsA("AnimationConstraint") then
			created.dirty = true
		end
	end
	character.DescendantAdded:Connect(onJointChanged)
	character.DescendantRemoving:Connect(onJointChanged)
	character.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			tracks[character] = nil
		end
	end)
	return created
end

-- Sets (or clears, with nil) a named per-joint offset layer ("Root", "Waist", "Neck").
function PoseController.setLayer(character: Model, layer: string, joint: string, offset: CFrame?)
	local entry = if offset == nil then tracks[character] else track(character)
	if entry == nil then
		return
	end
	local layerTable = entry.layers[layer]
	if layerTable == nil then
		if offset == nil then
			return
		end
		layerTable = {}
		entry.layers[layer] = layerTable
	end
	-- nil clears the joint from this layer.
	layerTable[joint] = offset :: any
end

local function step()
	for _, entry in tracks do
		if entry.dirty then
			rescan(entry)
		end
		for name, joint in entry.joints do
			local driver: Instance? = joint.motor or joint.attachment
			if driver == nil or driver.Parent == nil then
				continue
			end
			local offset = CFrame.identity
			for _, layer in entry.layers do
				local extra = layer[name]
				if extra then
					offset *= extra
				end
			end
			local cf = joint.pivot * offset * joint.rotation
			if joint.motor then
				joint.motor.C0 = cf
			elseif joint.attachment then
				joint.attachment.CFrame = cf
			end
		end
	end
end

function PoseController:Init()
	Players.PlayerRemoving:Connect(function(player)
		local character = player.Character
		if character then
			tracks[character] = nil
		end
	end)
	RunService:BindToRenderStep("RC_Pose", Enum.RenderPriority.Character.Value + 1, step)
end

return PoseController
