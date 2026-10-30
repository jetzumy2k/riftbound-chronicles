--!strict
--[[
	HudController — the status row in Roblox's top bar (PLAN.md D-98;
	creator review 2026-10-26: the HUD panels took the left side of the view
	while the top strip stood empty).

	Lives in ScreenInsets.TopbarSafeInsets (the part of Roblox's top bar not
	used by Roblox's own buttons), placed by Layout/TopBarLayout:
	  Level    medallion with the level, the EXP bar with "4 / 100 XP"
	  Vitals   the HP bar with its numbers (shield, resting), Focus under it
	  Zone     🛡 SAFE ZONE / 🗡 WAR ZONE, and PROTECTED while spawn
	           protection lasts (icons only on phones)
	Each piece explains itself in a tooltip (UI/Tooltip). Text and bar fill
	together, never colour alone. Display only: values come from the server
	(PlayerDataController, character attributes, SafeZone / WarZone).
	The events chip, 📐 Edit HUD and 🛠 Admin share the row (their own
	controllers place them from the same layout).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local LevelCap = require(Shared.Logic.LevelCap)
-- D-129: forward declaration (defined beside render).
local liveCap: () -> number
local TopBarLayout = require(Shared.Layout.TopBarLayout)

local UI = script.Parent.Parent.UI
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)
local HudLayout = require(UI.HudLayout)
local Tooltip = require(UI.Tooltip)

local PlayerDataController = require(script.Parent.PlayerDataController)

local HudController = {}

local gui: ScreenGui
local levelPanel: Frame
local vitalsPanel: Frame
local zonePill: Frame
local zoneText: TextLabel
local levelText: TextLabel
local xpText: TextLabel
local fill: Frame
local hpFill: Frame
local hpText: TextLabel
local focusFill: Frame
local compact = false
local characterConnections: { RBXScriptConnection } = {}
local lastLevel = -1

local function formatNumber(n: number): string
	local text = tostring(math.floor(n))
	local formatted = string.reverse((string.gsub(string.reverse(text), "(%d%d%d)", "%1,")))
	return (string.gsub(formatted, "^,", ""))
end

local function localPlayer(): Player
	return Players.LocalPlayer :: Player
end

local function bar(parent: Instance, height: number, y: number, radius: number): (Frame, Frame)
	local track = Kit.new("Frame", {
		BackgroundColor3 = Theme.Colors.Ink,
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.fromOffset(0, y),
		Size = UDim2.new(1, 0, 0, height),
		Parent = parent,
	})
	Kit.corner(track, radius)
	local inner = Kit.new("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		Size = UDim2.fromScale(0, 1),
		Parent = track,
	})
	Kit.corner(inner, radius)
	return track, inner
end

local function build()
	gui = Kit.new("ScreenGui", {
		Name = "RC_TopBar",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.TopbarSafeInsets,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 4,
	})

	-- Level and EXP.
	levelPanel = Kit.glassPanel({ Name = "Level", Parent = gui }, 12)
	local medallion = Kit.new("Frame", {
		Name = "Medallion",
		BackgroundColor3 = Theme.Colors.Ink,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 3, 0.5, 0),
		Size = UDim2.fromOffset(32, 32),
		Parent = levelPanel,
	})
	Kit.corner(medallion, 20)
	Kit.goldStroke(medallion, 1.5)
	levelText = Kit.new("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = "0",
		TextScaled = true,
		FontFace = Theme.Fonts.Display,
		TextColor3 = Theme.Colors.GoldBright,
		Parent = medallion,
	})
	Kit.new("UIPadding", {
		PaddingTop = UDim.new(0.18, 0),
		PaddingBottom = UDim.new(0.18, 0),
		Parent = levelText,
	})
	local xpArea = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Name = "Exp",
		Parent = levelPanel,
	})
	local track
	track, fill = bar(xpArea, 18, 0, 6)
	track.AnchorPoint = Vector2.new(0, 0.5)
	track.Position = UDim2.fromScale(0, 0.5)
	Kit.new("UIStroke", { Color = Theme.Colors.GoldDeep, Thickness = 1, Transparency = 0.3, Parent = track })
	Kit.new("UIGradient", { Color = Theme.GoldSequence, Parent = fill })
	xpText = Kit.new("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = "",
		TextSize = 12,
		FontFace = Theme.Fonts.BodyBold,
		TextColor3 = Theme.Colors.Text,
		TextStrokeTransparency = 0.35,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 3,
		Parent = track,
	})
	Tooltip.attach(levelPanel, function()
		local s = PlayerDataController:Get()
		if s.Level >= liveCap() then
			return `Level {s.Level} (max)`, "You've reached the top level."
		end
		return `Level {s.Level}`,
			`{formatNumber(s.Experience)} / {formatNumber(s.XPToNext)} EXP to level {s.Level + 1}. Defeat creatures and finish quests to earn EXP.`
	end)

	-- HP and Focus.
	vitalsPanel = Kit.glassPanel({ Name = "Vitals", Parent = gui }, 12)
	Kit.padding(vitalsPanel, 4, 6)
	local hpTrack
	hpTrack, hpFill = bar(vitalsPanel, 0, 0, 6)
	hpTrack.Size = UDim2.new(1, 0, 1, -8)
	Kit.new("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(196, 40, 52), Color3.fromRGB(255, 120, 90)),
		Parent = hpFill,
	})
	hpText = Kit.new("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = "",
		TextSize = 12,
		FontFace = Theme.Fonts.BodyBold,
		TextColor3 = Theme.Colors.Text,
		TextStrokeTransparency = 0.35,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 3,
		Parent = hpTrack,
	})
	local focusTrack
	focusTrack, focusFill = bar(vitalsPanel, 5, 0, 3)
	focusTrack.AnchorPoint = Vector2.new(0, 1)
	focusTrack.Position = UDim2.fromScale(0, 1)
	focusFill.BackgroundColor3 = Color3.fromRGB(110, 190, 255)
	Tooltip.attach(vitalsPanel, function()
		local character = localPlayer().Character
		local hp = character and character:GetAttribute("HP")
		local maxHp = character and character:GetAttribute("MaxHP")
		local focus = character and character:GetAttribute("Focus")
		local maxFocus = character and character:GetAttribute("MaxFocus")
		return "HP and Focus",
			`HP {formatNumber(tonumber(hp) or 0)} / {formatNumber(tonumber(maxHp) or 0)} (red bar). Focus {formatNumber(
				tonumber(focus) or 0
			)} / {formatNumber(tonumber(maxFocus) or 100)} (blue bar): skills and sprinting spend it, it refills by itself.`
	end)

	-- Zone badge.
	zonePill = Kit.glassPanel({ Name = "Zone", Visible = false, Parent = gui }, 12)
	zoneText = Kit.new("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = "",
		TextSize = 13,
		FontFace = Theme.Fonts.BodyBold,
		TextColor3 = Theme.Colors.Safe,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = zonePill,
	})
	Tooltip.attach(zonePill, function()
		local player = localPlayer()
		local character = player.Character
		local protected = character ~= nil and character:GetAttribute("Protected") == true
		local lines = {}
		if player:GetAttribute("SafeZone") ~= nil then
			table.insert(lines, "Safe zone: no player can hurt you here, and you can't attack players.")
		elseif player:GetAttribute("WarZone") ~= nil then
			table.insert(lines, "War zone: players of the other realm can fight you here.")
		end
		if protected then
			table.insert(lines, "Protected: you can't be hurt for a few seconds; attacking ends it.")
		end
		return "Where you are", table.concat(lines, "\n")
	end)

	gui.Parent = localPlayer():WaitForChild("PlayerGui")
end

local function rect(object: GuiObject, r: TopBarLayout.Rect)
	object.Position = UDim2.fromOffset(r.x, r.y)
	object.Size = UDim2.fromOffset(r.w, r.h)
end

local renderZone: () -> ()
local renderVitals: (Model?) -> ()
local render: (PlayerDataController.State) -> ()

local function place()
	local size = gui.AbsoluteSize
	if size.X < 10 then
		return
	end
	local layout = TopBarLayout.compute(size.X, size.Y, localPlayer():GetAttribute("RC_IsStaff") == true)
	compact = layout.compact
	rect(levelPanel, layout.level)
	rect(vitalsPanel, layout.vitals)
	rect(zonePill, layout.zone)
	local xpArea = levelPanel:FindFirstChild("Exp") :: Frame
	local medallion = layout.level.h - 6
	(levelPanel:FindFirstChild("Medallion") :: Frame).Size = UDim2.fromOffset(medallion, medallion)
	xpArea.Position = UDim2.fromOffset(medallion + 9, 0)
	xpArea.Size = UDim2.new(1, -(medallion + 15), 1, 0)
	xpText.TextSize = if compact then 11 else 12
	hpText.TextSize = if compact then 11 else 12
	renderZone()
	-- The numbers' form follows `compact`.
	renderVitals(localPlayer().Character)
	render(PlayerDataController:Get())
end

function renderVitals(character: Model?)
	local hp = if character then character:GetAttribute("HP") else nil
	local maxHp = if character then character:GetAttribute("MaxHP") else nil
	local focus = if character then character:GetAttribute("Focus") else nil
	if type(hp) ~= "number" or type(maxHp) ~= "number" or maxHp <= 0 then
		hpText.Text = ""
		hpFill.Size = UDim2.fromScale(0, 1)
		focusFill.Size = UDim2.fromScale(0, 1)
		renderZone()
		return
	end
	local shield = if character then character:GetAttribute("Shield") else nil
	local resting = character ~= nil and character:GetAttribute("Resting") == true and hp < maxHp
	-- Phones: just the numbers (the bar is short); the tooltip has the rest.
	hpText.Text = (
		if compact
			then `{formatNumber(hp)}/{formatNumber(maxHp)}`
			else `HP {formatNumber(hp)} / {formatNumber(maxHp)}`
	)
		.. (if type(shield) == "number" and shield > 0 then ` +{formatNumber(shield)}🛡` else "")
		.. (if resting and not compact then " · resting" else "")
	Kit.tween(hpFill, Kit.Tween.Quick, { Size = UDim2.fromScale(math.clamp(hp / maxHp, 0, 1), 1) })
	if type(focus) == "number" then
		-- Max Focus grows with Wisdom (D-90).
		local maxFocus = if character then character:GetAttribute("MaxFocus") else nil
		local cap = if type(maxFocus) == "number" and maxFocus > 0 then maxFocus else 100
		focusFill.Size = UDim2.fromScale(math.clamp(focus / cap, 0, 1), 1)
	end
	renderZone()
end

function renderZone()
	local player = localPlayer()
	local character = player.Character
	local safe = player:GetAttribute("SafeZone") ~= nil
	local war = not safe and player:GetAttribute("WarZone") ~= nil
	local protected = character ~= nil and character:GetAttribute("Protected") == true
	zonePill.Visible = safe or war or protected
	if compact then
		zoneText.Text = if safe then "🛡" elseif war then "🗡" else "✨"
		zoneText.TextSize = 18
	else
		zoneText.Text = (if safe then "🛡 SAFE ZONE" elseif war then "🗡 WAR ZONE" else "✨ PROTECTED")
			.. (if protected and (safe or war) then " ✨" else "")
		zoneText.TextSize = 13
	end
	zoneText.TextColor3 = if war then Color3.fromRGB(255, 190, 170) else Theme.Colors.Safe
end

local function bindCharacter(character: Model?)
	for _, connection in characterConnections do
		connection:Disconnect()
	end
	table.clear(characterConnections)
	renderVitals(character)
	if character then
		for _, name in { "HP", "MaxHP", "Focus", "MaxFocus", "Protected", "Shield", "Resting" } do
			table.insert(
				characterConnections,
				character:GetAttributeChangedSignal(name):Connect(function()
					renderVitals(character)
				end)
			)
		end
	end
end

-- D-129: the live level cap the server mirrors (30, or 60 with the switch).
function liveCap(): number
	local cap = ReplicatedStorage:GetAttribute(LevelCap.ATTRIBUTE)
	return if type(cap) == "number" then cap else Constants.Level.Base
end

function render(state: PlayerDataController.State)
	levelText.Text = tostring(state.Level)
	local ratio
	if state.Level >= liveCap() then
		xpText.Text = "MAX LEVEL"
		ratio = 1
	elseif state.XPToNext > 0 then
		xpText.Text = if compact
			then `{formatNumber(state.Experience)}/{formatNumber(state.XPToNext)}`
			else `{formatNumber(state.Experience)} / {formatNumber(state.XPToNext)} XP`
		ratio = math.clamp(state.Experience / state.XPToNext, 0, 1)
	else
		ratio = 0
	end
	Kit.tween(fill, Kit.Tween.Smooth, { Size = UDim2.fromScale(ratio, 1) })
	if lastLevel >= 0 and state.Level > lastLevel then
		-- Level-up pulse on the medallion.
		local medallion = levelText.Parent :: GuiObject
		medallion.BackgroundColor3 = Theme.Colors.Gold
		Kit.tween(medallion, Kit.Tween.Smooth, { BackgroundColor3 = Theme.Colors.Ink })
	end
	lastLevel = state.Level
end

function HudController:Start()
	build()
	place()
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
	localPlayer():GetAttributeChangedSignal("RC_IsStaff"):Connect(place)
	-- The bars first: nothing below may keep HP and EXP from showing
	-- (creator report 2026-10-26: an error in the Edit HUD button's setup
	-- left both bars empty).
	local player = localPlayer()
	player.CharacterAdded:Connect(bindCharacter)
	bindCharacter(player.Character)
	player:GetAttributeChangedSignal("SafeZone"):Connect(renderZone)
	player:GetAttributeChangedSignal("WarZone"):Connect(renderZone)
	render(PlayerDataController:Get())
	PlayerDataController.Changed:Connect(function(state, reason)
		render(state)
		HudLayout.setEditVisible(state.Job ~= nil)
		if reason == "snapshot" then
			HudLayout.load(state.HudLayout)
		end
	end)

	-- D-74: the player can move the other HUD pieces (📐 opens the editor);
	-- the top bar itself stays put.
	HudLayout.start()
	HudLayout.setEditVisible(PlayerDataController:Get().Job ~= nil)
end

return HudController
