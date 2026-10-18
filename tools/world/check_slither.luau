--[[
	Offline slither check (authoring aid, not shipped; PLAN.md D-54). Builds
	a serpent with the real CreatureBuilder and moves it over bumpy ground
	with the animator's chest weave and the shared follow-the-leader maths
	(Animation/CreatureSlither), then reports, after the body has laid its
	trail:

	  slip    the fastest the middle of any body segment moves sideways to
	          that segment, as a share of the speed (a slithering body moves along
	          itself: should be ~0, no sliding / skating)
	  height  the worst difference between a joint's height above the
	          ground under it and its rest height (should be ~0: the body
	          lies on the ground over bumps, never floating)
	  weave   how far the middle of the body swings side to side (studs):
	          the S must be visible

	From the repository root:

	    lune run tools/world/check_slither [EnemyId | mesh | all] [speed]
]]

local roblox = require("@lune/roblox")
local process = require("@lune/process")
local load = require("../../tests/pure/loader")

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
for _, name in { "Instance", "CFrame", "Vector3", "Vector2", "Color3", "Enum", "UDim2", "Font" } do
	load.globals[name] = (roblox :: any)[name]
end
load.globals.Random = RandomShim
roblox.implementMethod("Model", "PivotTo", function(model: any, target: any)
	local primary = model.PrimaryPart
	local delta = target * primary.CFrame:Inverse()
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CFrame = delta * d.CFrame
		end
	end
end)
roblox.implementMethod("Humanoid", "SetStateEnabled", function() end)

local CreatureBuilder = load("src/server/World/CreatureBuilder")
local EnemyDefinitions = load("src/shared/Definitions/EnemyDefinitions")
local CreatureSlither = load("src/shared/Animation/CreatureSlither")
local CFrame = roblox.CFrame
local Vector3 = roblox.Vector3

local id = process.args[1] or "all"
if id == "all" then
	local ids = {}
	for enemyId, def in EnemyDefinitions.ById do
		if def.body == "Serpent" then
			table.insert(ids, enemyId)
		end
	end
	table.sort(ids)
	local failed = 0
	for _, enemyId in ids do
		for _, speed in { "4", "12" } do
			local result = ((process :: any).exec or (process :: any).spawn)(
				"lune",
				{ "run", "tools/world/check_slither", enemyId, speed },
				{ shell = true }
			)
			if not result.ok then
				failed += 1
			end
			print((string.gsub(result.stdout, "%s+$", "")))
		end
	end
	local meshResult = ((process :: any).exec or (process :: any).spawn)(
		"lune",
		{ "run", "tools/world/check_slither", "mesh" },
		{ shell = true }
	)
	print((string.gsub(meshResult.stdout, "%s+$", "")))
	if not meshResult.ok then
		failed += 1
	end
	print(`{#ids} serpents checked slow and fast, and the Serpent and Gorgon meshes: {failed} failed`)
	process.exit(if failed == 0 then 0 else 1)
end

-- "mesh": the sculpted serpent bodies' skeletons (build/creatures/
-- Serpent.gltf, Gorgon.gltf bones; Bone joints instead of Motor6Ds), at
-- sizes 1 and 3.
if id == "mesh" then
	local fs = require("@lune/fs")
	local serde = require("@lune/serde")
	local failed = 0
	for _, shapeName in { "Serpent", "Gorgon" } do
		local gltf = serde.decode("json", fs.readFile(`build/creatures/{shapeName}.gltf`))
		local offsets = {}
		for _, node in gltf.nodes do
			if node.name and node.translation then
				offsets[node.name] =
					Vector3.new(node.translation[1], node.translation[2], node.translation[3])
			end
		end
		local function fakeBone(offset: any): any
			return {
				CFrame = CFrame.new(offset),
				Transform = CFrame.identity,
				IsA = function(_, class: string): boolean
					return class == "Bone"
				end,
			}
		end
		for _, s in { 1, 3 } do
			for _, speed in { 4, 12 } do
				local motors: { [string]: any } = {}
				local count = 0
				while offsets[`Seg{count + 1}`] do
					count += 1
					motors[`Seg{count}`] = fakeBone(offsets[`Seg{count}`] * s)
				end
				-- The root sits on the Body bone, which stands `height` up.
				local height = offsets.Body.Y * s
				local layout = assert(CreatureSlither.layout(motors, count, CFrame.identity))
				local trail = {}
				local distance = 0
				local dt = 1 / 60
				local last = {}
				local slip, heightErr, weaveMin, weaveMax = 0, 0, math.huge, -math.huge
				local function ground(z: number): number
					return (math.sin(z * 0.35 / s) * 0.8 + math.sin(z * 0.9 / s) * 0.25) * s * 0.5
				end
				local warmup = (layout.total + 4 * s) / speed
				for frame = 0, math.floor((warmup + 6) / dt) do
					local z = -distance
					local rootCF = CFrame.new(0, height + ground(z), z)
					local weaveX = CreatureSlither.weave(layout, distance)
					local yaw = CreatureSlither.heading(layout, trail, rootCF, weaveX) or 0
					local body = CFrame.new(weaveX, 0, 0) * CFrame.Angles(0, yaw, 0)
					CreatureSlither.step(layout, motors, body, rootCF, trail, s, function()
						return 0
					end)
					local joints = {}
					local parent = body
					for i = 1, count do
						local bone = motors[`Seg{i}`]
						local jointFrame = parent * bone.CFrame
						joints[i] = rootCF * jointFrame.Position
						parent = jointFrame * bone.Transform
					end
					joints[count + 1] = rootCF * (parent * CFrame.new(layout.restDir[count])).Position
					if frame * dt > warmup then
						for i = 2, count + 1 do
							local p = joints[i]
							heightErr = math.max(
								heightErr,
								math.abs((p.Y - ground(p.Z)) - (height + layout.restY[i]))
							)
							local middle = (joints[i - 1] + p) / 2
							if last[i] then
								local v = (middle - last[i]) / dt
								local along = joints[i - 1] - p
								local flat = Vector3.new(along.X, 0, along.Z)
								if flat.Magnitude > 1e-3 then
									local t = flat.Unit
									local flatV = Vector3.new(v.X, 0, v.Z)
									slip = math.max(slip, (flatV - t * flatV:Dot(t)).Magnitude / speed)
								end
							end
						end
						local mid = joints[math.floor(count / 2)]
						weaveMin, weaveMax = math.min(weaveMin, mid.X), math.max(weaveMax, mid.X)
					end
					for i = 2, count + 1 do
						last[i] = (joints[i - 1] + joints[i]) / 2
					end
					distance += speed * dt
				end
				local weave = weaveMax - weaveMin
				local ok = slip < 0.08 and heightErr < 0.25 * s and weave > 0.5 * s
				if not ok then
					failed += 1
				end
				print(
					string.format(
						"%-4s %s mesh (size %d, %d bones, %.1f studs long) at %d studs/s: slip %.1f%% of speed, height error %.2f, weave %.2f studs",
						if ok then "ok" else "FAIL",
						shapeName,
						s,
						count,
						layout.total,
						speed,
						slip * 100,
						heightErr,
						weave
					)
				)
			end
		end
	end
	process.exit(if failed == 0 then 0 else 1)
end

local enemy = EnemyDefinitions.get(id)
assert(enemy and enemy.body == "Serpent", `{id} is not a serpent`)
local speed = tonumber(process.args[2]) or 8
local s = enemy.scale

local model = CreatureBuilder.build(id, CFrame.new(0, 0, 0))
local root = model:FindFirstChild("HumanoidRootPart")
local rootHeight = root.CFrame.Y
local motors: { [string]: any } = {}
local motorOf: { [any]: any } = {}
local count = 0
for _, d in model:GetDescendants() do
	if d:IsA("Motor6D") then
		motors[d.Name] = d
		motorOf[d.Part1] = d
		local seg = tonumber(string.match(d.Name, "^Seg(%d+)$"))
		if seg then
			count = math.max(count, seg)
		end
	end
end
assert(count > 0 and motors.Body, `{id}: no body segments`)

-- Root-space frame of a part through the motors' current Transforms.
local function frameOf(part: any): any
	if part == root then
		return CFrame.identity
	end
	local motor = motorOf[part]
	return frameOf(motor.Part0) * motor.C0 * motor.Transform * motor.C1:Inverse()
end

local body = motors.Body
local layout = CreatureSlither.layout(motors, count, body.C0 * body.C1:Inverse())
assert(layout, "layout")

-- Bumpy ground the root rides over (as the Humanoid keeps its hip height).
local function ground(z: number): number
	return (math.sin(z * 0.35 / s) * 0.8 + math.sin(z * 0.9 / s) * 0.25) * s
end

local trail = {}
local dt = 1 / 60
local distance = 0
local last: { [number]: any } = {}
local slip, heightErr, weaveMin, weaveMax = 0, 0, math.huge, -math.huge
local mid = math.max(1, math.floor(count / 2))
local warmup = (layout.total + 4 * s) / speed
for frame = 0, math.floor((warmup + 6) / dt) do
	local time = frame * dt
	local z = -distance
	local rootCF = CFrame.new(0, rootHeight + ground(z), z)
	local weaveX = CreatureSlither.weave(layout, distance)
	local weaveYaw = CreatureSlither.heading(layout, trail, rootCF, weaveX) or 0
	body.Transform = CFrame.new(weaveX, 0, 0) * CFrame.Angles(0, weaveYaw, 0)
	CreatureSlither.step(layout, motors, frameOf(body.Part1), rootCF, trail, s, function()
		return 0
	end)
	-- Joint world positions (Seg1 .. SegN and the tail tip).
	local joints = {}
	for i = 1, count do
		local motor = motors[`Seg{i}`]
		joints[i] = rootCF * (frameOf(motor.Part0) * motor.C0).Position
	end
	local lastMotor = motors[`Seg{count}`]
	joints[count + 1] = rootCF
		* (frameOf(lastMotor.Part1) * lastMotor.C1 * CFrame.new(layout.restDir[count])).Position
	if time > warmup then
		for i = 2, count + 1 do
			local p = joints[i]
			-- Height above the ground under it vs. at rest.
			local expected = rootHeight + layout.restY[i]
			heightErr = math.max(heightErr, math.abs((p.Y - ground(p.Z)) - expected))
			-- The middle of the segment from joint i - 1 to joint i.
			local middle = (joints[i - 1] + p) / 2
			local prev = last[i]
			if prev then
				local v = (middle - prev) / dt
				local along = joints[i - 1] - p
				local flatAlong = Vector3.new(along.X, 0, along.Z)
				if flatAlong.Magnitude > 1e-3 then
					local t = flatAlong.Unit
					local flatV = Vector3.new(v.X, 0, v.Z)
					local sideways = (flatV - t * flatV:Dot(t)).Magnitude
					slip = math.max(slip, sideways / speed)
				end
			end
		end
		weaveMin = math.min(weaveMin, joints[mid].X)
		weaveMax = math.max(weaveMax, joints[mid].X)
	end
	for i = 2, count + 1 do
		last[i] = (joints[i - 1] + joints[i]) / 2
	end
	distance += speed * dt
end

local weave = weaveMax - weaveMin
local ok = slip < 0.08 and heightErr < 0.25 * s and weave > 0.5 * s
print(
	string.format(
		"%-4s %s (size %.1f, %d segments, %.1f studs long) at %.0f studs/s: slip %.1f%% of speed, height error %.2f, weave %.2f studs",
		if ok then "ok" else "FAIL",
		id,
		s,
		count,
		layout.total,
		speed,
		slip * 100,
		heightErr,
		weave
	)
)
process.exit(if ok then 0 else 1)
