--!strict
--[[
	PlayerDataController
	Holds the local player's replicated profile view (docs/DATA_MODEL.md §6).
	Read-only mirror of server state; the client never writes progression.

	    PlayerDataController.Changed:Connect(function(state, reason) ... end)
	    local state = PlayerDataController:Get()
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Log = require(Shared.Util.Log)
local Signal = require(Shared.Util.Signal)
local NetClient = require(Shared.Net.Client)

local log = Log.new("PlayerData")

export type State = {
	loaded: boolean,
	Race: string?,
	Job: string?,
	FacePreset: number,
	Level: number,
	Experience: number,
	XPToNext: number,
}

local PlayerDataController = {
	-- (state, reason: "snapshot" | "progression", levelsGained: number)
	Changed = Signal.new(),
}

local state: State = {
	loaded = false,
	FacePreset = 1,
	Level = 0,
	Experience = 0,
	XPToNext = 0,
}

function PlayerDataController:Init()
	NetClient.on("ProfileSnapshot", function(snapshot)
		if type(snapshot) ~= "table" then
			return
		end
		state = {
			loaded = true,
			Race = snapshot.Race,
			Job = snapshot.Job,
			FacePreset = snapshot.FacePreset,
			Level = snapshot.Level,
			Experience = snapshot.Experience,
			XPToNext = snapshot.XPToNext,
		}
		log:Debug("snapshot: L%d %d/%d XP", state.Level, state.Experience, state.XPToNext)
		PlayerDataController.Changed:Fire(state, "snapshot", 0)
	end)

	NetClient.on("ProgressionUpdate", function(update)
		if type(update) ~= "table" then
			return
		end
		state.Level = update.Level
		state.Experience = update.Experience
		state.XPToNext = update.XPToNext
		PlayerDataController.Changed:Fire(state, "progression", update.LevelsGained)
	end)
end

function PlayerDataController:Get(): State
	return state
end

return PlayerDataController
