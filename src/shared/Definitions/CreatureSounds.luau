--!strict
--[[
	CreatureSounds — the creatures' sound effects (creature overhaul stage
	5, PLAN.md D-62). Data only; the client plays them (Effects/CreatureSfx).

	Every id is a sound effect from the Pro Sound Effects library on the
	Roblox Creator Store (licensed for use in any experience), checked by
	`python tools/creatures/check_sounds.py` (asset type Audio, creator
	ProSoundEffects or Roblox).

	A sound: `id`, `volume` (0..1), `pitch` (PlaybackSpeed; the client also
	lowers it for bigger creatures) and `seconds` (it fades out after this
	long; the library clips run longer than a game cue needs).
]]

export type Sound = {
	id: number,
	volume: number,
	pitch: number,
	seconds: number,
}

local function sound(id: number, volume: number, pitch: number, seconds: number): Sound
	return table.freeze({ id = id, volume = volume, pitch = pitch, seconds = seconds })
end

local CreatureSounds = {}

-- Each sculpted shape's voice: the alert roar, some wind-ups, defeat.
CreatureSounds.Voices = table.freeze({
	-- Wolf Howl Two Versions 1 (the first howl; D-63: wolves howl, not snarl).
	Hound = sound(9120790529, 0.7, 1.05, 2.4),
	Cerberus = sound(9120790529, 0.8, 0.85, 2.6),
	-- Lion Roar Short Blast Attack Angry Sharp 4.
	Lion = sound(9116302511, 0.7, 1, 1.8),
	Chimera = sound(9116302511, 0.75, 0.85, 1.8),
	-- D-63: Hawk Bird Screeching Calls (storm birds, griffins, harpies) and
	-- Creature Screech Pterodactyl Vocals (the bat); the old prehistoric
	-- bird calls sounded like an elephant.
	Griffin = sound(9125598512, 0.75, 0.9, 1.8),
	Bat = sound(9125474229, 0.6, 1.25, 1.2),
	Harpy = sound(9125598509, 0.7, 1.05, 1.8),
	-- Lion Roar Growl Low Rumble Reverberant 1.
	Dragon = sound(9116300725, 0.8, 0.75, 2.6),
	-- Bull Grunts Snorts Constant 3.
	Steed = sound(9113636194, 0.6, 1.2, 1.6),
	-- Snake Growl 3.
	Serpent = sound(9119302282, 0.6, 1, 1.8),
	Hydra = sound(9119302282, 0.7, 0.8, 2),
	Gorgon = sound(9119302282, 0.6, 1.15, 1.6),
	-- Giant Bug Vocals 1 (D-63: the flying-insect buzz was too faint to hear);
	-- Creature Vocal Spider Sucking Hiss 7.
	Beetle = sound(9114574288, 0.9, 0.95, 1.6),
	Spider = sound(9113992234, 0.6, 1, 1.6),
	-- Rock Scrape Deep Clunky Slides Rumbling Thunder (D-63: a grinding stone
	-- giant, not a lion's roar).
	Golem = sound(9125879007, 0.9, 0.85, 2.2),
	-- Robot Voice Low Pitch Nasty Growls Screams 1 (a voice in a helm).
	Knight = sound(9125861903, 0.45, 0.8, 1.4),
	-- Spirit Pass Bys Fast Overlapping Whooshes 3.
	Sprite = sound(9119467149, 0.45, 1.5, 1.2),
}) :: { [string]: Sound }

-- Voices for creatures without a sculpted shape, by body plan.
CreatureSounds.BodyVoices = table.freeze({
	Wolf = CreatureSounds.Voices.Hound,
	Serpent = CreatureSounds.Voices.Serpent,
	Golem = CreatureSounds.Voices.Golem,
	Guardian = CreatureSounds.Voices.Knight,
	Beetle = CreatureSounds.Voices.Beetle,
	Sprite = CreatureSounds.Voices.Sprite,
}) :: { [string]: Sound }

CreatureSounds.Cues = table.freeze({
	-- Swish Thin 13: bites, claws, swings.
	Swish = sound(9119711581, 0.5, 1, 0.8),
	-- Low Impacts 3: slams, stomps, a dive landing.
	Impact = sound(9116329922, 0.8, 1, 1.6),
	-- Shale Break 12: stone giants' blows.
	RockImpact = sound(9119042093, 0.7, 0.9, 1.6),
	-- Hard Metal Clanking Impacts With Ringing 1: armoured blows.
	Clank = sound(9114776354, 0.45, 1.1, 0.9),
	-- Body Impact 2: heavy footfalls.
	Footstep = sound(9113524237, 0.35, 0.9, 0.7),
	-- Wing Flaps 14: take-off and beats in flight.
	Wings = sound(9120775287, 0.5, 1, 1.4),
	-- Whoosh Fast Swish By 1: a dive.
	Dive = sound(9120710054, 0.7, 0.9, 1.6),
	-- Wolf Snorts 5: staggered.
	Stagger = sound(9120791804, 0.5, 1, 1),
	-- Body Fall Master 2: the body settles.
	BodyFall = sound(9113474578, 0.6, 1, 1.6),
}) :: { [string]: Sound }

function CreatureSounds.voiceFor(shape: string?, body: string): Sound
	return (shape and CreatureSounds.Voices[shape])
		or CreatureSounds.BodyVoices[body]
		or CreatureSounds.Voices.Hound
end

-- Lower pitch for bigger creatures (size 1 = as listed).
function CreatureSounds.pitchFor(cue: Sound, scale: number): number
	return cue.pitch * math.clamp(1.12 - 0.12 * scale, 0.6, 1.2)
end

-- Every id, for preloading and the licence check.
function CreatureSounds.allIds(): { number }
	local seen: { [number]: boolean } = {}
	local out = {}
	for _, group in { CreatureSounds.Voices, CreatureSounds.Cues } do
		for _, s in group do
			if not seen[s.id] then
				seen[s.id] = true
				table.insert(out, s.id)
			end
		end
	end
	table.sort(out)
	return out
end

return table.freeze(CreatureSounds)
