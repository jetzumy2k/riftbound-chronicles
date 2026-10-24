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
	HeadStyle: string,
	Level: number,
	Experience: number,
	XPToNext: number,
	-- Phase 5 skill tree (D-45): learned skill id -> rank, and the 3 + 1 bar.
	OwnedSkills: { [string]: number },
	EquippedSkills: { Regular: { string }, Special: string? },
	-- Phase 7 (D-64): items (guid -> item), slot -> guid, stackables, wallet,
	-- and when each consumable is usable again (os.clock()).
	Inventory: { [string]: Item },
	Equipment: { [string]: string },
	Stackables: { [string]: number },
	Wallet: { Gold: number, PvPMarks: number },
	ReadyAt: { [string]: number },
	-- Phase 11 (D-73): quests, story flags, titles, cosmetics.
	Quests: QuestsView,
	-- D-74: HUD pieces the player moved (id -> centre fraction).
	HudLayout: { [string]: { X: number, Y: number } },
}

export type QuestProgress = {
	Status: string,
	Objectives: { [string]: number },
	Found: { string },
}

export type QuestsView = {
	Quests: { [string]: QuestProgress },
	Flags: { string },
	Titles: { string },
	EquippedTitle: string?,
	Cosmetics: { string },
}

local function emptyQuests(): QuestsView
	return { Quests = {}, Flags = {}, Titles = {}, Cosmetics = {} }
end

export type Item = {
	Guid: string,
	DefId: string,
	Rarity: string,
	ItemLevel: number,
	Attributes: { { Stat: string, Value: number } },
	Enhancement: number,
	Locked: boolean,
	CreatedAt: number,
}

local PlayerDataController = {
	-- (state, reason: "snapshot" | "progression" | "inventory" | "quests", levelsGained: number)
	Changed = Signal.new(),
}

local state: State = {
	loaded = false,
	FacePreset = 1,
	HeadStyle = "Man",
	Level = 0,
	Experience = 0,
	XPToNext = 0,
	OwnedSkills = {},
	EquippedSkills = { Regular = {} },
	Inventory = {},
	Equipment = {},
	Stackables = {},
	Wallet = { Gold = 0, PvPMarks = 0 },
	ReadyAt = {},
	Quests = emptyQuests(),
	HudLayout = {},
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
			HeadStyle = snapshot.HeadStyle or "Man",
			Level = snapshot.Level,
			Experience = snapshot.Experience,
			XPToNext = snapshot.XPToNext,
			OwnedSkills = snapshot.OwnedSkills or {},
			EquippedSkills = snapshot.EquippedSkills or { Regular = {} },
			Inventory = snapshot.Inventory or {},
			Equipment = snapshot.Equipment or {},
			Stackables = snapshot.Stackables or {},
			Wallet = snapshot.Wallet or { Gold = 0, PvPMarks = 0 },
			ReadyAt = state.ReadyAt,
			Quests = snapshot.Quests or emptyQuests(),
			HudLayout = snapshot.HudLayout or {},
		}
		log:Debug("snapshot: L%d %d/%d XP", state.Level, state.Experience, state.XPToNext)
		PlayerDataController.Changed:Fire(state, "snapshot", 0)
	end)

	NetClient.on("QuestUpdate", function(update)
		if type(update) ~= "table" then
			return
		end
		state.Quests = update
		PlayerDataController.Changed:Fire(state, "quests", 0)
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

	NetClient.on("InventoryUpdate", function(update)
		if type(update) ~= "table" then
			return
		end
		for guid, item in update.Changed do
			state.Inventory[guid] = item
		end
		for _, guid in update.Removed do
			state.Inventory[guid] = nil
		end
		state.Equipment = update.Equipment
		state.Stackables = update.Stackables
		state.Wallet = update.Wallet
		local now = os.clock()
		local readyIn: { [string]: number } = update.ReadyIn or {}
		state.ReadyAt = {}
		for id, seconds in readyIn do
			state.ReadyAt[id] = now + seconds
		end
		PlayerDataController.Changed:Fire(state, "inventory", 0)
	end)
end

function PlayerDataController:Get(): State
	return state
end

return PlayerDataController
