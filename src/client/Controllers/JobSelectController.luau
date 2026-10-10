--!strict
--[[
	JobSelectController — "Choose your path" (Phase 4).

	Shown after the realm is chosen and before the character enters the world.
	Same dark-glass + gold kit and responsive approach as the realm screen: the
	shared JobSelectLayout picks wide / tall / compact layouts (tested across
	20 device sizes) and this controller only applies them.

	Each card shows the job's emblem, the race-specific role line from the
	concept sheet, a description and the weapons that job can wield for this
	race. The client sends only the chosen job; the server validates it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local JobDefinitions = require(Shared.Definitions.JobDefinitions)
local RaceDefinitions = require(Shared.Definitions.RaceDefinitions)
local WorldLayout = require(Shared.Definitions.WorldLayout)
local JobSelectLayout = require(Shared.Layout.JobSelectLayout)
local NetClient = require(Shared.Net.Client)
local Log = require(Shared.Util.Log)

local UI = script.Parent.Parent.UI
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)

local PlayerDataController = require(script.Parent.PlayerDataController)

local CONFIRM_TIMEOUT = 10
local CARD_KEY: { [string]: string } =
	{ Warrior = "cardWarrior", Healer = "cardHealer", Archer = "cardArcher", Mage = "cardMage" }

local log = Log.new("JobSelect")

local JobSelectController = {}

type Card = {
	root: Frame,
	padding: UIPadding,
	listLayout: UIListLayout,
	medallion: Frame,
	name: TextLabel,
	role: TextLabel,
	description: TextLabel,
	weapons: TextLabel,
}

local state = {
	race = nil :: string?,
	job = nil :: string?,
	submitting = false,
	layout = nil :: JobSelectLayout.Layout?,
}

local gui: ScreenGui? = nil
local backdropGui: ScreenGui? = nil
local connections: { RBXScriptConnection } = {}
local refreshers: { () -> () } = {}

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function track(connection: RBXScriptConnection)
	table.insert(connections, connection)
end

local function refresh()
	for _, fn in refreshers do
		fn()
	end
end

-- Frames the player's own capital behind the menu.
local function setCamera(active: boolean, race: string?)
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end
	local realm = if race then WorldLayout.realmFor(race) else nil
	if active and realm then
		local spawn = Vector3.new(realm.spawnPosition[1], realm.spawnPosition[2], realm.spawnPosition[3])
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = CFrame.lookAt(spawn + Vector3.new(70, 40, 90), spawn + Vector3.new(0, 8, 0))
	else
		camera.CameraType = Enum.CameraType.Custom
	end
end

local function selectJob(job: string)
	if state.submitting or state.job == job then
		return
	end
	state.job = job
	refresh()
end

local function buildCard(parent: Instance, job: string, race: string, accent: Color3): Card?
	local def = JobDefinitions.get(job)
	if def == nil then
		return nil
	end

	local root = Kit.glassPanel({ Name = job, Parent = parent }, Theme.Radius.Card)
	local stroke = root:FindFirstChildOfClass("UIStroke") :: UIStroke
	local scale = Kit.new("UIScale", { Parent = root })

	local content = Kit.new(
		"Frame",
		{ BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = root }
	)
	local padding = Kit.padding(content, 18, 20)
	local listLayout = Kit.list(content, Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Center)
	listLayout.VerticalAlignment = Enum.VerticalAlignment.Center

	local medallion = Kit.medallion(76, def.glyph, accent)
	medallion.LayoutOrder = 1
	medallion.Parent = content

	local name = Kit.goldTitle(def.displayName:upper(), 28)
	name.LayoutOrder = 2
	name.Parent = content

	local role = Kit.label(def.roleByRace[race] or "", 16, Theme.Fonts.BodyBold, accent)
	role.LayoutOrder = 3
	role.Parent = content

	local description = Kit.label(def.description, 15, Theme.Fonts.Body, Theme.Colors.TextDim)
	description.LayoutOrder = 4
	description.Parent = content

	local weaponList = def.weaponsByRace[race] or {}
	local weapons =
		Kit.label(`⚔  {table.concat(weaponList, "  ·  ")}`, 14, Theme.Fonts.BodyBold, Theme.Colors.Text)
	weapons.LayoutOrder = 5
	weapons.Parent = content

	local tag = Kit.new("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(128, 28),
		ZIndex = 5,
		Visible = false,
		Parent = root,
	})
	Kit.corner(tag, 14)
	Kit.new("UIGradient", { Color = Theme.GoldSequence, Rotation = 90, Parent = tag })
	Kit.new("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = "✓  SELECTED",
		TextSize = 14,
		FontFace = Theme.Fonts.BodyBold,
		TextColor3 = Color3.fromRGB(40, 24, 8),
		ZIndex = 6,
		Parent = tag,
	})

	local dim = Kit.new("Frame", {
		BackgroundColor3 = Theme.Colors.Ink,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 4,
		Parent = root,
	})
	Kit.corner(dim, Theme.Radius.Card)

	local hit = Kit.new(
		"TextButton",
		{ BackgroundTransparency = 1, Text = "", Size = UDim2.fromScale(1, 1), ZIndex = 10, Parent = root }
	)
	track(hit.Activated:Connect(function()
		selectJob(job)
	end))

	table.insert(refreshers, function()
		local selected = state.job == job
		local other = state.job ~= nil and not selected
		Kit.tween(stroke, Kit.Tween.Smooth, {
			Thickness = if selected then 3 else 1.5,
			Transparency = if selected then 0 else 0.15,
		})
		Kit.tween(dim, Kit.Tween.Smooth, { BackgroundTransparency = if other then 0.45 else 1 })
		Kit.tween(scale, Kit.Tween.Smooth, { Scale = if selected then 1.03 else 1 })
		tag.Visible = selected
	end)

	return {
		root = root,
		padding = padding,
		listLayout = listLayout,
		medallion = medallion,
		name = name,
		role = role,
		description = description,
		weapons = weapons,
	}
end

local function applyCardLayout(card: Card, layout: JobSelectLayout.Layout, r: JobSelectLayout.Rect?)
	Kit.place(card.root, r)
	local compact = layout.mode == "compactLandscape" or layout.mode == "compactPortrait"
	local pad = if compact then 8 else 16
	card.padding.PaddingTop = UDim.new(0, pad)
	card.padding.PaddingBottom = UDim.new(0, pad)
	card.padding.PaddingLeft = UDim.new(0, if compact then 12 else 20)
	card.padding.PaddingRight = UDim.new(0, if compact then 12 else 20)
	card.listLayout.Padding = UDim.new(0, if compact then 4 else 8)
	card.medallion.Visible = layout.showMedallion
	card.name.TextSize = layout.fonts.cardName
	card.role.TextSize = layout.fonts.role
	card.description.TextSize = layout.fonts.description
	card.description.Visible = layout.showDescription
	card.weapons.TextSize = layout.fonts.weapons
end

local function build(race: string): ScreenGui
	refreshers = {}
	local playerGui = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")
	local raceDef = RaceDefinitions.get(race)
	local accent = if raceDef then rgb(raceDef.uiAccent) else Theme.Colors.Gold

	backdropGui = Kit.backdrop("RC_JobSelectBackdrop", 9, playerGui)

	local screen = Kit.new("ScreenGui", {
		Name = "RC_JobSelect",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		DisplayOrder = 10,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	local canvas = Kit.new("Frame", { Name = "Canvas", BackgroundTransparency = 1, Parent = screen })
	local canvasScale = Kit.new("UIScale", { Parent = canvas })

	local header = Kit.new("Frame", { Name = "Header", BackgroundTransparency = 1, Parent = canvas })
	Kit.list(header, Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Center)
	local title = Kit.goldTitle("✦  CHOOSE YOUR PATH  ✦", 40)
	title.LayoutOrder = 1
	title.Parent = header
	local subtitle = Kit.label(
		`{if raceDef then raceDef.displayName else "Champion"} walk four paths. Choose how you will fight.`,
		18,
		Theme.Fonts.Accent,
		Theme.Colors.TextDim
	)
	subtitle.LayoutOrder = 2
	subtitle.Parent = header
	local headerDivider = Kit.divider(360)
	headerDivider.LayoutOrder = 3
	headerDivider.Parent = header

	local cards: { [string]: Card } = {}
	for _, job in JobDefinitions.Order do
		local card = buildCard(canvas, job, race, accent)
		if card then
			cards[job] = card
		end
	end

	local confirm, setConfirmEnabled = Kit.button("SELECT A PATH", "gold")
	confirm.Parent = canvas

	local note =
		Kit.label("Your path is permanent for this character.", 14, Theme.Fonts.Body, Theme.Colors.TextMuted)
	note.AutomaticSize = Enum.AutomaticSize.None
	note.Parent = canvas

	table.insert(refreshers, function()
		if state.submitting then
			setConfirmEnabled(false, "ENTERING…")
		elseif state.job then
			setConfirmEnabled(true, `BEGIN AS {state.job:upper()}`)
		else
			setConfirmEnabled(false, "SELECT A PATH")
		end
	end)

	track(confirm.Activated:Connect(function()
		if state.submitting or state.job == nil then
			return
		end
		state.submitting = true
		refresh()
		NetClient.fire("SelectJob", state.job)
		log:Debug("requested %s", state.job)
		task.delay(CONFIRM_TIMEOUT, function()
			if gui and state.submitting then
				state.submitting = false
				refresh()
			end
		end)
	end))

	local function applyLayout()
		local area = screen.AbsoluteSize
		if area.X < 1 or area.Y < 1 then
			return
		end
		local layout = JobSelectLayout.compute(area.X, area.Y)
		state.layout = layout
		canvas.Size = UDim2.fromOffset(layout.canvas.w, layout.canvas.h)
		canvasScale.Scale = layout.scale

		Kit.place(header, layout.rects.header)
		title.TextSize = layout.fonts.title
		subtitle.TextSize = layout.fonts.subtitle
		subtitle.Visible = layout.showSubtitle
		headerDivider.Visible = layout.showSubtitle

		for job, card in cards do
			applyCardLayout(card, layout, layout.rects[CARD_KEY[job]])
		end
		Kit.place(confirm, layout.rects.confirm)
		confirm.TextSize = layout.fonts.button
		Kit.place(note, layout.rects.note)
		note.TextSize = layout.fonts.note
		refresh()
		log:Debug("layout %s %dx%d scale %.2f", layout.mode, area.X, area.Y, layout.scale)
	end

	screen.Parent = playerGui
	track(screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyLayout))
	applyLayout()
	return screen
end

local function show(race: string)
	if gui then
		return
	end
	state.race = race
	state.job = nil
	state.submitting = false
	setCamera(true, race)
	gui = build(race)
	log:Debug("job selection shown")
end

local function hide()
	if gui == nil then
		return
	end
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	refreshers = {}
	gui:Destroy()
	gui = nil
	if backdropGui then
		backdropGui:Destroy()
		backdropGui = nil
	end
	state.submitting = false
	state.layout = nil
	setCamera(false, nil)
end

function JobSelectController:Init()
	PlayerDataController.Changed:Connect(function(data, reason)
		if reason ~= "snapshot" then
			return
		end
		if data.Race ~= nil and data.Job == nil then
			show(data.Race)
		else
			hide()
		end
	end)
end

return JobSelectController
