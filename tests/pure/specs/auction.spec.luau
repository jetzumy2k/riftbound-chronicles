--[[
	D-122: Auction market rules: prices, fees, the minimum raise and who
	may bid.
]]
local load = require("../loader")
local AuctionRules = load("src/shared/Logic/AuctionRules")
local RewardClaims = load("src/server/Persistence/RewardClaims")
local Defaults = load("src/server/Config/Defaults")

local function listing(): any
	return {
		Id = "x",
		Seller = 1,
		SellerName = "S",
		SellerSlot = 1,
		Kind = "Item",
		StartBid = 100,
		BuyNow = 500,
		HighBid = 0,
		Bids = 0,
		EndsAt = 1000,
		State = "Open",
	}
end

return function(t)
	t.describe("Auction market (D-122)", function()
		local c = Defaults.Auction

		t.it("prices: a starting bid, Buy Now above it, 12 / 24 / 48 hours", function()
			t.ok(AuctionRules.checkPrices(100, nil, 24))
			t.ok(AuctionRules.checkPrices(100, 150, 12))
			t.eq(select(2, AuctionRules.checkPrices(0, nil, 24)), "price")
			t.eq(select(2, AuctionRules.checkPrices(100, 100, 24)), "buyNow")
			t.eq(select(2, AuctionRules.checkPrices(100, nil, 6)), "hours")
		end)

		t.it("fees: a small listing fee, the sale fee taken from the price", function()
			t.eq(AuctionRules.listFee(c, 10, nil), c.MinListFee)
			t.eq(AuctionRules.listFee(c, 100, 10000), math.floor(10000 * c.ListFeePct / 100))
			t.eq(AuctionRules.payout(c, 1000), 1000 - math.floor(1000 * c.SaleFeePct / 100))
		end)

		t.it("bids start at the starting bid, then rise by the minimum raise", function()
			local l = listing()
			t.eq(AuctionRules.minBid(c, l), 100)
			t.ok(AuctionRules.canBid(c, l, 2, 100, 10))
			t.eq(select(2, AuctionRules.canBid(c, l, 2, 99, 10)), "low")
			t.eq(select(2, AuctionRules.canBid(c, l, 1, 200, 10)), "own")
			t.eq(select(2, AuctionRules.canBid(c, l, 2, 500, 10)), "buyNow")
			t.eq(select(2, AuctionRules.canBid(c, l, 2, 200, 1000)), "ended")
			l.HighBid, l.HighBidder = 100, 2
			t.eq(AuctionRules.minBid(c, l), 100 + math.max(1, math.ceil(100 * c.MinRaisePct / 100)))
			t.ok(AuctionRules.due(l, 1000))
			t.ok(not AuctionRules.due(l, 999))
		end)

		t.it("mailbox deliveries are claimed once (M:<id>)", function()
			t.ok(RewardClaims.isValidId("M:0f8fad5b-d9cb-469f-a165-70867728950e"))
		end)
	end)
end
