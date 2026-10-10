--!strict
--[[
	RaceSelectController — first-time realm choice (Phase 3).

	Dark-glass + gold fantasy UI (PLAN.md D-28), fully responsive: the shared
	RaceSelectLayout module picks one of four layouts from the safe-area size
	(wide / tall / compact landscape / compact portrait) and this controller
	only applies its rects, fonts and visibility. The layout rules (on-screen,
	no overlap, fonts >= 11 px, touch targets >= 44 px) are unit-tested across
	20 device sizes. Layout re-applies live on rotation / window resize.

	  - The 3D preview shows the player's own avatar dressed in the chosen look.
	    The server builds the preview models (PlayerGui.RC_Previews); the client
	    only recolours them with the shared palette and rotates them.
	  - Selection is shown with a brighter frame, a "SELECTED" tag and a check
	    mark, never colour alone.

	The client sends only (race, presetId). The server validates and decides.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RaceDefinitions = require(Shared.Definitions.RaceDefinitions)
local FacePresets = require(Shared.Definitions.FacePresets)
local WorldLayout = require(Shared.Definitions.WorldLayout)
local RaceSelectLayout = require(Shared.Layout.RaceSelectLayout)
local NetClient = require(Shared.Net.Client)
local Log = require(Shared.Util.Log)

local UI = script.Parent.Parent.UI
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)

local PlayerDataController = require(script.Parent.PlayerDataController)

local PREVIEW_FOLDER = "RC_Previews"
local CONFIRM_TIMEOUT = 10
local SPIN_SPEED = 0.35 -- radians per second

local log = Log.new("RaceSelect")

local RaceSelectController = {}

type Card = {
	root: Frame,
	glow: Frame,
	padding: UIPadding,
	listLayout: UIListLayout,
	medallion: Frame,
	divider: Frame,
	name: TextLabel,
	tagline: TextLabel,
	description: TextLabel,
	chips: { Frame },
}

type Applier = (layout: RaceSelectLayout.Layout) -> ()

local state = {
	race = nil :: string?,
	preset = nil :: number?,
	submitting = false,
	layout = nil :: RaceSelectLayout.Layout?,
}

local gui: ScreenGui? = nil
local backdropGui: ScreenGui? = nil
local connections: { RBXScriptConnection } = {}
local refreshers: { () -> () } = {}
local layoutAppliers: { Applier } = {}

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function v3(t: { number }): Vector3
	return Vector3.new(t[1], t[2], t[3])
end

local function track(connection: RBXScriptConnection)
	table.insert(connections, connection)
end

local function refresh()
	for _, fn in refreshers do
		fn()
	end
end

local function place(instance: GuiObject, r: RaceSelectLayout.Rect?)
	if r == nil then
		instance.Visible = false
		return
	end
	instance.Visible = true
	instance.AnchorPoint = Vector2.zero
	instance.Position = UDim2.fromOffset(r.x, r.y)
	instance.Size = UDim2.fromOffset(r.w, r.h)
end

local function setCamera(active: boolean)
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end
	if active then
		local view = WorldLayout.SelectionCamera
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = CFrame.lookAt(v3(view.position), v3(view.lookAt))
	else
		camera.CameraType = Enum.CameraType.Custom
	end
end

local function selectRace(race: string)
	if state.submitting or state.race == race then
		return
	end
	state.race = race
	state.preset = FacePresets.defaultFor(race)
	refresh()
end

local function selectPreset(presetId: number)
	local preset = FacePresets.get(presetId)
	if state.submitting or preset == nil then
		return
	end
	state.race = preset.race
	state.preset = presetId
	refresh()
end

--------------------------------------------------------------------------------
-- Race card
--------------------------------------------------------------------------------

local function buildCard(parent: Instance, race: string): Card?
	local def = RaceDefinitions.get(race)
	if def == nil then
		return nil
	end
	local accent = rgb(def.uiAccent)

	local glow = Kit.new("Frame", {
		Name = `{race}Glow`,
		BackgroundColor3 = accent,
		BackgroundTransparency = 1,
		Parent = parent,
	})
	Kit.corner(glow, Theme.Radius.Card + 10)

	local root = Kit.glassPanel({ Name = race, Parent = parent }, Theme.Radius.Card)
	local stroke = root:FindFirstChildOfClass("UIStroke") :: UIStroke
	local scale = Kit.new("UIScale", { Parent = root })

	local wash = Kit.new("Frame", {
		BackgroundColor3 = accent,
		BackgroundTransparency = 0.82,
		Size = UDim2.fromScale(1, 0.5),
		BorderSizePixel = 0,
		Parent = root,
	})
	Kit.corner(wash, Theme.Radius.Card)
	Kit.new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0, 1), Parent = wash })

	local content = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = root,
	})
	local padding = Kit.padding(content, 18, 20)
	local listLayout = Kit.list(content, Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Center)

	local medallion = Kit.medallion(72, def.glyph, accent)
	medallion.LayoutOrder = 1
	medallion.Parent = content

	local name = Kit.goldTitle(def.displayName:upper(), 28)
	name.LayoutOrder = 2
	name.Parent = content

	local tagline = Kit.label(def.tagline, 18, Theme.Fonts.Accent, accent)
	tagline.LayoutOrder = 3
	tagline.Parent = content

	local divider = Kit.divider(220)
	divider.LayoutOrder = 4
	divider.Parent = content

	local chipsRow = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 26),
		LayoutOrder = 5,
		Parent = content,
	})
	Kit.list(chipsRow, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Center)
	local chips = {}
	for index, trait in def.traits do
		local chip = Kit.chip(trait, accent)
		chip.LayoutOrder = index
		chip.Parent = chipsRow
		table.insert(chips, chip)
	end

	local description = Kit.label(def.description, 16, Theme.Fonts.Body, Theme.Colors.TextDim)
	description.LayoutOrder = 6
	description.Parent = content

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

	local hit = Kit.new("TextButton", {
		BackgroundTransparency = 1,
		Text = "",
		Size = UDim2.fromScale(1, 1),
		ZIndex = 10,
		Parent = root,
	})
	track(hit.Activated:Connect(function()
		selectRace(race)
	end))

	table.insert(refreshers, function()
		local layout = state.layout
		local both = layout ~= nil and layout.showBothCards
		local selected = state.race == race
		local other = state.race ~= nil and not selected
		Kit.tween(stroke, Kit.Tween.Smooth, {
			Thickness = if selected then 3 else 1.5,
			Transparency = if selected then 0 else 0.15,
		})
		Kit.tween(glow, Kit.Tween.Smooth, { BackgroundTransparency = if selected and both then 0.78 else 1 })
		Kit.tween(dim, Kit.Tween.Smooth, { BackgroundTransparency = if other and both then 0.45 else 1 })
		Kit.tween(scale, Kit.Tween.Smooth, { Scale = if selected and both then 1.03 else 1 })
		tag.Visible = selected and both
		if layout ~= nil and not both then
			-- Compact layouts show only the selected realm's card.
			root.Visible = selected
		end
	end)

	return {
		root = root,
		glow = glow,
		padding = padding,
		listLayout = listLayout,
		medallion = medallion,
		divider = divider,
		name = name,
		tagline = tagline,
		description = description,
		chips = chips,
	}
end

local function applyCardLayout(card: Card, layout: RaceSelectLayout.Layout, r: RaceSelectLayout.Rect?)
	place(card.root, r)
	if r and layout.showBothCards then
		card.glow.Visible = true
		card.glow.Position = UDim2.fromOffset(r.x - 8, r.y - 8)
		card.glow.Size = UDim2.fromOffset(r.w + 16, r.h + 16)
	else
		card.glow.Visible = false
	end
	local compact = not layout.showBothCards
	local pad = if compact then 8 else 18
	local side = if compact then 14 else 20
	card.padding.PaddingTop = UDim.new(0, pad)
	card.padding.PaddingBottom = UDim.new(0, pad)
	card.padding.PaddingLeft = UDim.new(0, side)
	card.padding.PaddingRight = UDim.new(0, side)
	card.listLayout.Padding = UDim.new(0, if compact then 4 else 8)
	card.medallion.Visible = layout.showMedallion
	card.divider.Visible = not compact
	card.name.TextSize = layout.fonts.cardName
	card.tagline.TextSize = layout.fonts.tagline
	card.description.TextSize = layout.fonts.description
	card.description.Visible = layout.showDescription
	for _, chip in card.chips do
		local text = chip:FindFirstChildOfClass("TextLabel")
		if text then
			text.TextSize = layout.fonts.chip
		end
	end
end

--------------------------------------------------------------------------------
-- Compact race toggle  [ ☀ ANGELS | ✶ DEVILS ]
--------------------------------------------------------------------------------

local function buildToggle(parent: Instance): Frame
	local bar = Kit.glassPanel({ Name = "RaceToggle", Parent = parent }, Theme.Radius.Button)
	local row = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = bar })
	Kit.padding(row, 4)
	Kit.list(row, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Center)

	for index, race in RaceDefinitions.Order do
		local def = RaceDefinitions.get(race)
		if def == nil then
			continue
		end
		local button = Kit.new("TextButton", {
			Name = race,
			LayoutOrder = index,
			AutoButtonColor = false,
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 1,
			Size = UDim2.new(0.5, -3, 1, 0),
			Text = `{def.glyph}  {def.displayName:upper()}`,
			TextSize = 16,
			FontFace = Theme.Fonts.BodyBold,
			TextColor3 = Theme.Colors.TextDim,
			Parent = row,
		})
		Kit.corner(button, Theme.Radius.Button - 4)
		local fill = Kit.new("UIGradient", { Color = Theme.GoldSequence, Rotation = 90, Parent = button })
		track(button.Activated:Connect(function()
			selectRace(race)
		end))
		table.insert(refreshers, function()
			local selected = state.race == race
			button.BackgroundTransparency = if selected then 0 else 1
			fill.Enabled = selected
			button.TextColor3 = if selected then Color3.fromRGB(40, 24, 8) else Theme.Colors.TextDim
		end)
	end
	return bar
end

-- Shown in the compact card slot before a realm is chosen.
local function buildPrompt(parent: Instance): Frame
	local prompt = Kit.glassPanel({ Name = "Prompt", Parent = parent }, Theme.Radius.Card)
	local text =
		Kit.label("Tap a realm above to meet your champion.", 15, Theme.Fonts.Accent, Theme.Colors.TextDim)
	text.AnchorPoint = Vector2.new(0.5, 0.5)
	text.Position = UDim2.fromScale(0.5, 0.5)
	text.Size = UDim2.new(1, -24, 0, 20)
	text.Parent = prompt
	table.insert(refreshers, function()
		local layout = state.layout
		prompt.Visible = layout ~= nil and not layout.showBothCards and state.race == nil
	end)
	return prompt
end

--------------------------------------------------------------------------------
-- 3D preview
--------------------------------------------------------------------------------

local function buildPreview(parent: Instance): (Frame, (string?, number?) -> ())
	local frame = Kit.glassPanel({ Name = "Preview", Parent = parent })
	frame.BackgroundTransparency = 0.35

	local viewport = Kit.new("ViewportFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Ambient = Color3.fromRGB(150, 146, 160),
		LightColor = Color3.fromRGB(255, 244, 226),
		LightDirection = Vector3.new(-0.6, -1, -0.8),
		ZIndex = 2,
		Parent = frame,
	})
	Kit.corner(viewport, Theme.Radius.Panel)
	local world = Kit.new("WorldModel", { Parent = viewport })
	local camera = Kit.new("Camera", { FieldOfView = 32, Parent = viewport })
	viewport.CurrentCamera = camera

	local placeholder = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
		Parent = frame,
	})
	Kit.list(placeholder, Enum.FillDirection.Vertical, 10, Enum.HorizontalAlignment.Center)
	local placeholderMedallion = Kit.medallion(84, "✦", Theme.Colors.Gold)
	placeholderMedallion.Parent = placeholder
	local placeholderText =
		Kit.label("Choose a realm to see your champion", 15, Theme.Fonts.Accent, Theme.Colors.TextDim)
	placeholderText.Size = UDim2.new(0.86, 0, 0, 20)
	placeholderText.Parent = placeholder

	local hint = Kit.label("◀  drag to turn  ▶", 14, Theme.Fonts.Body, Theme.Colors.TextMuted)
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Position = UDim2.new(0.5, 0, 1, -8)
	hint.Size = UDim2.new(1, 0, 0, 16)
	hint.ZIndex = 4
	hint.Visible = false
	hint.Parent = frame

	local current: Model? = nil
	local currentRace: string? = nil
	local yaw = math.pi
	local dragging = false
	local lastX = 0

	local function frameModel(model: Model)
		local cf, size = model:GetBoundingBox()
		local center = cf.Position + Vector3.new(0, size.Y * 0.04, 0)
		local distance = size.Y * 2.3 + 2
		camera.CFrame = CFrame.lookAt(center + Vector3.new(0, size.Y * 0.08, -distance), center)
	end

	local function recolor(model: Model, presetId: number)
		local preset = FacePresets.get(presetId)
		if preset == nil then
			return
		end
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				local role = part:GetAttribute("RC_Role")
				if type(role) == "string" then
					part.Color = rgb(FacePresets.roleColor(preset, role))
				end
			end
		end
	end

	local function show(race: string?, presetId: number?)
		if race == nil or presetId == nil then
			if current then
				current:Destroy()
				current = nil
			end
			currentRace = nil
			placeholderText.Text = "Choose a realm to see your champion"
			placeholder.Visible = true
			hint.Visible = false
			return
		end
		if currentRace ~= race or current == nil then
			if current then
				current:Destroy()
				current = nil
			end
			local playerGui = (Players.LocalPlayer :: Player):FindFirstChildOfClass("PlayerGui")
			local folder = playerGui and playerGui:FindFirstChild(PREVIEW_FOLDER)
			local source = folder and folder:FindFirstChild(race)
			if source and source:IsA("Model") then
				local clone = source:Clone()
				clone.Parent = world
				current = clone
				currentRace = race
				frameModel(clone)
			else
				currentRace = nil
			end
		end
		if current then
			recolor(current, presetId)
			placeholder.Visible = false
			hint.Visible = true
		else
			placeholderText.Text = "Summoning your champion…"
			placeholder.Visible = true
			hint.Visible = false
		end
	end

	track(viewport.InputBegan:Connect(function(input: InputObject)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = true
			lastX = input.Position.X
		end
	end))
	track(UserInputService.InputChanged:Connect(function(input: InputObject)
		local moved = input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch
		if dragging and moved then
			yaw += (input.Position.X - lastX) * 0.012
			lastX = input.Position.X
		end
	end))
	track(UserInputService.InputEnded:Connect(function(input: InputObject)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = false
		end
	end))
	track(RunService.RenderStepped:Connect(function(dt: number)
		if current then
			if not dragging then
				yaw += dt * SPIN_SPEED
			end
			current:PivotTo(CFrame.Angles(0, yaw, 0))
		end
	end))

	local playerGui = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")
	track(playerGui.ChildAdded:Connect(function(child)
		if child.Name == PREVIEW_FOLDER then
			task.defer(refresh)
		end
	end))

	table.insert(layoutAppliers, function(layout)
		placeholderMedallion.Visible = layout.showBothCards
	end)

	return frame, show
end

--------------------------------------------------------------------------------
-- Look medallions
--------------------------------------------------------------------------------

local function buildLooks(parent: Instance): Frame
	local panel = Kit.glassPanel({ Name = "Looks", Parent = parent })

	local title = Kit.label("", 16, Theme.Fonts.Display, Theme.Colors.Gold)
	title.AutomaticSize = Enum.AutomaticSize.None
	title.Position = UDim2.fromOffset(0, 6)
	title.Size = UDim2.new(1, 0, 0, 18)
	title.Parent = panel

	local row = Kit.new("Frame", { BackgroundTransparency = 1, Parent = panel })
	Kit.list(row, Enum.FillDirection.Horizontal, 12, Enum.HorizontalAlignment.Center)

	local swatches: { TextButton } = {}
	local swatchSize = 56

	local function rebuildRow(race: string?)
		for _, swatch in swatches do
			swatch:Destroy()
		end
		table.clear(swatches)
		if race == nil then
			return
		end
		for index, preset in FacePresets.forRace(race) do
			local swatch = Kit.new("TextButton", {
				Name = preset.name,
				LayoutOrder = index,
				AutoButtonColor = false,
				BackgroundColor3 = Color3.new(1, 1, 1),
				Size = UDim2.fromOffset(swatchSize, swatchSize),
				Text = "",
				Parent = row,
			})
			Kit.corner(swatch, swatchSize // 2)
			Kit.new("UIGradient", {
				Color = ColorSequence.new(rgb(preset.palette.glow), rgb(preset.palette.cloth)),
				Rotation = 90,
				Parent = swatch,
			})
			local stroke = Kit.goldStroke(swatch, 2, 0.3)
			local check = Kit.new("TextLabel", {
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				Text = "✓",
				TextSize = 24,
				FontFace = Theme.Fonts.BodyBold,
				TextColor3 = Color3.new(1, 1, 1),
				TextStrokeTransparency = 0.2,
				Visible = false,
				Parent = swatch,
			})
			local swatchScale = Kit.new("UIScale", { Parent = swatch })
			track(swatch.Activated:Connect(function()
				selectPreset(preset.id)
			end))
			table.insert(swatches, swatch)
			table.insert(refreshers, function()
				if swatch.Parent == nil then
					return
				end
				local selected = state.preset == preset.id
				stroke.Thickness = if selected then 4 else 2
				stroke.Transparency = if selected then 0 else 0.3
				check.Visible = selected
				Kit.tween(swatchScale, Kit.Tween.Quick, { Scale = if selected then 1.08 else 1 })
			end)
		end
	end

	local shownRace: string? = "__none"
	table.insert(refreshers, function()
		if shownRace ~= state.race then
			shownRace = state.race
			rebuildRow(state.race)
		end
		local preset = if state.preset then FacePresets.get(state.preset) else nil
		title.Text = if preset then `LOOK  ·  {preset.name:upper()}` else "Choose a realm to see its looks"
		title.TextColor3 = if preset then Theme.Colors.Gold else Theme.Colors.TextDim
	end)

	table.insert(layoutAppliers, function(layout)
		swatchSize = layout.swatchSize
		title.TextSize = layout.fonts.looksTitle
		row.Position = UDim2.fromOffset(0, 28)
		row.Size = UDim2.new(1, 0, 0, swatchSize)
		for _, swatch in swatches do
			swatch.Size = UDim2.fromOffset(swatchSize, swatchSize)
			local c = swatch:FindFirstChildOfClass("UICorner")
			if c then
				c.CornerRadius = UDim.new(0, swatchSize // 2)
			end
		end
	end)

	return panel
end

--------------------------------------------------------------------------------
-- Screen
--------------------------------------------------------------------------------

local function build(): ScreenGui
	refreshers = {}
	layoutAppliers = {}
	local playerGui = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")

	-- Full-bleed backdrop (also under the top bar), darkening the world view.
	local back = Kit.new("ScreenGui", {
		Name = "RC_RaceSelectBackdrop",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 9,
	})
	local shade = Kit.new("Frame", {
		BackgroundColor3 = Theme.Colors.Ink,
		BackgroundTransparency = 0.15,
		Size = UDim2.fromScale(1, 1),
		Active = true,
		Parent = back,
	})
	Kit.new("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.05),
			NumberSequenceKeypoint.new(0.5, 0.45),
			NumberSequenceKeypoint.new(1, 0.05),
		}),
		Parent = shade,
	})
	back.Parent = playerGui
	backdropGui = back

	-- Content stays inside the core-UI safe area.
	local screen = Kit.new("ScreenGui", {
		Name = "RC_RaceSelect",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		DisplayOrder = 10,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	local canvas = Kit.new("Frame", { Name = "Canvas", BackgroundTransparency = 1, Parent = screen })
	local canvasScale = Kit.new("UIScale", { Parent = canvas })

	-- Header.
	local header = Kit.new("Frame", { Name = "Header", BackgroundTransparency = 1, Parent = canvas })
	Kit.list(header, Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Center)
	local title = Kit.goldTitle("✦  CHOOSE YOUR REALM  ✦", 40)
	title.LayoutOrder = 1
	title.Parent = header
	local subtitle = Kit.label(
		"Two realms. One Rift. Your story begins here.",
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
	for _, race in RaceDefinitions.Order do
		local card = buildCard(canvas, race)
		if card then
			cards[race] = card
		end
	end
	local toggle = buildToggle(canvas)
	local prompt = buildPrompt(canvas)
	local previewFrame, showPreview = buildPreview(canvas)
	local looks = buildLooks(canvas)

	local confirm, setConfirmEnabled = Kit.button("SELECT A REALM", "gold")
	confirm.Parent = canvas

	local note = Kit.label(
		"Your realm is permanent. Your look is chosen now.",
		14,
		Theme.Fonts.Body,
		Theme.Colors.TextMuted
	)
	note.AutomaticSize = Enum.AutomaticSize.None
	note.Parent = canvas

	table.insert(refreshers, function()
		showPreview(state.race, state.preset)
		if state.submitting then
			setConfirmEnabled(false, "ENTERING…")
		elseif state.race then
			local def = RaceDefinitions.get(state.race)
			setConfirmEnabled(true, if def then def.enterLabel else "ENTER")
		else
			setConfirmEnabled(false, "SELECT A REALM")
		end
	end)

	track(confirm.Activated:Connect(function()
		if state.submitting or state.race == nil or state.preset == nil then
			return
		end
		state.submitting = true
		refresh()
		NetClient.fire("SelectRace", state.race, state.preset)
		log:Debug("requested %s preset %d", state.race, state.preset)
		task.delay(CONFIRM_TIMEOUT, function()
			if gui and state.submitting then
				-- Server did not confirm (rejected or slow): let the player retry.
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
		local layout = RaceSelectLayout.compute(area.X, area.Y)
		state.layout = layout
		local rects = layout.rects

		canvas.Size = UDim2.fromOffset(layout.canvas.w, layout.canvas.h)
		canvasScale.Scale = layout.scale

		place(header, rects.header)
		title.TextSize = layout.fonts.title
		subtitle.TextSize = layout.fonts.subtitle
		subtitle.Visible = layout.showSubtitle
		headerDivider.Visible = layout.showSubtitle

		if layout.showBothCards then
			applyCardLayout(cards.Angel, layout, rects.cardAngel)
			applyCardLayout(cards.Devil, layout, rects.cardDevil)
			toggle.Visible = false
			prompt.Visible = false
		else
			applyCardLayout(cards.Angel, layout, rects.card)
			applyCardLayout(cards.Devil, layout, rects.card)
			place(toggle, rects.toggle)
			place(prompt, rects.card)
		end

		place(previewFrame, rects.preview)
		place(looks, rects.looks)
		place(confirm, rects.confirm)
		confirm.TextSize = layout.fonts.button
		place(note, rects.note)
		note.TextSize = layout.fonts.note

		for _, apply in layoutAppliers do
			apply(layout)
		end
		refresh()
		log:Debug("layout %s %dx%d scale %.2f", layout.mode, area.X, area.Y, layout.scale)
	end

	screen.Parent = playerGui
	track(screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyLayout))
	applyLayout()
	return screen
end

local function show()
	if gui then
		return
	end
	state.race = nil
	state.preset = nil
	state.submitting = false
	setCamera(true)
	gui = build()
	log:Debug("race selection shown")
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
	layoutAppliers = {}
	gui:Destroy()
	gui = nil
	if backdropGui then
		backdropGui:Destroy()
		backdropGui = nil
	end
	state.submitting = false
	state.layout = nil
	setCamera(false)
end

function RaceSelectController:Init()
	PlayerDataController.Changed:Connect(function(data, reason)
		if reason ~= "snapshot" then
			return
		end
		if data.Race == nil then
			show()
		else
			hide()
		end
	end)
end

return RaceSelectController
