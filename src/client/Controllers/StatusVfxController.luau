--!strict
--[[
	StatusVfxController — shows skill statuses on every fighter (Phase 5,
	D-45). Display only: the server publishes them as model attributes
	(CombatService: Stunned, Frozen, Rooted, ... Shield) on models tagged
	"RC_Combatant".

	Each status has:
	  - a chip above the head with an icon and a word ("🧊 FROZEN"), never
	    colour alone (the selected target shows them on its target plate);
	  - an aura while it lasts: stars circling the head (stun), a block of
	    ice (freeze), frost shards at the feet (root), mist (slow), green
	    bubbles (poison), flames (burn), a stone sheen (hardening), red
	    sparks (empower), wind streaks (haste), rising sparkles (regen), a
	    reticle (mark), dark wisps (weaken), a gold outline (guard), a
	    bubble (shield), "!" over taunted creatures.
	Built-in particle textures only; a handful of particles per aura so
	phones stay smooth. Nothing exists while no status is active.
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local UI = script.Parent.Parent.UI
local Theme = require(UI.Theme)

local TargetController = require(script.Parent.TargetController)

local TAG = "RC_Combatant"
local SPARKLES = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"

type Chip = { attribute: string, text: string, color: Color3 }

-- Display order.
local CHIPS: { Chip } = {
	{ attribute = "Stunned", text = "💫 STUNNED", color = Color3.fromRGB(255, 230, 120) },
	{ attribute = "Frozen", text = "🧊 FROZEN", color = Color3.fromRGB(170, 230, 255) },
	{ attribute = "Rooted", text = "⚓ ROOTED", color = Color3.fromRGB(170, 230, 255) },
	{ attribute = "Slowed", text = "↓ SLOWED", color = Color3.fromRGB(180, 200, 255) },
	{ attribute = "Silenced", text = "🔇 SILENCED", color = Color3.fromRGB(220, 170, 255) },
	{ attribute = "Poisoned", text = "💀 POISON", color = Color3.fromRGB(150, 240, 110) },
	{ attribute = "Burning", text = "🔥 BURN", color = Color3.fromRGB(255, 160, 70) },
	{ attribute = "Marked", text = "◎ MARKED", color = Color3.fromRGB(255, 140, 120) },
	{ attribute = "Weakened", text = "▼ WEAK", color = Color3.fromRGB(200, 150, 255) },
	{ attribute = "Taunted", text = "! TAUNTED", color = Color3.fromRGB(255, 120, 100) },
	{ attribute = "Guarded", text = "🛡 GUARD", color = Theme.Colors.GoldBright },
	{ attribute = "Hardened", text = "🧱 HARDENED", color = Color3.fromRGB(220, 200, 170) },
	{ attribute = "Empowered", text = "▲ EMPOWER", color = Color3.fromRGB(255, 150, 110) },
	{ attribute = "Hasted", text = "» HASTE", color = Color3.fromRGB(150, 240, 220) },
	{ attribute = "Regenerating", text = "💚 REGEN", color = Color3.fromRGB(140, 255, 170) },
	{ attribute = "Shield", text = "◈ ", color = Color3.fromRGB(150, 210, 255) },
}

type Follower = { part: BasePart, offset: CFrame, spin: number?, feet: boolean? }
type Aura = { instances: { Instance }, followers: { Follower } }

type Watch = {
	model: Model,
	billboard: BillboardGui?,
	auras: { [string]: Aura },
	connections: { RBXScriptConnection },
}

local StatusVfxController = {}

local watched: { [Model]: Watch } = {}

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

local function rootOf(model: Model): BasePart?
	local root = model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function anchorOf(model: Model): BasePart?
	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head
	end
	return rootOf(model) or model.PrimaryPart
end

local function vfxPart(size: Vector3, color: Color3, material: Enum.Material, shape: Enum.PartType?): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = material
	p.Color = color
	p.Size = size
	if shape then
		p.Shape = shape
	end
	p.Parent = folder()
	return p
end

-- A looping particle emitter on the fighter's root.
local function emitter(
	model: Model,
	texture: string,
	color: Color3,
	rate: number,
	size: number,
	speed: NumberRange,
	acceleration: Vector3,
	offset: Vector3?,
	lightEmission: number?
): Instance?
	local root = rootOf(model)
	if root == nil then
		return nil
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "RC_StatusAura"
	attachment.Position = offset or Vector3.zero
	local e = Instance.new("ParticleEmitter")
	e.Texture = texture
	e.Color = ColorSequence.new(color)
	e.LightEmission = lightEmission or 0.8
	e.Size =
		NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, size * 0.2) })
	e.Transparency =
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(0.6, 1)
	e.Speed = speed
	e.SpreadAngle = Vector2.new(40, 40)
	e.Acceleration = acceleration
	e.Rate = rate
	e.Parent = attachment
	attachment.Parent = root
	return attachment
end

local function billboardIcon(model: Model, text: string, color: Color3, height: number): Instance?
	local anchor = anchorOf(model)
	if anchor == nil then
		return nil
	end
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "RC_StatusIcon"
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 90
	billboard.Size = UDim2.fromOffset(40, 40)
	billboard.StudsOffset = Vector3.new(0, height, 0)
	billboard.Adornee = anchor
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.2
	label.Parent = billboard
	billboard.Parent = anchor
	return billboard
end

-- Builds the aura for one status attribute.
local function buildAura(model: Model, attribute: string): Aura
	local aura: Aura = { instances = {}, followers = {} }
	local function add(instance: Instance?)
		if instance then
			table.insert(aura.instances, instance)
		end
	end
	local root = rootOf(model)
	local height = if root then root.Size.Y else 2
	if attribute == "Stunned" then
		-- Three stars circling above the head.
		for i = 0, 2 do
			local star = vfxPart(
				Vector3.one * 0.45,
				Color3.fromRGB(255, 230, 120),
				Enum.Material.Neon,
				Enum.PartType.Ball
			)
			add(star)
			table.insert(aura.followers, {
				part = star,
				offset = CFrame.Angles(0, i * math.pi * 2 / 3, 0) * CFrame.new(1.1, height * 1.6 + 1.2, 0),
				spin = 4,
			})
		end
	elseif attribute == "Frozen" then
		local ice = vfxPart(
			Vector3.new(4.2, 6.4, 4.2) * math.clamp(height / 2, 0.8, 2.5),
			Color3.fromRGB(170, 225, 255),
			Enum.Material.Glass
		)
		ice.Transparency = 0.45
		ice.Reflectance = 0.2
		add(ice)
		table.insert(aura.followers, { part = ice, offset = CFrame.new(0, 0.2, 0) })
		add(
			emitter(
				model,
				SPARKLES,
				Color3.fromRGB(220, 245, 255),
				8,
				0.4,
				NumberRange.new(0.5, 1.5),
				Vector3.zero
			)
		)
	elseif attribute == "Rooted" then
		for i = 0, 5 do
			local shard =
				vfxPart(Vector3.new(0.35, 1.6, 0.35), Color3.fromRGB(170, 225, 255), Enum.Material.Glass)
			shard.Transparency = 0.25
			add(shard)
			local a = i * math.pi * 2 / 6
			table.insert(aura.followers, {
				part = shard,
				offset = CFrame.new(math.cos(a) * 1.4, 0.6, math.sin(a) * 1.4)
					* CFrame.Angles(math.cos(a) * 0.4, 0, math.sin(a) * 0.4),
				feet = true,
			})
		end
	elseif attribute == "Slowed" then
		add(
			emitter(
				model,
				SMOKE,
				Color3.fromRGB(160, 190, 255),
				6,
				1.6,
				NumberRange.new(0.3, 1),
				Vector3.new(0, -1, 0),
				Vector3.new(0, -height, 0),
				0.2
			)
		)
	elseif attribute == "Silenced" then
		add(billboardIcon(model, "🔇", Color3.fromRGB(220, 170, 255), 3.4))
	elseif attribute == "Poisoned" then
		add(
			emitter(
				model,
				SMOKE,
				Color3.fromRGB(120, 220, 90),
				8,
				1.2,
				NumberRange.new(1, 2),
				Vector3.new(0, 3, 0),
				nil,
				0.3
			)
		)
		add(
			emitter(
				model,
				SPARKLES,
				Color3.fromRGB(170, 255, 120),
				6,
				0.35,
				NumberRange.new(1, 3),
				Vector3.new(0, 4, 0)
			)
		)
	elseif attribute == "Burning" then
		add(
			emitter(
				model,
				FIRE,
				Color3.fromRGB(255, 140, 50),
				14,
				1.4,
				NumberRange.new(1, 3),
				Vector3.new(0, 6, 0),
				nil,
				1
			)
		)
	elseif attribute == "Marked" then
		add(billboardIcon(model, "◎", Color3.fromRGB(255, 110, 90), 3.8))
	elseif attribute == "Weakened" then
		add(
			emitter(
				model,
				SMOKE,
				Color3.fromRGB(110, 60, 150),
				5,
				1.4,
				NumberRange.new(0.3, 1),
				Vector3.new(0, -1.5, 0),
				nil,
				0
			)
		)
	elseif attribute == "Taunted" then
		add(billboardIcon(model, "!", Color3.fromRGB(255, 90, 70), 3.6))
	elseif attribute == "Guarded" or attribute == "Hardened" then
		local highlight = Instance.new("Highlight")
		highlight.Name = "RC_StatusHighlight"
		highlight.FillTransparency = if attribute == "Hardened" then 0.75 else 1
		highlight.FillColor = Color3.fromRGB(150, 140, 120)
		highlight.OutlineColor = if attribute == "Guarded"
			then Theme.Colors.GoldBright
			else Color3.fromRGB(200, 190, 170)
		highlight.OutlineTransparency = 0.1
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.Parent = model
		add(highlight)
		if attribute == "Hardened" then
			add(
				emitter(
					model,
					SMOKE,
					Color3.fromRGB(190, 170, 140),
					3,
					1,
					NumberRange.new(0.2, 0.6),
					Vector3.zero,
					nil,
					0
				)
			)
		end
	elseif attribute == "Empowered" then
		add(
			emitter(
				model,
				SPARKLES,
				Color3.fromRGB(255, 120, 80),
				10,
				0.5,
				NumberRange.new(1, 3),
				Vector3.new(0, 4, 0)
			)
		)
	elseif attribute == "Hasted" then
		add(
			emitter(
				model,
				SPARKLES,
				Color3.fromRGB(170, 255, 235),
				12,
				0.35,
				NumberRange.new(4, 7),
				Vector3.zero
			)
		)
	elseif attribute == "Regenerating" then
		add(
			emitter(
				model,
				SPARKLES,
				Color3.fromRGB(150, 255, 170),
				8,
				0.45,
				NumberRange.new(1, 2),
				Vector3.new(0, 5, 0)
			)
		)
	elseif attribute == "Shield" then
		local bubble = vfxPart(
			Vector3.one * 7,
			Color3.fromRGB(150, 210, 255),
			Enum.Material.ForceField,
			Enum.PartType.Ball
		)
		add(bubble)
		table.insert(aura.followers, { part = bubble, offset = CFrame.new() })
	end
	return aura
end

local function destroyAura(aura: Aura)
	for _, instance in aura.instances do
		instance:Destroy()
	end
end

local function renderChips(watch: Watch, active: { Chip })
	local model = watch.model
	-- The selected target shows its statuses on its target plate instead.
	if #active == 0 or model == TargetController.current() then
		if watch.billboard then
			watch.billboard:Destroy()
			watch.billboard = nil
		end
		return
	end
	local anchor = anchorOf(model)
	local billboard = watch.billboard
	if billboard == nil and anchor then
		local created = Instance.new("BillboardGui")
		created.Name = "RC_Status"
		created.AlwaysOnTop = true
		created.LightInfluence = 0
		created.MaxDistance = 90
		created.Size = UDim2.fromOffset(260, 22)
		created.StudsOffset = Vector3.new(0, 2.6, 0)
		created.Adornee = anchor
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.Padding = UDim.new(0, 4)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = created
		created.Parent = anchor
		watch.billboard = created
		billboard = created
	end
	if billboard == nil then
		return
	end
	for _, child in billboard:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	for order, chip in active do
		if order > 5 then
			break -- keep it readable
		end
		local label = Instance.new("TextLabel")
		label.LayoutOrder = order
		label.AutomaticSize = Enum.AutomaticSize.X
		label.Size = UDim2.fromOffset(0, 20)
		label.BackgroundColor3 = Theme.Colors.Ink
		label.BackgroundTransparency = 0.3
		label.TextColor3 = chip.color
		label.TextSize = 12
		label.FontFace = Theme.Fonts.BodyBold
		local value = model:GetAttribute(chip.attribute)
		label.Text = if chip.attribute == "Shield" then `{chip.text}{tostring(value)}` else chip.text
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 5)
		pad.PaddingRight = UDim.new(0, 5)
		pad.Parent = label
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = label
		label.Parent = billboard
	end
end

local function render(watch: Watch)
	local model = watch.model
	local active: { Chip } = {}
	for _, chip in CHIPS do
		local value = model:GetAttribute(chip.attribute)
		local on = value ~= nil and value ~= false
		if on then
			table.insert(active, chip)
			if watch.auras[chip.attribute] == nil then
				watch.auras[chip.attribute] = buildAura(model, chip.attribute)
			end
		elseif watch.auras[chip.attribute] then
			destroyAura(watch.auras[chip.attribute])
			watch.auras[chip.attribute] = nil
		end
	end
	renderChips(watch, active)
end

local function unwatch(model: Model)
	local watch = watched[model]
	if watch == nil then
		return
	end
	watched[model] = nil
	for _, connection in watch.connections do
		connection:Disconnect()
	end
	if watch.billboard then
		watch.billboard:Destroy()
	end
	for _, aura in watch.auras do
		destroyAura(aura)
	end
end

local function watchModel(instance: Instance)
	if not instance:IsA("Model") or watched[instance] then
		return
	end
	local model = instance :: Model
	local watch: Watch = { model = model, billboard = nil, auras = {}, connections = {} }
	watched[model] = watch
	for _, chip in CHIPS do
		table.insert(
			watch.connections,
			model:GetAttributeChangedSignal(chip.attribute):Connect(function()
				render(watch)
			end)
		)
	end
	table.insert(
		watch.connections,
		model.AncestryChanged:Connect(function(_, parent)
			if parent == nil then
				unwatch(model)
			end
		end)
	)
	render(watch)
end

function StatusVfxController:Start()
	CollectionService:GetInstanceAddedSignal(TAG):Connect(watchModel)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(instance)
		if instance:IsA("Model") then
			unwatch(instance)
		end
	end)
	for _, instance in CollectionService:GetTagged(TAG) do
		watchModel(instance)
	end
	local lastTarget: Model? = nil
	TargetController.Changed:Connect(function(target)
		for _, model in { lastTarget, target } do
			local watch = model and watched[model]
			if watch then
				render(watch)
			end
		end
		lastTarget = target
	end)
	-- Ice blocks, stars, shards and bubbles follow their fighter.
	RunService.RenderStepped:Connect(function()
		local t = os.clock()
		for model, watch in watched do
			if next(watch.auras) == nil then
				continue
			end
			local root = rootOf(model)
			if root == nil then
				continue
			end
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			local feetY = (if humanoid then humanoid.HipHeight else 2) + root.Size.Y / 2
			local base = CFrame.new(root.Position)
			for _, aura in watch.auras do
				for _, follower in aura.followers do
					local frame = if follower.feet then base * CFrame.new(0, -feetY, 0) else base
					if follower.spin then
						frame *= CFrame.Angles(0, t * follower.spin, 0)
					end
					follower.part.CFrame = frame * follower.offset
				end
			end
		end
	end)
end

return StatusVfxController
