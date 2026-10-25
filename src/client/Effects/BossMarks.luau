--!strict
--[[
	BossMarks — a boss's rank marks (Definitions/CreatureLanguage, D-88).
	Display only, on this screen:

	  Sigil   a glowing circle on the ground under the boss in its element's
	          colour (one ring for a mini boss; two rings with rune marks
	          for floor bosses and Bosses), turning slowly. It stays on the
	          ground while the boss flies, showing where it will land.
	          Enraged: it turns red and spins fast.
	  Crown   floor bosses and Bosses: rift shards circling over the head.

	One flat part with a SurfaceGui for the sigil (no textures), a few neon
	parts for the crown, in Workspace.RC_ClientVfx. MobVisualController
	moves them every frame the creature is animated and fades them out when
	it is defeated.
]]

local Workspace = game:GetService("Workspace")

local CreatureLanguage = require(game:GetService("ReplicatedStorage").Shared.Definitions.CreatureLanguage)

local BossMarks = {}

local FADE_SECONDS = 0.9
local CANVAS = 256

export type Marks = {
	sigil: BasePart,
	strokes: { UIStroke },
	fills: { GuiObject },
	shards: { BasePart },
	glow: Color3,
	radius: number,
	scale: number,
	spin: number,
	heat: number,
	fadeStart: number?,
}

local function folder(): Folder
	local existing = Workspace:FindFirstChild("RC_ClientVfx")
	if existing and existing:IsA("Folder") then
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = "RC_ClientVfx"
	created.Parent = Workspace
	return created
end

local function decor(size: Vector3): BasePart
	local p = Instance.new("Part")
	p.Size = size
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	return p
end

-- A circle `fraction` of the canvas wide, centred.
local function ring(gui: SurfaceGui, fraction: number, thickness: number, color: Color3): UIStroke
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromScale(fraction, fraction)
	frame.BackgroundTransparency = 1
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = thickness
	stroke.Color = color
	stroke.Transparency = 0.1
	stroke.Parent = frame
	frame.Parent = gui
	return stroke
end

--[[
	The marks for `model` (an enemy with a boss tier), or nil for creatures
	without a sigil.
]]
function BossMarks.attach(model: Model, enemy: { elite: boolean, tier: string?, glow: { number } }): Marks?
	local rank = CreatureLanguage.rankOf(enemy)
	local spec = CreatureLanguage.sigil(rank)
	if spec == nil then
		return nil
	end
	local scale = model:GetAttribute("RC_Scale")
	local s = if type(scale) == "number" then scale else 1
	local glow = Color3.fromRGB(enemy.glow[1], enemy.glow[2], enemy.glow[3])
	local radius = spec.radius * s
	local sigil = decor(Vector3.new(radius * 2, 0.1, radius * 2))
	sigil.Name = "BossSigil"
	sigil.Transparency = 1
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(CANVAS, CANVAS)
	gui.LightInfluence = 0
	gui.Brightness = 1.6
	gui.Adornee = sigil
	local strokes: { UIStroke } = { ring(gui, 0.94, 7, glow) }
	if spec.rings >= 2 then
		table.insert(strokes, ring(gui, 0.7, 4, glow))
	end
	-- A faint pool of light inside the rings.
	local pool = Instance.new("Frame")
	pool.AnchorPoint = Vector2.new(0.5, 0.5)
	pool.Position = UDim2.fromScale(0.5, 0.5)
	pool.Size = UDim2.fromScale(0.9, 0.9)
	pool.BackgroundColor3 = glow
	pool.BackgroundTransparency = 0.88
	pool.BorderSizePixel = 0
	local poolCorner = Instance.new("UICorner")
	poolCorner.CornerRadius = UDim.new(0.5, 0)
	poolCorner.Parent = pool
	pool.Parent = gui
	local fills: { GuiObject } = { pool }
	-- Rune marks: small diamonds between the two rings.
	for i = 1, spec.runes do
		local a = (i - 1) / spec.runes * math.pi * 2
		local rune = Instance.new("Frame")
		rune.AnchorPoint = Vector2.new(0.5, 0.5)
		rune.Position = UDim2.fromScale(0.5 + math.cos(a) * 0.41, 0.5 + math.sin(a) * 0.41)
		rune.Size = UDim2.fromOffset(16, 16)
		rune.Rotation = 45
		rune.BackgroundColor3 = glow
		rune.BorderSizePixel = 0
		rune.Parent = gui
		table.insert(fills, rune)
	end
	gui.Parent = sigil
	local parent = folder()
	sigil.Parent = parent
	local shards: { BasePart } = {}
	for _ = 1, spec.crown do
		local shard = decor(Vector3.new(0.3, 1, 0.3) * s)
		shard.Name = "BossCrownShard"
		shard.Material = Enum.Material.Neon
		shard.Color = glow
		shard.Transparency = 0.1
		shard.Parent = parent
		table.insert(shards, shard)
	end
	return {
		sigil = sigil,
		strokes = strokes,
		fills = fills,
		shards = shards,
		glow = glow,
		radius = radius,
		scale = s,
		spin = 0,
		heat = 0,
		fadeStart = nil,
	}
end

--[[
	Places the marks: the sigil on `ground` (a point on the ground under the
	boss), the crown over `head`. Returns false once faded out (destroyed).
]]
function BossMarks.update(
	marks: Marks,
	now: number,
	dt: number,
	ground: Vector3,
	head: Vector3,
	enraged: boolean
): boolean
	local fade = 0
	if marks.fadeStart then
		fade = math.clamp((now - marks.fadeStart) / FADE_SECONDS, 0, 1)
		if fade >= 1 then
			BossMarks.destroy(marks)
			return false
		end
	end
	marks.heat += ((if enraged then 1 else 0) - marks.heat) * (1 - math.exp(-4 * dt))
	local turn = CreatureLanguage.SIGIL_TURN
		+ (CreatureLanguage.SIGIL_TURN_ENRAGED - CreatureLanguage.SIGIL_TURN) * marks.heat
	marks.spin = (marks.spin + dt * math.pi * 2 / turn) % (math.pi * 2)
	local hot = CreatureLanguage.ENRAGED
	local color = marks.glow:Lerp(Color3.fromRGB(hot[1], hot[2], hot[3]), marks.heat * 0.8)
	marks.sigil.CFrame = CFrame.new(ground + Vector3.new(0, 0.04, 0)) * CFrame.Angles(0, marks.spin, 0)
	for _, stroke in marks.strokes do
		stroke.Color = color
		stroke.Transparency = 0.1 + 0.9 * fade
	end
	for i, fill in marks.fills do
		fill.BackgroundColor3 = color
		fill.BackgroundTransparency = if i == 1 then 0.88 + 0.12 * fade else fade
	end
	local count = #marks.shards
	local s = marks.scale
	for i, shard in marks.shards do
		local a = -marks.spin * 2 + (i - 1) / count * math.pi * 2
		local bob = math.sin(now * 2 + i) * 0.12 * s
		local at = head + Vector3.new(math.cos(a) * 0.8 * s, 1.3 * s + bob, math.sin(a) * 0.8 * s)
		-- Each shard leans out from the centre.
		shard.CFrame = CFrame.new(at) * CFrame.Angles(0, -a, 0) * CFrame.Angles(0, 0, math.rad(-18))
		shard.Color = color
		shard.Transparency = 0.1 + 0.9 * fade
	end
	return true
end

function BossMarks.fade(marks: Marks, now: number)
	if marks.fadeStart == nil then
		marks.fadeStart = now
	end
end

function BossMarks.destroy(marks: Marks)
	marks.sigil:Destroy()
	for _, shard in marks.shards do
		shard:Destroy()
	end
end

return BossMarks
