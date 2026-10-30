--!strict
--[[
	AuctionController — the Auction market screen (creator request
	2026-10-27, PLAN.md D-122). Opens from the 🏛️ Auctioneer (NpcOpen).
	Display and requests only: prices, bids, fees, escrow and deliveries
	are the server's (AuctionService).

	  Browse  every open listing (ending soonest first), filtered by kind
	          and rarity; tap one, then bid (at least the minimum shown)
	          or Buy Now. Both ask twice.
	  Mine    what you are selling (cancel if nobody bid yet) and the
	          auctions you lead; "Collect mail" fetches deliveries now
	          (they also arrive by themselves within a minute).
	  Sell    pick an item from your bag or a consumable, a starting bid,
	          an optional Buy Now and 12 / 24 / 48 hours; the fee shows
	          before you list.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemDefinitions = require(Shared.Definitions.ItemDefinitions)
local NetClient = require(Shared.Net.Client)

local UI = script.Parent.Parent.UI
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)
local Panels = require(UI.Panels)
local PlayerDataController = require(script.Parent.PlayerDataController)
local InventoryController = require(script.Parent.InventoryController)

local AuctionController = {}

local BAD = Color3.fromRGB(255, 140, 130)
local RARITIES = { "Standard", "Uncommon", "Rare", "Epic", "Legendary", "Mythical" }
local RARITY_COLOR = {
	Standard = Color3.fromRGB(200, 200, 200),
	Uncommon = Color3.fromRGB(110, 225, 120),
	Rare = Color3.fromRGB(90, 160, 255),
	Epic = Color3.fromRGB(190, 110, 255),
	Legendary = Color3.fromRGB(255, 165, 50),
	Mythical = Color3.fromRGB(255, 80, 110),
}
local KINDS = {
	{ id = "All", label = "All" },
	{ id = "Weapons", label = "🗡️ Weapons" },
	{ id = "Armor", label = "🛡️ Armor" },
	{ id = "Accessories", label = "💍 Accessories" },
	{ id = "Consumables", label = "🧪 Consumables" },
}
local KIND_OF_SLOT = {
	Weapon = "Weapons",
	Shield = "Armor",
	Helm = "Armor",
	Shoulders = "Armor",
	Chest = "Armor",
	Hands = "Armor",
	Legs = "Armor",
	Boots = "Armor",
	Necklace = "Accessories",
	Earrings = "Accessories",
	Ring = "Accessories",
}
local MALL_ONLY = {
	RebirthScroll = true,
	RelearnScroll = true,
	RaceRune = true,
	GreaterHealingPotion = true,
	MajorHealingPotion = true,
	SupremeHealingPotion = true,
}
local REASONS = {
	far = "Walk closer to the Auctioneer.",
	closed = "The Auction market is closed for now.",
	offline = "The Auction market is unavailable on this server.",
	level = "You need a higher level for the Auction market.",
	gold = "Not enough Gold.",
	low = "Bid at least the minimum shown.",
	ended = "That auction has ended.",
	own = "You can't bid on your own auction.",
	buyNow = "That bid reaches the Buy Now price: use Buy Now instead.",
	gone = "That auction is gone.",
	hasBids = "Someone already bid; it can't be cancelled.",
	tooMany = "You have the most auctions allowed at once.",
	price = "Enter a starting bid of at least 1 Gold.",
	hours = "Pick how long it runs.",
	mall = "Item Mall items can't be sold here.",
	locked = "Unlock the item in your bag first.",
	equipped = "Take the item off first.",
	count = "You don't have that many.",
	item = "Pick something to sell.",
	store = "The market didn't answer; nothing changed. Try again.",
	RateLimited = "Too fast; wait a moment.",
	BadArgs = "That request was not accepted.",
	HandlerError = "Something went wrong on the server; try again.",
}

local panel: Frame? = nil
local content: Frame? = nil
local page = "Browse"
local listed: any = nil
local mine: any = nil
local kindFilter, rarityFilter = "All", "All"
local selected: string? = nil
local confirming: string? = nil
local status, statusBad = "", false
local fields: { [string]: string } = {}
local sellPick: string? = nil -- "item:<guid>" | "stack:<id>"
local sellHours = 24

local render: () -> ()

local function setStatus(text: string, bad: boolean?)
	status, statusBad = text, bad == true
end

local function call(action: string, args: { [string]: any }?): any
	local result = NetClient.invoke("Auction", action, args or {})
	if type(result) ~= "table" then
		setStatus("No answer from the server.", true)
		return nil
	end
	if result.ok == false then
		setStatus(
			REASONS[result.reason or result.code] or `Refused ({tostring(result.reason or result.code)}).`,
			true
		)
		return nil
	end
	return result
end

local function text(parent: Instance, body: string, size: number, color: Color3?, bold: boolean?): TextLabel
	return Kit.new("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = body,
		TextSize = size,
		FontFace = if bold then Theme.Fonts.BodyBold else Theme.Fonts.Body,
		TextColor3 = color or Theme.Colors.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Parent = parent,
	})
end

local function button(
	parent: Instance,
	label: string,
	width: number,
	gold: boolean?,
	onClick: () -> ()
): TextButton
	local b = Kit.new("TextButton", {
		Size = UDim2.fromOffset(width, 36),
		BackgroundColor3 = if gold then Theme.Colors.Gold else Theme.Colors.GlassHighlight,
		BackgroundTransparency = if gold then 0.05 else 0.3,
		Text = label,
		TextSize = 13,
		FontFace = Theme.Fonts.BodyBold,
		TextColor3 = if gold then Theme.Colors.Ink else Theme.Colors.Text,
		TextTruncate = Enum.TextTruncate.AtEnd,
		AutoButtonColor = true,
		Parent = parent,
	})
	Kit.corner(b, 8)
	b.Activated:Connect(onClick)
	return b
end

local function row(parent: Instance, y: number?): Frame
	local frame = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 36),
		Parent = parent,
	})
	if y then
		frame.Position = UDim2.fromOffset(14, y)
		frame.Size = UDim2.new(1, -28, 0, 36)
	end
	Kit.list(frame, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Left)
	return frame
end

local function box(parent: Instance, key: string, placeholder: string, width: number): TextBox
	local b = Kit.new("TextBox", {
		Size = UDim2.fromOffset(width, 36),
		BackgroundColor3 = Theme.Colors.Ink,
		BackgroundTransparency = 0.1,
		PlaceholderText = placeholder,
		PlaceholderColor3 = Theme.Colors.TextMuted,
		Text = fields[key] or "",
		TextSize = 14,
		FontFace = Theme.Fonts.Body,
		TextColor3 = Theme.Colors.Text,
		ClearTextOnFocus = false,
		Parent = parent,
	})
	Kit.corner(b, 8)
	b:GetPropertyChangedSignal("Text"):Connect(function()
		fields[key] = b.Text
	end)
	return b
end

local function twice(key: string, action: () -> ())
	if confirming ~= key then
		confirming = key
		task.delay(4, function()
			if confirming == key then
				confirming = nil
				render()
			end
		end)
		render()
		return
	end
	confirming = nil
	action()
end

local function left(endsAt: number): string
	local s = math.max(0, endsAt - os.time())
	local h, m = s // 3600, (s % 3600) // 60
	return if h > 0 then `{h}h {m}m` else `{math.max(1, m)}m`
end

-- What a listing sells, in one line.
local function whatOf(l: any): (string, Color3)
	if l.Kind == "Stack" then
		local def = ItemDefinitions.stackable(l.StackId)
		return `{if def then def.glyph else ""} {l.Count} × {if def then def.name else l.StackId}`,
			Theme.Colors.Text
	end
	local item = l.Item or {}
	local def = ItemDefinitions.get(item.DefId)
	return `{if def then def.glyph else "?"} {if def then def.name else "?"} · {item.Rarity} · Lv {item.ItemLevel}{if (
			item.Enhancement or 0
		) > 0
		then ` · +{item.Enhancement}`
		else ""}`,
		RARITY_COLOR[item.Rarity] or Theme.Colors.Text
end

local function kindOf(l: any): string
	if l.Kind == "Stack" then
		return "Consumables"
	end
	local def = l.Item and ItemDefinitions.get(l.Item.DefId)
	return if def then KIND_OF_SLOT[def.slot] or "Armor" else "Armor"
end

local function listingCard(parent: Instance, l: any, chosen: boolean, onClick: () -> ())
	local b = Kit.new("TextButton", {
		BackgroundColor3 = if chosen then Theme.Colors.GlassRaised else Theme.Colors.Ink,
		BackgroundTransparency = if chosen then 0.05 else 0.4,
		Size = UDim2.new(1, -4, 0, 58),
		Text = "",
		AutoButtonColor = true,
		Parent = parent,
	})
	Kit.corner(b, 10)
	if chosen then
		Kit.goldStroke(b, 2, 0)
	end
	local what, color = whatOf(l)
	local a = text(b, what, 14, color, true)
	a.AutomaticSize = Enum.AutomaticSize.None
	a.Position = UDim2.fromOffset(12, 6)
	a.Size = UDim2.new(1, -220, 0, 20)
	a.TextTruncate = Enum.TextTruncate.AtEnd
	a.TextWrapped = false
	local sub =
		text(b, `by {l.SellerName} · {l.Bids} bid(s) · ends in {left(l.EndsAt)}`, 12, Theme.Colors.TextDim)
	sub.AutomaticSize = Enum.AutomaticSize.None
	sub.Position = UDim2.fromOffset(12, 30)
	sub.Size = UDim2.new(1, -220, 0, 18)
	local price = text(
		b,
		`{if l.HighBidder then "Bid" else "Start"}: {if l.HighBidder then l.HighBid else l.StartBid}{if l.BuyNow
			then `\nBuy Now: {l.BuyNow}`
			else ""}`,
		13,
		Theme.Colors.GoldBright,
		true
	)
	price.AutomaticSize = Enum.AutomaticSize.None
	price.AnchorPoint = Vector2.new(1, 0)
	price.Position = UDim2.new(1, -12, 0, 6)
	price.Size = UDim2.fromOffset(200, 46)
	price.TextXAlignment = Enum.TextXAlignment.Right
	b.Activated:Connect(onClick)
end

local function refresh()
	local result = call(if page == "Mine" then "Mine" else "Browse")
	if result then
		if page == "Mine" then
			mine = result
		else
			listed = result
		end
	end
	render()
end

local function drawBrowse(body: Instance, bar: Frame)
	local l = listed
	if l == nil then
		text(body, "Loading...", 13, Theme.Colors.TextDim)
		return
	end
	local shown = 0
	local chosen: any = nil
	for _, entry in l.listings do
		local rarity = if entry.Item then entry.Item.Rarity else nil
		if
			(kindFilter == "All" or kindOf(entry) == kindFilter)
			and (rarityFilter == "All" or rarity == rarityFilter)
		then
			shown += 1
			if entry.Id == selected then
				chosen = entry
			end
			listingCard(body, entry, entry.Id == selected, function()
				selected = entry.Id
				fields.bid = tostring(entry.MinBid)
				confirming = nil
				render()
			end)
		end
	end
	if shown == 0 then
		text(body, "No auctions match. Try other filters, or be the first to sell!", 13, Theme.Colors.TextDim)
	end
	-- The bar: bid / Buy Now for the chosen listing.
	if chosen == nil then
		text(bar, "  Tap an auction to bid or buy.", 13, Theme.Colors.TextDim, true).Size =
			UDim2.fromScale(1, 1)
		return
	end
	local mineToo = chosen.Seller == l.me
	local info = text(bar, `Lowest bid now: {chosen.MinBid} Gold`, 13, Theme.Colors.Text, true)
	info.Size = UDim2.fromOffset(200, 48)
	if mineToo then
		info.Text = "This is your auction."
		return
	end
	box(bar, "bid", "Your bid", 100)
	button(
		bar,
		if confirming == "bid" then "Tap to bid" else "Place bid",
		110,
		confirming == "bid",
		function()
			local amount = math.floor(tonumber(fields.bid) or 0)
			twice("bid", function()
				if call("Bid", { ListingId = chosen.Id, Bid = amount }) then
					setStatus(`✅ You bid {amount} Gold. It's held until you're outbid or it ends.`)
					refresh()
				else
					render()
				end
			end)
		end
	)
	if chosen.BuyNow then
		button(
			bar,
			if confirming == "buy" then `Pay {chosen.BuyNow}` else `Buy Now {chosen.BuyNow}`,
			140,
			true,
			function()
				twice("buy", function()
					if call("BuyNow", { ListingId = chosen.Id }) then
						setStatus("✅ Bought! It arrives in your bag within a minute.")
						selected = nil
						refresh()
					else
						render()
					end
				end)
			end
		)
	end
end

local function drawMine(body: Instance, bar: Frame)
	local m = mine
	if m == nil then
		text(body, "Loading...", 13, Theme.Colors.TextDim)
		return
	end
	text(body, `Selling ({#m.selling})`, 15, Theme.Colors.GoldBright, true)
	for _, entry in m.selling do
		listingCard(body, entry, false, function() end)
		if entry.Bids == 0 then
			local key = `cancel{entry.Id}`
			button(
				body,
				if confirming == key then "Tap to cancel" else "Cancel (no bids yet)",
				180,
				false,
				function()
					twice(key, function()
						if call("Cancel", { ListingId = entry.Id }) then
							setStatus("✅ Cancelled. The item is on its way back to your bag.")
						end
						refresh()
					end)
				end
			)
		end
	end
	if #m.selling == 0 then
		text(body, "Nothing for sale.", 13, Theme.Colors.TextDim)
	end
	text(body, `Leading bids ({#m.bidding})`, 15, Theme.Colors.GoldBright, true)
	for _, entry in m.bidding do
		listingCard(body, entry, false, function() end)
	end
	if #m.bidding == 0 then
		text(body, "You aren't leading any auction.", 13, Theme.Colors.TextDim)
	end
	text(bar, "  Wins, sales, refunds and returns arrive by mail on their own.", 12, Theme.Colors.TextDim).Size =
		UDim2.new(1, -170, 1, 0)
	local go = button(bar, "📬 Collect mail", 150, true, function()
		if call("Mail") then
			setStatus("✅ Mail collected.")
		end
		refresh()
	end)
	go.AnchorPoint = Vector2.new(1, 0.5)
	go.Position = UDim2.new(1, -8, 0.5, 0)
end

local function drawSell(body: Instance, bar: Frame)
	local state = PlayerDataController:Get()
	local fees = (listed and listed.fees)
		or { ListFeePct = 2, MinListFee = 10, SaleFeePct = 5, MaxListings = 5 }
	text(
		body,
		`Pick what to sell (up to {fees.MaxListings} auctions at once). Equipped, locked and Item Mall items can't be sold. The sale fee is {fees.SaleFeePct}%.`,
		12,
		Theme.Colors.TextDim
	)
	local worn: { [string]: boolean } = {}
	for _, guid in state.Equipment do
		worn[guid] = true
	end
	text(body, "Gear", 14, Theme.Colors.GoldBright, true)
	for guid, item in state.Inventory do
		if not worn[guid] and not (item :: any).Locked then
			local key = `item:{guid}`
			local on = sellPick == key
			local what, color = whatOf({ Kind = "Item", Item = item })
			local b = button(body, `{if on then "✅" else "▢"}  {what}`, 10, false, function()
				sellPick = key
				render()
			end)
			b.Size = UDim2.new(1, -4, 0, 32)
			b.TextXAlignment = Enum.TextXAlignment.Left
			b.TextColor3 = color
			b.BackgroundTransparency = if on then 0.05 else 0.5
			Kit.padding(b, 0, 8)
		end
	end
	text(body, "Consumables", 14, Theme.Colors.GoldBright, true)
	for _, id in ItemDefinitions.STACKABLE_ORDER do
		local have = state.Stackables[id] or 0
		if have > 0 and not MALL_ONLY[id] and string.sub(id, 1, 5) ~= "Buff_" then
			local key = `stack:{id}`
			local on = sellPick == key
			local def = ItemDefinitions.stackable(id)
			local b = button(
				body,
				`{if on then "✅" else "▢"}  {if def then def.glyph else ""} {if def then def.name else id} (you have {have})`,
				10,
				false,
				function()
					sellPick = key
					render()
				end
			)
			b.Size = UDim2.new(1, -4, 0, 32)
			b.TextXAlignment = Enum.TextXAlignment.Left
			b.BackgroundTransparency = if on then 0.05 else 0.5
			Kit.padding(b, 0, 8)
		end
	end
	-- The terms, in the bar's two rows.
	local isStack = sellPick ~= nil and string.sub(sellPick, 1, 6) == "stack:"
	local terms = row(bar)
	if isStack then
		box(terms, "count", "How many", 80)
	end
	box(terms, "start", "Start bid", 90)
	box(terms, "buynow", "Buy Now (optional)", 130)
	for _, h in { 12, 24, 48 } do
		button(terms, `{h}h`, 46, sellHours == h, function()
			sellHours = h
			render()
		end)
	end
	local startBid = math.floor(tonumber(fields.start) or 0)
	local buyNow = tonumber(fields.buynow)
	local fee = math.max(fees.MinListFee, math.floor((buyNow or startBid) * fees.ListFeePct / 100))
	button(terms, if confirming == "list" then `Pay fee {fee}` else `List · fee {fee}`, 130, true, function()
		if sellPick == nil then
			setStatus(REASONS.item, true)
			render()
			return
		end
		local args: { [string]: any } = {
			StartBid = startBid,
			BuyNow = if buyNow then math.floor(buyNow) else nil,
			Hours = sellHours,
		}
		local pick = sellPick :: string
		if string.sub(pick, 1, 5) == "item:" then
			args.Guid = string.sub(pick, 6)
		else
			args.StackId = string.sub(pick, 7)
			args.Count = math.floor(tonumber(fields.count) or 0)
		end
		twice("list", function()
			if call("List", args) then
				setStatus("✅ Listed! See it under Mine.")
				sellPick = nil
				fields.start, fields.buynow, fields.count = "", "", ""
			end
			render()
		end)
	end)
end

function render()
	local frame = content
	if frame == nil then
		return
	end
	frame:ClearAllChildren()
	local title = Kit.label("🏛️ Auction market", 18, Theme.Fonts.Display, Theme.Colors.GoldBright)
	title.AutomaticSize = Enum.AutomaticSize.None
	title.Position = UDim2.fromOffset(14, 10)
	title.Size = UDim2.new(1, -260, 0, 26)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = frame
	local gold =
		text(frame, `💰 {PlayerDataController:Get().Wallet.Gold} Gold`, 15, Theme.Colors.GoldBright, true)
	gold.AutomaticSize = Enum.AutomaticSize.None
	gold.AnchorPoint = Vector2.new(1, 0)
	gold.Position = UDim2.new(1, -100, 0, 14)
	gold.Size = UDim2.fromOffset(150, 24)
	gold.TextXAlignment = Enum.TextXAlignment.Right
	local shut = button(frame, "Close", 80, false, AuctionController.close)
	shut.AnchorPoint = Vector2.new(1, 0)
	shut.Position = UDim2.new(1, -10, 0, 8)
	local tabs = row(frame, 44)
	for _, name in { "Browse", "Mine", "Sell" } do
		button(tabs, name, 100, page == name, function()
			page = name
			confirming = nil
			setStatus("")
			if name ~= "Sell" then
				task.spawn(refresh)
			end
			render()
		end)
	end
	local top = 88
	if page == "Browse" then
		local kinds = row(frame, top)
		for _, k in KINDS do
			button(kinds, k.label, 120, kindFilter == k.id, function()
				kindFilter = k.id
				render()
			end)
		end
		top += 42
		local rarities = row(frame, top)
		button(rarities, "All", 60, rarityFilter == "All", function()
			rarityFilter = "All"
			render()
		end)
		for _, r in RARITIES do
			local b = button(rarities, r, 90, rarityFilter == r, function()
				rarityFilter = r
				render()
			end)
			if rarityFilter ~= r then
				b.TextColor3 = RARITY_COLOR[r]
			end
		end
		top += 42
	end
	local statusLabel = text(frame, status, 13, if statusBad then BAD else Theme.Colors.Safe, true)
	statusLabel.AnchorPoint = Vector2.new(0, 1)
	statusLabel.Position = UDim2.new(0, 14, 1, -8)
	statusLabel.Size = UDim2.new(1, -28, 0, 0)
	local bar = Kit.new("Frame", {
		BackgroundColor3 = Theme.Colors.Ink,
		BackgroundTransparency = 0.15,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 10, 1, -34),
		Size = UDim2.new(1, -20, 0, 52),
		Parent = frame,
	})
	Kit.corner(bar, 10)
	Kit.padding(bar, 8, 8)
	local barList = Kit.list(bar, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Left)
	barList.VerticalAlignment = Enum.VerticalAlignment.Center
	local scroll = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, top),
		Size = UDim2.new(1, -20, 1, -top - 92),
		CanvasSize = UDim2.fromScale(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = frame,
	})
	local list = Kit.list(scroll, Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Left)
	list.VerticalAlignment = Enum.VerticalAlignment.Top
	Kit.padding(scroll, 4, 4)
	if page == "Mine" then
		drawMine(scroll, bar)
	elseif page == "Sell" then
		drawSell(scroll, bar)
	else
		drawBrowse(scroll, bar)
	end
end

function AuctionController.close()
	if panel then
		panel:Destroy()
		panel, content = nil, nil
		Panels.closed("auction")
	end
end

local function open()
	AuctionController.close()
	InventoryController.setOpen(false)
	Panels.opened("auction")
	page, selected, confirming, sellPick = "Browse", nil, nil, nil
	setStatus("")
	local layer = Panels.layer()
	local screen = layer.AbsoluteSize
	local w, h = math.min(screen.X - 16, 860), math.min(screen.Y - 16, 640)
	local frame = Kit.glassPanel({
		Name = "Auction",
		Active = true,
		Position = UDim2.fromOffset((screen.X - w) / 2, (screen.Y - h) / 2),
		Size = UDim2.fromOffset(w, h),
		Parent = layer,
	})
	frame.BackgroundTransparency = 0.04
	panel = frame
	content = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = frame })
	render()
	task.spawn(refresh)
end

function AuctionController:Start()
	Panels.register("auction", AuctionController.close)
	NetClient.on("NpcOpen", function(payload: any)
		if type(payload) == "table" and payload.Npc == "Auctioneer" then
			open()
		end
	end)
end

return AuctionController
