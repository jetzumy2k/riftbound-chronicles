--!strict
--[[
	AuctionRules — the Auction market (creator request 2026-10-27, PLAN.md
	D-122; numbers in config Auction). Pure.

	A seller lists one item, or a stack of a consumable, with a starting
	bid and optionally a Buy Now price, for 12, 24 or 48 hours, paying a
	small listing fee. Others bid (each bid at least MinRaisePct % above
	the last, the bid's Gold held until outbid or the end) or Buy Now. At
	the end the item goes to the highest bidder and the Gold, minus the
	SaleFeePct fee, to the seller; with no bids the item goes back. What may
	be listed follows the trading rules (TradeRules: never Mall items,
	equipped or locked gear). Mall Points are never used.
]]

local AuctionRules = {}

AuctionRules.HOURS = table.freeze({ 12, 24, 48 })

export type Config = {
	Enabled: boolean,
	MinLevel: number,
	MaxListingsPerPlayer: number,
	ListFeePct: number,
	MinListFee: number,
	SaleFeePct: number,
	MinRaisePct: number,
}

export type Listing = {
	Id: string,
	Seller: number,
	SellerName: string,
	SellerSlot: number,
	Kind: string, -- "Item" | "Stack"
	Item: any?,
	StackId: string?,
	Count: number?,
	StartBid: number,
	BuyNow: number?,
	HighBid: number,
	HighBidder: number?,
	HighBidderName: string?,
	HighBidderSlot: number?,
	Bids: number,
	EndsAt: number,
	State: string, -- "Open" | "Done"
}

-- (ok, reason): the prices and length a seller asked for.
function AuctionRules.checkPrices(startBid: number, buyNow: number?, hours: number): (boolean, string?)
	if startBid % 1 ~= 0 or startBid < 1 or startBid > 1e12 then
		return false, "price"
	elseif buyNow ~= nil and (buyNow % 1 ~= 0 or buyNow <= startBid or buyNow > 1e12) then
		return false, "buyNow"
	elseif table.find(AuctionRules.HOURS, hours) == nil then
		return false, "hours"
	end
	return true, nil
end

function AuctionRules.listFee(config: Config, startBid: number, buyNow: number?): number
	local basis = buyNow or startBid
	return math.max(config.MinListFee, math.floor(basis * config.ListFeePct / 100))
end

-- What the seller receives for a sale at `price`.
function AuctionRules.payout(config: Config, price: number): number
	return math.max(0, price - math.floor(price * config.SaleFeePct / 100))
end

-- The lowest bid that is accepted now.
function AuctionRules.minBid(config: Config, listing: Listing): number
	if listing.HighBidder == nil then
		return listing.StartBid
	end
	return listing.HighBid + math.max(1, math.ceil(listing.HighBid * config.MinRaisePct / 100))
end

--[[
	(ok, reason) for `bidder` bidding `amount` on `listing` at `now`:
	ended, own, low, buyNow (at or above Buy Now: use Buy Now).
]]
function AuctionRules.canBid(
	config: Config,
	listing: Listing,
	bidder: number,
	amount: number,
	now: number
): (boolean, string?)
	if listing.State ~= "Open" or now >= listing.EndsAt then
		return false, "ended"
	elseif listing.Seller == bidder then
		return false, "own"
	elseif amount < AuctionRules.minBid(config, listing) then
		return false, "low"
	elseif listing.BuyNow ~= nil and amount >= listing.BuyNow then
		return false, "buyNow"
	end
	return true, nil
end

-- True when the listing is over (time up) but not yet settled.
function AuctionRules.due(listing: Listing, now: number): boolean
	return listing.State == "Open" and now >= listing.EndsAt
end

return table.freeze(AuctionRules)
