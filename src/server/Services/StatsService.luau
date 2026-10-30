--!strict
--[[
	StatsService (Layer 2)
	Server-authoritative character stats. Phase 2: base stats from level
	(CLAUDE.md §5 via shared StatFormulas). Phase 7 (D-64) layers gear
	(and Phase 8 enhancement, via ItemRules) on top, then D-90 attribute
	points (Logic/AttributeRules); combat uses GetStats.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StatFormulas = require(ReplicatedStorage.Shared.Logic.StatFormulas)
local ItemRules = require(ReplicatedStorage.Shared.Logic.ItemRules)
local AttributeRules = require(ReplicatedStorage.Shared.Logic.AttributeRules)
local BuffRules = require(ReplicatedStorage.Shared.Logic.BuffRules)
local PassiveRules = require(ReplicatedStorage.Shared.Logic.PassiveRules)

local PlayerDataService = require(script.Parent.PlayerDataService)

local StatsService = {}

-- D-126: admin test overrides (Max HP / Attack / Defense) per player, for
-- trying out events. Session only: never saved, gone when they leave.
StatsService.OVERRIDABLE = table.freeze({ "MaxHP", "Attack", "Defense" })
local overrides: { [Player]: any } = {}

-- Sets (value > 0) or clears (nil / 0) an override for `stat`.
function StatsService:SetOverride(player: Player, stat: string, value: number?)
	if table.find(StatsService.OVERRIDABLE, stat) == nil then
		return
	end
	local mine: any = overrides[player] or {}
	mine[stat] = if value and value > 0 then value else nil
	overrides[player] = if next(mine) then mine else nil
end

function StatsService:GetOverrides(player: Player): { [string]: number }
	return table.clone(overrides[player] or {})
end

game:GetService("Players").PlayerRemoving:Connect(function(player)
	overrides[player] = nil
end)

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
	local stats = ItemRules.withGear(StatFormulas.forLevel(data.Level), gear)
	-- D-90: attribute points on top, as a new table (the gear stats are
	-- frozen; writing into them stopped combat setup, creator report
	-- 2026-10-25 "no damage").
	local withAttributes =
		AttributeRules.applyTo(stats, AttributeRules.combine(data.Attributes, data.BonusAttributes), data.Job)
	-- D-104: learned class passives (always on, no bar slot).
	local withPassives = PassiveRules.applyTo(withAttributes, data.OwnedSkills, data.Job)
	-- D-93: running Mall stat buffs (Might, Iron, Vigor, Clarity).
	local final = BuffRules.applyTo(withPassives, data.Buffs, os.time())
	-- D-126: an admin's test override replaces the stat outright.
	local mine = overrides[player]
	if mine then
		final = table.clone(final)
		for stat, value in mine do
			(final :: any)[stat] = value
		end
	end
	return final
end

return StatsService
