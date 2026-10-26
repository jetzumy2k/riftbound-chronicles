--!strict
--[[
	CombatController — basic-attack input: a 3-step combo per job
	(BasicAttacks, PLAN.md D-36).

	Sends *intents only*: `BasicAttack(targetModel?)`. The server decides the
	combo step, whether anything happens (hostility, safe zones, protection,
	range, line of sight) and how much damage it does. The client predicts
	the step with the same rules (ComboMath) to start the animation at once.

	Feel:
	  - Hold to attack: holding the button / mouse / key keeps chaining.
	  - Input buffer: a press slightly early is remembered and fires the
	    moment the next step is allowed.
	  - Always attacks the selected target (TargetController). With nothing
	    selected, the nearest enemy in front becomes the selection, so the
	    next attacks keep following it. Out of range, the character walks
	    to it first (any movement input cancels).
	  - Turns to face the target immediately; melee steps lunge in a little
	    toward a target that is just out of reach.
	  - Auto Attack (a basic skill on the skill bar, SkillBarController):
	    targets the selected enemy or, with none, the nearest creature
	    around you (any direction), walks into reach and keeps chaining the
	    normal attack until it falls, facing it the whole time. Pressing it
	    again keeps attacking (it is not an on / off switch, creator review
	    2026-10-24). Steering, clearing the target or selecting a friend
	    stops it; selecting another enemy switches to it.

	  - Auto-attack switch (creator review 2026-10-24): an AUTO button (R on
	    desktop) the player turns on / off. While on, whenever the character
	    is idle it picks the nearest creature within HUNT_STUDS (never a
	    player or a training dummy) and attacks it like the Attack skill,
	    then looks for the next one. Steering takes over; it resumes a moment
	    after you let go. A creature it can't reach in UNREACHABLE_SECONDS is
	    skipped for a while. Admins can switch it off for the whole game
	    (Flags.AutoAttack, mirrored to the RC_AutoAttack attribute); the
	    server checks every attack as usual.

	Input:
	  Desktop  left mouse (click an enemy to target it) or F; R toggles AUTO
	  Gamepad  R2
	  Touch    on-screen attack button (bottom-right, left of jump); shows
	           the combo step as three pips (shape, not only colour)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BasicAttacks = require(Shared.Definitions.BasicAttacks)
local CombatButtonsLayout = require(Shared.Layout.CombatButtonsLayout)
local ComboMath = require(Shared.Logic.ComboMath)
local JobDefinitions = require(Shared.Definitions.JobDefinitions)
local NetClient = require(Shared.Net.Client)

local UI = script.Parent.Parent.UI
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)
local Tooltip = require(UI.Tooltip)
local SkillIcon = require(UI.SkillIcon)

local Constants = require(Shared.Constants)

local PlayerDataController = require(script.Parent.PlayerDataController)
local NotificationController = require(script.Parent.NotificationController)
local AnimationController = require(script.Parent.AnimationController)
local CharacterMotionController = require(script.Parent.CharacterMotionController)
local TargetController = require(script.Parent.TargetController)

local BUFFER_SECONDS = 0.3
local LUNGE_SECONDS = 0.14 -- CombatService.LUNGE_SECONDS
local LUNGE_STOP_DISTANCE = 3.2
-- With nothing selected, an attack looks this far for an enemy to walk to.
local SEARCH_STUDS = 30
-- Auto Attack looks this far around the character for a creature.
local AUTO_SEARCH_STUDS = 60

local CombatController = {}

local combo = ComboMath.new()
local holding: { [string]: boolean? } = {}
local queued = false
local pips: { Frame } = {}
local button: TextButton? = nil
local glyph: TextLabel? = nil
-- Auto Attack: the enemy being attacked automatically (nil = off).
local autoTarget: Model? = nil
-- Auto-attack switch: looks for creatures on its own while on.
local HUNT_STUDS = 50
local HUNT_RESUME_SECONDS = 0.8
local UNREACHABLE_SECONDS = 7
local SKIP_SECONDS = 15
local hunting = false
local lastSteerAt = 0
local farSince: number? = nil
local skipped: { [Model]: number } = {}
local autoButton: TextButton? = nil
local autoLabel: TextLabel? = nil
local autoIcon: Frame? = nil

local function currentAttack(): BasicAttacks.BasicAttack?
	return BasicAttacks.forJob(PlayerDataController:Get().Job)
end

local function localCharacter(): Model?
	return (Players.LocalPlayer :: Player).Character
end

local function rootOf(model: Model): BasePart?
	local root = model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Short burst of horizontal velocity toward the target (melee steps).
local function lunge(target: Model, maxStuds: number, delaySeconds: number)
	task.delay(delaySeconds, function()
		local character = localCharacter()
		local root = character and rootOf(character)
		local targetRoot = rootOf(target)
		if root == nil or targetRoot == nil or (character :: Model):GetAttribute("Defeated") == true then
			return
		end
		local offset = targetRoot.Position - root.Position
		local flat = Vector3.new(offset.X, 0, offset.Z)
		local travel = math.min(maxStuds, flat.Magnitude - LUNGE_STOP_DISTANCE)
		if travel < 0.3 then
			return
		end
		local attachment = root:FindFirstChild("RootAttachment")
		if attachment == nil or not attachment:IsA("Attachment") then
			return
		end
		local push = Instance.new("LinearVelocity")
		push.Name = "RC_Lunge"
		push.Attachment0 = attachment
		push.RelativeTo = Enum.ActuatorRelativeTo.World
		push.ForceLimitMode = Enum.ForceLimitMode.PerAxis
		push.MaxAxesForce = Vector3.new(60000, 0, 60000)
		push.VectorVelocity = flat.Unit * (travel / LUNGE_SECONDS)
		push.Parent = root
		task.delay(LUNGE_SECONDS, function()
			push:Destroy()
		end)
	end)
end

local function refreshPips()
	for index, pip in pips do
		local lit = index <= combo.index and os.clock() <= combo.readyAt + 0.7
		pip.BackgroundTransparency = if lit then 0 else 0.6
		pip.Size = if lit then UDim2.fromOffset(10, 10) else UDim2.fromOffset(7, 7)
	end
end

local attack: (explicitTarget: Model?) -> ()

function attack(explicitTarget: Model?)
	local definition = currentAttack()
	local character = localCharacter()
	if
		definition == nil
		or character == nil
		or character:GetAttribute("Defeated") == true
		or character:GetAttribute("Stunned") == true
		or character:GetAttribute("Frozen") == true
		or TargetController.approaching()
	then
		return
	end
	-- Always the selected enemy; with none, the nearest one becomes selected.
	if explicitTarget and TargetController.isHostile(explicitTarget) then
		TargetController.set(explicitTarget)
	end
	local target = TargetController.enemyFor(math.max(definition.range, SEARCH_STUDS))
	if target and TargetController.distanceTo(target) > definition.range + 1 then
		-- Walk into range first, then swing.
		TargetController.approach(target, math.max(definition.range - 1.5, 4), function()
			attack(target)
		end)
		return
	end

	local now = os.clock()
	local index = ComboMath.resolve(combo, now, definition.steps)
	if index == nil then
		-- Slightly early: remember it and fire as soon as it is allowed.
		if ComboMath.waitTime(combo, now) <= BUFFER_SECONDS then
			queued = true
		end
		return
	end
	queued = false
	ComboMath.commit(combo, now, definition.steps, index, definition.finisherCooldown)
	local step = definition.steps[index]

	local targetRoot = if target then rootOf(target) else nil
	if targetRoot then
		CharacterMotionController.faceToward(targetRoot.Position, step.recovery + 0.3)
	end
	AnimationController.play(character, step.clip)
	if target and step.lunge and definition.style == "Melee" then
		lunge(target, step.lunge, math.max(0, BasicAttacks.hitTime(step) - 0.12))
	end
	NetClient.fire("BasicAttack", target)
	refreshPips()
end

local function anyHeld(): boolean
	return next(holding) ~= nil
end

local function buildTouchButton()
	local gui = Kit.new("ScreenGui", {
		Name = "RC_Combat",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
		DisplayOrder = 5,
	})
	-- Left of Roblox's touch jump button (CombatButtonsLayout).
	local holder = Kit.new("TextButton", {
		Name = "Attack",
		AnchorPoint = Vector2.new(1, 1),
		BackgroundColor3 = Theme.Colors.Glass,
		BackgroundTransparency = 0.15,
		Text = "",
		AutoButtonColor = false,
		Parent = gui,
	})
	local corner = Kit.corner(holder, 46)
	local function place()
		local camera = Workspace.CurrentCamera
		local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
		local slot = CombatButtonsLayout.compute(viewport.X, viewport.Y).attack
		holder.Position = UDim2.new(1, -slot.right, 1, -slot.bottom)
		holder.Size = UDim2.fromOffset(slot.size, slot.size)
		corner.CornerRadius = UDim.new(0, slot.size // 2)
	end
	place()
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(place)
	end
	Kit.goldStroke(holder, 3)

	local icon = Kit.new("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0.8),
		Text = "🗡",
		TextSize = 40,
		FontFace = Theme.Fonts.DisplayHeavy,
		TextColor3 = Theme.Colors.GoldBright,
		ZIndex = 4,
		Parent = holder,
	})

	-- Combo step pips (size and fill, not colour alone).
	local row = Kit.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.fromOffset(46, 12),
		ZIndex = 4,
		Parent = holder,
	})
	Kit.list(row, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Center)
	for _ = 1, 3 do
		local pip = Kit.new("Frame", {
			BackgroundColor3 = Theme.Colors.GoldBright,
			BackgroundTransparency = 0.6,
			Size = UDim2.fromOffset(7, 7),
			ZIndex = 5,
			Parent = row,
		})
		Kit.corner(pip, 5)
		table.insert(pips, pip)
	end

	holder.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			holding.touch = true
			attack(nil)
		end
	end)
	holder.InputEnded:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			holding.touch = nil
		end
	end)

	gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")
	button = holder
	glyph = icon
end

local function huntAllowed(): boolean
	return ReplicatedStorage:GetAttribute(Constants.Attributes.AutoAttack) ~= false
end

local function refreshAutoButton()
	local b = autoButton
	if b == nil then
		return
	end
	b.Visible = PlayerDataController:Get().Job ~= nil and huntAllowed()
	local touch = UserInputService.TouchEnabled
	b.BackgroundColor3 = if hunting then Theme.Colors.SafeDeep else Theme.Colors.Glass
	local label = autoLabel
	if label then
		label.Text = `AUTO {if hunting then "ON" else "OFF"}{if touch then "" else " (R)"}`
		label.TextColor3 = if hunting then Theme.Colors.Safe else Theme.Colors.TextDim
	end
	-- The drawn loop icon (emoji don't render reliably), green while on.
	if autoIcon then
		autoIcon:Destroy()
	end
	local size = math.floor(math.min(b.Size.X.Offset, b.Size.Y.Offset) * 0.55)
	local icon = SkillIcon.new({
		icon = "auto",
		element = if hunting then "Nature" else "Steel",
		size = math.max(size, 20),
		plain = true,
	})
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = UDim2.new(0.5, 0, 0, 4)
	icon.Parent = b
	autoIcon = icon
	local stroke = b:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Thickness = if hunting then 3 else 1.5
	end
end

local function setHunting(on: boolean, quiet: boolean?)
	if on and not huntAllowed() then
		NotificationController:ShowKey("Warning", "combat.autoHunt.disabled")
		on = false
	end
	if hunting == on then
		refreshAutoButton()
		return
	end
	hunting = on
	farSince = nil
	if not on then
		autoTarget = nil
	end
	if not quiet then
		NotificationController:ShowKey("Info", if on then "combat.autoHunt.on" else "combat.autoHunt.off")
	end
	refreshAutoButton()
end

local function buildAutoButton()
	local gui = Kit.new("ScreenGui", {
		Name = "RC_AutoAttack",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
		DisplayOrder = 5,
	})
	local b = Kit.new("TextButton", {
		Name = "Auto",
		BackgroundColor3 = Theme.Colors.Glass,
		BackgroundTransparency = 0.12,
		Text = "",
		AutoButtonColor = true,
		Visible = false,
		Parent = gui,
	})
	Tooltip.attach(b, function()
		return "Auto attack",
			"When on, your character keeps attacking the target in front of you. Tap to switch. Key: R."
	end)
	autoLabel = Kit.new("TextLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -3),
		Size = UDim2.new(1, -4, 0, 12),
		TextSize = 10,
		TextScaled = true,
		FontFace = Theme.Fonts.BodyBold,
		TextColor3 = Theme.Colors.TextDim,
		Parent = b,
	})
	local corner = Kit.corner(b, 12)
	Kit.goldStroke(b, 1.5, 0.2)
	b.Activated:Connect(function()
		setHunting(not hunting)
	end)
	local function place()
		local camera = Workspace.CurrentCamera
		local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
		if UserInputService.TouchEnabled then
			local s = CombatButtonsLayout.compute(viewport.X, viewport.Y).auto
			b.AnchorPoint = Vector2.new(1, 1)
			b.Position = UDim2.new(1, -s.right, 1, -s.bottom)
			b.Size = UDim2.fromOffset(s.size, s.size)
			corner.CornerRadius = UDim.new(0, s.size // 2)
		else
			-- Left of the desktop skill bar (7 x 60 px buttons, 10 px gaps,
			-- 18 px from the bottom: SkillBarController).
			b.AnchorPoint = Vector2.new(1, 1)
			b.Position = UDim2.new(0.5, -240 - 14, 1, -18)
			b.Size = UDim2.fromOffset(64, 60)
		end
		refreshAutoButton()
	end
	place()
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(place)
	end
	gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")
	autoButton = b
	refreshAutoButton()
end

-- Auto-attack: while idle, start on the nearest creature in reach.
local function stepHunt(now: number)
	if not hunting then
		return
	end
	if not huntAllowed() then
		setHunting(false, true)
		NotificationController:ShowKey("Warning", "combat.autoHunt.disabled")
		return
	end
	if TargetController.steering() then
		lastSteerAt = now
		return
	end
	local character = localCharacter()
	local definition = currentAttack()
	if
		character == nil
		or definition == nil
		or character:GetAttribute("Defeated") == true
		or now - lastSteerAt < HUNT_RESUME_SECONDS
	then
		return
	end
	local current = autoTarget
	if current then
		-- Give up on a creature it can't get to (walls, cliffs, water).
		if TargetController.distanceTo(current) > definition.range + 2 then
			farSince = farSince or now
			if now - (farSince :: number) > UNREACHABLE_SECONDS then
				skipped[current] = now + SKIP_SECONDS
				autoTarget = nil
				farSince = nil
				TargetController.set(nil)
			end
		else
			farSince = nil
		end
		return
	end
	if TargetController.approaching() then
		return
	end
	local skip: { [Model]: boolean } = {}
	for model, untilTime in skipped do
		if now >= untilTime or model.Parent == nil then
			skipped[model] = nil
		else
			skip[model] = true
		end
	end
	local target = TargetController.nearestMob(HUNT_STUDS, skip)
	if target then
		farSince = nil
		TargetController.set(target)
		autoTarget = target
		attack(target)
	end
end

local function refreshButton()
	local job = PlayerDataController:Get().Job
	local def = JobDefinitions.get(job)
	if glyph and def then
		glyph.Text = def.glyph
	end
	if button then
		button.Visible = job ~= nil
	end
	refreshAutoButton()
end

local function disableCoreUi()
	-- The HUD shows HP; resets are handled by the server either way.
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
	end)
	task.spawn(function()
		for _ = 1, 10 do
			local ok = pcall(function()
				StarterGui:SetCore("ResetButtonCallback", false)
			end)
			if ok then
				return
			end
			task.wait(1)
		end
	end)
end

function CombatController:Start()
	disableCoreUi()

	if UserInputService.TouchEnabled then
		buildTouchButton()
	end
	buildAutoButton()
	refreshButton()
	PlayerDataController.Changed:Connect(refreshButton)
	ReplicatedStorage:GetAttributeChangedSignal(Constants.Attributes.AutoAttack):Connect(function()
		if not huntAllowed() and hunting then
			setHunting(false, true)
			NotificationController:ShowKey("Warning", "combat.autoHunt.disabled")
		end
		refreshAutoButton()
	end)

	local player = Players.LocalPlayer :: Player
	player.CharacterAdded:Connect(function()
		combo = ComboMath.new()
		holding = {}
		queued = false
		autoTarget = nil
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			local position = input.Position
			local clicked = TargetController.pickAt(Vector2.new(position.X, position.Y))
			if clicked and not TargetController.isHostile(clicked) then
				-- A realm-mate: select them for heals and wards; no swing.
				TargetController.set(clicked)
				return
			end
			holding.mouse = true
			attack(clicked)
		elseif input.KeyCode == Enum.KeyCode.F or input.KeyCode == Enum.KeyCode.ButtonR2 then
			holding[input.KeyCode.Name] = true
			attack(nil)
		elseif input.KeyCode.Name == "R" then
			setHunting(not hunting)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			holding.mouse = nil
		elseif input.KeyCode == Enum.KeyCode.F or input.KeyCode == Enum.KeyCode.ButtonR2 then
			holding[input.KeyCode.Name] = nil
		end
	end)

	-- Buffered presses and hold-to-attack fire the moment the next step is allowed.
	RunService.Heartbeat:Connect(function()
		stepHunt(os.clock())
		local auto = autoTarget
		if auto then
			local selected = TargetController.current()
			if selected ~= auto and selected ~= nil and TargetController.isHostile(selected) then
				-- The player picked another enemy: attack that one instead.
				autoTarget = selected
				auto = selected
			end
			if
				not TargetController.isHostile(auto)
				or selected ~= auto
				or (TargetController.steering() and not TargetController.approaching())
			then
				-- It fell, the selection was cleared or moved to a friend, or
				-- the player took over.
				autoTarget = nil
			elseif not TargetController.approaching() then
				-- Keep facing it (creatures move) and chain the next swing.
				local targetRoot = rootOf(auto)
				if targetRoot then
					CharacterMotionController.faceToward(targetRoot.Position, 0.2)
				end
				if ComboMath.waitTime(combo, os.clock()) == 0 then
					attack(auto)
				end
			end
		end
		if (queued or anyHeld()) and ComboMath.waitTime(combo, os.clock()) == 0 then
			attack(nil)
		end
		if #pips > 0 then
			refreshPips()
		end
	end)
end

--------------------------------------------------------------------------------
-- For SkillBarController (Phase 5).
--------------------------------------------------------------------------------

--[[
	Auto Attack (the basic skill): attacks the selected enemy or the nearest
	creature around you at once and keeps going until it falls. Pressing it
	while already on just keeps attacking (no off switch). Returns whether
	it is on, and "none" when there was nothing to attack.
]]
function CombatController.startAutoAttack(): (boolean, string?)
	local selected = TargetController.current()
	local target = if selected and TargetController.isHostile(selected)
		then selected
		else TargetController.nearestCreature(AUTO_SEARCH_STUDS)
	if target == nil then
		return false, "none"
	end
	TargetController.set(target)
	autoTarget = target
	attack(target)
	return true, nil
end

-- Is Auto Attack on (for the skill button)?
function CombatController.autoAttacking(): boolean
	return autoTarget ~= nil
end

-- A skill was cast: the basic-attack chain restarts after `seconds`.
function CombatController.holdAttacks(seconds: number)
	combo = ComboMath.new()
	combo.readyAt = os.clock() + seconds
	queued = false
end

return CombatController
