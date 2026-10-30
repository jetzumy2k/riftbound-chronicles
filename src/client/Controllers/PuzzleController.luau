--!strict
--[[
	PuzzleController — the Puzzle Sage's screen (creator request
	2026-10-30, PLAN.md D-128). Opens from the 🧩 Sage (NpcOpen).

	Shows the puzzle the server made, lets the player play it here (moves
	apply on screen at once with the same PuzzleRules), and when the board
	looks solved sends the move list; the server replays and judges it and
	gives the reward. Display and requests only.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PuzzleRules = require(Shared.Logic.PuzzleRules)
local NetClient = require(Shared.Net.Client)

local UI = script.Parent.Parent.UI
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)
local Panels = require(UI.Panels)
local InventoryController = require(script.Parent.InventoryController)

local PuzzleController = {}

local BAD = Color3.fromRGB(255, 140, 130)
local LIGHT_ON = Color3.fromRGB(255, 214, 110)
local LIGHT_OFF = Color3.fromRGB(40, 36, 52)
local REASONS = {
	far = "Walk closer to the Sage.",
	closed = "The Sage is resting (puzzles are off for now).",
	bag = "Free a bag slot first: the reward goes there.",
	time = "Out of time! Try another puzzle.",
	wrong = "Not solved yet: keep going.",
	noPuzzle = "Start a puzzle first.",
	RateLimited = "Too fast; wait a moment.",
	BadArgs = "That request was not accepted.",
	HandlerError = "Something went wrong on the server; try again.",
}
local HOW = {
	Slide = "Slide the tiles into order 1, 2, 3... with the gap last. Tap a tile next to the gap to move it.",
	Lights = "Turn every light off. Tapping a light flips it and the four next to it.",
}

local panel: Frame? = nil
local content: Frame? = nil
local status, statusBad = "", false
local info: any = nil
local board: { number } = {}
local moves: { number } = {}
local endsAt = 0
local sending = false
-- The header line with the timer, updated in place (no rebuild).
local timerLabel: TextLabel? = nil

local render: () -> ()

local function setStatus(text: string, bad: boolean?)
	status, statusBad = text, bad == true
end

local function call(action: string, list: { number }?): any
	local result = NetClient.invoke("Puzzle", action, list)
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

local function adopt(result: any)
	info = result
	local p = result and result.puzzle
	if p then
		board = table.clone(p.Board)
		moves = {}
		endsAt = os.clock() + p.Seconds
	end
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
		Size = UDim2.fromOffset(width, 40),
		BackgroundColor3 = if gold then Theme.Colors.Gold else Theme.Colors.GlassHighlight,
		BackgroundTransparency = if gold then 0.05 else 0.3,
		Text = label,
		TextSize = 14,
		FontFace = Theme.Fonts.BodyBold,
		TextColor3 = if gold then Theme.Colors.Ink else Theme.Colors.Text,
		AutoButtonColor = true,
		Parent = parent,
	})
	Kit.corner(b, 8)
	b.Activated:Connect(onClick)
	return b
end

local function submit()
	if sending then
		return
	end
	sending = true
	local result = call("Submit", moves)
	sending = false
	if result then
		info = result
		if result.given then
			setStatus(`🎉 Solved in {result.seconds}s! Reward: Legendary {result.given} (in your bag).`)
		else
			setStatus(`✅ Solved in {result.seconds}s! (Practice: today's reward is already claimed.)`)
		end
	end
	render()
end

local function tap(index: number)
	local p = info and info.puzzle
	if p == nil or sending then
		return
	end
	local ok = if p.Kind == "Slide"
		then PuzzleRules.slide(board, p.Size, index)
		else PuzzleRules.press(board, p.Size, index)
	if not ok then
		return
	end
	table.insert(moves, index)
	local puzzle: PuzzleRules.Puzzle = { kind = p.Kind, level = p.Level, size = p.Size, board = board }
	if PuzzleRules.solved(puzzle, board) then
		submit()
	else
		render()
	end
end

function render()
	local frame = content
	if frame == nil then
		return
	end
	frame:ClearAllChildren()
	local list = Kit.list(frame, Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Center)
	list.VerticalAlignment = Enum.VerticalAlignment.Top
	Kit.padding(frame, 12, 14)
	local title = text(frame, "🧩 The Puzzle Sage", 18, Theme.Colors.GoldBright, true)
	title.LayoutOrder = 1
	local i = info
	local p = i and i.puzzle
	local order = 2
	local function add(inst: Instance)
		(inst :: any).LayoutOrder = order
		order += 1
	end
	if i == nil then
		add(text(frame, "Loading...", 13, Theme.Colors.TextDim))
	elseif p == nil then
		add(
			text(
				frame,
				if i.rewardUsed
					then "Today's reward is claimed. You can still practise: a new puzzle every time, no reward."
					else "Solve a medium or hard puzzle in time for a Legendary gear piece, weapon or accessory. One reward a day; it starts counting when you begin.",
				13,
				Theme.Colors.Text
			)
		)
		local row = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40) })
		Kit.list(row, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center)
		add(row)
		row.Parent = frame
		button(
			row,
			if i.rewardUsed then "Practice puzzle" else "🧩 Start today's puzzle",
			220,
			true,
			function()
				local result = call("Start")
				if result then
					adopt(result)
					setStatus("")
				end
				render()
			end
		)
		button(row, "Close", 100, false, PuzzleController.close)
	else
		local header = text(frame, "", 14, Theme.Colors.GoldBright, true)
		add(header)
		timerLabel = header
		PuzzleController.tick()
		add(text(frame, HOW[p.Kind] or "", 12, Theme.Colors.TextDim))
		local cell = math.floor(math.min(300, (frame.AbsoluteSize.X - 40)) / p.Size)
		local grid = Kit.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(cell * p.Size, cell * p.Size),
		})
		add(grid)
		grid.Parent = frame
		local layout = Instance.new("UIGridLayout")
		layout.CellSize = UDim2.fromOffset(cell - 6, cell - 6)
		layout.CellPadding = UDim2.fromOffset(6, 6)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = grid
		for index = 1, p.Size * p.Size do
			local value = board[index]
			local b = Kit.new("TextButton", {
				LayoutOrder = index,
				AutoButtonColor = true,
				Text = if p.Kind == "Slide" and value ~= 0 then tostring(value) else "",
				TextSize = math.floor(cell * 0.4),
				FontFace = Theme.Fonts.Display,
				TextColor3 = Theme.Colors.Ink,
				BackgroundColor3 = if p.Kind == "Slide"
					then (if value == 0 then Theme.Colors.Ink else Theme.Colors.Gold)
					else (if value == 1 then LIGHT_ON else LIGHT_OFF),
				BackgroundTransparency = if p.Kind == "Slide" and value == 0 then 0.7 else 0,
				Parent = grid,
			})
			Kit.corner(b, 8)
			b.Activated:Connect(function()
				tap(index)
			end)
		end
		local row = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40) })
		Kit.list(row, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center)
		add(row)
		row.Parent = frame
		button(row, "Restart board", 140, false, function()
			board = table.clone(p.Board)
			moves = {}
			render()
		end)
		button(row, "Give up", 110, false, function()
			local result = call("GiveUp")
			if result then
				adopt(result)
				setStatus("Puzzle ended.")
			end
			render()
		end)
	end
	local s = text(frame, status, 13, if statusBad then BAD else Theme.Colors.Safe, true)
	s.LayoutOrder = 999
end

-- The timer line (called each second; never rebuilds the board).
function PuzzleController.tick()
	local label = timerLabel
	local p = info and info.puzzle
	if label == nil or label.Parent == nil or p == nil then
		return
	end
	local left = math.max(0, math.ceil(endsAt - os.clock()))
	label.Text = `{if p.Kind == "Slide" then "Sliding tiles" else "Lights out"} · {p.Level} · {if p.Rewarded
		then "🎁 rewarded"
		else "practice"} · ⌛ {left // 60}:{string.format("%02d", left % 60)} · moves {#moves}`
end

function PuzzleController.close()
	if panel then
		panel:Destroy()
		panel, content = nil, nil
		Panels.closed("puzzle")
	end
end

local function open()
	PuzzleController.close()
	InventoryController.setOpen(false)
	Panels.opened("puzzle")
	local layer = Panels.layer()
	local screen = layer.AbsoluteSize
	local w, h = math.min(screen.X - 16, 460), math.min(screen.Y - 16, 600)
	local frame = Kit.glassPanel({
		Name = "Puzzle",
		Active = true,
		Position = UDim2.fromOffset((screen.X - w) / 2, (screen.Y - h) / 2),
		Size = UDim2.fromOffset(w, h),
		Parent = layer,
	})
	frame.BackgroundTransparency = 0.04
	panel = frame
	content = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = frame })
	info = nil
	setStatus("")
	render()
	task.spawn(function()
		local result = call("Status")
		if result then
			adopt(result)
		end
		render()
	end)
end

function PuzzleController:Start()
	Panels.register("puzzle", PuzzleController.close)
	NetClient.on("NpcOpen", function(payload: any)
		if type(payload) == "table" and payload.Npc == "Sage" then
			open()
		end
	end)
	-- The timer ticks while a puzzle is open (a label refresh, once a second).
	task.spawn(function()
		while true do
			task.wait(1)
			if panel and info and info.puzzle then
				PuzzleController.tick()
			end
		end
	end)
end

return PuzzleController
