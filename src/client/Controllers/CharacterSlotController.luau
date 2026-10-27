--!strict
--[[
	CharacterSlotController — the character screen (creator request
	2026-10-27, PLAN.md D-115). Opened from the Bag's "Characters" button.

	Up to 4 characters, all of the account's realm. Each card shows the
	class and level; the one being played is marked. Play switches to it,
	Create starts a new character in an empty slot (the class screen opens
	after the rejoin), Delete needs DELETE typed in the box. The server
	decides everything (CharacterService); this only shows and asks.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local JobDefinitions = require(Shared.Definitions.JobDefinitions)
local RaceDefinitions = require(Shared.Definitions.RaceDefinitions)
local Enums = require(Shared.Enums)
local NetClient = require(Shared.Net.Client)

local UI = script.Parent.Parent.UI
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)
local Panels = require(UI.Panels)
local InventoryController = require(script.Parent.InventoryController)

local CharacterSlotController = {}

local REASONS = {
	combat = "Leave combat first.",
	confirm = "Type DELETE (capitals) in the box first.",
	backup = "Couldn't save a safety copy; nothing was deleted. Try again.",
	busy = "Already switching...",
	same = "You are already playing this character.",
	empty = "That slot is empty.",
	noRune = "You need a Race Conversion Rune (Item Mall).",
	pending = "A realm change is already waiting for your rejoin.",
	RateLimited = "Too many requests; wait a few seconds.",
	BadArgs = "That request was not accepted.",
	BadState = "Wait until your character has loaded.",
	HandlerError = "Something went wrong on the server; try again.",
}

local BAD = Color3.fromRGB(255, 140, 130)

local panel: Frame? = nil
-- Everything inside the panel (redrawn; the panel's own look stays).
local content: Frame? = nil
local listed: any = nil
local confirmText = ""
local deleting: number? = nil
local status = ""
-- D-116: showing the Race Conversion Rune screen instead of the slots.
local runeMode = false
local statusBad = false

local render: () -> ()
local drawRune: (frame: Frame, race: string) -> ()

local function close()
	if panel then
		panel:Destroy()
		panel = nil
		content = nil
		runeMode = false
		Panels.closed("characters")
	end
end

local function setStatus(text: string, bad: boolean?)
	status, statusBad = text, bad == true
end

local function call(action: string, slot: number?, confirm: string?): any
	local result = NetClient.invoke("CharacterSlots", action, slot, confirm)
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

local function button(
	parent: Instance,
	text: string,
	width: number,
	color: Color3?,
	onClick: () -> ()
): TextButton
	local b = Kit.new("TextButton", {
		Size = UDim2.fromOffset(width, 40),
		BackgroundColor3 = color or Theme.Colors.GlassHighlight,
		BackgroundTransparency = if color then 0.05 else 0.3,
		Text = text,
		TextSize = 14,
		FontFace = Theme.Fonts.BodyBold,
		TextColor3 = if color == Theme.Colors.Gold then Theme.Colors.Ink else Theme.Colors.Text,
		AutoButtonColor = true,
		Parent = parent,
	})
	Kit.corner(b, 8)
	b.Activated:Connect(onClick)
	return b
end

local function text(parent: Instance, body: string, size: number, color: Color3, bold: boolean?): TextLabel
	return Kit.new("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = body,
		TextSize = size,
		FontFace = if bold then Theme.Fonts.BodyBold else Theme.Fonts.Body,
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Parent = parent,
	})
end

local function slotCard(parent: Instance, s: any)
	local card = Kit.new("Frame", {
		BackgroundColor3 = if s.Active then Theme.Colors.GlassRaised else Theme.Colors.Ink,
		BackgroundTransparency = if s.Active then 0.15 else 0.4,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = parent,
	})
	Kit.corner(card, 10)
	Kit.padding(card, 10, 12)
	if s.Active then
		Kit.goldStroke(card, 1.5, 0.2)
	end
	Kit.list(card, Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Left)
	local job = if s.Job then JobDefinitions.get(s.Job) else nil
	local title = if s.Empty
		then `Slot {s.Slot} · Empty`
		else `Slot {s.Slot} · {if job then job.displayName else s.Job} · Level {s.Level or 0}`
	text(card, title, 15, if s.Empty then Theme.Colors.TextDim else Theme.Colors.GoldBright, true)
	if s.Active and not s.Empty then
		text(card, "▶ Playing now", 12, Theme.Colors.Safe, true)
	end
	local row = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = card,
	})
	local layout = Kit.list(row, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left)
	layout.Wraps = true
	if not s.Active then
		button(row, if s.Empty then "➕ Create" else "Play", 110, Theme.Colors.Gold, function()
			if call("Switch", s.Slot) then
				setStatus("Saving and switching: the game will reload.")
				render()
			else
				render()
			end
		end)
	end
	if not s.Empty then
		button(row, if deleting == s.Slot then "Cancel" else "Delete", 100, nil, function()
			deleting = if deleting == s.Slot then nil else s.Slot
			confirmText = ""
			setStatus("")
			render()
		end)
	end
	if deleting == s.Slot then
		local count = 0
		for _, other in listed.slots do
			if not other.Empty then
				count += 1
			end
		end
		text(
			card,
			if count <= 1
				then "This is your last character. Deleting it is permanent and lets you choose a new realm, like a new player."
				else "Deleting is permanent: level, gear, bag and Gold of this character are lost. Mall Points stay with your account.",
			12,
			Theme.Colors.TextDim
		)
		local confirmRow = Kit.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = card,
		})
		Kit.list(confirmRow, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left)
		local box = Kit.new("TextBox", {
			Size = UDim2.fromOffset(150, 40),
			BackgroundColor3 = Theme.Colors.Ink,
			BackgroundTransparency = 0.1,
			PlaceholderText = "Type DELETE",
			PlaceholderColor3 = Theme.Colors.TextMuted,
			Text = confirmText,
			TextSize = 14,
			FontFace = Theme.Fonts.Body,
			TextColor3 = Theme.Colors.Text,
			ClearTextOnFocus = false,
			Parent = confirmRow,
		})
		Kit.corner(box, 8)
		box:GetPropertyChangedSignal("Text"):Connect(function()
			confirmText = box.Text
		end)
		button(confirmRow, "Delete forever", 140, Color3.fromRGB(170, 50, 50), function()
			local result = call("Delete", s.Slot, confirmText)
			deleting = nil
			confirmText = ""
			if result then
				if result.rejoin then
					setStatus("Character deleted. The game will reload.")
				else
					listed = result
					setStatus("Character deleted.")
				end
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
	if runeMode then
		if listed and listed.race then
			drawRune(frame, listed.race)
		else
			text(frame, "Loading...", 13, Theme.Colors.TextDim).Position = UDim2.fromOffset(14, 14)
		end
		return
	end
	local title = Kit.label("👥 Characters", 18, Theme.Fonts.Display, Theme.Colors.GoldBright)
	title.AutomaticSize = Enum.AutomaticSize.None
	title.Position = UDim2.fromOffset(14, 10)
	title.Size = UDim2.new(1, -110, 0, 26)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = frame
	local closeButton = button(frame, "Close", 80, nil, close)
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, -10, 0, 8)
	local note = text(
		frame,
		`Up to {if listed then listed.max else 4} characters, all of your realm. One is played at a time; switching saves and reloads the game.`,
		12,
		Theme.Colors.TextDim
	)
	note.Position = UDim2.fromOffset(14, 40)
	note.Size = UDim2.new(1, -28, 0, 0)
	local statusLabel = text(frame, status, 13, if statusBad then BAD else Theme.Colors.Safe, true)
	statusLabel.AnchorPoint = Vector2.new(0, 1)
	statusLabel.Position = UDim2.new(0, 14, 1, -8)
	statusLabel.Size = UDim2.new(1, -28, 0, 0)
	local scroll = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, 84),
		Size = UDim2.new(1, -20, 1, -120),
		CanvasSize = UDim2.fromScale(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = frame,
	})
	Kit.list(scroll, Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Left)
	if listed == nil then
		text(scroll, "Loading...", 13, Theme.Colors.TextDim)
		return
	end
	for _, s in listed.slots do
		slotCard(scroll, s)
	end
end

function CharacterSlotController.open()
	if panel then
		return
	end
	InventoryController.setOpen(false)
	Panels.opened("characters")
	local layer = Panels.layer()
	local screen = layer.AbsoluteSize
	local w, h = math.min(screen.X - 16, 520), math.min(screen.Y - 16, 560)
	panel = Kit.glassPanel({
		Name = "Characters",
		Active = true,
		Position = UDim2.fromOffset((screen.X - w) / 2, (screen.Y - h) / 2),
		Size = UDim2.fromOffset(w, h),
		Parent = layer,
	})
	content = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = panel,
	})
	listed, deleting, confirmText = nil, nil, ""
	setStatus("")
	render()
	task.spawn(function()
		local result = call("List")
		if result then
			listed = result
		end
		render()
	end)
end

-- D-116: the Race Conversion Rune screen (in the same panel).
function drawRune(frame: Frame, race: string)
	local target: string? = nil
	for _, r in Enums.Race do
		if r ~= race then
			target = r
		end
	end
	local from = RaceDefinitions.get(race)
	local to = if target then RaceDefinitions.get(target) else nil
	local title = Kit.label("🔮 Race Conversion Rune", 18, Theme.Fonts.Display, Theme.Colors.GoldBright)
	title.AutomaticSize = Enum.AutomaticSize.None
	title.Position = UDim2.fromOffset(14, 10)
	title.Size = UDim2.new(1, -110, 0, 26)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = frame
	local closeButton = button(frame, "Close", 80, nil, close)
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, -10, 0, 8)
	local body = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(14, 48),
		Size = UDim2.new(1, -28, 1, -56),
		Parent = frame,
	})
	Kit.list(body, Enum.FillDirection.Vertical, 10, Enum.HorizontalAlignment.Left)
	text(
		body,
		`{if from then from.displayName else race}  →  {if to then to.displayName else "?"}`,
		20,
		Theme.Colors.GoldBright,
		true
	)
	text(
		body,
		"Every character on your account moves to the new realm after you rejoin. Levels, skills, gear, weapons, bag, Gold, quests and Mall Points are all kept; your gear takes the new realm's look and your face resets to the realm's default (you can change your head style any time). One rune is used. This can only be undone with another rune.",
		13,
		Theme.Colors.Text
	)
	local row = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = body,
	})
	Kit.list(row, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left)
	local box = Kit.new("TextBox", {
		Size = UDim2.fromOffset(160, 40),
		BackgroundColor3 = Theme.Colors.Ink,
		BackgroundTransparency = 0.1,
		PlaceholderText = "Type CONVERT",
		PlaceholderColor3 = Theme.Colors.TextMuted,
		Text = confirmText,
		TextSize = 14,
		FontFace = Theme.Fonts.Body,
		TextColor3 = Theme.Colors.Text,
		ClearTextOnFocus = false,
		Parent = row,
	})
	Kit.corner(box, 8)
	box:GetPropertyChangedSignal("Text"):Connect(function()
		confirmText = box.Text
	end)
	button(row, "Convert my account", 180, Theme.Colors.Gold, function()
		if target == nil then
			return
		end
		if confirmText ~= "CONVERT" then
			setStatus("Type CONVERT (capitals) in the box first.", true)
			render()
			return
		end
		local result = NetClient.invoke("ConvertRace", target, confirmText)
		confirmText = ""
		if type(result) == "table" and result.ok then
			setStatus("Rune used. The game will reload in your new realm.")
		elseif type(result) == "table" then
			setStatus(
				REASONS[result.reason or result.code] or `Refused ({tostring(result.reason or result.code)}).`,
				true
			)
		else
			setStatus("No answer from the server.", true)
		end
		render()
	end)
	local statusLabel = text(body, status, 13, if statusBad then BAD else Theme.Colors.Safe, true)
	statusLabel.LayoutOrder = 99
end

function CharacterSlotController.openRaceRune()
	if panel then
		close()
	end
	CharacterSlotController.open()
	runeMode = true
	render()
end

function CharacterSlotController:Start()
	Panels.register("characters", close)
	InventoryController.OpenCharacters = CharacterSlotController.open
	InventoryController.OpenRaceRune = CharacterSlotController.openRaceRune
end

return CharacterSlotController
