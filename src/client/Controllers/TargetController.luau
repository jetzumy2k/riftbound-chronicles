--!strict
--[[
	TargetController — the selected target (Phase 5 rework, D-45).

	One selected target that stays selected until you pick another, it is
	defeated, it goes far away, or you press × on the target frame:
	  Desktop  click a creature or player; the fighter under the mouse
	           lights up first. The click ray only looks at fighters
	           (scenery and invisible zone parts never block it), anywhere
	           inside a fighter's on-screen body box counts, and a near miss
	           still picks the closest fighter within a small radius; Tab
	           cycles enemies in front of you
	  Gamepad  DPad right cycles enemies
	  Touch    tap a creature or player (same near-miss help)

	Basic attacks and skills always use the selected target. With nothing
	selected, an attack picks the nearest enemy in front of you and selects
	it, so the next attacks keep following it. If the target is out of range
	the character walks to it first and then attacks (any movement input
	cancels the walk). While walking there the character faces the target
	(creator review 2026-10-24: it used to keep its last facing and walk
	sideways or backward).

	Click positions are screen points (InputObject.Position, top bar inset
	excluded), so picking uses ScreenPointToRay / WorldToScreenPoint
	(creator review 2026-10-24: mixing in viewport points aimed every click
	one top-bar height above the cursor).

	Shows a ring under the target (red enemy / green ally, with a different
	dash pattern so colour is not the only cue) and a plate over its head:
	🗡 / 💚, name, level, HP bar with numbers, status words and × to clear.

	Display and intent only: the server re-validates every target.
]]

local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared.Util.Signal)

local UI = script.Parent.Parent.UI
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)
local LevelTier = require(UI.LevelTier)

local CharacterMotionController = require(script.Parent.CharacterMotionController)

local TAG = "RC_Combatant"
local RAY_LENGTH = 400
-- Clicks this close (pixels) to a fighter on screen select it.
local PICK_RADIUS_PX = 70
local MAX_KEEP_DISTANCE = 160
local CYCLE_RANGE = 70
local APPROACH_TIMEOUT = 6
local APPROACH_REPATH = 0.25
local ENEMY_COLOR = Color3.fromRGB(255, 90, 80)
local ALLY_COLOR = Color3.fromRGB(120, 235, 150)

-- Status words on the target frame (CombatService attributes).
local STATUS_WORDS = {
	{ "Stunned", "STUNNED" },
	{ "Frozen", "FROZEN" },
	{ "Rooted", "ROOTED" },
	{ "Slowed", "SLOWED" },
	{ "Silenced", "SILENCED" },
	{ "Marked", "MARKED" },
	{ "Weakened", "WEAK" },
	{ "Poisoned", "POISON" },
	{ "Burning", "BURN" },
	{ "Guarded", "GUARD" },
	{ "Hardened", "HARDENED" },
	{ "Empowered", "EMPOWERED" },
	{ "Hasted", "HASTE" },
	{ "Regenerating", "REGEN" },
	{ "Shield", "SHIELD" },
	{ "Immune", "IMMUNE" },
	{ "Reflecting", "REFLECT" },
}

local TargetController = {
	-- (target: Model?) when the selection changes.
	Changed = Signal.new(),
}

local current: Model? = nil
local deadSince: number? = nil
local controls: any = nil

type Pending = { target: Model, range: number, action: () -> (), startedAt: number, nextPathAt: number }
local pending: Pending? = nil

-- UI
local plate: BillboardGui
local frame: Frame
local nameLabel: TextLabel
local hpFill: Frame
local hpText: TextLabel
local statusLabel: TextLabel
local ring: Model? = nil

local function localPlayer(): Player
	return Players.LocalPlayer :: Player
end

local function localCharacter(): Model?
	return localPlayer().Character
end

local function rootOf(model: Model?): BasePart?
	if model == nil then
		return nil
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function alive(model: Model?): boolean
	return model ~= nil
		and model.Parent ~= nil
		and model:GetAttribute("Defeated") ~= true
		and rootOf(model) ~= nil
end

function TargetController.isHostile(model: Model?): boolean
	if model == nil or model == localCharacter() or not alive(model) then
		return false
	end
	local player = Players:GetPlayerFromCharacter(model)
	if player == nil then
		return model:FindFirstChildOfClass("Humanoid") ~= nil -- creatures, dummies
	end
	local ours, theirs = localPlayer():GetAttribute("Race"), player:GetAttribute("Race")
	return ours == nil or theirs == nil or ours ~= theirs
end

function TargetController.isAlly(model: Model?): boolean
	if model == nil or not alive(model) then
		return false
	end
	if model == localCharacter() then
		return true
	end
	local player = Players:GetPlayerFromCharacter(model)
	return player ~= nil and player:GetAttribute("Race") == localPlayer():GetAttribute("Race")
end

-- Every fighter the server registered (players, creatures, dummies).
local function fighters(): { Model }
	local out = {}
	for _, instance in CollectionService:GetTagged(TAG) do
		if instance:IsA("Model") and instance ~= localCharacter() and alive(instance) then
			table.insert(out, instance)
		end
	end
	return out
end

local function fighterOf(instance: Instance?): Model?
	local node = instance
	while node and node ~= Workspace do
		if node:IsA("Model") and CollectionService:HasTag(node, TAG) then
			return node
		end
		node = node.Parent
	end
	return nil
end

function TargetController.current(): Model?
	if current and not alive(current) then
		return nil
	end
	return current
end

function TargetController.set(model: Model?)
	if model == current then
		return
	end
	current = model
	deadSince = nil
	pending = nil
	TargetController.Changed:Fire(model)
end

-- A fighter's body box on screen: (min, max) corners, or nil off screen.
local function screenBox(camera: Camera, model: Model): (Vector2?, Vector2?)
	local ok, cframe, size = pcall(model.GetBoundingBox, model)
	if not ok then
		return nil, nil
	end
	local half = size / 2
	local low, high = Vector2.new(math.huge, math.huge), Vector2.new(-math.huge, -math.huge)
	local any = false
	for _, x in { -1, 1 } do
		for _, y in { -1, 1 } do
			for _, z in { -1, 1 } do
				local corner = (cframe * CFrame.new(half * Vector3.new(x, y, z))).Position
				local point = camera:WorldToScreenPoint(corner)
				if point.Z > 0 then
					any = true
					local flat = Vector2.new(point.X, point.Y)
					low, high = low:Min(flat), high:Max(flat)
				end
			end
		end
	end
	if not any then
		return nil, nil
	end
	return low, high
end

--[[
	The fighter at a screen point (InputObject.Position, top bar inset
	excluded): the fighter the click ray hits (only fighters are tested, so
	scenery never blocks it), else the fighter whose on-screen body box
	holds the point, else the closest within PICK_RADIUS_PX.
]]
function TargetController.pickAt(screen: Vector2): Model?
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return nil
	end
	local candidates = fighters()
	if #candidates == 0 then
		return nil
	end
	local ray = camera:ScreenPointToRay(screen.X, screen.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = candidates :: { any }
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * RAY_LENGTH, params)
	local direct = if hit then fighterOf(hit.Instance) else nil
	if direct and alive(direct) then
		return direct
	end

	local scale = math.clamp(camera.ViewportSize.Y / 720, 0.8, 1.6)
	local margin = 14 * scale
	local best: Model? = nil
	local bestPx = math.huge
	-- Inside a body box (a little padded): the one whose centre is closest.
	for _, model in candidates do
		local low, high = screenBox(camera, model)
		if low and high then
			local inside = screen.X >= low.X - margin
				and screen.X <= high.X + margin
				and screen.Y >= low.Y - margin
				and screen.Y <= high.Y + margin
			if inside then
				local px = ((low + high) / 2 - screen).Magnitude
				if px < bestPx then
					best, bestPx = model, px
				end
			end
		end
	end
	if best then
		return best
	end
	-- Near miss: closest fighter on screen.
	bestPx = PICK_RADIUS_PX * scale
	for _, model in candidates do
		local root = rootOf(model) :: BasePart
		for _, offset in { 0, 1.5 } do
			local point = camera:WorldToScreenPoint(root.Position + Vector3.new(0, offset, 0))
			if point.Z > 0 then
				local px = (Vector2.new(point.X, point.Y) - screen).Magnitude
				if px < bestPx then
					best, bestPx = model, px
				end
			end
		end
	end
	return best
end

-- The mouse position as a screen point (like InputObject.Position).
function TargetController.mouseScreen(): Vector2
	local inset = GuiService:GetGuiInset()
	return UserInputService:GetMouseLocation() - inset
end

-- Nearest enemy within `range` in front of the character (or the camera).
function TargetController.nearestEnemy(range: number): Model?
	local character = localCharacter()
	local root = rootOf(character)
	if root == nil then
		return nil
	end
	local facing = root.CFrame.LookVector
	local camera = Workspace.CurrentCamera
	local look = if camera then camera.CFrame.LookVector else facing
	local best: Model? = nil
	local bestScore = math.huge
	for _, model in fighters() do
		if not TargetController.isHostile(model) then
			continue
		end
		local offset = (rootOf(model) :: BasePart).Position - root.Position
		local distance = offset.Magnitude
		if distance > range then
			continue
		end
		local flat = Vector3.new(offset.X, 0, offset.Z)
		local dir = if flat.Magnitude > 0.5 then flat.Unit else facing
		local front = math.max(dir:Dot(facing), dir:Dot(Vector3.new(look.X, 0, look.Z).Unit))
		if front < -0.2 and distance > 6 then
			continue -- well behind you
		end
		local score = distance * (1.8 - front)
		if score < bestScore then
			best, bestScore = model, score
		end
	end
	return best
end

--[[
	Auto Attack: the nearest creature around the character within `range`
	(any direction), or, with none, the nearest enemy player (war zones).
]]
function TargetController.nearestCreature(range: number): Model?
	local root = rootOf(localCharacter())
	if root == nil then
		return nil
	end
	local bestCreature: Model?, creatureDistance = nil, range
	local bestPlayer: Model?, playerDistance = nil, range
	for _, model in fighters() do
		if not TargetController.isHostile(model) then
			continue
		end
		local distance = ((rootOf(model) :: BasePart).Position - root.Position).Magnitude
		if Players:GetPlayerFromCharacter(model) == nil then
			if distance <= creatureDistance then
				bestCreature, creatureDistance = model, distance
			end
		elseif distance <= playerDistance then
			bestPlayer, playerDistance = model, distance
		end
	end
	return bestCreature or bestPlayer
end

--[[
	Auto-attack: the nearest hostile creature within `range` (never a player
	or a training dummy), skipping models in `skip`.
]]
function TargetController.nearestMob(range: number, skip: { [Model]: boolean }?): Model?
	local root = rootOf(localCharacter())
	if root == nil then
		return nil
	end
	local best: Model?, bestDistance = nil, range
	for _, model in fighters() do
		if
			not TargetController.isHostile(model)
			or Players:GetPlayerFromCharacter(model) ~= nil
			or model:GetAttribute("RC_Npc") == "TrainingDummy"
			or (skip and skip[model])
		then
			continue
		end
		local distance = ((rootOf(model) :: BasePart).Position - root.Position).Magnitude
		if distance <= bestDistance then
			best, bestDistance = model, distance
		end
	end
	return best
end

--[[
	The enemy an attack / skill with `range` goes to: the selected target if
	it is an enemy, else the nearest enemy (which becomes the selection).
	`searchRange` is how far to look when picking a new one.
]]
function TargetController.enemyFor(searchRange: number): Model?
	local selected = TargetController.current()
	if selected and TargetController.isHostile(selected) then
		return selected
	end
	local picked = TargetController.nearestEnemy(searchRange)
	if picked then
		TargetController.set(picked)
	end
	return picked
end

-- The ally a heal / ward goes to: the selected ally, else the most hurt
-- realm-mate within `range`, else yourself.
function TargetController.allyFor(range: number): Model?
	local character = localCharacter()
	local root = rootOf(character)
	if character == nil or root == nil then
		return nil
	end
	local selected = TargetController.current()
	if selected and TargetController.isAlly(selected) then
		return selected
	end
	local best, bestFraction = character, 1.01
	for _, player in Players:GetPlayers() do
		local model = player.Character
		local other = rootOf(model)
		if
			model
			and other
			and TargetController.isAlly(model)
			and (other.Position - root.Position).Magnitude <= range
		then
			local hp, maxHp = model:GetAttribute("HP"), model:GetAttribute("MaxHP")
			local fraction = if type(hp) == "number"
					and type(maxHp) == "number"
					and maxHp > 0
				then hp / maxHp
				else 1
			if fraction < bestFraction - 0.001 then
				best, bestFraction = model, fraction
			end
		end
	end
	return best
end

function TargetController.distanceTo(model: Model): number
	local a, b = rootOf(localCharacter()), rootOf(model)
	if a == nil or b == nil then
		return math.huge
	end
	return (a.Position - b.Position).Magnitude
end

-- Selects the next enemy (Tab / DPad right), nearest first.
function TargetController.cycle()
	local root = rootOf(localCharacter())
	if root == nil then
		return
	end
	local list = {}
	for _, model in fighters() do
		if TargetController.isHostile(model) and TargetController.distanceTo(model) <= CYCLE_RANGE then
			table.insert(list, model)
		end
	end
	table.sort(list, function(a, b)
		return TargetController.distanceTo(a) < TargetController.distanceTo(b)
	end)
	if #list == 0 then
		return
	end
	local index = (current and table.find(list, current)) or 0
	TargetController.set(list[index % #list + 1])
end

--------------------------------------------------------------------------------
-- Walk into range, then act
--------------------------------------------------------------------------------

local function getControls(): any
	if controls then
		return controls
	end
	local module = localPlayer():WaitForChild("PlayerScripts"):FindFirstChild("PlayerModule")
	if module and module:IsA("ModuleScript") then
		local ok, playerModule = pcall(require, module)
		if ok and playerModule and playerModule.GetControls then
			controls = playerModule:GetControls()
		end
	end
	return controls
end

local function moveInput(): number
	local ctrl = getControls()
	if ctrl then
		local ok, value = pcall(ctrl.GetMoveVector, ctrl)
		if ok and typeof(value) == "Vector3" then
			return value.Magnitude
		end
	end
	return 0
end

-- True while the player steers the character (stick / WASD / touch pad).
function TargetController.steering(): boolean
	return moveInput() > 0.1
end

-- True while the character is walking to a target to attack it.
function TargetController.approaching(): boolean
	return pending ~= nil
end

-- Walks toward `target` until within `range`, then runs `action`.
function TargetController.approach(target: Model, range: number, action: () -> ())
	local t = os.clock()
	pending = { target = target, range = range, action = action, startedAt = t, nextPathAt = 0 }
end

local function stopWalking()
	local character = localCharacter()
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = rootOf(character)
	if humanoid and root then
		humanoid:MoveTo(root.Position)
	end
end

local function stepApproach()
	local job = pending
	if job == nil then
		return
	end
	local character = localCharacter()
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local targetRoot = rootOf(job.target)
	local t = os.clock()
	if
		humanoid == nil
		or targetRoot == nil
		or not alive(job.target)
		or (character :: Model):GetAttribute("Defeated") == true
		or (character :: Model):GetAttribute("Stunned") == true
		or (character :: Model):GetAttribute("Frozen") == true
		or t - job.startedAt > APPROACH_TIMEOUT
		or moveInput() > 0.1
	then
		pending = nil
		return
	end
	if TargetController.distanceTo(job.target) <= job.range then
		pending = nil
		stopWalking()
		job.action()
		return
	end
	-- Face the target while walking (also in shift-lock), never sideways.
	CharacterMotionController.faceToward(targetRoot.Position, 0.2)
	if t >= job.nextPathAt then
		job.nextPathAt = t + APPROACH_REPATH
		humanoid:MoveTo(targetRoot.Position)
	end
end

--------------------------------------------------------------------------------
-- Visuals
--------------------------------------------------------------------------------

local function buildRing(): Model
	local holder = Instance.new("Model")
	holder.Name = "RC_TargetRing"
	local segments, radius = 16, 2.6
	for i = 0, segments - 1 do
		local a0 = (i / segments) * math.pi * 2
		local a1 = ((i + 0.6) / segments) * math.pi * 2
		local p0 = Vector3.new(math.cos(a0) * radius, 0, math.sin(a0) * radius)
		local p1 = Vector3.new(math.cos(a1) * radius, 0, math.sin(a1) * radius)
		local part = Instance.new("Part")
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.Neon
		part.Size = Vector3.new((p1 - p0).Magnitude, 0.08, 0.2)
		part.CFrame = CFrame.lookAt((p0 + p1) / 2, p1) * CFrame.Angles(0, math.rad(90), 0)
		part.Parent = holder
	end
	local folder = Workspace:FindFirstChild("RC_ClientVfx")
	if folder == nil then
		local created = Instance.new("Folder")
		created.Name = "RC_ClientVfx"
		created.Parent = Workspace
		folder = created
	end
	holder.Parent = folder
	return holder
end

local function renderRing()
	local model = TargetController.current()
	local root = rootOf(model)
	if ring == nil then
		ring = buildRing()
	end
	local holder = ring :: Model
	if model == nil or root == nil then
		holder:PivotTo(CFrame.new(0, -10000, 0))
		return
	end
	local hostile = TargetController.isHostile(model)
	local color = if hostile then ENEMY_COLOR else ALLY_COLOR
	for index, part in holder:GetChildren() do
		if part:IsA("BasePart") then
			part.Color = color
			-- Allies: every other dash hidden (pattern, not only colour).
			part.Transparency = if not hostile and index % 2 == 0 then 1 else 0.05
		end
	end
	local humanoid = (model :: Model):FindFirstChildOfClass("Humanoid")
	local drop = (if humanoid then humanoid.HipHeight else 2) + root.Size.Y / 2 - 0.1
	local scale = math.clamp(root.Size.X / 2, 1, 3)
	holder:PivotTo(
		CFrame.new(root.Position - Vector3.new(0, drop, 0)) * CFrame.Angles(0, os.clock() * 1.2, 0)
	)
	holder:ScaleTo(scale)
end

local function buildFrame()
	-- A plate floating over the target's head: it follows the target and
	-- never collides with the HUD, toasts or touch buttons. It lives in
	-- PlayerGui (adorned to the target) so its × button can be pressed.
	plate = Kit.new("BillboardGui", {
		Name = "RC_TargetPlate",
		ResetOnSpawn = false,
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = 220,
		Size = UDim2.fromOffset(250, 66),
		StudsOffset = Vector3.new(0, 4.6, 0),
		Active = true,
		Enabled = false,
	})
	frame = Kit.glassPanel({
		Name = "TargetFrame",
		Size = UDim2.fromScale(1, 1),
		Parent = plate,
	})
	nameLabel = Kit.new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, 4),
		Size = UDim2.new(1, -62, 0, 18),
		TextSize = 14,
		FontFace = Theme.Fonts.Display,
		TextColor3 = Theme.Colors.GoldBright,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		RichText = true,
		Parent = frame,
	})
	local track = Kit.new("Frame", {
		BackgroundColor3 = Theme.Colors.Ink,
		Position = UDim2.fromOffset(10, 24),
		Size = UDim2.new(1, -62, 0, 16),
		Parent = frame,
	})
	Kit.corner(track, 6)
	hpFill = Kit.new("Frame", {
		BackgroundColor3 = ENEMY_COLOR,
		Size = UDim2.fromScale(1, 1),
		Parent = track,
	})
	Kit.corner(hpFill, 6)
	hpText = Kit.new("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		TextSize = 12,
		FontFace = Theme.Fonts.BodyBold,
		TextColor3 = Theme.Colors.Text,
		TextStrokeTransparency = 0.4,
		ZIndex = 3,
		Parent = track,
	})
	statusLabel = Kit.new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, 43),
		Size = UDim2.new(1, -62, 0, 16),
		TextSize = 11,
		FontFace = Theme.Fonts.BodyBold,
		TextColor3 = Color3.fromRGB(255, 220, 160),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = frame,
	})
	local clear = Kit.new("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -6, 0.5, 0),
		Size = UDim2.fromOffset(44, 44),
		BackgroundColor3 = Theme.Colors.GlassRaised,
		Text = "×",
		TextSize = 18,
		FontFace = Theme.Fonts.BodyBold,
		TextColor3 = Theme.Colors.Text,
		Parent = frame,
	})
	Kit.corner(clear, 10)
	clear.Activated:Connect(function()
		TargetController.set(nil)
	end)
	plate.Parent = localPlayer():WaitForChild("PlayerGui")
end

local function escapeRich(text: string): string
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function renderFrame()
	local model = TargetController.current()
	local anchor = if model then (model:FindFirstChild("Head") or rootOf(model)) else nil
	plate.Enabled = model ~= nil and anchor ~= nil
	if model == nil or anchor == nil then
		(plate :: any).Adornee = nil
		return
	end
	if plate.Adornee ~= anchor then
		plate.Adornee = anchor :: Instance
	end
	local player = Players:GetPlayerFromCharacter(model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local name = if player then player.DisplayName elseif humanoid then humanoid.DisplayName else model.Name
	local level = if player then player:GetAttribute("Level") else model:GetAttribute("Level")
	local hostile = TargetController.isHostile(model)
	local levelText = ""
	if type(level) == "number" then
		levelText = `  ·  Lv {level}`
		if player == nil then
			-- D-63: a creature's level in its danger colour, with its mark.
			local style = LevelTier.styleFor(level)
			local mark = if style.mark ~= "" then ` {style.mark}` else ""
			levelText = `  ·  <font color="#{style.color:ToHex()}">Lv {level}{mark}</font>`
		end
	end
	nameLabel.Text = `{if hostile then "🗡" else "💚"}  {escapeRich(name)}{levelText}`
	local hp, maxHp = model:GetAttribute("HP"), model:GetAttribute("MaxHP")
	if type(hp) == "number" and type(maxHp) == "number" and maxHp > 0 then
		hpFill.Size = UDim2.fromScale(math.clamp(hp / maxHp, 0, 1), 1)
		hpText.Text = `{math.floor(hp)} / {math.floor(maxHp)}`
	end
	hpFill.BackgroundColor3 = if hostile then ENEMY_COLOR else ALLY_COLOR
	local words = {}
	for _, entry in STATUS_WORDS do
		if model:GetAttribute(entry[1]) ~= nil then
			table.insert(words, entry[2])
		end
	end
	statusLabel.Text = table.concat(words, " · ")
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

-- Is a visible, click-catching GUI element under this screen point?
local function guiUnder(screen: Vector2): boolean
	local gui = localPlayer():FindFirstChildOfClass("PlayerGui")
	if gui == nil then
		return false
	end
	for _, object in gui:GetGuiObjectsAtPosition(screen.X, screen.Y) do
		if object.Visible and object.Active and object.BackgroundTransparency < 1 then
			return true
		end
	end
	return false
end

-- Desktop: the fighter under the mouse lights up, so you can see what a
-- click will pick before clicking.
local function startHover()
	if not UserInputService.MouseEnabled then
		return
	end
	local glow = Instance.new("Highlight")
	glow.Name = "RC_HoverTarget"
	glow.FillTransparency = 0.8
	glow.OutlineTransparency = 0
	glow.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	glow.Enabled = false
	local acc = 0
	RunService.RenderStepped:Connect(function(dt)
		acc += dt
		if acc < 1 / 15 then
			return
		end
		acc = 0
		local camera = Workspace.CurrentCamera
		if camera and glow.Parent ~= camera then
			glow.Parent = camera
		end
		local over: Model? = nil
		if UserInputService:GetFocusedTextBox() == nil then
			local screen = TargetController.mouseScreen()
			if not guiUnder(screen) then
				over = TargetController.pickAt(screen)
			end
		end
		if over then
			glow.Adornee = over
			local color = if TargetController.isHostile(over) then ENEMY_COLOR else ALLY_COLOR
			glow.OutlineColor = color
			glow.FillColor = color
			glow.Enabled = true
		else
			glow.Enabled = false
			glow.Adornee = nil
		end
	end)
end

function TargetController:Start()
	buildFrame()
	startHover()

	-- Touch: tap a fighter to select it.
	UserInputService.TouchTapInWorld:Connect(function(position, processedByUI)
		if processedByUI then
			return
		end
		local picked = TargetController.pickAt(position)
		if picked then
			TargetController.set(picked)
		end
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.Tab or input.KeyCode == Enum.KeyCode.DPadRight then
			TargetController.cycle()
		end
	end)

	localPlayer().CharacterAdded:Connect(function()
		TargetController.set(nil)
	end)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		stepApproach()
		local selected = current
		if selected then
			if not alive(selected) then
				-- Give the defeat a moment, then drop it.
				deadSince = deadSince or os.clock()
				if os.clock() - (deadSince :: number) > 0.8 then
					TargetController.set(nil)
				end
			elseif TargetController.distanceTo(selected) > MAX_KEEP_DISTANCE then
				TargetController.set(nil)
			else
				deadSince = nil
			end
		end
		acc += dt
		if acc >= 0.1 then
			acc = 0
			renderFrame()
		end
	end)
	RunService.RenderStepped:Connect(renderRing)
end

return TargetController
