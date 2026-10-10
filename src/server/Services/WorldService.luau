--!strict
--[[
	WorldService (Layer 5)
	Builds the Phase 3 graybox world from WorldLayout: one floating platform per
	race capital, a fixed SpawnLocation each, and a visible safe-zone ring.
	Phase 16 replaces the visuals; the anchors in WorldLayout stay.

	Exposes the SpawnLocation for each race (deterministic spawning).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local WorldLayout = require(Shared.Definitions.WorldLayout)
local Log = require(Shared.Util.Log)

local FOLDER_NAME = "RC_World"

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

-- Returns the fixed SpawnLocation for `race`.
function WorldService:GetSpawnLocation(race: string): SpawnLocation?
	return spawnByRace[race]
end

return WorldService
