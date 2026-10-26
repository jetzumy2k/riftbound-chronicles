--!strict
--[[
	EventController — live events on the player's screen (Phase 18, PLAN.md
	D-89). Display only: the server decides what an event changes.

	Reads the ReplicatedStorage attribute RC_Events (JSON [{Id, EndsAt}],
	EventService) and:
	  - announces each event that starts ("Event started: ✨ Double EXP
	    Weekend. All EXP from creatures is doubled.") and ends, as toasts;
	    on joining, running events are listed once ("Event running: ...");
	  - shows a chip at the top centre while any event runs: the events'
	    icons and the time left on the soonest to end. Tapping it opens
	    the event board (D-92): every running event with its time left,
	    what it does, and its live state from the RC_EventBoard attribute
	    (treasure clues, realm / tournament scores, defense waves, the
	    parade's 5 minutes).
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EventDefinitions = require(Shared.Definitions.EventDefinitions)
local EventRewards = require(Shared.Logic.EventRewards)
local TopBarLayout = require(Shared.Layout.TopBarLayout)

local UI = script.Parent.Parent.UI
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)
local Panels = require(UI.Panels)
local Tooltip = require(UI.Tooltip)
local NotificationController = require(script.Parent.NotificationController)

local ATTRIBUTE = "RC_Events"
local BOARD = "RC_EventBoard"

local EventController = {}

type Running = { Id: string, EndsAt: number, Rewards: { any }? }

local running: { Running } = {}
local seen: { [string]: boolean }? = nil
local chip: TextButton? = nil
-- Phase 19 (D-94): the chip's short form on crowded screens.
local compact = false
local board: Frame? = nil
local drawBoard: () -> ()

local function boardData(): { [string]: any }
	local raw = ReplicatedStorage:GetAttribute(BOARD)
	local ok, data = pcall(HttpService.JSONDecode, HttpService, if type(raw) == "string" then raw else "{}")
	return if ok and type(data) == "table" then data else {}
end

-- Live lines for event `id` from the board (scores, clues, waves).
local function liveLines(id: string, data: any): { string }
	local lines = {}
	if type(data) ~= "table" then
		return lines
	end
	if id == "TreasureHunt" and type(data.clues) == "table" then
		for index, clue in data.clues do
			table.insert(lines, `Chest {index}: {clue}`)
		end
		table.insert(lines, "Find all 5 for the title Treasure Seeker.")
	elseif id == "HiddenChestHunt" then
		table.insert(
			lines,
			`{data.total or 12} chests are hidden around both war zones. Find 8 for the title Keen Eye.`
		)
	elseif id == "RaceChallenge" then
		table.insert(lines, `Angels {data.Angel or 0}  :  {data.Devil or 0} Devils (war-zone victories)`)
		table.insert(lines, "Everyone who wins a fight is paid at the end; the winning realm more.")
	elseif id == "CrossRaceTournament" then
		if type(data.top) == "table" and #data.top > 0 then
			for place, entry in data.top do
				table.insert(lines, `{place}. {entry.name}: {entry.score}`)
			end
		else
			table.insert(lines, "No victories yet. The top 3 are paid at the end.")
		end
	elseif id == "AngelDefense" or id == "DevilDefense" then
		table.insert(
			lines,
			`Wave {data.wave or 0} of {data.waves or 5} · {data.kills or 0} creatures defeated`
		)
		table.insert(lines, "Fight them in your training yard; every defender is paid at the end.")
	elseif id == "CosmeticParade" then
		table.insert(
			lines,
			`Spend {math.floor((data.seconds or 300) / 60)} minutes in a capital for the title Parade Star.`
		)
	end
	return lines
end

local function decode(): { Running }
	local raw = ReplicatedStorage:GetAttribute(ATTRIBUTE)
	if type(raw) ~= "string" then
		return {}
	end
	local ok, list = pcall(HttpService.JSONDecode, HttpService, raw)
	if not ok or type(list) ~= "table" then
		return {}
	end
	local out = {}
	for _, entry in list do
		if type(entry) == "table" and EventDefinitions.get(entry.Id) and type(entry.EndsAt) == "number" then
			table.insert(out, {
				Id = entry.Id,
				EndsAt = entry.EndsAt,
				Rewards = if type(entry.Rewards) == "table" then entry.Rewards else nil,
			})
		end
	end
	return out
end

local function left(endsAt: number): string
	local seconds = math.max(0, endsAt - Workspace:GetServerTimeNow())
	local days = seconds // 86400
	local hours = (seconds % 86400) // 3600
	local minutes = (seconds % 3600) // 60
	if days > 0 then
		return `{days}d {hours}h`
	elseif hours > 0 then
		return `{hours}h {minutes}m`
	end
	return `{math.max(1, minutes)}m`
end

local function render()
	local button = chip
	if button == nil then
		return
	end
	if #running == 0 then
		button.Visible = false
		return
	end
	local icons = {}
	local soonest = math.huge
	for _, entry in running do
		local e = EventDefinitions.get(entry.Id) :: EventDefinitions.Event
		table.insert(icons, e.icon)
		soonest = math.min(soonest, entry.EndsAt)
	end
	button.Text = if compact
		then `🎉{#running} {left(soonest)}`
		else `🎉 {table.concat(icons, " ")}  ·  {left(soonest)}`
	button.Visible = true
end

local function update()
	local now = decode()
	local ids: { [string]: boolean } = {}
	for _, entry in now do
		ids[entry.Id] = true
	end
	local before = seen
	if before == nil then
		-- Just joined: list what is already running, once.
		for _, entry in now do
			local e = EventDefinitions.get(entry.Id) :: EventDefinitions.Event
			NotificationController:ShowKey(
				"Info",
				"event.running",
				{ name = `{e.icon} {e.name}`, left = left(entry.EndsAt) }
			)
		end
	else
		for _, entry in now do
			if not before[entry.Id] then
				local e = EventDefinitions.get(entry.Id) :: EventDefinitions.Event
				NotificationController:ShowKey(
					"Info",
					"event.started",
					{ name = `{e.icon} {e.name}`, blurb = e.blurb }
				)
			end
		end
		for id in before do
			if not ids[id] then
				local e = EventDefinitions.get(id) :: EventDefinitions.Event
				NotificationController:ShowKey("Info", "event.ended", { name = `{e.icon} {e.name}` })
			end
		end
	end
	seen = ids
	running = now
	render()
	if board then
		drawBoard()
	end
end

local function build()
	local gui = Kit.new("ScreenGui", {
		Name = "RC_Events",
		ResetOnSpawn = false,
		-- In Roblox's top bar with the status row (TopBarLayout, D-98).
		ScreenInsets = Enum.ScreenInsets.TopbarSafeInsets,
		-- Under the toasts (20), which may briefly cover it.
		DisplayOrder = 8,
	})
	local button = Kit.new("TextButton", {
		Name = "Events",
		-- Placed in its top-bar slot by TopBarLayout (D-98).
		Position = UDim2.fromOffset(8, 6),
		Size = UDim2.fromOffset(150, 36),
		TextTruncate = Enum.TextTruncate.AtEnd,
		BackgroundColor3 = Theme.Colors.Glass,
		BackgroundTransparency = 0.15,
		Text = "",
		TextSize = 14,
		FontFace = Theme.Fonts.BodyBold,
		TextColor3 = Theme.Colors.GoldBright,
		AutoButtonColor = true,
		Visible = false,
		Parent = gui,
	})
	Kit.corner(button, 22)
	Tooltip.attach(button, function()
		local names = {}
		for _, entry in running do
			local e = EventDefinitions.get(entry.Id) :: EventDefinitions.Event
			table.insert(names, `{e.icon} {e.name} ({left(entry.EndsAt)} left)`)
		end
		return "🎉 Live events", `{table.concat(names, "\n")}\nTap for details.`
	end)
	Kit.goldStroke(button, 1.5, 0.2)
	Kit.padding(button, 0, 12)
	local limit = Kit.new("UISizeConstraint", { Parent = button })
	local function fit()
		local size = gui.AbsoluteSize
		if size.X < 10 then
			return
		end
		local layout = TopBarLayout.compute(
			size.X,
			size.Y,
			(Players.LocalPlayer :: Player):GetAttribute("RC_IsStaff") == true
		)
		button.Position = UDim2.fromOffset(layout.events.x, layout.events.y)
		button.Size = UDim2.fromOffset(layout.events.w, layout.events.h)
		limit.MaxSize = Vector2.new(layout.events.w, layout.events.h)
		compact = layout.compact
		render()
	end
	local me = Players.LocalPlayer :: Player
	me:GetAttributeChangedSignal("RC_IsStaff"):Connect(fit)
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()
	button.Activated:Connect(function()
		if board then
			EventController.closeBoard()
		else
			Panels.opened("events")
			drawBoard()
		end
	end)
	gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")
	chip = button
end

function EventController.closeBoard()
	if board then
		board:Destroy()
		board = nil
		Panels.closed("events")
	end
end

-- The event board: every running event, its time left and live state.
function drawBoard()
	local old = board
	if old then
		old:Destroy()
	end
	local layer = Panels.layer()
	local screen = layer.AbsoluteSize
	local w, h = math.min(screen.X - 16, 460), math.min(screen.Y - 16, 480)
	local frame = Kit.glassPanel({
		Name = "EventBoard",
		Active = true,
		Position = UDim2.fromOffset((screen.X - w) / 2, (screen.Y - h) / 2),
		Size = UDim2.fromOffset(w, h),
		Parent = layer,
	})
	board = frame
	local title = Kit.label("🎉 Live events", 17, Theme.Fonts.Display, Theme.Colors.GoldBright)
	title.AutomaticSize = Enum.AutomaticSize.None
	title.Position = UDim2.fromOffset(14, 10)
	title.Size = UDim2.new(1, -110, 0, 26)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = frame
	local close = Kit.new("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 8),
		Size = UDim2.fromOffset(80, 44),
		BackgroundColor3 = Theme.Colors.GlassHighlight,
		BackgroundTransparency = 0.3,
		Text = "Close",
		TextSize = 13,
		FontFace = Theme.Fonts.BodyBold,
		TextColor3 = Theme.Colors.Text,
		Parent = frame,
	})
	Kit.corner(close, 8)
	close.Activated:Connect(EventController.closeBoard)
	local scroll = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, 58),
		Size = UDim2.new(1, -20, 1, -66),
		CanvasSize = UDim2.fromScale(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = frame,
	})
	local list = Kit.list(scroll, Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Left)
	list.VerticalAlignment = Enum.VerticalAlignment.Top
	local function line(parent: Instance, text: string, size: number, color: Color3, bold: boolean?)
		local l = Kit.label(text, size, if bold then Theme.Fonts.BodyBold else Theme.Fonts.Body, color)
		l.Size = UDim2.new(1, -8, 0, 0)
		l.AutomaticSize = Enum.AutomaticSize.Y
		l.TextWrapped = true
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.Parent = parent
	end
	local data = boardData()
	if #running == 0 then
		line(scroll, "No events running right now.", 13, Theme.Colors.TextDim)
	end
	for _, entry in running do
		local e = EventDefinitions.get(entry.Id) :: EventDefinitions.Event
		local card = Kit.new("Frame", {
			BackgroundColor3 = Theme.Colors.Ink,
			BackgroundTransparency = 0.45,
			Size = UDim2.new(1, -8, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = scroll,
		})
		Kit.corner(card, 10)
		Kit.padding(card, 8, 10)
		Kit.list(card, Enum.FillDirection.Vertical, 3, Enum.HorizontalAlignment.Left)
		line(card, `{e.icon} {e.name} · {left(entry.EndsAt)} left`, 14, Theme.Colors.GoldBright, true)
		line(card, e.blurb, 12, Theme.Colors.TextDim)
		if entry.Rewards and #entry.Rewards > 0 then
			line(
				card,
				`🎁 Bonus rewards: {EventRewards.describe(entry.Rewards)}, for {EventRewards.RECIPIENTS[e.rewardTo or ""] or "taking part"}.`,
				12,
				Theme.Colors.GoldBright,
				true
			)
		end
		for _, text in liveLines(e.id, data[e.id]) do
			line(card, text, 12, Theme.Colors.Text)
		end
	end
end

function EventController:Start()
	build()
	Panels.register("events", EventController.closeBoard)
	ReplicatedStorage:GetAttributeChangedSignal(BOARD):Connect(function()
		if board then
			drawBoard()
		end
	end)
	ReplicatedStorage:GetAttributeChangedSignal(ATTRIBUTE):Connect(update)
	update()
	-- The countdown ticks once a minute is enough; every 15 s keeps it close.
	task.spawn(function()
		while true do
			task.wait(15)
			render()
		end
	end)
end

return EventController
