--[[
	Runs the real world builders offline (Lune's Roblox instance library)
	and dumps every part as JSON for tools/world/render_capitals.py
	(authoring aid, not shipped). From the repository root:

	    lune run tools/world/dump_capitals [all|capitals|dungeon|creatures] > build/world.json
]]

local roblox = require("@lune/roblox")
local process = require("@lune/process")
local serde = require("@lune/serde")
local load = require("../../tests/pure/loader")

-- Minimal Random (not provided by @lune/roblox): deterministic LCG.
local RandomShim = {}
RandomShim.__index = RandomShim
function RandomShim.new(seed: number?)
	return setmetatable({ state = (seed or 1) % 2147483647 + 1 }, RandomShim)
end
function RandomShim:NextNumber(min: number?, max: number?): number
	self.state = (self.state * 48271) % 2147483647
	local u = self.state / 2147483647
	local lo, hi = min or 0, max or 1
	return lo + (hi - lo) * u
end

for _, name in
	{
		"Instance",
		"CFrame",
		"Vector3",
		"Vector2",
		"Color3",
		"Enum",
		"UDim2",
		"Font",
		"NumberSequence",
		"NumberSequenceKeypoint",
		"ColorSequence",
		"NumberRange",
	}
do
	load.globals[name] = (roblox :: any)[name]
end
load.globals.Random = RandomShim

-- @lune/roblox's CFrame.lookAt flips the look direction's Z; use Roblox's
-- definition so the preview matches the game.
local RealCFrame = roblox.CFrame
local function lookAt(at: any, target: any, up: any?): any
	local look = (target - at).Unit
	local worldUp = up or roblox.Vector3.new(0, 1, 0)
	if math.abs(look:Dot(worldUp)) > 0.999 then
		worldUp = roblox.Vector3.new(0, 0, 1)
	end
	local right = look:Cross(worldUp).Unit
	local trueUp = right:Cross(look)
	return RealCFrame.fromMatrix(at, right, trueUp, -look)
end
load.globals.CFrame = setmetatable({ lookAt = lookAt }, { __index = RealCFrame })
do
	local check = lookAt(roblox.Vector3.new(0, 0, 0), roblox.Vector3.new(0, -1, 1))
	assert((check.LookVector - roblox.Vector3.new(0, -1, 1).Unit).Magnitude < 1e-4, "lookAt shim is wrong")
end

-- @lune/roblox has no Model:PivotTo; same behaviour as Roblox (pivot = PrimaryPart).
roblox.implementMethod("Model", "PivotTo", function(model: any, target: any)
	local primary = model.PrimaryPart
	if primary == nil then
		return
	end
	local delta = target * primary.CFrame:Inverse()
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CFrame = delta * d.CFrame
		end
	end
end)

-- Engine-only behaviour the preview does not need.
roblox.implementMethod("Humanoid", "SetStateEnabled", function() end)

local WorldLayout = load("src/shared/Definitions/WorldLayout")
local CapitalBuilder = load("src/server/World/CapitalBuilder")
local DungeonBuilder = load("src/server/World/DungeonBuilder")
local CreatureBuilder = load("src/server/World/CreatureBuilder")
local DungeonDefinitions = load("src/shared/Definitions/DungeonDefinitions")
local EnemyDefinitions = load("src/shared/Definitions/EnemyDefinitions")

local function dumpParts(container: any): { any }
	local parts = {}
	for _, d in container:GetDescendants() do
		if d:IsA("BasePart") then
			local cf = d.CFrame
			local rx, ry, rz = cf.XVector, cf.YVector, cf.ZVector
			local mesh = d:FindFirstChildOfClass("SpecialMesh")
			local round = (mesh and mesh.MeshType == roblox.Enum.MeshType.Sphere)
				or (d:IsA("Part") and d.Shape == roblox.Enum.PartType.Ball)
			local shape = if round then "Ellipsoid" elseif d:IsA("Part") then d.Shape.Name else d.ClassName
			table.insert(parts, {
				c = { cf.Position.X, cf.Position.Y, cf.Position.Z },
				x = { rx.X, rx.Y, rx.Z },
				y = { ry.X, ry.Y, ry.Z },
				z = { rz.X, rz.Y, rz.Z },
				s = { d.Size.X, d.Size.Y, d.Size.Z },
				col = { d.Color.R, d.Color.G, d.Color.B },
				t = d.Transparency,
				shape = shape,
				m = d.Material.Name,
			})
		end
	end
	return parts
end

local root = roblox.Instance.new("Folder")
local zones = {}
for _, zone in WorldLayout.SafeZones do
	zones[zone.id] = zone
end

local out = {}
local only = (process.args[1] or "all")
if only == "all" or only == "capitals" then
	for race, realm in WorldLayout.Realms do
		local built = CapitalBuilder.build(root, realm, zones[realm.zone])
		out[race] = { center = realm.platformCenter, parts = dumpParts(root:FindFirstChild(realm.zone)), count = built.parts }
	end
end
if only == "all" or only == "dungeon" then
	local dungeon = DungeonDefinitions.get("RiftHollow")
	local map = DungeonBuilder.build(dungeon)
	map.Parent = root
	-- Place every room's enemies as they spawn in a run.
	for index, room in dungeon.rooms do
		for _, spawn in room.spawns do
			local creature = CreatureBuilder.build(spawn.enemy, DungeonBuilder.spawnCFrame(dungeon, index, spawn.x, spawn.z))
			creature.Parent = map
		end
	end
	local parts = dumpParts(map)
	out.Dungeon = { center = { 0, 0, -DungeonDefinitions.length(dungeon) / 2 }, parts = parts, count = #parts, half = 230 }
end
if only == "all" or only == "creatures" then
	local holder = roblox.Instance.new("Folder")
	local x = -24
	local ids = {}
	for id in EnemyDefinitions.ById do
		if process.args[2] == nil or process.args[2] == id then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	for _, id in ids do
		local creature = CreatureBuilder.build(id, roblox.CFrame.new(x, 0, 0))
		creature.Parent = holder
		x += 12
	end
	local parts = dumpParts(holder)
	local single = process.args[2] ~= nil
	out.Creatures = {
		center = if single then { -24, 2, 0 } else { 12, 0, 0 },
		parts = parts,
		count = #parts,
		half = if single then 7 else 26,
	}
end
print(serde.encode("json", out))
