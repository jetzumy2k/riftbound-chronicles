--!strict
--[[
	Tooltip — a small explanation card for icons (creator request
	2026-10-26: buff and other icons were hard to understand).

	    Tooltip.attach(guiObject, function()
	        return "Scroll of Insight", "+50% EXP from creatures. 42 min left."
	    end)

	Mouse: shows while the pointer is over the object, beside the pointer.
	Touch: on plain icons (badges, rows) a tap shows it for a few seconds;
	on buttons that do something (potion, Auto, SKILLS...) a press held
	half a second shows it, so a normal tap never pops it up. `touch` can
	force either ("tap" / "hold"). The text is asked for
	each time it opens, so it is always current. One tooltip at a time, in
	its own layer above panels and toasts, kept inside the screen.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Theme)
local Kit = require(script.Parent.Kit)

local Tooltip = {}

local TOUCH_SECONDS = 4
local HOLD_SECONDS = 0.5
local MAX_W = 260

local layer: ScreenGui? = nil
local card: Frame? = nil
local titleLabel: TextLabel? = nil
local bodyLabel: TextLabel? = nil
local owner: GuiObject? = nil
local shownAt = 0

local function build()
	if layer then
		return
	end
	local gui = Kit.new("ScreenGui", {
		Name = "RC_Tooltip",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		DisplayOrder = 30,
	})
	local frame = Kit.new("Frame", {
		BackgroundColor3 = Theme.Colors.Ink,
		BackgroundTransparency = 0.04,
		Size = UDim2.fromOffset(MAX_W, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		Parent = gui,
	})
	Kit.corner(frame, 10)
	Kit.goldStroke(frame, 1.5, 0.15)
	Kit.padding(frame, 8, 10)
	local list = Kit.list(frame, Enum.FillDirection.Vertical, 3, Enum.HorizontalAlignment.Left)
	list.VerticalAlignment = Enum.VerticalAlignment.Top
	local function line(size: number, font: Font, color: Color3): TextLabel
		local l = Kit.label("", size, font, color)
		l.Size = UDim2.fromScale(1, 0)
		l.AutomaticSize = Enum.AutomaticSize.Y
		l.TextWrapped = true
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.Parent = frame
		return l
	end
	titleLabel = line(15, Theme.Fonts.BodyBold, Theme.Colors.GoldBright)
	bodyLabel = line(13, Theme.Fonts.Body, Theme.Colors.Text)
	gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")
	layer, card = gui, frame
end

-- Places the card next to `point` (screen pixels inside the safe area).
local function place(point: Vector2)
	local frame, gui = card, layer
	if frame == nil or gui == nil then
		return
	end
	local screen = gui.AbsoluteSize
	local size = frame.AbsoluteSize
	local x = point.X + 16
	local y = point.Y + 16
	if x + size.X > screen.X - 8 then
		x = point.X - size.X - 12
	end
	if y + size.Y > screen.Y - 8 then
		y = point.Y - size.Y - 12
	end
	frame.Position = UDim2.fromOffset(math.max(8, x), math.max(8, y))
end

local function hide(object: GuiObject?)
	if object ~= nil and owner ~= object then
		return
	end
	-- hide(nil) closes whatever is open.
	owner = nil
	if card then
		card.Visible = false
	end
end

local function show(object: GuiObject, content: () -> (string, string?), point: Vector2)
	build()
	local title, body = content()
	if title == "" then
		return
	end
	owner = object
	shownAt = os.clock();
	(titleLabel :: TextLabel).Text = title
	local b = bodyLabel :: TextLabel
	b.Text = body or ""
	b.Visible = body ~= nil and body ~= ""
	local frame = card :: Frame
	frame.Visible = true
	place(point)
	-- AutomaticSize settles next frame: place again with the real size.
	task.defer(place, point)
end

--[[
	Gives `object` a tooltip. `content` returns the title and an optional
	body. Safe to call on objects that are rebuilt often (connections die
	with the object).
]]
-- Closes any open tooltip (a panel opened, the HUD stepped aside).
function Tooltip.hide()
	hide(nil)
end

function Tooltip.attach(object: GuiObject, content: () -> (string, string?), touch: ("tap" | "hold")?)
	local hold = if touch then touch == "hold" else object:IsA("GuiButton")
	object.MouseEnter:Connect(function(x: number, y: number)
		if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
			return
		end
		local inset = if layer then layer.AbsolutePosition else Vector2.zero
		show(object, content, Vector2.new(x, y) - inset)
	end)
	object.MouseMoved:Connect(function(x: number, y: number)
		if owner == object then
			local inset = if layer then layer.AbsolutePosition else Vector2.zero
			place(Vector2.new(x, y) - inset)
		end
	end)
	object.MouseLeave:Connect(function()
		hide(object)
	end)
	local pressed = 0
	local function showTouch()
		local p = object.AbsolutePosition + Vector2.new(object.AbsoluteSize.X / 2, object.AbsoluteSize.Y)
		local inset = if layer then layer.AbsolutePosition else Vector2.zero
		show(object, content, p - inset)
		local stamp = shownAt
		task.delay(TOUCH_SECONDS, function()
			if owner == object and shownAt == stamp then
				hide(object)
			end
		end)
	end
	object.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if owner == object then
			hide(object)
			return
		end
		if not hold then
			showTouch()
			return
		end
		pressed += 1
		local press = pressed
		task.delay(HOLD_SECONDS, function()
			if pressed == press then
				showTouch()
			end
		end)
	end)
	object.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch then
			pressed += 1
		end
	end)
	object.Destroying:Connect(function()
		hide(object)
	end)
	object:GetPropertyChangedSignal("Visible"):Connect(function()
		if not object.Visible then
			hide(object)
		end
	end)
end

return Tooltip
