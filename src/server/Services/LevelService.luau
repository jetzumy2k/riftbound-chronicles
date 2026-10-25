--!strict
--[[
	LevelService (Layer 2)
	Server-authoritative XP and levels 0..30 (CLAUDE.md §4, PLAN.md D-18).

	There is no remote that grants XP. `GrantXP` is called only by server
	systems (mobs, dungeons, quests — later phases; admin tools — Phase 17).

	Publishes:
	  - Player attribute "Level" (public, for nameplates)
	  - `ProgressionUpdate` to the owning client
	  - `LevelService.LevelChanged(player, newLevel, oldLevel)`
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Constants = require(Shared.Constants)
local XPTable = require(Shared.Logic.XPTable)
local Log = require(Shared.Util.Log)
local Signal = require(Shared.Util.Signal)

local ProfileView = require(script.Parent.Parent.Persistence.ProfileView)

local NetService = require(script.Parent.NetService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local EventService = require(script.Parent.EventService)

local SOURCE_PATTERN = "^[%w_:%-]+$"
local MAX_SOURCE_LENGTH = 64

local log = Log.new("LevelService")

local LevelService = {
	-- (player, newLevel, oldLevel). Handlers must not yield.
	LevelChanged = Signal.new(),
}

local function publishLevel(player: Player, level: number)
	player:SetAttribute("Level", level)
end

function LevelService:Init()
	PlayerDataService.ProfileLoaded:Connect(function(player, data)
		publishLevel(player, data.Level)
	end)
end

--[[
	Grants XP to a loaded player. Server-internal only.
	`amount`: positive integer <= Constants.Experience.MaxGrant.
	`source`: short tag for logs, e.g. "Mob:RiftWolf", "Quest:FirstSpark".
	Returns (granted, levelsGained).
]]
function LevelService:GrantXP(player: Player, amount: number, source: string): (boolean, number)
	if
		type(amount) ~= "number"
		or amount ~= amount
		or amount % 1 ~= 0
		or amount <= 0
		or amount > Constants.Experience.MaxGrant
	then
		log:Error("GrantXP rejected invalid amount %s from %s", tostring(amount), tostring(source))
		return false, 0
	end
	if
		type(source) ~= "string"
		or #source > MAX_SOURCE_LENGTH
		or string.match(source, SOURCE_PATTERN) == nil
	then
		log:Error("GrantXP rejected invalid source %s", tostring(source))
		return false, 0
	end

	local data = PlayerDataService:GetData(player)
	if data == nil then
		return false, 0
	end
	-- Live events (D-89): scaled as it is earned, capped per category.
	amount = math.min(EventService:ScaleXp(player, amount, source), Constants.Experience.MaxGrant)

	-- Synchronous read-modify-write.
	local oldLevel = data.Level
	local result = XPTable.apply(data.Level, data.Experience, amount)
	data.Level = result.level
	data.Experience = result.experience
	data.TotalExperience += result.applied

	publishLevel(player, data.Level)
	NetService:FireClient("ProgressionUpdate", player, ProfileView.progression(data, result.levelsGained))

	log:Debug(
		"user=%d +%d XP (%s) applied=%d discarded=%d L%d->L%d",
		player.UserId,
		amount,
		source,
		result.applied,
		result.discarded,
		oldLevel,
		data.Level
	)
	if result.levelsGained > 0 then
		log:Info("user=%d reached level %d", player.UserId, data.Level)
		LevelService.LevelChanged:Fire(player, data.Level, oldLevel)
	end
	return true, result.levelsGained
end

--[[
	Sets a loaded player's level (admin action, Phase 17; audited by the
	caller). EXP into the level resets to 0. Returns false for a bad level.
]]
function LevelService:SetLevel(player: Player, level: number): boolean
	if type(level) ~= "number" or level % 1 ~= 0 or level < 0 or level > Constants.Level.Max then
		return false
	end
	local data = PlayerDataService:GetData(player)
	if data == nil then
		return false
	end
	local oldLevel = data.Level
	data.Level = level
	data.Experience = 0
	publishLevel(player, level)
	NetService:FireClient(
		"ProgressionUpdate",
		player,
		ProfileView.progression(data, math.max(level - oldLevel, 0))
	)
	if level ~= oldLevel then
		LevelService.LevelChanged:Fire(player, level, oldLevel)
	end
	return true
end

function LevelService:GetLevel(player: Player): number?
	local data = PlayerDataService:GetData(player)
	return if data then data.Level else nil
end

return LevelService
