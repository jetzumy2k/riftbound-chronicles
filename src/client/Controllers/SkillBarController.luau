--!strict
--[[
	SkillBarController — the 3 + 1 skill buttons (Phase 5, CLAUDE.md §7,
	PLAN.md D-45).

	Sends *intents only*: `SkillCast(id, target?)`. The server checks the
	bar, cooldown, Focus, target, range and line of sight and computes every
	effect. The client predicts the animation and the cooldown sweep so a
	press feels instant; the server's `SkillCooldown` reply corrects it.

	Targets (TargetController):
	  enemy skills   the selected enemy; with none, the nearest enemy in
	                 front becomes the selection. Out of range, the character
	                 walks to it and casts on arrival.
	  heals / wards  the selected realm-mate, else the most hurt one in
	                 range, else yourself
	  dashes         where you are moving (backwards when still), after the
	                 server confirms the cast

	Input: desktop 1, 2, 3, Q (click works too) · gamepad X, Y, L1, R1 ·
	touch: buttons around the attack button (CombatButtonsLayout).

	Each button shows its drawn icon (UI/SkillIcon), key, rank pips, Focus cost, a cooldown sweep
	with seconds, and a "COMBO" tag + bright outline when its combo is ready
	on your target (e.g. Frost Bolt on a frozen enemy). Hover (desktop) or
	press-and-hold (touch) shows the skill's full information. Empty slots
	open the skill tree. State is never shown by colour alone.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SkillDefinitions = require(Shared.Definitions.SkillDefinitions)
local SkillRules = require(Shared.Logic.SkillRules)
local CombatButtonsLayout = require(Shared.Layout.CombatButtonsLayout)
local NetClient = require(Shared.Net.Client)

local UI = script.Parent.Parent.UI
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)
local SkillInfo = require(UI.SkillInfo)
local SkillIcon = require(UI.SkillIcon)

local PlayerDataController = require(script.Parent.PlayerDataController)
local AnimationController = require(script.Parent.AnimationController)
local CharacterMotionController = require(script.Parent.CharacterMotionController)
local CombatController = require(script.Parent.CombatController)
local TargetController = require(script.Parent.TargetController)
local NotificationController = require(script.Parent.NotificationController)

type Skill = SkillDefinitions.Skill

local SLOT_KEYS = CombatButtonsLayout.SKILL_KEYS
local KEY_LABELS = { skill1 = "1", skill2 = "2", skill3 = "3", special = "Q" }
local KEYBOARD: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.One] = "skill1",
	[Enum.KeyCode.Two] = "skill2",
	[Enum.KeyCode.Three] = "skill3",
	[Enum.KeyCode.Q] = "special",
	[Enum.KeyCode.ButtonX] = "skill1",
	[Enum.KeyCode.ButtonY] = "skill2",
	[Enum.KeyCode.ButtonL1] = "skill3",
	[Enum.KeyCode.ButtonR1] = "special",
}
-- Desktop bar (bottom centre).
local BAR_SIZE = 60
local BAR_GAP = 10
local BAR_BOTTOM = 18
-- Mirrors Skills.GlobalCooldownSeconds (the server decides; this only paces presses).
local GLOBAL_COOLDOWN = 0.6
local LONG_PRESS = 0.45
local COMBO_COLOR = Color3.fromRGB(255, 200, 110)
local DASH_FORCE = Vector3.new(60000, 0, 60000)

local SkillBarController = {
	-- Set by SkillTreeController: opens the tree (empty slot pressed).
	OpenTree = nil :: (() -> ())?,
}

type Button = {
	key: string,
	frame: TextButton,
	corner: UICorner,
	stroke: UIStroke,
	glyph: TextLabel, -- "+" on an empty slot
	icon: Frame?,
	iconKey: string?,
	size: number,
	dim: Frame,
	keyLabel: TextLabel,
	cost: TextLabel,
	pips: TextLabel,
	shade: Frame,
	timer: TextLabel,
	status: TextLabel,
}

local buttons: { [string]: Button } = {}
local readyAt: { [string]: number } = {}
local globalReadyAt = 0
local touch = false
local screen: ScreenGui
local tooltip: Frame
local tooltipBody: Frame

local function localCharacter(): Model?
	return (Players.LocalPlayer :: Player).Character
end

-- The skill in a slot right now (from the server's loadout).
local function skillIn(slot: string): Skill?
	local equipped = PlayerDataController:Get().EquippedSkills
	if slot == "special" then
		return SkillDefinitions.get(equipped.Special)
	end
	local index = table.find(SLOT_KEYS, slot) or 0
	return SkillDefinitions.get(equipped.Regular[index])
end

local function rankOf(skill: Skill): number
	return SkillRules.rankOf(PlayerDataController:Get().OwnedSkills, skill.id)
end

local function focusOf(character: Model?): number
	local focus = if character then character:GetAttribute("Focus") else nil
	return if type(focus) == "number" then focus else 0
end

-- Is this skill's combo ready on the selected target? (display only)
local function comboReady(skill: Skill): boolean
	local combo = skill.combo
	local target = TargetController.current()
	if combo == nil or target == nil or not TargetController.isHostile(target) then
		return false
	end
	local hp, maxHp = target:GetAttribute("HP"), target:GetAttribute("MaxHP")
	local fraction = if type(hp) == "number" and type(maxHp) == "number" and maxHp > 0 then hp / maxHp else 1
	local attributes = {
		Stun = "Stunned",
		Freeze = "Frozen",
		Root = "Rooted",
		Slow = "Slowed",
		Poison = "Poisoned",
		Burn = "Burning",
		Mark = "Marked",
		Weaken = "Weakened",
		Silence = "Silenced",
	}
	return SkillRules.comboApplies(combo, function(kind)
		local attribute = (attributes :: any)[kind]
		return attribute ~= nil and target:GetAttribute(attribute) ~= nil
	end, fraction)
end

--------------------------------------------------------------------------------
-- Casting
--------------------------------------------------------------------------------

-- Short burst of velocity (dashes), started once the server confirms.
local function dash(studs: number, seconds: number)
	local character = localCharacter()
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if root == nil or not root:IsA("BasePart") or humanoid == nil then
		return
	end
	local attachment = root:FindFirstChild("RootAttachment")
	if attachment == nil or not attachment:IsA("Attachment") then
		return
	end
	local move = humanoid.MoveDirection
	local flat = Vector3.new(move.X, 0, move.Z)
	local direction = if flat.Magnitude > 0.2 then flat.Unit else -root.CFrame.LookVector
	local push = Instance.new("LinearVelocity")
	push.Name = "RC_Dash"
	push.Attachment0 = attachment
	push.RelativeTo = Enum.ActuatorRelativeTo.World
	push.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	push.MaxAxesForce = DASH_FORCE
	push.VectorVelocity = direction * (studs / seconds)
	push.Parent = root
	task.delay(seconds, function()
		push:Destroy()
	end)
end

-- Our own cast was accepted (CombatFeedbackController): dashes move now.
function SkillBarController.onOwnCast(id: string)
	local skill = SkillDefinitions.get(id)
	local effect = skill and SkillDefinitions.effect(skill, "Dash")
	if effect then
		dash(effect.studs or 10, effect.seconds or 0.25)
	end
end

local cast: (slot: string) -> ()

-- Sends the cast with its predicted animation and cooldown.
local function fire(skill: Skill, target: Model?)
	local character = localCharacter()
	if character == nil then
		return
	end
	local now = os.clock()
	readyAt[skill.id] = now + skill.cooldown
	globalReadyAt = now + GLOBAL_COOLDOWN
	local recovery = SkillDefinitions.recovery(skill)
	CombatController.holdAttacks(recovery)
	local root = if target and target ~= character then target:FindFirstChild("HumanoidRootPart") else nil
	if root and root:IsA("BasePart") then
		CharacterMotionController.faceToward(root.Position, recovery + 0.2)
	end
	if skill.clip then
		AnimationController.play(character, skill.clip)
	end
	NetClient.fire("SkillCast", skill.id, if target == character then nil else target)
end

function cast(slot: string)
	local skill = skillIn(slot)
	if skill == nil then
		local open = SkillBarController.OpenTree
		if open then
			open()
		end
		return
	end
	local character = localCharacter()
	if character == nil or character:GetAttribute("Defeated") == true then
		return
	end
	local now = os.clock()
	if character:GetAttribute("Stunned") == true or character:GetAttribute("Frozen") == true then
		NotificationController:ShowKey("Warning", "skill.stunned")
		return
	elseif character:GetAttribute("Silenced") == true then
		NotificationController:ShowKey("Warning", "skill.silenced")
		return
	elseif now < (readyAt[skill.id] or 0) or now < globalReadyAt then
		return -- the sweep already shows it
	elseif focusOf(character) < skill.focusCost then
		NotificationController:ShowKey("Warning", "skill.noFocus")
		return
	end

	if skill.target == "Enemy" or skill.target == "EnemyArea" then
		local target = TargetController.enemyFor(math.max(skill.range, 30))
		if target == nil then
			if skill.target == "EnemyArea" then
				fire(skill, nil) -- lands ahead of you
			else
				-- Let the server look (and explain) without playing the cast.
				NetClient.fire("SkillCast", skill.id, nil)
			end
			return
		end
		if TargetController.distanceTo(target) > skill.range + 1 then
			-- Walk into range, then cast (if still ready).
			TargetController.approach(target, math.max(skill.range - 1.5, 4), function()
				cast(slot)
			end)
			return
		end
		fire(skill, target)
	elseif skill.target == "Ally" then
		local ally = TargetController.allyFor(skill.range)
		if ally and ally ~= character and TargetController.distanceTo(ally) > skill.range + 1 then
			TargetController.approach(ally, math.max(skill.range - 2, 4), function()
				cast(slot)
			end)
			return
		end
		fire(skill, ally)
	else
		fire(skill, nil)
	end
end

--------------------------------------------------------------------------------
-- Tooltip
--------------------------------------------------------------------------------

local function showTooltip(slot: string?)
	local skill = if slot then skillIn(slot) else nil
	if skill == nil or slot == nil then
		tooltip.Visible = false
		return
	end
	SkillInfo.fill(tooltipBody, skill, rankOf(skill), { compact = true })
	local button = buttons[slot].frame
	local area = screen.AbsoluteSize
	local at = button.AbsolutePosition - screen.AbsolutePosition
	local width = math.min(320, area.X - 24)
	tooltip.Size = UDim2.fromOffset(width, 0)
	-- Above the button, kept on screen.
	local x = math.clamp(at.X + button.AbsoluteSize.X / 2 - width / 2, 12, area.X - width - 12)
	tooltip.Position = UDim2.fromOffset(x, at.Y - 10)
	tooltip.Visible = true
end

--------------------------------------------------------------------------------
-- Buttons
--------------------------------------------------------------------------------

local function makeButton(gui: ScreenGui, slot: string): Button
	local frame = Kit.new("TextButton", {
		Name = slot,
		AnchorPoint = Vector2.new(1, 1),
		BackgroundColor3 = Theme.Colors.Glass,
		BackgroundTransparency = 0.15,
		Text = "",
		AutoButtonColor = false,
		ClipsDescendants = true,
		Parent = gui,
	})
	local corner = Kit.corner(frame, 14)
	local stroke = Kit.goldStroke(frame, if slot == "special" then 3 else 2)
	stroke.Transparency = if slot == "special" then 0 else 0.25
	local glyph = Kit.new("TextLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.46),
		Size = UDim2.fromScale(1, 0.55),
		TextScaled = true,
		FontFace = Theme.Fonts.DisplayHeavy,
		TextColor3 = Theme.Colors.GoldBright,
		ZIndex = 2,
		Parent = frame,
	})
	Kit.new("UITextSizeConstraint", { MaxTextSize = 30, Parent = glyph })
	local keyLabel = Kit.new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(6, 3),
		Size = UDim2.fromOffset(16, 14),
		Text = KEY_LABELS[slot],
		TextSize = 12,
		FontFace = Theme.Fonts.BodyBold,
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 4,
		Parent = frame,
	})
	local pips = Kit.new("TextLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -5, 0, 3),
		Size = UDim2.fromOffset(34, 12),
		TextSize = 9,
		FontFace = Theme.Fonts.BodyBold,
		TextColor3 = Theme.Colors.GoldBright,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 4,
		Parent = frame,
	})
	local cost = Kit.new("TextLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -5, 1, -3),
		Size = UDim2.fromOffset(30, 13),
		TextSize = 11,
		FontFace = Theme.Fonts.BodyBold,
		TextColor3 = Color3.fromRGB(150, 205, 255),
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 4,
		Parent = frame,
	})
	-- Darkens the icon while the skill can't be used (no Focus).
	local dim = Kit.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.Ink,
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 2,
		Parent = frame,
	})
	-- Cooldown sweep: a shade that shrinks from the top as the skill recovers.
	local shade = Kit.new("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0),
		BackgroundColor3 = Theme.Colors.Ink,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = frame,
	})
	local timer = Kit.new("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = "",
		TextSize = 20,
		FontFace = Theme.Fonts.DisplayHeavy,
		TextColor3 = Theme.Colors.Text,
		TextStrokeTransparency = 0.3,
		ZIndex = 5,
		Parent = frame,
	})
	local status = Kit.new("TextLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -2),
		Size = UDim2.new(1, -4, 0, 13),
		Text = "",
		TextSize = 10,
		FontFace = Theme.Fonts.BodyBold,
		TextColor3 = Theme.Colors.Text,
		TextStrokeTransparency = 0.3,
		ZIndex = 5,
		Parent = frame,
	})

	-- Tap / click casts; hover (mouse) or press-and-hold (touch) explains.
	local pressedAt: number? = nil
	local longShown = false
	frame.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			pressedAt = os.clock()
			longShown = false
			local started = pressedAt
			task.delay(LONG_PRESS, function()
				if pressedAt == started then
					longShown = true
					showTooltip(slot)
				end
			end)
		elseif input.UserInputType == Enum.UserInputType.MouseMovement then
			showTooltip(slot)
		end
	end)
	frame.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			pressedAt = nil
			if longShown then
				showTooltip(nil)
			end
		elseif input.UserInputType == Enum.UserInputType.MouseMovement then
			showTooltip(nil)
		end
	end)
	frame.Activated:Connect(function()
		if not longShown then
			cast(slot)
		end
		longShown = false
	end)
	return {
		key = slot,
		frame = frame,
		corner = corner,
		stroke = stroke,
		glyph = glyph,
		icon = nil,
		iconKey = nil,
		size = BAR_SIZE,
		dim = dim,
		keyLabel = keyLabel,
		cost = cost,
		pips = pips,
		shade = shade,
		timer = timer,
		status = status,
	}
end

local function place()
	local camera = Workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	if touch then
		local layout = CombatButtonsLayout.compute(viewport.X, viewport.Y) :: any
		for slot, button in buttons do
			local s = layout[slot]
			button.frame.AnchorPoint = Vector2.new(1, 1)
			button.frame.Position = UDim2.new(1, -s.right, 1, -s.bottom)
			button.frame.Size = UDim2.fromOffset(s.size, s.size)
			button.size = s.size
			button.corner.CornerRadius = UDim.new(0, s.size // 2)
		end
		return
	end
	-- Desktop: a row at the bottom centre, special last.
	local total = #SLOT_KEYS * BAR_SIZE + (#SLOT_KEYS - 1) * BAR_GAP
	for index, slot in SLOT_KEYS do
		local button = buttons[slot]
		button.frame.AnchorPoint = Vector2.new(0, 1)
		button.frame.Position =
			UDim2.new(0.5, -total / 2 + (index - 1) * (BAR_SIZE + BAR_GAP), 1, -BAR_BOTTOM)
		button.frame.Size = UDim2.fromOffset(BAR_SIZE, BAR_SIZE)
		button.size = BAR_SIZE
		button.corner.CornerRadius = UDim.new(0, 12)
	end
end

local function render()
	local state = PlayerDataController:Get()
	local character = localCharacter()
	local focus = focusOf(character)
	local now = os.clock()
	local visible = state.Job ~= nil
	for slot, button in buttons do
		button.frame.Visible = visible
		local skill = skillIn(slot)
		-- The icon is rebuilt only when the skill or the button size changes.
		local iconKey = if skill then `{skill.id}:{button.size}:{touch}` else nil
		if iconKey ~= button.iconKey then
			if button.icon then
				button.icon:Destroy()
				button.icon = nil
			end
			if skill then
				local icon = SkillIcon.forSkill(skill, button.size, { round = touch, zIndex = 1 })
				icon.Parent = button.frame
				button.icon = icon
			end
			button.iconKey = iconKey
		end
		if skill == nil then
			button.dim.Visible = false
			button.glyph.Text = "+"
			button.glyph.TextColor3 = Theme.Colors.TextMuted
			button.cost.Text = ""
			button.pips.Text = ""
			button.shade.Size = UDim2.fromScale(1, 0)
			button.timer.Text = ""
			button.status.Text = "EMPTY"
			button.stroke.Color = Color3.new(1, 1, 1)
			continue
		end
		button.glyph.Text = ""
		button.cost.Text = tostring(skill.focusCost)
		button.pips.Text = `R{rankOf(skill)}`
		local left = math.max((readyAt[skill.id] or 0) - now, 0)
		button.shade.Size = UDim2.fromScale(1, math.clamp(left / skill.cooldown, 0, 1))
		button.timer.Text = if left > 0
			then (if left >= 10 then tostring(math.ceil(left)) else string.format("%.1f", left))
			else ""
		local combo = left <= 0 and comboReady(skill)
		if left <= 0 and focus < skill.focusCost then
			button.status.Text = "NO FOCUS"
		elseif combo then
			button.status.Text = "COMBO!"
		else
			button.status.Text = ""
		end
		-- Combo ready: thick bright outline (with the COMBO word above).
		button.stroke.Thickness = if combo then 4 elseif slot == "special" then 3 else 2
		button.stroke.Color = if combo then COMBO_COLOR else Color3.new(1, 1, 1)
		local usable = left <= 0 and focus >= skill.focusCost
		button.dim.Visible = not usable and left <= 0
	end
end

local function build()
	local gui = Kit.new("ScreenGui", {
		Name = "RC_Skills",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
		DisplayOrder = 5,
	})
	for _, slot in SLOT_KEYS do
		buttons[slot] = makeButton(gui, slot)
		buttons[slot].keyLabel.Visible = not touch
	end
	tooltip = Kit.glassPanel({
		Name = "Tooltip",
		AnchorPoint = Vector2.new(0, 1),
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.fromOffset(320, 0),
		Visible = false,
		ZIndex = 10,
		Parent = gui,
	})
	Kit.padding(tooltip, 10, 12)
	tooltipBody = Kit.new("Frame", {
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.fromScale(1, 0),
		Parent = tooltip,
	})
	local layout = Kit.list(tooltipBody, Enum.FillDirection.Vertical, 3, Enum.HorizontalAlignment.Left)
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	place()
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(place)
	end
	gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")
	screen = gui
end

function SkillBarController:Init()
	NetClient.on("SkillCooldown", function(payload)
		if
			type(payload) ~= "table"
			or type(payload.skill) ~= "string"
			or type(payload.readyIn) ~= "number"
		then
			return
		end
		readyAt[payload.skill] = os.clock() + payload.readyIn
	end)
end

function SkillBarController:Start()
	touch = UserInputService.TouchEnabled
	build()
	render()
	-- Cooldowns carry over a respawn (the server keeps them per player).
	PlayerDataController.Changed:Connect(render)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local slot = KEYBOARD[input.KeyCode]
		if slot then
			cast(slot)
		end
	end)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 0.1 then
			acc = 0
			render()
		end
	end)
end

return SkillBarController
