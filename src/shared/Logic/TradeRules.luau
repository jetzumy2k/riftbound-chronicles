--!strict
--[[
	TradeRules — what may change hands in a player trade and whether a trade
	can complete (creator request 2026-10-27, PLAN.md D-121). Pure.

	Tradeable: Gold, gear and weapons earned in play, and consumables
	that can be earned in play. Never: Mall Points, gear bought in the
	Item Mall (item Source "Mall:..."), Mall-only consumables (MALL_ONLY),
	equipped or locked items (creator decision 2026-10-27).

	An offer is { Gold, Items = { guid }, Stackables = { [id] = count } }.
]]

local ItemDefinitions = require(script.Parent.Parent.Definitions.ItemDefinitions)
local ItemRules = require(script.Parent.ItemRules)

local TradeRules = {}

TradeRules.MAX_ITEMS = 8
TradeRules.MAX_STACKS = 6
TradeRules.COUNTDOWN_SECONDS = 3
TradeRules.INVITE_SECONDS = 30
TradeRules.HISTORY = 20

-- Consumables only sold in the Item Mall (or Mall-tier): never traded.
TradeRules.MALL_ONLY = table.freeze({
	RebirthScroll = true,
	RelearnScroll = true,
	RaceRune = true,
	GreaterHealingPotion = true,
	MajorHealingPotion = true,
	SupremeHealingPotion = true,
	Buff_Insight = true,
	Buff_Fortune = true,
	Buff_StoneSeeker = true,
	Buff_Might = true,
	Buff_Iron = true,
	Buff_Vigor = true,
	Buff_Clarity = true,
})

export type Offer = { Gold: number, Items: { string }, Stackables: { [string]: number } }

function TradeRules.emptyOffer(): Offer
	return { Gold = 0, Items = {}, Stackables = {} }
end

-- Why `item` (guid `guid`) can't be offered, or nil.
function TradeRules.itemBlock(data: { [string]: any }, guid: string, item: any): string?
	if type(item) ~= "table" then
		return "item"
	elseif item.Locked then
		return "locked"
	elseif type(item.Source) == "string" and string.sub(item.Source, 1, 5) == "Mall:" then
		return "mall"
	end
	for _, worn in data.Equipment or {} do
		if worn == guid then
			return "equipped"
		end
	end
	return nil
end

function TradeRules.stackBlock(id: string): string?
	if ItemDefinitions.stackable(id) == nil then
		return "item"
	elseif TradeRules.MALL_ONLY[id] then
		return "mall"
	end
	return nil
end

--[[
	Checks `offer` against the owner's profile `data`. Returns (ok, reason):
	gold, item, locked, mall, equipped, count, many.
]]
function TradeRules.checkOffer(data: { [string]: any }, offer: Offer): (boolean, string?)
	if offer.Gold % 1 ~= 0 or offer.Gold < 0 or offer.Gold > (data.Wallet.Gold or 0) then
		return false, "gold"
	end
	if #offer.Items > TradeRules.MAX_ITEMS then
		return false, "many"
	end
	local seen = {}
	for _, guid in offer.Items do
		if seen[guid] then
			return false, "item"
		end
		seen[guid] = true
		local block = TradeRules.itemBlock(data, guid, data.Inventory[guid])
		if block then
			return false, block
		end
	end
	local stacks = 0
	for id, count in offer.Stackables do
		stacks += 1
		local block = TradeRules.stackBlock(id)
		if block then
			return false, block
		end
		if count % 1 ~= 0 or count < 1 or count > (data.Stackables[id] or 0) then
			return false, "count"
		end
	end
	if stacks > TradeRules.MAX_STACKS then
		return false, "many"
	end
	return true, nil
end

--[[
	Can `data` take what the other side gives (`incoming`) after giving
	`outgoing`? Returns (ok, reason): bag, full.
]]
function TradeRules.canReceive(data: { [string]: any }, outgoing: Offer, incoming: Offer): (boolean, string?)
	local count = 0
	for _ in data.Inventory do
		count += 1
	end
	if count - #outgoing.Items + #incoming.Items > ItemRules.INVENTORY_CAP then
		return false, "bag"
	end
	for id, n in incoming.Stackables do
		local def = ItemDefinitions.stackable(id)
		local after = (data.Stackables[id] or 0) - (outgoing.Stackables[id] or 0) + n
		if def == nil or after > def.maxStack then
			return false, "full"
		end
	end
	return true, nil
end

-- True if the offer gives nothing.
function TradeRules.isEmpty(offer: Offer): boolean
	return offer.Gold == 0 and #offer.Items == 0 and next(offer.Stackables) == nil
end

return table.freeze(TradeRules)
