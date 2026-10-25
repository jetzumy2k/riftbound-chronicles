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
	    icons and the time left on the soonest to end. Tapping it lists
	    every running event with its time left.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EventDefinitions = require(Shared.Definitions.EventDefinitions)

local UI = script.Parent.Parent.UI
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)
local NotificationController = require(script.Parent.NotificationController)

local ATTRIBUTE = "RC_Events"

local EventController = {}

type Running = { Id: string, EndsAt: number }

local running: { Running } = {}
local seen: { [string]: boolean }? = nil
local chip: TextButton? = nil

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
			table.insert(out, { Id = entry.Id, EndsAt = entry.EndsAt })
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
	button.Text = `🎉 {table.concat(icons, " ")}  ·  {left(soonest)}`
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
end

local function build()
	local gui = Kit.new("ScreenGui", {
		Name = "RC_Events",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		-- Under the toasts (20), which may briefly cover it.
		DisplayOrder = 8,
	})
	local button = Kit.new("TextButton", {
		Name = "Events",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.fromOffset(0, 30),
		AutomaticSize = Enum.AutomaticSize.X,
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
	Kit.corner(button, 15)
	Kit.goldStroke(button, 1.5, 0.2)
	Kit.padding(button, 0, 12)
	local scale = Kit.new("UIScale", { Parent = button })
	local function fit()
		local height = gui.AbsoluteSize.Y
		scale.Scale = math.clamp((if height > 0 then height else 720) / 720, 0.85, 1.35)
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()
	button.Activated:Connect(function()
		for _, entry in running do
			local e = EventDefinitions.get(entry.Id) :: EventDefinitions.Event
			NotificationController:ShowKey(
				"Info",
				"event.running",
				{ name = `{e.icon} {e.name}`, left = left(entry.EndsAt) }
			)
		end
	end)
	gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")
	chip = button
end

function EventController:Start()
	build()
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
