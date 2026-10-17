--!strict
--[[
	SkillIcon — draws a SkillIcons motif with UI frames (D-45 follow-up):
	an element-coloured tile with the motif and a soft drop shadow. Used by
	the skill tree, the skill bar and the skill info card.

	    SkillIcon.forSkill(skill, 56, { dim = true, lock = true })
	    SkillIcon.new({ icon = "sword", element = "Steel", size = 24, plain = true })

	Options
	  plain   no tile background (motif only, e.g. inline in a header)
	  round   circular tile (specials)
	  dim     darkened (not learned yet / not usable)
	  lock    a small padlock badge (locked by level)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SkillIcons = require(ReplicatedStorage.Shared.Definitions.SkillIcons)

local SkillIcon = {}

export type Options = {
	icon: string?,
	element: string?,
	size: number,
	plain: boolean?,
	round: boolean?,
	dim: boolean?,
	lock: boolean?,
	zIndex: number?,
}

local WHITE = Color3.fromRGB(250, 248, 240)
local GOLD = Color3.fromRGB(255, 205, 90)
local SHADOW = Color3.new(0, 0, 0)

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

type Palette = { a: Color3, m: Color3, g: Color3, d: Color3, bg: Color3 }

local function palette(element: string?): Palette
	local e = (SkillIcons.Elements :: any)[element or ""] or SkillIcons.Elements.Steel
	local main, dark = rgb(e.main), rgb(e.dark)
	return { a = WHITE, m = main, g = GOLD, d = dark, bg = dark:Lerp(main, 0.4) }
end

local function frame(props: { [string]: any }): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	for key, value in props do
		(f :: any)[key] = value
	end
	return f
end

local function circle(parent: Instance)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = parent
end

local function ringFrame(size: number, thickness: number, color: Color3, transparency: number): Frame
	-- UIStroke draws outside the frame, so the frame is the ring's hole.
	local ring = frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(math.max(size - thickness * 2, 1), math.max(size - thickness * 2, 1)),
		BackgroundTransparency = 1,
	})
	circle(ring)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = math.max(thickness, 1)
	stroke.Color = color
	stroke.Transparency = transparency
	stroke.Parent = ring
	return ring
end

-- One shape as a GuiObject inside a layer of `k` pixels per unit.
local function build(
	shape: SkillIcons.Shape,
	k: number,
	color: Color3,
	transparency: number,
	z: number
): GuiObject
	local x, y = shape.x * k, shape.y * k
	if shape.kind == "bar" then
		local w, h = (shape.w or 0) * k, (shape.h or 0) * k
		local bar = frame({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(x, y),
			Size = UDim2.fromOffset(w, h),
			Rotation = shape.r or 0,
			BackgroundColor3 = color,
			BackgroundTransparency = transparency,
			ZIndex = z,
		})
		local round = shape.round or 0
		if round > 0 then
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, math.min(w, h) * round / 100)
			corner.Parent = bar
		end
		return bar
	elseif shape.kind == "dot" then
		local d = (shape.d or 0) * k
		local dot = frame({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(x, y),
			Size = UDim2.fromOffset(d, d),
			BackgroundColor3 = color,
			BackgroundTransparency = transparency,
			ZIndex = z,
		})
		circle(dot)
		return dot
	end
	local d, t = (shape.d or 0) * k, (shape.t or 1) * k
	local ring = ringFrame(d, t, color, transparency)
	ring.ZIndex = z
	if shape.kind == "ring" then
		ring.Position = UDim2.fromOffset(x, y)
		return ring
	end
	-- Arc: the ring inside a clipping half-box whose edge runs through the centre.
	local side = shape.side or "Top"
	local clip = frame({ BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = z })
	clip.Position = UDim2.fromOffset(x, y)
	if side == "Top" or side == "Bottom" then
		clip.Size = UDim2.fromOffset(d + 2, d / 2 + 1)
		clip.AnchorPoint = Vector2.new(0.5, if side == "Top" then 1 else 0)
		ring.Position = UDim2.fromScale(0.5, if side == "Top" then 1 else 0)
	else
		clip.Size = UDim2.fromOffset(d / 2 + 1, d + 2)
		clip.AnchorPoint = Vector2.new(if side == "Left" then 1 else 0, 0.5)
		ring.Position = UDim2.fromScale(if side == "Left" then 1 else 0, 0.5)
	end
	ring.Parent = clip
	return clip
end

-- Draws `shapes` into a new transparent layer of `size` pixels.
local function motif(
	shapes: { SkillIcons.Shape },
	size: number,
	colors: Palette,
	z: number,
	shadow: boolean
): Frame
	local layer = frame({ BackgroundTransparency = 1, Size = UDim2.fromOffset(size, size), ZIndex = z })
	local k = size / 100
	local order = 1
	if shadow then
		local offset = frame({
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(1.6 * k, 2.4 * k),
			Size = UDim2.fromScale(1, 1),
			ZIndex = 1,
			Parent = layer,
		})
		for _, shape in shapes do
			build(shape, k, SHADOW, 0.62, order).Parent = offset
			order += 1
		end
	end
	local front =
		frame({ BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = layer })
	for _, shape in shapes do
		build(shape, k, (colors :: any)[shape.c] or WHITE, 0, order).Parent = front
		order += 1
	end
	return layer
end

function SkillIcon.new(options: Options): Frame
	local size = options.size
	local colors = palette(options.element)
	local z = options.zIndex or 1
	local root = frame({
		Name = "SkillIcon",
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = colors.d,
		BackgroundTransparency = if options.plain then 1 else 0,
		ZIndex = z,
	})
	if not options.plain then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = if options.round then UDim.new(0.5, 0) else UDim.new(0.2, 0)
		corner.Parent = root
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = 90
		gradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(150, 150, 160))
		gradient.Parent = root
		local glow = frame({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.42),
			Size = UDim2.fromScale(0.86, 0.86),
			BackgroundColor3 = colors.bg,
			BackgroundTransparency = 0.25,
			ZIndex = z,
			Parent = root,
		})
		circle(glow)
	end
	local shapes = SkillIcons.get(options.icon) or SkillIcons.get("star") :: { SkillIcons.Shape }
	local inner = math.floor(size * (if options.plain then 1 else if options.round then 0.7 else 0.78))
	local layer = motif(shapes, inner, colors, z + 1, size >= 28)
	layer.AnchorPoint = Vector2.new(0.5, 0.5)
	layer.Position = UDim2.fromScale(0.5, 0.5)
	layer.Parent = root
	if options.dim then
		local shade = frame({
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.fromRGB(12, 12, 20),
			BackgroundTransparency = 0.45,
			ZIndex = z + 2,
			Parent = root,
		})
		if not options.plain then
			local corner = Instance.new("UICorner")
			corner.CornerRadius = if options.round then UDim.new(0.5, 0) else UDim.new(0.2, 0)
			corner.Parent = shade
		end
	end
	if options.lock then
		local badge = math.max(math.floor(size * 0.42), 14)
		local lock =
			motif(SkillIcons.get("lock") :: { SkillIcons.Shape }, badge, palette("Steel"), z + 3, false)
		lock.AnchorPoint = Vector2.new(1, 1)
		lock.Position = UDim2.fromScale(1, 1)
		lock.Parent = root
	end
	return root
end

-- The icon of a skill (or a branch: anything with `icon`, optionally `fx`).
function SkillIcon.forSkill(skill: any, size: number, options: { [string]: any }?): Frame
	local opts: Options = {
		icon = skill.icon,
		element = if skill.fx then skill.fx.element else (options and options.element),
		size = size,
		round = skill.type == "Special",
	}
	if options then
		for key, value in options do
			(opts :: any)[key] = value
		end
	end
	return SkillIcon.new(opts)
end

return SkillIcon
