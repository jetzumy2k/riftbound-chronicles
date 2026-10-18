--[[
	Offline check of the sculpted creatures' skeletons against the game's
	leg IK (authoring aid, not shipped; PLAN.md D-52). For every shape in
	Animation/CreatureMeshes:

	  rest    the IK, asked to reach each foot's rest spot, must return the
	          bind angles the sculpt baked into the bones (same conventions
	          in Python and Luau)
	  walk    walking the legs through a full step cycle at a walk and a
	          run (bones composed like Roblox does: parent * CFrame *
	          Transform), planted feet must stay put and every foot must
	          reach its target

	    lune run tools/creatures/check_mesh_rigs
]]

local roblox = require("@lune/roblox")
local process = require("@lune/process")
local load = require("../../tests/pure/loader")

for _, name in { "CFrame", "Vector3", "Vector2" } do
	load.globals[name] = (roblox :: any)[name]
end

local CreatureMeshes = load("src/shared/Animation/CreatureMeshes")
local CreatureRigs = load("src/shared/Animation/CreatureRigs")
local CreatureIK = load("src/shared/Logic/CreatureIK")
local CreatureGait = load("src/shared/Animation/CreatureGait")
local CFrame = roblox.CFrame
local Vector3 = roblox.Vector3

local failed = 0
for shapeName, shape in CreatureMeshes.Shapes do
	if #shape.legs == 0 then
		print(`{shapeName}: no legs ({shape.bodyPlan})`)
		continue
	end
	local plan = { bodyCenter = Vector3.zero, height = shape.height, legs = shape.legs }
	-- Rest angles.
	local worstRest = 0
	for _, leg in shape.legs do
		local forward, down = CreatureRigs.restReach(plan, leg)
		local a1, a2, a3 = CreatureIK.solve(leg.lengths, leg.bend, math.rad(leg.footAngle), forward, down)
		worstRest = math.max(
			worstRest,
			math.abs(a1 - leg.rest.X),
			math.abs(a2 - leg.rest.Y),
			math.abs(a3 - leg.rest.Z)
		)
	end
	-- Walk / run: compose the bones, measure planting and reach.
	local results = {}
	for _, speed in { 5, 14 } do
		for _, scale in { 1, 3 } do
			local gaitName = if scale >= CreatureRigs.HEAVY_SCALE then shape.heavyGait else shape.gait
			local gait = CreatureRigs.Gaits[gaitName]
			local state = CreatureGait.state(gait, plan, scale, speed)
			local slide, err = 0, 0
			local last = {}
			local dt = 1 / 60
			local phase, distance = 0, 0
			for _ = 0, 480 do
				for _, leg in shape.legs do
					local offset = leg.walk + ((if gait.trot then leg.trot else leg.run) - leg.walk) * state.run
					local t = (phase + offset) % 1
					local home = Vector3.new(
						leg.hip.X + leg.reach.X,
						-shape.height + CreatureRigs.FOOT_CLEARANCE,
						leg.hip.Z + leg.reach.Y
					) * scale
					local target = CreatureGait.footTarget(home, t, state.duty, state.stride, state.lift, state.amp, 0)
					-- The parent bone (Chest / Hips) bobs and pitches a little.
					local parent = CFrame.new(0, math.sin(distance) * 0.05 * scale - state.crouch, 0) * CFrame.Angles(math.rad(math.sin(distance * 0.7) * 3), 0, 0)
					local hipLocal = leg.hip * scale
					-- The upper bone's CFrame relative to its parent, as the sculpt binds it.
					local upperCF = CFrame.new(hipLocal) * CFrame.Angles(0, math.rad(leg.splay), 0) * CFrame.Angles(leg.rest.X, 0, 0)
					local bones = {
						base = upperCF * CFrame.Angles(-leg.rest.X, 0, 0),
						rest = leg.rest,
						lengths = { leg.lengths[1] * scale, leg.lengths[2] * scale, leg.lengths[3] * scale },
						bend = leg.bend,
						splay = leg.splay,
					}
					local tu, tl, tf = CreatureGait.solveLeg(parent, bones, target, math.rad(leg.footAngle))
					local upperWorld = parent * upperCF * tu
					local lowerWorld = upperWorld * (CFrame.new(0, -bones.lengths[1], 0) * CFrame.Angles(leg.rest.Y, 0, 0)) * tl
					local footWorld = lowerWorld * (CFrame.new(0, -bones.lengths[2], 0) * CFrame.Angles(leg.rest.Z, 0, 0)) * tf
					local tip = footWorld * Vector3.new(0, -bones.lengths[3], 0)
					-- World = root moving forward.
					local worldTip = tip + Vector3.new(0, 0, -distance)
					err = math.max(err, (tip - target).Magnitude / scale)
					if t > state.duty * 0.05 and t < state.duty * 0.95 then
						local prev = last[leg.name]
						if prev then
							slide = math.max(slide, (worldTip - prev).Magnitude / dt / speed)
						end
						last[leg.name] = worldTip
					else
						last[leg.name] = nil
					end
				end
				distance += speed * dt
				phase = (phase + speed * dt / state.cycle) % 1
			end
			table.insert(results, { speed = speed, scale = scale, slide = slide, err = err })
		end
	end
	local ok = worstRest < 1e-3
	local line = string.format("%s: rest angle error %.1e", shapeName, worstRest)
	for _, r in results do
		line ..= string.format(" | %d studs/s size %d: slide %.1f%%, reach %.3f", r.speed, r.scale, r.slide * 100, r.err)
		ok = ok and r.slide < 0.02 and r.err < 0.12
	end
	print((if ok then "ok   " else "FAIL ") .. line)
	if not ok then
		failed += 1
	end
end
process.exit(if failed == 0 then 0 else 1)
