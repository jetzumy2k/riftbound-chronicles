--!strict
--[[
	MallController — the Item Mall and the buff chip (creator request
	2026-10-25, PLAN.md D-93; layout reworked after the creator's review:
	"not user-friendly, no back button"). Display only: every purchase is a
	request the server checks (BuyMallItem; Robux packs through Roblox's own
	purchase window, granted by MallService.ProcessReceipt).

	  Header   "← Bag" (back to the bag), the title, the Mall Point balance
	           with "Get MP" (opens the Mall Points tab) and Close
	  Tabs     🧪 Buffs, 💎 Stones, 🔶 Gear sets, 💠 Get Mall Points
	  Cards    each tab lists its items as cards under headings (Boosts,
	           Combat draughts; Utility: scrolls, the rune, potions): icon, name, price (red when
	           you can't afford it)
	  Details  tapping a card shows everything about it beside the cards (or,
	           on a narrow screen, in place of them with "← Back to list"):
	           the description, how many you have, a running buff's time
	           left, a set's pieces with their fixed attributes, and Buy
	           (then "Tap again to confirm" for a few seconds)
	  Buffs    while any buff runs, a row of badges under the event chip:
	           each shows the buff's icon, a short label (EXP, DROP, STONE,
	           ATK, DEF, HP, FOCUS) and the minutes left; hover or tap one
	           for its name, effect and time (UI/Tooltip). More buffs than
	           fit end in a "+2" badge listing the rest

	Opened from the 🛒 Mall button in the bag (or key N).
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MallDefinitions = require(Shared.Definitions.MallDefinitions)
local Constants = require(Shared.Constants)
local BuffRules = require(Shared.Logic.BuffRules)
local ItemRules = require(Shared.Logic.ItemRules)
local MallGear = require(Shared.Logic.MallGear)
local OverlayLayout = require(Shared.Layout.OverlayLayout)
local MallLayout = require(Shared.Layout.MallLayout)
local NetClient = require(Shared.Net.Client)

local UI = script.Parent.Parent.UI
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)
local Panels = require(UI.Panels)

local Tooltip = require(UI.Tooltip)

local PlayerDataController = require(script.Parent.PlayerDataController)
local InventoryController = require(script.Parent.InventoryController)

local MallController = {}

local GOLD_TEXT = Color3.fromRGB(30, 20, 8)
local TOO_DEAR = Color3.fromRGB(255, 140, 130)
local CONFIRM_SECONDS = 4
local REASONS = {
	points = "Not enough Mall Points. Get more in the 💠 tab.",
	full = "You can't carry more of that.",
	bag = "Not enough room in your bag for every piece of the set.",
	unknown = "That item isn't available.",
	RateLimited = "Too many requests at once; wait a moment.",
}

-- An item on a card: a catalog entry or a Robux pack.
type Choice = { entry: MallDefinitions.Entry?, pack: MallDefinitions.Pack? }

local panel: Frame? = nil
local tab = "Buffs"
local selected: { [string]: string } = {}
local detailOnly = false
local confirming: string? = nil
local confirmUntil = 0
local status = ""
local statusBad = false
-- The buff badges' row (placed by OverlayLayout) and how wide it may be.
local badgeRow: Frame? = nil
local badgeWidth = 200
-- Reward buffs ring green, combat buffs red-orange.
local REWARD_RING = Color3.fromRGB(120, 220, 140)
local COMBAT_RING = Color3.fromRGB(255, 150, 110)
local REWARD_CATEGORIES = { XP = true, DropChance = true, StoneChance = true }

local function state()
	return PlayerDataController:Get()
end

-- D-109: the admin can change prices; the server mirrors them.
local function priceOf(entry: MallDefinitions.Entry): number
	local price = ReplicatedStorage:GetAttribute(Constants.Attributes.MallPricePrefix .. entry.id)
	return if type(price) == "number" then price else entry.price
end

local function points(): number
	return (state().Wallet :: any).MallPoints or 0
end

local function setStatus(message: string, bad: boolean?)
	status = message
	statusBad = bad == true
end

local function owned(entry: MallDefinitions.Entry): number?
	local grant = entry.grant
	if grant.kind ~= "Stackable" then
		return nil
	end
	return state().Stackables[grant.id] or 0
end

-- Minutes left on the buff an entry starts (nil when none is running).
local function buffLeft(entry: MallDefinitions.Entry): number?
	local buff = BuffRules.get(entry.id)
	local untilAt = buff and state().BuffsUntil[buff.id]
	if untilAt and untilAt > os.clock() then
		return math.ceil((untilAt - os.clock()) / 60)
	end
	return nil
end

-- D-124: the buyer's choice for the gear entry shown (level tier, weapon
-- type, accessory piece), kept while the same entry stays selected.
local gearChoice: MallGear.Choice = {}
local gearChoiceFor: string? = nil

-- The pieces a gear entry gives with `choice`, and their fixed attributes.
local function gearPreview(kind: string, rarity: string, choice: MallGear.Choice): ({ string }, string?)
	local s = state()
	local job, race = s.Job, s.Race
	if job == nil then
		return {}, nil
	end
	local level = choice.Bracket or MallGear.defaultBracket(s.Level)
	local pieces, why = MallGear.pieces(job, race, kind, level, choice)
	if pieces == nil then
		return {}, why
	end
	local lines = {}
	for _, piece in pieces do
		local parts = {}
		for _, attribute in ItemRules.fixedRoll(piece.def, rarity, piece.itemLevel) do
			local spec = ItemRules.STATS[attribute.Stat]
			table.insert(parts, `{spec.name} {attribute.Value}{if spec.percent then "%" else ""}`)
		end
		table.insert(lines, `{piece.def.name} (requires Lv {piece.itemLevel}): {table.concat(parts, ", ")}`)
	end
	return lines, nil
end

local function choicesFor(name: string): { { title: string, items: { Choice } } }
	if name == "Points" then
		local items = {}
		for _, pack in MallDefinitions.PACKS do
			table.insert(items, { pack = pack })
		end
		return { { title = "Mall Point packs (Robux)", items = items } }
	end
	local out = {}
	for _, section in (MallDefinitions.SECTIONS :: any)[name] or {} do
		local items = {}
		for _, entry in MallDefinitions.CATALOG do
			if entry.tab == name and entry.section == section then
				table.insert(items, { entry = entry })
			end
		end
		table.insert(out, { title = section, items = items })
	end
	return out
end

local function keyOf(choice: Choice): string
	return if choice.entry then choice.entry.id else (choice.pack :: MallDefinitions.Pack).id
end

local function close()
	if panel then
		panel:Destroy()
		panel = nil
		Panels.closed("mall")
	end
end

local render: () -> ()

local function buy(entry: MallDefinitions.Entry)
	local now = os.clock()
	if confirming ~= entry.id or now > confirmUntil then
		confirming = entry.id
		confirmUntil = now + CONFIRM_SECONDS
		render()
		task.delay(CONFIRM_SECONDS + 0.1, function()
			if confirming == entry.id and os.clock() > confirmUntil then
				confirming = nil
				render()
			end
		end)
		return
	end
	confirming = nil
	local result = NetClient.invoke(
		"BuyMallItem",
		entry.id,
		if MallGear.KINDS[entry.grant.kind] then gearChoice else nil
	)
	if type(result) ~= "table" then
		setStatus("❌ No answer from the server.", true)
	elseif result.ok then
		setStatus(`✅ Bought {entry.name}. It's in your bag.`)
	else
		local reason = tostring(result.reason or result.code)
		setStatus(`❌ {REASONS[reason] or reason}`, true)
	end
	render()
end

local function buyPack(pack: MallDefinitions.Pack)
	if pack.productId == 0 then
		setStatus("❌ Mall Point packs aren't on sale yet.", true)
		render()
		return
	end
	MarketplaceService:PromptProductPurchase(Players.LocalPlayer :: Player, pack.productId)
end

local function button(
	parent: Instance,
	label: string,
	width: number,
	gold: boolean,
	onClick: () -> ()
): TextButton
	local b = Kit.new("TextButton", {
		Size = UDim2.fromOffset(width, 44),
		BackgroundColor3 = if gold then Theme.Colors.Gold else Theme.Colors.GlassHighlight,
		BackgroundTransparency = if gold then 0.05 else 0.35,
		Text = label,
		TextSize = 13,
		FontFace = Theme.Fonts.BodyBold,
		TextColor3 = if gold then GOLD_TEXT else Theme.Colors.Text,
		TextWrapped = true,
		AutoButtonColor = true,
		Parent = parent,
	})
	Kit.corner(b, 8)
	b.Activated:Connect(onClick)
	return b
end

local function text(parent: Instance, content: string, size: number, color: Color3, bold: boolean?): TextLabel
	local l = Kit.label(content, size, if bold then Theme.Fonts.BodyBold else Theme.Fonts.Body, color)
	l.Size = UDim2.new(1, -8, 0, 0)
	l.AutomaticSize = Enum.AutomaticSize.Y
	l.TextWrapped = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = parent
	return l
end

-- One card in the grid.
local function card(parent: Instance, choice: Choice, isSelected: boolean)
	local entry, pack = choice.entry, choice.pack
	local b = Kit.new("TextButton", {
		BackgroundColor3 = Theme.Colors.Ink,
		BackgroundTransparency = if isSelected then 0.15 else 0.45,
		Text = "",
		AutoButtonColor = true,
		Parent = parent,
	})
	Kit.corner(b, 10)
	local stroke = Instance.new("UIStroke")
	stroke.Color = if isSelected then Theme.Colors.GoldBright else Theme.Colors.Gold
	stroke.Transparency = if isSelected then 0 else 0.7
	stroke.Thickness = if isSelected then 2 else 1
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = b
	local icon = Kit.label(if entry then entry.icon else "💠", 26, Theme.Fonts.BodyBold, Theme.Colors.Text)
	icon.Position = UDim2.fromOffset(8, 6)
	icon.Parent = b
	local name = Kit.label(
		if entry then entry.name else `{MallDefinitions.pointsOf(pack :: any)} MP`,
		13,
		Theme.Fonts.BodyBold,
		Theme.Colors.GoldBright
	)
	name.AutomaticSize = Enum.AutomaticSize.None
	name.Position = UDim2.fromOffset(8, 36)
	name.Size = UDim2.new(1, -16, 0, 18)
	name.TextWrapped = false
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextYAlignment = Enum.TextYAlignment.Top
	name.Parent = b
	-- What it does in a few words (creator review 2026-10-26: the icon
	-- alone didn't say), and the full story on hover / tap.
	local short = Kit.label(
		if entry
			then entry.short
			else (if (pack :: any).bonusPct > 0
				then `incl. +{(pack :: any).bonusPct}% bonus`
				else "Mall Points"),
		12,
		Theme.Fonts.Body,
		Theme.Colors.Text
	)
	short.AutomaticSize = Enum.AutomaticSize.None
	short.Position = UDim2.fromOffset(8, 55)
	short.Size = UDim2.new(1, -16, 1, -80)
	short.TextWrapped = true
	short.TextTruncate = Enum.TextTruncate.AtEnd
	short.TextXAlignment = Enum.TextXAlignment.Left
	short.TextYAlignment = Enum.TextYAlignment.Top
	short.Parent = b
	Tooltip.attach(b, function()
		if entry then
			local have = owned(entry)
			return `{entry.icon} {entry.name}`,
				`{entry.description}\nPrice: {priceOf(entry)} MP{if have then `  ·  You have {have}` else ""}`
		end
		local pk = pack :: any
		return `💠 {MallDefinitions.pointsOf(pk)} Mall Points`,
			if pk.productId == 0
				then "Not on sale yet."
				else `{pk.robux} Robux through Roblox's purchase window.`
	end)
	local affordable = entry == nil or points() >= priceOf(entry)
	local price = Kit.label(
		if entry
			then `{priceOf(entry)} MP`
			else (if (pack :: any).productId == 0
				then "Not on sale yet"
				else `{(pack :: any).robux} Robux`),
		12,
		Theme.Fonts.BodyBold,
		if affordable then Theme.Colors.Safe else TOO_DEAR
	)
	price.AnchorPoint = Vector2.new(0, 1)
	price.Position = UDim2.new(0, 8, 1, -6)
	price.Parent = b
	if pack and pack.bonusPct > 0 then
		local bonus = Kit.label(`+{pack.bonusPct}%`, 12, Theme.Fonts.BodyBold, Theme.Colors.Safe)
		bonus.AnchorPoint = Vector2.new(1, 0)
		bonus.Position = UDim2.new(1, -8, 0, 8)
		bonus.Parent = b
	end
	b.Activated:Connect(function()
		selected[tab] = keyOf(choice)
		confirming = nil
		detailOnly = true
		render()
	end)
end

-- Everything about the selected item, and how to get it.
local function detail(parent: Instance, choice: Choice)
	local entry, pack = choice.entry, choice.pack
	if pack then
		local total = MallDefinitions.pointsOf(pack)
		text(parent, `💠 {total} Mall Points`, 18, Theme.Colors.GoldBright, true)
		text(
			parent,
			if pack.bonusPct > 0
				then `{pack.points} points + {pack.bonusPct}% bonus. Paid in Robux through Roblox's purchase window.`
				else "Paid in Robux through Roblox's purchase window.",
			12,
			Theme.Colors.TextDim
		)
		text(
			parent,
			"Spend Mall Points on buffs, stones and gear sets in the other tabs.",
			12,
			Theme.Colors.TextDim
		)
		button(
			parent,
			if pack.productId == 0 then "Not on sale yet" else `Buy for {pack.robux} Robux`,
			220,
			pack.productId ~= 0,
			function()
				buyPack(pack)
			end
		)
		return
	end
	local e = entry :: MallDefinitions.Entry
	text(parent, `{e.icon} {e.name}`, 18, Theme.Colors.GoldBright, true)
	text(parent, e.description, 13, Theme.Colors.Text)
	local have = owned(e)
	if have then
		text(parent, `You have: {have}`, 12, Theme.Colors.TextDim, true)
	end
	local left = buffLeft(e)
	if left then
		text(
			parent,
			`Running now: {left} min left (another adds its time, up to 6 h).`,
			12,
			Theme.Colors.Safe,
			true
		)
	end
	if e.grant.kind == "Stackable" and string.sub(e.grant.id, 1, 5) == "Buff_" then
		text(
			parent,
			"Goes to your bag: use it from there when you want it to start.",
			12,
			Theme.Colors.TextDim
		)
	end
	local blocked: string? = nil
	if MallGear.KINDS[e.grant.kind] then
		local st = state()
		if gearChoiceFor ~= e.id then
			gearChoiceFor = e.id
			local families = if st.Job then MallGear.families(st.Job, st.Race) else {}
			gearChoice = {
				Bracket = MallGear.defaultBracket(st.Level),
				Family = families[1],
				Piece = MallGear.ACCESSORIES[1],
			}
		end
		local function choiceRow(
			label: string,
			options: { { id: any, text: string } },
			current: any,
			set: (any) -> ()
		)
			text(parent, label, 12, Theme.Colors.TextDim, true)
			local line = Kit.new("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Parent = parent,
			})
			local layout = Kit.list(line, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Left)
			layout.Wraps = true
			for _, option in options do
				button(line, option.text, 96, option.id == current, function()
					set(option.id)
					confirming = nil
					render()
				end)
			end
		end
		local levels = {}
		for _, l in MallGear.LEVELS do
			table.insert(levels, { id = l, text = if l > st.Level then `Lv {l} 🔒` else `Lv {l}` })
		end
		choiceRow("Level (it can be worn from this level)", levels, gearChoice.Bracket, function(v)
			gearChoice.Bracket = v
		end)
		if e.grant.kind == "Weapon" and st.Job then
			local options = {}
			for _, family in MallGear.families(st.Job, st.Race) do
				table.insert(options, { id = family, text = family })
			end
			choiceRow("Weapon type", options, gearChoice.Family, function(v)
				gearChoice.Family = v
			end)
		elseif e.grant.kind == "Accessory" then
			local options = {}
			for _, piece in MallGear.ACCESSORIES do
				table.insert(options, { id = piece, text = MallGear.PIECE_NAMES[piece] })
			end
			choiceRow("Accessory", options, gearChoice.Piece, function(v)
				gearChoice.Piece = v
			end)
		end
		local bracket = gearChoice.Bracket or 0
		if bracket > st.Level then
			text(
				parent,
				`🔒 You are level {st.Level}: you can buy it now and wear it from level {bracket}.`,
				12,
				Theme.Colors.GoldBright,
				true
			)
		end
		local lines, why = gearPreview(e.grant.kind, e.grant.rarity, gearChoice)
		if why == "noOffHand" then
			local message = "Your class has no off-hand piece."
			blocked = message
			text(parent, message, 13, TOO_DEAR, true)
		else
			text(parent, "You get, with these exact attributes:", 12, Theme.Colors.TextDim)
			for _, line in lines do
				text(parent, "• " .. line, 11, Theme.Colors.Text)
			end
		end
	end
	local affordable = points() >= priceOf(e)
	local asking = confirming == e.id and os.clock() <= confirmUntil
	text(
		parent,
		if affordable
			then `Price: {priceOf(e)} MP  ·  You have {points()} MP`
			else `Price: {priceOf(e)} MP  ·  You need {priceOf(e) - points()} more MP`,
		13,
		if affordable then Theme.Colors.Safe else TOO_DEAR,
		true
	)
	button(
		parent,
		if blocked
			then "Not for your class"
			elseif asking then `Tap again to confirm ({priceOf(e)} MP)`
			else `Buy for {priceOf(e)} MP`,
		240,
		blocked == nil and (affordable or asking),
		function()
			if blocked == nil then
				buy(e)
			end
		end
	)
	if not affordable then
		button(parent, "💠 Get Mall Points", 200, false, function()
			tab = "Points"
			detailOnly = false
			render()
		end)
	end
end

function render()
	if panel == nil then
		return
	end
	local old = (panel :: Frame):FindFirstChild("Content")
	if old then
		old:Destroy()
	end
	local frame = Kit.new("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = panel,
	})
	-- Regions from MallLayout (Phase 19, D-94: tested on every device size).
	local screen = Panels.layer().AbsoluteSize
	local l = MallLayout.compute(screen.X, screen.Y)
	local wide = l.wide

	-- Header: back to the bag, title, balance, Get MP, Close.
	local back = button(frame, "← Bag", 84, false, function()
		close()
		InventoryController.setOpen(true)
	end)
	back.Position = UDim2.fromOffset(l.back.x, l.back.y)
	-- Left-aligned beside ← Bag, never reaching the balance on the right
	-- (creator review 2026-10-26: it sat centred against "0 MP").
	local title = Kit.label("🛒 Item Mall", 17, Theme.Fonts.Display, Theme.Colors.GoldBright)
	local titleX = l.back.x + l.back.w + 12
	title.AutomaticSize = Enum.AutomaticSize.None
	title.Position = UDim2.fromOffset(titleX, l.back.y)
	title.Size = UDim2.fromOffset(math.max(0, l.right.x - titleX - 12), l.back.h)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextWrapped = false
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.Visible = l.showTitle
	title.Parent = frame
	local right = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(l.right.x, l.right.y),
		Size = UDim2.fromOffset(l.right.w, l.right.h),
		Parent = frame,
	})
	Kit.list(right, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Right)
	local balance = Kit.label(`💠 {points()} MP`, 15, Theme.Fonts.BodyBold, Theme.Colors.Text)
	balance.Size = UDim2.fromOffset(0, 44)
	balance.AutomaticSize = Enum.AutomaticSize.X
	balance.LayoutOrder = 1
	balance.Parent = right
	local get = button(right, "Get MP", 80, true, function()
		tab = "Points"
		detailOnly = false
		render()
	end)
	get.LayoutOrder = 2
	get.Visible = l.showGetMp
	local shut = button(right, "Close", 70, false, close)
	shut.LayoutOrder = 3

	-- Tabs.
	local tabs = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(l.tabs.x, l.tabs.y),
		Size = UDim2.fromOffset(l.tabs.w, l.tabs.h),
		CanvasSize = UDim2.fromScale(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 3,
		Parent = frame,
	})
	Kit.list(tabs, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Left)
	for _, name in MallDefinitions.TABS do
		button(
			tabs,
			MallDefinitions.TAB_NAMES[name],
			if name == "Points" then (if l.short then 150 else 170) else (if l.short then 104 else 120),
			name == tab,
			function()
				tab = name
				confirming = nil
				detailOnly = false
				render()
			end
		)
	end

	-- The selected card of this tab (default: its first).
	local sections = choicesFor(tab)
	local chosen: Choice? = nil
	for _, section in sections do
		for _, choice in section.items do
			if chosen == nil or keyOf(choice) == selected[tab] then
				chosen = choice
			end
		end
	end
	if chosen then
		selected[tab] = keyOf(chosen)
	end

	local showGrid = wide or not detailOnly
	local showDetail = wide or detailOnly
	local gridW = l.grid.w
	if showGrid then
		local grid = Kit.new("ScrollingFrame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(l.grid.x, l.grid.y),
			Size = UDim2.fromOffset(l.grid.w, l.grid.h),
			CanvasSize = UDim2.fromScale(0, 0),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = 6,
			Parent = frame,
		})
		local list = Kit.list(grid, Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Left)
		list.VerticalAlignment = Enum.VerticalAlignment.Top
		-- Room round the cards so their borders (and the selected card's
		-- gold ring) are never clipped, and for the scroll bar on the
		-- right (creator review 2026-10-26: the right border was cut).
		local padding = Instance.new("UIPadding")
		padding.PaddingTop = UDim.new(0, 4)
		padding.PaddingBottom = UDim.new(0, 6)
		padding.PaddingLeft = UDim.new(0, 4)
		padding.PaddingRight = UDim.new(0, 14)
		padding.Parent = grid
		local usable = gridW - 18
		local columns = math.max(2, math.floor((usable + 8) / 158))
		local cellW = math.floor((usable - (columns - 1) * 8) / columns)
		for order, section in sections do
			local heading = text(grid, section.title, 14, Theme.Colors.GoldBright, true)
			heading.LayoutOrder = order * 2 - 1
			-- Exact height (rows of cards): a grid inside an auto-sized frame
			-- can come up short and hide the last row.
			local rows = math.max(1, math.ceil(#section.items / columns))
			local cells = Kit.new("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, rows * l.cardH + (rows - 1) * 8),
				LayoutOrder = order * 2,
				Parent = grid,
			})
			local layout = Instance.new("UIGridLayout")
			layout.CellSize = UDim2.fromOffset(cellW, l.cardH)
			layout.CellPadding = UDim2.fromOffset(8, 8)
			layout.SortOrder = Enum.SortOrder.LayoutOrder
			layout.Parent = cells
			for _, choice in section.items do
				card(cells, choice, chosen ~= nil and keyOf(choice) == keyOf(chosen))
			end
		end
	end
	if showDetail and chosen then
		local pane = Kit.new("ScrollingFrame", {
			BackgroundColor3 = Theme.Colors.Ink,
			BackgroundTransparency = 0.35,
			Position = UDim2.fromOffset(l.detail.x, l.detail.y),
			Size = UDim2.fromOffset(l.detail.w, l.detail.h),
			CanvasSize = UDim2.fromScale(0, 0),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = 6,
			Parent = frame,
		})
		Kit.corner(pane, 10)
		Kit.padding(pane, 10, 12)
		local list = Kit.list(pane, Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Left)
		list.VerticalAlignment = Enum.VerticalAlignment.Top
		if not wide then
			button(pane, "← Back to list", 150, false, function()
				detailOnly = false
				confirming = nil
				render()
			end)
		end
		detail(pane, chosen)
	end
	local footer =
		Kit.label(status, 12, Theme.Fonts.BodyBold, if statusBad then TOO_DEAR else Theme.Colors.Safe)
	footer.AutomaticSize = Enum.AutomaticSize.None
	footer.Position = UDim2.fromOffset(l.footer.x, l.footer.y)
	footer.Size = UDim2.fromOffset(l.footer.w, l.footer.h)
	footer.TextXAlignment = Enum.TextXAlignment.Left
	footer.TextTruncate = Enum.TextTruncate.AtEnd
	footer.Parent = frame
end

function MallController.open()
	if panel then
		return
	end
	InventoryController.setOpen(false)
	Panels.opened("mall")
	local layer = Panels.layer()
	local screen = layer.AbsoluteSize
	local l = MallLayout.compute(screen.X, screen.Y)
	panel = Kit.glassPanel({
		Name = "Mall",
		Active = true,
		Position = UDim2.fromOffset(l.panel.x, l.panel.y),
		Size = UDim2.fromOffset(l.panel.w, l.panel.h),
		Parent = layer,
	})
	setStatus("")
	detailOnly = false
	render()
end

-- One badge: icon and label on top, minutes left under them.
local function badge(
	parent: Instance,
	top: string,
	bottom: string,
	ring: Color3,
	tip: () -> (string, string?)
)
	local b = Kit.new("TextButton", {
		Size = UDim2.fromOffset(OverlayLayout.BADGE_W, OverlayLayout.BADGE_H),
		BackgroundColor3 = Theme.Colors.Glass,
		BackgroundTransparency = 0.1,
		Text = "",
		AutoButtonColor = true,
		Parent = parent,
	})
	Kit.corner(b, 10)
	local stroke = Instance.new("UIStroke")
	stroke.Color = ring
	stroke.Thickness = 1.5
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = b
	local upper = Kit.label(top, 13, Theme.Fonts.BodyBold, Theme.Colors.Text)
	upper.AutomaticSize = Enum.AutomaticSize.None
	upper.Position = UDim2.fromOffset(0, 4)
	upper.Size = UDim2.new(1, 0, 0, 18)
	upper.TextWrapped = false
	upper.Parent = b
	local lower = Kit.label(bottom, 12, Theme.Fonts.BodyBold, ring)
	lower.AutomaticSize = Enum.AutomaticSize.None
	lower.Position = UDim2.fromOffset(0, 23)
	lower.Size = UDim2.new(1, 0, 0, 16)
	lower.TextWrapped = false
	lower.Parent = b
	Tooltip.attach(b, tip, "tap")
end

-- The running buffs as badges under the event chip.
local function renderChip()
	local row = badgeRow
	if row == nil then
		return
	end
	for _, child in row:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local now = os.clock()
	local running = {}
	for _, id in BuffRules.IDS do
		local untilAt = state().BuffsUntil[id]
		if type(untilAt) == "number" and untilAt > now then
			table.insert(
				running,
				{ buff = BuffRules.get(id) :: BuffRules.Buff, minutes = math.ceil((untilAt - now) / 60) }
			)
		end
	end
	row.Visible = #running > 0
	local columns = math.max(1, math.floor((badgeWidth + 4) / (OverlayLayout.BADGE_W + 4)))
	local shown = if #running > columns then columns - 1 else #running
	for index = 1, shown do
		local entry = running[index]
		local buff = entry.buff
		local ring = if REWARD_CATEGORIES[buff.category] then REWARD_RING else COMBAT_RING
		badge(row, `{buff.icon} {buff.tag}`, `{entry.minutes}m`, ring, function()
			local left = state().BuffsUntil[buff.id] or 0
			local minutes = math.max(0, math.ceil((left - os.clock()) / 60))
			return buff.name,
				`{buff.short}. {minutes} min left.\nUsing another adds {buff.minutes} min (up to 6 h).`
		end)
	end
	local rest = #running - shown
	if rest > 0 then
		badge(row, if shown == 0 then `🧪 {rest}` else `+{rest}`, "buffs", REWARD_RING, function()
			local lines = {}
			for index = shown + 1, #running do
				local entry = running[index]
				table.insert(
					lines,
					`{entry.buff.icon} {entry.buff.name}: {entry.buff.short}, {entry.minutes} min`
				)
			end
			return if shown == 0 then "Active buffs" else "More active buffs", table.concat(lines, "\n")
		end)
	end
end

function MallController:Start()
	Panels.register("mall", close)
	InventoryController.OpenMall = MallController.open
	local gui = Kit.new("ScreenGui", {
		Name = "RC_Buffs",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		DisplayOrder = 8,
	})
	local row = Kit.new("Frame", {
		Name = "Buffs",
		-- Under the event chip (OverlayLayout, Phase 19, D-94).
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(8, 52),
		Size = UDim2.fromOffset(200, OverlayLayout.BADGE_H),
		Visible = false,
		Parent = gui,
	})
	Kit.list(row, Enum.FillDirection.Horizontal, 4, Enum.HorizontalAlignment.Left)
	gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")
	badgeRow = row
	local function fit()
		local size = gui.AbsoluteSize
		if size.X < 10 then
			return
		end
		local layout = OverlayLayout.compute(size.X, size.Y)
		row.Position = UDim2.fromOffset(layout.chips.x, layout.chips.y)
		row.Size = UDim2.fromOffset(layout.chips.w, OverlayLayout.BADGE_H)
		badgeWidth = layout.chips.w
		renderChip()
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()
	PlayerDataController.Changed:Connect(function()
		renderChip()
		if panel then
			render()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(15)
			renderChip()
		end
	end)
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(_userId, _productId, purchased)
		if purchased and panel then
			setStatus("✅ Thank you! Your Mall Points arrive in a moment.")
			render()
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.N then
			if panel then
				close()
			else
				MallController.open()
			end
		end
	end)
end

return MallController
