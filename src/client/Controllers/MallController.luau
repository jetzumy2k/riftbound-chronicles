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
	           Combat draughts, Utility...): icon, name, price (red when
	           you can't afford it)
	  Details  tapping a card shows everything about it beside the cards (or,
	           on a narrow screen, in place of them with "← Back to list"):
	           the description, how many you have, a running buff's time
	           left, a set's pieces with their fixed attributes, and Buy
	           (then "Tap again to confirm" for a few seconds)
	  Buffs    while any buff runs, a chip under the event chip shows each
	           buff's icon and minutes left

	Opened from the 🛒 Mall button in the bag (or key N).
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MallDefinitions = require(Shared.Definitions.MallDefinitions)
local ItemDefinitions = require(Shared.Definitions.ItemDefinitions)
local JobDefinitions = require(Shared.Definitions.JobDefinitions)
local BuffRules = require(Shared.Logic.BuffRules)
local ItemRules = require(Shared.Logic.ItemRules)
local OverlayLayout = require(Shared.Layout.OverlayLayout)
local MallLayout = require(Shared.Layout.MallLayout)
local NetClient = require(Shared.Net.Client)

local UI = script.Parent.Parent.UI
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)
local Panels = require(UI.Panels)

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
local chip: TextLabel? = nil
-- Phase 19 (D-94): the buff chip's short form (icons only) on crowded screens.
local chipCompact = false

local function state()
	return PlayerDataController:Get()
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

-- The set's pieces and their fixed attributes for this character.
local function setPreview(rarity: string): { string }
	local s = state()
	local job, race = s.Job, s.Race
	if job == nil then
		return {}
	end
	local level = math.clamp(s.Level, 0, 30)
	local family: string? = nil
	for _, candidate in ItemDefinitions.familiesOf(job) do
		if JobDefinitions.allowsWeapon(job, race, candidate) then
			family = candidate
			break
		end
	end
	local lines = {}
	for _, kind in ItemDefinitions.kindsOf(job) do
		local def = ItemDefinitions.defFor(job, kind, if kind == "Weapon" then family else nil, level)
		if def then
			local itemLevel = math.clamp(level, def.minItemLevel, def.maxItemLevel)
			local parts = {}
			for _, attribute in ItemRules.fixedRoll(def, rarity, itemLevel) do
				local spec = ItemRules.STATS[attribute.Stat]
				table.insert(parts, `{spec.name} {attribute.Value}{if spec.percent then "%" else ""}`)
			end
			table.insert(lines, `{def.name} (Lv {itemLevel}): {table.concat(parts, ", ")}`)
		end
	end
	return lines
end

-- What the cards of a tab are, by section.
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
	local result = NetClient.invoke("BuyMallItem", entry.id)
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
	name.Position = UDim2.fromOffset(8, 40)
	name.Size = UDim2.new(1, -16, 0, 34)
	name.TextWrapped = true
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextYAlignment = Enum.TextYAlignment.Top
	name.Parent = b
	local affordable = entry == nil or points() >= entry.price
	local price = Kit.label(
		if entry
			then `{entry.price} MP`
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
	if e.grant.kind == "Set" then
		text(
			parent,
			"Every piece for your class at your level, with these exact attributes:",
			12,
			Theme.Colors.TextDim
		)
		for _, line in setPreview(e.grant.rarity) do
			text(parent, "• " .. line, 11, Theme.Colors.Text)
		end
	end
	local affordable = points() >= e.price
	local asking = confirming == e.id and os.clock() <= confirmUntil
	text(
		parent,
		if affordable
			then `Price: {e.price} MP  ·  You have {points()} MP`
			else `Price: {e.price} MP  ·  You need {e.price - points()} more MP`,
		13,
		if affordable then Theme.Colors.Safe else TOO_DEAR,
		true
	)
	button(
		parent,
		if asking then `Tap again to confirm ({e.price} MP)` else `Buy for {e.price} MP`,
		240,
		affordable or asking,
		function()
			buy(e)
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
	local title = Kit.label("🛒 Item Mall", 17, Theme.Fonts.Display, Theme.Colors.GoldBright)
	title.Position = UDim2.fromOffset(l.back.x + l.back.w + 10, l.back.y + 10)
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
		local columns = math.max(2, math.floor((gridW - 10) / 150))
		local cellW = math.floor((gridW - 14 - (columns - 1) * 8) / columns)
		for order, section in sections do
			local heading = text(grid, section.title, 14, Theme.Colors.GoldBright, true)
			heading.LayoutOrder = order * 2 - 1
			local cells = Kit.new("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, -8, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
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

-- The running-buffs chip under the event chip.
local function renderChip()
	local label = chip
	if label == nil then
		return
	end
	local now = os.clock()
	local parts = {}
	for _, id in BuffRules.IDS do
		local untilAt = state().BuffsUntil[id]
		if type(untilAt) == "number" and untilAt > now then
			local buff = BuffRules.get(id) :: BuffRules.Buff
			table.insert(
				parts,
				if chipCompact then buff.icon else `{buff.icon} {math.ceil((untilAt - now) / 60)}m`
			)
		end
	end
	label.Visible = #parts > 0
	label.Text = table.concat(parts, if chipCompact then "" else "  ")
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
	local label = Kit.new("TextLabel", {
		-- Under the event chip (OverlayLayout, Phase 19, D-94).
		Position = UDim2.fromOffset(8, 40),
		Size = UDim2.fromOffset(0, 26),
		AutomaticSize = Enum.AutomaticSize.X,
		TextTruncate = Enum.TextTruncate.AtEnd,
		BackgroundColor3 = Theme.Colors.Glass,
		BackgroundTransparency = 0.25,
		TextSize = 13,
		FontFace = Theme.Fonts.BodyBold,
		TextColor3 = Theme.Colors.Text,
		Visible = false,
		Parent = gui,
	})
	Kit.corner(label, 13)
	Kit.padding(label, 0, 10)
	local limit = Kit.new("UISizeConstraint", { Parent = label })
	gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")
	chip = label
	local function fit()
		local size = gui.AbsoluteSize
		if size.X < 10 then
			return
		end
		local layout = OverlayLayout.compute(size.X, size.Y)
		label.Position = UDim2.fromOffset(layout.chips.x, layout.chips.y + OverlayLayout.EVENT_CHIP_H + 4)
		limit.MaxSize = Vector2.new(layout.chips.w, 26)
		chipCompact = layout.compact
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
