--!strict
--[[
	StatsService (Layer 2)
	Server-authoritative character stats. Phase 2: base stats from level
	(CLAUDE.md §5 via shared StatFormulas). Phase 7/8 layer gear and
	enhancement bonuses on top; Phase 6 consumes these for combat.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StatFormulas = require(ReplicatedStorage.Shared.Logic.StatFormulas)

local PlayerDataService = require(script.Parent.PlayerDataService)

local StatsService = {}

--[[
	Returns the player's base stats, or nil if their profile is not loaded.
]]
function StatsService:GetBaseStats(player: Player): StatFormulas.BaseStats?
	local data = PlayerDataService:GetData(player)
	if data == nil then
		return nil
	end
	return StatFormulas.forLevel(data.Level)
end

return StatsService
