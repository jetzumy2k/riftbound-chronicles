--!strict
--[[
	MallService (Layer 5) — the Item Mall (creator request 2026-10-25,
	PLAN.md D-93; catalog in Definitions/MallDefinitions).

	  BuyMallItem(entryId)  spends Mall Points on a catalog entry. The price
	                        and what it gives come from the server's catalog,
	                        never from the client. Checked and paid in one
	                        synchronous block (no yields): enough MP, room in
	                        the bag (a set needs a slot per piece), stack
	                        limits; then MP are taken and the goods given.
	  ProcessReceipt        Robux -> Mall Points (Developer Products, PACKS).
	                        Each PurchaseId is a claim ("R:<id>", kept
	                        forever), so a retried receipt never pays twice;
	                        the profile is saved before Roblox is told the
	                        purchase was granted. NotProcessedYet while the
	                        player's profile isn't loaded (Roblox retries).

	Every purchase is audited (MallBuy, MallPoints).
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local MallDefinitions = require(Shared.Definitions.MallDefinitions)
local ItemDefinitions = require(Shared.Definitions.ItemDefinitions)
local JobDefinitions = require(Shared.Definitions.JobDefinitions)
local ItemRules = require(Shared.Logic.ItemRules)
local Log = require(Shared.Util.Log)

local AuditLogService = require(script.Parent.AuditLogService)
local NetService = require(script.Parent.NetService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local InventoryService = require(script.Parent.InventoryService)

local log = Log.new("MallService")

local MallService = {}

local function notify(player: Player, kind: string, key: string, params: { [string]: string }?)
	NetService:FireClient("Notify", player, { kind = kind, textKey = key, params = params })
end

--[[
	The pieces of a complete set for `job` / `race` at `level`: every kind
	the class has, the weapon in the first family the realm may use.
]]
local function setPieces(job: string, race: string?, level: number): { ItemDefinitions.ItemDef }
	local out = {}
	local family: string? = nil
	for _, candidate in ItemDefinitions.familiesOf(job) do
		if JobDefinitions.allowsWeapon(job, race, candidate) then
			family = candidate
			break
		end
	end
	for _, kind in ItemDefinitions.kindsOf(job) do
		local def = ItemDefinitions.defFor(job, kind, if kind == "Weapon" then family else nil, level)
		if def then
			table.insert(out, def)
		end
	end
	return out
end
MallService.setPieces = setPieces

--[[
	Gives `player` a complete `rarity` set for their class at their level
	with fixed attributes. Returns false (giving nothing) without room in
	the bag. Used by the Mall and by event rewards (D-93 stage 2).
]]
function MallService:GrantSet(player: Player, rarity: string, source: string): boolean
	local data = PlayerDataService:GetData(player)
	if data == nil or data.Job == nil then
		return false
	end
	local level = math.clamp(data.Level, 0, 30)
	local pieces = setPieces(data.Job, data.Race, level)
	if InventoryService:FreeSlots(player) < #pieces then
		return false
	end
	for _, def in pieces do
		local itemLevel = math.clamp(level, def.minItemLevel, def.maxItemLevel)
		InventoryService:GrantItem(
			player,
			def.id,
			rarity,
			itemLevel,
			source,
			ItemRules.fixedRoll(def, rarity, itemLevel)
		)
	end
	return true
end

-- How many pieces a set for this player has (bag room needed).
function MallService:SetSize(player: Player): number
	local data = PlayerDataService:GetData(player)
	if data == nil or data.Job == nil then
		return 0
	end
	return #setPieces(data.Job, data.Race, math.clamp(data.Level, 0, 30))
end

local function onBuy(player: Player, entryId: string): { [string]: any }
	local entry = MallDefinitions.get(entryId)
	local data = PlayerDataService:GetData(player)
	if entry == nil or data == nil or data.Job == nil then
		return { ok = false, reason = "unknown" }
	end
	local wallet = data.Wallet
	local have = wallet.MallPoints or 0
	if have < entry.price then
		return { ok = false, reason = "points" }
	end
	local grant = entry.grant :: any
	local source = `Mall:{entry.id}`
	if grant.kind == "Stackable" then
		local def = ItemDefinitions.stackable(grant.id)
		if def == nil then
			return { ok = false, reason = "unknown" }
		end
		if (data.Stackables[grant.id] or 0) + grant.count > def.maxStack then
			return { ok = false, reason = "full" }
		end
		wallet.MallPoints = have - entry.price
		local added = InventoryService:GrantStackable(player, grant.id, grant.count, source)
		if added < grant.count then
			-- Cannot happen after the check above; refund what didn't fit.
			wallet.MallPoints += math.floor(entry.price * (grant.count - added) / grant.count)
		end
	else
		if InventoryService:FreeSlots(player) < MallService:SetSize(player) then
			return { ok = false, reason = "bag" }
		end
		wallet.MallPoints = have - entry.price
		MallService:GrantSet(player, grant.rarity, source)
	end
	AuditLogService:Audit({
		actorUserId = player.UserId,
		action = "MallBuy",
		target = entry.id,
		details = { price = entry.price, left = wallet.MallPoints },
	})
	notify(player, "Info", "mall.bought", { name = entry.name })
	PlayerDataService:PushSnapshot(player)
	return { ok = true, points = wallet.MallPoints }
end

local function processReceipt(info: any): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(info.PlayerId)
	local pack = MallDefinitions.packForProduct(info.ProductId)
	if pack == nil then
		log:Error(
			"receipt for unknown product %s (purchase %s)",
			tostring(info.ProductId),
			tostring(info.PurchaseId)
		)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if player == nil or PlayerDataService:GetData(player) == nil then
		-- Roblox retries when the player is back with a loaded profile.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local points = MallDefinitions.pointsOf(pack)
	local status = (PlayerDataService :: any):ClaimReward(player, `R:{info.PurchaseId}`, function(data: any)
		data.Wallet.MallPoints = (data.Wallet.MallPoints or 0) + points
	end)
	if status == "granted" then
		local data = PlayerDataService:GetData(player) :: any
		AuditLogService:Audit({
			actorUserId = player.UserId,
			action = "MallPoints",
			target = pack.id,
			details = {
				points = points,
				robux = info.CurrencySpent,
				purchase = info.PurchaseId,
				total = data.Wallet.MallPoints,
			},
		})
		PlayerDataService:SaveNow(player)
		notify(player, "Info", "mall.points", { points = tostring(points) })
		PlayerDataService:PushSnapshot(player)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	elseif status == "already" then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

function MallService:Init()
	NetService:Handle("BuyMallItem", onBuy)
end

function MallService:Start()
	MarketplaceService.ProcessReceipt = processReceipt
end

return MallService
