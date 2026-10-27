--!strict
--[[
	AdminController — the admin / moderator panel (Phase 17, PLAN.md D-77).

	Built only after the server sends AdminHello (staff only), so players
	never get a button or a panel. The client shows what the role allows;
	the server checks every call again (AdminService) and audits it.

	Open with the 🛠 button (under 📐) or F2. Tabs:
	  Players   online players on the left; the picked player on the right
	            with pages Profile (overview, kick / ban), Progress (level,
	            PvP victories, Gold / PvP Marks), Items (give gear or
	            stones, remove bag items) and Quests (reset a stuck quest)
	  Settings  sections on the left (Switches, Drop rates, Enhancement,
	            PvP...); each value has a plain name, an explanation, its
	            default and limits. Edits collect as unsaved changes; "Save"
	            sends the batch, "Reset" puts a value back to its default.
	            Loot tables show their live total (must be 100).
	  Events    (Phase 18, D-89) what is running and scheduled (stop any),
	            and every event template: start now, or schedule it for a
	            day (today ... +6) and a time (HH:MM, the admin's own local
	            time; a live preview shows when that is), for the chosen
	            length. The server checks the template's longest
	            length and cooldown; events of later stages show greyed out
	  World     respawn the war-zone bosses now
	  Log       recent audit entries (Moderators: their own)

	Creator review 2026-10-24: the panel used to rebuild itself whenever a
	typed value was confirmed, so the click on the next box landed on the
	dim backdrop behind it and closed the panel. Now the frame stays put:
	typed values update their row in place, only the area below the tabs
	is redrawn on navigation, the panel sinks clicks, and a backdrop tap
	never closes it (Panels keepOnBackdrop).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local NetClient = require(Shared.Net.Client)
local Enums = require(Shared.Enums)
local ItemDefinitions = require(Shared.Definitions.ItemDefinitions)
local AdminRules = require(Shared.Logic.AdminRules)
local TopBarLayout = require(Shared.Layout.TopBarLayout)
local EventDefinitions = require(Shared.Definitions.EventDefinitions)
local EventRewards = require(Shared.Logic.EventRewards)
local ResetRules = require(Shared.Logic.ResetRules)
local StaffRules = require(Shared.Logic.StaffRules)

local UI = script.Parent.Parent.UI
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)
local Panels = require(UI.Panels)
local AdminText = require(UI.AdminText)
local Tooltip = require(UI.Tooltip)

local AdminController = {}

local GOLD_TEXT = Color3.fromRGB(30, 20, 8)
local DANGER = Color3.fromRGB(150, 44, 44)
local BAD_TEXT = Color3.fromRGB(255, 140, 130)
local CHANGED_BG = Color3.fromRGB(58, 46, 24)
local BAN_LABELS = { [60] = "1 hour", [1440] = "1 day", [10080] = "7 days", [0] = "Permanent" }
local HEADER_H = 92
local FOOTER_H = 30

type Page = { id: string, label: string, permission: string? }

local TABS: { Page } = {
	{ id = "Players", label = "👥 Players" },
	{ id = "Settings", label = "🔧 Settings", permission = "config.view" },
	{ id = "Events", label = "🎉 Events", permission = "events.activate" },
	{ id = "World", label = "🌍 World" },
	{ id = "Staff", label = "🛡️ Staff", permission = "staff.manage" },
	{ id = "Log", label = "📜 Log", permission = "audit.view" },
}
local PLAYER_PAGES: { Page } = {
	{ id = "Profile", label = "Profile" },
	{ id = "Progress", label = "Progress", permission = "player.edit" },
	{ id = "Items", label = "Items" },
	{ id = "Quests", label = "Quests", permission = "quests.manage" },
}

local role: string? = nil
local permissions: { [string]: boolean } = {}
local panel: Frame? = nil
local content: Frame? = nil
local tabStrip: Frame? = nil
local statusLabel: TextLabel? = nil
local tab = "Players"
local status = ""
local statusBad = false
-- Text typed in the boxes (kept when the page is redrawn) and scroll
-- positions per page.
local fields: { [string]: string } = {}
local scrolls: { [string]: Vector2 } = {}

-- Players tab
local searched = false
local results: { any } = {}
local inspected: any = nil
local playerPage = "Profile"
local pickedItem: string? = nil
local rarityIndex = 3
local stackIndex = 1
local reasonIndex = 1
local banIndex = 1

-- Events tab: chosen length (index into EVENT_MINUTES).
local EVENT_MINUTES = { 30, 60, 120, 360, 1440, 2880, 4320 }
local minutesIndex = 2
-- Schedule: the day (0 = today) and the list fetched for this visit (only
-- re-asked after an action or on opening the tab, not on every tap).
local eventDay = 0
local eventsFetched: any = nil
-- D-93 stage 2: rewards to attach to the next Start / Schedule.
local eventRewards: { EventRewards.Entry } = {}
-- D-113: the daily random event settings being edited (nil: as saved).
local dailyDraft: any = nil
-- The event page open (nil: the list) and the reward group being picked.
local eventPage: string? = nil
local rewardGroup = "MallPoints"
local rewardItem = "EnhancementStone"
local rewardSet = "Legendary"

-- World tab: the system reset (D-111). What to keep, and the last reset
-- (fetched once per panel visit).
local RESET_LABELS = {
	Items = "Items & consumables (Gold, PvP Marks too)",
	Gear = "Gear & weapons",
	MallPoints = "Mall Points (Robux-bought points are always kept)",
	Levels = "Levels, attributes & skills",
	Rankings = "PvP rankings",
}
local resetKeep: { [string]: boolean } = {}
-- Staff tab (D-112): the list (fetched per visit), whether we are the
-- Owner, pay being edited per UserId, the item picker and a pending remove.
local staffList: { any }? = nil
local staffOwner = false
local salaryDrafts: { [number]: any } = {}
local staffItemIndex = 1
local staffConfirmRemove: number? = nil
local resetInfo: any = nil

-- Settings tab
local config: any = nil
local section = "Flags"
local pending: { [string]: any } = {}
local updateSaveBar: () -> () = function() end

local refresh: () -> ()

local function can(permission: string): boolean
	return permissions[permission] == true
end

local function allowed(page: Page): boolean
	return page.permission == nil or can(page.permission)
end

--------------------------------------------------------------------------------
-- Widgets
--------------------------------------------------------------------------------

local function setStatus(text: string, bad: boolean?)
	status = text
	statusBad = bad == true
	local label = statusLabel
	if label then
		label.Text = text
		label.TextColor3 = if statusBad then BAD_TEXT else Theme.Colors.Safe
	end
end

-- variant: "gold" (main action), "danger" (kick / ban), nil (plain).
local function button(
	parent: Instance,
	text: string,
	width: number,
	variant: string?,
	onClick: (() -> ())?
): TextButton
	local b = Kit.new("TextButton", {
		Size = UDim2.fromOffset(width, 36),
		BackgroundColor3 = if variant == "gold"
			then Theme.Colors.Gold
			elseif variant == "danger" then DANGER
			else Theme.Colors.GlassHighlight,
		BackgroundTransparency = if variant then 0.05 else 0.35,
		Text = text,
		TextSize = 13,
		FontFace = Theme.Fonts.BodyBold,
		TextColor3 = if variant == "gold" then GOLD_TEXT else Theme.Colors.Text,
		TextWrapped = true,
		AutoButtonColor = true,
		Parent = parent,
	})
	Kit.corner(b, 8)
	if onClick then
		b.Activated:Connect(onClick)
	end
	return b
end

local function label(parent: Instance, text: string, size: number?, color: Color3?, bold: boolean?): TextLabel
	return Kit.new("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = text,
		TextSize = size or 13,
		FontFace = if bold then Theme.Fonts.BodyBold else Theme.Fonts.Body,
		TextColor3 = color or Theme.Colors.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Parent = parent,
	})
end

-- A text box whose text survives redraws (kept in `fields[key]`).
local function field(parent: Instance, key: string, placeholder: string, width: number): TextBox
	local box = Kit.new("TextBox", {
		Size = UDim2.fromOffset(width, 36),
		BackgroundColor3 = Theme.Colors.Ink,
		BackgroundTransparency = 0.1,
		PlaceholderText = placeholder,
		PlaceholderColor3 = Theme.Colors.TextMuted,
		Text = fields[key] or "",
		TextSize = 13,
		FontFace = Theme.Fonts.Body,
		TextColor3 = Theme.Colors.Text,
		ClearTextOnFocus = false,
		Parent = parent,
	})
	Kit.corner(box, 8)
	Kit.goldStroke(box, 1, 0.5)
	box:GetPropertyChangedSignal("Text"):Connect(function()
		fields[key] = box.Text
	end)
	return box
end

-- A wrapping row of controls.
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

-- A titled box grouping related controls.
local function card(parent: Instance, title: string?, help: string?): Frame
	local frame = Kit.new("Frame", {
		BackgroundColor3 = Theme.Colors.GlassRaised,
		BackgroundTransparency = 0.25,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = parent,
	})
	Kit.corner(frame, 10)
	Kit.padding(frame, 10, 12)
	local list = Kit.list(frame, Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Left)
	list.VerticalAlignment = Enum.VerticalAlignment.Top
	if title then
		label(frame, title, 14, Theme.Colors.GoldBright, true)
	end
	if help and help ~= "" then
		label(frame, help, 12, Theme.Colors.TextDim)
	end
	return frame
end

-- A vertical scrolling list; its scroll position is kept per `key`.
local function scroller(parent: Instance, key: string, position: UDim2, size: UDim2): ScrollingFrame
	local frame: ScrollingFrame = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		Position = position,
		Size = size,
		CanvasSize = UDim2.fromScale(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.Colors.Gold,
		Parent = parent,
	})
	local list = Kit.list(frame, Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Left)
	list.VerticalAlignment = Enum.VerticalAlignment.Top
	Kit.padding(frame, 2, 8)
	local saved = scrolls[key]
	local restored = not saved
	task.defer(function()
		if saved and frame.Parent then
			frame.CanvasPosition = saved
		end
		restored = true
	end)
	frame:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		if restored then
			scrolls[key] = frame.CanvasPosition
		end
	end)
	return frame
end

--[[
	A row of page buttons; the selected one is gold. `vertical` stacks them
	Returns the buttons by page id.
]]
local function pageButtons(
	parent: Instance,
	pages: { Page },
	selected: string,
	width: number,
	onPick: (string) -> (),
	badge: ((string) -> string)?
): { [string]: TextButton }
	local made = {}
	for _, page in pages do
		if allowed(page) then
			local text = page.label .. (if badge then badge(page.id) else "")
			made[page.id] = button(
				parent,
				text,
				width,
				if page.id == selected then "gold" else nil,
				function()
					onPick(page.id)
				end
			)
		end
	end
	return made
end

-- Runs a server call and shows the outcome in the status line.
local function call(name: string, ...: any): any
	local result = NetClient.invoke(name, ...)
	if type(result) ~= "table" then
		setStatus("❌ No answer from the server.", true)
		return nil
	end
	if result.ok == false then
		setStatus(`❌ Refused: {tostring(result.reason or result.code)}`, true)
		return nil
	end
	setStatus("✅ Done.")
	return result
end

local function clear(frame: Instance)
	for _, child in frame:GetChildren() do
		child:Destroy()
	end
end

--------------------------------------------------------------------------------
-- Players
--------------------------------------------------------------------------------

local function search()
	local result = call("AdminPlayers", string.sub(fields.search or "", 1, 20))
	results = if result then result.players else {}
	searched = true
	if result then
		setStatus(`✅ {#results} player(s) online match.`)
	end
end

local function inspect(userId: number)
	local result = call("AdminInspect", userId)
	inspected = if result then result.player else nil
end

local function act(action: string, args: { [string]: any })
	if inspected == nil then
		return
	end
	local userId = inspected.UserId
	local result = call("AdminPlayerAction", userId, action, args)
	if result then
		local keep = status
		if action == "Kick" or action == "Ban" then
			inspected = nil
			search()
		else
			inspect(userId)
		end
		setStatus(keep)
	end
	refresh()
end

local function numberIn(key: string): number?
	local n = tonumber(fields[key] or "")
	return if n and n == n and n % 1 == 0 then n else nil
end

-- A number box plus its action button; refuses to send a non-number.
local function numberAction(
	parent: Instance,
	key: string,
	placeholder: string,
	text: string,
	onNumber: (number) -> ()
)
	local r = row(parent)
	field(r, key, placeholder, 130)
	button(r, text, 130, "gold", function()
		local n = numberIn(key)
		if n == nil then
			setStatus(`❗ Type a whole number first ({placeholder}).`, true)
			return
		end
		onNumber(n)
	end)
end

local function drawProfile(body: Instance, p: any)
	local overview = card(body, "Overview")
	label(overview, `Level {p.Level}  ·  {p.Experience} EXP`, 13)
	label(overview, `Realm: {p.Race or "not chosen"}  ·  Class: {p.Job or "not chosen"}`, 13)
	label(overview, `PvP: {p.Victories} victories / {p.Defeats} defeats`, 13)
	if p.Wallet then
		label(
			overview,
			`Gold {p.Wallet.Gold}  ·  PvP Marks {p.Wallet.PvPMarks}  ·  Mall Points {p.Wallet.MallPoints or 0}`,
			13
		)
		local stones = {}
		for id, count in p.Stackables or {} do
			local def = ItemDefinitions.stackable(id)
			table.insert(stones, `{if def then def.name else AdminText.words(id)} x{count}`)
		end
		if #stones > 0 then
			label(overview, `Stones: {table.concat(stones, ", ")}`, 13)
		end
	end

	if can("moderation.kick") or can("moderation.ban") then
		local moderation = card(
			body,
			"Moderation",
			"Pick a reason first. Kick removes them from this server; Ban uses Roblox's ban system for the chosen time."
		)
		local r = row(moderation)
		button(r, `Reason: {AdminRules.REASONS[reasonIndex]}`, 200, nil, function()
			reasonIndex = reasonIndex % #AdminRules.REASONS + 1
			refresh()
		end)
		if can("moderation.kick") then
			button(r, "Kick", 90, "danger", function()
				act("Kick", { Reason = AdminRules.REASONS[reasonIndex] })
			end)
		end
		if can("moderation.ban") then
			local r2 = row(moderation)
			local minutes = AdminRules.BAN_MINUTES[banIndex]
			button(r2, `Length: {BAN_LABELS[minutes]}`, 200, nil, function()
				banIndex = banIndex % #AdminRules.BAN_MINUTES + 1
				refresh()
			end)
			button(r2, "Ban", 90, "danger", function()
				act("Ban", { Reason = AdminRules.REASONS[reasonIndex], Number = minutes })
			end)
		end
	end
end

local function drawProgress(body: Instance, p: any)
	local level = card(body, "Level", `Now level {p.Level}. Type 0 to 30.`)
	numberAction(level, "level", "Level 0-30", "Set level", function(n)
		act("SetLevel", { Number = n })
	end)
	local victories = card(
		body,
		"PvP victories (kill points)",
		`Now {p.Victories}. Victory titles follow the new number automatically.`
	)
	numberAction(victories, "victories", "Victories", "Set victories", function(n)
		act("SetVictories", { Number = n })
	end)
	local wallet = card(
		body,
		"Gold, PvP Marks and Mall Points",
		"Type an amount to add. Use a minus number to take (for example -100); it never goes below 0."
	)
	local r = row(wallet)
	field(r, "amount", "Amount", 130)
	for _, currency in
		{ { "Gold", "Add Gold" }, { "PvPMarks", "Add PvP Marks" }, { "MallPoints", "Add Mall Points" } }
	do
		button(r, currency[2], 130, "gold", function()
			local n = numberIn("amount")
			if n == nil then
				setStatus("❗ Type a whole number first.", true)
				return
			end
			act("AddCurrency", { Currency = currency[1], Number = n })
		end)
	end
end

local function drawItems(body: Instance, p: any)
	if can("items.grant") then
		local gear =
			card(body, "Give gear", "Search by name, pick one, choose rarity and item level, then Give.")
		local r1 = row(gear)
		local box = field(r1, "itemSearch", "Search gear by name", 220)
		local matches = row(gear)
		local function fill()
			clear(matches)
			local layout = Kit.list(matches, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Left)
			layout.Wraps = true
			local needle = string.lower(fields.itemSearch or "")
			if needle == "" then
				return
			end
			local shown = 0
			for _, def in ItemDefinitions.All do
				if shown < 12 and string.find(string.lower(def.name), needle, 1, true) then
					shown += 1
					button(
						matches,
						`{def.glyph} {def.name} (L{def.minItemLevel}-{def.maxItemLevel})`,
						230,
						if def.id == pickedItem then "gold" else nil,
						function()
							pickedItem = def.id
							refresh()
						end
					)
				end
			end
			if shown == 0 then
				label(matches, "No gear matches.", 12, Theme.Colors.TextMuted)
			end
		end
		box:GetPropertyChangedSignal("Text"):Connect(fill)
		fill()
		local picked = if pickedItem then ItemDefinitions.get(pickedItem) else nil
		label(
			gear,
			if picked then `Picked: {picked.glyph} {picked.name}` else "Picked: nothing yet",
			13,
			if picked then Theme.Colors.GoldBright else Theme.Colors.TextMuted,
			true
		)
		local r2 = row(gear)
		button(r2, `Rarity: {Enums.Rarity[rarityIndex]}`, 170, nil, function()
			rarityIndex = rarityIndex % #Enums.Rarity + 1
			refresh()
		end)
		field(r2, "itemLevel", "Item level 0-30", 130)
		button(r2, "Give", 100, if picked then "gold" else nil, function()
			if pickedItem == nil then
				setStatus("❗ Pick gear from the search first.", true)
				return
			end
			act("GrantItem", {
				DefId = pickedItem,
				Rarity = Enums.Rarity[rarityIndex],
				Number = numberIn("itemLevel"),
			})
		end)

		-- Player-facing names, never ids (creator review 2026-10-26:
		-- "Buff_Clarity" showed here); tap to cycle, the effect is listed.
		local stones = card(body, "Give stones, potions and buffs", "Tap the name to pick another item.")
		local r3 = row(stones)
		local stackId = ItemDefinitions.STACKABLE_ORDER[stackIndex] or ItemDefinitions.STACKABLE_ORDER[1]
		local stackDef = ItemDefinitions.stackable(stackId) :: ItemDefinitions.StackableDef
		button(r3, `{stackDef.glyph} {stackDef.name}`, 240, nil, function()
			stackIndex = stackIndex % #ItemDefinitions.STACKABLE_ORDER + 1
			refresh()
		end)
		field(r3, "count", "Count 1-999", 130)
		label(stones, stackDef.short, 12, Theme.Colors.TextDim)
		button(r3, "Give", 100, "gold", function()
			local n = numberIn("count")
			if n == nil then
				setStatus("❗ Type how many to give.", true)
				return
			end
			act("GrantStackable", { Stackable = stackId, Number = n })
		end)
	end

	if p.Items then
		local bag = card(
			body,
			`Bag ({#p.Items} items)`,
			if can("items.remove") then "Equipped items can't be removed." else nil
		)
		if #p.Items == 0 then
			label(bag, "Empty.", 12, Theme.Colors.TextMuted)
		end
		for index, item in p.Items do
			local r = Kit.new("Frame", {
				BackgroundColor3 = Theme.Colors.Ink,
				BackgroundTransparency = if index % 2 == 0 then 0.6 else 0.85,
				Size = UDim2.new(1, 0, 0, 40),
				Parent = bag,
			})
			Kit.corner(r, 6)
			local text = label(
				r,
				`{item.Name}  ·  {item.Rarity}  ·  L{item.ItemLevel}  ·  +{item.Enhancement}{if item.Equipped
					then "  ·  equipped"
					else ""}`,
				12
			)
			text.AutomaticSize = Enum.AutomaticSize.None
			text.Position = UDim2.fromOffset(8, 0)
			text.Size = UDim2.new(1, -110, 1, 0)
			if can("items.remove") and not item.Equipped then
				local remove = button(r, "Remove", 90, "danger", function()
					act("RemoveItem", { Guid = item.Guid })
				end)
				remove.AnchorPoint = Vector2.new(1, 0.5)
				remove.Position = UDim2.new(1, -4, 0.5, 0)
				remove.Size = UDim2.fromOffset(90, 32)
			end
		end
	end
end

local function drawQuests(body: Instance, p: any)
	local quests = card(
		body,
		"Quests",
		"Reset puts a stuck quest back so it can be taken again. A reward already paid is never paid twice."
	)
	for index, quest in p.Quests or {} do
		local r = Kit.new("Frame", {
			BackgroundColor3 = Theme.Colors.Ink,
			BackgroundTransparency = if index % 2 == 0 then 0.6 else 0.85,
			Size = UDim2.new(1, 0, 0, 40),
			Parent = quests,
		})
		Kit.corner(r, 6)
		local text = label(r, `{quest.Name}: {quest.Status or "not started"}`, 12)
		text.AutomaticSize = Enum.AutomaticSize.None
		text.Position = UDim2.fromOffset(8, 0)
		text.Size = UDim2.new(1, -110, 1, 0)
		if quest.Status then
			local reset = button(r, "Reset", 90, nil, function()
				act("ResetQuest", { Quest = quest.Id })
			end)
			reset.AnchorPoint = Vector2.new(1, 0.5)
			reset.Position = UDim2.new(1, -4, 0.5, 0)
			reset.Size = UDim2.fromOffset(90, 32)
		end
	end
end

local function drawPlayerList(parent: Instance, position: UDim2, size: UDim2)
	local column = Kit.new("Frame", {
		BackgroundColor3 = Theme.Colors.GlassRaised,
		BackgroundTransparency = 0.25,
		Position = position,
		Size = size,
		Parent = parent,
	})
	Kit.corner(column, 10)
	local title = label(column, "Online players", 14, Theme.Colors.GoldBright, true)
	title.Position = UDim2.fromOffset(10, 8)
	title.Size = UDim2.new(1, -20, 0, 18)
	local r = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, 32),
		Size = UDim2.new(1, -20, 0, 36),
		Parent = column,
	})
	local box = field(r, "search", "Name or UserId", 100)
	box.Size = UDim2.new(1, -86, 0, 36)
	local go = button(r, "Search", 80, "gold", function()
		search()
		refresh()
	end)
	go.AnchorPoint = Vector2.new(1, 0)
	go.Position = UDim2.fromScale(1, 0)
	box.FocusLost:Connect(function(enterPressed)
		-- Enter searches; tapping away does nothing (no redraw under the tap).
		if enterPressed then
			search()
			refresh()
		end
	end)
	local list = scroller(column, "players", UDim2.fromOffset(2, 74), UDim2.new(1, -4, 1, -78))
	if #results == 0 then
		label(
			list,
			if searched then "Nobody matches." else "Press Search to list everyone online.",
			12,
			Theme.Colors.TextMuted
		)
	end
	for _, p in results do
		local selected = inspected ~= nil and inspected.UserId == p.UserId
		local b = button(
			list,
			`{p.DisplayName} (@{p.Name})\nLv {p.Level} · {p.Race or "-"} · {p.Job or "-"}`,
			100,
			if selected then "gold" else nil,
			function()
				inspect(p.UserId)
				playerPage = "Profile"
				refresh()
			end
		)
		b.Size = UDim2.new(1, -4, 0, 46)
		b.TextXAlignment = Enum.TextXAlignment.Left
		Kit.padding(b, 4, 10)
	end
end

local function drawPlayerDetail(parent: Instance, position: UDim2, size: UDim2, narrow: boolean)
	local column = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Position = position,
		Size = size,
		Parent = parent,
	})
	local p = inspected
	if p == nil then
		local hint =
			label(column, "Pick a player from the list to see their details.", 14, Theme.Colors.TextMuted)
		hint.TextXAlignment = Enum.TextXAlignment.Center
		hint.Position = UDim2.fromScale(0, 0.4)
		return
	end
	local top = 0
	if narrow then
		local back = button(column, "Back to the list", 150, nil, function()
			inspected = nil
			refresh()
		end)
		back.Position = UDim2.fromOffset(0, 0)
		top = 42
	end
	local name = label(column, `{p.DisplayName}  (@{p.Name})`, 16, Theme.Colors.GoldBright, true)
	name.Position = UDim2.fromOffset(4, top)
	name.Size = UDim2.new(1, -8, 0, 20)
	name.AutomaticSize = Enum.AutomaticSize.None
	name.TextTruncate = Enum.TextTruncate.AtEnd
	local sub = label(
		column,
		`UserId {p.UserId}  ·  Level {p.Level}  ·  {p.Race or "no realm"}  ·  {p.Job or "no class"}`,
		12,
		Theme.Colors.TextDim
	)
	sub.Position = UDim2.fromOffset(4, top + 22)
	sub.Size = UDim2.new(1, -8, 0, 16)
	sub.AutomaticSize = Enum.AutomaticSize.None
	sub.TextTruncate = Enum.TextTruncate.AtEnd
	local pages = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, top + 44),
		Size = UDim2.new(1, 0, 0, 36),
		Parent = column,
	})
	Kit.list(pages, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Left)
	local visible: { Page } = {}
	for _, page in PLAYER_PAGES do
		if allowed(page) and (page.id ~= "Items" or can("items.grant") or p.Items ~= nil) then
			table.insert(visible, page)
		end
	end
	local known = false
	for _, page in visible do
		known = known or page.id == playerPage
	end
	if not known then
		playerPage = "Profile"
	end
	pageButtons(pages, visible, playerPage, if narrow then 84 else 110, function(id)
		playerPage = id
		refresh()
	end)
	local body = scroller(
		column,
		`player:{playerPage}`,
		UDim2.fromOffset(0, top + 88),
		UDim2.new(1, 0, 1, -(top + 88))
	)
	if playerPage == "Progress" then
		drawProgress(body, p)
	elseif playerPage == "Items" then
		drawItems(body, p)
	elseif playerPage == "Quests" then
		drawQuests(body, p)
	else
		drawProfile(body, p)
	end
end

local function drawPlayers(area: Frame)
	if not searched then
		search()
	end
	local width = area.AbsoluteSize.X
	if width >= 680 then
		drawPlayerList(area, UDim2.fromOffset(0, 0), UDim2.new(0, 260, 1, 0))
		drawPlayerDetail(area, UDim2.fromOffset(272, 0), UDim2.new(1, -272, 1, 0), false)
	elseif inspected then
		drawPlayerDetail(area, UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1), true)
	else
		drawPlayerList(area, UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1))
	end
end

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

local function loadConfig()
	config = call("AdminConfigGet")
	pending = {}
end

local function shown(value: any): string
	if value == nil then
		return "none"
	elseif value == true then
		return "ON"
	elseif value == false then
		return "OFF"
	end
	return tostring(value)
end

local function pendingCount(sectionName: string?): number
	local count = 0
	for path in pending do
		if sectionName == nil or string.match(path, "^([%w]+)") == sectionName then
			count += 1
		end
	end
	return count
end

-- The value a row shows: the unsaved edit, else the live value.
local function displayed(entry: any): any
	local change = pending[entry.path]
	if change == nil then
		return entry.value
	elseif change.Reset then
		return entry.default
	elseif change.Number ~= nil then
		return change.Number
	elseif change.Bool ~= nil then
		return change.Bool
	end
	return change.Text
end

-- Records `value` for the row (or drops the edit when it matches the live value).
local function edit(entry: any, change: any)
	local path = entry.path
	if change == nil then
		pending[path] = nil
		return
	end
	local value = if change.Number ~= nil
		then change.Number
		elseif change.Bool ~= nil then change.Bool
		else change.Text
	pending[path] = if value == entry.value then nil else change
end

local function limitsText(entry: any): string
	if entry.min ~= nil and entry.max ~= nil then
		return `{entry.min} to {entry.max}`
	elseif entry.min ~= nil then
		return `at least {entry.min}`
	elseif entry.max ~= nil then
		return `at most {entry.max}`
	end
	return ""
end

local function drawSettingRow(
	parent: Instance,
	entry: any,
	leaf: AdminText.Leaf,
	narrow: boolean,
	onChange: () -> ()
)
	local frame = Kit.new("Frame", {
		BackgroundColor3 = CHANGED_BG,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = parent,
	})
	Kit.corner(frame, 8)
	Kit.padding(frame, 6, 8)
	local layout = Kit.list(frame, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left)
	layout.Wraps = true
	local controlsWidth = 220
	local text = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Size = if narrow then UDim2.fromScale(1, 0) else UDim2.new(1, -(controlsWidth + 8), 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = frame,
	})
	local textList = Kit.list(text, Enum.FillDirection.Vertical, 2, Enum.HorizontalAlignment.Left)
	textList.VerticalAlignment = Enum.VerticalAlignment.Top
	local name = label(text, leaf.name, 13, Theme.Colors.Text, true)
	if leaf.help then
		label(text, leaf.help, 11, Theme.Colors.TextDim)
	end
	local unit = if leaf.unit then ` {leaf.unit}` else ""
	local limits = limitsText(entry)
	label(
		text,
		`Default: {shown(entry.default)}{if entry.default ~= nil then unit else ""}{if limits ~= ""
			then `  ·  allowed {limits}`
			else ""}`,
		11,
		Theme.Colors.TextMuted
	)

	local controls = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(controlsWidth, 36),
		Parent = frame,
	})
	local controlsList = Kit.list(controls, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Right)
	controlsList.HorizontalAlignment = if narrow
		then Enum.HorizontalAlignment.Left
		else Enum.HorizontalAlignment.Right

	local look: () -> ()
	local control: GuiObject
	if entry.kind == "boolean" then
		local toggle = button(controls, "", 120, nil)
		toggle.Activated:Connect(function()
			edit(entry, { Bool = not displayed(entry) })
			look()
			onChange()
		end)
		control = toggle
	elseif entry.kind == "enum" then
		local cycle = button(controls, "", 140, nil)
		cycle.Activated:Connect(function()
			local values = entry.values
			local index = table.find(values, displayed(entry)) or 0
			edit(entry, { Text = values[index % #values + 1] })
			look()
			onChange()
		end)
		control = cycle
	elseif entry.kind == "number" then
		local box: TextBox = Kit.new("TextBox", {
			Size = UDim2.fromOffset(120, 36),
			BackgroundColor3 = Theme.Colors.Ink,
			BackgroundTransparency = 0.1,
			PlaceholderText = "none",
			PlaceholderColor3 = Theme.Colors.TextMuted,
			Text = "",
			TextSize = 14,
			FontFace = Theme.Fonts.BodyBold,
			TextColor3 = Theme.Colors.Text,
			ClearTextOnFocus = false,
			Parent = controls,
		})
		Kit.corner(box, 8)
		local stroke = Kit.new("UIStroke", {
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = Theme.Colors.GoldDeep,
			Thickness = 1,
			Parent = box,
		})
		box.Focused:Connect(function()
			stroke.Color = Theme.Colors.GoldBright
		end)
		box.FocusLost:Connect(function()
			local typed = string.gsub(box.Text, "%s", "")
			if typed == "" then
				-- Emptied: back to what it was.
				edit(entry, nil)
				look()
				onChange()
				return
			end
			local n = tonumber(typed)
			local bad = n == nil
				or n ~= n
				or (entry.min ~= nil and n < entry.min)
				or (entry.max ~= nil and n > entry.max)
				or (entry.integer and n % 1 ~= 0)
			if bad then
				stroke.Color = BAD_TEXT
				setStatus(
					`❗ {leaf.name}: type a {if entry.integer then "whole number" else "number"}{if limits
							~= ""
						then ` from {limits}`
						else ""}.`,
					true
				)
				return
			end
			edit(entry, { Number = n })
			look()
			onChange()
		end)
		control = box
	else
		local value = label(controls, "", 13)
		value.Size = UDim2.fromOffset(120, 36)
		value.AutomaticSize = Enum.AutomaticSize.None
		control = value
	end

	local reset = button(controls, "Reset", 70, nil)
	reset.TextSize = 12
	reset.Activated:Connect(function()
		if entry.value == entry.default then
			edit(entry, nil)
		elseif string.match(entry.path, "%.%d+$") and entry.default ~= nil then
			-- A list step (Enhancement): a Reset would put back the whole
			-- list, so set just this step to its default.
			edit(entry, { Number = entry.default })
		else
			pending[entry.path] = { Reset = true }
		end
		look()
		onChange()
	end)

	function look()
		local value = displayed(entry)
		local changed = pending[entry.path] ~= nil
		frame.BackgroundTransparency = if changed then 0.35 else 1
		name.Text = leaf.name .. (if changed then "  (unsaved)" else "")
		name.TextColor3 = if changed then Theme.Colors.GoldBright else Theme.Colors.Text
		reset.Visible = value ~= entry.default
		if entry.kind == "boolean" then
			local toggle = control :: TextButton
			toggle.Text = if value then "ON" else "OFF"
			toggle.BackgroundColor3 = if value then Theme.Colors.SafeDeep else Theme.Colors.GlassHighlight
			toggle.TextColor3 = if value then Theme.Colors.Safe else Theme.Colors.TextDim
			toggle.BackgroundTransparency = 0.05
		elseif entry.kind == "enum" then
			(control :: TextButton).Text = shown(value)
		elseif entry.kind == "number" then
			local box = control :: TextBox
			box.Text = if value ~= nil then tostring(value) else ""
			local stroke = box:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = if changed then Theme.Colors.GoldBright else Theme.Colors.GoldDeep
			end
		else
			(control :: TextLabel).Text = shown(value)
		end
	end
	look()
end

-- Live total of a loot table's weights (rarity or stone), which must be 100.
local function weightTotal(entries: { any }): (number, boolean)
	local total, any = 0, false
	for _, entry in entries do
		if string.match(entry.path, "%.Rarity%.") or string.match(entry.path, "%.Stones%.") then
			any = true
			total += displayed(entry) or 0
		end
	end
	return total, any
end

local function drawSettings(area: Frame)
	if config == nil then
		loadConfig()
	end
	if config == nil then
		label(area, "Settings unavailable. Try again in a moment.", 13, Theme.Colors.TextDim)
		return
	end
	local width = area.AbsoluteSize.X
	local wide = width >= 640
	local sections: { Page } = {}
	for _, name in AdminRules.SECTION_ORDER do
		local permission = AdminRules.CONFIG_SECTIONS[name]
		if can(permission) then
			table.insert(sections, { id = name, label = AdminText.section(name).title })
		end
	end
	if #sections == 0 then
		label(area, "Your role can't change settings.", 13, Theme.Colors.TextDim)
		return
	end
	local known = false
	for _, page in sections do
		known = known or page.id == section
	end
	if not known then
		section = sections[1].id
	end
	local function badge(id: string): string
		local count = pendingCount(id)
		return if count > 0 then `  ({count})` else ""
	end
	local function pick(id: string)
		section = id
		refresh()
	end

	local paneX, paneY = 0, 0
	local sectionButtons: { [string]: TextButton }
	if wide then
		local side = scroller(area, "sections", UDim2.fromOffset(0, 0), UDim2.new(0, 190, 1, 0))
		sectionButtons = pageButtons(side, sections, section, 170, pick, badge)
		for _, b in sectionButtons do
			b.TextXAlignment = Enum.TextXAlignment.Left
			Kit.padding(b, 0, 10)
		end
		paneX = 200
	else
		local strip: ScrollingFrame = Kit.new("ScrollingFrame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 44),
			CanvasSize = UDim2.fromScale(0, 0),
			AutomaticCanvasSize = Enum.AutomaticSize.X,
			ScrollingDirection = Enum.ScrollingDirection.X,
			ScrollBarThickness = 4,
			Parent = area,
		})
		Kit.list(strip, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Left)
		sectionButtons = pageButtons(strip, sections, section, 150, pick, badge)
		paneY = 50
	end

	local pane = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(paneX, paneY),
		Size = UDim2.new(1, -paneX, 1, -paneY),
		Parent = area,
	})
	local info = AdminText.section(section)
	local title = label(pane, info.title, 16, Theme.Colors.GoldBright, true)
	title.Position = UDim2.fromOffset(4, 0)
	title.Size = UDim2.new(1, -8, 0, 20)
	title.AutomaticSize = Enum.AutomaticSize.None
	local help = label(pane, info.help, 12, Theme.Colors.TextDim)
	help.Position = UDim2.fromOffset(4, 22)
	help.Size = UDim2.new(1, -8, 0, 32)
	help.AutomaticSize = Enum.AutomaticSize.None
	help.TextYAlignment = Enum.TextYAlignment.Top

	local barH = 48
	local body =
		scroller(pane, `settings:{section}`, UDim2.fromOffset(0, 58), UDim2.new(1, 0, 1, -(58 + barH + 4)))
	local narrow = pane.AbsoluteSize.X < 520

	-- Save bar (stays in place; updated as values change).
	local bar = Kit.new("Frame", {
		BackgroundColor3 = Theme.Colors.Ink,
		BackgroundTransparency = 0.3,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, barH),
		Parent = pane,
	})
	Kit.corner(bar, 10)
	local summary = label(bar, "", 12, Theme.Colors.TextDim, true)
	summary.AutomaticSize = Enum.AutomaticSize.None
	summary.Position = UDim2.fromOffset(10, 0)
	summary.Size = UDim2.new(1, -350, 1, 0)
	local actions = Kit.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -6, 0.5, 0),
		Size = UDim2.fromOffset(336, 36),
		Parent = bar,
	})
	Kit.list(actions, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Right)
	button(actions, "Reload", 90, nil, function()
		loadConfig()
		refresh()
	end)
	local discard = button(actions, "Discard", 90, nil, function()
		pending = {}
		setStatus("Unsaved changes discarded.")
		refresh()
	end)
	local save = button(actions, "Save", 130, nil, function()
		local list = {}
		for path, change in pending do
			local c = table.clone(change)
			c.Path = path
			table.insert(list, c)
		end
		if #list == 0 then
			setStatus("❗ Nothing to save yet.", true)
			return
		end
		if call("AdminConfigSet", config.version, list) then
			loadConfig()
			setStatus(
				`✅ Saved {#list} change(s). Settings are now version {config and config.version or "?"}.`
			)
		end
		refresh()
	end)

	function updateSaveBar()
		local count = pendingCount(nil)
		summary.Text = if count == 0
			then `No unsaved changes  ·  version {config.version}`
			else `{count} unsaved change(s). Save applies them to every server.`
		summary.TextColor3 = if count == 0 then Theme.Colors.TextMuted else Theme.Colors.GoldBright
		save.Text = if count == 0 then "Save" else `Save {count}`
		save.BackgroundColor3 = if count == 0 then Theme.Colors.GlassHighlight else Theme.Colors.Gold
		save.BackgroundTransparency = if count == 0 then 0.35 else 0.05
		save.TextColor3 = if count == 0 then Theme.Colors.TextDim else GOLD_TEXT
		discard.Visible = count > 0
		-- Unsaved counts on the section buttons.
		for id, b in sectionButtons do
			b.Text = AdminText.section(id).title .. badge(id)
		end
	end

	-- Cards: one per loot table / list, or one for the section.
	local order: { string } = {}
	local groups: { [string]: { title: string, entries: { any }, leaves: { AdminText.Leaf } } } = {}
	for _, entry in config.entries do
		if string.match(entry.path, "^([%w]+)") == section then
			local key, groupTitle, leaf = AdminText.describe(entry.path)
			local group = groups[key]
			if group == nil then
				group = { title = groupTitle, entries = {}, leaves = {} }
				groups[key] = group
				table.insert(order, key)
			end
			table.insert(group.entries, entry)
			table.insert(group.leaves, leaf)
		end
	end
	for _, key in order do
		local group = groups[key]
		local box = card(body, if #order > 1 then group.title else nil)
		local totalLabel: TextLabel? = nil
		local function updateTotal()
			local total, hasWeights = weightTotal(group.entries)
			local target = totalLabel
			if target and hasWeights then
				target.Text = if total == 100
					then "✅ Weights total 100"
					else `❗ Weights total {total}: must be exactly 100 to save`
				target.TextColor3 = if total == 100 then Theme.Colors.Safe else BAD_TEXT
			end
		end
		local _, hasWeights = weightTotal(group.entries)
		if hasWeights then
			totalLabel = label(box, "", 12, Theme.Colors.Safe, true)
		end
		for index, entry in group.entries do
			drawSettingRow(box, entry, group.leaves[index], narrow, function()
				updateTotal()
				updateSaveBar()
			end)
		end
		updateTotal()
	end
	updateSaveBar()
end

--------------------------------------------------------------------------------
-- World and log
--------------------------------------------------------------------------------

local function drawWorld(area: Frame)
	local body = scroller(area, "world", UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1))
	if can("bosses.manage") then
		local bosses = card(
			body,
			"🐉 War-zone bosses",
			"Brings back every fallen war-zone boss in this server right away (normally they return on a timer)."
		)
		button(bosses, "Respawn every fallen boss now", 280, "gold", function()
			local result = call("AdminBoss", "RespawnAll")
			if result then
				setStatus(`✅ {result.count} boss(es) respawned.`)
			end
		end)
	end
	if can("system.reset") then
		if resetInfo == nil then
			resetInfo = NetClient.invoke("AdminSystemReset", "Status", {}) or false
		end
		local reset = card(
			body,
			"❗ Reset the whole game (Owner only)",
			"Resets EVERY player, offline ones too (each on their next join). Quests and story always restart; pick what to keep below. A backup of every profile is saved before it is reset. Everyone online is asked to rejoin."
		)
		local info = resetInfo
		label(
			reset,
			if type(info) == "table" and (info.version or 0) > 0
				then `Last reset: #{info.version}, {os.date("%Y-%m-%d %H:%M", info.at)}`
				else "No reset has been run yet.",
			12,
			Theme.Colors.TextDim
		)
		for _, key in ResetRules.KEEP_KEYS do
			local keep = resetKeep[key] == true
			local line = row(reset)
			button(
				line,
				if keep then `✅ Keep: {RESET_LABELS[key]}` else `❌ Clear: {RESET_LABELS[key]}`,
				380,
				nil,
				function()
					resetKeep[key] = not keep
					refresh()
				end
			)
		end
		local confirmLine = row(reset)
		field(confirmLine, "resetConfirm", `Type {ResetRules.CONFIRM_TEXT} to confirm`, 200)
		button(confirmLine, "Reset every player", 200, "danger", function()
			if fields.resetConfirm ~= ResetRules.CONFIRM_TEXT then
				setStatus(`❌ Type {ResetRules.CONFIRM_TEXT} (capitals) in the box first.`, true)
				return
			end
			local result =
				call("AdminSystemReset", "Reset", { Keep = resetKeep, Confirm = fields.resetConfirm })
			fields.resetConfirm = ""
			if result then
				resetInfo = nil
				setStatus(`✅ Reset #{result.version} started. Everyone rejoins in {result.kickIn} seconds.`)
			end
		end)
	end
	local later = card(body, "Coming later")
	label(
		later,
		"Store / item mall: not in v1 (PLAN.md D-15). Anything sold for Robux needs a Roblox policy review first; paid random items are not allowed without it.",
		12,
		Theme.Colors.TextDim
	)
end

--------------------------------------------------------------------------------
-- Events (Phase 18, D-89)
--------------------------------------------------------------------------------

local EVENT_REASONS = {
	running = "it is already running (or scheduled) at that time",
	cooldown = "it ran too recently (its cooldown has not passed)",
	duration = "that length is longer than this event allows",
	notReady = "this event arrives in a later stage",
	past = "that start time is in the past",
	ahead = "events can be scheduled at most 30 days ahead",
	full = "too many events are running or scheduled",
	notRunning = "it is not running or scheduled",
	stale = "another admin changed the settings meanwhile; try again",
	rewardsPermission = "only an Owner or Admin can attach rewards",
	dailyPermission = "only an Owner or Admin can change the daily event",
	["rewards:count"] = "a reward amount is too big (Mall Points up to 10,000, items up to 99, one set)",
	["rewards:many"] = "at most 4 rewards per event",
	["rewards:item"] = "that item can't be an event reward",
	["rewards:group"] = "this event doesn't take that kind of reward",
	["rewards:none"] = "this event takes no bonus rewards",
	RateLimited = "too many requests at once; wait a few seconds and try again",
}

local function span(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local days = seconds // 86400
	local hours = (seconds % 86400) // 3600
	local minutes = (seconds % 3600) // 60
	if days > 0 then
		return `{days}d {hours}h`
	elseif hours > 0 then
		return `{hours}h {minutes}m`
	end
	return `{minutes}m`
end

local function lengthText(minutes: number): string
	return if minutes >= 1440
		then `{minutes // 1440} day(s)`
		elseif minutes >= 60 then `{minutes // 60} h`
		else `{minutes} min`
end

local function eventCall(action: string, args: { [string]: any }): any
	local result = NetClient.invoke("AdminEvents", action, args)
	if type(result) ~= "table" then
		setStatus("❌ No answer from the server.", true)
		return nil
	end
	if result.ok == false then
		local reason = tostring(result.reason or result.code)
		setStatus(`❌ Refused: {EVENT_REASONS[reason] or reason}`, true)
		return nil
	end
	return result
end

-- A time as the admin's local "Sat 26 Oct 14:00".
local function localText(unix: number): string
	return DateTime.fromUnixTimestamp(unix):FormatLocalTime("ddd D MMM HH:mm", "en-us")
end

--[[
	The schedule's start (UTC seconds) from the day chips and the time box
	("14:30", "9:05" or "14"), read as the admin's local time; nil and a
	reason when the box can't be read.
]]
local function scheduledStart(): (number?, string?)
	local text = string.gsub(fields.eventTime or "", "%s", "")
	local h, m = string.match(text, "^(%d%d?):(%d%d)$")
	if h == nil then
		h, m = string.match(text, "^(%d%d?)$"), "0"
	end
	local hour, minute = tonumber(h), tonumber(m)
	if hour == nil or minute == nil or hour > 23 or minute > 59 then
		return nil, "Type a time like 14:30 in the box."
	end
	local today = DateTime.now():ToLocalTime() :: any
	local midnight = DateTime.fromLocalTime(today.Year, today.Month, today.Day, 0, 0, 0).UnixTimestamp
	return midnight + eventDay * 86400 + hour * 3600 + minute * 60, nil
end

local GROUPS = {
	{
		id = "Boosts",
		title = "⚡ Boosts",
		help = "Raise EXP, drops, stones or healing while they run. The boost is the reward.",
	},
	{ id = "World", title = "🌍 World events", help = "Creatures, bosses or weather in the war zones." },
	{ id = "Hunts", title = "🗺️ Hunts", help = "Chests to find in the war zones." },
	{ id = "Challenges", title = "🏆 Challenges", help = "Contests between players and realms." },
}
local ZONE_TEXT = {
	All = "everywhere",
	Dungeon = "the dungeons",
	Desert = "the Desert Rift",
	Jungle = "the Jungle Rift",
	WarZones = "both war zones",
	Capitals = "the capitals",
	Training = "the training yards",
}

-- The live window of event `id` (running or scheduled), if any.
local function windowOf(listed: any, id: string): any
	for _, w in listed.windows do
		if w.Id == id and w.EndsAt > listed.now then
			return w
		end
	end
	return nil
end

local function windowLine(w: any, now: number): string
	if w.StartsAt <= now then
		return `● Running · ends in {span(w.EndsAt - now)}`
	end
	return `📅 Scheduled · starts {localText(w.StartsAt)} your time (in {span(w.StartsAt - now)}), lasts {span(
		w.EndsAt - w.StartsAt
	)}`
end

local function stopButton(parent: Instance, e: EventDefinitions.Event, w: any, now: number)
	local started = w.StartsAt <= now
	button(parent, if started then "Stop" else "Cancel", 96, "danger", function()
		if eventCall("Stop", { Id = w.Id }) then
			setStatus(`✅ {e.name} {if started then "stopped" else "cancelled"}.`)
			eventsFetched = nil
			refresh()
		end
	end)
end

-- The list: what is live, then every event by group; tap one to open it.
-- D-113: minutes this device's clock is ahead of UTC.
local function utcOffsetMinutes(): number
	local t = os.time()
	local here = os.date("*t", t) :: any
	local utc = os.date("!*t", t) :: any
	here.isdst = false
	return math.floor((os.time(here) - os.time(utc)) / 60 + 0.5)
end

local DAILY_MINUTES = { 30, 60, 120, 180, 360, 720, 1440 }

-- The daily random event settings (D-113).
local function drawDaily(body: Instance, listed: any)
	local saved = listed.daily
	if type(saved) ~= "table" then
		return
	end
	local editable = can("config.game")
	if dailyDraft == nil then
		dailyDraft = {
			Enabled = saved.Enabled == true,
			TimeUtcMinutes = saved.TimeUtcMinutes,
			Minutes = saved.Minutes,
			Excluded = table.clone(saved.Excluded),
		}
	end
	local draft = dailyDraft :: any
	local offset = utcOffsetMinutes()
	local localMinutes = (draft.TimeUtcMinutes + offset) % 1440
	local box = card(
		body,
		"📅 Daily random event",
		"When on, one ticked event is picked at random every day at this time (your local time) and runs for the length below. Events that are already running or on cooldown are skipped that day."
	)
	if not editable then
		label(
			box,
			if saved.Enabled
				then string.format(
					"On: every day at %02d:%02d, %s.",
					localMinutes // 60,
					localMinutes % 60,
					lengthText(saved.Minutes)
				)
				else "Off.",
			12,
			Theme.Colors.TextDim
		)
		return
	end
	local top = row(box)
	button(top, if draft.Enabled then "✅ Daily event on" else "❌ Daily event off", 170, nil, function()
		draft.Enabled = not draft.Enabled
		refresh()
	end)
	if fields.dailyHour == nil then
		fields.dailyHour = tostring(localMinutes // 60)
		fields.dailyMinute = string.format("%02d", localMinutes % 60)
	end
	label(top, "Time", 12, Theme.Colors.TextDim).Size = UDim2.fromOffset(40, 36)
	field(top, "dailyHour", "HH", 50)
	label(top, ":", 14).Size = UDim2.fromOffset(8, 36)
	field(top, "dailyMinute", "MM", 50)
	button(top, `Runs {lengthText(draft.Minutes)}`, 140, nil, function()
		local index = table.find(DAILY_MINUTES, draft.Minutes) or 0
		draft.Minutes = DAILY_MINUTES[index % #DAILY_MINUTES + 1]
		refresh()
	end)
	-- Ready events by panel group, ticked ones counted.
	local readyIds: { string } = {}
	for _, e in EventDefinitions.List do
		if EventDefinitions.isReady(e) then
			table.insert(readyIds, e.id)
		end
	end
	local function ticked(id: string): boolean
		return table.find(draft.Excluded, id) == nil
	end
	local function setAll(ids: { string }, on: boolean)
		for _, id in ids do
			local index = table.find(draft.Excluded, id)
			if on and index then
				table.remove(draft.Excluded, index)
			elseif not on and index == nil then
				table.insert(draft.Excluded, id)
			end
		end
		refresh()
	end
	local count = 0
	for _, id in readyIds do
		if ticked(id) then
			count += 1
		end
	end
	local head = row(box)
	label(head, `Events that can be picked: {count} of {#readyIds}`, 13, Theme.Colors.Text, true).Size =
		UDim2.fromOffset(260, 32)
	button(head, "✅ Check all", 120, nil, function()
		setAll(readyIds, true)
	end)
	button(head, "❌ Uncheck all", 130, nil, function()
		setAll(readyIds, false)
	end)
	-- Fixed-width columns so every tick lines up (2 on phones, 3 wider).
	local columns = if Panels.layer().AbsoluteSize.X < 720 then 2 else 3
	for _, group in GROUPS do
		local ids = {}
		for _, e in EventDefinitions.List do
			if e.group == group.id and EventDefinitions.isReady(e) then
				table.insert(ids, e.id)
			end
		end
		if #ids == 0 then
			continue
		end
		local groupHead = row(box)
		label(groupHead, group.title, 12, Theme.Colors.GoldBright, true).Size = UDim2.fromOffset(160, 28)
		local allOn = true
		for _, id in ids do
			allOn = allOn and ticked(id)
		end
		local toggle = button(
			groupHead,
			if allOn then "Uncheck group" else "Check group",
			130,
			nil,
			function()
				setAll(ids, not allOn)
			end
		)
		toggle.Size = UDim2.fromOffset(130, 28)
		local grid = Kit.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = box,
		})
		local layout = Instance.new("UIGridLayout")
		layout.CellPadding = UDim2.fromOffset(6, 6)
		layout.CellSize = UDim2.new(1 / columns, -6, 0, 34)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = grid
		for order, id in ids do
			local e = EventDefinitions.get(id) :: EventDefinitions.Event
			local on = ticked(id)
			local cell = button(grid, `{if on then "✅" else "❌"}  {e.icon} {e.name}`, 10, nil, function()
				setAll({ id }, not on)
			end)
			cell.LayoutOrder = order
			cell.TextXAlignment = Enum.TextXAlignment.Left
			cell.TextWrapped = false
			cell.TextTruncate = Enum.TextTruncate.AtEnd
			cell.BackgroundTransparency = if on then 0.2 else 0.6
			cell.TextColor3 = if on then Theme.Colors.Text else Theme.Colors.TextMuted
			Kit.padding(cell, 0, 10)
		end
	end
	local save = row(box)
	button(save, "Save daily event", 170, "gold", function()
		local hour, minute = tonumber(fields.dailyHour), tonumber(fields.dailyMinute)
		if
			hour == nil
			or minute == nil
			or hour % 1 ~= 0
			or minute % 1 ~= 0
			or hour < 0
			or hour > 23
			or minute < 0
			or minute > 59
		then
			setStatus("❌ Time must be HH 0-23 and MM 0-59.", true)
			return
		end
		local result = eventCall("Daily", {
			Daily = {
				Enabled = draft.Enabled,
				TimeUtcMinutes = (hour * 60 + minute - offset) % 1440,
				Minutes = draft.Minutes,
				Excluded = draft.Excluded,
			},
		})
		if result then
			listed.daily = result.daily
			dailyDraft = nil
			(fields :: any).dailyHour, (fields :: any).dailyMinute = nil, nil
			setStatus(
				if result.daily.Enabled
					then "✅ Daily event saved and on."
					else "✅ Daily event saved (off)."
			)
			refresh()
		end
	end)
end

local function drawEventList(body: Instance, listed: any)
	drawDaily(body, listed)
	local now = listed.now
	local live = card(body, "Live now and scheduled", "Every server follows this list.")
	local any = false
	for _, w in listed.windows do
		local e = EventDefinitions.get(w.Id)
		if e == nil or w.EndsAt <= now then
			continue
		end
		any = true
		local r = row(live)
		label(
			r,
			`{e.icon} {e.name}  ·  {windowLine(w, now)}{if w.Daily then "  ·  📅 daily" else ""}`,
			13,
			if w.StartsAt <= now then Theme.Colors.Safe else Theme.Colors.Text,
			true
		).Size =
			UDim2.new(1, -110, 0, 0)
		stopButton(r, e, w, now)
		if w.Rewards and #w.Rewards > 0 then
			label(live, `      🎁 {EventRewards.describe(w.Rewards)}`, 12, Theme.Colors.GoldBright)
		end
	end
	if not any then
		label(live, "Nothing is running or scheduled.", 12, Theme.Colors.TextDim)
	end
	for _, group in GROUPS do
		local box = card(body, group.title, group.help)
		for _, e in EventDefinitions.List do
			if e.group ~= group.id then
				continue
			end
			local w = windowOf(listed, e.id)
			local entry = Kit.new("TextButton", {
				BackgroundColor3 = Theme.Colors.Ink,
				BackgroundTransparency = 0.5,
				Size = UDim2.new(1, 0, 0, 52),
				Text = "",
				AutoButtonColor = true,
				Parent = box,
			})
			Kit.corner(entry, 8)
			local name = Kit.label(
				`{e.icon} {e.name}{if w
					then (if w.StartsAt <= now then "   ● Running" else "   📅 Scheduled")
					else ""}`,
				14,
				Theme.Fonts.BodyBold,
				if w then Theme.Colors.Safe else Theme.Colors.GoldBright
			)
			name.AutomaticSize = Enum.AutomaticSize.None
			name.Position = UDim2.fromOffset(10, 6)
			name.Size = UDim2.new(1, -60, 0, 20)
			name.TextXAlignment = Enum.TextXAlignment.Left
			name.TextTruncate = Enum.TextTruncate.AtEnd
			name.Parent = entry
			local blurb = Kit.label(e.blurb, 11, Theme.Fonts.Body, Theme.Colors.TextDim)
			blurb.AutomaticSize = Enum.AutomaticSize.None
			blurb.Position = UDim2.fromOffset(10, 27)
			blurb.Size = UDim2.new(1, -60, 0, 18)
			blurb.TextXAlignment = Enum.TextXAlignment.Left
			blurb.TextTruncate = Enum.TextTruncate.AtEnd
			blurb.Parent = entry
			local arrow = Kit.label("›", 26, Theme.Fonts.BodyBold, Theme.Colors.GoldBright)
			arrow.AnchorPoint = Vector2.new(1, 0.5)
			arrow.Position = UDim2.new(1, -14, 0.5, 0)
			arrow.Parent = entry
			entry.Activated:Connect(function()
				eventPage = e.id
				eventRewards = {}
				rewardGroup = if e.rewards then e.rewards[1] else "MallPoints"
				setStatus("")
				refresh()
			end)
		end
	end
end

-- One event: about, status, 1 length, 2 bonus rewards, 3 when.
local function drawEventPage(body: Instance, listed: any, e: EventDefinitions.Event)
	local now = listed.now
	local top = row(body)
	button(top, "← All events", 130, nil, function()
		eventPage = nil
		setStatus("")
		refresh()
	end)
	label(top, `{e.icon} {e.name}`, 17, Theme.Colors.GoldBright, true).Size = UDim2.new(1, -150, 0, 0)

	local eligible = e.eligible
	local who = "every player"
	if eligible then
		who = if eligible.race
			then `{eligible.race}s only`
			elseif eligible.job then `{eligible.job}s only`
			elseif eligible.minLevel then `level {eligible.minLevel}+`
			else who
	end
	local about = card(body, "About")
	label(about, e.blurb, 13)
	label(
		about,
		`Where: {ZONE_TEXT[e.zone] or e.zone}   ·   Who: {who}   ·   Longest run: {lengthText(e.maxMinutes)}   ·   Cooldown: {lengthText(
			e.cooldownMinutes
		)}`,
		12,
		Theme.Colors.TextDim
	)
	local w = windowOf(listed, e.id)
	if w then
		local r = row(about)
		label(
			r,
			windowLine(w, now),
			13,
			if w.StartsAt <= now then Theme.Colors.Safe else Theme.Colors.Text,
			true
		).Size =
			UDim2.new(1, -110, 0, 0)
		stopButton(r, e, w, now)
		if w.Rewards and #w.Rewards > 0 then
			label(
				about,
				`🎁 Bonus rewards: {EventRewards.describe(w.Rewards)}`,
				12,
				Theme.Colors.GoldBright
			)
		end
	end

	-- 1. Length.
	local lengthCard = card(body, "1. How long")
	local lengths = row(lengthCard)
	local chosen = math.min(EVENT_MINUTES[minutesIndex], e.maxMinutes)
	for index, minutes in EVENT_MINUTES do
		if minutes <= e.maxMinutes then
			button(lengths, lengthText(minutes), 80, if index == minutesIndex then "gold" else nil, function()
				minutesIndex = index
				refresh()
			end)
		end
	end
	if EVENT_MINUTES[minutesIndex] > e.maxMinutes then
		label(
			lengthCard,
			`This event runs at most {lengthText(e.maxMinutes)}: it will run {lengthText(chosen)}.`,
			12,
			Theme.Colors.TextDim
		)
	end

	-- 2. Bonus rewards (only events that take them, only Owner / Admin).
	local rewardCard = card(body, "2. Bonus rewards (optional)")
	local allowedGroups = e.rewards
	if allowedGroups == nil then
		label(
			rewardCard,
			"This event's boost is the reward, so it takes no bonus rewards.",
			12,
			Theme.Colors.TextDim
		)
	elseif not can("items.grant") then
		label(rewardCard, "Only an Owner or Admin can add bonus rewards.", 12, Theme.Colors.TextDim)
	else
		label(
			rewardCard,
			`Given once to {EventRewards.RECIPIENTS[e.rewardTo or ""] or "the players who take part"}, on top of the event's usual prizes. Up to {EventRewards.MAX_ENTRIES}.`,
			12,
			Theme.Colors.TextDim
		)
		if table.find(allowedGroups, rewardGroup) == nil then
			rewardGroup = allowedGroups[1]
		end
		local tabs = row(rewardCard)
		for _, group in EventRewards.GROUP_ORDER do
			if table.find(allowedGroups, group) then
				button(
					tabs,
					EventRewards.GROUP_NAMES[group],
					150,
					if group == rewardGroup then "gold" else nil,
					function()
						rewardGroup = group
						refresh()
					end
				)
			end
		end
		local items = (EventRewards.GROUP_ITEMS :: any)[rewardGroup] :: { string }?
		if items then
			if table.find(items, rewardItem) == nil then
				rewardItem = items[1]
			end
			local pick = row(rewardCard)
			for _, id in items do
				local def = ItemDefinitions.stackable(id)
				button(
					pick,
					if def then `{def.glyph} {def.name}` else id,
					170,
					if rewardItem == id then "gold" else nil,
					function()
						rewardItem = id
						refresh()
					end
				)
			end
		elseif rewardGroup == "Sets" then
			local pick = row(rewardCard)
			for _, rarity in EventRewards.SET_RARITIES do
				button(pick, `{rarity} set`, 150, if rewardSet == rarity then "gold" else nil, function()
					rewardSet = rarity
					refresh()
				end)
			end
			label(
				rewardCard,
				"A complete set for the receiver's class at their level, fixed attributes.",
				11,
				Theme.Colors.TextDim
			)
		end
		local add = row(rewardCard)
		if rewardGroup ~= "Sets" then
			local quick: { number } = if rewardGroup == "MallPoints"
				then { 100, 250, 500, 1000 }
				else { 1, 3, 5, 10 }
			for _, n in quick do
				button(
					add,
					tostring(n),
					60,
					if fields.rewardCount == tostring(n) then "gold" else nil,
					function()
						fields.rewardCount = tostring(n)
						refresh()
					end
				)
			end
			field(add, "rewardCount", "or type", 90)
		end
		button(add, "+ Add", 90, "gold", function()
			if #eventRewards >= EventRewards.MAX_ENTRIES then
				setStatus(`❌ At most {EventRewards.MAX_ENTRIES} bonus rewards.`, true)
				return
			end
			local entry: EventRewards.Entry
			if rewardGroup == "Sets" then
				entry = { Kind = "Set", Id = rewardSet, Count = 1 }
			else
				local n = tonumber(fields.rewardCount or "")
				if n == nil or n < 1 or n % 1 ~= 0 then
					setStatus("❌ Pick or type an amount first.", true)
					return
				end
				entry = if rewardGroup == "MallPoints"
					then { Kind = "MallPoints", Count = n }
					else { Kind = "Item", Id = rewardItem, Count = n }
			end
			local ok, reason = EventRewards.validate({ entry }, allowedGroups)
			if not ok then
				setStatus(`❌ {EVENT_REASONS[`rewards:{reason}`] or reason}`, true)
				return
			end
			table.insert(eventRewards, entry)
			setStatus(`✅ Added {EventRewards.describeEntry(entry)}.`)
			refresh()
		end)
		if #eventRewards == 0 then
			label(rewardCard, "No bonus rewards added.", 12, Theme.Colors.TextDim)
		end
		for index, entry in eventRewards do
			local r = row(rewardCard)
			label(r, `🎁 {EventRewards.describeEntry(entry)}`, 13, Theme.Colors.Text, true).Size =
				UDim2.new(1, -110, 0, 0)
			button(r, "Remove", 96, "danger", function()
				table.remove(eventRewards, index)
				refresh()
			end)
		end
	end

	-- 3. When.
	local whenCard = card(body, "3. When")
	local rewards = if #eventRewards > 0 then eventRewards else nil
	local withText = if rewards then ` with {EventRewards.describe(rewards)}` else ""
	button(whenCard, `▶ Start now ({lengthText(chosen)})`, 240, "gold", function()
		if eventCall("Start", { Id = e.id, Minutes = chosen, Rewards = rewards }) then
			setStatus(`✅ {e.name} started for {lengthText(chosen)}{withText}.`)
			eventRewards = {}
			eventsFetched = nil
			refresh()
		end
	end)
	label(
		whenCard,
		"Or schedule it: pick a day, type the start time (your local time, 24-hour, e.g. 14:30).",
		12,
		Theme.Colors.TextDim
	)
	local days = row(whenCard)
	for day = 0, 6 do
		local text = if day == 0
			then "Today"
			elseif day == 1 then "Tomorrow"
			else DateTime.fromUnixTimestamp(os.time() + day * 86400):FormatLocalTime("ddd D", "en-us")
		button(days, text, 86, if day == eventDay then "gold" else nil, function()
			eventDay = day
			refresh()
		end)
	end
	local later = row(whenCard)
	label(later, "Start time:", 12, Theme.Colors.TextDim).Size = UDim2.fromOffset(80, 0)
	local timeBox = field(later, "eventTime", "e.g. 14:30", 100)
	local schedule = button(later, "📅 Schedule", 140, nil, function()
		local startsAt, problem = scheduledStart()
		if startsAt == nil then
			setStatus(`❌ {problem}`, true)
			return
		end
		if startsAt <= os.time() then
			setStatus(`❌ {localText(startsAt)} is already past: pick a later time or another day.`, true)
			return
		end
		if eventCall("Schedule", { Id = e.id, Minutes = chosen, StartsAt = startsAt, Rewards = rewards }) then
			setStatus(`✅ {e.name} scheduled for {localText(startsAt)} your time{withText}.`)
			eventRewards = {}
			eventsFetched = nil
			refresh()
		end
	end)
	local preview = label(whenCard, "", 12, Theme.Colors.TextDim)
	local function updatePreview()
		local startsAt, problem = scheduledStart()
		if startsAt == nil then
			preview.Text = if (fields.eventTime or "") == ""
				then "No start time typed yet."
				else problem or ""
			preview.TextColor3 = Theme.Colors.TextDim
		elseif startsAt <= now then
			preview.Text = `{localText(startsAt)} is already past: pick a later time or another day.`
			preview.TextColor3 = BAD_TEXT
		else
			preview.Text = `Starts {localText(startsAt)} your time (in {span(startsAt - now)}).`
			preview.TextColor3 = Theme.Colors.Safe
		end
		schedule.AutoButtonColor = startsAt ~= nil
	end
	timeBox:GetPropertyChangedSignal("Text"):Connect(updatePreview)
	updatePreview()
end

local function drawEvents(area: Frame)
	local body = scroller(area, `events:{eventPage or "list"}`, UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1))
	local listed = eventsFetched or eventCall("List", {})
	if listed == nil then
		return
	end
	eventsFetched = listed
	local e = if eventPage then EventDefinitions.get(eventPage) else nil
	if e then
		drawEventPage(body, listed, e)
	else
		drawEventList(body, listed)
	end
end

--------------------------------------------------------------------------------
-- Staff (D-112): panel-assigned Moderators / Game Masters and their pay
--------------------------------------------------------------------------------

local STAFF_REASONS = {
	permission = "only the Owner can approve or reject",
	self = "you can't assign yourself",
	codeStaff = "Owners and Admins are set in code",
	full = "the staff list is full",
	missing = "that person is not on the staff list",
	user = "enter a valid UserId",
	save = "the staff list could not be saved; try again",
}

local function staffCall(action: string, args: { [string]: any }): any
	local result = NetClient.invoke("AdminStaff", action, args)
	if type(result) ~= "table" then
		setStatus("❌ No answer from the server.", true)
		return nil
	end
	if result.ok == false then
		setStatus(`❌ Refused: {STAFF_REASONS[result.reason] or tostring(result.reason)}`, true)
		return nil
	end
	if result.staff then
		staffList = result.staff
		staffOwner = result.owner == true
	end
	return result
end

local function featureLine(perms: { string }): string
	local names = {}
	for _, p in perms do
		table.insert(names, StaffRules.FEATURE_NAMES[p] or p)
	end
	return table.concat(names, ", ")
end

local function salaryDraftOf(s: any): any
	if salaryDrafts[s.UserId] == nil then
		local items = {}
		for _, item in s.Salary.items or {} do
			table.insert(items, { id = item.id, count = item.count })
		end
		salaryDrafts[s.UserId] = {
			enabled = s.Salary.enabled == true,
			period = s.Salary.period or "Monthly",
			mallPoints = s.Salary.mallPoints or 0,
			items = items,
			setRarity = s.Salary.setRarity,
		}
	end
	return salaryDrafts[s.UserId]
end

local function drawStaffMember(body: Instance, s: any)
	local roleName = StaffRules.ROLE_NAMES[s.Role] or s.Role
	local member = card(body, `{s.Name} ({s.UserId}) · {roleName}`)
	if s.Status == "Pending" then
		label(member, "⏳ Waiting for the Owner's approval (no powers yet).", 12, Theme.Colors.GoldBright)
	end
	if s.Pending then
		local what = {}
		if s.Pending.role then
			table.insert(what, `role: {StaffRules.ROLE_NAMES[s.Pending.role] or s.Pending.role}`)
		end
		if s.Pending.perms then
			table.insert(what, `features: {featureLine(s.Pending.perms)}`)
		end
		label(
			member,
			`⏳ Change waiting for the Owner: {table.concat(what, "; ")}`,
			12,
			Theme.Colors.GoldBright
		)
	end
	if staffOwner and (s.Status == "Pending" or s.Pending) then
		local decide = row(member)
		button(decide, "✅ Approve", 120, "gold", function()
			if staffCall("Approve", { UserId = s.UserId }) then
				setStatus("✅ Approved.")
				refresh()
			end
		end)
		button(decide, "❌ Reject", 120, "danger", function()
			if staffCall("Reject", { UserId = s.UserId }) then
				setStatus("✅ Rejected.")
				refresh()
			end
		end)
	end
	label(
		member,
		if (s.LastSeen or 0) > 0
			then `Last seen {os.date("%Y-%m-%d", s.LastSeen)}`
			else "Not seen since assigned",
		12,
		Theme.Colors.TextDim
	)

	-- Features: one switch each, up to the role's ceiling.
	label(member, "Features", 13, Theme.Colors.Text, true)
	local features = row(member)
	local on: { [string]: boolean } = {}
	for _, p in s.Perms do
		on[p] = true
	end
	for _, p in StaffRules.CEILING[s.Role] or {} do
		local name = StaffRules.FEATURE_NAMES[p] or p
		local b = button(features, if on[p] then `✅ {name}` else `❌ {name}`, 170, nil, function()
			if p == "panel.open" then
				return
			end
			local perms = {}
			for _, q in StaffRules.CEILING[s.Role] do
				local want = if q == p then not on[q] else on[q] == true
				if want then
					table.insert(perms, q)
				end
			end
			if staffCall("SetPerms", { UserId = s.UserId, Perms = perms }) then
				setStatus(if staffOwner then "✅ Features saved." else "✅ Sent to the Owner for approval.")
				refresh()
			end
		end)
		if p == "panel.open" then
			b.AutoButtonColor = false
		end
	end

	-- Pay.
	local draft = salaryDraftOf(s)
	label(member, "Pay", 13, Theme.Colors.Text, true)
	local payRow = row(member)
	button(payRow, if draft.enabled then "✅ Pay on" else "❌ Pay off", 110, nil, function()
		draft.enabled = not draft.enabled
		refresh()
	end)
	button(payRow, `Every {if draft.period == "Weekly" then "week" else "month"}`, 130, nil, function()
		draft.period = if draft.period == "Weekly" then "Monthly" else "Weekly"
		refresh()
	end)
	local mpKey = `staffMp{s.UserId}`
	if fields[mpKey] == nil then
		fields[mpKey] = tostring(draft.mallPoints)
	end
	field(payRow, mpKey, "Mall Points", 110)
	label(payRow, "MP", 12, Theme.Colors.TextDim).Size = UDim2.fromOffset(28, 36)
	button(payRow, `Gear set: {draft.setRarity or "none"}`, 160, nil, function()
		local list = StaffRules.SET_RARITIES
		local index = if draft.setRarity then table.find(list, draft.setRarity) else nil
		draft.setRarity = if index == nil then list[1] elseif index < #list then list[index + 1] else nil
		refresh()
	end)
	for index, item in draft.items do
		local def = ItemDefinitions.stackable(item.id)
		local itemRow = row(member)
		label(itemRow, `{item.count} × {if def then def.name else item.id}`, 12).Size =
			UDim2.fromOffset(260, 30)
		button(itemRow, "Remove", 80, nil, function()
			table.remove(draft.items, index)
			refresh()
		end)
	end
	if #draft.items < StaffRules.MAX_SALARY_ITEMS then
		local addRow = row(member)
		local id = ItemDefinitions.STACKABLE_IDS[staffItemIndex] or ItemDefinitions.STACKABLE_IDS[1]
		local def = ItemDefinitions.stackable(id)
		button(addRow, `Item: {if def then def.name else id}`, 220, nil, function()
			staffItemIndex = staffItemIndex % #ItemDefinitions.STACKABLE_IDS + 1
			refresh()
		end)
		field(addRow, "staffItemCount", "Count", 70)
		button(addRow, "Add item", 100, nil, function()
			local count = math.floor(tonumber(fields.staffItemCount) or 0)
			if count < 1 or count > StaffRules.MAX_ITEM_COUNT then
				setStatus(`❌ Count must be 1 to {StaffRules.MAX_ITEM_COUNT}.`, true)
				return
			end
			table.insert(draft.items, { id = id, count = count })
			refresh()
		end)
	end
	local saveRow = row(member)
	button(saveRow, "Save pay", 120, "gold", function()
		local points = math.floor(tonumber(fields[mpKey]) or -1)
		if points < 0 or points > StaffRules.MAX_SALARY_POINTS then
			setStatus(`❌ Mall Points must be 0 to {StaffRules.MAX_SALARY_POINTS}.`, true)
			return
		end
		local items = {}
		for _, item in draft.items do
			table.insert(items, { Id = item.id, Count = item.count })
		end
		local result = staffCall("SetSalary", {
			UserId = s.UserId,
			Salary = {
				Enabled = draft.enabled,
				Period = draft.period,
				MallPoints = points,
				Items = items,
				SetRarity = draft.setRarity,
			},
		})
		if result then
			salaryDrafts[s.UserId] = nil
			setStatus("✅ Pay saved.")
			refresh()
		end
	end)
	local confirming = staffConfirmRemove == s.UserId
	button(
		saveRow,
		if confirming then "Tap again to remove" else "Remove from staff",
		170,
		"danger",
		function()
			if not confirming then
				staffConfirmRemove = s.UserId
				refresh()
				return
			end
			staffConfirmRemove = nil
			if staffCall("Remove", { UserId = s.UserId }) then
				salaryDrafts[s.UserId] = nil
				setStatus("✅ Removed from staff.")
				refresh()
			end
		end
	)
end

local function drawStaff(area: Frame)
	if staffList == nil then
		if staffCall("List", {}) == nil then
			staffList = {}
		end
	end
	local body = scroller(area, "staff", UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1))
	local add = card(
		body,
		"🛡️ Add staff",
		if staffOwner
			then "Enter the person's UserId (shown in the Players tab). Game Masters get the standard set: moderation, events, bosses, giving items and fixing quests. Pay is set per person below."
			else "Enter the person's UserId (shown in the Players tab). As an Admin, new staff and feature changes wait for the Owner's approval."
	)
	local addRow = row(add)
	field(addRow, "staffUser", "UserId", 160)
	for _, staffRole in StaffRules.ROLES do
		button(addRow, `Add as {StaffRules.ROLE_NAMES[staffRole]}`, 170, "gold", function()
			local userId = tonumber(fields.staffUser)
			if userId == nil or userId < 1 or userId % 1 ~= 0 then
				setStatus("❌ Enter a valid UserId.", true)
				return
			end
			if staffCall("Assign", { UserId = userId, Role = staffRole }) then
				fields.staffUser = ""
				setStatus(if staffOwner then "✅ Assigned." else "✅ Sent to the Owner for approval.")
				refresh()
			end
		end)
	end
	if #(staffList :: { any }) == 0 then
		label(body, "No panel staff yet.", 13, Theme.Colors.TextDim)
	end
	for _, s in staffList :: { any } do
		drawStaffMember(body, s)
	end
end

local function drawLog(area: Frame)
	local top = row(area)
	top.Size = UDim2.new(1, 0, 0, 36)
	top.AutomaticSize = Enum.AutomaticSize.None
	button(top, "Refresh", 100, nil, refresh)
	label(top, "Newest first. Saved permanently every minute.", 12, Theme.Colors.TextMuted).Size =
		UDim2.new(1, -110, 0, 0)
	local body = scroller(area, "log", UDim2.fromOffset(0, 42), UDim2.new(1, 0, 1, -42))
	local result = call("AdminAudit")
	if result == nil then
		return
	end
	setStatus(`✅ {#result.rows} log entries.`)
	if #result.rows == 0 then
		label(body, "No entries yet.", 12, Theme.Colors.TextDim)
	end
	for index, entry in result.rows do
		local line = Kit.new("Frame", {
			BackgroundColor3 = Theme.Colors.Ink,
			BackgroundTransparency = if index % 2 == 0 then 0.55 else 0.85,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = body,
		})
		Kit.corner(line, 6)
		Kit.padding(line, 6, 8)
		local list = Kit.list(line, Enum.FillDirection.Vertical, 2, Enum.HorizontalAlignment.Left)
		list.VerticalAlignment = Enum.VerticalAlignment.Top
		label(
			line,
			`{os.date("%H:%M:%S", entry.At)}   {entry.Action}   by {entry.Actor}{if entry.Target
				then `   on {entry.Target}`
				else ""}`,
			12,
			Theme.Colors.GoldBright,
			true
		)
		if entry.Details then
			label(line, tostring(entry.Details), 11, Theme.Colors.TextDim)
		end
	end
end

--------------------------------------------------------------------------------
-- Panel
--------------------------------------------------------------------------------

local function close()
	if panel then
		panel:Destroy()
	end
	panel, content, tabStrip, statusLabel = nil, nil, nil, nil
	Panels.closed("admin")
end

-- Redraws the tab strip and the area below it; the panel frame stays.
function refresh()
	local area, strip = content, tabStrip
	if area == nil or strip == nil then
		return
	end
	updateSaveBar = function() end
	clear(strip)
	Kit.list(strip, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Left)
	pageButtons(strip, TABS, tab, 104, function(id)
		if id ~= tab then
			tab = id
			eventsFetched = nil
			resetInfo = nil
			dailyDraft = nil
			staffList = nil
			salaryDrafts = {}
			eventPage = nil
			setStatus("")
			refresh()
		end
	end)
	clear(area)
	if tab == "Players" then
		drawPlayers(area)
	elseif tab == "Settings" then
		drawSettings(area)
	elseif tab == "Events" then
		drawEvents(area)
	elseif tab == "World" then
		drawWorld(area)
	elseif tab == "Staff" then
		drawStaff(area)
	else
		drawLog(area)
	end
end

local function build()
	if panel then
		panel:Destroy()
	end
	local layer = Panels.layer()
	local screen = layer.AbsoluteSize
	local w, h = math.min(screen.X - 16, 960), math.min(screen.Y - 16, 660)
	local frame = Kit.glassPanel({
		Name = "Admin",
		Active = true, -- sinks clicks, so nothing reaches the backdrop behind
		Position = UDim2.fromOffset((screen.X - w) / 2, (screen.Y - h) / 2),
		Size = UDim2.fromOffset(w, h),
		BackgroundTransparency = 0.02,
		Parent = layer,
	})
	panel = frame
	local title = Kit.label(`🛠 Admin panel`, 18, Theme.Fonts.Display, Theme.Colors.GoldBright)
	title.AutomaticSize = Enum.AutomaticSize.None
	title.Position = UDim2.fromOffset(14, 8)
	title.Size = UDim2.new(1, -120, 0, 26)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = frame
	local roleText = label(frame, `Signed in as {role}`, 11, Theme.Colors.TextMuted)
	roleText.Position = UDim2.fromOffset(14, 32)
	roleText.Size = UDim2.new(1, -120, 0, 14)
	roleText.AutomaticSize = Enum.AutomaticSize.None
	local shut = button(frame, "Close", 84, nil, close)
	shut.AnchorPoint = Vector2.new(1, 0)
	shut.Position = UDim2.new(1, -10, 0, 10)
	local strip = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, 50),
		Size = UDim2.new(1, -24, 0, 36),
		Parent = frame,
	})
	tabStrip = strip
	Kit.new("Frame", {
		BackgroundColor3 = Theme.Colors.Gold,
		BackgroundTransparency = 0.6,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(12, HEADER_H - 2),
		Size = UDim2.new(1, -24, 0, 1),
		Parent = frame,
	})
	content = Kit.new("Frame", {
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Position = UDim2.fromOffset(12, HEADER_H + 6),
		Size = UDim2.new(1, -24, 1, -(HEADER_H + 6 + FOOTER_H + 4)),
		Parent = frame,
	})
	local footer = Kit.label(status, 12, Theme.Fonts.BodyBold, Theme.Colors.Safe)
	footer.AutomaticSize = Enum.AutomaticSize.None
	footer.Position = UDim2.new(0, 14, 1, -FOOTER_H)
	footer.Size = UDim2.new(1, -28, 0, FOOTER_H - 6)
	footer.TextXAlignment = Enum.TextXAlignment.Left
	footer.TextTruncate = Enum.TextTruncate.AtEnd
	footer.Parent = frame
	statusLabel = footer
	setStatus(status, statusBad)
	refresh()
end

function AdminController.toggle()
	if role == nil then
		return
	end
	if panel then
		close()
		return
	end
	Panels.opened("admin")
	build()
end

local function makeButton()
	local layer = Kit.new("ScreenGui", {
		Name = "RC_AdminButton",
		ResetOnSpawn = false,
		-- In Roblox's top bar, last in the status row (TopBarLayout, D-98).
		ScreenInsets = Enum.ScreenInsets.TopbarSafeInsets,
		DisplayOrder = 6,
	})
	local b = Kit.new("TextButton", {
		Name = "Admin",
		Size = UDim2.fromOffset(44, 44),
		BackgroundColor3 = Theme.Colors.Glass,
		BackgroundTransparency = 0.15,
		Text = "🛠",
		TextSize = 22,
		FontFace = Theme.Fonts.BodyBold,
		TextColor3 = Theme.Colors.GoldBright,
		AutoButtonColor = true,
		Parent = layer,
	})
	Tooltip.attach(b, function()
		return "🛠 Admin panel", "Staff tools: players, settings, events, world and the log. Key: F2."
	end)
	Kit.corner(b, 22)
	Kit.goldStroke(b, 1.5, 0.2)
	b.Activated:Connect(AdminController.toggle)
	-- Its slot at the right end of the top-bar row (TopBarLayout.admin).
	local function place()
		local size = layer.AbsoluteSize
		local slot = if size.X >= 10 then TopBarLayout.compute(size.X, size.Y, true).admin else nil
		if slot then
			b.Position = UDim2.fromOffset(slot.x, slot.y)
			b.Size = UDim2.fromOffset(slot.w, slot.h)
			b.TextSize = math.floor(slot.h * 0.5)
		end
	end
	place()
	layer:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
	layer.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")
end

function AdminController:Init()
	-- Another panel opening closes this one; a backdrop tap does not (typed
	-- values would be lost).
	Panels.register("admin", close, true)
	NetClient.on("AdminHello", function(payload)
		if type(payload) ~= "table" or type(payload.Role) ~= "string" or role ~= nil then
			return
		end
		role = payload.Role
		-- Client-local, display only: the top bar keeps a slot for 🛠.
		local me = Players.LocalPlayer :: Player
		me:SetAttribute("RC_IsStaff", true)
		for _, permission in payload.Permissions or {} do
			permissions[permission] = true
		end
		makeButton()
		-- Keep the panel fitted when the screen size changes.
		Panels.layer():GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			if panel then
				build()
			end
		end)
	end)
end

function AdminController:Start()
	UserInputService.InputBegan:Connect(function(event, processed)
		if not processed and event.KeyCode == Enum.KeyCode.F2 then
			AdminController.toggle()
		end
	end)
end

return AdminController
