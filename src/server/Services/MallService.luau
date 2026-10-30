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
local ItemRules = require(Shared.Logic.ItemRules)
local MallGear = require(Shared.Logic.MallGear)
local Log = require(Shared.Util.Log)

local AuditLogService = require(script.Parent.AuditLogService)
local ConfigurationService = require(script.Parent.ConfigurationService)
local NetService = require(script.Parent.NetService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local InventoryService = require(script.Parent.InventoryService)

local log = Log.new("MallService")

local MallService = {}

local function notify(player: Player, kind: string, key: string, params: { [string]: string }?)
	NetService:FireClient("Notify", player, { kind = kind, textKey = key, params = params })
end

-- D-124: the armor package (MallGear.ARMOR) for `job` at `level`.
local function setPieces(job: string, race: string?, level: number): { ItemDefinitions.ItemDef }
	local out = {}
	local pieces = MallGear.pieces(job, race, "Set", level)
	for _, p in pieces or {} :: { MallGear.Piece } do
		table.insert(out, p.def)
	end
	return out
end
MallService.setPieces = setPieces

-- Gives `pieces` (fixed attributes). False, giving nothing, without room.
local function grantPieces(
	player: Player,
	pieces: { MallGear.Piece },
	rarity: string,
	source: string
): boolean
	if InventoryService:FreeSlots(player) < #pieces then
		return false
	end
	for _, p in pieces do
		InventoryService:GrantItem(
			player,
			p.def.id,
			rarity,
			p.itemLevel,
			source,
			ItemRules.fixedRoll(p.def, rarity, p.itemLevel)
		)
	end
	return true
end

--[[
	Gives `player` the `rarity` armor package (D-124: helm, shoulders,
	armor, gloves, pants, boots) for their class at their level with fixed
	attributes. Returns false (giving nothing) without room in the bag.
	Used by event rewards (D-93 stage 2) and staff pay (D-112).
]]
function MallService:GrantSet(player: Player, rarity: string, source: string): boolean
	local data = PlayerDataService:GetData(player)
	if data == nil or data.Job == nil then
		return false
	end
	local pieces = MallGear.pieces(data.Job, data.Race, "Set", math.clamp(data.Level, 0, 30))
	return pieces ~= nil and grantPieces(player, pieces, rarity, source)
end

-- How many pieces a set for this player has (bag room needed).
function MallService:SetSize(player: Player): number
	local data = PlayerDataService:GetData(player)
	if data == nil or data.Job == nil then
		return 0
	end
	return #setPieces(data.Job, data.Race, math.clamp(data.Level, 0, 30))
end

-- D-109: the admin's price for an entry, else the catalog's.
function MallService:PriceOf(entry: MallDefinitions.Entry): number
	local price = ConfigurationService:Get("Mall").Prices[entry.id]
	return if type(price) == "number" and price >= 1 then price else entry.price
end

local function onBuy(player: Player, entryId: string, choice: MallGear.Choice?): { [string]: any }
	local catalog = MallDefinitions.get(entryId)
	local data = PlayerDataService:GetData(player)
	if catalog == nil or data == nil or data.Job == nil then
		return { ok = false, reason = "unknown" }
	end
	-- The price is read once, so a change mid-purchase can't split it.
	local entry = table.clone(catalog) :: any
	entry.price = MallService:PriceOf(catalog)
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
	elseif MallGear.KINDS[grant.kind] then
		-- D-124: armor package, weapon, off-hand or accessory, at the level
		-- tier the buyer picked (equippable from that level).
		local bracket, why = MallGear.bracketOf(choice, data.Level)
		if bracket == nil then
			return { ok = false, reason = why }
		end
		local pieces, reason = MallGear.pieces(data.Job, data.Race, grant.kind, bracket, choice)
		if pieces == nil or #pieces == 0 then
			return { ok = false, reason = reason or "unknown" }
		end
		if InventoryService:FreeSlots(player) < #pieces then
			return { ok = false, reason = "bag" }
		end
		wallet.MallPoints = have - entry.price
		grantPieces(player, pieces, grant.rarity, source)
	else
		return { ok = false, reason = "unknown" }
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
		data.Wallet.PurchasedMallPoints = (data.Wallet.PurchasedMallPoints or 0) + points
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
