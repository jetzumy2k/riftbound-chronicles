--[[
	Runs the real CapitalBuilder offline (Lune's Roblox instance library) and
	dumps every part as JSON for tools/world/render_capitals.py
	(authoring aid, not shipped). From the repository root:

	    lune run tools/world/dump_capitals > build/capitals.json
]]

local roblox = require("@lune/roblox")
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

local WorldLayout = load("src/shared/Definitions/WorldLayout")
local CapitalBuilder = load("src/server/World/CapitalBuilder")

local root = roblox.Instance.new("Folder")
local zones = {}
for _, zone in WorldLayout.SafeZones do
	zones[zone.id] = zone
end

local out = {}
for race, realm in WorldLayout.Realms do
	local built = CapitalBuilder.build(root, realm, zones[realm.zone])
	local parts = {}
	local capital = root:FindFirstChild(realm.zone)
	for _, d in capital:GetDescendants() do
		if d:IsA("BasePart") then
			local cf = d.CFrame
			local rx, ry, rz = cf.XVector, cf.YVector, cf.ZVector
			local shape = if d:IsA("Part") then d.Shape.Name else d.ClassName
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
	out[race] = { center = realm.platformCenter, parts = parts, count = built.parts }
end
print(serde.encode("json", out))
