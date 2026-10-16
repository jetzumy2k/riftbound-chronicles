--!strict
--[[
	NotificationController — short, non-blocking toasts for server notices
	(CLAUDE.md §28: notifications must not block play).

	The server sends a text *key* (never player-written text); this controller
	maps keys to player-facing strings. Unknown keys are ignored.

	Toasts stack at the top centre inside the safe area, never take input,
	show an icon plus text (not colour alone) and fade after a few seconds.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DungeonDefinitions = require(Shared.Definitions.DungeonDefinitions)
local Log = require(Shared.Util.Log)
local NetClient = require(Shared.Net.Client)

local UI = script.Parent.Parent.UI
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)

local MAX_TOASTS = 2
local TOAST_SECONDS = 2.4
local MAX_WIDTH = 420

local STRINGS: { [string]: string } = {
	["system.welcome"] = "Welcome to Riftbound Chronicles",
	["race.invalidPreset"] = "That look isn't available for this realm.",
	["combat.blocked.safeZone"] = "You can't fight inside a safe zone. Step past the glowing ring.",
	["combat.blocked.protected"] = "That target is protected right now.",
	["combat.blocked.sameRace"] = "You can't attack your own realm.",
	["combat.blocked.outOfRange"] = "Too far away. Move closer.",
	["combat.blocked.lineOfSight"] = "No clear line of sight.",
	["combat.blocked.noTarget"] = "No target in range. Face an enemy or tap one.",
	["movement.noFocus"] = "Not enough Focus to sprint.",
	["dungeon.full"] = "Too many players for this dungeon.",
	["dungeon.level"] = "You need level {level} for this dungeon. Train on the Rift Sprites in the Training Grounds.",
	["dungeon.busy"] = "All dungeon instances are busy. Try again in a moment.",
	["dungeon.inRun"] = "You're already inside a dungeon.",
	["dungeon.disabled"] = "Dungeons are closed for maintenance right now.",
	["dungeon.leaderOnly"] = "Only your party leader can open the dungeon.",
	["dungeon.partyEntered"] = "{name} entered Rift Hollow. Use the dungeon gate to join them.",
	["dungeon.memberJoined"] = "{name} joined the run.",
	["dungeon.roomCleared"] = "Room cleared! The way forward is open.",
	["dungeon.respawnAlly"] = "Back on your feet beside your party.",
	["dungeon.wiped"] = "Your whole party fell. Regroup at the gate and try again.",
	["dungeon.cleared"] = "Dungeon cleared! +{xp} EXP",
	["dungeon.bossDefeated"] = "{name} defeated! +{xp} bonus EXP",
	["dungeon.bossReset"] = "The guardian recovers. Regroup and try again.",
	["pvp.entered"] = "You entered the {zone}. Players of the other realm can attack you outside the oasis.",
	["pvp.portal.inCombat"] = "You can't use a portal while in combat.",
	["pvp.portal.level"] = "War zones open at level {level}.",
	["pvp.victory"] = "Victory over {name}!",
	["pvp.enemyCamp"] = "That is the other realm's camp. You can't enter it.",
	["party.invite.sent"] = "Invite sent to {name}.",
	["party.invite.self"] = "You can't invite yourself.",
	["party.invite.unavailable"] = "That player can't join right now.",
	["party.invite.notLeader"] = "Only the party leader can invite.",
	["party.invite.otherRace"] = "You can only party with players of your realm.",
	["party.invite.targetInParty"] = "That player is already in a party.",
	["party.invite.full"] = "Your party is full.",
	["party.invite.alreadyInvited"] = "You already invited that player.",
	["party.invite.inDungeon"] = "You can't invite while the party is in a dungeon.",
	["party.invite.expired"] = "That invite has expired.",
	["party.invite.declined"] = "{name} declined your invite.",
	["party.joined"] = "{name} joined the party.",
	["party.nowLeader"] = "You are now the party leader.",
	["party.removed"] = "You were removed from the party.",
}

local ICONS: { [string]: string } = {
	Info = "✦",
	Welcome = "✦",
	Warning = "⚠",
}

local log = Log.new("Notification")

local bossAnnouncement: (key: string) -> string?
local withParams: (message: string, params: any) -> string

local NotificationController = {}

local container: Frame? = nil
local toasts: { Frame } = {}

local function build()
	local gui = Kit.new("ScreenGui", {
		Name = "RC_Toasts",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		DisplayOrder = 20,
	})
	-- A thin strip at the top centre, clear of the character in the middle of
	-- the screen; it grows downward only as far as its toasts need.
	local holder = Kit.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromScale(0.5, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = gui,
	})
	Kit.new(
		"UISizeConstraint",
		{ MinSize = Vector2.new(260, 0), MaxSize = Vector2.new(MAX_WIDTH, math.huge), Parent = holder }
	)
	local layout = Kit.list(holder, Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Center)
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")
	container = holder
end

local function dismiss(toast: Frame)
	local index = table.find(toasts, toast)
	if index then
		table.remove(toasts, index)
	end
	local text = toast:FindFirstChild("Text")
	Kit.tween(toast, Kit.Tween.Smooth, { BackgroundTransparency = 1 })
	if text and text:IsA("TextLabel") then
		Kit.tween(text, Kit.Tween.Smooth, { TextTransparency = 1 })
	end
	local stroke = toast:FindFirstChildOfClass("UIStroke")
	if stroke then
		Kit.tween(stroke, Kit.Tween.Smooth, { Transparency = 1 })
	end
	task.delay(0.3, function()
		toast:Destroy()
	end)
end

-- "boss.<id>.phase<n>" -> that phase's announcement (DungeonDefinitions).
function bossAnnouncement(key: string): string?
	local bossId, phase = string.match(key, "^boss%.(%w+)%.phase(%d+)$")
	local boss = DungeonDefinitions.boss(bossId)
	local def = boss and boss.phases[tonumber(phase) or 0]
	return if def then def.announce else nil
end

-- Fills "{name}" placeholders from server params (plain text, no markup).
function withParams(message: string, params: any): string
	if type(params) ~= "table" then
		return message
	end
	return (
		string.gsub(message, "{(%w+)}", function(name)
			local value = params[name]
			return if type(value) == "string" then value else "?"
		end)
	)
end

local function show(kind: string, message: string)
	local holder = container
	if holder == nil then
		return
	end
	-- Same message already visible: just keep it alive instead of stacking.
	for _, existing in toasts do
		local text = existing:FindFirstChild("Text")
		if text and text:IsA("TextLabel") and text.Text == `{ICONS[kind] or "✦"}  {message}` then
			return
		end
	end
	while #toasts >= MAX_TOASTS do
		dismiss(toasts[1])
	end

	local camera = Workspace.CurrentCamera
	local textSize = if camera and camera.ViewportSize.Y < 500 then 13 else 14
	local toast = Kit.new("Frame", {
		Name = "Toast",
		BackgroundColor3 = Theme.Colors.Glass,
		BackgroundTransparency = 0.25,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.fromScale(1, 0),
		Active = false,
		Parent = holder,
	})
	Kit.corner(toast, 12)
	Kit.padding(toast, 6, 12)
	Kit.new("UIStroke", {
		Color = if kind == "Warning" then Color3.fromRGB(255, 170, 90) else Theme.Colors.Gold,
		Thickness = 1.5,
		Transparency = 0.1,
		Parent = toast,
	})
	Kit.new("TextLabel", {
		Name = "Text",
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.fromScale(1, 0),
		Text = `{ICONS[kind] or "✦"}  {message}`,
		TextWrapped = true,
		TextSize = textSize,
		FontFace = Theme.Fonts.BodyBold,
		TextColor3 = Theme.Colors.Text,
		Parent = toast,
	})
	table.insert(toasts, toast)
	task.delay(TOAST_SECONDS, function()
		if toast.Parent then
			dismiss(toast)
		end
	end)
end

function NotificationController:Init()
	build()
	NetClient.on("Notify", function(payload)
		if type(payload) ~= "table" or type(payload.textKey) ~= "string" then
			return
		end
		local message = STRINGS[payload.textKey] or bossAnnouncement(payload.textKey)
		if message == nil then
			log:Debug("no text for key %s", payload.textKey)
			return
		end
		show(tostring(payload.kind), withParams(message, payload.params))
	end)
end

return NotificationController
