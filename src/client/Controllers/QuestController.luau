--!strict
--[[
	QuestController — the quest UI (Phase 11, PLAN.md D-73; CLAUDE.md §28).

	  - Tracker (Layout/QuestLayout): the current quest and its next step,
	    top-right; a "📜" pill where a card would cover something. Tap it
	    or press J for the quest log.
	  - Quest log: every story quest with its state (✅ done, ▶ active,
	    ⭐ ready to hand in, ! available, 🔒 level / earlier quest), the
	    selected quest's steps and rewards, and your titles (tap to wear).
	  - Dialogue: what your realm's quest giver says (QuestDialogue), with
	    Accept / Complete buttons (QuestAccept / QuestTurnIn intents; the
	    server checks everything).
	  - In the world: the giver shows "!" (a quest to take) or "⭐" (one to
	    hand in); quest objects (fragments, gates, clues) show and can be
	    used only while a step needs them; a marker with the distance points
	    at the next place to go when it is known (a place in the capital, a
	    quest object, the giver).
	  - Titles: each player's worn title floats over their head.

	Display only: progress comes from the server (QuestUpdate).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local QuestDefinitions = require(Shared.Definitions.QuestDefinitions)
local WorldLayout = require(Shared.Definitions.WorldLayout)
local QuestRules = require(Shared.Logic.QuestRules)
local PvPRules = require(Shared.Logic.PvPRules)
local QuestLayout = require(Shared.Layout.QuestLayout)
local NetClient = require(Shared.Net.Client)

local UI = script.Parent.Parent.UI
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)
local Panels = require(UI.Panels)
local HudLayout = require(UI.HudLayout)

local PlayerDataController = require(script.Parent.PlayerDataController)

type Quest = QuestDefinitions.Quest

local GOLD_TEXT = Color3.fromRGB(30, 20, 8)
local MARKER_SECONDS = 0.25

local QuestController = {}

local gui: ScreenGui
local trackerButton: TextButton
local panel: Frame? = nil
local panelMode: "log" | "dialogue" | nil = nil
local dialogue: any = nil
local selectedQuest: string? = nil
local marker: BillboardGui
local markerLabel: TextLabel
-- A client-only point the marker hangs on.
local markerAnchor: Part
local markerTarget: Vector3? = nil
local questParts: { [BasePart]: string } = {}
local giverMarks: { [Model]: BillboardGui } = {}

local function localPlayer(): Player
	return Players.LocalPlayer :: Player
end

local function state(): PlayerDataController.State
	return PlayerDataController:Get()
end

-- Server progress as QuestRules progress (Found as a set).
local function progressOf(questId: string): QuestRules.Progress?
	local view = state().Quests.Quests[questId]
	if view == nil then
		return nil
	end
	local found = {}
	for _, target in view.Found do
		found[target] = true
	end
	return { Status = view.Status, Objectives = view.Objectives, Found = found, AcceptedAt = 0 }
end

local function questState(): QuestRules.State
	local out = {}
	for id in state().Quests.Quests do
		local progress = progressOf(id)
		if progress then
			out[id] = progress
		end
	end
	return out
end

local function fill(text: string): string
	return QuestDefinitions.fill(text, state().Race, localPlayer().DisplayName)
end

-- The quest the tracker follows: the first active or ready one in story
-- order.
local function pinned(): (Quest?, QuestRules.Progress?)
	for _, quest in QuestDefinitions.List do
		local progress = progressOf(quest.id)
		if progress and progress.Status ~= "Completed" then
			return quest, progress
		end
	end
	return nil, nil
end

local function giverName(): string
	local giver = QuestDefinitions.Givers[state().Race or ""]
	return if giver then giver.name else "your commander"
end

local function button(text: string, width: number, accent: boolean?): TextButton
	local b = Kit.new("TextButton", {
		Size = UDim2.fromOffset(width, 44),
		BackgroundColor3 = if accent then Theme.Colors.Gold else Theme.Colors.GlassRaised,
		BackgroundTransparency = 0.05,
		Text = text,
		TextSize = 13,
		FontFace = Theme.Fonts.BodyBold,
		TextColor3 = if accent then GOLD_TEXT else Theme.Colors.Text,
		TextWrapped = true,
		AutoButtonColor = true,
	})
	Kit.corner(b, 10)
	return b
end

local function text(
	parent: Instance,
	value: string,
	size: number,
	color: Color3?,
	font: Font?,
	order: number?
): TextLabel
	return Kit.new("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = value,
		TextSize = size,
		FontFace = font or Theme.Fonts.Body,
		TextColor3 = color or Theme.Colors.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		LayoutOrder = order or 0,
		Parent = parent,
	})
end

local function layout(): QuestLayout.Layout
	local size = gui.AbsoluteSize
	if size.X < 10 then
		local camera = Workspace.CurrentCamera
		size = if camera then camera.ViewportSize else Vector2.new(800, 600)
	end
	return QuestLayout.compute(size.X, size.Y)
end

--------------------------------------------------------------------------------
-- Tracker
--------------------------------------------------------------------------------

local function stepText(quest: Quest, progress: QuestRules.Progress): (string, string)
	if progress.Status == "ReadyToTurnIn" then
		return `⭐ Return to {giverName()}`, "⭐"
	end
	local objective = QuestRules.current(quest, progress)
	if objective == nil then
		return "", ""
	end
	local count = progress.Objectives[objective.id] or 0
	local tally = if objective.target > 1 then ` {count}/{objective.target}` else ""
	return `▶ {objective.text}{tally}`, if objective.target > 1 then `{count}/{objective.target}` else "▶"
end

local function refreshTracker()
	local data = state()
	local l = layout()
	trackerButton.Visible = data.Job ~= nil
	trackerButton.Position = UDim2.fromOffset(l.tracker.x, l.tracker.y)
	trackerButton.Size = UDim2.fromOffset(l.tracker.w, l.tracker.h)
	trackerButton.AnchorPoint = Vector2.zero
	HudLayout.apply("Quest")
	local quest, progress = pinned()
	local title, step, short
	if quest and progress then
		title = quest.name
		step, short = stepText(quest, progress)
	else
		local offers = QuestRules.offers(questState(), data.Level)
		if #offers > 0 then
			title, step, short = "New quest", `! Talk to {giverName()}`, "!"
		else
			title, step, short = "Quests", "Open the quest log", ""
		end
	end
	if l.trackerMode == "pill" then
		trackerButton.Text = `📜 {if short ~= "" then short else "QUESTS"}`
		trackerButton.TextXAlignment = Enum.TextXAlignment.Center
		trackerButton.TextSize = 13
	else
		trackerButton.Text = `<b><font color="#FFE6A0">📜 {title}</font></b>\n{step}`
		trackerButton.TextXAlignment = Enum.TextXAlignment.Left
		trackerButton.TextSize = 12
	end
end

--------------------------------------------------------------------------------
-- Panels (log and dialogue)
--------------------------------------------------------------------------------

local renderPanel: () -> ()

local function closePanel()
	panelMode = nil
	dialogue = nil
	Panels.closed("quests")
	renderPanel()
end

local function panelFrame(titleText: string): (Frame, ScrollingFrame)
	local l = layout()
	-- D-74: in the shared panel layer (its contents were drawn behind the
	-- panel's own glass before, which made the text look dark).
	local frame = Kit.glassPanel({
		Name = "Quests",
		Position = UDim2.fromOffset(l.panel.x, l.panel.y),
		Size = UDim2.fromOffset(l.panel.w, l.panel.h),
		BackgroundTransparency = 0.04,
		Parent = Panels.layer(),
	})
	local title = Kit.label(titleText, 17, Theme.Fonts.Display, Theme.Colors.GoldBright)
	title.AutomaticSize = Enum.AutomaticSize.None
	title.Position = UDim2.fromOffset(12, 10)
	title.Size = UDim2.new(1, -110, 0, 24)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.Parent = frame
	local close = button("Close", 80)
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -8, 0, 6)
	close.Parent = frame
	close.Activated:Connect(closePanel)
	local body = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, 56),
		Size = UDim2.new(1, -20, 1, -66),
		CanvasSize = UDim2.fromScale(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = frame,
	})
	local list = Kit.list(body, Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Left)
	list.VerticalAlignment = Enum.VerticalAlignment.Top
	Kit.padding(body, 2, 4)
	return frame, body
end

local function rewardsText(quest: Quest): string
	local r = quest.rewards
	local parts = {}
	local xp = QuestRules.xpFor(quest)
	if xp > 0 then
		table.insert(parts, `{xp} EXP`)
	end
	for _, item in (r.items or {}) :: { QuestDefinitions.ItemReward } do
		local rarities = {}
		for name in item.rarity do
			table.insert(rarities, name)
		end
		table.sort(rarities)
		table.insert(parts, `{table.concat(rarities, " / ")} {item.kind}`)
	end
	for id, count in (r.stackables or {}) :: { [string]: number } do
		table.insert(parts, `{count}× {id}`)
	end
	for id, amount in (r.wallet or {}) :: { [string]: number } do
		table.insert(parts, `{amount} {id}`)
	end
	for _, title in (r.titles or {}) :: { string } do
		table.insert(parts, `title "{QuestDefinitions.Titles[title]}"`)
	end
	for _, cosmetic in (r.cosmetics or {}) :: { string } do
		table.insert(parts, QuestDefinitions.Cosmetics[cosmetic])
	end
	return "Rewards: " .. table.concat(parts, ", ")
end

local function statusMark(quest: Quest, all: QuestRules.State, level: number): (string, string)
	local progress = all[quest.id]
	if progress then
		if progress.Status == "Completed" then
			return "✅", "Done"
		elseif progress.Status == "ReadyToTurnIn" then
			return "⭐", "Hand in"
		end
		return "▶", "Active"
	end
	local ok, reason = QuestRules.canAccept(all, quest.id, level)
	if ok then
		return "!", "Available"
	elseif reason == "level" then
		return "🔒", `Level {quest.level}`
	end
	return "🔒", "Locked"
end

local function drawLog(body: ScrollingFrame)
	local data = state()
	local all = questState()
	-- Titles you own: tap to wear (or take off).
	local owned = data.Quests.Titles
	if #owned > 0 then
		text(body, "Titles", 13, Theme.Colors.GoldBright, Theme.Fonts.BodyBold, 1)
		local row = Kit.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 2,
			Parent = body,
		})
		Kit.new("UIGridLayout", {
			CellSize = UDim2.fromOffset(130, 44),
			CellPadding = UDim2.fromOffset(6, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = row,
		})
		for index, id in owned do
			local wearing = data.Quests.EquippedTitle == id
			local b = button(`{if wearing then "✅ " else ""}{QuestDefinitions.Titles[id]}`, 130, wearing)
			b.LayoutOrder = index
			b.Parent = row
			b.Activated:Connect(function()
				NetClient.fire("EquipTitle", if wearing then nil else id)
			end)
		end
	end
	-- PvP record and the next victory title (D-76).
	local victories = data.PvP.Victories
	local nextTitle, needed = PvPRules.nextTitle(victories)
	text(
		body,
		`🗡 PvP: {victories} victories · {data.Wallet.PvPMarks} PvP Marks`
			.. (
				if nextTitle
					then `  ·  next title « {QuestDefinitions.Titles[nextTitle]} » at {needed}`
					else ""
			),
		12,
		Theme.Colors.TextDim,
		Theme.Fonts.BodyBold,
		0
	)
	text(body, "Story", 13, Theme.Colors.GoldBright, Theme.Fonts.BodyBold, 3)
	local order = 4
	for _, quest in QuestDefinitions.List do
		local mark, word = statusMark(quest, all, data.Level)
		local open = selectedQuest == quest.id
		local row = button(`{mark}  {quest.order}. {quest.name}   ·  {word}`, 10, open)
		row.Size = UDim2.new(1, -4, 0, 44)
		row.TextXAlignment = Enum.TextXAlignment.Left
		Kit.padding(row, 0, 10)
		row.LayoutOrder = order
		row.Parent = body
		order += 1
		row.Activated:Connect(function()
			selectedQuest = if open then nil else quest.id
			renderPanel()
		end)
		if open then
			local detail = Kit.new("Frame", {
				BackgroundColor3 = Theme.Colors.Ink,
				BackgroundTransparency = 0.35,
				Size = UDim2.new(1, -4, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				LayoutOrder = order,
				Parent = body,
			})
			order += 1
			Kit.corner(detail, 10)
			Kit.padding(detail, 8, 10)
			local list = Kit.list(detail, Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Left)
			list.VerticalAlignment = Enum.VerticalAlignment.Top
			text(detail, fill(quest.summary), 13, Theme.Colors.Text, nil, 1)
			local progress = all[quest.id]
			local current = if progress then QuestRules.current(quest, progress) else nil
			for index, objective in quest.objectives do
				local count = if progress then progress.Objectives[objective.id] or 0 else 0
				local done = progress ~= nil and count >= objective.target
				local markText = if done then "✅" elseif current == objective then "▶" else "·"
				local tally = if objective.target > 1 then `  {count}/{objective.target}` else ""
				text(
					detail,
					`{markText} {objective.text}{tally}`,
					12,
					if done then Theme.Colors.Safe else Theme.Colors.TextDim,
					Theme.Fonts.BodyBold,
					1 + index
				)
			end
			text(detail, rewardsText(quest), 12, Theme.Colors.GoldBright, nil, 50)
			if progress == nil then
				text(
					detail,
					`Accept it from {giverName()} in your capital.`,
					12,
					Theme.Colors.TextMuted,
					nil,
					51
				)
			elseif progress.Status == "ReadyToTurnIn" then
				text(detail, `Hand it in to {giverName()}.`, 12, Theme.Colors.Safe, nil, 51)
			end
		end
	end
end

local MODE_BUTTON: { [string]: string } = { Offer = "Accept", TurnIn = "Complete" }

local function drawDialogue(body: ScrollingFrame)
	local payload = dialogue
	if payload == nil then
		return
	end
	text(body, payload.Title, 12, Theme.Colors.TextDim, nil, 1)
	local order = 2
	for _, entry in payload.Entries do
		local quest = QuestDefinitions.get(entry.Quest)
		if quest == nil then
			continue
		end
		local box = Kit.new("Frame", {
			BackgroundColor3 = Theme.Colors.Ink,
			BackgroundTransparency = 0.35,
			Size = UDim2.new(1, -4, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = order,
			Parent = body,
		})
		order += 1
		Kit.corner(box, 10)
		Kit.padding(box, 8, 10)
		local list = Kit.list(box, Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Left)
		list.VerticalAlignment = Enum.VerticalAlignment.Top
		local heading = if entry.Mode == "TurnIn"
			then `⭐ {quest.name}: complete`
			elseif entry.Mode == "Offer" then `! {quest.name}`
			elseif entry.Mode == "Later" then `🔒 {quest.name}`
			else `▶ {quest.name}`
		text(box, heading, 14, Theme.Colors.GoldBright, Theme.Fonts.BodyBold, 1)
		text(box, `"{entry.Text}"`, 13, Theme.Colors.Text, nil, 2)
		if entry.Mode == "Offer" or entry.Mode == "TurnIn" then
			text(box, rewardsText(quest), 12, Theme.Colors.TextDim, nil, 3)
		end
		local label = MODE_BUTTON[entry.Mode]
		if label then
			local b = button(label, 140, true)
			b.LayoutOrder = 4
			b.Parent = box
			local id, mode = quest.id, entry.Mode
			b.Activated:Connect(function()
				NetClient.fire(if mode == "Offer" then "QuestAccept" else "QuestTurnIn", id)
			end)
		end
	end
	if payload.Idle then
		text(body, `"{payload.Idle}"`, 13, Theme.Colors.Text, nil, order)
	end
end

function renderPanel()
	if panel then
		panel:Destroy()
		panel = nil
	end
	if panelMode == "log" then
		local frame, body = panelFrame("Quest Log")
		panel = frame
		drawLog(body)
	elseif panelMode == "dialogue" and dialogue then
		local frame, body = panelFrame(dialogue.Giver)
		panel = frame
		drawDialogue(body)
	end
end

function QuestController.toggleLog()
	if panelMode == "log" then
		closePanel()
		return
	end
	panelMode = "log"
	Panels.opened("quests")
	renderPanel()
end

--------------------------------------------------------------------------------
-- World: quest objects, the giver's mark, the marker
--------------------------------------------------------------------------------

-- Ids of quest objects a current step needs (not yet found).
local function wantedTargets(): { [string]: boolean }
	local wanted = {}
	for _, quest in QuestDefinitions.List do
		local progress = progressOf(quest.id)
		local objective = if progress and progress.Status == "Active"
			then QuestRules.current(quest, progress)
			else nil
		if objective and objective.type == "Interact" then
			for _, target in (objective.targets or {}) :: { string } do
				if not (progress :: QuestRules.Progress).Found[target] then
					wanted[target] = true
				end
			end
		end
	end
	return wanted
end

local function refreshObjects()
	local wanted = wantedTargets()
	for part, id in questParts do
		if part.Parent == nil then
			questParts[part] = nil
			continue
		end
		local on = wanted[id] == true
		part.Transparency = if on then 0.15 else 1
		local prompt = part:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.Enabled = on
		end
		local light = part:FindFirstChildOfClass("PointLight")
		if light then
			light.Enabled = on
		end
	end
end

local function watchPart(part: Instance)
	if part:IsA("BasePart") then
		local id = part:GetAttribute("RC_QuestTarget")
		if type(id) == "string" then
			questParts[part] = id
			refreshObjects()
		end
	end
end

local function ownGiver(): Model?
	for model in giverMarks do
		if model.Parent and model:GetAttribute("RC_QuestGiver") == state().Race then
			return model
		end
	end
	return nil
end

local function refreshGiverMarks()
	local all = questState()
	local offers = QuestRules.offers(all, state().Level)
	local ready = false
	for _, progress in all do
		ready = ready or progress.Status == "ReadyToTurnIn"
	end
	for model, mark in giverMarks do
		if model.Parent == nil then
			giverMarks[model] = nil
			continue
		end
		local own = model:GetAttribute("RC_QuestGiver") == state().Race
		local label = mark:FindFirstChildOfClass("TextLabel") :: TextLabel
		label.Text = if ready then "⭐" elseif #offers > 0 then "!" else ""
		mark.Enabled = own and label.Text ~= ""
	end
end

local function watchGiver(model: Instance)
	if not model:IsA("Model") or model:GetAttribute("RC_QuestGiver") == nil or giverMarks[model] then
		return
	end
	local head = model:FindFirstChild("Head")
	local mark = Instance.new("BillboardGui")
	mark.Name = "RC_QuestMark"
	mark.Size = UDim2.fromOffset(60, 60)
	mark.StudsOffset = Vector3.new(0, 3.4, 0)
	mark.AlwaysOnTop = true
	mark.MaxDistance = 140
	mark.Adornee = (if head and head:IsA("BasePart") then head else model.PrimaryPart) :: any
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.TextScaled = true
	label.FontFace = Theme.Fonts.DisplayHeavy
	label.TextColor3 = Theme.Colors.GoldBright
	label.TextStrokeTransparency = 0.2
	label.Parent = mark
	mark.Parent = gui
	giverMarks[model] = mark
	refreshGiverMarks()
end

-- Where the next step is, if the client can know it.
local function targetPosition(): Vector3?
	local data = state()
	local race = data.Race
	if race == nil then
		return nil
	end
	local quest, progress = pinned()
	local giver = ownGiver()
	local giverRoot = giver and giver:FindFirstChild("HumanoidRootPart")
	local giverAt = if giverRoot and giverRoot:IsA("BasePart") then giverRoot.Position else nil
	if quest == nil or progress == nil then
		return if #QuestRules.offers(questState(), data.Level) > 0 then giverAt else nil
	end
	if progress.Status == "ReadyToTurnIn" then
		return giverAt
	end
	local objective = QuestRules.current(quest, progress)
	if objective == nil then
		return nil
	end
	if objective.type == "Visit" and objective.place then
		local realm = WorldLayout.Realms[race]
		local place = objective.place
		if realm and place.kind == "yard" then
			local center = WorldLayout.trainingYard(realm)
			return Vector3.new(center[1], center[2], center[3])
		elseif realm and place.kind == "city" and place.at then
			local p = WorldLayout.toWorld(realm, place.at)
			return Vector3.new(p[1], p[2], p[3])
		end
	elseif objective.type == "Interact" then
		local character = localPlayer().Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local best, bestDistance = nil, math.huge
		local wanted = wantedTargets()
		for part, id in questParts do
			if wanted[id] and part.Parent then
				local d = if root and root:IsA("BasePart")
					then (part.Position - root.Position).Magnitude
					else 0
				if d < bestDistance then
					best, bestDistance = part.Position, d
				end
			end
		end
		return best
	end
	return nil
end

local function refreshMarker()
	markerTarget = targetPosition()
	local character = localPlayer().Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if markerTarget == nil or root == nil or not root:IsA("BasePart") then
		marker.Enabled = false
		return
	end
	local distance = (markerTarget - root.Position).Magnitude
	marker.Enabled = distance > 10
	markerAnchor.CFrame = CFrame.new(markerTarget + Vector3.new(0, 6, 0))
	markerLabel.Text = `◆\n{math.floor(distance)} m`
end

--------------------------------------------------------------------------------
-- Title plates
--------------------------------------------------------------------------------

local function plateFor(player: Player)
	local function apply()
		local character = player.Character
		local head = character and character:FindFirstChild("Head")
		local title = player:GetAttribute("Title")
		local existing = head and head:FindFirstChild("RC_TitlePlate")
		if type(title) ~= "string" or head == nil then
			if existing then
				existing:Destroy()
			end
			return
		end
		local plate = existing :: BillboardGui?
		if plate == nil then
			local made = Instance.new("BillboardGui")
			made.Name = "RC_TitlePlate"
			made.Size = UDim2.fromOffset(200, 22)
			made.StudsOffset = Vector3.new(0, 3.6, 0)
			made.MaxDistance = 60
			made.Adornee = head :: BasePart
			local label = Instance.new("TextLabel")
			label.BackgroundTransparency = 1
			label.Size = UDim2.fromScale(1, 1)
			label.TextSize = 14
			label.FontFace = Theme.Fonts.BodyBold
			label.TextColor3 = Theme.Colors.GoldBright
			label.TextStrokeTransparency = 0.3
			label.Parent = made
			made.Parent = head
			plate = made
		end
		local label = (plate :: BillboardGui):FindFirstChildOfClass("TextLabel")
		if label then
			label.Text = `« {title} »`
		end
	end
	player:GetAttributeChangedSignal("Title"):Connect(apply)
	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("Head", 10)
		apply()
	end)
	if player.Character then
		task.spawn(apply)
	end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

local function refreshAll()
	refreshTracker()
	refreshObjects()
	refreshGiverMarks()
	if panelMode == "log" then
		renderPanel()
	end
end

function QuestController:Start()
	gui = Kit.new("ScreenGui", {
		Name = "RC_Quests",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		DisplayOrder = 7,
	})
	trackerButton = Kit.new("TextButton", {
		Name = "QuestTracker",
		BackgroundColor3 = Theme.Colors.Glass,
		BackgroundTransparency = 0.15,
		TextSize = 12,
		RichText = true,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.AtEnd,
		FontFace = Theme.Fonts.BodyBold,
		TextColor3 = Theme.Colors.Text,
		AutoButtonColor = true,
		Visible = false,
		Parent = gui,
	})
	Kit.corner(trackerButton, 12)
	Kit.goldStroke(trackerButton, 1.5, 0.2)
	Kit.padding(trackerButton, 4, 10)
	trackerButton.Activated:Connect(QuestController.toggleLog)
	HudLayout.register("Quest", trackerButton)
	HudLayout.Changed:Connect(refreshTracker)

	marker = Instance.new("BillboardGui")
	marker.Name = "RC_QuestMarker"
	marker.Size = UDim2.fromOffset(70, 40)
	marker.AlwaysOnTop = true
	marker.Enabled = false
	markerAnchor = Instance.new("Part")
	markerAnchor.Name = "RC_QuestMarkerAnchor"
	markerAnchor.Size = Vector3.new(0.2, 0.2, 0.2)
	markerAnchor.Transparency = 1
	markerAnchor.Anchored = true
	markerAnchor.CanCollide = false
	markerAnchor.CanQuery = false
	markerAnchor.CanTouch = false
	markerAnchor.Parent = Workspace.CurrentCamera or Workspace
	marker.Adornee = markerAnchor
	markerLabel = Instance.new("TextLabel")
	markerLabel.BackgroundTransparency = 1
	markerLabel.Size = UDim2.fromScale(1, 1)
	markerLabel.TextSize = 14
	markerLabel.FontFace = Theme.Fonts.BodyBold
	markerLabel.TextColor3 = Theme.Colors.GoldBright
	markerLabel.TextStrokeTransparency = 0.2
	markerLabel.Parent = marker
	marker.Parent = gui

	gui.Parent = localPlayer():WaitForChild("PlayerGui")
	Panels.register("quests", closePanel)

	for _, item in Workspace:GetDescendants() do
		watchPart(item)
		watchGiver(item)
	end
	Workspace.DescendantAdded:Connect(function(item)
		watchPart(item)
		if item:IsA("Model") then
			-- The giver's attribute is set after it is parented.
			task.defer(watchGiver, item)
		end
	end)

	PlayerDataController.Changed:Connect(function(_, reason)
		if reason == "quests" or reason == "snapshot" or reason == "progression" then
			refreshAll()
		end
	end)
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		refreshTracker()
		if panel then
			renderPanel()
		end
	end)
	NetClient.on("QuestDialogue", function(payload)
		if type(payload) ~= "table" then
			return
		end
		dialogue = payload
		panelMode = "dialogue"
		Panels.opened("quests")
		renderPanel()
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.J then
			QuestController.toggleLog()
		end
	end)
	-- Walking away from the giver closes the dialogue.
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < MARKER_SECONDS then
			return
		end
		elapsed = 0
		refreshMarker()
		if panelMode == "dialogue" then
			local giver = ownGiver()
			local character = localPlayer().Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local giverRoot = giver and giver:FindFirstChild("HumanoidRootPart")
			if
				root
				and giverRoot
				and root:IsA("BasePart")
				and giverRoot:IsA("BasePart")
				and (root.Position - giverRoot.Position).Magnitude > QuestDefinitions.GIVER_REACH + 6
			then
				closePanel()
			end
		end
	end)
	for _, player in Players:GetPlayers() do
		plateFor(player)
	end
	Players.PlayerAdded:Connect(plateFor)
	refreshAll()
end

return QuestController
