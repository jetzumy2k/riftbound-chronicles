--!strict
--[[
	Kit — reusable components for the dark-glass + gold fantasy UI.
	No images are required: depth comes from gradients, layered strokes and
	glows, so the UI works before any art assets are uploaded.

	Components never decide game outcomes; they only render and forward input.
]]

local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)

local Kit = {}

local QUICK = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SMOOTH = TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

Kit.Tween = {
	Quick = QUICK,
	Smooth = SMOOTH,
}

--[[
	Creates an instance with properties and children:
	    Kit.new("Frame", { Size = ..., Parent = gui }, { Kit.new("UICorner") })
]]
function Kit.new(className: string, props: { [string]: any }?, children: { Instance }?): any
	local instance = Instance.new(className) :: any
	local parent = nil
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			else
				instance[key] = value
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = instance
		end
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

function Kit.tween(instance: Instance, info: TweenInfo, goal: { [string]: any }): Tween
	local tween = TweenService:Create(instance, info, goal)
	tween:Play()
	return tween
end

function Kit.corner(parent: Instance, radius: number): UICorner
	return Kit.new("UICorner", { CornerRadius = UDim.new(0, radius), Parent = parent })
end

function Kit.padding(parent: Instance, all: number, horizontal: number?): UIPadding
	local h = horizontal or all
	return Kit.new("UIPadding", {
		PaddingTop = UDim.new(0, all),
		PaddingBottom = UDim.new(0, all),
		PaddingLeft = UDim.new(0, h),
		PaddingRight = UDim.new(0, h),
		Parent = parent,
	})
end

function Kit.list(
	parent: Instance,
	direction: Enum.FillDirection,
	gap: number,
	align: Enum.HorizontalAlignment?
): UIListLayout
	return Kit.new("UIListLayout", {
		FillDirection = direction,
		Padding = UDim.new(0, gap),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Parent = parent,
	})
end

--[[
	Positions a GuiObject at a layout rect {x, y, w, h} (canvas units) and
	shows it; a nil rect hides it.
]]
function Kit.place(instance: GuiObject, r: { x: number, y: number, w: number, h: number }?)
	if r == nil then
		instance.Visible = false
		return
	end
	instance.Visible = true
	instance.AnchorPoint = Vector2.zero
	instance.Position = UDim2.fromOffset(r.x, r.y)
	instance.Size = UDim2.fromOffset(r.w, r.h)
end

--[[
	Full-bleed darkening backdrop for full-screen menus (covers the top bar
	too and swallows touches meant for the world).
]]
function Kit.backdrop(name: string, displayOrder: number, parent: Instance): ScreenGui
	local screen = Kit.new("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = displayOrder,
	})
	local shade = Kit.new("Frame", {
		BackgroundColor3 = Theme.Colors.Ink,
		BackgroundTransparency = 0.15,
		Size = UDim2.fromScale(1, 1),
		Active = true,
		Parent = screen,
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
	screen.Parent = parent
	return screen
end

--[[
	Gold border with a moving-light sheen. Returns the stroke and its gradient.
]]
function Kit.goldStroke(parent: Instance, thickness: number, transparency: number?): (UIStroke, UIGradient)
	local stroke = Kit.new("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = Color3.new(1, 1, 1),
		Thickness = thickness,
		Transparency = transparency or 0,
		Parent = parent,
	})
	local gradient = Kit.new("UIGradient", {
		Color = Theme.GoldSequence,
		Rotation = 35,
		Parent = stroke,
	})
	return stroke, gradient
end

--[[
	Frosted dark-glass panel with a gold frame and a soft top highlight.
]]
function Kit.glassPanel(props: { [string]: any }?, radius: number?): Frame
	local frame = Kit.new("Frame", {
		BackgroundColor3 = Theme.Colors.Glass,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
	})
	if props then
		for key, value in props do
			if key ~= "Parent" then
				(frame :: any)[key] = value
			end
		end
	end
	local r = radius or Theme.Radius.Panel
	Kit.corner(frame, r)
	Kit.new("UIGradient", {
		Color = ColorSequence.new(Theme.Colors.GlassHighlight, Theme.Colors.Glass),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.45, 0.1),
			NumberSequenceKeypoint.new(1, 0.15),
		}),
		Rotation = 90,
		Parent = frame,
	})
	Kit.goldStroke(frame, 1.5, 0.15)
	if props and props.Parent then
		frame.Parent = props.Parent
	end
	return frame
end

function Kit.label(text: string, size: number, font: Font?, color: Color3?): TextLabel
	return Kit.new("TextLabel", {
		BackgroundTransparency = 1,
		Text = text,
		TextSize = size,
		FontFace = font or Theme.Fonts.Body,
		TextColor3 = color or Theme.Colors.Text,
		TextWrapped = true,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, size + 4),
	})
end

-- Title text filled with the gold gradient.
function Kit.goldTitle(text: string, size: number): TextLabel
	local label = Kit.label(text, size, Theme.Fonts.Display, Color3.new(1, 1, 1))
	Kit.new("UIGradient", { Color = Theme.GoldSequence, Rotation = 90, Parent = label })
	Kit.new("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		Color = Color3.fromRGB(40, 24, 8),
		Thickness = 1.2,
		Transparency = 0.35,
		Parent = label,
	})
	return label
end

--[[
	Ornamental divider:  ────── ◆ ──────
]]
function Kit.divider(width: number): Frame
	local holder = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(width, 14),
	})
	for _, side in { -1, 1 } do
		local line = Kit.new("Frame", {
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(if side < 0 then 1 else 0, 0.5),
			Position = UDim2.new(0.5, side * 12, 0.5, 0),
			Size = UDim2.new(0.5, -14, 0, 2),
			Parent = holder,
		})
		Kit.new("UIGradient", {
			Color = ColorSequence.new(Theme.Colors.Gold),
			Transparency = NumberSequence.new(if side < 0 then 1 else 0, if side < 0 then 0 else 1),
			Parent = line,
		})
	end
	local gem = Kit.new("Frame", {
		BackgroundColor3 = Theme.Colors.GoldBright,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(9, 9),
		Rotation = 45,
		Parent = holder,
	})
	Kit.goldStroke(gem, 1)
	return holder
end

-- Small pill tag:  ◆ Swift
function Kit.chip(text: string, accent: Color3, textSize: number?): Frame
	local chip = Kit.new("Frame", {
		BackgroundColor3 = Theme.Colors.GlassRaised,
		BackgroundTransparency = 0.2,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 26),
	})
	Kit.corner(chip, Theme.Radius.Chip)
	Kit.padding(chip, 0, 10)
	Kit.new("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = accent,
		Transparency = 0.45,
		Thickness = 1,
		Parent = chip,
	})
	Kit.new("TextLabel", {
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		Text = `◆ {text}`,
		TextSize = textSize or 14,
		FontFace = Theme.Fonts.BodyBold,
		TextColor3 = Theme.Colors.Text,
		Parent = chip,
	})
	return chip
end

-- Round emblem with a glyph and a glowing accent ring.
function Kit.medallion(size: number, glyph: string, accent: Color3): Frame
	local medallion = Kit.new("Frame", {
		BackgroundColor3 = Theme.Colors.Ink,
		Size = UDim2.fromOffset(size, size),
	})
	Kit.corner(medallion, size // 2)
	Kit.new("UIGradient", {
		Color = ColorSequence.new(accent:Lerp(Theme.Colors.Ink, 0.55), Theme.Colors.Ink),
		Rotation = 90,
		Parent = medallion,
	})
	Kit.goldStroke(medallion, 2)
	Kit.new("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = glyph,
		TextSize = math.floor(size * 0.52),
		FontFace = Theme.Fonts.DisplayHeavy,
		TextColor3 = accent,
		Parent = medallion,
	})
	return medallion
end

--[[
	Primary gold button (or "ghost" outline variant) with press feedback.
	Returns the button and a setEnabled(enabled, text?) function.
]]
function Kit.button(text: string, variant: "gold" | "ghost"?): (TextButton, (boolean, string?) -> ())
	local isGold = (variant or "gold") == "gold"
	local button = Kit.new("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(1, 1, 1),
		Size = UDim2.fromOffset(280, 56),
		Text = text,
		TextSize = 18,
		FontFace = Theme.Fonts.BodyBold,
		TextColor3 = if isGold then Color3.fromRGB(40, 24, 8) else Theme.Colors.Gold,
		BackgroundTransparency = if isGold then 0 else 0.6,
	})
	Kit.corner(button, Theme.Radius.Button)
	local fill = Kit.new("UIGradient", {
		Color = if isGold then Theme.GoldSequence else ColorSequence.new(Theme.Colors.GlassRaised),
		Rotation = 90,
		Parent = button,
	})
	local stroke = Kit.goldStroke(button, 2, if isGold then 0.1 else 0.3)
	local scale = Kit.new("UIScale", { Parent = button })

	local enabled = true
	button.MouseEnter:Connect(function()
		if enabled then
			Kit.tween(scale, QUICK, { Scale = 1.03 })
		end
	end)
	button.MouseLeave:Connect(function()
		Kit.tween(scale, QUICK, { Scale = 1 })
	end)
	button.MouseButton1Down:Connect(function()
		if enabled then
			Kit.tween(scale, QUICK, { Scale = 0.96 })
		end
	end)
	button.MouseButton1Up:Connect(function()
		Kit.tween(scale, QUICK, { Scale = 1 })
	end)

	local function setEnabled(value: boolean, newText: string?)
		enabled = value
		button.Active = value
		if newText then
			button.Text = newText
		end
		if value then
			fill.Color = if isGold then Theme.GoldSequence else ColorSequence.new(Theme.Colors.GlassRaised)
			button.TextColor3 = if isGold then Color3.fromRGB(40, 24, 8) else Theme.Colors.Gold
			stroke.Transparency = if isGold then 0.1 else 0.3
		else
			fill.Color = ColorSequence.new(Theme.Colors.Disabled)
			button.TextColor3 = Theme.Colors.TextDim
			stroke.Transparency = 0.7
		end
	end

	return button, setEnabled
end

return Kit
