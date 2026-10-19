--!strict
--[[
	EnhancementService (Layer 4)
	Enhances weapons and gear from +0 to +10 (Phase 8, PLAN.md D-08 / D-66;
	CLAUDE.md §10).

	`EnhanceItem(guid, perfect)`: the item must be in the caller's own
	inventory and below +10, and they must hold the stone. Then, in one
	synchronous block with no yield (DATA_MODEL.md §4.1), exactly one stone
	is consumed, the server rolls and the result is applied
	(Logic/EnhanceRules). Luau runs one handler to the end before the next,
	so twenty requests in one frame are twenty separate attempts, each
	needing its own stone; a per-player busy flag guards against any future
	yield sneaking in. The profile is changed in memory and saved by
	ProfileStore, so a disconnect can't leave half an attempt.

	Rates (config Enhancement.RatesPct, D-08) are published on
	ReplicatedStorage attribute "RC_EnhanceRates" so the screen shows them.
	A failure never lowers or destroys the item. No stone is ever sold
	(D-15): stones come from play (salvage, PvP mobs, quests).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local EnhanceRules = require(Shared.Logic.EnhanceRules)
local ItemDefinitions = require(Shared.Definitions.ItemDefinitions)
local Log = require(Shared.Util.Log)

local AuditLogService = require(script.Parent.AuditLogService)
local ConfigurationService = require(script.Parent.ConfigurationService)
local NetService = require(script.Parent.NetService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local RaceService = require(script.Parent.RaceService)
local CombatService = require(script.Parent.CombatService)
local InventoryService = require(script.Parent.InventoryService)

local RATES_ATTRIBUTE = "RC_EnhanceRates"
local NOTICE_SECONDS = 1

local log = Log.new("EnhancementService")
local random = Random.new()

local EnhancementService = {}

local busy: { [Player]: boolean } = {}
local lastNotice: { [Player]: number } = {}

local function rates(): { number }
	return ConfigurationService:Get("Enhancement.RatesPct")
end

local function publishRates()
	local list = {}
	for level = 0, EnhanceRules.MAX - 1 do
		table.insert(list, tostring(EnhanceRules.rateFor(level, rates())))
	end
	ReplicatedStorage:SetAttribute(RATES_ATTRIBUTE, table.concat(list, ","))
end

local function warn(player: Player, key: string)
	local t = os.clock()
	if t - (lastNotice[player] or -math.huge) < NOTICE_SECONDS then
		return
	end
	lastNotice[player] = t
	NetService:FireClient("Notify", player, { kind = "Warning", textKey = `enhance.{key}` })
end

local function onEnhance(player: Player, guid: string, perfect: boolean)
	if busy[player] then
		return
	end
	local data = PlayerDataService:GetData(player)
	if data == nil then
		return
	end
	local item = data.Inventory[guid]
	if item == nil or ItemDefinitions.get(item.DefId) == nil then
		AuditLogService:Security(player, "ItemNotOwned", guid)
		return
	end
	busy[player] = true
	-- Check, consume one stone, roll, apply: one synchronous step.
	local result, reason = EnhanceRules.attempt(item, data.Stackables, perfect, random:NextNumber(), rates())
	busy[player] = nil
	if result == nil then
		warn(player, reason or "noStone")
		return
	end
	log:Info(
		"user=%d %s %s +%d -> +%d (%s, %d%%)",
		player.UserId,
		guid,
		item.DefId,
		result.from,
		result.to,
		result.stone,
		result.rate
	)
	InventoryService:Push(player, { guid })
	NetService:FireClient("EnhanceResult", player, {
		Guid = guid,
		Success = result.success,
		Level = result.to,
		Perfect = perfect,
	})
	if result.success and InventoryService:EquippedSlot(player, guid) then
		CombatService:RefreshStats(player)
		RaceService:Redress(player)
	end
end

function EnhancementService:Init()
	NetService:Handle("EnhanceItem", onEnhance)
end

function EnhancementService:Start()
	publishRates()
	Players.PlayerRemoving:Connect(function(player)
		busy[player] = nil
		lastNotice[player] = nil
	end)
	-- Live config changes reach the screen.
	task.spawn(function()
		local version = ConfigurationService:GetVersion()
		while true do
			task.wait(30)
			if ConfigurationService:GetVersion() ~= version then
				version = ConfigurationService:GetVersion()
				publishRates()
			end
		end
	end)
end

return EnhancementService
