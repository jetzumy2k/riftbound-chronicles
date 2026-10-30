--!strict
--[[
	TowerController — the Tower Challenge (creator request 2026-10-30,
	PLAN.md D-131). Display and requests only; the server opens the Tower,
	runs the waves, times the clear and gives the points.

	  The Tower Keeper's screen (NpcOpen "Tower"): open / sealed and when,
	  the player's Tower points, every floor (levels, points, cleared,
	  best time) with Enter and 🏆 Top 3 (the week's board).
	  The run bar (TowerState): floor, wave, timer against the limit, a
	  Leave button, then the result.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local TowerRules = require(Shared.Logic.TowerRules)
local NetClient = require(Shared.Net.Client)

local UI = script.Parent.Parent.UI
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)
local Panels = require(UI.Panels)
local InventoryController = require(script.Parent.InventoryController)

local TowerController = {}

local BAD = Color3.fromRGB(255, 140, 130)
local GOOD = Color3.fromRGB(150, 230, 150)
local REASONS = {
	far = "Walk closer to the Tower Keeper.",
	closed = "The Tower is sealed right now. Check when it opens next.",
	inRun = "You are already in a Tower run.",
	dungeon = "Leave the dungeon first.",
	cap = "This floor needs the level 60 cap.",
	level = "Your level is too low for this floor.",
	leader = "Only your party leader can take the party in.",
	dead = "You can't enter while defeated.",
	busy = "Every Tower arena is in use. Try again in a minute.",
	floor = "That floor isn't open.",
	noRun = "You are not in a Tower run.",
	RateLimited = "Too fast; wait a moment.",
	BadArgs = "That request was not accepted.",
	HandlerError = "Something went wrong on the server; try again.",
}
local WHY = {
	wiped = "Everyone was defeated or left.",
	time = "Time ran out.",
	closed = "The Tower closed.",
	left = "You left the run.",
	down = "You were defeated.",
}

local panel: Frame? = nil
local content: Frame? = nil
local status, statusBad = "", false
local info: any = nil
local boardFor: string? = nil
local boardInfo: any = nil

-- The run bar.
local bar: Frame? = nil
local barText: TextLabel? = nil
local run: any = nil
local runClock = 0

local render: () -> ()

local function setStatus(text: string, bad: boolean?)
	status, statusBad = text, bad == true
end

local function call(action: string, floor: string?): any
	local result = NetClient.invoke("Tower", action, floor)
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

local function duration(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local d, h, m = seconds // 86400, (seconds % 86400) // 3600, (seconds % 3600) // 60
	if d > 0 then
		return `{d}d {h}h`
	elseif h > 0 then
		return `{h}h {m}m`
	end
	return `{m}m {seconds % 60}s`
end

local function clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
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
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
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
		AutoButtonColor = true,
		Parent = parent,
	})
	Kit.corner(b, 8)
	b.Activated:Connect(onClick)
	return b
end

local function row(parent: Instance, height: number?): Frame
	local r = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, height or 36),
		Parent = parent,
	})
	Kit.list(r, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left)
	return r
end

local function refreshStatus()
	local result = call("Status")
	if result then
		info = result
	end
	render()
end

local function lockedText(why: string?, f: any): string
	if why == "level" then
		return `🔒 Level {f.Min}+`
	elseif why == "cap" then
		return "🔒 Needs the level 60 cap"
	end
	return ""
end

local function drawBoard(frame: Instance, order: number): number
	local b = boardInfo
	if b == nil or boardFor == nil then
		return order
	end
	local box = Kit.new("Frame", {
		LayoutOrder = order,
		BackgroundColor3 = Theme.Colors.GlassHighlight,
		BackgroundTransparency = 0.6,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = frame,
	})
	Kit.corner(box, 8)
	Kit.padding(box, 8, 10)
	Kit.list(box, Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Left)
	text(box, `🏆 Floor {b.floor}: this week's fastest`, 14, Theme.Colors.GoldBright, true)
	if not b.online then
		text(box, "The board is offline on this server (no DataStore access in this place).", 12, BAD)
	end
	local function list(entries: { any }, empty: string)
		if #entries == 0 then
			text(box, empty, 12, Theme.Colors.TextDim)
		end
		for _, e in entries do
			text(box, `{e.Place}. {e.Name}  ·  {TowerRules.formatTenths(e.Time)}`, 13)
		end
	end
	list(b.thisWeek, "No clears yet this week: be the first!")
	text(box, `Resets in {duration(b.resetsIn)} (Monday 00:00 UTC).`, 11, Theme.Colors.TextDim)
	text(box, "Last week's top 3", 13, Theme.Colors.GoldBright, true)
	list(b.lastWeek, "Nobody last week.")
	text(
		box,
		"The week's 3 fastest get the floor's points again after the week ends. Only runs where nobody is above the floor's top level count.",
		11,
		Theme.Colors.TextDim
	)
	if b.best then
		text(box, `Your best: {TowerRules.formatTenths(b.best)}`, 12, GOOD, true)
	end
	button(box, "Close board", 120, false, function()
		boardFor, boardInfo = nil, nil
		render()
	end)
	return order + 1
end

function render()
	local frame = content
	if frame == nil then
		return
	end
	frame:ClearAllChildren()
	local scroll = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.fromScale(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = frame,
	})
	local list = Kit.list(scroll, Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Left)
	list.VerticalAlignment = Enum.VerticalAlignment.Top
	Kit.padding(scroll, 12, 14)
	local order = 1
	local function add(inst: Instance)
		(inst :: any).LayoutOrder = order
		order += 1
	end
	add(text(scroll, "🗼 The Tower Challenge", 18, Theme.Colors.GoldBright, true))
	local i = info
	if i == nil then
		add(text(scroll, "Loading...", 13, Theme.Colors.TextDim))
	else
		local when = if i.open
			then `✅ Open now · closes in {duration(i.closesIn or 0)}`
			elseif i.opensIn then `🔒 Sealed · opens in {duration(i.opensIn)} for {duration(
				i.opensFor or 0
			)}`
			else "🔒 Sealed · no opening scheduled (watch for the event)"
		add(text(scroll, when, 14, if i.open then GOOD else Theme.Colors.Text, true))
		add(
			text(
				scroll,
				`Clear a floor's waves before time runs out. A first clear gives its attribute points (once per character); then race for the week's best times. Tower points: {i.points} / {i.maxPoints} (spend them in 🌟 Skills, then 📊 Stats).`,
				12,
				Theme.Colors.TextDim
			)
		)
		local top = row(scroll)
		add(top)
		button(top, "Refresh", 90, false, refreshStatus)
		if i.inRun then
			button(top, "Leave run", 110, false, function()
				if call("Leave") then
					setStatus("You left the run.")
				end
				refreshStatus()
			end)
		end
		button(top, "Close", 80, false, TowerController.close)
		order = drawBoard(scroll, order)
		for _, f in i.floors do
			local card = Kit.new("Frame", {
				BackgroundColor3 = Theme.Colors.GlassHighlight,
				BackgroundTransparency = 0.7,
				Size = UDim2.fromScale(1, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
			})
			add(card)
			card.Parent = scroll
			Kit.corner(card, 8)
			Kit.padding(card, 8, 10)
			Kit.list(card, Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Left)
			text(
				card,
				`{f.Id} · {f.Name}  ·  Levels {f.Min}-{f.Max}  ·  ⭐ {f.Points} points`,
				14,
				Theme.Colors.Text,
				true
			)
			local facts = `{f.Waves} waves · limit {clock(f.Limit)}`
			if f.Cleared then
				facts ..= "  ·  ✅ Cleared"
			end
			if f.Best then
				facts ..= `  ·  best {TowerRules.formatTenths(f.Best)}`
			end
			if f.Locked then
				facts ..= `  ·  {lockedText(f.Locked, f)}`
			end
			text(card, facts, 12, if f.Locked then Theme.Colors.TextDim else Theme.Colors.Text)
			local buttons = row(card)
			if not f.Locked and i.open and not i.inRun then
				button(buttons, if f.Cleared then "Run again" else "Enter", 110, true, function()
					local result = call("Enter", f.Id)
					if result then
						setStatus(
							if (result.behind or 0) > 0
								then `Entering... ({result.behind} party member(s) were too far or not ready).`
								else "Entering..."
						)
						TowerController.close()
						return
					end
					render()
				end)
			end
			button(buttons, "🏆 Top 3", 100, false, function()
				local result = call("Board", f.Id)
				if result then
					boardFor, boardInfo = f.Id, result
					setStatus("")
				end
				render()
			end)
		end
	end
	local s = text(scroll, status, 13, if statusBad then BAD else Theme.Colors.Safe, true)
	add(s)
end

function TowerController.close()
	if panel then
		panel:Destroy()
		panel, content = nil, nil
		Panels.closed("tower")
	end
end

local function open()
	TowerController.close()
	InventoryController.setOpen(false)
	Panels.opened("tower")
	local layer = Panels.layer()
	local screen = layer.AbsoluteSize
	local w, h = math.min(screen.X - 16, 520), math.min(screen.Y - 16, 620)
	local frame = Kit.glassPanel({
		Name = "Tower",
		Active = true,
		Position = UDim2.fromOffset((screen.X - w) / 2, (screen.Y - h) / 2),
		Size = UDim2.fromOffset(w, h),
		Parent = layer,
	})
	frame.BackgroundTransparency = 0.04
	panel = frame
	content = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = frame })
	info, boardFor, boardInfo = nil, nil, nil
	setStatus("")
	render()
	task.spawn(refreshStatus)
end

--------------------------------------------------------------------------------
-- The run bar
--------------------------------------------------------------------------------

local function closeBar()
	if bar then
		bar:Destroy()
		bar, barText = nil, nil
	end
	run = nil
end

local function barLine(): string
	local r = run
	if r == nil then
		return ""
	end
	if r.Phase == "Countdown" then
		return `🗼 Floor {r.Floor} · get ready...`
	elseif r.Phase == "Fight" then
		local elapsed = r.Elapsed + (os.clock() - runClock)
		return `🗼 Floor {r.Floor} · wave {r.Wave}/{r.Waves} · ⌛ {clock(elapsed)} / {clock(r.Limit)}`
	elseif r.Phase == "Cleared" then
		local line = `✅ Floor {r.Floor} cleared in {TowerRules.formatTenths(r.Time or 0)}`
		if r.Best then
			line ..= " · new best!"
		end
		if (r.Points or 0) > 0 then
			line ..= ` · +{r.Points} attribute points`
		end
		return line .. " · back to the capital soon"
	elseif r.Phase == "Failed" then
		return `❌ Floor {r.Floor} failed: {WHY[r.Why or ""] or "the run ended."}`
	end
	return ""
end

local function showBar(state: any)
	if state.Phase == "Gone" then
		closeBar()
		return
	end
	run = state
	runClock = os.clock()
	if bar == nil then
		local layer = Panels.layer()
		local w = math.min(layer.AbsoluteSize.X - 16, 460)
		local frame = Kit.glassPanel({
			Name = "TowerBar",
			Position = UDim2.new(0.5, -w / 2, 0, 64),
			Size = UDim2.fromOffset(w, 44),
			Parent = layer,
		})
		frame.BackgroundTransparency = 0.15
		bar = frame
		barText = Kit.new("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(10, 0),
			Size = UDim2.new(1, -100, 1, 0),
			TextSize = 14,
			FontFace = Theme.Fonts.BodyBold,
			TextColor3 = Theme.Colors.Text,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true,
			Parent = frame,
		})
		local leave = button(frame, "Leave", 76, false, function()
			NetClient.invoke("Tower", "Leave")
		end)
		leave.Position = UDim2.new(1, -84, 0.5, -18)
	end
	if barText then
		barText.Text = barLine()
	end
	if state.Phase == "Cleared" or state.Phase == "Failed" then
		local shown = state
		task.delay(14, function()
			if run == shown then
				closeBar()
			end
		end)
	end
end

function TowerController:Start()
	Panels.register("tower", TowerController.close)
	NetClient.on("NpcOpen", function(payload: any)
		if type(payload) == "table" and payload.Npc == "Tower" then
			open()
		end
	end)
	NetClient.on("TowerState", function(state: any)
		if type(state) == "table" then
			showBar(state)
		end
	end)
	-- The run timer ticks in place (a label refresh, twice a second).
	task.spawn(function()
		while true do
			task.wait(0.5)
			if barText and run and run.Phase == "Fight" then
				barText.Text = barLine()
			end
		end
	end)
end

return TowerController
