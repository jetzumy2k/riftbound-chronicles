--[[
	Dumps AnimationClips as JSON (stdout) for tools/anim/render_clips.py and
	tools/anim/generate_arms.py. Run from the repository root:
	    lune run tools/anim/dump_clips > build/clips.json
]]
local serde = require("@lune/serde")
local load = require("../../tests/pure/loader")
local AnimationClips = load("src/shared/Definitions/AnimationClips")

local out = {}
for name, clip in AnimationClips.Clips do
	local keys = {}
	for _, key in clip.keys do
		table.insert(keys, { t = key.t, ease = key.ease or "Linear", pose = key.pose })
	end
	out[name] = { duration = clip.duration, markers = clip.markers or {}, keys = keys }
end
print(serde.encode("json", out))
