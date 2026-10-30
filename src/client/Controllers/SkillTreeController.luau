--!strict
--[[
	SkillTreeController — the class skill tree (Phase 5, CLAUDE.md §6-7,
	PLAN.md D-45).

	  - 4 branch columns x 6 tiers per class (24 skills). Each node shows
	    its drawn icon (UI/SkillIcon), name and a rank badge ("2/5"); a
	    padlock and "Lv 8" while the level is too low, "LEARN" / "+RANK"
	    when a point can be spent on it; lines join each skill to the one it
	    requires (gold when learned). Skills open level by level up to 30
	    and higher ranks open every few levels (SkillRules.rankCap).
	  - Tap a node: the detail pane shows everything about it (UI/SkillInfo:
	    damage, effects, durations, combo, next rank) with buttons to learn /
	    rank it up (1 skill point) and to put it on the skill bar.
	  - The skill bar row (6 regular + 1 ultimate) sits on top; tap a slot to
	    inspect its skill. Left of it, the BASIC tile: Auto Attack, free for
	    every class (no point, no rank); tap it to put it in a slot.
	  - Header: skill points left and Reset (refunds every point; only in a
	    safe zone, out of combat).
	  - D-90: a "📊 Stats" button switches to the Attributes page
	    (UI/AttributePanel: spend the 5 points a level on REC / INT / WIS /
	    STR / AGI; Reset there is the free daily attribute reset) and
	    "🌟 Skills" back. The toggle counts skill and attribute points.

	D-103 stage A look: the class colours (Definitions/ClassThemes: Warrior
	crimson / steel / gold, Archer emerald / teal / silver, Mage violet /
	blue / cyan, Healer white / gold / celestial blue) tint the panel, the
	branch cards and the links; each branch shows its role ("ATTACK
	BUILD", "DEFENSE BUILD", ...). The one ultimate per branch (tier 6) has
	a round frame with a spinning glow and a ⭐ badge. Learnable nodes and
	the link leading to them pulse; nodes grow on hover and when selected;
	learning plays a burst and a chime. The detail pane shows chips for
	type, power, cooldown, Focus and range (UI/SkillInfo).

	Every action is an intent (`LearnSkill`, `ResetSkills`, `SetLoadout`);
	the server validates it and answers with a fresh snapshot, which is what
	this screen shows. Open with the "🌟 SKILLS" button (right edge), K, or
	an empty skill-bar slot. Layout: Layout/SkillTreeLayout (device-tested).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SkillDefinitions = require(Shared.Definitions.SkillDefinitions)
local PassiveDefinitions = require(Shared.Definitions.PassiveDefinitions)
local SkillRules = require(Shared.Logic.SkillRules)
local PassiveRules = require(Shared.Logic.PassiveRules)
local JobDefinitions = require(Shared.Definitions.JobDefinitions)
local SkillTreeLayout = require(Shared.Layout.SkillTreeLayout)
local NetClient = require(Shared.Net.Client)
local Constants = require(Shared.Constants)

local UI = script.Parent.Parent.UI
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)
local Panels = require(UI.Panels)
local HudLayout = require(UI.HudLayout)
local SkillInfo = require(UI.SkillInfo)
local SkillIcon = require(UI.SkillIcon)
local Tooltip = require(UI.Tooltip)
local AttributePanel = require(UI.AttributePanel)
local ClassTheme = require(UI.ClassTheme)
local AttributeRules = require(Shared.Logic.AttributeRules)

local PlayerDataController = require(script.Parent.PlayerDataController)
local NotificationController = require(script.Parent.NotificationController)
local SkillBarController = require(script.Parent.SkillBarController)

type Skill = SkillDefinitions.Skill

local LOCKED_LINE = Color3.fromRGB(70, 66, 82)
local LEARNABLE = Color3.fromRGB(140, 235, 160)
local ULTIMATE_GOLD = Color3.fromRGB(255, 205, 90)
local SLOT_NAMES = { "1", "2", "3", "4", "5", "6", "ULTIMATE" }
local LEARN_SOUND = "rbxasset://sounds/electronicpingshort.wav"
local SPECIAL_INDEX = #SLOT_NAMES

local SkillTreeController = {}

local gui: ScreenGui
local toggle: TextButton
-- Phone landscape shows the toggle as a 44 px icon button (D-86).
local toggleCompact: () -> boolean = function()
	return false
end
local panel: Frame? = nil
local selected: string? = nil
local open = false
-- Tree scroll position, kept across re-renders (learning re-renders).
local scroll = Vector2.zero
-- D-103: the panel animates in only when it opens, not on every re-render.
local justOpened = false
-- A learn / rank-up we asked for: burst on its node when the rank arrives.
local pending: { id: string, rank: number }? = nil

local function colors(): ClassTheme.Colors
	return ClassTheme.forJob(PlayerDataController:Get().Job)
end

local function player(): Player
	return Players.LocalPlayer :: Player
end

local function unlockAll(): boolean
	return player():GetAttribute("SkillsUnlockAll") == true
end

local function bonus(): number
	local value = player():GetAttribute("SkillBonusPoints")
	return if type(value) == "number" then value else 0
end

local function state()
	return PlayerDataController:Get()
end

local function owned(): SkillRules.Owned
	return state().OwnedSkills
end

local function pointsLeft(): number
	return SkillRules.available(owned(), state().Level, bonus())
end

-- D-90: the page shown ("Skills" or "Attributes") and the points left.
local page = "Skills"
local function attributePoints(): number
	local s = state()
	return math.max(0, AttributeRules.unspent(s.Attributes, s.Level))
end

-- Why a skill or passive can't be learned / ranked right now (nil = it can).
local function blocker(skill: { id: string, unlockLevel: number, requires: string? }): string?
	local ok, reason =
		SkillRules.canLearn(state().Job, owned(), state().Level, bonus(), unlockAll(), skill.id)
	if ok then
		return nil
	end
	if reason == "locked" then
		return `Learn at level {skill.unlockLevel}`
	elseif reason == "rankLocked" then
		local next = SkillRules.rankOf(owned(), skill.id) + 1
		return `Rank {next} opens at level {SkillRules.rankLevel(next)}`
	elseif reason == "requires" then
		local need = SkillDefinitions.get(skill.requires)
		return `Requires {if need then need.name else "the skill above"}`
	elseif reason == "noPoints" then
		return "No skill points (3 per level)"
	elseif reason == "maxRank" then
		return "Max rank"
	end
	return "Not available"
end

--------------------------------------------------------------------------------
-- Skill bar editing
--------------------------------------------------------------------------------

local function sendLoadout(regular: { string? }, special: string?)
	local compact = {}
	for index = 1, SkillRules.REGULAR_SLOTS do
		local id = regular[index]
		if id then
			table.insert(compact, id)
		end
	end
	local ok = SkillRules.validateLoadout(state().Job, owned(), compact, special)
	if not ok then
		NotificationController:ShowKey("Warning", "skill.loadoutInvalid")
		return
	end
	NetClient.fire("SetLoadout", compact, special)
end

-- The regular slots as a fixed-size list (nil = empty slot).
local function regularSlots(): { string? }
	local regular: { string? } = {}
	for index = 1, SkillRules.REGULAR_SLOTS do
		regular[index] = state().EquippedSkills.Regular[index]
	end
	return regular
end

local function equip(skill: Skill, slot: number)
	local loadout = state().EquippedSkills
	local regular = regularSlots()
	local special = loadout.Special
	if skill.type == "Special" then
		special = skill.id
	else
		local from = table.find(regular, skill.id)
		if from then
			regular[from] = regular[slot]
		end
		regular[slot] = skill.id
	end
	sendLoadout(regular, special)
end

local function unequip(skill: Skill)
	local loadout = state().EquippedSkills
	local regular = regularSlots()
	local special = loadout.Special
	if special == skill.id then
		special = nil
	end
	local index = table.find(regular, skill.id)
	if index then
		regular[index] = nil
	end
	sendLoadout(regular, special)
end

local function slotOf(skill: Skill): string?
	local loadout = state().EquippedSkills
	if loadout.Special == skill.id then
		return "Ultimate"
	end
	local index = table.find(loadout.Regular, skill.id)
	return if index then `Slot {index}` else nil
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

local function smallButton(text: string, width: number, accent: Color3?): TextButton
	local button = Kit.new("TextButton", {
		Size = UDim2.fromOffset(width, 44),
		BackgroundColor3 = accent or Theme.Colors.GlassRaised,
		BackgroundTransparency = 0.05,
		Text = text,
		TextSize = 13,
		FontFace = Theme.Fonts.BodyBold,
		TextColor3 = if accent then Color3.fromRGB(30, 20, 8) else Theme.Colors.Text,
		TextWrapped = true,
		AutoButtonColor = true,
	})
	Kit.corner(button, 10)
	return button
end

local function line(parent: Instance, from: Vector2, to: Vector2, color: Color3, thickness: number): Frame
	local length = (to - from).Magnitude
	return Kit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset((from.X + to.X) / 2, (from.Y + to.Y) / 2),
		Size = UDim2.fromOffset(thickness, length),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = parent,
	}, { Kit.new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
end

-- D-103: an expanding ring and a chime when a skill is learned / ranked up.
local function burst(tile: GuiObject, color: Color3)
	local ring = Kit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.35,
		ZIndex = 8,
		Parent = tile,
	}, {
		Kit.new("UICorner", { CornerRadius = UDim.new(1, 0) }),
		Kit.new("UIStroke", { Color = color, Thickness = 3 }),
	})
	local info = TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(ring, info, { Size = UDim2.fromScale(2.4, 2.4), BackgroundTransparency = 1 }):Play()
	local stroke = ring:FindFirstChildOfClass("UIStroke")
	if stroke then
		TweenService:Create(stroke, info, { Transparency = 1 }):Play()
	end
	task.delay(0.6, function()
		ring:Destroy()
	end)
	local sound = Instance.new("Sound")
	sound.SoundId = LEARN_SOUND
	sound.Volume = 0.45
	SoundService:PlayLocalSound(sound)
end

local render: () -> ()

local function drawDetail(parent: Instance, skill: Skill?)
	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	if skill == nil then
		local hint = Kit.label(
			"Tap a skill in the tree to see what it does. Spend a skill point to learn it, then put it on your skill bar.",
			13,
			Theme.Fonts.Body,
			Theme.Colors.TextDim
		)
		hint.TextXAlignment = Enum.TextXAlignment.Left
		hint.Parent = parent
		return
	end
	local rank = SkillRules.rankOf(owned(), skill.id)
	local info = Kit.new("Frame", {
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.fromScale(1, 0),
		LayoutOrder = 1,
		Parent = parent,
	})
	local infoLayout = Kit.list(info, Enum.FillDirection.Vertical, 3, Enum.HorizontalAlignment.Left)
	infoLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	local why = blocker(skill)
	local equippedAt = slotOf(skill)
	SkillInfo.fill(info, skill, rank, {
		accent = colors().text,
		note = if equippedAt
			then `On your skill bar: {equippedAt}`
			elseif SkillDefinitions.isBasic(skill) then "Free: put it in a slot, then press its key (1 to 6)."
			elseif why and why ~= "Max rank" then why
			else nil,
		noteColor = if equippedAt then LEARNABLE else nil,
	})

	-- Buttons.
	local actions = Kit.new("Frame", {
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.fromScale(1, 0),
		LayoutOrder = 2,
		Parent = parent,
	})
	local flow = Kit.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(112, 44),
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = actions,
	})
	flow.FillDirectionMaxCells = 0
	local basic = SkillDefinitions.isBasic(skill)
	if basic then
		-- Free for every class: no Learn button, just the slots.
		local free = smallButton("✅ Free · known", 112)
		free.LayoutOrder = 1
		free.TextColor3 = LEARNABLE
		free.Parent = actions
	else
		local learnText = if rank >= skill.maxRank
			then "Max rank"
			elseif rank == 0 then "Learn (1 pt)"
			else `Rank {rank + 1} (1 pt)`
		local learn = smallButton(learnText, 112, if why == nil then Theme.Colors.Gold else nil)
		learn.LayoutOrder = 1
		learn.Parent = actions
		learn.Activated:Connect(function()
			if rank >= skill.maxRank then
				return
			end
			-- When it can't be learned yet the server explains why.
			pending = { id = skill.id, rank = rank }
			NetClient.fire("LearnSkill", skill.id)
		end)
		if why then
			learn.TextColor3 = Theme.Colors.TextMuted
		end
	end
	if rank >= 1 then
		if skill.type == "Special" then
			local put = smallButton(if equippedAt then "✅ Ultimate" else "Put in Ultimate", 112)
			put.LayoutOrder = 2
			put.Parent = actions
			put.Activated:Connect(function()
				equip(skill, SPECIAL_INDEX)
			end)
		else
			for slot = 1, SkillRules.REGULAR_SLOTS do
				local here = state().EquippedSkills.Regular[slot] == skill.id
				local put = smallButton(if here then `✅ Slot {slot}` else `Put in slot {slot}`, 112)
				put.LayoutOrder = 1 + slot
				put.Parent = actions
				put.Activated:Connect(function()
					equip(skill, slot)
				end)
			end
		end
		if equippedAt then
			local remove = smallButton("Remove from bar", 112)
			remove.LayoutOrder = 6
			remove.Parent = actions
			remove.Activated:Connect(function()
				unequip(skill)
			end)
		end
	end
end

local function drawNode(
	parent: Instance,
	skill: Skill,
	center: { x: number, y: number },
	size: number,
	columnWidth: number
)
	local rank = SkillRules.rankOf(owned(), skill.id)
	local why = blocker(skill)
	local learnable = why == nil
	local levelLocked = rank == 0 and not unlockAll() and state().Level < skill.unlockLevel
	local isSelected = selected == skill.id
	local special = skill.type == "Special"
	local theme = colors()
	local tile = Kit.new("TextButton", {
		Name = skill.id,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(center.x, center.y),
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 3,
		Parent = parent,
	})
	-- Grows on hover and when selected.
	local scale = Kit.new("UIScale", { Scale = if isSelected then 1.1 else 1, Parent = tile })
	local rest = scale.Scale
	tile.MouseEnter:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.12), { Scale = rest + 0.08 }):Play()
	end)
	tile.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.12), { Scale = rest }):Play()
	end)
	if special then
		-- The ultimate: a round frame with a spinning two-colour glow.
		local ring = Kit.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(size + 12, size + 12),
			BackgroundColor3 = theme.dark,
			BackgroundTransparency = if rank >= 1 then 0.2 else 0.5,
			ZIndex = 0,
			Parent = tile,
		}, { Kit.new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
		local glow = Kit.new("UIStroke", {
			Thickness = 3,
			Color = Color3.new(1, 1, 1),
			Transparency = if rank >= 1 or learnable then 0 else 0.55,
			Parent = ring,
		})
		local gradient = Kit.new("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, ULTIMATE_GOLD),
				ColorSequenceKeypoint.new(0.5, theme.primary),
				ColorSequenceKeypoint.new(1, ULTIMATE_GOLD),
			}),
			Parent = glow,
		})
		ClassTheme.spin(gradient, 4)
		Kit.new("TextLabel", {
			AnchorPoint = Vector2.new(0, 0),
			Position = UDim2.fromOffset(-8, -8),
			Size = UDim2.fromOffset(18, 18),
			BackgroundColor3 = ULTIMATE_GOLD,
			Text = "⭐",
			TextSize = 12,
			FontFace = Theme.Fonts.BodyBold,
			TextColor3 = Color3.fromRGB(40, 20, 0),
			ZIndex = 7,
			Parent = tile,
		}, { Kit.new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	end
	local icon = SkillIcon.forSkill(skill, size, { dim = rank == 0, lock = levelLocked, zIndex = 1 })
	icon.Parent = tile
	local stroke = Kit.new("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Thickness = if isSelected then 3 elseif special then 2.5 else 2,
		Color = if isSelected
			then Color3.new(1, 1, 1)
			elseif learnable then LEARNABLE
			elseif rank >= 1 then (if special then ULTIMATE_GOLD else theme.primary)
			else LOCKED_LINE,
		Parent = icon,
	})
	stroke.Transparency = 0
	if learnable and not isSelected then
		-- Learnable: the outline breathes.
		ClassTheme.pulse(stroke, 0.7, { Transparency = 0.65 })
	end
	if pending and pending.id == skill.id and rank > pending.rank then
		pending = nil
		task.defer(burst, tile, if special then ULTIMATE_GOLD else theme.accent)
	end
	-- Rank badge (bottom-left; the padlock sits bottom-right).
	Kit.new("TextLabel", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, -4, 1, 4),
		Size = UDim2.fromOffset(26, 14),
		BackgroundColor3 = if rank >= 1 then Theme.Colors.Gold else Theme.Colors.Ink,
		BackgroundTransparency = 0.05,
		Text = `{rank}/{skill.maxRank}`,
		TextSize = 10,
		FontFace = Theme.Fonts.BodyBold,
		TextColor3 = if rank >= 1 then Color3.fromRGB(30, 20, 8) else Theme.Colors.TextMuted,
		ZIndex = 6,
		Parent = tile,
	}, { Kit.new("UICorner", { CornerRadius = UDim.new(0, 5) }) })
	if learnable then
		Kit.new("TextLabel", {
			BackgroundColor3 = LEARNABLE,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0),
			Size = UDim2.fromOffset(44, 14),
			Text = if rank == 0 then "LEARN" else "+RANK",
			TextSize = 9,
			FontFace = Theme.Fonts.BodyBold,
			TextColor3 = Color3.fromRGB(10, 40, 20),
			ZIndex = 6,
			Parent = tile,
		}, { Kit.new("UICorner", { CornerRadius = UDim.new(0, 5) }) })
	end
	local label = Kit.new("TextLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(center.x, center.y + size / 2 + (if special then 6 else 2)),
		Size = UDim2.fromOffset(math.max(columnWidth - 4, size), SkillTreeLayout.LABEL_HEIGHT),
		Text = if levelLocked then `{skill.name}\nLv {skill.unlockLevel}` else skill.name,
		TextSize = 10,
		FontFace = Theme.Fonts.BodyBold,
		TextColor3 = if special and rank >= 1
			then ULTIMATE_GOLD
			elseif rank >= 1 then Theme.Colors.Text
			elseif levelLocked then Theme.Colors.TextMuted
			else Theme.Colors.TextDim,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 3,
		Parent = parent,
	})
	label.TextTruncate = Enum.TextTruncate.AtEnd
	tile.Activated:Connect(function()
		selected = skill.id
		render()
	end)
end

--------------------------------------------------------------------------------
-- Class passives (D-104): always on once learned, no bar slot
--------------------------------------------------------------------------------

local PASSIVE_TEAL = Color3.fromRGB(120, 230, 220)

local function drawPassiveDetail(parent: Instance, passive: PassiveDefinitions.Passive)
	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local rank = SkillRules.rankOf(owned(), passive.id)
	local why = blocker(passive)
	local function add(text: string, size: number, font: Font, color: Color3, order: number)
		local label = Kit.label(text, size, font, color)
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.LayoutOrder = order
		label.Parent = parent
	end
	add(passive.name, 18, Theme.Fonts.Display, colors().text, 1)
	add(
		`PASSIVE · ALWAYS ON · no slot needed · rank {rank}/{passive.maxRank}`,
		11,
		Theme.Fonts.BodyBold,
		PASSIVE_TEAL,
		2
	)
	add(passive.description, 13, Theme.Fonts.Body, Theme.Colors.TextDim, 3)
	local now = PassiveRules.describe(passive, rank)
	add(
		if #now > 0 then "Now: " .. table.concat(now, ", ") else "Not learned yet.",
		13,
		Theme.Fonts.BodyBold,
		if #now > 0 then LEARNABLE else Theme.Colors.TextMuted,
		4
	)
	if rank < passive.maxRank then
		add(
			`Rank {rank + 1}: ` .. table.concat(PassiveRules.describe(passive, rank + 1), ", "),
			13,
			Theme.Fonts.BodyBold,
			Theme.Colors.Text,
			5
		)
	end
	if why and why ~= "Max rank" then
		add(why, 12, Theme.Fonts.BodyBold, Color3.fromRGB(255, 170, 130), 6)
	end
	local learnText = if rank >= passive.maxRank
		then "Max rank"
		elseif rank == 0 then "Learn (1 pt)"
		else `Rank {rank + 1} (1 pt)`
	local learn = smallButton(learnText, 140, if why == nil then Theme.Colors.Gold else nil)
	learn.LayoutOrder = 7
	learn.Parent = parent
	if why then
		learn.TextColor3 = Theme.Colors.TextMuted
	end
	learn.Activated:Connect(function()
		if rank >= passive.maxRank then
			return
		end
		pending = { id = passive.id, rank = rank }
		NetClient.fire("LearnSkill", passive.id)
	end)
end

-- A diamond node: passives look different from skills at a glance (and are
-- labelled, so not by shape alone).
local function drawPassive(
	parent: Instance,
	passive: PassiveDefinitions.Passive,
	center: { x: number, y: number },
	size: number,
	width: number
)
	local rank = SkillRules.rankOf(owned(), passive.id)
	local why = blocker(passive)
	local learnable = why == nil
	local levelLocked = rank == 0 and not unlockAll() and state().Level < passive.unlockLevel
	local isSelected = selected == passive.id
	local tile = Kit.new("TextButton", {
		Name = passive.id,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(center.x, center.y),
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 3,
		Parent = parent,
	})
	local scale = Kit.new("UIScale", { Scale = if isSelected then 1.1 else 1, Parent = tile })
	local rest = scale.Scale
	tile.MouseEnter:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.12), { Scale = rest + 0.08 }):Play()
	end)
	tile.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.12), { Scale = rest }):Play()
	end)
	local diamond = Kit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size * 0.78, size * 0.78),
		Rotation = 45,
		BackgroundColor3 = colors().dark,
		BackgroundTransparency = if rank >= 1 then 0.1 else 0.45,
		ZIndex = 1,
		Parent = tile,
	}, { Kit.new("UICorner", { CornerRadius = UDim.new(0, 6) }) })
	local stroke = Kit.new("UIStroke", {
		Thickness = if isSelected then 3 else 2,
		Color = if isSelected
			then Color3.new(1, 1, 1)
			elseif learnable then LEARNABLE
			elseif rank >= 1 then PASSIVE_TEAL
			else LOCKED_LINE,
		Parent = diamond,
	})
	if learnable and not isSelected then
		ClassTheme.pulse(stroke, 0.7, { Transparency = 0.65 })
	end
	local icon = SkillIcon.forSkill(passive, math.floor(size * 0.62), {
		plain = true,
		dim = rank == 0,
		lock = levelLocked,
		zIndex = 2,
	})
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Parent = tile
	if pending and pending.id == passive.id and rank > pending.rank then
		pending = nil
		task.defer(burst, tile, PASSIVE_TEAL)
	end
	Kit.new("TextLabel", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, -4, 1, 4),
		Size = UDim2.fromOffset(26, 14),
		BackgroundColor3 = if rank >= 1 then PASSIVE_TEAL else Theme.Colors.Ink,
		BackgroundTransparency = 0.05,
		Text = `{rank}/{passive.maxRank}`,
		TextSize = 10,
		FontFace = Theme.Fonts.BodyBold,
		TextColor3 = if rank >= 1 then Color3.fromRGB(8, 30, 30) else Theme.Colors.TextMuted,
		ZIndex = 6,
		Parent = tile,
	}, { Kit.new("UICorner", { CornerRadius = UDim.new(0, 5) }) })
	if learnable then
		Kit.new("TextLabel", {
			BackgroundColor3 = LEARNABLE,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0),
			Size = UDim2.fromOffset(44, 14),
			Text = if rank == 0 then "LEARN" else "+RANK",
			TextSize = 9,
			FontFace = Theme.Fonts.BodyBold,
			TextColor3 = Color3.fromRGB(10, 40, 20),
			ZIndex = 6,
			Parent = tile,
		}, { Kit.new("UICorner", { CornerRadius = UDim.new(0, 5) }) })
	end
	local label = Kit.new("TextLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(center.x, center.y + size / 2 + 2),
		Size = UDim2.fromOffset(math.max(width - 6, size), SkillTreeLayout.LABEL_HEIGHT),
		Text = if levelLocked then `{passive.name}\nLv {passive.unlockLevel}` else passive.name,
		TextSize = 10,
		FontFace = Theme.Fonts.BodyBold,
		TextColor3 = if rank >= 1
			then PASSIVE_TEAL
			elseif levelLocked then Theme.Colors.TextMuted
			else Theme.Colors.TextDim,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 3,
		Parent = parent,
	})
	label.TextTruncate = Enum.TextTruncate.AtEnd
	tile.Activated:Connect(function()
		selected = passive.id
		render()
	end)
end

local function drawPassiveRow(parent: Instance, layout: SkillTreeLayout.Layout)
	local passives = PassiveDefinitions.forJob(state().Job)
	if #passives == 0 then
		return
	end
	local theme = colors()
	Kit.new("Frame", {
		Position = UDim2.fromOffset(3, layout.passiveTop),
		Size = UDim2.fromOffset(layout.tree.w - 6, layout.tree.h - layout.passiveTop - 2),
		BackgroundColor3 = PASSIVE_TEAL,
		BackgroundTransparency = 0.9,
		BorderSizePixel = 0,
		ZIndex = 0,
		Parent = parent,
	}, {
		Kit.new("UICorner", { CornerRadius = UDim.new(0, 12) }),
		Kit.new("UIStroke", { Color = PASSIVE_TEAL, Transparency = 0.7, Thickness = 1 }),
	})
	Kit.new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, layout.passiveTop + 4),
		Size = UDim2.fromOffset(layout.tree.w - 20, 18),
		Text = "◆ PASSIVES · always on, no slot needed",
		TextSize = 12,
		FontFace = Theme.Fonts.Display,
		TextColor3 = theme.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = parent,
	})
	local width = layout.tree.w / SkillTreeLayout.PASSIVES
	for index, passive in passives do
		local center = layout.passives[index]
		if center then
			drawPassive(parent, passive, center, layout.node, width)
		end
	end
end

local function drawTree(parent: Instance, layout: SkillTreeLayout.Layout)
	local job = state().Job
	local branches = (SkillDefinitions.Branches :: any)[job or ""] or {}
	local columnWidth = layout.columnWidth
	local first = SkillDefinitions.forJob(job)[1]
	local element = if first then first.fx.element else nil
	local theme = colors()
	for index, branch in branches do
		-- D-103: a tinted card behind each branch column.
		local card = Kit.new("Frame", {
			Position = UDim2.fromOffset((index - 1) * columnWidth + 3, 0),
			Size = UDim2.fromOffset(columnWidth - 6, layout.passiveTop - 4),
			BackgroundColor3 = theme.primary,
			BackgroundTransparency = 0.86,
			BorderSizePixel = 0,
			ZIndex = 0,
			Parent = parent,
		}, {
			Kit.new("UICorner", { CornerRadius = UDim.new(0, 12) }),
			Kit.new("UIGradient", {
				Rotation = 90,
				Transparency = NumberSequence.new(0.1, 0.85),
			}),
			Kit.new("UIStroke", { Color = theme.primary, Transparency = 0.75, Thickness = 1 }),
		})
		card.Name = `Branch{index}`
		local head = Kit.new("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset((index - 1) * columnWidth, 0),
			Size = UDim2.fromOffset(columnWidth, layout.columnHeader),
			Parent = parent,
		})
		local column = SkillDefinitions.at(job, branch.id, 1)
		local mark = SkillIcon.forSkill(branch, 18, {
			plain = true,
			element = if column then column.fx.element else element,
		})
		mark.Position = UDim2.fromOffset(2, 2)
		mark.Parent = head
		Kit.new("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(22, 0),
			Size = UDim2.new(1, -24, 0, 18),
			Text = branch.name,
			TextSize = 12,
			FontFace = Theme.Fonts.Display,
			TextColor3 = theme.text,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = head,
		})
		local role = ClassTheme.role(branch.id)
		if role then
			Kit.new("TextLabel", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(4, 18),
				Size = UDim2.new(1, -6, 0, 12),
				Text = role,
				TextSize = 9,
				FontFace = Theme.Fonts.BodyBold,
				TextColor3 = theme.accent,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Parent = head,
			})
		end
		-- Connectors first (under the nodes).
		for tier = 2, SkillTreeLayout.TIERS do
			local skill = SkillDefinitions.at(job, branch.id, tier)
			local a, b = layout.nodes[`{index}.{tier - 1}`], layout.nodes[`{index}.{tier}`]
			if skill and a and b then
				local learnedLink = SkillRules.rankOf(owned(), skill.id) >= 1
				-- The way forward: the skill above is learned and this one can be.
				local next = not learnedLink and blocker(skill) == nil
				local link = line(
					parent,
					Vector2.new(a.x, a.y + layout.node / 2 + SkillTreeLayout.LABEL_HEIGHT),
					Vector2.new(b.x, b.y - layout.node / 2),
					if learnedLink then theme.primary elseif next then LEARNABLE else LOCKED_LINE,
					if learnedLink then 5 elseif next then 3 else 2
				)
				if learnedLink then
					Kit.new("UIGradient", {
						Rotation = 90,
						Color = ColorSequence.new(theme.primary, theme.accent),
						Parent = link,
					})
				elseif next then
					ClassTheme.pulse(link, 0.7, { BackgroundTransparency = 0.6 })
				end
			end
		end
		for tier = 1, SkillTreeLayout.TIERS do
			local skill = SkillDefinitions.at(job, branch.id, tier)
			local center = layout.nodes[`{index}.{tier}`]
			if skill and center then
				drawNode(parent, skill, center, layout.node, columnWidth)
			end
		end
	end
	drawPassiveRow(parent, layout)
end

local function drawBar(parent: Instance, layout: SkillTreeLayout.Layout)
	-- Scrolls sideways when the 7 slots don't fit (phones, D-75).
	local row = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = Theme.Colors.Gold,
		VerticalScrollBarInset = Enum.ScrollBarInset.None,
		Parent = parent,
	})
	Kit.list(row, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center)
	-- Basic skills first (free for every class): tap to inspect and slot.
	for order, basic in SkillDefinitions.Basics do
		local holder = Kit.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(layout.barSlot + 16, layout.barSlot + 16),
			LayoutOrder = -10 + order,
			Parent = row,
		})
		local tile = Kit.new("TextButton", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0),
			Size = UDim2.fromOffset(layout.barSlot, layout.barSlot),
			BackgroundColor3 = Theme.Colors.Ink,
			Text = "",
			Parent = holder,
		})
		Kit.corner(tile, 10)
		SkillIcon.forSkill(basic, layout.barSlot, {}).Parent = tile
		Kit.goldStroke(tile, if selected == basic.id then 3 else 1.5, 0.2)
		Kit.new("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, layout.barSlot + 1),
			Size = UDim2.new(1, 0, 0, 14),
			Text = `BASIC · {basic.name}`,
			TextSize = 10,
			FontFace = Theme.Fonts.BodyBold,
			TextColor3 = LEARNABLE,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = holder,
		})
		tile.Activated:Connect(function()
			selected = basic.id
			render()
		end)
	end
	local divider = Kit.new("Frame", {
		BackgroundColor3 = Theme.Colors.Gold,
		BackgroundTransparency = 0.6,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(2, layout.barSlot),
		LayoutOrder = 0,
		Parent = row,
	})
	divider.Name = "Divider"
	local loadout = state().EquippedSkills
	for index, name in SLOT_NAMES do
		local special = index == SPECIAL_INDEX
		local id = if special then loadout.Special else loadout.Regular[index]
		local skill = SkillDefinitions.get(id)
		local holder = Kit.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(layout.barSlot + 8, layout.barSlot + 16),
			LayoutOrder = index,
			Parent = row,
		})
		local tile = Kit.new("TextButton", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0),
			Size = UDim2.fromOffset(layout.barSlot, layout.barSlot),
			BackgroundColor3 = Theme.Colors.Ink,
			Text = if skill then "" else "+",
			TextSize = 24,
			FontFace = Theme.Fonts.DisplayHeavy,
			TextColor3 = Theme.Colors.TextMuted,
			Parent = holder,
		})
		Kit.corner(tile, if special then layout.barSlot // 2 else 10)
		if skill then
			local icon = SkillIcon.forSkill(skill, layout.barSlot, { round = special })
			icon.Parent = tile
		end
		if special then
			Kit.new("UIStroke", {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = ULTIMATE_GOLD,
				Thickness = 2.5,
				Parent = tile,
			})
		else
			Kit.new("UIStroke", {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = colors().primary,
				Transparency = if skill then 0.1 else 0.5,
				Thickness = 1.5,
				Parent = tile,
			})
		end
		Kit.new("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, layout.barSlot + 1),
			Size = UDim2.new(1, 0, 0, 14),
			Text = if skill then `{name} · {skill.name}` else `{name} · empty`,
			TextSize = 10,
			FontFace = Theme.Fonts.BodyBold,
			TextColor3 = Theme.Colors.TextDim,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = holder,
		})
		tile.Activated:Connect(function()
			if skill then
				selected = skill.id
				render()
			end
		end)
	end
end

function render()
	toggle.Visible = state().Job ~= nil
	local points = pointsLeft() + attributePoints()
	if toggleCompact() then
		toggle.Text = if points > 0 then `🌟{points}` else "🌟"
		toggle.TextSize = 20
	else
		toggle.Text = if points > 0 then `🌟 SKILLS ({points})` else "🌟 SKILLS"
		toggle.TextSize = 13
	end
	if panel then
		local oldBody = panel:FindFirstChild("Body")
		if oldBody and oldBody:IsA("ScrollingFrame") then
			scroll = oldBody.CanvasPosition
		end
		panel:Destroy()
		panel = nil
	end
	if not open then
		return
	end
	local camera = Workspace.CurrentCamera
	local area = gui.AbsoluteSize
	if area.X < 10 and camera then
		area = camera.ViewportSize
	end
	local layout = SkillTreeLayout.compute(area.X, area.Y)
	-- D-74: in the shared panel layer, above the HUD, one panel at a time.
	local frame = Kit.glassPanel({
		Name = "SkillTree",
		Position = UDim2.fromOffset(layout.panel.x, layout.panel.y),
		Size = UDim2.fromOffset(layout.panel.w, layout.panel.h),
		BackgroundTransparency = 0.04,
		Parent = Panels.layer(),
	})
	panel = frame
	local theme = colors()
	-- D-103: the class colours wash over the glass panel.
	Kit.new("Frame", {
		Name = "ClassTint",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = theme.dark,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		ZIndex = 0,
		Parent = frame,
	}, {
		Kit.new("UICorner", { CornerRadius = UDim.new(0, 16) }),
		Kit.new("UIGradient", {
			Rotation = 120,
			Color = ColorSequence.new(theme.dark, theme.primary:Lerp(theme.dark, 0.7)),
		}),
	})
	Kit.new("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = theme.primary,
		Transparency = 0.35,
		Thickness = 1.5,
		Parent = frame,
	})
	if justOpened then
		justOpened = false
		local grow = Kit.new("UIScale", { Scale = 0.94, Parent = frame })
		TweenService
			:Create(grow, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
			:Play()
	end

	local attributesPage = page == "Attributes"
	if attributesPage then
		points = attributePoints()
	else
		points = pointsLeft()
	end

	-- Header.
	local job = JobDefinitions.get(state().Job)
	local header = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(layout.header.x, layout.header.y + 2),
		Size = UDim2.fromOffset(layout.header.w, layout.header.h - 4),
		Parent = frame,
	})
	-- D-90: switch between the skill tree and the attributes.
	local unspentAttributes = attributePoints()
	local switch = smallButton(
		if attributesPage
			then "🌟 Skills"
			elseif unspentAttributes > 0 then `📊 Stats ({unspentAttributes})`
			else "📊 Stats",
		112,
		if not attributesPage and unspentAttributes > 0 then LEARNABLE else nil
	)
	switch.Parent = header
	switch.Activated:Connect(function()
		page = if attributesPage then "Skills" else "Attributes"
		render()
	end)
	local title = Kit.label(
		if attributesPage then "Attributes" elseif job then `{job.displayName} Skill Tree` else "Skill Tree",
		17,
		Theme.Fonts.Display,
		theme.text
	)
	title.AutomaticSize = Enum.AutomaticSize.None
	title.Position = UDim2.fromOffset(118, 0)
	title.Size = UDim2.new(1, -368, 1, 0)
	title.Visible = layout.header.w >= 480
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.TextWrapped = false
	title.Parent = header
	local right = Kit.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, 246, 1, 0),
		Parent = header,
	})
	Kit.list(right, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Right)
	local pointsLabel = Kit.new("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(84, 44),
		Text = `Points: {points}`,
		TextSize = 13,
		FontFace = Theme.Fonts.BodyBold,
		TextColor3 = if points > 0 then LEARNABLE else Theme.Colors.TextDim,
		LayoutOrder = 1,
		Parent = right,
	})
	pointsLabel.TextWrapped = true
	-- D-105: with the free reset switched off (admin) the button uses a
	-- scroll and shows how many you have.
	local free = ReplicatedStorage:GetAttribute(
		if attributesPage then Constants.Attributes.FreeAttributeReset else Constants.Attributes.FreeTreeReset
	) ~= false
	local scrollId = if attributesPage then "RebirthScroll" else "RelearnScroll"
	local scrolls = state().Stackables[scrollId] or 0
	local reset = smallButton(if free then "Reset" else `📜 ×{scrolls}`, 72)
	reset.LayoutOrder = 2
	reset.Parent = right
	if not free and scrolls <= 0 then
		reset.TextColor3 = Theme.Colors.TextMuted
	end
	Tooltip.attach(reset, function()
		local name = if attributesPage then "Scroll of Rebirth" else "Scroll of Relearning"
		if free then
			return "Reset",
				if attributesPage
					then "Get every attribute point back (free once a day)."
					else "Get every skill point back (free, in a safe zone)."
		end
		return `📜 {name}`, `The free reset is off. Uses one {name} (Item Mall). You have {scrolls}.`
	end)
	reset.Activated:Connect(function()
		NetClient.fire(if attributesPage then "ResetAttributes" else "ResetSkills")
	end)
	local close = smallButton("Close", 72)
	close.LayoutOrder = 3
	close.Parent = right
	close.Activated:Connect(function()
		SkillTreeController.setOpen(false)
	end)

	if attributesPage then
		local top = layout.bar.y
		local pageArea = Kit.new("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(layout.header.x, top),
			Size = UDim2.fromOffset(layout.header.w, layout.panel.h - top - 8),
			Parent = frame,
		})
		local s = state()
		AttributePanel.draw(
			pageArea,
			Vector2.new(layout.header.w, layout.panel.h - top - 8),
			s.Attributes,
			s.Level,
			s.Job,
			s.AttributeResetAt - os.clock(),
			function(id: string, n: number)
				NetClient.fire("SpendAttributes", { [id] = n })
			end,
			s.AttributeBonus,
			s.AttributeExtra
		)
		return
	end

	-- Skill bar row.
	local bar = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(layout.bar.x, layout.bar.y),
		Size = UDim2.fromOffset(layout.bar.w, layout.bar.h),
		Parent = frame,
	})
	drawBar(bar, layout)

	-- Body.
	local body = Kit.new("ScrollingFrame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(layout.body.x, layout.body.y),
		Size = UDim2.fromOffset(layout.body.w, layout.body.h),
		CanvasSize = UDim2.fromOffset(0, layout.tree.h),
		AutomaticCanvasSize = if layout.mode == "stacked"
			then Enum.AutomaticSize.Y
			else Enum.AutomaticSize.None,
		ScrollBarThickness = 6,
		Parent = frame,
	})
	local tree = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(layout.tree.w, layout.tree.h),
		Parent = body,
	})
	drawTree(tree, layout)

	local detailParent: Instance
	if layout.mode == "wide" then
		local detail = Kit.new("ScrollingFrame", {
			BackgroundColor3 = Theme.Colors.Ink,
			BackgroundTransparency = 0.4,
			Position = UDim2.fromOffset(layout.detail.x, layout.detail.y),
			Size = UDim2.fromOffset(layout.detail.w, layout.detail.h),
			CanvasSize = UDim2.fromScale(0, 0),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = 6,
			Parent = frame,
		})
		Kit.corner(detail, 12)
		Kit.padding(detail, 10, 12)
		Kit.new("UIStroke", {
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = theme.primary,
			Transparency = 0.55,
			Thickness = 1,
			Parent = detail,
		})
		detailParent = detail
	else
		detailParent = Kit.new("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(layout.detail.x, layout.detail.y),
			Size = UDim2.fromOffset(layout.detail.w, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = body,
		})
	end
	local detailLayout =
		Kit.list(detailParent, Enum.FillDirection.Vertical, 10, Enum.HorizontalAlignment.Left)
	detailLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	local passive = PassiveDefinitions.get(selected)
	if passive then
		drawPassiveDetail(detailParent, passive)
	else
		drawDetail(detailParent, SkillDefinitions.get(selected))
	end
	body.CanvasPosition = scroll
end

function SkillTreeController.setOpen(value: boolean)
	-- Attribute points but no skill points: open on the Attributes page.
	if value and not open and pointsLeft() == 0 and attributePoints() > 0 then
		page = "Attributes"
	end
	justOpened = value and not open
	open = value
	if value then
		Panels.opened("skills")
	else
		Panels.closed("skills")
	end
	render()
end

function SkillTreeController.toggle()
	SkillTreeController.setOpen(not open)
end

function SkillTreeController:Start()
	gui = Kit.new("ScreenGui", {
		Name = "RC_SkillTree",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		DisplayOrder = 7,
	})
	toggle = Kit.new("TextButton", {
		Name = "SkillsToggle",
		AnchorPoint = Vector2.new(1, 0.5),
		-- Placed by HudLayout.bindToggle (CombatButtonsLayout.toggles) in Start.
		Position = UDim2.new(1, -8, 0.5, -56),
		Size = UDim2.fromOffset(110, 44),
		BackgroundColor3 = Theme.Colors.Glass,
		BackgroundTransparency = 0.15,
		Text = "🌟 SKILLS",
		TextSize = 13,
		FontFace = Theme.Fonts.BodyBold,
		TextColor3 = Theme.Colors.GoldBright,
		AutoButtonColor = true,
		Visible = false,
		Parent = gui,
	})
	Tooltip.attach(toggle, function()
		return "🌟 Skills and attributes",
			`Learn skills, set your skill bar and spend attribute points (📊 Stats). Skill points: {pointsLeft()}, attribute points: {attributePoints()}. Key: K.`
	end)
	Kit.corner(toggle, 12)
	Kit.goldStroke(toggle, 1.5, 0.2)
	HudLayout.register("Skills", toggle)
	toggle.Activated:Connect(SkillTreeController.toggle)
	gui.Parent = player():WaitForChild("PlayerGui")
	toggleCompact = HudLayout.bindToggle("Skills", toggle, "skills", render)
	Panels.register("skills", function()
		SkillTreeController.setOpen(false)
	end)

	SkillBarController.OpenTree = function()
		SkillTreeController.setOpen(true)
	end
	render()
	-- D-90: tell the player where unspent attribute points go (on joining
	-- and when a level brings new ones).
	local told = false
	PlayerDataController.Changed:Connect(function(s, reason, levelsGained)
		render()
		local left = attributePoints()
		if s.Job ~= nil and left > 0 and ((reason == "snapshot" and not told) or (levelsGained or 0) > 0) then
			told = true
			NotificationController:ShowKey("Info", "attributes.available", { points = tostring(left) })
		end
	end)
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if open then
			render()
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.K then
			SkillTreeController.toggle()
		end
	end)
end

return SkillTreeController
