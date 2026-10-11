local load = require("../loader")
local AnimationClips = load("src/shared/Definitions/AnimationClips")
local AnimationArms = load("src/shared/Definitions/AnimationArms")
local AnimationAssets = load("src/shared/Definitions/AnimationAssets")
local Enums = load("src/shared/Enums")

local AXES = { x = true, y = true, z = true, px = true, py = true, pz = true }

local function poseEqual(a, b): boolean
	for joint, value in a do
		for axis, amount in value do
			local other = b[joint] and b[joint][axis] or 0
			if math.abs(amount - other) > 1e-6 then
				return false
			end
		end
	end
	for joint, value in b do
		for axis, amount in value do
			local other = a[joint] and a[joint][axis] or 0
			if math.abs(amount - other) > 1e-6 then
				return false
			end
		end
	end
	return true
end

return function(t)
	t.it("every clip is well formed", function()
		for name, clip in AnimationClips.Clips do
			t.ok(clip.duration > 0 and clip.duration <= 3, `{name}: duration`)
			t.ok(table.find(AnimationClips.PRIORITIES, clip.priority) ~= nil, `{name}: priority`)
			t.ok(#clip.keys >= 2, `{name}: needs at least two keys`)
			t.eq(clip.keys[1].t, 0, `{name}: first key at 0`)
			t.near(clip.keys[#clip.keys].t, clip.duration, 1e-9, `{name}: last key at duration`)
			for index, key in clip.keys do
				if index > 1 then
					t.ok(key.t > clip.keys[index - 1].t, `{name}: key {index} time increases`)
				end
				if key.ease then
					t.ok(table.find(AnimationClips.EASES, key.ease) ~= nil, `{name}: ease {key.ease}`)
				end
				for joint, value in key.pose do
					t.ok(table.find(AnimationClips.JOINTS, joint) ~= nil, `{name}: joint {joint}`)
					for axis, amount in value do
						t.ok(AXES[axis] == true, `{name}: axis {axis}`)
						t.ok(amount == amount, `{name}.{joint}.{axis} is NaN`)
						local limit = if string.sub(axis, 1, 1) == "p" then 2 else 200
						t.ok(math.abs(amount) <= limit, `{name}.{joint}.{axis} = {amount} out of range`)
					end
				end
			end
			for marker, time in clip.markers or {} do
				t.ok(time > 0 and time < clip.duration, `{name}: marker {marker} inside the clip`)
			end
		end
	end)

	t.it("loops start and end on the same pose", function()
		for name, clip in AnimationClips.Clips do
			if clip.looped then
				t.ok(poseEqual(clip.keys[1].pose, clip.keys[#clip.keys].pose), `{name} does not loop cleanly`)
			end
		end
	end)

	t.it("every job has an idle, a weapon hold and three attacks", function()
		for _, job in Enums.Job do
			for _, suffix in { "_Idle", "_Hold", "_Attack1", "_Attack2", "_Attack3" } do
				t.ok(AnimationClips.get(job .. suffix) ~= nil, `missing {job}{suffix}`)
			end
			local idle = AnimationClips.get(job .. "_Idle")
			t.eq(idle.priority, "Idle", job)
			t.ok(idle.looped, job)
		end
		for _, name in { "Sprint", "CrouchIdle", "CrouchWalk", "HitLight", "HitHeavy", "Defeat" } do
			t.ok(AnimationClips.get(name) ~= nil, `missing {name}`)
		end
		t.eq(AnimationClips.get("Bard_Idle"), nil)
		t.eq(AnimationClips.get(42), nil)
	end)

	t.it("weapon holds only move the upper body (legs keep walking)", function()
		for _, job in Enums.Job do
			for _, joint in AnimationClips.jointsOf(AnimationClips.get(job .. "_Hold")) do
				t.ok(table.find(AnimationClips.UPPER_JOINTS, joint) ~= nil, `{job}_Hold moves {joint}`)
			end
		end
	end)

	t.it("crouch loops leave the arms to the weapon hold", function()
		for _, name in { "CrouchIdle", "CrouchWalk" } do
			for _, joint in AnimationClips.jointsOf(AnimationClips.get(name)) do
				t.ok(
					string.find(joint, "Shoulder") == nil and string.find(joint, "Elbow") == nil,
					`{name}: {joint}`
				)
			end
		end
	end)

	t.it("standing feet stay roughly flat", function()
		-- Root + Hip + Knee + Ankle pitch ~ 0 keeps the sole on the floor.
		local function flat(clipName: string)
			for index, key in AnimationClips.get(clipName).keys do
				for _, side in { "Left", "Right" } do
					local function x(joint)
						local v = key.pose[joint]
						return v and v.x or 0
					end
					local sum = x("Root") + x(side .. "Hip") + x(side .. "Knee") + x(side .. "Ankle")
					t.ok(math.abs(sum) <= 16, `{clipName} key {index} {side} foot tilted {sum}`)
				end
			end
		end
		for _, job in Enums.Job do
			flat(job .. "_Idle")
		end
		flat("CrouchIdle")
	end)

	t.it("attacks have a Hit marker", function()
		for name, clip in AnimationClips.Clips do
			if string.find(name, "_Attack", 1, true) then
				t.ok(clip.markers ~= nil and clip.markers.Hit ~= nil, `{name}: Hit marker`)
			end
		end
	end)

	t.it("defeat holds its last pose", function()
		t.eq(AnimationClips.get("Defeat").hold, true)
		t.eq(AnimationClips.get("Defeat").priority, "Action4")
	end)

	t.it("solved arm poses are wired to real keys", function()
		for clipName, perKey in AnimationArms.Keys do
			local clip = AnimationClips.get(clipName)
			t.ok(clip ~= nil, `AnimationArms: unknown clip {clipName}`)
			for time, ids in perKey do
				local found = false
				for _, key in clip.keys do
					if string.format("%.3f", key.t) == time then
						found = true
					end
				end
				t.ok(found, `AnimationArms: {clipName} has no key at {time}`)
				for _, id in ids do
					t.ok(AnimationArms.Poses[id] ~= nil, `AnimationArms: missing pose {id}`)
				end
			end
		end
		for _, job in Enums.Job do
			t.ok(AnimationArms.Poses[job .. ".hold"] ~= nil, `{job}.hold`)
		end
	end)

	t.it("mirror swaps sides and flips turns", function()
		local m =
			AnimationClips.mirror({ LeftHip = { x = 10, z = -4 }, Waist = { y = 8 }, Root = { px = 1 } })
		t.eq(m.RightHip.x, 10)
		t.eq(m.RightHip.z, 4)
		t.eq(m.LeftHip, nil)
		t.eq(m.Waist.y, -8)
		t.eq(m.Root.px, -1)
	end)

	t.it("names are sorted and published ids are well formed", function()
		for index = 2, #AnimationClips.NAMES do
			t.ok(AnimationClips.NAMES[index - 1] < AnimationClips.NAMES[index])
		end
		for asset, id in AnimationAssets do
			local base = string.gsub(asset, "_Upper$", "")
			t.ok(AnimationClips.get(base) ~= nil, `AnimationAssets: unknown clip {asset}`)
			t.ok(string.match(id, "^rbxassetid://%d+$") ~= nil, `AnimationAssets: bad id for {asset}`)
		end
	end)

	t.it("clip data is frozen", function()
		t.throws(function()
			(AnimationClips.Clips :: any).Warrior_Idle = nil
		end)
		t.throws(function()
			(AnimationClips.get("Warrior_Attack1") :: any).keys[1].t = 5
		end)
	end)
end
