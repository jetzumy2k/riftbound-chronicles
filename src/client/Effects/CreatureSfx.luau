--!strict
--[[
	CreatureSfx — plays the creatures' sounds (Definitions/CreatureSounds,
	PLAN.md D-62). Display only.

	Sounds play from the creature (3D, fading with distance; bigger
	creatures carry further), in one "RC_Creatures" sound group, and fade
	out after the cue's length. Mobile budget: nothing beyond
	HEAR_DISTANCE of the camera, at most MAX_PLAYING at once, and each
	creature at most one sound per kind per cooldown.
]]

local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local CreatureSounds = require(ReplicatedStorage.Shared.Definitions.CreatureSounds)

local CreatureSfx = {}

local HEAR_DISTANCE = 150
local MAX_PLAYING = 10
local FADE_SECONDS = 0.25

local playing = 0
local group: SoundGroup? = nil
-- [part][kind] = earliest time that kind may play again from it.
local cooldowns: { [Instance]: { [string]: number } } = setmetatable({}, { __mode = "k" }) :: any

local function soundGroup(): SoundGroup
	local existing = group
	if existing and existing.Parent then
		return existing
	end
	local made = Instance.new("SoundGroup")
	made.Name = "RC_Creatures"
	made.Volume = 0.7
	made.Parent = SoundService
	group = made
	return made
end

--[[
	Plays `sound` from `part` (a creature's root) for a creature of size
	`scale`. `kind` + `cooldown` rate-limit it per creature; `volumeScale`
	adjusts the cue's own volume.
]]
function CreatureSfx.play(
	sound: CreatureSounds.Sound,
	part: BasePart,
	scale: number,
	kind: string,
	cooldown: number,
	volumeScale: number?
)
	local camera = Workspace.CurrentCamera
	if camera == nil or part.Parent == nil then
		return
	end
	if (camera.CFrame.Position - part.Position).Magnitude > HEAR_DISTANCE or playing >= MAX_PLAYING then
		return
	end
	local now = os.clock()
	local own = cooldowns[part]
	if own == nil then
		own = {}
		cooldowns[part] = own
	end
	if now < (own[kind] or 0) then
		return
	end
	own[kind] = now + cooldown

	local s = Instance.new("Sound")
	s.SoundId = `rbxassetid://{sound.id}`
	s.Volume = sound.volume * (volumeScale or 1)
	s.PlaybackSpeed = CreatureSounds.pitchFor(sound, scale)
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 8 + scale * 4
	s.RollOffMaxDistance = 90 + scale * 25
	s.SoundGroup = soundGroup()
	s.Parent = part
	playing += 1
	s:Play()
	local length = sound.seconds / math.max(s.PlaybackSpeed, 0.1)
	task.delay(math.max(length - FADE_SECONDS, 0.05), function()
		if s.Parent then
			TweenService:Create(s, TweenInfo.new(FADE_SECONDS), { Volume = 0 }):Play()
		end
	end)
	task.delay(length + 0.05, function()
		playing -= 1
	end)
	Debris:AddItem(s, length + 0.1)
end

-- Loads every creature sound in the background so the first roar isn't late.
function CreatureSfx.preload()
	task.spawn(function()
		local sounds = {}
		for _, id in CreatureSounds.allIds() do
			local s = Instance.new("Sound")
			s.SoundId = `rbxassetid://{id}`
			table.insert(sounds, s)
		end
		pcall(function()
			ContentProvider:PreloadAsync(sounds)
		end)
		for _, s in sounds do
			s:Destroy()
		end
	end)
end

return CreatureSfx
