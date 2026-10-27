--!strict
--[[
	DurabilityService (Layer 6) — equipped gear wears down (creator request
	2026-10-27, PLAN.md D-118; rules in Logic/DurabilityRules, numbers in
	config Durability). Repairs are the Blacksmith's (ShopService).

	  - Each creature whose EXP a player earns wears their equipped weapon
	    by WeaponWearPerKill and every other worn piece by ArmorWearPerKill.
	  - A defeat wears every worn piece by DefeatWearPct % (a defeat by a
	    player only when PvPDefeatWear is on).
	  - A piece reaching 0 is broken: stats are refreshed at once (its
	    stats stop counting) and the owner is told; reaching 20 % warns.
	The bag view is updated a few seconds later (batched), so a fight does
	not send an item update per creature.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local DurabilityRules = require(Shared.Logic.DurabilityRules)
local ItemDefinitions = require(Shared.Definitions.ItemDefinitions)

local ConfigurationService = require(script.Parent.ConfigurationService)
local NetService = require(script.Parent.NetService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local InventoryService = require(script.Parent.InventoryService)
local CombatService = require(script.Parent.CombatService)
local MobService = require(script.Parent.MobService)

local PUSH_DELAY = 3

local DurabilityService = {}

-- Worn items changed since the last bag update, per player.
local dirty: { [Player]: { [string]: boolean } } = {}

local function config(): DurabilityRules.Config
	return ConfigurationService:Get("Durability")
end

local function notify(player: Player, kind: string, textKey: string, name: string)
	NetService:FireClient("Notify", player, { kind = kind, textKey = textKey, params = { name = name } })
end

local function pushSoon(player: Player, guids: { string })
	local pending = dirty[player]
	if pending == nil then
		pending = {}
		dirty[player] = pending
		task.delay(PUSH_DELAY, function()
			local list = {}
			for guid in (dirty[player] or {}) :: { [string]: boolean } do
				table.insert(list, guid)
			end
			dirty[player] = nil
			if player.Parent == Players and #list > 0 then
				InventoryService:Push(player, list)
			end
		end)
	end
	for _, guid in guids do
		(pending :: any)[guid] = true
	end
end

-- Wears every worn piece of `player`; `amountFor(slot, def)` gives the wear.
local function wearWorn(player: Player, amountFor: (string, ItemDefinitions.ItemDef) -> number)
	local data = PlayerDataService:GetData(player)
	if data == nil then
		return
	end
	local changed, broke = {}, false
	for slot, guid in data.Equipment do
		local item = data.Inventory[guid]
		local def = item and ItemDefinitions.get(item.DefId)
		if item and def then
			local amount = amountFor(slot, def)
			if amount > 0 then
				local after, crossed = DurabilityRules.wear(item, amount)
				if after ~= DurabilityRules.of(item) then
					item.Durability = after
					table.insert(changed, guid)
				end
				if crossed == "broken" then
					broke = true
					notify(player, "Warning", "durability.broken", def.name)
				elseif crossed == "low" then
					notify(player, "Info", "durability.low", def.name)
				end
			end
		end
	end
	if broke then
		CombatService:RefreshStats(player)
	end
	if #changed > 0 then
		pushSoon(player, changed)
	end
end

function DurabilityService:Init()
	MobService.MobDefeated:Connect(function(_mob, _contributors, recipients: { Player }?)
		local c = config()
		if not c.Enabled or recipients == nil then
			return
		end
		for _, player in recipients do
			wearWorn(player, function(slot, def)
				return DurabilityRules.killWear(c, slot, def.slot == "Weapon")
			end)
		end
	end)
	CombatService.Defeated:Connect(function(entity: any, attacker: any)
		local player = entity.player
		if player == nil then
			return
		end
		local amount = DurabilityRules.defeatWear(config(), attacker ~= nil and attacker.player ~= nil)
		if amount > 0 then
			wearWorn(player, function()
				return amount
			end)
		end
	end)
end

function DurabilityService:Start()
	Players.PlayerRemoving:Connect(function(player)
		dirty[player] = nil
	end)
end

return DurabilityService
