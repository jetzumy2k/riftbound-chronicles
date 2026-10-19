--!strict
--[[
	InventoryController — the bag and equipment screen (Phase 7, PLAN.md
	D-64; CLAUDE.md §8-9, §28).

	  - Equipment: the six D-25 slots (tap one to inspect what's in it), the
	    total gear bonus, the stackables (Healing Potion "Use", fragments
	    "Combine" 10 -> 1 Enhancement Stone) and the wallet.
	  - The bag: every item as a tile (icon, rarity border and letter, item
	    level, +N, 🔒 locked, ✓ equipped), strongest first, filtered by All /
	    Weapons / Armor / Accessories. Bulk salvage of unlocked Standard and
	    Uncommon pieces (tap twice).
	  - Detail: name in its rarity colour plus the rarity word (never colour
	    alone), slot, job, item level, the piece's stats and rolled
	    attributes, why it can't be worn (if so), and Equip / Unequip, Lock /
	    Unlock, Salvage (tap twice).

	Every button is an intent (EquipItem, UnequipItem, LockItem,
	SalvageItems, CombineFragments, UseConsumable); the server validates it
	and answers with InventoryUpdate, which is what this screen shows. Open
	with the "🎒 BAG" button (right edge, under SKILLS) or B. Layout:
	Layout/InventoryLayout (device-tested). Studio only: a "test gear"
	button (StudioTestGear) until loot exists (Phase 10).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enums = require(Shared.Enums)
local ItemDefinitions = require(Shared.Definitions.ItemDefinitions)
local JobDefinitions = require(Shared.Definitions.JobDefinitions)
local ItemRules = require(Shared.Logic.ItemRules)
local WeaponRules = require(Shared.Definitions.WeaponRules)
local EnhanceRules = require(Shared.Logic.EnhanceRules)
local InventoryLayout = require(Shared.Layout.InventoryLayout)
local NetClient = require(Shared.Net.Client)

local UI = script.Parent.Parent.UI
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)

local PlayerDataController = require(script.Parent.PlayerDataController)
local NotificationController = require(script.Parent.NotificationController)

type Item = PlayerDataController.Item

-- Rarity colour, short letter (shown on tiles) and order (CLAUDE.md §9).
local RARITY_COLOR: { [string]: Color3 } = {
	Standard = Color3.fromRGB(200, 200, 205),
	Uncommon = Color3.fromRGB(110, 220, 120),
	Rare = Color3.fromRGB(90, 160, 255),
	Epic = Color3.fromRGB(190, 110, 255),
	Legendary = Color3.fromRGB(255, 160, 50),
	Mythical = Color3.fromRGB(255, 80, 110),
}
local RARITY_LETTER: { [string]: string } = {
	Standard = "S",
	Uncommon = "U",
	Rare = "R",
	Epic = "E",
	Legendary = "L",
	Mythical = "M",
}
local SLOT_GLYPH: { [string]: string } = {
	Weapon = "⚔",
	OffHand = "🛡",
	Helm = "⛑",
	Shoulders = "🦺",
	Chest = "🛡",
	Hands = "🧤",
	Legs = "👖",
	Boots = "👢",
	Necklace = "📿",
	Earrings = "✧",
	Ring1 = "💍",
	Ring2 = "💍",
}
-- Slot labels under the equipment tiles (D-68).
local SLOT_LABEL: { [string]: string } = {
	Weapon = "Main hand",
	OffHand = "Off-hand",
	Ring1 = "Ring",
	Ring2 = "Ring",
}
local FILTERS = {
	{ id = "All", text = "All" },
	{ id = "Weapon", text = "Weapons" },
	{ id = "Armor", text = "Armor" },
	{ id = "Accessory", text = "Accessories" },
}
local CANT_WEAR: { [string]: string } = {
	job = "Another class's gear.",
	race = "Your realm doesn't use this weapon.",
	level = "Reach level %d to wear it.",
	unknown = "Unknown item.",
}
-- Bulk salvage takes unlocked, unequipped pieces of these rarities.
local BULK_RARITIES = { Standard = true, Uncommon = true }
local CONFIRM_SECONDS = 3

local InventoryController = {}

local gui: ScreenGui
local toggle: TextButton
local panel: Frame? = nil
local open = false
local selected: string? = nil
local filter = "All"
-- What a second tap confirms ("salvage:<guid>" / "bulk") and until when.
local confirm: string? = nil
local confirmUntil = 0
local gridScroll = Vector2.zero
local renderToken = 0
-- The last enhancement result, shown in the detail for a few seconds.
local lastEnhance: { guid: string, success: boolean, level: number, at: number }? = nil
local ENHANCE_RESULT_SECONDS = 4

local render: () -> ()

local function localPlayer(): Player
	return Players.LocalPlayer :: Player
end

local function state(): PlayerDataController.State
	return PlayerDataController:Get()
end

local function defOf(item: Item): ItemDefinitions.ItemDef?
	return ItemDefinitions.get(item.DefId)
end

local function equippedSlot(guid: string): string?
	for slot, equipped in state().Equipment do
		if equipped == guid then
			return slot
		end
	end
	return nil
end

local function count(t: { [any]: any }): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

local function confirming(key: string): boolean
	return confirm == key and os.clock() < confirmUntil
end

local function askConfirm(key: string)
	confirm = key
	confirmUntil = os.clock() + CONFIRM_SECONDS
	render()
	task.delay(CONFIRM_SECONDS + 0.05, function()
		if confirm == key and os.clock() >= confirmUntil then
			confirm = nil
			render()
		end
	end)
end

--------------------------------------------------------------------------------
-- Pieces
--------------------------------------------------------------------------------

local function button(text: string, width: number, accent: Color3?): TextButton
	local b = Kit.new("TextButton", {
		Size = UDim2.fromOffset(width, 44),
		BackgroundColor3 = accent or Theme.Colors.GlassRaised,
		BackgroundTransparency = 0.05,
		Text = text,
		TextSize = 13,
		FontFace = Theme.Fonts.BodyBold,
		TextColor3 = if accent then Color3.fromRGB(30, 20, 8) else Theme.Colors.Text,
		TextWrapped = true,
		AutoButtonColor = true,
	})
	Kit.corner(b, 10)
	return b
end

local function text(parent: Instance, value: string, size: number, color: Color3?, font: Font?): TextLabel
	local label = Kit.new("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = value,
		TextSize = size,
		FontFace = font or Theme.Fonts.Body,
		TextColor3 = color or Theme.Colors.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		RichText = false,
		Parent = parent,
	})
	return label
end

local function badge(parent: Instance, value: string, anchor: Vector2, color: Color3)
	Kit.new("TextLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = anchor,
		Position = UDim2.new(
			anchor.X,
			if anchor.X > 0 then -3 else 3,
			anchor.Y,
			if anchor.Y > 0 then -1 else 1
		),
		Size = UDim2.fromOffset(28, 14),
		Text = value,
		TextSize = 11,
		FontFace = Theme.Fonts.BodyBold,
		TextColor3 = color,
		TextStrokeTransparency = 0.3,
		TextXAlignment = if anchor.X > 0 then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left,
		ZIndex = 3,
		Parent = parent,
	})
end

-- An item tile (or an empty slot when `item` is nil).
local function tile(size: number, item: Item?, emptyGlyph: string?): TextButton
	local def = item and defOf(item)
	local rarity = item and item.Rarity or "Standard"
	local color = RARITY_COLOR[rarity] or Theme.Colors.TextDim
	local isSelected = item ~= nil and item.Guid == selected
	local b = Kit.new("TextButton", {
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = if item then Theme.Colors.GlassRaised else Theme.Colors.Ink,
		BackgroundTransparency = if item then 0.05 else 0.4,
		Text = if def then def.glyph else (emptyGlyph or ""),
		TextSize = math.floor(size * 0.42),
		TextTransparency = if item then 0 else 0.6,
		FontFace = Theme.Fonts.BodyBold,
		TextColor3 = Theme.Colors.Text,
		AutoButtonColor = true,
	})
	Kit.corner(b, 10)
	Kit.new("UIStroke", {
		Color = if isSelected then Theme.Colors.GoldBright else color,
		Thickness = if isSelected then 3 else (if item then 2 else 1),
		Transparency = if item then 0 else 0.6,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = b,
	})
	if item then
		badge(b, RARITY_LETTER[rarity] or "?", Vector2.new(0, 1), color)
		badge(b, `Lv{item.ItemLevel}`, Vector2.new(1, 1), Theme.Colors.TextDim)
		if item.Enhancement > 0 then
			badge(b, `+{item.Enhancement}`, Vector2.new(1, 0), Theme.Colors.GoldBright)
		end
		if item.Locked then
			badge(b, "🔒", Vector2.new(0, 0), Theme.Colors.Text)
		elseif equippedSlot(item.Guid) then
			badge(b, "✓", Vector2.new(0, 0), Theme.Colors.Safe)
		end
	end
	return b
end

local function sortedItems(): { Item }
	local list = {}
	for _, item in state().Inventory do
		local def = defOf(item)
		local category = if def and def.category == "Shield" then "Armor" else def and def.category
		if def and (filter == "All" or category == filter) then
			table.insert(list, item)
		end
	end
	table.sort(list, function(a, b)
		local ra = Enums.indexOf(Enums.Rarity, a.Rarity) or 0
		local rb = Enums.indexOf(Enums.Rarity, b.Rarity) or 0
		if ra ~= rb then
			return ra > rb
		end
		if a.ItemLevel ~= b.ItemLevel then
			return a.ItemLevel > b.ItemLevel
		end
		if a.CreatedAt ~= b.CreatedAt then
			return a.CreatedAt > b.CreatedAt
		end
		return a.Guid < b.Guid
	end)
	return list
end

local function bulkCandidates(): { string }
	local out = {}
	for guid, item in state().Inventory do
		if BULK_RARITIES[item.Rarity] and not item.Locked and equippedSlot(guid) == nil then
			table.insert(out, guid)
			if #out >= 25 then
				break
			end
		end
	end
	return out
end

local function choose(guid: string?)
	selected = guid
	confirm = nil
	render()
end

--------------------------------------------------------------------------------
-- Sections
--------------------------------------------------------------------------------

local function drawSide(parent: Instance, layout: InventoryLayout.Layout)
	local list = Kit.list(parent, Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Left)
	list.VerticalAlignment = Enum.VerticalAlignment.Top

	-- Equipment slots.
	local slotsFrame = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, InventoryLayout.slotsHeight(layout.slotColumns)),
		LayoutOrder = 1,
		Parent = parent,
	})
	local tileSize = layout.tile
	for index, slot in Enums.ItemSlot do
		local column = (index - 1) % layout.slotColumns
		local row = (index - 1) // layout.slotColumns
		local guid = state().Equipment[slot]
		local item = if guid then state().Inventory[guid] else nil
		local cell = tile(tileSize, item, SLOT_GLYPH[slot])
		cell.Position = UDim2.fromOffset(
			column * (tileSize + layout.gap),
			row * (tileSize + InventoryLayout.SLOT_LABEL + layout.gap)
		)
		cell.Parent = slotsFrame
		if item then
			cell.Activated:Connect(function()
				choose(item.Guid)
			end)
		end
		Kit.new("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(cell.Position.X.Offset - 6, cell.Position.Y.Offset + tileSize),
			Size = UDim2.fromOffset(tileSize + 12, InventoryLayout.SLOT_LABEL),
			Text = SLOT_LABEL[slot] or slot,
			TextSize = 11,
			FontFace = Theme.Fonts.Body,
			TextColor3 = Theme.Colors.TextDim,
			Parent = slotsFrame,
		})
	end

	-- Gear bonus.
	local totals = ItemRules.gearTotals(state().Equipment, state().Inventory :: any)
	local lines = {}
	for _, stat in ItemRules.STAT_ORDER do
		local value = (totals :: any)[stat]
		if value > 0 then
			table.insert(lines, ItemRules.formatStat(stat, value))
		end
	end
	local bonus = text(
		parent,
		if #lines > 0 then "Gear bonus:  " .. table.concat(lines, ",  ") else "Gear bonus: nothing equipped",
		12,
		Theme.Colors.TextDim
	)
	bonus.LayoutOrder = 2

	-- Stackables.
	local heading = text(parent, "Materials and potions", 13, Theme.Colors.GoldBright, Theme.Fonts.BodyBold)
	heading.LayoutOrder = 3
	local order = 4
	for _, id in ItemDefinitions.STACKABLE_ORDER do
		local def = ItemDefinitions.stackable(id) :: ItemDefinitions.StackableDef
		local have = state().Stackables[id] or 0
		local row = Kit.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 44),
			LayoutOrder = order,
			Parent = parent,
		})
		order += 1
		local name = Kit.new("TextLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -92, 1, 0),
			Text = `{def.glyph}  {def.name}  ×{have}`,
			TextSize = 12,
			FontFace = Theme.Fonts.BodyBold,
			TextColor3 = if have > 0 then Theme.Colors.Text else Theme.Colors.TextMuted,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true,
			Parent = row,
		})
		name.TextTruncate = Enum.TextTruncate.AtEnd
		local action: TextButton? = nil
		if def.use then
			local readyAt = state().ReadyAt[id] or 0
			local wait = math.ceil(readyAt - os.clock())
			action = button(
				if wait > 0 then `{wait}s` else "Use",
				84,
				if wait <= 0 and have > 0 then Theme.Colors.Gold else nil
			);
			(action :: TextButton).Activated:Connect(function()
				NetClient.fire("UseConsumable", id)
			end)
		elseif id == "StoneFragment" then
			local stones = math.min(have // ItemRules.FRAGMENTS_PER_STONE, 100)
			action = button(
				if stones > 0 then `Combine ×{stones}` else `Need {ItemRules.FRAGMENTS_PER_STONE}`,
				84,
				if stones > 0 then Theme.Colors.Gold else nil
			);
			(action :: TextButton).Activated:Connect(function()
				if stones > 0 then
					NetClient.fire("CombineFragments", stones)
				end
			end)
		end
		if action then
			action.AnchorPoint = Vector2.new(1, 0)
			action.Position = UDim2.fromScale(1, 0)
			action.Parent = row
		end
	end

	if ReplicatedStorage:GetAttribute("RC_StudioTestGear") == true then
		local test = button("Studio: add test gear", 180)
		test.LayoutOrder = order
		test.Parent = parent
		test.Activated:Connect(function()
			NetClient.fire("StudioTestGear")
		end)
	end
end

local function drawFilters(parent: ScrollingFrame)
	Kit.list(parent, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Left)
	for index, entry in FILTERS do
		local b = button(entry.text, 96, if filter == entry.id then Theme.Colors.Gold else nil)
		b.LayoutOrder = index
		b.Parent = parent
		b.Activated:Connect(function()
			filter = entry.id
			gridScroll = Vector2.zero
			render()
		end)
	end
	local candidates = bulkCandidates()
	local bulk = button(
		if confirming("bulk") then `Tap again: salvage {#candidates}` else "Salvage S + U",
		128,
		if confirming("bulk") then Color3.fromRGB(255, 140, 110) else nil
	)
	bulk.LayoutOrder = 10
	bulk.Parent = parent
	bulk.Activated:Connect(function()
		local now = bulkCandidates()
		if #now == 0 then
			return
		end
		if confirming("bulk") then
			confirm = nil
			NetClient.fire("SalvageItems", now)
		else
			askConfirm("bulk")
		end
	end)
end

local function drawGrid(parent: GuiObject, width: number, layout: InventoryLayout.Layout)
	local items = sortedItems()
	local columns = InventoryLayout.columns(width)
	local step = layout.tile + layout.gap
	for index, item in items do
		local cell = tile(layout.tile, item)
		cell.Position = UDim2.fromOffset(((index - 1) % columns) * step, ((index - 1) // columns) * step)
		cell.Parent = parent
		cell.Activated:Connect(function()
			choose(item.Guid)
		end)
	end
	if #items == 0 then
		local empty = text(
			parent,
			if filter == "All"
				then "Your bag is empty. Defeat creatures and bosses to find gear."
				else "Nothing of this kind yet.",
			13,
			Theme.Colors.TextDim
		)
		empty.Size = UDim2.new(1, 0, 0, 40)
	end
	return math.max(1, math.ceil(#items / columns)) * step
end

-- Server-published rates (ReplicatedStorage "RC_EnhanceRates"), else D-08.
local function enhanceRates(): { number }?
	local raw = ReplicatedStorage:GetAttribute("RC_EnhanceRates")
	if type(raw) ~= "string" then
		return nil
	end
	local out = {}
	for value in string.gmatch(raw, "[^,]+") do
		table.insert(out, tonumber(value) or 0)
	end
	return out
end

-- Enhancement (Phase 8, D-66): the odds, what +1 adds, the two stone
-- buttons and the last result. Failure never lowers the item.
local function drawEnhance(parent: Instance, item: Item, def: ItemDefinitions.ItemDef)
	local box = Kit.new("Frame", {
		BackgroundColor3 = Theme.Colors.Ink,
		BackgroundTransparency = 0.35,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 8,
		Parent = parent,
	})
	Kit.corner(box, 10)
	Kit.padding(box, 8, 8)
	local list = Kit.list(box, Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Left)
	list.VerticalAlignment = Enum.VerticalAlignment.Top
	local level = item.Enhancement
	local result = lastEnhance
	if result and result.guid == item.Guid and os.clock() - result.at < ENHANCE_RESULT_SECONDS then
		text(
			box,
			if result.success
				then `✓ Success! Now +{result.level}`
				else `✗ Failed: still +{result.level} (a stone was used, the item is unchanged)`,
			13,
			if result.success then Theme.Colors.Safe else Color3.fromRGB(255, 150, 130),
			Theme.Fonts.BodyBold
		).LayoutOrder =
			0
	end
	if level >= EnhanceRules.MAX then
		text(box, `Enhancement +{level}: maximum reached.`, 13, Theme.Colors.GoldBright, Theme.Fonts.BodyBold).LayoutOrder =
			1
		return
	end
	local rate = EnhanceRules.rateFor(level, enhanceRates())
	local gain = if def.category == "Weapon" then "+20 Attack, +2.5% Crit Damage" else "+8 Defense"
	text(
		box,
		`Enhance +{level} → +{level + 1}:  {rate}% chance  ·  each +1 adds {gain}. A failure only uses the stone.`,
		12,
		Theme.Colors.Text
	).LayoutOrder =
		1
	local stones = state().Stackables[EnhanceRules.STONE] or 0
	local perfects = state().Stackables[EnhanceRules.PERFECT] or 0
	local row = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		Parent = box,
	})
	Kit.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(112, 44),
		CellPadding = UDim2.fromOffset(6, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = row,
	})
	local guid = item.Guid
	local normal = button(`💎 Enhance ({stones})`, 112, if stones > 0 then Theme.Colors.Gold else nil)
	normal.LayoutOrder = 1
	normal.Parent = row
	normal.Activated:Connect(function()
		if stones > 0 then
			NetClient.fire("EnhanceItem", guid, false)
		end
	end)
	local perfect =
		button(`✨ Perfect 100% ({perfects})`, 112, if perfects > 0 then Theme.Colors.Gold else nil)
	perfect.LayoutOrder = 2
	perfect.Parent = row
	perfect.Activated:Connect(function()
		if perfects > 0 then
			NetClient.fire("EnhanceItem", guid, true)
		end
	end)
end

local function drawDetail(parent: Instance)
	local list = Kit.list(parent, Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Left)
	list.VerticalAlignment = Enum.VerticalAlignment.Top
	local item = if selected then state().Inventory[selected] else nil
	local def = item and defOf(item)
	if item == nil or def == nil then
		text(parent, "Tap an item to see its stats.", 13, Theme.Colors.TextDim)
		return
	end
	local color = RARITY_COLOR[item.Rarity] or Theme.Colors.Text
	local plus = if item.Enhancement > 0 then ` +{item.Enhancement}` else ""
	text(parent, `{def.name}{plus}`, 16, color, Theme.Fonts.Display).LayoutOrder = 1
	local job = JobDefinitions.get(def.job)
	text(
		parent,
		`{item.Rarity} · {def.slot}{if def.family then ` ({def.family})` else ""} · Item level {item.ItemLevel}`,
		12,
		Theme.Colors.TextDim
	).LayoutOrder =
		2
	text(parent, `{if job then job.displayName else def.job} gear`, 12, Theme.Colors.TextDim).LayoutOrder = 3
	-- D-68: how it is held and what goes with it.
	local hold = if def.family
		then WeaponRules.describe(def.family)
		elseif def.slot == "Shield" then "Shield · off-hand · with a short sword, mace or hand axe"
		elseif def.slot == "Ring" then "Ring · two can be worn"
		else nil
	if hold then
		text(parent, hold, 12, Theme.Colors.GoldBright, Theme.Fonts.BodyBold).LayoutOrder = 3
	end

	local base = ItemRules.baseStats(def, item.Rarity, item.ItemLevel, item.Enhancement)
	local lines = {}
	for _, stat in ItemRules.STAT_ORDER do
		local value = (base :: any)[stat]
		if value > 0 then
			table.insert(lines, ItemRules.formatStat(stat, value))
		end
	end
	text(parent, table.concat(lines, "\n"), 13, Theme.Colors.Text, Theme.Fonts.BodyBold).LayoutOrder = 4
	if #item.Attributes > 0 then
		local rolled = {}
		for _, attribute in item.Attributes do
			table.insert(rolled, "◆ " .. ItemRules.formatStat(attribute.Stat, attribute.Value))
		end
		text(parent, table.concat(rolled, "\n"), 13, color, Theme.Fonts.BodyBold).LayoutOrder = 5
	end

	local data = state()
	local slot = equippedSlot(item.Guid)
	local ok, reason = ItemRules.canEquip(item :: any, data.Job, data.Race, data.Level)
	if not ok and slot == nil then
		local why = CANT_WEAR[reason or "unknown"] or CANT_WEAR.unknown
		text(parent, string.format(why, item.ItemLevel), 12, Color3.fromRGB(255, 150, 130)).LayoutOrder = 6
	end
	if slot then
		text(parent, `✓ Equipped ({slot})`, 12, Theme.Colors.Safe).LayoutOrder = 6
	end
	drawEnhance(parent, item, def)

	local buttons = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 7,
		Parent = parent,
	})
	local grid = Kit.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(112, 44),
		CellPadding = UDim2.fromOffset(6, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = buttons,
	})
	grid.FillDirection = Enum.FillDirection.Horizontal
	local guid = item.Guid
	if slot then
		local unequip = button("Unequip", 112)
		unequip.LayoutOrder = 1
		unequip.Parent = buttons
		unequip.Activated:Connect(function()
			NetClient.fire("UnequipItem", slot)
		end)
	elseif ok then
		-- D-68: rings pick a finger; a Warrior's second short sword can go in
		-- the off-hand (dual swords) when a short sword is in the main hand.
		local targets: { { text: string, slot: string? } } = {}
		if def.slot == "Ring" then
			targets = { { text = "Ring 1", slot = "Ring1" }, { text = "Ring 2", slot = "Ring2" } }
		else
			table.insert(
				targets,
				{ text = if def.slot == "Shield" then "Equip (off-hand)" else "Equip", slot = nil }
			)
			local rule = WeaponRules.get(def.family)
			local mainGuid = state().Equipment.Weapon
			local main = mainGuid and state().Inventory[mainGuid]
			local mainDef = main and defOf(main)
			if rule and rule.dual and mainDef and mainDef.family == def.family then
				table.insert(targets, { text = "Off-hand (dual)", slot = "OffHand" })
			end
		end
		for index, target in targets do
			local equip = button(target.text, 112, Theme.Colors.Gold)
			equip.LayoutOrder = index
			equip.Parent = buttons
			equip.Activated:Connect(function()
				NetClient.fire("EquipItem", guid, target.slot)
			end)
		end
	end
	local lock = button(if item.Locked then "🔓 Unlock" else "🔒 Lock", 112)
	lock.LayoutOrder = 2
	lock.Parent = buttons
	lock.Activated:Connect(function()
		NetClient.fire("LockItem", guid, not item.Locked)
	end)
	if slot == nil and not item.Locked then
		local key = `salvage:{guid}`
		local yield = ItemRules.salvageYield(item :: any)
		local salvage = button(
			if confirming(key) then "Tap again" else `Salvage (+{yield}🔹)`,
			112,
			if confirming(key) then Color3.fromRGB(255, 140, 110) else nil
		)
		salvage.LayoutOrder = 3
		salvage.Parent = buttons
		salvage.Activated:Connect(function()
			if confirming(key) then
				confirm = nil
				selected = nil
				NetClient.fire("SalvageItems", { guid })
			else
				askConfirm(key)
			end
		end)
	end
end

--------------------------------------------------------------------------------
-- Screen
--------------------------------------------------------------------------------

function render()
	renderToken += 1
	toggle.Visible = state().Job ~= nil
	if panel then
		local oldGrid = panel:FindFirstChild("Grid", true)
		if oldGrid and oldGrid:IsA("ScrollingFrame") then
			gridScroll = oldGrid.CanvasPosition
		end
		panel:Destroy()
		panel = nil
	end
	if not open then
		return
	end
	if selected and state().Inventory[selected] == nil then
		selected = nil
	end
	local camera = Workspace.CurrentCamera
	local area = gui.AbsoluteSize
	if area.X < 10 and camera then
		area = camera.ViewportSize
	end
	local layout = InventoryLayout.compute(area.X, area.Y)
	local frame = Kit.glassPanel({
		Name = "Inventory",
		Position = UDim2.fromOffset(layout.panel.x, layout.panel.y),
		Size = UDim2.fromOffset(layout.panel.w, layout.panel.h),
		Parent = gui,
	})
	panel = frame

	-- Header: title, count and wallet, Close.
	local header = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(layout.header.x, layout.header.y + 4),
		Size = UDim2.fromOffset(layout.header.w, layout.header.h - 4),
		Parent = frame,
	})
	local title = Kit.label("Inventory", 17, Theme.Fonts.Display, Theme.Colors.GoldBright)
	title.AutomaticSize = Enum.AutomaticSize.None
	title.Size = UDim2.new(1, -84, 0, 22)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = header
	local wallet = state().Wallet
	local sub = Kit.label(
		`{count(state().Inventory)}/{ItemRules.INVENTORY_CAP} items  ·  Gold {wallet.Gold}  ·  PvP Marks {wallet.PvPMarks}`,
		12,
		Theme.Fonts.Body,
		Theme.Colors.TextDim
	)
	sub.AutomaticSize = Enum.AutomaticSize.None
	sub.Position = UDim2.fromOffset(0, 24)
	sub.Size = UDim2.new(1, -84, 0, 18)
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.TextTruncate = Enum.TextTruncate.AtEnd
	sub.Parent = header
	local close = button("Close", 76)
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.fromScale(1, 0)
	close.Parent = header
	close.Activated:Connect(function()
		InventoryController.setOpen(false)
	end)

	local function scroller(name: string, r: InventoryLayout.Rect, parent: Instance): ScrollingFrame
		return Kit.new("ScrollingFrame", {
			Name = name,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(r.x, r.y),
			Size = UDim2.fromOffset(r.w, r.h),
			CanvasSize = UDim2.fromScale(0, 0),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = 6,
			Parent = parent,
		})
	end

	local filtersRect = layout.filters
	local function filterBar(parent: Instance): ScrollingFrame
		local bar = Kit.new("ScrollingFrame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(filtersRect.x, filtersRect.y),
			Size = UDim2.fromOffset(filtersRect.w, filtersRect.h),
			CanvasSize = UDim2.fromScale(0, 0),
			AutomaticCanvasSize = Enum.AutomaticSize.X,
			ScrollingDirection = Enum.ScrollingDirection.X,
			ScrollBarThickness = 3,
			Parent = parent,
		})
		drawFilters(bar)
		return bar
	end

	if layout.mode == "wide" then
		local side = scroller("Side", layout.side, frame)
		Kit.padding(side, 2, 2)
		drawSide(side, layout)
		filterBar(frame)
		local grid = scroller("Grid", layout.grid, frame)
		grid.AutomaticCanvasSize = Enum.AutomaticSize.None
		local inner = Kit.new("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(4, 4),
			Size = UDim2.new(1, -12, 0, 0),
			Parent = grid,
		})
		local height = drawGrid(inner, layout.grid.w - 12, layout)
		inner.Size = UDim2.new(1, -12, 0, height)
		grid.CanvasSize = UDim2.fromOffset(0, height + 8)
		grid.CanvasPosition = gridScroll
		local detail = scroller("Detail", layout.detail, frame)
		detail.BackgroundColor3 = Theme.Colors.Ink
		detail.BackgroundTransparency = 0.4
		Kit.corner(detail, 12)
		Kit.padding(detail, 10, 12)
		drawDetail(detail)
		return
	end

	-- Stacked: one scrolling body; the detail is a sheet over the bottom.
	local body = scroller("Grid", layout.body, frame)
	body.AutomaticCanvasSize = Enum.AutomaticSize.None
	local side = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(layout.side.x, layout.side.y),
		Size = UDim2.fromOffset(layout.side.w, layout.side.h),
		Parent = body,
	})
	drawSide(side, layout)
	filterBar(body)
	local grid = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(layout.grid.x + 4, layout.grid.y + 4),
		Size = UDim2.fromOffset(layout.grid.w - 8, 0),
		Parent = body,
	})
	local height = drawGrid(grid, layout.grid.w - 8, layout)
	grid.Size = UDim2.fromOffset(layout.grid.w - 8, height)
	-- Room at the bottom so the sheet never hides the last row.
	local sheetRoom = if selected then layout.detail.h else 0
	body.CanvasSize = UDim2.fromOffset(0, layout.grid.y + height + 12 + sheetRoom)
	body.CanvasPosition = gridScroll
	if selected then
		local sheet = Kit.glassPanel({
			Name = "DetailSheet",
			Position = UDim2.fromOffset(layout.detail.x, layout.detail.y),
			Size = UDim2.fromOffset(layout.detail.w, layout.detail.h),
			ZIndex = 5,
			Parent = frame,
		})
		local shut = button("✕", 44)
		shut.AnchorPoint = Vector2.new(1, 0)
		shut.Position = UDim2.new(1, -6, 0, 6)
		shut.ZIndex = 6
		shut.Parent = sheet
		shut.Activated:Connect(function()
			choose(nil)
		end)
		local content = scroller("Detail", {
			x = 10,
			y = 8,
			w = layout.detail.w - 64,
			h = layout.detail.h - 16,
		}, sheet)
		drawDetail(content)
	end

	-- Potion cooldowns count down while the screen is open.
	local token = renderToken
	for _, at in state().ReadyAt do
		if at > os.clock() then
			task.delay(1, function()
				if open and token == renderToken then
					render()
				end
			end)
			break
		end
	end
end

function InventoryController.setOpen(value: boolean)
	open = value
	if not value then
		confirm = nil
	end
	render()
end

function InventoryController.toggle()
	InventoryController.setOpen(not open)
end

function InventoryController:Start()
	gui = Kit.new("ScreenGui", {
		Name = "RC_Inventory",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		DisplayOrder = 8,
	})
	local t = InventoryLayout.TOGGLE
	toggle = Kit.new("TextButton", {
		Name = "BagToggle",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -t.right, 0.5, t.offset),
		Size = UDim2.fromOffset(t.w, t.h),
		BackgroundColor3 = Theme.Colors.Glass,
		BackgroundTransparency = 0.15,
		Text = "🎒 BAG",
		TextSize = 13,
		FontFace = Theme.Fonts.BodyBold,
		TextColor3 = Theme.Colors.GoldBright,
		AutoButtonColor = true,
		Visible = false,
		Parent = gui,
	})
	Kit.corner(toggle, 12)
	Kit.goldStroke(toggle, 1.5, 0.2)
	toggle.Activated:Connect(InventoryController.toggle)
	gui.Parent = localPlayer():WaitForChild("PlayerGui")

	render()
	NetClient.on("EnhanceResult", function(result)
		if type(result) ~= "table" then
			return
		end
		lastEnhance = { guid = result.Guid, success = result.Success, level = result.Level, at = os.clock() }
		NotificationController:ShowKey(
			if result.Success then "Info" else "Warning",
			if result.Success then "enhance.success" else "enhance.failed",
			{ level = tostring(result.Level) }
		)
		render()
		local token = renderToken
		task.delay(ENHANCE_RESULT_SECONDS + 0.1, function()
			if open and token == renderToken then
				render()
			end
		end)
	end)
	PlayerDataController.Changed:Connect(function(_, reason)
		-- Levels change what can be worn; everything else is inventory.
		if reason == "inventory" or reason == "snapshot" or open then
			render()
		end
	end)
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if open then
			render()
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.B then
			InventoryController.toggle()
		end
	end)
end

return InventoryController
