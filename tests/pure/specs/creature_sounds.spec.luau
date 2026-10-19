--[[
	Creature sounds (PLAN.md D-62): every creature has a voice, every cue
	exists, pitches stay sensible (Definitions/CreatureSounds). The ids'
	licence is checked online by tools/creatures/check_sounds.py.
]]

local load = require("../loader")
local CreatureSounds = load("src/shared/Definitions/CreatureSounds")

local SHAPES = {
	"Hound",
	"Cerberus",
	"Serpent",
	"Hydra",
	"Beetle",
	"Spider",
	"Golem",
	"Knight",
	"Lion",
	"Chimera",
	"Dragon",
	"Griffin",
	"Steed",
	"Bat",
	"Harpy",
	"Gorgon",
	"Sprite",
}

return function(t)
	t.describe("CreatureSounds", function()
		t.it("every sculpted shape and body plan has its own voice", function()
			for _, shape in SHAPES do
				t.ok(CreatureSounds.Voices[shape] ~= nil, shape)
			end
			for _, body in { "Wolf", "Serpent", "Golem", "Guardian", "Beetle", "Sprite" } do
				t.ok(CreatureSounds.voiceFor(nil, body) ~= nil, body)
			end
			t.eq(CreatureSounds.voiceFor("Dragon", "Guardian"), CreatureSounds.Voices.Dragon, "shape first")
		end)

		t.it("every cue the effects use exists with sane values", function()
			for _, name in
				{
					"Swish",
					"Impact",
					"RockImpact",
					"Clank",
					"Footstep",
					"Wings",
					"Dive",
					"Stagger",
					"BodyFall",
				}
			do
				local cue = CreatureSounds.Cues[name]
				t.ok(cue ~= nil, name)
				if cue then
					t.ok(cue.id > 0 and cue.volume > 0 and cue.volume <= 1 and cue.seconds > 0, name)
				end
			end
			local ids = CreatureSounds.allIds()
			local seen = {}
			for _, id in ids do
				t.ok(not seen[id], `duplicate {id}`)
				seen[id] = true
			end
			t.ok(#ids >= 20)
		end)

		t.it("bigger creatures sound deeper, within limits", function()
			local roar = CreatureSounds.Voices.Lion
			t.ok(CreatureSounds.pitchFor(roar, 3) < CreatureSounds.pitchFor(roar, 1))
			t.ok(CreatureSounds.pitchFor(roar, 10) >= roar.pitch * 0.6)
			t.ok(CreatureSounds.pitchFor(roar, 0.3) <= roar.pitch * 1.2)
		end)
	end)
end
