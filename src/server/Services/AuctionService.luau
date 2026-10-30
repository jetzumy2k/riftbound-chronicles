--!strict
--[[
	AuctionService (Layer 6) — the cross-server Auction market (creator
	request 2026-10-27, PLAN.md D-122; rules in Logic/AuctionRules, what may
	be listed in Logic/TradeRules, numbers in config Auction). The 🏛️
	Auctioneer stands in each capital (built by ShopService).

	Stores
	  RC_Auction_v1      "L_<id>"  the listing: { listing, pending, mailed }
	                     (source of truth; changed only with UpdateAsync)
	  RC_AuctionEnds_v1  ordered:  listing id -> end time (settlement scan)
	  RC_AuctionBoard    MemoryStore sorted map: id -> summary (browsing;
	                     rebuilt from each change, never trusted for Gold)
	  RC_Mail_v1         "U_<userId>"  deliveries waiting for the player

	Nothing is ever lost or doubled:
	  - Escrow in the player's own profile first. Listing an item moves it
	    (and the fee) into data.Escrow in one synchronous step; a bid moves
	    the Gold there with a fresh BidId. Only then is the shared store
	    written. If that fails the escrow is returned at once; if the server
	    dies in between, the next load checks the listing (does it exist /
	    does it hold this BidId?) and either drops the escrow (the listing
	    has it) or returns it.
	  - Everything a listing owes (the item to the winner, Gold to the
	    seller, refunds to outbid bidders, the item back with no bids) is a
	    delivery with its own id, recorded in the listing first, then copied
	    to the recipient's mailbox (deduplicated by id), then marked mailed.
	  - A mailbox delivery is applied through a reward claim (M:<id>) on the
	    profile, saved, and only then removed from the mailbox, so a crash
	    at any point re-applies nothing twice and loses nothing.
	  - Deliveries go to the character that listed or bid (its slot); other
	    characters of the account leave them waiting.
	Settlement: every server scans the ended listings each minute; the
	first UpdateAsync to see a listing open and over settles it.
]]

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local AuctionRules = require(Shared.Logic.AuctionRules)
local TradeRules = require(Shared.Logic.TradeRules)
local ItemDefinitions = require(Shared.Definitions.ItemDefinitions)
local Log = require(Shared.Util.Log)

local ProfileView = require(script.Parent.Parent.Persistence.ProfileView)

local ConfigurationService = require(script.Parent.ConfigurationService)
local AuditLogService = require(script.Parent.AuditLogService)
local NetService = require(script.Parent.NetService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local InventoryService = require(script.Parent.InventoryService)
local ShopService = require(script.Parent.ShopService)

local log = Log.new("AuctionService")

local NPC = "Auctioneer"
local SCAN_SECONDS = 60
local MAIL_SECONDS = 60
local BOARD_SIZE = 200

type Listing = AuctionRules.Listing
type Delivery = {
	Id: string,
	To: number,
	Slot: number?,
	Kind: string, -- "Item" | "Stack" | "Gold"
	Item: any?,
	StackId: string?,
	Count: number?,
	Gold: number?,
	Note: string,
}
type Record = {
	listing: Listing,
	pending: { Delivery },
	mailed: { [string]: boolean },
	bidIds: { [string]: boolean },
}

local AuctionService = {}

local listingsStore: DataStore? = nil
local endsStore: OrderedDataStore? = nil
local mailStore: DataStore? = nil
local board: MemoryStoreSortedMap? = nil

local function config(): AuctionRules.Config
	return ConfigurationService:Get("Auction")
end

local function notify(player: Player, kind: string, textKey: string, params: { [string]: string }?)
	NetService:FireClient("Notify", player, { kind = kind, textKey = textKey, params = params })
end

local function guidNew(): string
	return HttpService:GenerateGUID(false)
end

local function try(f: () -> ...any): (boolean, any)
	local ok, result = pcall(f)
	if not ok then
		log:Warn("store call failed: %s", tostring(result))
		return false, nil
	end
	return true, result
end

--------------------------------------------------------------------------------
-- The board (browsing)
--------------------------------------------------------------------------------

local function summary(l: Listing): { [string]: any }
	return {
		Id = l.Id,
		Seller = l.Seller,
		SellerName = l.SellerName,
		Kind = l.Kind,
		Item = if l.Item then ProfileView.item(l.Item) else nil,
		StackId = l.StackId,
		Count = l.Count,
		StartBid = l.StartBid,
		BuyNow = l.BuyNow,
		HighBid = l.HighBid,
		HighBidder = l.HighBidder,
		HighBidderName = l.HighBidderName,
		Bids = l.Bids,
		EndsAt = l.EndsAt,
	}
end

local function publish(l: Listing)
	local map = board
	if map == nil then
		return
	end
	if l.State ~= "Open" then
		try(function()
			map:RemoveAsync(l.Id)
		end)
		return
	end
	local ttl = math.clamp(l.EndsAt - os.time() + 3600, 60, 45 * 86400)
	try(function()
		map:SetAsync(l.Id, summary(l), ttl, l.EndsAt)
	end)
end

local function readBoard(): { any }
	local map = board
	if map == nil then
		return {}
	end
	local ok, items = try(function()
		return map:GetRangeAsync(Enum.SortDirection.Ascending, BOARD_SIZE)
	end)
	local out = {}
	for _, entry in (if ok and items then items else {}) :: { any } do
		if type(entry.value) == "table" and entry.value.EndsAt > os.time() then
			table.insert(out, entry.value)
		end
	end
	return out
end

--------------------------------------------------------------------------------
-- Deliveries and the mailbox
--------------------------------------------------------------------------------

local function delivery(to: number, slot: number?, kind: string, note: string): Delivery
	return { Id = guidNew(), To = to, Slot = slot, Kind = kind, Note = note }
end

-- What a finished listing owes, added to its pending deliveries.
local function owe(record: Record, winner: number?, winnerSlot: number?, price: number)
	local l = record.listing
	local goods = delivery(
		winner or l.Seller,
		if winner then winnerSlot else l.SellerSlot,
		l.Kind,
		if winner then "won" else "returned"
	)
	goods.Item, goods.StackId, goods.Count = l.Item, l.StackId, l.Count
	table.insert(record.pending, goods)
	if winner then
		local pay = delivery(l.Seller, l.SellerSlot, "Gold", "sold")
		pay.Gold = AuctionRules.payout(config(), price)
		table.insert(record.pending, pay)
	end
end

-- Copies a listing's unmailed deliveries to the mailboxes; tidies up when done.
local function flush(id: string)
	local store, mail = listingsStore, mailStore
	if store == nil or mail == nil then
		return
	end
	local ok, record = try(function()
		return store:GetAsync(`L_{id}`)
	end)
	if not ok then
		return
	end
	if record == nil or record.tomb then
		try(function()
			(endsStore :: OrderedDataStore):RemoveAsync(id)
		end)
		return
	end
	local rec = record :: Record
	local sent: { string } = {}
	for _, d in rec.pending do
		if not rec.mailed[d.Id] then
			local okMail = try(function()
				mail:UpdateAsync(`U_{d.To}`, function(old: any): any
					local box = if type(old) == "table" then old else { deliveries = {} }
					box.deliveries[d.Id] = d
					return box
				end)
			end)
			if okMail then
				table.insert(sent, d.Id)
				local to = Players:GetPlayerByUserId(d.To)
				if to then
					notify(to, "Info", "auction.mail", { note = d.Note })
				end
			end
		end
	end
	local finished = false
	if #sent > 0 or rec.listing.State == "Done" then
		try(function()
			store:UpdateAsync(`L_{id}`, function(old: any): any
				if type(old) ~= "table" then
					return nil
				end
				for _, deliveryId in sent do
					old.mailed[deliveryId] = true
				end
				local all = true
				for _, d in old.pending do
					all = all and old.mailed[d.Id] == true
				end
				finished = old.listing.State == "Done" and all
				return old
			end)
		end)
	end
	if finished then
		try(function()
			(endsStore :: OrderedDataStore):RemoveAsync(id)
		end)
		-- Keep a small record (the bid ids) so a late escrow check still
		-- knows this listing held them; never delete it.
		try(function()
			store:UpdateAsync(`L_{id}`, function(old: any): any
				if type(old) ~= "table" then
					return nil
				end
				return {
					listing = {
						Id = id,
						State = "Done",
						Seller = old.listing.Seller,
						EndsAt = old.listing.EndsAt,
					},
					pending = {},
					mailed = {},
					bidIds = old.bidIds,
					tomb = true,
				}
			end)
		end)
	end
end

-- Settles an ended listing (whichever server gets there first).
local function settle(id: string)
	local store = listingsStore
	if store == nil then
		return
	end
	local settled: Listing? = nil
	try(function()
		store:UpdateAsync(`L_{id}`, function(old: any): any
			if type(old) ~= "table" or not AuctionRules.due(old.listing, os.time()) then
				return nil
			end
			local l = old.listing
			l.State = "Done"
			owe(old, l.HighBidder, l.HighBidderSlot, l.HighBid)
			settled = l
			return old
		end)
	end)
	if settled then
		publish(settled :: Listing)
		AuditLogService:Audit({
			actorUserId = (settled :: Listing).Seller,
			action = "AuctionEnd",
			target = id,
			details = { winner = (settled :: Listing).HighBidder, price = (settled :: Listing).HighBid },
		})
	end
	flush(id)
end

-- True if the delivery fits (bag room, stack cap).
local function fits(player: Player, data: { [string]: any }, d: Delivery): boolean
	if d.Kind == "Gold" then
		return true
	elseif d.Kind == "Stack" then
		local def = d.StackId and ItemDefinitions.stackable(d.StackId)
		return def ~= nil and (data.Stackables[d.StackId] or 0) + (d.Count or 0) <= def.maxStack
	end
	return d.Kind == "Item" and type(d.Item) == "table" and InventoryService:FreeSlots(player) >= 1
end

-- Applies a delivery to the profile (no yields). False if there's no room.
local function apply(player: Player, data: { [string]: any }, d: Delivery): boolean
	if d.Kind == "Gold" then
		data.Wallet.Gold = (data.Wallet.Gold or 0) + (d.Gold or 0)
		return true
	elseif d.Kind == "Stack" then
		local def = d.StackId and ItemDefinitions.stackable(d.StackId)
		if def == nil or (data.Stackables[d.StackId] or 0) + (d.Count or 0) > def.maxStack then
			return false
		end
		data.Stackables[d.StackId :: string] = (data.Stackables[d.StackId :: string] or 0) + (d.Count or 0)
		return true
	elseif d.Kind == "Item" and type(d.Item) == "table" then
		if InventoryService:FreeSlots(player) < 1 then
			return false
		end
		local item = table.clone(d.Item)
		if data.Inventory[item.Guid] ~= nil then
			item.Guid = guidNew()
		end
		item.Locked = false
		data.Inventory[item.Guid] = item
		return true
	end
	return false
end

-- Collects the player's mail for the character being played.
local function collect(player: Player)
	local mail = mailStore
	local data = PlayerDataService:GetData(player)
	if mail == nil or data == nil then
		return
	end
	local ok, box = try(function()
		return mail:GetAsync(`U_{player.UserId}`)
	end)
	if not ok or type(box) ~= "table" then
		return
	end
	data = PlayerDataService:GetData(player)
	if data == nil then
		return
	end
	local done: { string } = {}
	local notes = {}
	for id, d in box.deliveries do
		-- For the character that listed / bid; if it was deleted, for anyone.
		local slotGone = d.Slot ~= nil
			and d.Slot ~= data.ActiveSlot
			and (data.Characters or {})[tostring(d.Slot)] == nil
		if d.Slot == nil or d.Slot == data.ActiveSlot or slotGone then
			local claimed = data.ClaimedRewardIds[`M:{id}`] ~= nil
			if claimed then
				table.insert(done, id)
			elseif fits(player, data, d) then
				local status = (PlayerDataService :: any):ClaimReward(player, `M:{id}`, function(profile: any)
					apply(player, profile, d)
				end)
				if status == "granted" then
					table.insert(done, id)
					table.insert(notes, d.Note)
				end
			end
		end
	end
	if #done == 0 then
		return
	end
	InventoryService:Push(player, nil)
	PlayerDataService:PushSnapshot(player)
	-- Only once the profile (with its M: claims) is written does the mail go.
	if not PlayerDataService:SaveAndWait(player, 15) then
		return
	end
	try(function()
		mail:UpdateAsync(`U_{player.UserId}`, function(old: any): any
			if type(old) ~= "table" then
				return nil
			end
			for _, id in done do
				old.deliveries[id] = nil
			end
			return old
		end)
	end)
	if #notes > 0 then
		notify(player, "Info", "auction.collected", { count = tostring(#notes) })
	end
end

--------------------------------------------------------------------------------
-- Escrow recovery (after a crash between the profile and the store)
--------------------------------------------------------------------------------

local function resolveEscrow(player: Player)
	local store = listingsStore
	local data = PlayerDataService:GetData(player)
	if store == nil or data == nil or next(data.Escrow) == nil then
		return
	end
	for key, entry in table.clone(data.Escrow) :: { [string]: any } do
		local ok, record = try(function()
			return store:GetAsync(`L_{entry.ListingId}`)
		end)
		if not ok then
			continue -- try again next join
		end
		data = PlayerDataService:GetData(player)
		if data == nil or data.Escrow[key] == nil then
			return
		end
		local held = false
		if entry.Kind == "List" then
			held = record ~= nil
		elseif entry.Kind == "Bid" then
			held = type(record) == "table"
				and type(record.bidIds) == "table"
				and record.bidIds[entry.BidId] == true
		end
		if not held then
			if entry.Kind == "List" then
				if entry.Item then
					data.Inventory[entry.Item.Guid] = entry.Item
				elseif entry.StackId then
					data.Stackables[entry.StackId] = (data.Stackables[entry.StackId] or 0) + entry.Count
				end
				data.Wallet.Gold += entry.Fee or 0
			else
				data.Wallet.Gold += entry.Gold or 0
			end
			log:Info("user=%d escrow %s returned", player.UserId, key)
		end
		data.Escrow[key] = nil
	end
	PlayerDataService:PushSnapshot(player)
end

--------------------------------------------------------------------------------
-- Actions
--------------------------------------------------------------------------------

local function failReturn(reason: string): { [string]: any }
	return { ok = false, reason = reason }
end

local function mine(player: Player, data: { [string]: any }): { [string]: any }
	local listings = readBoard()
	local selling, bidding = {}, {}
	for _, s in listings do
		if s.Seller == player.UserId then
			table.insert(selling, s)
		elseif s.HighBidder == player.UserId then
			table.insert(bidding, s)
		end
	end
	return { ok = true, selling = selling, bidding = bidding, gold = data.Wallet.Gold or 0 }
end

local function onList(player: Player, data: { [string]: any }, args: { [string]: any }): { [string]: any }
	local c = config()
	local startBid, buyNow, hours = args.StartBid, args.BuyNow, args.Hours
	local okPrice, why = AuctionRules.checkPrices(startBid or 0, buyNow, hours or 0)
	if not okPrice then
		return failReturn(why :: string)
	end
	local count = 0
	for _, s in readBoard() do
		if s.Seller == player.UserId then
			count += 1
		end
	end
	if count >= c.MaxListingsPerPlayer then
		return failReturn("tooMany")
	end
	data = PlayerDataService:GetData(player) :: any
	if data == nil then
		return failReturn("notLoaded")
	end
	local fee = AuctionRules.listFee(c, startBid, buyNow)
	if (data.Wallet.Gold or 0) < fee then
		return failReturn("gold")
	end
	local id = guidNew()
	local entry: { [string]: any } = { Kind = "List", ListingId = id, Fee = fee }
	local kind
	if args.Guid then
		local item = data.Inventory[args.Guid]
		local block = TradeRules.itemBlock(data, args.Guid, item)
		if block then
			return failReturn(block)
		end
		kind = "Item"
		entry.Item = item
	elseif args.StackId then
		local n = args.Count or 0
		local block = TradeRules.stackBlock(args.StackId)
		if block then
			return failReturn(block)
		end
		if n < 1 or n > (data.Stackables[args.StackId] or 0) then
			return failReturn("count")
		end
		kind = "Stack"
		entry.StackId, entry.Count = args.StackId, n
	else
		return failReturn("item")
	end
	-- Escrow: out of the bag (and the fee) in one step.
	if kind == "Item" then
		data.Inventory[args.Guid] = nil
	else
		data.Stackables[entry.StackId] -= entry.Count
		if data.Stackables[entry.StackId] <= 0 then
			data.Stackables[entry.StackId] = nil
		end
	end
	data.Wallet.Gold -= fee
	data.Escrow[id] = entry
	local listing: Listing = {
		Id = id,
		Seller = player.UserId,
		SellerName = player.DisplayName,
		SellerSlot = data.ActiveSlot,
		Kind = kind,
		Item = entry.Item,
		StackId = entry.StackId,
		Count = entry.Count,
		StartBid = startBid,
		BuyNow = buyNow,
		HighBid = 0,
		HighBidder = nil,
		HighBidderName = nil,
		HighBidderSlot = nil,
		Bids = 0,
		EndsAt = os.time() + hours * 3600,
		State = "Open",
	}
	-- The escrow is written before anything shared: a crash after this
	-- point is resolved from the profile on the next load.
	local saved = PlayerDataService:SaveAndWait(player, 15)
	-- The settlement index first (harmless if the listing never appears).
	local indexed = saved
		and try(function()
			(endsStore :: OrderedDataStore):SetAsync(id, listing.EndsAt)
		end)
	local written = indexed
		and try(function()
			(listingsStore :: DataStore):SetAsync(
				`L_{id}`,
				{ listing = listing, pending = {}, mailed = {}, bidIds = {} } :: Record
			)
		end)
	data = PlayerDataService:GetData(player) :: any
	if not written then
		-- Return the escrow at once.
		if data and data.Escrow[id] then
			if kind == "Item" then
				data.Inventory[entry.Item.Guid] = entry.Item
			else
				data.Stackables[entry.StackId] = (data.Stackables[entry.StackId] or 0) + entry.Count
			end
			data.Wallet.Gold += fee
			data.Escrow[id] = nil
			PlayerDataService:PushSnapshot(player)
		end
		return failReturn("store")
	end
	if data then
		data.Escrow[id] = nil
	end
	publish(listing)
	AuditLogService:Audit({
		actorUserId = player.UserId,
		action = "AuctionList",
		target = id,
		details = {
			kind = kind,
			item = entry.Item and entry.Item.DefId or entry.StackId,
			start = startBid,
			buyNow = buyNow,
			fee = fee,
		},
	})
	PlayerDataService:SaveNow(player)
	PlayerDataService:PushSnapshot(player)
	notify(player, "Info", "auction.listed")
	return mine(player, data or {})
end

-- A bid (or Buy Now when `buyNow`): escrow the Gold, then the store.
local function onBid(
	player: Player,
	data: { [string]: any },
	id: string,
	amount: number,
	buyNow: boolean
): { [string]: any }
	local c = config()
	local store = listingsStore :: DataStore
	if buyNow then
		local ok, record = try(function()
			return store:GetAsync(`L_{id}`)
		end)
		if not ok or type(record) ~= "table" or record.listing.BuyNow == nil then
			return failReturn("gone")
		end
		amount = record.listing.BuyNow
	end
	data = PlayerDataService:GetData(player) :: any
	if data == nil then
		return failReturn("notLoaded")
	end
	if type(amount) ~= "number" or amount < 1 or (data.Wallet.Gold or 0) < amount then
		return failReturn("gold")
	end
	local bidId = guidNew()
	local key = `B:{bidId}`
	data.Wallet.Gold -= amount
	data.Escrow[key] = { Kind = "Bid", ListingId = id, BidId = bidId, Gold = amount }
	local reason: string? = "store"
	if not PlayerDataService:SaveAndWait(player, 15) then
		data = PlayerDataService:GetData(player) :: any
		if data and data.Escrow[key] then
			data.Wallet.Gold += amount
			data.Escrow[key] = nil
		end
		return failReturn("store")
	end
	local result: Listing? = nil
	local outbid: number? = nil
	try(function()
		store:UpdateAsync(`L_{id}`, function(old: any): any
			reason = "gone"
			if type(old) ~= "table" then
				return nil
			end
			local l = old.listing
			if buyNow then
				if l.State ~= "Open" or os.time() >= l.EndsAt or l.BuyNow ~= amount then
					reason = "ended"
					return nil
				elseif l.Seller == player.UserId then
					reason = "own"
					return nil
				end
			else
				local okBid, why = AuctionRules.canBid(c, l, player.UserId, amount, os.time())
				if not okBid then
					reason = why
					return nil
				end
			end
			if l.HighBidder then
				local refund = delivery(l.HighBidder, l.HighBidderSlot, "Gold", "outbid")
				refund.Gold = l.HighBid
				table.insert(old.pending, refund)
				outbid = l.HighBidder
			end
			l.HighBid, l.HighBidder, l.HighBidderName, l.HighBidderSlot =
				amount, player.UserId, player.DisplayName, data.ActiveSlot
			l.Bids += 1
			old.bidIds[bidId] = true
			if buyNow then
				l.State = "Done"
				owe(old, player.UserId, data.ActiveSlot, amount)
			end
			reason = nil
			result = l
			return old
		end)
	end)
	data = PlayerDataService:GetData(player) :: any
	if data == nil then
		return failReturn("notLoaded")
	end
	if result == nil then
		if data.Escrow[key] then
			data.Wallet.Gold += amount
			data.Escrow[key] = nil
			PlayerDataService:PushSnapshot(player)
		end
		return failReturn(reason or "store")
	end
	-- The listing holds the Gold now.
	data.Escrow[key] = nil
	publish(result :: Listing)
	AuditLogService:Audit({
		actorUserId = player.UserId,
		action = if buyNow then "AuctionBuyNow" else "AuctionBid",
		target = id,
		details = { gold = amount },
	})
	if outbid then
		local loser = Players:GetPlayerByUserId(outbid)
		if loser and loser ~= player then
			notify(loser, "Warning", "auction.outbid")
		end
	end
	PlayerDataService:SaveNow(player)
	PlayerDataService:PushSnapshot(player)
	task.spawn(flush, id)
	if buyNow then
		task.delay(3, collect, player)
	end
	notify(player, "Info", if buyNow then "auction.bought" else "auction.bidPlaced")
	return { ok = true, gold = data.Wallet.Gold }
end

local function onCancel(player: Player, id: string): { [string]: any }
	local store = listingsStore :: DataStore
	local reason: string? = "gone"
	local done: Listing? = nil
	try(function()
		store:UpdateAsync(`L_{id}`, function(old: any): any
			if type(old) ~= "table" then
				return nil
			end
			local l = old.listing
			if l.Seller ~= player.UserId then
				reason = "own"
				return nil
			elseif l.State ~= "Open" then
				reason = "ended"
				return nil
			elseif l.Bids > 0 then
				reason = "hasBids"
				return nil
			end
			l.State = "Done"
			owe(old, nil, nil, 0)
			reason = nil
			done = l
			return old
		end)
	end)
	if done == nil then
		return failReturn(reason or "store")
	end
	publish(done :: Listing)
	AuditLogService:Audit({ actorUserId = player.UserId, action = "AuctionCancel", target = id })
	flush(id)
	collect(player)
	return { ok = true }
end

local function onRequest(player: Player, action: string, args: { [string]: any }): { [string]: any }
	local data = PlayerDataService:GetData(player)
	if data == nil or data.Job == nil then
		return failReturn("notLoaded")
	end
	if listingsStore == nil or board == nil then
		return failReturn("offline")
	end
	if not ShopService:Near(player, data, NPC) then
		return failReturn("far")
	end
	local c = config()
	if not c.Enabled then
		return failReturn("closed")
	end
	if action == "Browse" then
		local listings = readBoard()
		for _, l in listings do
			l.MinBid = AuctionRules.minBid(c, l :: any)
		end
		return {
			ok = true,
			listings = listings,
			gold = data.Wallet.Gold or 0,
			me = player.UserId,
			fees = {
				ListFeePct = c.ListFeePct,
				MinListFee = c.MinListFee,
				SaleFeePct = c.SaleFeePct,
				MaxListings = c.MaxListingsPerPlayer,
				MinLevel = c.MinLevel,
			},
		}
	elseif action == "Mine" then
		return mine(player, data)
	elseif action == "Mail" then
		collect(player)
		return { ok = true }
	end
	if (data.Level or 0) < c.MinLevel then
		return failReturn("level")
	end
	if action == "List" then
		return onList(player, data, args)
	elseif action == "Bid" then
		return onBid(player, data, args.ListingId, args.Bid or 0, false)
	elseif action == "BuyNow" then
		return onBid(player, data, args.ListingId, 0, true)
	elseif action == "Cancel" then
		return onCancel(player, args.ListingId)
	end
	return failReturn("action")
end

function AuctionService:Init()
	local ok = pcall(function()
		listingsStore = DataStoreService:GetDataStore("RC_Auction_v1")
		endsStore = DataStoreService:GetOrderedDataStore("RC_AuctionEnds_v1")
		mailStore = DataStoreService:GetDataStore("RC_Mail_v1")
		board = MemoryStoreService:GetSortedMap("RC_AuctionBoard")
	end)
	if not ok then
		log:Warn("auction stores unavailable; the market is offline on this server")
	end
	NetService:Handle("Auction", onRequest)
end

function AuctionService:Start()
	PlayerDataService.ProfileLoaded:Connect(function(player)
		task.spawn(function()
			resolveEscrow(player)
			collect(player)
		end)
	end)
	-- Mail for players online here, and settling ended listings.
	task.spawn(function()
		local sinceMail = 0
		while true do
			task.wait(SCAN_SECONDS + math.random() * 10)
			sinceMail += SCAN_SECONDS
			if sinceMail >= MAIL_SECONDS then
				sinceMail = 0
				for _, player in Players:GetPlayers() do
					task.spawn(collect, player)
				end
			end
			local index = endsStore
			if index then
				local ok, pages = try(function()
					return index:GetSortedAsync(true, 20, nil, os.time())
				end)
				if ok and pages then
					for _, entry in (pages :: any):GetCurrentPage() do
						settle(entry.key)
					end
				end
			end
		end
	end)
end

return AuctionService
