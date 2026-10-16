--!strict
--[[
	WorldService (Layer 5)
	Builds the race capitals from WorldLayout with World/CapitalBuilder
	(Skyreach Citadel, Emberdeep Bastion; PLAN.md D-37) and spawns the
	training dummies.

	Exposes the SpawnLocation for each race (deterministic spawning) and the
	capital portal gates.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local WorldLayout = require(Shared.Definitions.WorldLayout)
local Log = require(Shared.Util.Log)

local FOLDER_NAME = "RC_World"

local CombatService = require(script.Parent.CombatService)
local CapitalBuilder = require(script.Parent.Parent.World.CapitalBuilder)

local NPC_FOLDER_NAME = "RC_Npcs"
local DUMMY_COLOR = Color3.fromRGB(196, 168, 120)

local log = Log.new("WorldService")

local WorldService = {}

local spawnByRace: { [string]: SpawnLocation } = {}
-- Portal surfaces per race by gate id (dungeons / war zones hook in later).
local gatesByRace: { [string]: { [string]: BasePart } } = {}

local function v3(t: { number }): Vector3
	return Vector3.new(t[1], t[2], t[3])
end

function WorldService:Init()
	local existing = Workspace:FindFirstChild(FOLDER_NAME)
	if existing then
		existing:Destroy()
	end

	local root = Instance.new("Folder")
	root.Name = FOLDER_NAME

	local zonesById: { [string]: WorldLayout.SafeZone } = {}
	for _, zone in WorldLayout.SafeZones do
		zonesById[zone.id] = zone
	end

	for _, realm in WorldLayout.Realms :: { [string]: WorldLayout.Realm } do
		local built = CapitalBuilder.build(root, realm, zonesById[realm.zone])
		spawnByRace[realm.race] = built.spawn
		gatesByRace[realm.race] = built.gates
		log:Info("%s built (%d parts)", realm.displayName, built.parts)
	end

	root.Parent = Workspace
	log:Info("capitals built")
end

--------------------------------------------------------------------------------
-- Training dummies (Phase 6 test targets)
--------------------------------------------------------------------------------

-- Simple part-built humanoid used if avatar rig creation is unavailable.
local function fallbackDummy(): Model
	local model = Instance.new("Model")
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Transparency = 1
	root.Parent = model
	local torso = Instance.new("Part")
	torso.Name = "Torso"
	torso.Size = Vector3.new(2, 2, 1)
	torso.CFrame = root.CFrame
	torso.Parent = model
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1.2, 1.2, 1.2)
	head.CFrame = root.CFrame * CFrame.new(0, 1.6, 0)
	head.Parent = model
	for _, part in { torso, head } do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = part
		weld.Parent = part
	end
	local humanoid = Instance.new("Humanoid")
	humanoid.HipHeight = 2
	humanoid.Parent = model
	model.PrimaryPart = root
	return model
end

local function createDummy(): Model
	local description = Instance.new("HumanoidDescription")
	for _, field in
		{ "HeadColor", "TorsoColor", "LeftArmColor", "RightArmColor", "LeftLegColor", "RightLegColor" }
	do
		(description :: any)[field] = DUMMY_COLOR
	end
	local ok, rig = pcall(function()
		return Players:CreateHumanoidModelFromDescriptionAsync(description, Enum.HumanoidRigType.R15)
	end)
	if ok and rig then
		return rig
	end
	log:Warn("dummy rig creation failed (%s); using fallback", tostring(rig))
	return fallbackDummy()
end

local function spawnDummies(folder: Folder)
	local spec = WorldLayout.TrainingDummy
	for _, realm in WorldLayout.Realms :: { [string]: WorldLayout.Realm } do
		local center = v3(realm.platformCenter)
		for index, position in WorldLayout.dummyPositions(realm) do
			local model = createDummy()
			model.Name = "Training Dummy"
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			local root = model:FindFirstChild("HumanoidRootPart")
			if humanoid == nil or root == nil or not root:IsA("BasePart") then
				model:Destroy()
				continue
			end
			humanoid.DisplayName = "Training Dummy"
			humanoid.NameDisplayDistance = 60
			humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOn
			root.Anchored = true -- server-owned, never pushed around (SECURITY_MODEL T-33)
			local feet = v3(position)
			local height = humanoid.HipHeight + root.Size.Y / 2
			local base = Vector3.new(feet.X, feet.Y + height, feet.Z)
			model:PivotTo(CFrame.lookAt(base, Vector3.new(center.X, base.Y, center.Z)))
			model:SetAttribute("RC_Npc", "TrainingDummy")
			model:SetAttribute("RC_Index", index)
			model.Parent = folder
			CombatService:RegisterNpc(
				model,
				{ name = "Training Dummy", level = spec.level, maxHp = spec.maxHp }
			)
		end
	end
end

function WorldService:Start()
	local existing = Workspace:FindFirstChild(NPC_FOLDER_NAME)
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = NPC_FOLDER_NAME
	folder.Parent = Workspace
	spawnDummies(folder)
	log:Info("training dummies ready")
end

-- The portal surface of gate `gateId` in `race`'s capital (WorldLayout.City.gates).
function WorldService:GetGate(race: string, gateId: string): BasePart?
	local gates = gatesByRace[race]
	return if gates then gates[gateId] else nil
end

-- Returns the fixed SpawnLocation for `race`.
function WorldService:GetSpawnLocation(race: string): SpawnLocation?
	return spawnByRace[race]
end

return WorldService
