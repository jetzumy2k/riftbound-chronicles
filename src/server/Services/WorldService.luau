--!strict
--[[
	WorldService (Layer 5)
	Builds the Phase 3 graybox world from WorldLayout: one floating platform per
	race capital, a fixed SpawnLocation each, and a visible safe-zone ring.
	Phase 16 replaces the visuals; the anchors in WorldLayout stay.

	Exposes the SpawnLocation for each race (deterministic spawning).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local WorldLayout = require(Shared.Definitions.WorldLayout)
local Log = require(Shared.Util.Log)

local FOLDER_NAME = "RC_World"

local CombatService = require(script.Parent.CombatService)

local NPC_FOLDER_NAME = "RC_Npcs"
local DUMMY_COLOR = Color3.fromRGB(196, 168, 120)

local log = Log.new("WorldService")

local WorldService = {}

local spawnByRace: { [string]: SpawnLocation } = {}

local function v3(t: { number }): Vector3
	return Vector3.new(t[1], t[2], t[3])
end

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function block(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function decorative(part: BasePart)
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
end

local function buildRealm(root: Folder, realm: WorldLayout.Realm, safeZone: WorldLayout.SafeZone?)
	local model = Instance.new("Model")
	model.Name = realm.zone
	-- Small graybox capitals stay loaded on every client so a spawning player
	-- never lands before the floor has streamed in.
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent

	local center = v3(realm.platformCenter)
	local size = v3(realm.platformSize)
	local base = rgb(realm.baseColor)
	local trim = rgb(realm.trimColor)
	local isAngel = realm.race == "Angel"
	local baseMaterial = if isAngel then Enum.Material.Marble else Enum.Material.Basalt

	block(model, "Platform", size, CFrame.new(center), base, baseMaterial)

	-- Glowing trim around the platform edge.
	local top = center.Y + size.Y / 2
	local half = size.X / 2
	for _, offset in { Vector3.new(0, 0, half), Vector3.new(0, 0, -half) } do
		local strip = block(
			model,
			"Trim",
			Vector3.new(size.X, 0.6, 1.2),
			CFrame.new(center + offset + Vector3.new(0, size.Y / 2, 0)),
			trim,
			Enum.Material.Neon
		)
		decorative(strip)
	end
	for _, offset in { Vector3.new(half, 0, 0), Vector3.new(-half, 0, 0) } do
		local strip = block(
			model,
			"Trim",
			Vector3.new(1.2, 0.6, size.Z),
			CFrame.new(center + offset + Vector3.new(0, size.Y / 2, 0)),
			trim,
			Enum.Material.Neon
		)
		decorative(strip)
	end

	-- Corner pillars give the capital a silhouette in graybox.
	local inset = half - 12
	for _, corner in
		{
			Vector3.new(inset, 0, inset),
			Vector3.new(-inset, 0, inset),
			Vector3.new(inset, 0, -inset),
			Vector3.new(-inset, 0, -inset),
		}
	do
		block(
			model,
			"Pillar",
			Vector3.new(8, 36, 8),
			CFrame.new(center.X + corner.X, top + 18, center.Z + corner.Z),
			base,
			baseMaterial
		)
		local cap = block(
			model,
			"PillarGlow",
			Vector3.new(9, 1.5, 9),
			CFrame.new(center.X + corner.X, top + 36.75, center.Z + corner.Z),
			trim,
			Enum.Material.Neon
		)
		decorative(cap)
	end

	-- Fixed spawn point (deterministic: one per race).
	local spawnPosition = v3(realm.spawnPosition)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = `Spawn_{realm.race}`
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = CFrame.lookAt(
		Vector3.new(spawnPosition.X, top + 0.5, spawnPosition.Z),
		Vector3.new(realm.spawnLookAt[1], top + 0.5, realm.spawnLookAt[3])
	)
	spawn.Color = trim
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Neutral = true
	spawn.Duration = 0 -- spawn protection is a combat-state concern (Phase 6), not a ForceField
	spawn.Enabled = true
	spawn.Parent = model
	spawnByRace[realm.race] = spawn

	-- Training yard: open ground outside the safe zone for melee and ranged practice.
	local yardCenter, yardSize = WorldLayout.trainingYard(realm)
	local yardCF = CFrame.new(v3(yardCenter))
	local yardFloor = block(model, "TrainingYard", v3(yardSize), yardCF, base:Lerp(trim, 0.12), baseMaterial)
	yardFloor:SetAttribute("RC_Zone", "TrainingGrounds")
	local yardTop = yardCenter[2] + yardSize[2] / 2
	local dir = WorldLayout.yardDirection(realm)
	local dummies = WorldLayout.dummyPositions(realm)
	local lineZ = dummies[1][3]
	for _, distance in WorldLayout.TrainingYard.rangeMarkers do
		local z = lineZ - dir * distance
		local stripe = block(
			model,
			"RangeMarker",
			Vector3.new(yardSize[1] - 16, 0.1, 0.6),
			CFrame.new(yardCenter[1], yardTop + 0.05, z),
			trim,
			Enum.Material.Neon
		)
		decorative(stripe)
		stripe.Transparency = 0.45
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(90, 26)
		gui.StudsOffset = Vector3.new(-(yardSize[1] / 2 - 14), 1.2, 0)
		gui.MaxDistance = 90
		gui.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Text = `{distance} studs`
		label.TextSize = 16
		label.FontFace = Font.fromEnum(Enum.Font.GothamBold)
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextStrokeTransparency = 0.3
		label.Parent = gui
		gui.Parent = stripe
	end
	local sign = block(
		model,
		"TrainingSign",
		Vector3.new(18, 5, 1),
		CFrame.new(yardCenter[1], yardTop + 6, yardCenter[3] - dir * (yardSize[3] / 2 - 4))
			* CFrame.Angles(0, if dir > 0 then math.pi else 0, 0),
		trim,
		Enum.Material.Neon
	)
	decorative(sign)
	local signGui = Instance.new("SurfaceGui")
	signGui.Face = Enum.NormalId.Back
	signGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	signGui.PixelsPerStud = 30
	local signText = Instance.new("TextLabel")
	signText.BackgroundTransparency = 1
	signText.Size = UDim2.fromScale(1, 1)
	signText.Text = "⚔  TRAINING GROUNDS  ⚔"
	signText.TextScaled = true
	signText.FontFace = Font.fromEnum(Enum.Font.Merriweather)
	signText.TextColor3 = Color3.fromRGB(40, 24, 8)
	signText.Parent = signGui
	signGui.Parent = sign
	local signBack = signGui:Clone()
	signBack.Face = Enum.NormalId.Front
	signBack.Parent = sign

	-- Visible safe-zone boundary ring (purely visual).
	if safeZone and safeZone.volume.kind == "cylinder" then
		local radius = safeZone.volume.radius :: number
		local ring = Instance.new("Part")
		ring.Name = "SafeZoneRing"
		ring.Anchored = true
		ring.Shape = Enum.PartType.Cylinder
		ring.Size = Vector3.new(0.2, radius * 2, radius * 2)
		ring.CFrame = CFrame.new(center.X, top + 0.15, center.Z) * CFrame.Angles(0, 0, math.rad(90))
		ring.Color = trim
		ring.Material = Enum.Material.ForceField
		ring.Transparency = 0.6
		decorative(ring)
		ring.Parent = model
	end

	model.Parent = root
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
		buildRealm(root, realm, zonesById[realm.zone])
	end

	root.Parent = Workspace
	log:Info("graybox world built")
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

-- Returns the fixed SpawnLocation for `race`.
function WorldService:GetSpawnLocation(race: string): SpawnLocation?
	return spawnByRace[race]
end

return WorldService
