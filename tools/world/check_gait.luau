--[[
	Offline gait check (authoring aid, not shipped; PLAN.md D-51). Builds a
	creature with the real CreatureBuilder, walks it forward with the same
	gait maths the client uses (Animation/CreatureGait, Animation/CreatureRigs)
	while the body bobs and pitches, follows every bone with forward
	kinematics and reports, per leg:

	  slide   how far a planted foot moves over the ground during its
	          stance (should be ~0: no skating)
	  error   largest distance between the foot tip and its target
	  height  foot tip height above the ground while planted

	From the repository root:

	    lune run tools/world/check_gait <EnemyId> [speed] [frames.json]

	With a third argument it also writes 8 poses across one step cycle for
	tools/world/render_capitals.py.
]]

local roblox = require("@lune/roblox")
local process = require("@lune/process")
local fs = require("@lune/fs")
local serde = require("@lune/serde")
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
local CreatureRigs = load("src/shared/Animation/CreatureRigs")
local CreatureIK = load("src/shared/Logic/CreatureIK")
local CreatureGait = load("src/shared/Animation/CreatureGait")
local CFrame = roblox.CFrame
local Vector3 = roblox.Vector3

local id = process.args[1] or "RiftWolf"
-- "all": every legged creature at a walk and a run, each in its own run.
if id == "all" then
	local ids = {}
	for enemyId, def in EnemyDefinitions.ById do
		if CreatureRigs.plan(def.body) then
			table.insert(ids, enemyId)
		end
	end
	table.sort(ids)
	local failed = 0
	for _, enemyId in ids do
		for _, speed in { "", "16" } do
			local args = { "run", "tools/world/check_gait", enemyId }
			if speed ~= "" then
				table.insert(args, speed)
			end
			local result = ((process :: any).exec or (process :: any).spawn)("lune", args, { shell = true })
			if not result.ok then
				failed += 1
				print(result.stdout)
			end
		end
	end
	print(`{#ids} legged creatures checked at a walk and a run: {failed} failed`)
	process.exit(if failed == 0 then 0 else 1)
end
local enemy = EnemyDefinitions.get(id)
assert(enemy, `unknown enemy {id}`)
local plan = CreatureRigs.plan(enemy.body)
local gait = CreatureRigs.gaitFor(enemy.body, enemy.scale)
assert(plan and gait, `{id}: {enemy.body} has no legs`)
local speed = tonumber(process.args[2]) or enemy.moveSpeed * 0.35
local s = enemy.scale

local model = CreatureBuilder.build(id, CFrame.new(0, 0, 0))
local root = model:FindFirstChild("HumanoidRootPart")
local rootStart = root.CFrame
local motors: { [string]: any } = {}
local motorOf: { [any]: any } = {}
for _, d in model:GetDescendants() do
	if d:IsA("Motor6D") then
		motors[d.Name] = d
		motorOf[d.Part1] = d
	end
end
local transforms: { [any]: any } = {}

-- Rest-relative part offsets, so FK can rebuild any pose.
local function worldOf(part: any, rootCF: any): any
	if part == root then
		return rootCF
	end
	local motor = motorOf[part]
	if motor == nil then
		return rootCF
	end
	return worldOf(motor.Part0, rootCF)
		* motor.C0
		* (transforms[motor] or CFrame.identity)
		* motor.C1:Inverse()
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end
local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

type Leg = { spec: any, bones: any, home: any, upper: any, lower: any, foot: any }
local legs: { Leg } = {}
for _, spec in plan.legs do
	local upper = motors[spec.name]
	local rest = upper:GetAttribute("RestAngles")
	local hipRoot = plan.bodyCenter + spec.hip
	table.insert(legs, {
		spec = spec,
		upper = upper,
		lower = motors[`{spec.name}b`],
		foot = motors[`{spec.name}c`],
		bones = {
			base = upper.C0 * CFrame.Angles(-rest.X, 0, 0),
			rest = rest,
			lengths = { spec.lengths[1] * s, spec.lengths[2] * s, spec.lengths[3] * s },
			bend = spec.bend,
			splay = spec.splay,
		},
		home = Vector3.new(
			hipRoot.X + spec.reach.X,
			-plan.height + CreatureRigs.FOOT_CLEARANCE,
			hipRoot.Z + spec.reach.Y
		) * s,
	})
end

-- The animator's gait state for a speed.
local state = CreatureGait.state(gait, plan, s, speed)
local run, cycle, duty, stride, lift, amp =
	state.run, state.cycle, state.duty, state.stride, state.lift, state.amp

local bodyMotor = motors.Body
local function pose(phase: number, rootCF: any, time: number)
	-- The body bobs, pitches and rolls a little; feet must not care.
	local bodyT = CFrame.new(0, math.sin(time * 9) * 0.08 * s - state.crouch, math.sin(time * 5) * 0.05 * s)
		* CFrame.Angles(math.rad(math.sin(time * 4) * 4), 0, math.rad(math.sin(time * 6) * 3))
	transforms[bodyMotor] = bodyT
	local body = bodyMotor.C0 * bodyT * bodyMotor.C1:Inverse()
	local out = {}
	for _, leg in legs do
		local offset = lerp(leg.spec.walk, if gait.trot then leg.spec.trot else leg.spec.run, run)
		local t = (phase + offset) % 1
		local target = CreatureGait.footTarget(leg.home, t, duty, stride, lift, amp, 0)
		local a, b, c = CreatureGait.solveLeg(body, leg.bones, target, math.rad(leg.spec.footAngle))
		transforms[leg.upper], transforms[leg.lower], transforms[leg.foot] = a, b, c
		local footCF = worldOf(leg.foot.Part1, rootCF)
		local tip = footCF * Vector3.new(0, -leg.spec.lengths[3] * s / 2, 0)
		table.insert(out, { t = t, tip = tip, target = rootCF * target })
	end
	return out
end

local report: { [string]: { slide: number, err: number, minH: number, maxH: number } } = {}
for _, leg in legs do
	report[leg.spec.name] = { slide = 0, err = 0, minH = math.huge, maxH = -math.huge }
end
local dt = 1 / 60
local phase = 0
local distance = 0
local last: { [string]: any } = {}
local groundY = rootStart.Y - plan.height * s
for frame = 0, 600 do
	local time = frame * dt
	local rootCF = rootStart * CFrame.new(0, 0, -distance)
	local result = pose(phase, rootCF, time)
	for i, leg in legs do
		local r = report[leg.spec.name]
		local info = result[i]
		r.err = math.max(r.err, (info.tip - info.target).Magnitude)
		local planted = info.t < duty * 0.95 and info.t > duty * 0.05
		if planted then
			local h = info.tip.Y - groundY
			r.minH = math.min(r.minH, h)
			r.maxH = math.max(r.maxH, h)
			local prev = last[leg.spec.name]
			if prev then
				r.slide = math.max(r.slide, (info.tip - prev).Magnitude / dt)
			end
			last[leg.spec.name] = info.tip
		else
			last[leg.spec.name] = nil
		end
	end
	distance += speed * dt
	phase = (phase + speed * dt / cycle) % 1
end

print(
	string.format(
		"%s (%s, size %.1f, gait %s) at %.1f studs/s: run %.2f, cycle %.1f, duty %.2f, stride %.2f",
		id,
		enemy.body,
		s,
		gait.name,
		speed,
		run,
		cycle,
		duty,
		stride
	)
)
local worst = 0
for _, leg in legs do
	local r = report[leg.spec.name]
	worst = math.max(worst, r.slide / math.max(speed, 0.01))
	print(
		string.format(
			"  %-6s slide %.3f studs/s (%.1f%% of speed)  max error %.3f  planted height %.2f..%.2f",
			leg.spec.name,
			r.slide,
			r.slide / math.max(speed, 0.01) * 100,
			r.err,
			r.minH,
			r.maxH
		)
	)
end
local _ = CreatureIK

-- Poses for the renderer: 8 snapshots across one cycle, side by side.
local framesPath = process.args[3]
if framesPath then
	local holder = roblox.Instance.new("Folder")
	local parts = {}
	for k = 0, 7 do
		local rootCF = CFrame.new(0, rootStart.Y, k * 5.5 * s)
		pose(k / 8, rootCF, k * 0.1)
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d ~= root then
				local cf
				local motor = motorOf[d]
				if motor then
					cf = worldOf(d, rootCF)
				else
					-- Welded decoration: keep its rest offset from its part.
					local weld = d:FindFirstChildOfClass("WeldConstraint")
					local host = weld and weld.Part0
					if host and host ~= d then
						cf = worldOf(host, rootCF) * (host.CFrame:Inverse() * d.CFrame)
					else
						cf = rootCF * (rootStart:Inverse() * d.CFrame)
					end
				end
				local mesh = d:FindFirstChildOfClass("SpecialMesh")
				local rx, ry, rz = cf.XVector, cf.YVector, cf.ZVector
				table.insert(parts, {
					c = { cf.Position.X, cf.Position.Y, cf.Position.Z },
					x = { rx.X, rx.Y, rx.Z },
					y = { ry.X, ry.Y, ry.Z },
					z = { rz.X, rz.Y, rz.Z },
					s = { d.Size.X, d.Size.Y, d.Size.Z },
					col = { d.Color.R, d.Color.G, d.Color.B },
					t = d.Transparency,
					shape = if mesh or d.Shape == roblox.Enum.PartType.Ball
						then "Ellipsoid"
						else d.Shape.Name,
					m = d.Material.Name,
				})
			end
		end
	end
	local _ = holder
	fs.writeFile(
		framesPath,
		serde.encode("json", {
			Gait = { center = { 0, 6 * s, 19 * s }, parts = parts, count = #parts, half = 24 * s },
		})
	)
end
-- Pass: planted feet slide under 2% of the speed and reach their targets.
local reachOk = true
for _, leg in legs do
	if report[leg.spec.name].err > 0.12 * s then
		reachOk = false
	end
end
process.exit(if worst < 0.02 and reachOk then 0 else 1)
