--!strict
--[[
	HudLayout — players move their HUD pieces where they like (creator
	request 2026-10-24, PLAN.md D-74; ids and rules in Layout/HudSlots).

	  - Controllers register what can move:
	        HudLayout.register("Bag", toggle)
	    and call `HudLayout.apply(id)` after placing it themselves (pieces
	    that re-place on refresh, like the potion button), so a moved piece
	    stays where the player put it.
	  - "📐" (top left, next to the HUD) opens the editor: every piece gets a
	    gold outline you drag with a finger or the mouse; Save keeps the
	    layout in the profile (SetHudLayout), Reset puts everything back,
	    Cancel drops the changes.
	  - Positions are screen fractions of each piece's centre, kept fully
	    on screen on any device.

	Display only: nothing here changes what the server allows.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local HudSlots = require(Shared.Layout.HudSlots)
local CombatButtonsLayout = require(Shared.Layout.CombatButtonsLayout)
local NetClient = require(Shared.Net.Client)
local Signal = require(Shared.Util.Signal)

local Theme = require(script.Parent.Theme)
local Kit = require(script.Parent.Kit)
local Tooltip = require(script.Parent.Tooltip)

type Default = { position: UDim2, anchor: Vector2 }
type Entry = { objects: { GuiObject }, defaults: { [GuiObject]: Default }, moved: boolean }

local HudLayout = {
	-- Fired after the layout changes (saved, reset, loaded); controllers
	-- that place pieces themselves re-place and call apply.
	Changed = Signal.new(),
}

local entries: { [string]: Entry } = {}
local saved: HudSlots.Saved = {}
local editing: { [string]: { X: number, Y: number } }? = nil
local overlay: ScreenGui? = nil
local editButton: TextButton? = nil

local function screenSize(object: GuiObject): Vector2
	local layer = object:FindFirstAncestorOfClass("ScreenGui")
	local size = if layer then layer.AbsoluteSize else Vector2.zero
	if size.X < 10 then
		local camera = Workspace.CurrentCamera
		size = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	end
	return size
end

local function layoutFor(id: string): { X: number, Y: number }?
	if editing then
		return editing[id]
	end
	return saved[id]
end

--[[
	Puts `id`'s pieces where the player moved them, or back to where their
	controller put them.
]]
function HudLayout.apply(id: string)
	local entry = entries[id]
	if entry == nil then
		return
	end
	local spot = layoutFor(id)
	for _, object in entry.objects do
		if spot then
			if not entry.moved then
				-- Remember the controller's own placement for Reset.
				entry.defaults[object] = { position = object.Position, anchor = object.AnchorPoint }
			end
			local screen = screenSize(object)
			local size = object.AbsoluteSize
			local x, y = HudSlots.clampCenter(spot.X, spot.Y, size.X, size.Y, screen.X, screen.Y)
			object.AnchorPoint = Vector2.new(0.5, 0.5)
			object.Position = UDim2.fromScale(x, y)
		else
			local default = entry.defaults[object]
			if entry.moved and default then
				object.AnchorPoint = default.anchor
				object.Position = default.position
			end
		end
	end
	entry.moved = spot ~= nil
end

function HudLayout.register(id: string, object: GuiObject)
	local entry = entries[id]
	if entry == nil then
		entry = { objects = {}, defaults = {}, moved = false }
		entries[id] = entry
	end
	table.insert(entry.objects, object)
	entry.defaults[object] = { position = object.Position, anchor = object.AnchorPoint }
	object:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if layoutFor(id) then
			HudLayout.apply(id)
		end
	end)
	HudLayout.apply(id)
end

--[[
	A controller's new placement for a registered piece (the screen changed
	size): used now unless the player moved the piece, and kept for Reset.
]]
function HudLayout.setDefault(id: string, object: GuiObject, position: UDim2, anchor: Vector2)
	local entry = entries[id]
	if entry then
		entry.defaults[object] = { position = position, anchor = anchor }
		if entry.moved then
			return
		end
	end
	object.AnchorPoint = anchor
	object.Position = position
end

--[[
	Places the SKILLS or BAG toggle (`which`) from CombatButtonsLayout.toggles
	and re-places it whenever its screen changes size; `changed` runs after
	(to refresh its text). Returns whether the toggle is compact right now:
	a 44 px icon button on phone landscape (D-86), else the labelled pill.
]]
function HudLayout.bindToggle(id: string, object: GuiObject, which: string, changed: () -> ()): () -> boolean
	local compact = false
	local function place()
		local screen = screenSize(object)
		local toggles = CombatButtonsLayout.toggles(screen.X, screen.Y)
		local t = (toggles :: any)[which] :: CombatButtonsLayout.Toggle
		compact = toggles.compact
		object.Size = UDim2.fromOffset(t.w, t.h)
		HudLayout.setDefault(id, object, UDim2.new(1, -t.right, 1, -t.bottom), Vector2.new(1, 1))
		changed()
	end
	local layer = object:FindFirstAncestorOfClass("ScreenGui")
	if layer then
		layer:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
	end
	place()
	return function(): boolean
		return compact
	end
end

local function applyAll()
	for id in entries do
		HudLayout.apply(id)
	end
	HudLayout.Changed:Fire()
end

-- The layout saved in the profile (from the snapshot).
function HudLayout.load(layout: any)
	saved = HudSlots.sanitize(layout)
	if editing == nil then
		applyAll()
	end
end

--------------------------------------------------------------------------------
-- Editor
--------------------------------------------------------------------------------

local function closeEditor(changes: HudSlots.Saved?)
	local shown = overlay
	editing = nil
	overlay = nil
	if shown then
		shown:Destroy()
	end
	if changes then
		saved = changes
		NetClient.fire("SetHudLayout", changes)
	end
	-- Pieces hidden outside the editor (e.g. the zone badge) go back.
	for _, entry in entries do
		for _, object in entry.objects do
			local was = object:GetAttribute("RC_HudWasVisible")
			if was ~= nil then
				object.Visible = was == true
				object:SetAttribute("RC_HudWasVisible", nil)
			end
		end
	end
	applyAll()
end

local function editorButton(text: string, accent: boolean): TextButton
	local b = Kit.new("TextButton", {
		Size = UDim2.fromOffset(96, 44),
		BackgroundColor3 = if accent then Theme.Colors.Gold else Theme.Colors.GlassRaised,
		Text = text,
		TextSize = 14,
		FontFace = Theme.Fonts.BodyBold,
		TextColor3 = if accent then Color3.fromRGB(30, 20, 8) else Theme.Colors.Text,
		AutoButtonColor = true,
	})
	Kit.corner(b, 10)
	return b
end

function HudLayout.openEditor()
	if overlay then
		return
	end
	local working: { [string]: { X: number, Y: number } } = table.clone(saved)
	editing = working
	local layer = Kit.new("ScreenGui", {
		Name = "RC_HudEditor",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 30,
	})
	overlay = layer
	Kit.new("Frame", {
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.6,
		Size = UDim2.fromScale(1, 1),
		Parent = layer,
	})
	layer.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")

	local handles: { [string]: TextButton } = {}
	local dragging: { id: string, input: InputObject, offset: Vector2 }? = nil

	local function syncHandle(id: string)
		local entry = entries[id]
		local handle: TextButton? = handles[id]
		local object: GuiObject? = if entry then entry.objects[1] else nil
		if not handle or not object then
			return
		end
		local origin = layer.AbsolutePosition
		handle.Position =
			UDim2.fromOffset(object.AbsolutePosition.X - origin.X, object.AbsolutePosition.Y - origin.Y)
		handle.Size =
			UDim2.fromOffset(math.max(object.AbsoluteSize.X, 44), math.max(object.AbsoluteSize.Y, 44))
	end

	for _, id in HudSlots.IDS do
		local entry = entries[id]
		local object: GuiObject? = if entry then entry.objects[1] else nil
		if not object then
			continue
		end
		-- Show pieces that are hidden right now so they can be placed too.
		for _, piece in (entry :: Entry).objects do
			if not piece.Visible then
				piece:SetAttribute("RC_HudWasVisible", false)
				piece.Visible = true
			end
		end
		local handle = Kit.new("TextButton", {
			Name = id,
			BackgroundColor3 = Theme.Colors.Gold,
			BackgroundTransparency = 0.75,
			Text = HudSlots.LABELS[id] or id,
			TextSize = 12,
			TextWrapped = true,
			FontFace = Theme.Fonts.BodyBold,
			TextColor3 = Theme.Colors.GoldBright,
			TextStrokeTransparency = 0.2,
			AutoButtonColor = false,
			ZIndex = 2,
			Parent = layer,
		})
		Kit.corner(handle, 8)
		Kit.new("UIStroke", {
			Color = Theme.Colors.GoldBright,
			Thickness = 2,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Parent = handle,
		})
		handles[id] = handle
		handle.InputBegan:Connect(function(input: InputObject)
			local kind = input.UserInputType
			if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
				local center = handle.AbsolutePosition + handle.AbsoluteSize / 2
				dragging = {
					id = id,
					input = input,
					offset = Vector2.new(input.Position.X, input.Position.Y) - center,
				}
			end
		end)
	end
	task.defer(function()
		for id in handles do
			syncHandle(id)
		end
	end)

	local moveConnection = UserInputService.InputChanged:Connect(function(input: InputObject)
		local drag = dragging
		if drag == nil then
			return
		end
		local moved = input == drag.input
			or (
				drag.input.UserInputType == Enum.UserInputType.MouseButton1
				and input.UserInputType == Enum.UserInputType.MouseMovement
			)
		if not moved then
			return
		end
		local size = layer.AbsoluteSize
		local origin = layer.AbsolutePosition
		local center = Vector2.new(input.Position.X, input.Position.Y) - drag.offset - origin
		working[drag.id] = {
			X = math.clamp(center.X / math.max(size.X, 1), 0, 1),
			Y = math.clamp(center.Y / math.max(size.Y, 1), 0, 1),
		}
		HudLayout.apply(drag.id)
		syncHandle(drag.id)
	end)
	local endConnection = UserInputService.InputEnded:Connect(function(input: InputObject)
		local drag = dragging
		if drag and (input == drag.input or input.UserInputType == Enum.UserInputType.MouseButton1) then
			dragging = nil
		end
	end)
	layer.Destroying:Connect(function()
		moveConnection:Disconnect()
		endConnection:Disconnect()
	end)

	-- Instructions and buttons in the middle (the pieces sit at the edges).
	local bar = Kit.glassPanel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(330, 104),
		BackgroundTransparency = 0.04,
		ZIndex = 3,
		Parent = layer,
	})
	local hint =
		Kit.label("Drag the gold boxes to move your HUD.", 14, Theme.Fonts.BodyBold, Theme.Colors.Text)
	hint.AutomaticSize = Enum.AutomaticSize.None
	hint.Position = UDim2.fromOffset(0, 10)
	hint.Size = UDim2.new(1, 0, 0, 20)
	hint.Parent = bar
	local row = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 46),
		Size = UDim2.new(1, 0, 0, 44),
		Parent = bar,
	})
	Kit.list(row, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center)
	local reset = editorButton("Reset", false)
	reset.LayoutOrder = 1
	reset.Parent = row
	reset.Activated:Connect(function()
		table.clear(working)
		for id in entries do
			HudLayout.apply(id)
		end
		HudLayout.Changed:Fire()
		task.defer(function()
			for id in handles do
				syncHandle(id)
			end
		end)
	end)
	local cancel = editorButton("Cancel", false)
	cancel.LayoutOrder = 2
	cancel.Parent = row
	cancel.Activated:Connect(function()
		closeEditor(nil)
	end)
	local save = editorButton("Save", true)
	save.LayoutOrder = 3
	save.Parent = row
	save.Activated:Connect(function()
		closeEditor(HudSlots.sanitize(working))
	end)
end

--------------------------------------------------------------------------------
-- The "📐" button
--------------------------------------------------------------------------------

function HudLayout.start()
	local layer = Kit.new("ScreenGui", {
		Name = "RC_HudEditButton",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		DisplayOrder = 6,
	})
	local b = Kit.new("TextButton", {
		Name = "EditHud",
		Size = UDim2.fromOffset(44, 44),
		BackgroundColor3 = Theme.Colors.Glass,
		BackgroundTransparency = 0.15,
		Text = "📐",
		TextSize = 22,
		FontFace = Theme.Fonts.BodyBold,
		TextColor3 = Theme.Colors.GoldBright,
		AutoButtonColor = true,
		Visible = false,
		Parent = layer,
	})
	Tooltip.attach(b, function()
		return "📐 Edit HUD", "Move the HUD pieces where you like them; Reset puts them back."
	end)
	Kit.corner(b, 22)
	Kit.goldStroke(b, 1.5, 0.2)
	b.Activated:Connect(HudLayout.openEditor)
	layer.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")
	editButton = b
	-- Right of the HUD panels (260 px wide, scaled like HudController).
	local function place()
		local camera = Workspace.CurrentCamera
		local height = if camera then camera.ViewportSize.Y else 720
		local scale = math.clamp(height / 720, 0.85, 1.35)
		b.AnchorPoint = Vector2.zero
		b.Position = UDim2.fromOffset(math.floor(260 * scale + 18), 10)
		HudLayout.apply("Edit")
	end
	place()
	HudLayout.register("Edit", b)
	layer:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
end

function HudLayout.setEditVisible(visible: boolean)
	if editButton then
		editButton.Visible = visible
	end
end

return HudLayout
