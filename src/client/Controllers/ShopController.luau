--!strict
--[[
	ShopController — the Merchant and Exchanger screens (creator request
	2026-10-27, PLAN.md D-117). Opens when the server says the player
	talked to one (NpcOpen). Display and requests only: every price,
	ratio, limit and check is the server's (ShopService); the screen shows
	the catalog it sends and asks again after each action.

	  Merchant   Buy: Healing Potions, and each piece of your class at
	             Standard / Uncommon / Rare (your level, fixed attributes).
	             Sell: tick unused items, then sell them (tap twice).
	  Exchanger  Mall Points -> Gold and Gold -> Mall Points, with the
	             ratios and today's limits shown.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local NpcDefinitions = require(Shared.Definitions.NpcDefinitions)
local ChainQuestDefinitions = require(Shared.Definitions.ChainQuestDefinitions)
local RouletteRules = require(Shared.Logic.RouletteRules)
local NetClient = require(Shared.Net.Client)

local UI = script.Parent.Parent.UI
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)
local Panels = require(UI.Panels)

local ShopController = {}

local BAD = Color3.fromRGB(255, 140, 130)
local RARITY_COLOR = {
	Standard = Color3.fromRGB(200, 200, 200),
	Uncommon = Color3.fromRGB(110, 225, 120),
	Rare = Color3.fromRGB(90, 160, 255),
	Epic = Color3.fromRGB(190, 110, 255),
	Legendary = Color3.fromRGB(255, 165, 50),
	Mythical = Color3.fromRGB(255, 80, 110),
}
local KIND_NAMES = {
	Weapon = "Weapons",
	Shield = "Shield",
	Helm = "Helm",
	Shoulders = "Shoulders",
	Chest = "Chest",
	Hands = "Gloves",
	Legs = "Legs",
	Boots = "Boots",
	Necklace = "Necklace",
	Earrings = "Earrings",
	Ring = "Ring",
}
local REASONS = {
	far = "Walk closer to the NPC.",
	gold = "Not enough Gold.",
	points = "Not enough Mall Points.",
	bag = "Your bag is full.",
	full = "You can't carry more potions.",
	daily = "That goes past today's limit.",
	closed = "Closed for now (admin).",
	locked = "A ticked item is locked.",
	equipped = "A ticked item is equipped.",
	stock = "That item isn't sold.",
	nothing = "Nothing needs repairing.",
	level = "You need a higher level for the trials.",
	cooldown = "The Warden needs time before your next trials.",
	active = "You are already on the trials.",
	notDone = "Finish every trial first.",
	amount = "Enter an amount from 1 to 100,000.",
	RateLimited = "Too many requests; wait a moment.",
}

local panel: Frame? = nil
local content: Frame? = nil
local npc: string? = nil
local page = "Buy"
-- Buy tab: the category, the rarity shown and the chosen item.
local buyCategory = "Potions"
local buyRarity = "Standard"
local selectedPick: string? = nil
-- D-119: the trial shown in detail (nil: the current one).
local chainPick: number? = nil
-- D-120: the wheel: the prize lit up while it spins, and the last win.
local wheelLit: string? = nil
local spinning = false
local lastWin: string? = nil
local listed: any = nil
local picked: { [string]: boolean? } = {}
local confirming: string? = nil
local status, statusBad = "", false
local fields: { [string]: string } = {}

local render: () -> ()

local function close()
	if panel then
		panel:Destroy()
		panel, content, npc = nil, nil, nil
		Panels.closed("shop")
	end
end

local function setStatus(text: string, bad: boolean?)
	status, statusBad = text, bad == true
end

local function call(action: string, args: { [string]: any }): any
	args.Npc = npc
	-- D-119: the Warden has its own remote.
	local result = if npc == "Warden"
		then NetClient.invoke("ChainQuest", action, args.Reward)
		elseif npc == "Fortune" then NetClient.invoke("Roulette", action)
		else NetClient.invoke("NpcShop", action, args)
	if type(result) ~= "table" then
		setStatus("No answer from the server.", true)
		return nil
	end
	if result.ok == false then
		setStatus(REASONS[result.reason] or `Refused ({tostring(result.reason)}).`, true)
		return nil
	end
	listed = result
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

local function row(parent: Instance): Frame
	local frame = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = parent,
	})
	local layout = Kit.list(frame, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Left)
	layout.Wraps = true
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	return frame
end

local function field(parent: Instance, key: string, placeholder: string, width: number): TextBox
	local box = Kit.new("TextBox", {
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
	Kit.corner(box, 8)
	box:GetPropertyChangedSignal("Text"):Connect(function()
		fields[key] = box.Text
	end)
	return box
end

-- Asks twice before spending: the first tap arms the button for 4 s.
local function twice(key: string, action: () -> ()): boolean
	if confirming ~= key then
		confirming = key
		task.delay(4, function()
			if confirming == key then
				confirming = nil
				render()
			end
		end)
		render()
		return false
	end
	confirming = nil
	action()
	return true
end

-- Which pieces each Buy category shows.
local CATEGORIES = {
	{ id = "Potions", label = "🧪 Potions" },
	{ id = "Weapons", label = "🗡️ Weapons", kinds = { Weapon = true } },
	{
		id = "Armor",
		label = "🛡️ Armor",
		kinds = {
			Shield = true,
			Helm = true,
			Shoulders = true,
			Chest = true,
			Hands = true,
			Legs = true,
			Boots = true,
		},
	},
	{
		id = "Accessories",
		label = "💍 Accessories",
		kinds = { Necklace = true, Earrings = true, Ring = true },
	},
}
local CELL_W, CELL_H = 180, 74

-- A grid of equal cards (columns fit the width).
local function grid(parent: Instance, width: number): Frame
	local frame = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = parent,
	})
	local columns = math.max(2, math.floor((width + 8) / (CELL_W + 8)))
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(1 / columns, -8, 0, CELL_H)
	layout.CellPadding = UDim2.fromOffset(8, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame
	return frame
end

-- One card: a name, a second line, a price line; gold ring when chosen.
local function itemCard(
	parent: Instance,
	order: number,
	title: string,
	sub: string,
	price: string,
	color: Color3,
	chosen: boolean,
	affordable: boolean,
	onClick: () -> ()
)
	local b = Kit.new("TextButton", {
		BackgroundColor3 = if chosen then Theme.Colors.GlassRaised else Theme.Colors.Ink,
		BackgroundTransparency = if chosen then 0.05 else 0.35,
		Text = "",
		AutoButtonColor = true,
		LayoutOrder = order,
		Parent = parent,
	})
	Kit.corner(b, 10)
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = if chosen then Theme.Colors.GoldBright else color
	stroke.Thickness = if chosen then 2.5 else 1
	stroke.Transparency = if chosen then 0 else 0.4
	stroke.Parent = b
	local function line(body: string, y: number, size: number, tint: Color3, bold: boolean)
		local l = Kit.new("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(10, y),
			Size = UDim2.new(1, -20, 0, size + 4),
			Text = body,
			TextSize = size,
			FontFace = if bold then Theme.Fonts.BodyBold else Theme.Fonts.Body,
			TextColor3 = tint,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = b,
		})
		return l
	end
	line(title, 6, 14, color, true)
	line(sub, 26, 12, Theme.Colors.TextDim, false)
	line(price, 46, 14, if affordable then Theme.Colors.GoldBright else BAD, true)
	b.Activated:Connect(onClick)
end

local function drawBuy(body: Instance, l: any, width: number): (string, string?, (() -> ())?)
	local gold = l.gold or 0
	local cards = grid(body, width)
	if buyCategory == "Potions" then
		itemCard(
			cards,
			1,
			"🧪 Healing Potion",
			`Restores 30% health · you have {l.potions}`,
			`{l.potionPrice} Gold each`,
			Theme.Colors.Text,
			true,
			gold >= l.potionPrice,
			function() end
		)
		return "🧪 Healing Potion", nil, nil
	end
	local category = nil
	for _, c in CATEGORIES do
		if c.id == buyCategory then
			category = c
		end
	end
	local chosen: any = nil
	local order = 0
	for _, entry in l.stock do
		if entry.Rarity == buyRarity and category and category.kinds and category.kinds[entry.Kind] then
			order += 1
			local isChosen = selectedPick == entry.Pick
			if isChosen then
				chosen = entry
			end
			itemCard(
				cards,
				order,
				entry.Name,
				`{KIND_NAMES[entry.Kind] or entry.Kind}{if entry.Family then ` · {entry.Family}` else ""} · Lv {entry.Level}`,
				`{entry.Price} Gold`,
				RARITY_COLOR[entry.Rarity] or Theme.Colors.Text,
				isChosen,
				gold >= entry.Price,
				function()
					selectedPick = entry.Pick
					confirming = nil
					render()
				end
			)
		end
	end
	if order == 0 then
		text(body, "Nothing in this category for your class.", 13, Theme.Colors.TextDim)
	end
	if chosen == nil then
		return "Tap an item to see its price.", nil, nil
	end
	local pick = chosen.Pick
	return `{chosen.Rarity} {chosen.Name} · Lv {chosen.Level} · {chosen.Price} Gold`,
		if confirming == pick then `Tap to pay {chosen.Price}` else "Buy",
		function()
			twice(pick, function()
				if call("BuyGear", { Pick = pick }) then
					setStatus(`✅ Bought {chosen.Rarity} {chosen.Name}. It's in your bag.`)
				end
			end)
			render()
		end
end

local function drawSell(body: Instance, l: any, width: number): (string, string?, (() -> ())?)
	if #l.offers == 0 then
		text(body, "Nothing to sell. Equipped and locked items are never offered.", 13, Theme.Colors.TextDim)
		return "", nil, nil
	end
	text(
		body,
		"Tap items to tick them (up to 20). Equipped and locked items are never offered.",
		12,
		Theme.Colors.TextDim
	)
	local cards = grid(body, width)
	local total, count, guids = 0, 0, {}
	for order, offer in l.offers do
		local on = picked[offer.Guid] == true
		if on then
			total += offer.Price
			count += 1
			table.insert(guids, offer.Guid)
		end
		itemCard(
			cards,
			order,
			`{if on then "✅ " else ""}{offer.Name}`,
			`{offer.Rarity} · Lv {offer.Level}{if offer.Enhancement > 0
				then ` · +{offer.Enhancement}`
				else ""}`,
			`Sells for {offer.Price} Gold`,
			RARITY_COLOR[offer.Rarity] or Theme.Colors.Text,
			on,
			true,
			function()
				picked[offer.Guid] = if on then nil else true
				confirming = nil
				render()
			end
		)
	end
	if count == 0 then
		return "Nothing ticked yet.", nil, nil
	end
	return `{count} item(s) ticked · {total} Gold`,
		if confirming == "sell" then `Tap to sell for {total}` else "Sell",
		function()
			if count > 20 then
				setStatus("Sell at most 20 at a time.", true)
				render()
				return
			end
			twice("sell", function()
				if call("Sell", { Guids = guids }) then
					picked = {}
					setStatus(`✅ Sold {count} item(s) for {total} Gold.`)
				end
			end)
			render()
		end
end

-- A small balance badge ("💠 120 Mall Points").
local function badge(parent: Instance, body: string, order: number)
	local b = Kit.new("TextLabel", {
		BackgroundColor3 = Theme.Colors.Ink,
		BackgroundTransparency = 0.2,
		Size = UDim2.fromOffset(200, 36),
		Text = body,
		TextSize = 15,
		FontFace = Theme.Fonts.BodyBold,
		TextColor3 = Theme.Colors.GoldBright,
		LayoutOrder = order,
		Parent = parent,
	})
	Kit.corner(b, 18)
end

local function drawExchange(body: Instance, l: any, width: number)
	local balances = row(body)
	balances.LayoutOrder = 1
	badge(balances, `💠 {l.mallPoints} Mall Points`, 1)
	badge(balances, `💰 {l.gold} Gold`, 2)
	if not l.enabled then
		text(body, "The Exchanger is closed for now.", 14, BAD, true).LayoutOrder = 2
		return
	end
	-- Two cards side by side (stacked on narrow screens).
	local cards = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		Parent = body,
	})
	local side = width >= 560
	local layout = Kit.list(
		cards,
		if side then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
		12,
		Enum.HorizontalAlignment.Left
	)
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	local cardW = if side then math.floor((width - 12) / 2) else width

	local function left(cap: number, used: number): number?
		return if cap > 0 then math.max(0, cap - used) else nil
	end
	local sections = {
		{
			direction = "ToGold",
			title = "💠 Mall Points  →  💰 Gold",
			rate = `1 Mall Point = {l.goldPerMallPoint} Gold`,
			left = left(l.dailyToGold, l.usedToGold),
			cap = l.dailyToGold,
			most = l.mallPoints,
			preview = function(n: number): string
				return `You pay {n} MP · you get {n * l.goldPerMallPoint} Gold`
			end,
		},
		{
			direction = "ToMallPoints",
			title = "💰 Gold  →  💠 Mall Points",
			rate = `1 Mall Point costs {l.goldForMallPoint} Gold`,
			left = left(l.dailyToMallPoints, l.usedToMallPoints),
			cap = l.dailyToMallPoints,
			most = l.gold // math.max(1, l.goldForMallPoint),
			preview = function(n: number): string
				return `You pay {n * l.goldForMallPoint} Gold · you get {n} MP`
			end,
		},
	}
	for order, sec in sections do
		local key = `x{sec.direction}`
		local most = sec.most
		if sec.left then
			most = math.min(most, sec.left)
		end
		local card = Kit.new("Frame", {
			BackgroundColor3 = Theme.Colors.GlassRaised,
			BackgroundTransparency = 0.1,
			Size = UDim2.fromOffset(cardW, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = order,
			Parent = cards,
		})
		Kit.corner(card, 12)
		Kit.padding(card, 12, 14)
		local list = Kit.list(card, Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Left)
		list.VerticalAlignment = Enum.VerticalAlignment.Top
		local function line(body2: string, size: number, color: Color3, bold: boolean, n: number)
			text(card, body2, size, color, bold).LayoutOrder = n
		end
		line(sec.title, 16, Theme.Colors.GoldBright, true, 1)
		line(sec.rate, 14, Theme.Colors.Text, true, 2)
		line(
			if sec.left then `Daily limit: {sec.left} of {sec.cap} MP left today` else "No daily limit",
			12,
			Theme.Colors.TextDim,
			false,
			3
		)
		-- Amount: a box and quick picks.
		local amountRow = row(card)
		amountRow.LayoutOrder = 4
		field(amountRow, key, "Mall Points", 110)
		for _, quick in { 1, 10, 50 } do
			button(amountRow, tostring(quick), 44, false, function()
				fields[key] = tostring(quick)
				confirming = nil
				render()
			end)
		end
		button(amountRow, "Max", 56, false, function()
			fields[key] = tostring(math.max(0, most))
			confirming = nil
			render()
		end)
		local amount = math.floor(tonumber(fields[key]) or 0)
		line(
			if amount > 0 then sec.preview(amount) else "Enter how many Mall Points.",
			13,
			if amount > 0 and amount <= most then Theme.Colors.Safe else Theme.Colors.TextDim,
			true,
			5
		)
		local go = button(
			card,
			if confirming == key then "Tap again to confirm" else "Exchange",
			10,
			true,
			function()
				if amount < 1 or amount > 100000 then
					setStatus(REASONS.amount, true)
					render()
					return
				end
				twice(key, function()
					if call("Exchange", { Direction = sec.direction, Count = amount }) then
						fields[key] = ""
						setStatus("✅ Exchanged.")
					end
				end)
				render()
			end
		)
		go.Size = UDim2.new(1, 0, 0, 40)
		go.LayoutOrder = 6
	end
end

-- D-118: the Blacksmith: worn items as cards; tick some or repair all.
local function drawRepair(body: Instance, l: any, width: number): (string, string?, (() -> ())?)
	if #l.repairs == 0 then
		text(body, "✅ All your gear is in perfect shape.", 14, Theme.Colors.Safe, true)
		return "Nothing needs repairing.", nil, nil
	end
	text(
		body,
		"Tap items to tick them, or repair everything at once. Broken gear (0) gives no stats until repaired.",
		12,
		Theme.Colors.TextDim
	)
	local cards = grid(body, width)
	local total, count, guids, all = 0, 0, {}, 0
	for order, entry in l.repairs do
		all += entry.Cost
		local on = picked[entry.Guid] == true
		if on then
			total += entry.Cost
			count += 1
			table.insert(guids, entry.Guid)
		end
		local broken = entry.Durability <= 0
		itemCard(
			cards,
			order,
			`{if on then "✅ " else ""}{entry.Name}`,
			`{if broken then "❗ Broken" else `Durability {math.floor(entry.Durability + 0.5)}/{l.max}`}{if entry.Equipped
				then " · worn"
				else ""}`,
			`Repair: {entry.Cost} Gold`,
			if broken then BAD else (RARITY_COLOR[entry.Rarity] or Theme.Colors.Text),
			on,
			(l.gold or 0) >= entry.Cost,
			function()
				picked[entry.Guid] = if on then nil else true
				confirming = nil
				render()
			end
		)
	end
	if count == 0 then
		return `Repair everything: {all} Gold`,
			if confirming == "repairAll" then `Tap to pay {all}` else "Repair all",
			function()
				twice("repairAll", function()
					if call("RepairAll", {}) then
						picked = {}
						setStatus(`✅ Everything repaired for {all} Gold.`)
					end
				end)
				render()
			end
	end
	return `{count} item(s) ticked · {total} Gold`,
		if confirming == "repair" then `Tap to pay {total}` else "Repair ticked",
		function()
			if count > 20 then
				setStatus("Repair at most 20 ticked items at a time (or use Repair all).", true)
				render()
				return
			end
			twice("repair", function()
				if call("Repair", { Guids = guids }) then
					picked = {}
					setStatus(`✅ Repaired {count} item(s) for {total} Gold.`)
				end
			end)
			render()
		end
end

local function span(seconds: number): string
	local h = seconds // 3600
	local m = (seconds % 3600) // 60
	return if h > 0 then `{h}h {m}m` else `{math.max(1, m)}m`
end

-- D-119: the Warden's trial chain. On top, the chosen trial in detail (what
-- to hunt, where, how to get there); below, all eight to pick from (creator
-- review 2026-10-27: the first version only named the zone).
local function drawChain(body: Instance, l: any): (string, string?, (() -> ())?)
	local steps = ChainQuestDefinitions.Steps
	local current = if l.active and not l.ready then l.step else nil
	local shown = chainPick or current or 1
	local step = steps[shown]
	local done = l.active and shown < l.step
	local isCurrent = shown == current

	local intro = text(
		body,
		`🗝️ {ChainQuestDefinitions.NAME} · {#steps} trials in order · from level {l.minLevel} · Reward: a Legendary gear piece or a 1-day buff (you choose)`,
		12,
		Theme.Colors.TextDim
	)
	intro.LayoutOrder = 1

	-- The detail card.
	local card = Kit.new("Frame", {
		BackgroundColor3 = Theme.Colors.GlassRaised,
		BackgroundTransparency = 0.05,
		Size = UDim2.new(1, -4, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		Parent = body,
	})
	Kit.corner(card, 12)
	Kit.goldStroke(card, 1.5, 0.15)
	Kit.padding(card, 12, 14)
	local list = Kit.list(card, Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Left)
	list.VerticalAlignment = Enum.VerticalAlignment.Top
	local order = 0
	local function line(body2: string, size: number, color: Color3, bold: boolean?)
		order += 1
		text(card, body2, size, color, bold).LayoutOrder = order
	end
	local state = if done then "✅ Done" elseif isCurrent then "▶ Your current trial" else "Upcoming"
	line(
		`Trial {shown} of {#steps} · {state}`,
		12,
		if done then Theme.Colors.Safe else Theme.Colors.GoldBright,
		true
	)
	line(`{step.icon} {step.label}`, 18, Theme.Colors.Text, true)
	if isCurrent then
		order += 1
		local barRow = Kit.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 22),
			LayoutOrder = order,
			Parent = card,
		})
		local back = Kit.new("Frame", {
			Position = UDim2.fromOffset(0, 5),
			Size = UDim2.new(1, -90, 0, 12),
			BackgroundColor3 = Color3.fromRGB(30, 26, 30),
			BorderSizePixel = 0,
			Parent = barRow,
		})
		Kit.corner(back, 6)
		local fill = Kit.new("Frame", {
			Size = UDim2.fromScale(math.clamp(l.progress / step.count, 0, 1), 1),
			BackgroundColor3 = Theme.Colors.Gold,
			BorderSizePixel = 0,
			Parent = back,
		})
		Kit.corner(fill, 6)
		local count = text(barRow, `{l.progress} / {step.count}`, 15, Theme.Colors.GoldBright, true)
		count.AutomaticSize = Enum.AutomaticSize.None
		count.AnchorPoint = Vector2.new(1, 0)
		count.Position = UDim2.fromScale(1, 0)
		count.Size = UDim2.fromOffset(80, 22)
		count.TextXAlignment = Enum.TextXAlignment.Right
	end
	line(`🎯 Hunt: {step.target}  ({step.levels})`, 14, Theme.Colors.Text, true)
	if step.kind == "Collect" then
		line(
			`🎲 Each {step.target} you defeat has a {l.chance}% chance to drop a {step.item}. You need {step.count}.`,
			13,
			Theme.Colors.Text
		)
	end
	line(`📍 Where: {step.where}`, 14, Theme.Colors.Text, true)
	line(`🧭 How to get there: {step.route}`, 13, Theme.Colors.Text)
	if step.tip then
		line(`💡 {step.tip}`, 12, Theme.Colors.TextDim)
	end

	-- All trials, compact; tap one to read it above.
	local heading = text(body, "All trials (tap one to see where to go)", 13, Theme.Colors.GoldBright, true)
	heading.LayoutOrder = 3
	for index, s2 in steps do
		local isDone = l.active and index < l.step
		local isNow = index == current
		local entry = Kit.new("TextButton", {
			BackgroundColor3 = if index == shown then Theme.Colors.GlassRaised else Theme.Colors.Ink,
			BackgroundTransparency = if index == shown then 0.1 else 0.45,
			Size = UDim2.new(1, -4, 0, 34),
			Text = "",
			AutoButtonColor = true,
			LayoutOrder = 3 + index,
			Parent = body,
		})
		Kit.corner(entry, 8)
		if index == shown then
			Kit.goldStroke(entry, 1.5, 0.2)
		end
		local mark = if isDone then "✅" elseif isNow then "▶" else tostring(index)
		local left = text(
			entry,
			`{mark}  {s2.icon} {s2.label}`,
			13,
			if isDone then Theme.Colors.Safe elseif isNow then Theme.Colors.GoldBright else Theme.Colors.Text,
			true
		)
		left.AutomaticSize = Enum.AutomaticSize.None
		left.Position = UDim2.fromOffset(10, 0)
		left.Size = UDim2.new(1, -190, 1, 0)
		left.TextTruncate = Enum.TextTruncate.AtEnd
		left.TextWrapped = false
		local right =
			text(entry, if isNow then `{l.progress} / {s2.count}` else s2.levels, 12, Theme.Colors.TextDim)
		right.AutomaticSize = Enum.AutomaticSize.None
		right.AnchorPoint = Vector2.new(1, 0)
		right.Position = UDim2.new(1, -10, 0, 0)
		right.Size = UDim2.fromOffset(170, 34)
		right.TextXAlignment = Enum.TextXAlignment.Right
		entry.Activated:Connect(function()
			chainPick = index
			render()
		end)
	end

	if l.ready then
		return "🎉 All trials done! Choose your reward:", nil, nil
	elseif l.active then
		return `Trial {l.step} of {#steps}: {steps[l.step].label} ({l.progress}/{steps[l.step].count})`,
			nil,
			nil
	elseif l.canStart then
		return `Ready to begin{if l.cycles > 0 then ` (finished {l.cycles} time(s))` else ""}.`,
			"Begin the trials",
			function()
				if call("Start", {}) then
					chainPick = nil
					setStatus("✅ The trials begin! First: " .. steps[1].label)
				end
				render()
			end
	elseif l.why == "level" then
		return `Reach level {l.minLevel} to take the trials.`, nil, nil
	elseif l.why == "cooldown" then
		return `Next trials in {span(l.cooldown)}.`, nil, nil
	end
	return "The trials are closed for now.", nil, nil
end

-- D-120: the Fortune Wheel: every prize with its chance; the spin lights
-- the prizes in turn and stops on the one the server rolled.
local function drawFortune(body: Instance, l: any, width: number): (string, string?, (() -> ())?)
	local intro = text(
		body,
		`🎡 {l.free > 0 and `You have {l.free} free spin(s) today.` or "No free spins left today."} More spins cost {l.price} Gold each (never Robux or Mall Points). Every prize and its chance:`,
		13,
		Theme.Colors.Text
	)
	intro.LayoutOrder = 1
	local cards = grid(body, width)
	cards.LayoutOrder = 2
	for order, prize in RouletteRules.PRIZES do
		local info = RouletteRules.INFO[prize]
		local lit = wheelLit == prize
		itemCard(
			cards,
			order,
			`{info.icon} {info.name}`,
			if prize == "Attribute"
				then "permanent bonus point"
				elseif prize == "Level" then "+1 level (Lv 30: a consumable)"
				elseif prize == "Consumable" then "potions, stones or a buff"
				elseif prize == "ThankYou" then "better luck next spin"
				else "a piece of your class",
			`{l.weights[prize] or 0}% chance`,
			if prize == "Legendary"
				then RARITY_COLOR.Legendary
				elseif prize == "Rare" then RARITY_COLOR.Rare
				else Theme.Colors.Text,
			lit,
			true,
			function() end
		)
	end
	if lastWin and not spinning then
		local won = text(body, `🎉 You won: {lastWin}`, 18, Theme.Colors.GoldBright, true)
		won.LayoutOrder = 3
	end
	if not l.enabled then
		return "The wheel is closed for now.", nil, nil
	end
	if spinning then
		return "Spinning...", nil, nil
	end
	local free = l.free > 0
	local key = "spin"
	return if free then `Free spins left today: {l.free}` else `Spin price: {l.price} Gold`,
		if free
			then "🎡 Free spin"
			elseif confirming == key then `Tap to pay {l.price}`
			else `🎡 Spin · {l.price} Gold`,
		function()
			local function go()
				local result = call("Spin", {})
				if result == nil then
					render()
					return
				end
				spinning = true
				lastWin = nil
				setStatus("")
				-- Light the prizes in turn, slowing down, then stop on the win.
				task.spawn(function()
					local prizes = RouletteRules.PRIZES
					local stop = table.find(prizes, result.prize) or 1
					local steps = #prizes * 3 + stop
					for i = 1, steps do
						wheelLit = prizes[(i - 1) % #prizes + 1]
						render()
						task.wait(0.04 + (i / steps) ^ 3 * 0.25)
					end
					wheelLit = result.prize
					spinning = false
					lastWin = result.given
					render()
				end)
			end
			if free then
				go()
			else
				twice(key, go)
				render()
			end
		end
end

function render()
	local frame = content
	if frame == nil then
		return
	end
	frame:ClearAllChildren()
	local def = if npc then NpcDefinitions.get(npc) else nil
	local title = Kit.label(
		if def then `{def.icon} {def.id}` else "Shop",
		18,
		Theme.Fonts.Display,
		Theme.Colors.GoldBright
	)
	title.AutomaticSize = Enum.AutomaticSize.None
	title.Position = UDim2.fromOffset(14, 10)
	title.Size = UDim2.new(1, -260, 0, 26)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = frame
	local shut = button(frame, "Close", 80, false, close)
	shut.AnchorPoint = Vector2.new(1, 0)
	shut.Position = UDim2.new(1, -10, 0, 8)
	local l = listed
	if l and l.gold and npc ~= "Exchanger" then
		local wallet = text(frame, `💰 {l.gold} Gold`, 15, Theme.Colors.GoldBright, true)
		wallet.AutomaticSize = Enum.AutomaticSize.None
		wallet.AnchorPoint = Vector2.new(1, 0)
		wallet.Position = UDim2.new(1, -100, 0, 14)
		wallet.Size = UDim2.fromOffset(150, 24)
		wallet.TextXAlignment = Enum.TextXAlignment.Right
	end
	local width = frame.AbsoluteSize.X - 40
	local top = 44
	local function tabRow(
		y: number,
		items: { { id: string, label: string } },
		current: string,
		w: number,
		pickFn: (string) -> ()
	)
		local strip = Kit.new("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(14, y),
			Size = UDim2.new(1, -28, 0, 36),
			Parent = frame,
		})
		Kit.list(strip, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Left)
		for _, item in items do
			button(strip, item.label, w, item.id == current, function()
				pickFn(item.id)
			end)
		end
	end
	if npc == "Merchant" then
		tabRow(
			top,
			{ { id = "Buy", label = "Buy" }, { id = "Sell", label = "Sell" } },
			page,
			110,
			function(id)
				page = id
				confirming = nil
				setStatus("")
				render()
			end
		)
		top += 44
		if page == "Buy" then
			tabRow(top, CATEGORIES :: any, buyCategory, 140, function(id)
				buyCategory = id
				selectedPick = nil
				confirming = nil
				render()
			end)
			top += 42
			if buyCategory ~= "Potions" then
				local rarities = {}
				for _, r in { "Standard", "Uncommon", "Rare" } do
					table.insert(rarities, { id = r, label = r })
				end
				tabRow(top, rarities, buyRarity, 110, function(id)
					buyRarity = id
					selectedPick = nil
					confirming = nil
					render()
				end)
				top += 42
			end
		end
	end
	-- Bottom: the action bar (what is chosen + the button) and the status.
	local bar = Kit.new("Frame", {
		BackgroundColor3 = Theme.Colors.Ink,
		BackgroundTransparency = 0.2,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 10, 1, -34),
		Size = UDim2.new(1, -20, 0, 50),
		Visible = npc ~= "Exchanger",
		Parent = frame,
	})
	Kit.corner(bar, 10)
	local statusLabel = text(frame, status, 13, if statusBad then BAD else Theme.Colors.Safe, true)
	statusLabel.AnchorPoint = Vector2.new(0, 1)
	statusLabel.Position = UDim2.new(0, 14, 1, -8)
	statusLabel.Size = UDim2.new(1, -28, 0, 0)
	local bottom = if npc ~= "Exchanger" then 92 else 36
	local scroll = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, top),
		Size = UDim2.new(1, -20, 1, -top - bottom),
		CanvasSize = UDim2.fromScale(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = frame,
	})
	local scrollList = Kit.list(scroll, Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Left)
	scrollList.VerticalAlignment = Enum.VerticalAlignment.Top
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 4)
	padding.PaddingLeft = UDim.new(0, 4)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = scroll
	if l == nil then
		text(scroll, "Loading...", 13, Theme.Colors.TextDim)
		return
	end
	if npc == "Exchanger" then
		drawExchange(scroll, l, width)
		return
	end
	local summary, actionText, action
	if npc == "Blacksmith" then
		summary, actionText, action = drawRepair(scroll, l, width)
	elseif npc == "Warden" then
		summary, actionText, action = drawChain(scroll, l)
	elseif npc == "Fortune" then
		summary, actionText, action = drawFortune(scroll, l, width)
	elseif page == "Sell" then
		summary, actionText, action = drawSell(scroll, l, width)
	else
		summary, actionText, action = drawBuy(scroll, l, width)
	end
	local info = text(bar, summary, 13, Theme.Colors.Text, true)
	info.AutomaticSize = Enum.AutomaticSize.None
	info.Position = UDim2.fromOffset(12, 0)
	info.Size = UDim2.new(1, -250, 1, 0)
	info.TextTruncate = Enum.TextTruncate.AtEnd
	info.TextWrapped = false
	if npc == "Merchant" and page == "Buy" and buyCategory == "Potions" then
		local buttons = Kit.new("Frame", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.fromOffset(236, 36),
			Parent = bar,
		})
		Kit.list(buttons, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Right)
		for _, count in { 1, 10 } do
			local key = `potion{count}`
			button(
				buttons,
				if confirming == key then `Pay {l.potionPrice * count}` else `Buy ×{count}`,
				115,
				true,
				function()
					twice(key, function()
						if call("BuyPotion", { Count = count }) then
							setStatus(`✅ Bought {count} Healing Potion(s).`)
						end
					end)
					render()
				end
			)
		end
	elseif npc == "Warden" and l.ready then
		local buttons = Kit.new("Frame", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.fromOffset(330, 36),
			Parent = bar,
		})
		Kit.list(buttons, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Right)
		for _, choice in
			{ { id = "Legendary", label = "🔶 Legendary gear" }, { id = "Buff", label = "✨ 1-day buff" } }
		do
			local key = `claim{choice.id}`
			button(
				buttons,
				if confirming == key then "Tap to confirm" else choice.label,
				160,
				true,
				function()
					twice(key, function()
						local result = call("Claim", { Reward = choice.id })
						if result then
							setStatus(`🎉 You received: {result.given or choice.label}`)
						end
					end)
					render()
				end
			)
		end
	elseif actionText and action then
		local go = button(bar, actionText, 200, true, action)
		go.AnchorPoint = Vector2.new(1, 0.5)
		go.Position = UDim2.new(1, -8, 0.5, 0)
	end
end

local function open(id: string)
	close()
	npc = id
	page, listed, picked, confirming = "Buy", nil, {}, nil
	buyCategory, buyRarity, selectedPick = "Potions", "Standard", nil
	chainPick = nil
	wheelLit, spinning, lastWin = nil, false, nil
	setStatus("")
	Panels.opened("shop")
	local layer = Panels.layer()
	local screen = layer.AbsoluteSize
	local w, h = math.min(screen.X - 16, 680), math.min(screen.Y - 16, 620)
	panel = Kit.glassPanel({
		Name = "Shop",
		Active = true,
		Position = UDim2.fromOffset((screen.X - w) / 2, (screen.Y - h) / 2),
		Size = UDim2.fromOffset(w, h),
		Parent = layer,
	})
	local solid = panel :: Frame
	solid.BackgroundTransparency = 0.04
	content = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = panel })
	render()
	task.spawn(function()
		call(if npc == "Warden" or npc == "Fortune" then "Status" else "Catalog", {})
		render()
	end)
end

function ShopController:Start()
	Panels.register("shop", close)
	NetClient.on("NpcOpen", function(payload: any)
		if type(payload) == "table" and NpcDefinitions.get(payload.Npc) then
			open(payload.Npc)
		end
	end)
end

return ShopController
