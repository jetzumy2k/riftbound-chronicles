--!strict
--[[
	StatsService (Layer 2)
	Server-authoritative character stats. Phase 2: base stats from level
	(CLAUDE.md §5 via shared StatFormulas). Phase 7 (D-64) layers gear
	(and Phase 8 enhancement, via ItemRules) on top; combat uses GetStats.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StatFormulas = require(ReplicatedStorage.Shared.Logic.StatFormulas)
local ItemRules = require(ReplicatedStorage.Shared.Logic.ItemRules)

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

--[[
	Base stats plus everything the equipped gear adds (Phase 7, D-64;
	ItemRules.withGear), or nil if the profile is not loaded. Combat uses
	this.
]]
function StatsService:GetStats(player: Player): ItemRules.Stats?
	local data = PlayerDataService:GetData(player)
	if data == nil then
		return nil
	end
	local gear = ItemRules.gearTotals(data.Equipment, data.Inventory)
	return ItemRules.withGear(StatFormulas.forLevel(data.Level), gear)
end

return StatsService
