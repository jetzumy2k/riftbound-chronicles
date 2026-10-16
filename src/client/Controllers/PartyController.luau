--!strict
--[[
	PartyController — party panel, invite picker and invite popup (D-39).
	Intents only: PartyInvite / PartyRespond / PartyLeave / PartyKick; the
	server decides everything (PartyService).

	  Panel    left side under the HUD: each member's name, level and health
	           (bar + numbers), ★ marks the leader. The leader can remove a
	           member (×). Buttons: "+ Invite" and "Leave party".
	           Not in a party: a single "+ Party" button to invite someone.
	  Picker   players of your realm who are not in your party, each with an
	           Invite button (opened from "+ Invite" / "+ Party").
	  Popup    "<name> invites you to a party" with Accept / Decline and a
	           countdown; never covers the centre of the screen.

	Mobile: buttons ≥ 44 px tall, panels in the safe area, state in text.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local NetClient = require(Shared.Net.Client)

local UI = script.Parent.Parent.UI
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)

local PANEL_WIDTH = 210
local ROW_HEIGHT = 40
local LEADER_MARK = "★"

local PartyController = {}

type Roster = { { userId: number, leader: boolean } }

local localPlayer = Players.LocalPlayer :: Player
local roster: Roster = {}
local maxMembers = 4
local isLeader = false

local gui: ScreenGui
local panel: Frame
local rows: Frame
local inviteButton: TextButton
local leaveButton: TextButton
local startButton: TextButton
local picker: Frame
local pickerList: ScrollingFrame
local popup: Frame
local popupText: TextLabel
local popupFrom: Player? = nil
local popupUntil = 0

local function smallButton(textValue: string, color: Color3, width: number): TextButton
	local button = Kit.new("TextButton", {
		Size = UDim2.fromOffset(width, 44),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.1,
		Text = textValue,
		TextSize = 14,
		FontFace = Theme.Fonts.BodyBold,
		TextColor3 = Color3.new(1, 1, 1),
		AutoButtonColor = true,
	})
	Kit.corner(button, 10)
	Kit.new("UIStroke", { Color = Theme.Colors.Gold, Thickness = 1, Transparency = 0.5, Parent = button })
	return button
end

local GOLD_BUTTON = Color3.fromRGB(120, 92, 40)
local DARK_BUTTON = Color3.fromRGB(46, 40, 62)
local RED_BUTTON = Color3.fromRGB(150, 40, 44)
local GREEN_BUTTON = Color3.fromRGB(40, 120, 80)

local function inParty(): boolean
	return #roster > 0
end

local function memberUserIds(): { [number]: boolean }
	local set = {}
	for _, member in roster do
		set[member.userId] = true
	end
	return set
end

--------------------------------------------------------------------------------
-- Party panel
--------------------------------------------------------------------------------

local function memberRow(entry: { userId: number, leader: boolean }, order: number)
	local player = Players:GetPlayerByUserId(entry.userId)
	local row = Kit.new("Frame", {
		BackgroundColor3 = Theme.Colors.GlassRaised,
		BackgroundTransparency = 0.35,
		Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
		LayoutOrder = order,
		Parent = rows,
	})
	Kit.corner(row, 8)
	local canKick = isLeader and entry.userId ~= localPlayer.UserId
	local name = Kit.label("", 13, Theme.Fonts.BodyBold, Theme.Colors.Text)
	name.Position = UDim2.fromOffset(8, 3)
	name.Size = UDim2.new(1, if canKick then -56 else -16, 0, 16)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Parent = row
	local barTrack = Kit.new("Frame", {
		BackgroundColor3 = Theme.Colors.Ink,
		BackgroundTransparency = 0.2,
		Position = UDim2.fromOffset(8, 22),
		Size = UDim2.new(1, if canKick then -56 else -16, 0, 12),
		Parent = row,
	})
	Kit.corner(barTrack, 6)
	local fill = Kit.new(
		"Frame",
		{ BackgroundColor3 = Color3.fromRGB(80, 200, 120), Size = UDim2.fromScale(1, 1), Parent = barTrack }
	)
	Kit.corner(fill, 6)
	local hpText = Kit.label("", 10, Theme.Fonts.BodyBold, Theme.Colors.Text)
	hpText.Size = UDim2.fromScale(1, 1)
	hpText.ZIndex = 3
	hpText.Parent = barTrack

	if canKick and player then
		local kick = smallButton("×", RED_BUTTON, 40)
		kick.Size = UDim2.fromOffset(40, 36)
		kick.AnchorPoint = Vector2.new(1, 0.5)
		kick.Position = UDim2.new(1, -4, 0.5, 0)
		kick.TextSize = 20
		kick.Parent = row
		kick.Activated:Connect(function()
			NetClient.fire("PartyKick", player)
		end)
	end

	-- Live name / level / health from replicated attributes.
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function()
		if row.Parent == nil then
			connection:Disconnect()
			return
		end
		local who = Players:GetPlayerByUserId(entry.userId)
		if who == nil then
			name.Text = "(left)"
			return
		end
		local level = who:GetAttribute("Level")
		name.Text = `{if entry.leader then LEADER_MARK .. " " else ""}{who.DisplayName}  Lv {if type(level)
				== "number"
			then level
			else "?"}`
		local character = who.Character
		local hp = character and character:GetAttribute("HP")
		local maxHp = character and character:GetAttribute("MaxHP")
		local defeated = character and character:GetAttribute("Defeated") == true
		if type(hp) == "number" and type(maxHp) == "number" and maxHp > 0 then
			fill.Size = UDim2.fromScale(math.clamp(hp / maxHp, 0, 1), 1)
			hpText.Text = if defeated then "Defeated" else `{hp}/{maxHp}`
		else
			hpText.Text = ""
		end
	end)
end

local function renderPanel()
	for _, child in rows:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local party = inParty()
	rows.Visible = party
	leaveButton.Visible = party
	inviteButton.Visible = party and isLeader and #roster < maxMembers
	startButton.Visible = not party
	if party then
		for index, entry in roster do
			memberRow(entry, index)
		end
	end
end

--------------------------------------------------------------------------------
-- Invite picker
--------------------------------------------------------------------------------

local function renderPicker()
	for _, child in pickerList:GetChildren() do
		if child:IsA("Frame") or child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	local members = memberUserIds()
	local myRace = localPlayer:GetAttribute("Race")
	local count = 0
	for _, other in Players:GetPlayers() do
		if other == localPlayer or members[other.UserId] or other:GetAttribute("Race") ~= myRace then
			continue
		end
		count += 1
		local row = Kit.new("Frame", {
			BackgroundColor3 = Theme.Colors.GlassRaised,
			BackgroundTransparency = 0.3,
			Size = UDim2.new(1, -6, 0, 48),
			LayoutOrder = count,
			Parent = pickerList,
		})
		Kit.corner(row, 8)
		local level = other:GetAttribute("Level")
		local label = Kit.label(
			`{other.DisplayName}  Lv {if type(level) == "number" then level else "?"}`,
			14,
			Theme.Fonts.BodyBold,
			Theme.Colors.Text
		)
		label.Position = UDim2.fromOffset(10, 0)
		label.Size = UDim2.new(1, -110, 1, 0)
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.Parent = row
		local invite = smallButton("Invite", GOLD_BUTTON, 88)
		invite.AnchorPoint = Vector2.new(1, 0.5)
		invite.Position = UDim2.new(1, -2, 0.5, 0)
		invite.Parent = row
		invite.Activated:Connect(function()
			NetClient.fire("PartyInvite", other)
			invite.Text = "Sent"
			invite.Active = false
			invite.AutoButtonColor = false
			invite.BackgroundColor3 = DARK_BUTTON
		end)
	end
	if count == 0 then
		local empty = Kit.label(
			"No other players of your realm are online right now.",
			13,
			Theme.Fonts.Body,
			Theme.Colors.TextDim
		)
		empty.Size = UDim2.new(1, -6, 0, 40)
		empty.TextWrapped = true
		empty.Parent = pickerList
	end
end

local function openPicker()
	picker.Visible = true
	renderPicker()
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

local function build()
	gui = Kit.new("ScreenGui", {
		Name = "RC_Party",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		DisplayOrder = 6,
	})

	-- Panel: left side, under the HUD.
	panel = Kit.new("Frame", {
		Name = "Party",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, 168),
		Size = UDim2.fromOffset(PANEL_WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = gui,
	})
	local panelLayout = Kit.list(panel, Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Left)
	panelLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	rows = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		Visible = false,
		Parent = panel,
	})
	local rowsLayout = Kit.list(rows, Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Left)
	rowsLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	local buttons = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 44),
		LayoutOrder = 2,
		Parent = panel,
	})
	local buttonsLayout = Kit.list(buttons, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Left)
	buttonsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	startButton = smallButton("+ Party", DARK_BUTTON, 92)
	startButton.Parent = buttons
	startButton.Activated:Connect(openPicker)
	inviteButton = smallButton("+ Invite", GOLD_BUTTON, 92)
	inviteButton.Parent = buttons
	inviteButton.Activated:Connect(openPicker)
	leaveButton = smallButton("Leave party", RED_BUTTON, 108)
	leaveButton.Parent = buttons
	leaveButton.Activated:Connect(function()
		NetClient.fire("PartyLeave")
	end)

	-- Picker: a centred list while open (closes on Close or after inviting).
	picker = Kit.glassPanel({
		Name = "Picker",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.9, 0.7),
		Visible = false,
		Parent = gui,
	})
	Kit.new("UISizeConstraint", { MaxSize = Vector2.new(360, 420), Parent = picker })
	Kit.padding(picker, 10, 12)
	local pickerTitle = Kit.label("Invite to your party", 16, Theme.Fonts.Display, Theme.Colors.GoldBright)
	pickerTitle.Size = UDim2.new(1, -60, 0, 44)
	pickerTitle.TextXAlignment = Enum.TextXAlignment.Left
	pickerTitle.Parent = picker
	local close = smallButton("Close", DARK_BUTTON, 64)
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.fromScale(1, 0)
	close.Parent = picker
	close.Activated:Connect(function()
		picker.Visible = false
	end)
	pickerList = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 52),
		Size = UDim2.new(1, 0, 1, -52),
		CanvasSize = UDim2.fromScale(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = picker,
	})
	local listLayout = Kit.list(pickerList, Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Left)
	listLayout.VerticalAlignment = Enum.VerticalAlignment.Top

	-- Invite popup: top centre, under the toasts.
	popup = Kit.glassPanel({
		Name = "Invite",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 64),
		Size = UDim2.fromOffset(320, 104),
		Visible = false,
		Parent = gui,
	})
	Kit.padding(popup, 8, 10)
	popupText = Kit.label("", 14, Theme.Fonts.BodyBold, Theme.Colors.Text)
	popupText.Size = UDim2.new(1, 0, 0, 40)
	popupText.TextWrapped = true
	popupText.Parent = popup
	local accept = smallButton("Accept", GREEN_BUTTON, 120)
	accept.Position = UDim2.fromOffset(0, 44)
	accept.Parent = popup
	local decline = smallButton("Decline", RED_BUTTON, 120)
	decline.AnchorPoint = Vector2.new(1, 0)
	decline.Position = UDim2.new(1, 0, 0, 44)
	decline.Parent = popup
	local function answer(yes: boolean)
		local from = popupFrom
		popup.Visible = false
		popupFrom = nil
		if from then
			NetClient.fire("PartyRespond", from, yes)
		end
	end
	accept.Activated:Connect(function()
		answer(true)
	end)
	decline.Activated:Connect(function()
		answer(false)
	end)

	gui.Parent = localPlayer:WaitForChild("PlayerGui")
end

function PartyController:Start()
	build()
	renderPanel()
	NetClient.on("PartyState", function(state)
		if type(state) ~= "table" or type(state.members) ~= "table" then
			return
		end
		roster = state.members
		maxMembers = state.maxMembers or 4
		isLeader = false
		for _, entry in roster do
			if entry.userId == localPlayer.UserId and entry.leader then
				isLeader = true
			end
		end
		renderPanel()
		if picker.Visible then
			renderPicker()
		end
	end)
	NetClient.on("PartyInvited", function(payload)
		if type(payload) ~= "table" then
			return
		end
		local from = Players:GetPlayerByUserId(payload.fromUserId)
		if from == nil then
			return
		end
		popupFrom = from
		popupUntil = os.clock() + (payload.expiresIn or 30)
		popup.Visible = true
	end)
	-- Popup countdown; the panel is hidden until a job is chosen.
	RunService.Heartbeat:Connect(function()
		panel.Visible = localPlayer:GetAttribute("Job") ~= nil
		if popup.Visible then
			local from = popupFrom
			local left = math.ceil(popupUntil - os.clock())
			if from == nil or left <= 0 or from.Parent ~= Players then
				popup.Visible = false
				popupFrom = nil
			else
				popupText.Text = `{from.DisplayName} invites you to a party ({left}s)`
			end
		end
	end)
end

return PartyController
