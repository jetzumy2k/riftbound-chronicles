--!strict
--[[
	TradeController — player trading on screen (creator request 2026-10-27,
	PLAN.md D-121). Display and requests only: every check, the swap and
	the history are the server's (TradeService).

	  - Walk up to another player in a safe zone: a "Trade" prompt invites
	    them. An invite shows a card with Accept / Decline (30 s).
	  - The trade window: the risk warning first ("I understand"), then two
	    columns, You give / They give. Your side: Gold, items from your bag
	    (tap to add / remove), consumables (- / +). Any change unlocks both.
	  - Lock -> when both are locked, the final summary -> Confirm -> a
	    3-second countdown either side can cancel.
	  - Trade history (Bag -> 🤝) lists the last 20 trades, each with
	    Report: it sends the trade id to the staff as evidence.
]]

local Players = game:GetService("Players")
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
local NotificationController = require(script.Parent.NotificationController)

local TradeController = {}

local BAD = Color3.fromRGB(255, 140, 130)
local WARN_BG = Color3.fromRGB(70, 40, 20)
local RARITY_COLOR = {
	Standard = Color3.fromRGB(200, 200, 200),
	Uncommon = Color3.fromRGB(110, 225, 120),
	Rare = Color3.fromRGB(90, 160, 255),
	Epic = Color3.fromRGB(190, 110, 255),
	Legendary = Color3.fromRGB(255, 165, 50),
	Mythical = Color3.fromRGB(255, 80, 110),
}
-- Mirrors TradeRules.MALL_ONLY (display only; the server decides).
local MALL_ONLY = {
	RebirthScroll = true,
	RelearnScroll = true,
	RaceRune = true,
	GreaterHealingPotion = true,
	MajorHealingPotion = true,
	SupremeHealingPotion = true,
}
local REASONS = {
	closed = "Trading is off for now.",
	realm = "You can only trade with your own realm.",
	level = "Both players need a higher level to trade.",
	safeZone = "Both players must be inside a safe zone.",
	far = "Stand closer to each other.",
	combat = "Leave combat first.",
	busy = "One of you is already trading.",
	expired = "That invite expired.",
	gold = "You don't have that much Gold.",
	locked = "Locked items can't be traded (unlock them in your bag).",
	mall = "Item Mall items can't be traded.",
	equipped = "Take the item off first.",
	count = "You don't have that many.",
	many = "Too many things in one trade.",
	ack = "Accept the risk warning first.",
	notLocked = "Both players must lock first.",
	bag = "Not enough bag space.",
	full = "One of you can't carry that many.",
	empty = "Nothing is being traded.",
	unknownTrade = "That trade isn't in your history.",
	left = "The other player left.",
	cancelled = "The trade was cancelled.",
	done = "Trade complete.",
	RateLimited = "Too fast; wait a moment.",
	BadArgs = "That request was not accepted.",
	BadState = "Wait until your character has loaded.",
	HandlerError = "Something went wrong on the server; try again.",
}

local panel: Frame? = nil
local content: Frame? = nil
local view: any = nil
local status, statusBad = "", false
local inviteCard: Frame? = nil
local historyMode = false
local history: { any }? = nil
local reportArmed: string? = nil
local goldText = ""

local render: () -> ()

local function setStatus(text: string, bad: boolean?)
	status, statusBad = text, bad == true
end

local function call(action: string, args: { [string]: any }?): any
	local result = NetClient.invoke("Trade", action, args or {})
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

local function column(parent: Instance, x: number, width: number, top: number, bottom: number): ScrollingFrame
	local scroll = Kit.new("ScrollingFrame", {
		BackgroundColor3 = Theme.Colors.Ink,
		BackgroundTransparency = 0.35,
		Position = UDim2.new(x, if x > 0 then 5 else 10, 0, top),
		Size = UDim2.new(width, -15, 1, -top - bottom),
		CanvasSize = UDim2.fromScale(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = parent,
	})
	Kit.corner(scroll, 10)
	local list = Kit.list(scroll, Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Left)
	list.VerticalAlignment = Enum.VerticalAlignment.Top
	Kit.padding(scroll, 8, 10)
	return scroll
end

-- One line for an item (name, rarity, level, enhancement), coloured by rarity.
local function itemLine(item: any): string
	local def = ItemDefinitions.get(item.DefId)
	return `{if def then def.glyph else "?"} {if def then def.name else item.DefId} · {item.Rarity} · Lv {item.ItemLevel}{if (
			item.Enhancement or 0
		) > 0
		then ` · +{item.Enhancement}`
		else ""}`
end

-- The player's current offer (as the server last sent it).
local function myOffer(): { GoldOffered: number, Items: { string }, Stackables: { [string]: number } }
	local mine = view and view.Mine
	local items = {}
	for _, item in (mine and mine.Items) or {} do
		table.insert(items, item.Guid)
	end
	return {
		GoldOffered = (mine and mine.Gold) or 0,
		Items = items,
		Stackables = table.clone((mine and mine.Stackables) or {}),
	}
end

local function sendOffer(offer: any)
	if call("Offer", offer) then
		setStatus("Offer changed: both players must lock again.")
	end
	render()
end

local function drawTheirs(parent: Instance)
	local theirs = view.Theirs or { Gold = 0, Items = {}, Stackables = {} }
	text(
		parent,
		`They give{if view.ThemLocked then "  ·  🔒 locked" else ""}`,
		15,
		Theme.Colors.GoldBright,
		true
	)
	if theirs.Gold > 0 then
		text(parent, `💰 {theirs.Gold} Gold`, 14, Theme.Colors.GoldBright, true)
	end
	for _, item in theirs.Items do
		text(parent, itemLine(item), 13, RARITY_COLOR[item.Rarity], true)
	end
	for id, n in theirs.Stackables do
		local def = ItemDefinitions.stackable(id)
		text(parent, `{if def then def.glyph else ""} {n} × {if def then def.name else id}`, 13)
	end
	if theirs.Gold == 0 and #theirs.Items == 0 and next(theirs.Stackables) == nil then
		text(parent, "Nothing yet.", 13, Theme.Colors.TextDim)
	end
end

local function drawMine(parent: Instance)
	local offer = myOffer()
	local state = PlayerDataController:Get()
	text(
		parent,
		`You give{if view.MeLocked then "  ·  🔒 locked" else ""}`,
		15,
		Theme.Colors.GoldBright,
		true
	)
	-- Gold.
	local goldRow = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 36),
		Parent = parent,
	})
	Kit.list(goldRow, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Left)
	local box = Kit.new("TextBox", {
		Size = UDim2.fromOffset(110, 36),
		BackgroundColor3 = Theme.Colors.Ink,
		BackgroundTransparency = 0.1,
		PlaceholderText = "Gold",
		PlaceholderColor3 = Theme.Colors.TextMuted,
		Text = if goldText ~= "" then goldText else tostring(offer.GoldOffered),
		TextSize = 14,
		FontFace = Theme.Fonts.Body,
		TextColor3 = Theme.Colors.Text,
		ClearTextOnFocus = false,
		Parent = goldRow,
	})
	Kit.corner(box, 8)
	box:GetPropertyChangedSignal("Text"):Connect(function()
		goldText = box.Text
	end)
	button(goldRow, "Set Gold", 90, false, function()
		local n = math.floor(tonumber(goldText) or -1)
		if n < 0 then
			setStatus("Enter a Gold amount.", true)
			render()
			return
		end
		offer.GoldOffered = n
		goldText = ""
		sendOffer(offer)
	end)
	text(goldRow, `of {state.Wallet.Gold}`, 12, Theme.Colors.TextDim).Size = UDim2.fromOffset(110, 36)

	-- Items: what is offered first, then the bag to add from.
	text(parent, "Items (tap to add or remove, up to 8)", 12, Theme.Colors.TextDim)
	local offered: { [string]: boolean } = {}
	for _, guid in offer.Items do
		offered[guid] = true
	end
	local worn: { [string]: boolean } = {}
	for _, guid in state.Equipment do
		worn[guid] = true
	end
	local any = false
	for guid, item in state.Inventory do
		if not worn[guid] and not (item :: any).Locked then
			any = true
			local on = offered[guid] == true
			local b = button(parent, `{if on then "✅" else "➕"}  {itemLine(item)}`, 10, false, function()
				if on then
					local index = table.find(offer.Items, guid)
					if index then
						table.remove(offer.Items, index)
					end
				else
					table.insert(offer.Items, guid)
				end
				sendOffer(offer)
			end)
			b.Size = UDim2.new(1, -4, 0, 32)
			b.TextXAlignment = Enum.TextXAlignment.Left
			b.TextColor3 = RARITY_COLOR[item.Rarity] or Theme.Colors.Text
			b.BackgroundTransparency = if on then 0.05 else 0.5
			Kit.padding(b, 0, 8)
		end
	end
	if not any then
		text(parent, "No tradeable items (equipped and locked items are left out).", 12, Theme.Colors.TextDim)
	end
	-- Consumables.
	text(parent, "Consumables (− / +)", 12, Theme.Colors.TextDim)
	for _, id in ItemDefinitions.STACKABLE_ORDER do
		local have = state.Stackables[id] or 0
		if have > 0 and not MALL_ONLY[id] and string.sub(id, 1, 5) ~= "Buff_" then
			local def = ItemDefinitions.stackable(id)
			local n = offer.Stackables[id] or 0
			local line = Kit.new("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 32),
				Parent = parent,
			})
			Kit.list(line, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Left)
			text(line, `{if def then def.glyph else ""} {if def then def.name else id}`, 13).Size =
				UDim2.new(1, -170, 0, 32)
			button(line, "−", 36, false, function()
				(offer.Stackables :: any)[id] = if n > 1 then n - 1 else nil
				sendOffer(offer)
			end)
			text(line, `{n}/{have}`, 13, Theme.Colors.GoldBright, true).Size = UDim2.fromOffset(56, 32)
			button(line, "+", 36, false, function()
				if n < have then
					offer.Stackables[id] = n + 1
					sendOffer(offer)
				end
			end)
		end
	end
end

local function summaryOf(side: any): string
	if side == nil then
		return "nothing"
	end
	local parts = {}
	if side.Gold > 0 then
		table.insert(parts, `{side.Gold} Gold`)
	end
	for _, item in side.Items do
		local def = ItemDefinitions.get(item.DefId)
		table.insert(parts, `{item.Rarity} {if def then def.name else item.DefId}`)
	end
	for id, n in side.Stackables do
		local def = ItemDefinitions.stackable(id)
		table.insert(parts, `{n} {if def then def.name else id}`)
	end
	return if #parts == 0 then "nothing" else table.concat(parts, ", ")
end

local function drawHistory(frame: Frame)
	local scroll = column(frame, 0, 1, 50, 40)
	if history == nil then
		text(scroll, "Loading...", 13, Theme.Colors.TextDim)
		return
	end
	if #history == 0 then
		text(scroll, "No trades yet.", 13, Theme.Colors.TextDim)
		return
	end
	text(
		scroll,
		"If someone scammed you, tap Report on that trade: the staff get the trade id and both sides as evidence.",
		12,
		Theme.Colors.TextDim
	)
	for _, e in history do
		local card = Kit.new("Frame", {
			BackgroundColor3 = Theme.Colors.GlassRaised,
			BackgroundTransparency = 0.1,
			Size = UDim2.new(1, -4, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = scroll,
		})
		Kit.corner(card, 10)
		Kit.padding(card, 8, 10)
		Kit.list(card, Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Left).VerticalAlignment =
			Enum.VerticalAlignment.Top
		text(
			card,
			`🤝 With {e.WithName} · {os.date("%Y-%m-%d %H:%M", e.At)}`,
			14,
			Theme.Colors.GoldBright,
			true
		)
		text(card, `You gave: {e.Gave}`, 13)
		text(card, `You got: {e.Got}`, 13)
		text(card, `Trade id: {e.Id}`, 11, Theme.Colors.TextDim)
		local armed = reportArmed == e.Id
		button(card, if armed then "Tap again to report" else "❗ Report this trade", 180, armed, function()
			if not armed then
				reportArmed = e.Id
				render()
				return
			end
			reportArmed = nil
			if call("Report", { TradeId = e.Id }) then
				setStatus("✅ Reported. The staff can see this trade.")
			end
			render()
		end)
	end
end

function render()
	local frame = content
	if frame == nil then
		return
	end
	frame:ClearAllChildren()
	local title = Kit.label(
		if historyMode
			then "🤝 Trade history"
			else `🤝 Trade with {view and view.Partner and view.Partner.Name or "?"}`,
		18,
		Theme.Fonts.Display,
		Theme.Colors.GoldBright
	)
	title.AutomaticSize = Enum.AutomaticSize.None
	title.Position = UDim2.fromOffset(14, 10)
	title.Size = UDim2.new(1, -130, 0, 26)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = frame
	local shut = button(frame, if historyMode then "Close" else "Cancel trade", 110, false, function()
		if historyMode then
			TradeController.close()
		else
			call("Cancel")
		end
	end)
	shut.AnchorPoint = Vector2.new(1, 0)
	shut.Position = UDim2.new(1, -10, 0, 8)
	local statusLabel = text(frame, status, 13, if statusBad then BAD else Theme.Colors.Safe, true)
	statusLabel.AnchorPoint = Vector2.new(0, 1)
	statusLabel.Position = UDim2.new(0, 14, 1, -8)
	statusLabel.Size = UDim2.new(1, -28, 0, 0)
	if historyMode then
		drawHistory(frame)
		return
	end
	if view == nil then
		return
	end
	local top = 48
	-- The risk warning (must be accepted before locking).
	if not view.MeAck then
		local warn = Kit.new("Frame", {
			BackgroundColor3 = WARN_BG,
			BackgroundTransparency = 0.05,
			Position = UDim2.fromOffset(10, top),
			Size = UDim2.new(1, -20, 0, 62),
			Parent = frame,
		})
		Kit.corner(warn, 10)
		local w = text(
			warn,
			"❗ Trades are at your own risk. Only trade with people you trust, and check every item before you confirm. If you are scammed, report it from your trade history (Bag → 🤝).",
			12,
			Color3.fromRGB(255, 220, 170),
			true
		)
		w.Position = UDim2.fromOffset(10, 6)
		w.Size = UDim2.new(1, -150, 0, 0)
		local ok = button(warn, "I understand", 120, true, function()
			call("Ack")
		end)
		ok.AnchorPoint = Vector2.new(1, 0.5)
		ok.Position = UDim2.new(1, -10, 0.5, 0)
		top += 70
	end
	local bottom = 96
	drawMine(column(frame, 0, 0.5, top, bottom))
	drawTheirs(column(frame, 0.5, 0.5, top, bottom))
	-- The action bar: lock / final check / countdown.
	local bar = Kit.new("Frame", {
		BackgroundColor3 = Theme.Colors.Ink,
		BackgroundTransparency = 0.15,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 10, 1, -34),
		Size = UDim2.new(1, -20, 0, 54),
		Parent = frame,
	})
	Kit.corner(bar, 10)
	local info = text(bar, "", 13, Theme.Colors.Text, true)
	info.AutomaticSize = Enum.AutomaticSize.None
	info.Position = UDim2.fromOffset(12, 0)
	info.Size = UDim2.new(1, -250, 1, 0)
	local function action(label: string, gold: boolean, f: () -> ())
		local b = button(bar, label, 200, gold, f)
		b.AnchorPoint = Vector2.new(1, 0.5)
		b.Position = UDim2.new(1, -8, 0.5, 0)
	end
	if view.CountdownIn then
		info.Text = `Trading in {view.CountdownIn}... (cancel to stop)`
		action("Stop", false, function()
			call("Unlock")
		end)
	elseif view.MeLocked and view.ThemLocked then
		info.Text = `Final check · you give: {summaryOf(view.Mine)} · you get: {summaryOf(view.Theirs)}`
		info.TextWrapped = true
		if view.MeConfirmed then
			info.Text ..= "  (waiting for them to confirm)"
			action("Unlock", false, function()
				call("Unlock")
			end)
		else
			action("✅ Confirm trade", true, function()
				call("Confirm")
			end)
		end
	elseif view.MeLocked then
		info.Text = "🔒 You locked your offer. Waiting for them to lock..."
		action("Unlock", false, function()
			call("Unlock")
		end)
	else
		info.Text = "Set what you give, then lock it. Any change unlocks both sides."
		action("🔒 Lock my offer", true, function()
			call("Lock")
		end)
	end
end

local function openPanel()
	if panel then
		return
	end
	InventoryController.setOpen(false)
	Panels.opened("trade")
	local layer = Panels.layer()
	local screen = layer.AbsoluteSize
	local w, h = math.min(screen.X - 16, 860), math.min(screen.Y - 16, 620)
	local frame = Kit.glassPanel({
		Name = "Trade",
		Active = true,
		Position = UDim2.fromOffset((screen.X - w) / 2, (screen.Y - h) / 2),
		Size = UDim2.fromOffset(w, h),
		Parent = layer,
	})
	frame.BackgroundTransparency = 0.04
	panel = frame
	content = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = frame })
end

function TradeController.close()
	if panel then
		panel:Destroy()
		panel, content = nil, nil
		Panels.closed("trade")
	end
	if view and view.Open and not historyMode then
		call("Cancel")
	end
	historyMode = false
end

function TradeController.openHistory()
	historyMode, history, reportArmed = true, nil, nil
	setStatus("")
	openPanel()
	render()
	task.spawn(function()
		local result = call("History")
		history = if result then result.history else {}
		render()
	end)
end

local function showInvite(payload: any)
	if inviteCard then
		inviteCard:Destroy()
	end
	local layer = Panels.layer()
	local card = Kit.glassPanel({
		Name = "TradeInvite",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -170),
		Size = UDim2.fromOffset(340, 96),
		Parent = layer,
	})
	inviteCard = card
	local t = text(card, `🤝 {payload.Name} wants to trade with you.`, 15, Theme.Colors.GoldBright, true)
	t.Position = UDim2.fromOffset(14, 10)
	t.Size = UDim2.new(1, -28, 0, 0)
	local row = Kit.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.fromOffset(250, 36),
		Parent = card,
	})
	Kit.list(row, Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center)
	local function done()
		if inviteCard == card then
			card:Destroy()
			inviteCard = nil
		end
	end
	button(row, "Accept", 110, true, function()
		done()
		call("Accept", { UserId = payload.UserId })
	end)
	button(row, "Decline", 110, false, function()
		done()
		call("Decline", { UserId = payload.UserId })
	end)
	task.delay(30, done)
end

-- A "Trade" prompt on every other player's character (local only).
local function addPrompt(player: Player, character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if root == nil or not root:IsA("BasePart") then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "RC_TradePrompt"
	prompt.ActionText = "Trade"
	prompt.ObjectText = player.DisplayName
	prompt.MaxActivationDistance = 10
	prompt.HoldDuration = 0.4
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.T
	prompt.Parent = root
	prompt.Triggered:Connect(function()
		if call("Invite", { UserId = player.UserId }) then
			NotificationController:ShowKey("Info", "trade.invited", { name = player.DisplayName })
		elseif status ~= "" then
			NotificationController:ShowKey("Warning", "trade.refused", { reason = status })
		end
	end)
end

local function watch(player: Player)
	if player == Players.LocalPlayer then
		return
	end
	player.CharacterAdded:Connect(function(character)
		addPrompt(player, character)
	end)
	if player.Character then
		task.spawn(addPrompt, player, player.Character)
	end
end

function TradeController:Start()
	Panels.register("trade", TradeController.close)
	InventoryController.OpenTrades = TradeController.openHistory
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	NetClient.on("TradeInvite", showInvite)
	NetClient.on("TradeUpdate", function(payload: any)
		if type(payload) ~= "table" then
			return
		end
		if not payload.Open then
			local wasOpen = view ~= nil
			view = nil
			if wasOpen and not historyMode and panel then
				panel:Destroy()
				panel, content = nil, nil
				Panels.closed("trade")
			end
			if payload.Reason and payload.Reason ~= "done" then
				setStatus(REASONS[payload.Reason] or "The trade ended.", true)
			end
			return
		end
		view = payload
		historyMode = false
		openPanel()
		render()
		-- Count the countdown down on screen (the server swaps at 0).
		if payload.CountdownIn then
			task.spawn(function()
				for _ = 1, payload.CountdownIn do
					task.wait(1)
					if view ~= payload then
						return
					end
					payload.CountdownIn = math.max(0, payload.CountdownIn - 1)
					render()
				end
			end)
		end
	end)
end

return TradeController
