--!strict
--[[
	DungeonController — compact dungeon tracker and ground warnings
	(Phase 9, D-39). Display only.

	Shows the server's DungeonState in a slim panel in the top-right safe
	area, away from the centre of the screen where the character and its
	targets are:
	  header   dungeon name (tap to collapse / expand) + Leave
	  body     room n/N, objective with a kill counter, party and leader
	  boss     name, health bar and percentage (boss room)
	  cleared  reward and the return countdown
	Telegraph events draw boss ground warnings (Effects/TelegraphVfx).

	Mobile: ≤ 250 px wide (scaled down on small screens), Leave ≥ 44 px
	tall, state always in text, never colour alone.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local NetClient = require(Shared.Net.Client)

local UI = script.Parent.Parent.UI
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)
local TelegraphVfx = require(script.Parent.Parent.Effects.TelegraphVfx)

local PANEL_WIDTH = 250
local LEAVE_RED = Color3.fromRGB(150, 40, 44)

local DungeonController = {}

type Widgets = {
	panel: Frame,
	scale: UIScale,
	title: TextButton,
	body: Frame,
	room: TextLabel,
	objective: TextLabel,
	detail: TextLabel,
	bossFrame: Frame,
	bossName: TextLabel,
	bossFill: Frame,
	bossText: TextLabel,
	leave: TextButton,
}

local widgets: Widgets? = nil
local collapsed = false
local lastState: any = nil

local function text(
	name: string,
	size: number,
	font: Font,
	color: Color3,
	order: number,
	parent: Instance
): TextLabel
	local label = Kit.label("", size, font, color)
	label.Name = name
	label.Size = UDim2.fromScale(1, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.LayoutOrder = order
	label.Parent = parent
	return label
end

local function build(): Widgets
	local gui = Kit.new("ScreenGui", {
		Name = "RC_Dungeon",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		DisplayOrder = 4,
	})
	local panel = Kit.glassPanel({
		Name = "Tracker",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.fromOffset(PANEL_WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 0.3,
		Visible = false,
		Parent = gui,
	})
	local scale = Kit.new("UIScale", { Parent = panel })
	Kit.padding(panel, 8, 10)
	local layout = Kit.list(panel, Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Left)
	layout.VerticalAlignment = Enum.VerticalAlignment.Top

	-- Header: title (tap to collapse) + Leave.
	local header = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 44),
		LayoutOrder = 1,
		Parent = panel,
	})
	local title = Kit.new("TextButton", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -78, 1, 0),
		Text = "",
		TextSize = 15,
		FontFace = Theme.Fonts.Display,
		TextColor3 = Theme.Colors.GoldBright,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		AutoButtonColor = false,
		Parent = header,
	})
	local leave = Kit.new("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(72, 44),
		BackgroundColor3 = LEAVE_RED,
		BackgroundTransparency = 0.1,
		Text = "Leave",
		TextSize = 15,
		FontFace = Theme.Fonts.BodyBold,
		TextColor3 = Color3.new(1, 1, 1),
		AutoButtonColor = true,
		Parent = header,
	})
	Kit.corner(leave, 10)
	Kit.new(
		"UIStroke",
		{ Color = Color3.fromRGB(255, 180, 170), Thickness = 1, Transparency = 0.4, Parent = leave }
	)
	leave.Activated:Connect(function()
		NetClient.fire("DungeonLeave")
	end)

	local body = Kit.new("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		Parent = panel,
	})
	local bodyLayout = Kit.list(body, Enum.FillDirection.Vertical, 3, Enum.HorizontalAlignment.Left)
	bodyLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	local room = text("Room", 12, Theme.Fonts.BodyBold, Theme.Colors.TextDim, 1, body)
	local objective = text("Objective", 14, Theme.Fonts.BodyBold, Theme.Colors.Text, 2, body)
	local detail = text("Detail", 12, Theme.Fonts.Body, Theme.Colors.TextDim, 3, body)

	-- Boss health bar (name + bar + percent text).
	local bossFrame = Kit.new("Frame", {
		Name = "Boss",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 34),
		LayoutOrder = 3,
		Visible = false,
		Parent = panel,
	})
	local bossName = Kit.label("", 12, Theme.Fonts.BodyBold, Theme.Colors.Text)
	bossName.Size = UDim2.new(1, 0, 0, 14)
	bossName.TextXAlignment = Enum.TextXAlignment.Left
	bossName.Parent = bossFrame
	local track = Kit.new("Frame", {
		BackgroundColor3 = Theme.Colors.Ink,
		BackgroundTransparency = 0.2,
		Position = UDim2.fromOffset(0, 17),
		Size = UDim2.new(1, 0, 0, 14),
		Parent = bossFrame,
	})
	Kit.corner(track, 7)
	local bossFill = Kit.new("Frame", {
		BackgroundColor3 = Color3.fromRGB(220, 60, 60),
		Size = UDim2.fromScale(1, 1),
		Parent = track,
	})
	Kit.corner(bossFill, 7)
	local bossText = Kit.label("", 11, Theme.Fonts.BodyBold, Theme.Colors.Text)
	bossText.Size = UDim2.fromScale(1, 1)
	bossText.ZIndex = 3
	bossText.Parent = track

	gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")
	local w: Widgets = {
		panel = panel,
		scale = scale,
		title = title,
		body = body,
		room = room,
		objective = objective,
		detail = detail,
		bossFrame = bossFrame,
		bossName = bossName,
		bossFill = bossFill,
		bossText = bossText,
		leave = leave,
	}
	return w
end

local function fitToScreen(w: Widgets)
	local camera = Workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	-- Never wider than ~38% of the screen, so the middle stays clear.
	w.scale.Scale = math.clamp(viewport.X * 0.38 / PANEL_WIDTH, 0.7, 1)
end

local function render(state: any)
	local w = widgets
	if w == nil or type(state) ~= "table" then
		return
	end
	lastState = state
	local phase = state.phase
	w.panel.Visible = phase == "Active" or phase == "Cleared"
	if not w.panel.Visible then
		return
	end
	fitToScreen(w)
	w.title.Text = `⚔ {state.dungeon or "Dungeon"}  {if collapsed then "+" else "–"}`
	w.body.Visible = not collapsed
	w.bossFrame.Visible = false
	w.leave.Text = "Leave"

	local party = if state.leader and (state.members or 1) > 1
		then `Party {state.members} · Leader: {state.leader}`
		else "Solo"
	if phase == "Active" then
		w.room.Text = `Room {state.roomIndex or 1}/{state.roomCount or 1} · {state.room or ""}`
		local progress = if state.goal and state.goal > 0 then ` ({state.progress or 0}/{state.goal})` else ""
		w.objective.Text = `• {state.objective or ""}{progress}`
		w.detail.Text = party
		if state.bossName and state.bossHp then
			w.bossFrame.Visible = true
			w.bossName.Text = state.bossName
			local hp = math.clamp(state.bossHp, 0, 1)
			w.bossFill.Size = UDim2.fromScale(hp, 1)
			w.bossText.Text = `{math.ceil(hp * 100)}%`
		end
	else
		w.room.Text = "★ Dungeon cleared!"
		w.objective.Text = if state.xp then `Reward: +{state.xp} EXP` else "Well fought!"
		w.detail.Text = `Back outside in {math.ceil(state.countdown or 0)}s, or use the portal.`
		w.leave.Text = "Exit"
	end
end

function DungeonController:Start()
	local built = build()
	widgets = built
	built.title.Activated:Connect(function()
		collapsed = not collapsed
		render(lastState)
	end)
	NetClient.on("DungeonState", render)
	NetClient.on("Telegraph", function(payload)
		if type(payload) == "table" and typeof(payload.center) == "Vector3" then
			TelegraphVfx.show(payload)
		end
	end)
	local player = Players.LocalPlayer :: Player
	player.CharacterAdded:Connect(function()
		if widgets then
			fitToScreen(widgets)
		end
	end)
end

return DungeonController
