--!strict
--[[
	NotificationController — short, non-blocking toasts for server notices
	(CLAUDE.md §28: notifications must not block play).

	The server sends a text *key* (never player-written text); this controller
	maps keys to player-facing strings. Unknown keys are ignored.

	Toasts stack at the top centre inside the safe area, never take input,
	show an icon plus text (not colour alone) and fade after a few seconds.

	One icon per toast (D-76 review): warnings always ❗; otherwise the
	key's own icon (KEY_ICONS) or its topic's (TOPIC_ICONS, by the key's
	first part: "quest.accepted" -> quest -> 📜). Message strings carry no
	icon of their own.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DungeonDefinitions = require(Shared.Definitions.DungeonDefinitions)
local Log = require(Shared.Util.Log)
local NetClient = require(Shared.Net.Client)
local OverlayLayout = require(Shared.Layout.OverlayLayout)

local UI = script.Parent.Parent.UI
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)

-- How many toasts at once (OverlayLayout: 1 on short screens, Phase 19).
local maxToasts = 2
local TOAST_SECONDS = 2.4
local MAX_WIDTH = 420

local STRINGS: { [string]: string } = {
	["system.welcome"] = "Welcome to Riftbound Chronicles",
	-- D-93 Item Mall and buffs.
	["mall.bought"] = "Bought: {name}",
	["mall.points"] = "{points} Mall Points added. Thank you!",
	["inventory.use.buff"] = "{name} is active",
	["inventory.use.noAttributes"] = "No attribute points spent yet",
	-- D-90 attribute points.
	["attributes.available"] = "{points} attribute points to spend: open 🌟 Skills, then 📊 Stats",
	["attributes.noPoints"] = "No attribute points left to spend",
	["attributes.nothingToReset"] = "No attribute points spent yet",
	["attributes.resetWait"] = "Free attribute reset ready in {hours} h",
	["attributes.reset"] = "Attribute points returned: spend them again",
	-- Phase 18 live events (D-89, EventController).
	["event.started"] = "Event started: {name}. {blurb}",
	["event.soon"] = "Event starting in {minutes} min: {name}. {blurb}",
	["event.ended"] = "Event ended: {name}",
	["event.worldBoss"] = "The Nullborn Herald has descended on both war zones!",
	["event.invasion"] = "Mythical bosses invade the war zones!",
	["event.reward"] = "Event reward: {gold} Gold, {stones} Enhancement Stone(s)",
	["event.prize"] = "Event reward: {rewards}",
	["event.prizeRoom"] = "Make room in your bag to receive your event reward",
	["event.chestFound"] = "Chest opened: {found} of {total} found",
	["event.chestOpened"] = "You already opened this chest",
	["event.wave"] = "Defend the training yard! Wave {wave} of {waves}",
	["event.running"] = "Event running: {name} ({left} left)",
	-- Phase 11 quests (D-73).
	["quest.accepted"] = "New quest: {name}",
	["quest.ready"] = "{name}: done! Return to your commander.",
	["quest.complete"] = "Quest complete: {name}",
	["quest.found"] = "Found: {name}",
	["quest.title"] = "New title: « {title} ». Wear it from the quest log (J).",
	["quest.token"] = "Rift token: +1 skill point. Open your skills (K).",
	["quest.level"] = "You need level {level} for that quest.",
	["quest.locked.dungeon"] = 'Finish the quest "First Spark" to open the Rift Dungeons.',
	["quest.locked.enhance"] = 'Finish the quest "Into the Rift" to unlock enhancement.',
	["quest.locked.portal"] = 'Finish the quest "The Broken Gate" to open the war-zone gates.',
	["race.invalidPreset"] = "That look isn't available for this realm.",
	["combat.blocked.safeZone"] = "You can't fight inside a safe zone. Step past the glowing ring.",
	["combat.blocked.protected"] = "That target is protected right now.",
	["combat.blocked.sameRace"] = "You can't attack your own realm.",
	["combat.blocked.outOfRange"] = "Too far away. Move closer.",
	["combat.blocked.lineOfSight"] = "No clear line of sight.",
	["combat.blocked.noTarget"] = "No target in range. Face an enemy or tap one.",
	["movement.noFocus"] = "Not enough Focus to sprint.",
	["skill.cooldown"] = "That skill isn't ready yet.",
	["skill.noFocus"] = "Not enough Focus for that skill.",
	["skill.stunned"] = "You can't act while stunned or frozen!",
	["skill.silenced"] = "You're silenced: no skills for a moment.",
	["skill.notEquipped"] = "Put that skill on your skill bar first (skill tree, K).",
	["skill.notLearned"] = "Learn that skill in your skill tree first (K).",
	["skill.learn.locked"] = "You can learn that skill at level {level}.",
	["skill.learn.requires"] = "Learn {name} first.",
	["skill.learn.noPoints"] = "No skill points left. You earn 3 every level.",
	["skill.learn.maxRank"] = "That skill is already at its highest rank.",
	["skill.learn.rankLocked"] = "Rank {rank} opens at level {level}.",
	["skill.learn.unlocked"] = "+{points} skill point! New skill unlocked: {names}. Open your skill tree (K).",
	["skill.learn.rankOpen"] = "Your skills can now reach rank {rank}!",
	["skill.learn.learned"] = "Learned {name}! It's on your skill bar if a slot was free.",
	["skill.learn.ranked"] = "{name} is now rank {rank}.",
	["skill.learn.firstPoint"] = "You have a skill point! Press K or tap 🌟 SKILLS to learn your first skill.",
	["skill.learn.newPoints"] = "+{points} skill point! Open your skill tree (K) to spend it.",
	["skill.reset.safeZone"] = "Reset your skill tree inside a safe zone, out of combat.",
	["skill.reset.done"] = "Skill tree reset: every point is back.",
	["skill.reset.nothing"] = "No skill points spent yet.",
	["skill.reset.combat"] = "Leave combat before resetting your skills.",
	["skill.reset.needScroll"] = "Free skill reset is off: you need a Scroll of Relearning (Item Mall).",
	["attributes.needScroll"] = "Free attribute reset is off: you need a Scroll of Rebirth (Item Mall).",
	["skill.notAlly"] = "That skill only works on players of your realm.",
	["skill.loadoutInvalid"] = "That skill can't go in that slot.",
	["skill.auto.none"] = "No creature nearby to attack.",
	["combat.autoHunt.on"] = "Auto-attack ON: you'll fight creatures nearby. Move to take over; tap AUTO again to stop.",
	["combat.autoHunt.off"] = "Auto-attack OFF.",
	["combat.autoHunt.disabled"] = "Auto-attack is switched off in this game right now.",
	-- Phase 7 inventory (D-64).
	["inventory.full"] = "Your bag is full ({cap} items). Salvage something to make room.",
	["inventory.notOwned"] = "That item isn't in your bag.",
	["inventory.inCombat"] = "You can't change gear in combat.",
	["inventory.equip.job"] = "That gear belongs to another class.",
	["inventory.equip.race"] = "Your realm doesn't use that weapon.",
	["inventory.equip.level"] = "You need level {level} to wear that.",
	["inventory.salvage.equipped"] = "Take it off before salvaging it.",
	["inventory.salvage.locked"] = "That item is locked. Unlock it to salvage it.",
	["inventory.salvage.full"] = "You can't carry more Stone Fragments.",
	["inventory.salvaged"] = "Salvaged {count} item(s): +{fragments} Stone Fragments.",
	["inventory.combine.notEnough"] = "You need {need} Stone Fragments.",
	["inventory.combine.full"] = "You can't carry more Enhancement Stones.",
	["inventory.combined"] = "+{count} Enhancement Stone(s).",
	["inventory.use.none"] = "You have no {name} left.",
	["inventory.use.cooldown"] = "Ready again in {seconds} s.",
	["inventory.use.fullHp"] = "Your health is already full.",
	["inventory.testGear"] = "Studio: {count} test items added to your bag.",
	-- Equipment overhaul (D-68).
	["inventory.equip.slot"] = "That piece can't go in that slot.",
	["inventory.equip.dualNeedsSword"] = "Dual swords: equip a short sword in your main hand first.",
	["inventory.equip.swapped"] = "Moved back to your bag to make room: {slots}.",
	-- Phase 10 loot (D-67).
	["loot.drop"] = "Loot: {name} ({rarity}, item level {level}). Open your bag (B).",
	["loot.stone"] = "Loot: an Enhancement Stone.",
	["loot.perfectStone"] = "Loot: a Perfect Enhancement Stone!",
	["loot.stoneFull"] = "Your {stone} stack is full: the stone was lost. Use some first.",
	["loot.bagFull"] = "Your bag is full: the {rarity} {name} was lost. Salvage something to make room.",
	-- Phase 8 enhancement (D-66).
	["enhance.success"] = "Enhancement succeeded: +{level}!",
	["enhance.failed"] = "Enhancement failed: the item stays +{level}, one stone used.",
	["enhance.max"] = "That item is already +10.",
	["enhance.noStone"] = "You don't have that stone.",
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
	["character.switching"] = "Saving and switching character...",
	["staff.paid"] = "Staff pay received: {what}. Thank you for helping!",
	["staff.payBag"] = "Your staff pay includes a gear set: free {slots} bag slots to receive it.",
	["staff.paused"] = "Your staff pay is paused after a long absence. Ask the Owner or an Admin to turn it back on.",
	["system.reset"] = "The game world is being reset. You will be asked to rejoin in {seconds} seconds.",
	["dungeon.respawnEntrance"] = "Back on your feet at this floor's entrance.",
	["dungeon.wiped"] = "Your whole party fell. Regroup at the gate and try again.",
	["dungeon.cleared"] = "Dungeon cleared! +{xp} EXP",
	["dungeon.bossDefeated"] = "{name} defeated! +{xp} bonus EXP",
	["dungeon.bossReset"] = "The guardian recovers. Regroup and try again.",
	["boss.enraged"] = "{name} is ENRAGED! Its blows are deadly now.",
	["dungeon.floor"] = "Floor {floor}: {name} (creatures level {levels}).",
	["dungeon.noFloor"] = "There's no floor in that direction.",
	["pvp.guardWarning"] = "Camp guardians strike intruders: turn back from the enemy camp!",
	["pvp.entered"] = "You entered the {zone}. Players of the other realm can attack you outside the oasis.",
	["pvp.portal.inCombat"] = "You can't use a portal while in combat.",
	["pvp.portal.level"] = "War zones open at level {level}.",
	["pvp.victory"] = "Victory over {name}!",
	["pvp.marks"] = "+{amount} PvP Marks.",
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
	["union.invite.noParty"] = "Form a party first: unions join whole parties.",
	["union.invite.notLeader"] = "Only your party leader can invite another party.",
	["union.invite.notUnionLeader"] = "Only the union leader can invite more parties.",
	["union.invite.self"] = "That player is already in your party.",
	["union.invite.targetNotLeader"] = "Invite the other party's leader.",
	["union.invite.otherRace"] = "Unions are for parties of your own realm.",
	["union.invite.targetInUnion"] = "That party is already in a union.",
	["union.invite.full"] = "Your union is full (4 parties).",
	["union.invite.alreadyInvited"] = "You already invited that party.",
	["union.invite.unavailable"] = "That union invite can't be accepted right now.",
	["union.invite.sent"] = "Union invite sent to {name}'s party.",
	["union.invite.declined"] = "{name} declined your union invite.",
	["union.invite.expired"] = "That union invite has expired.",
	["union.joined"] = "{name}'s party joined the union!",
	["union.partyLeft"] = "{name}'s party left the union.",
	["union.dissolved"] = "Your union has disbanded.",
	["union.removed"] = "Your party was removed from the union.",
	["party.invite.expired"] = "That invite has expired.",
	["party.invite.declined"] = "{name} declined your invite.",
	["party.joined"] = "{name} joined the party.",
	["party.nowLeader"] = "You are now the party leader.",
	["party.removed"] = "You were removed from the party.",
}

-- Warnings always show the warning icon.
local WARNING_ICON = "❗"
-- Icon by topic (the text key's first part); unknown topics get the bell.
local TOPIC_ICONS: { [string]: string } = {
	quest = "📜",
	loot = "🎁",
	enhance = "💎",
	inventory = "🎒",
	skill = "🌟",
	combat = "💥",
	dungeon = "🏰",
	boss = "🐉",
	party = "👥",
	union = "🤝",
	pvp = "🏆",
	race = "👤",
	movement = "🏃",
	system = "🔧",
	event = "🎉",
	attributes = "📊",
	mall = "🛒",
}
-- Keys whose meaning has a better icon than their topic's.
local KEY_ICONS: { [string]: string } = {
	["quest.ready"] = "⭐",
	["quest.complete"] = "✅",
	["quest.found"] = "🔎",
	["quest.title"] = "🏅",
	["loot.stone"] = "💎",
	["loot.perfectStone"] = "💎",
	["pvp.marks"] = "🏅",
	["pvp.entered"] = "🗡",
	["pvp.guardWarning"] = "🛡️",
}
local DEFAULT_ICON = "🔔"

local function iconFor(kind: string, key: string): string
	if kind == "Warning" then
		return WARNING_ICON
	end
	return KEY_ICONS[key] or TOPIC_ICONS[string.match(key, "^(%w+)") or ""] or DEFAULT_ICON
end

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
	-- A strip placed by OverlayLayout (Phase 19, D-94): in a free spot near
	-- the top, clear of the quest tracker, the chips and every button; it
	-- grows downward only as far as its toasts need.
	local holder = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.fromOffset(MAX_WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = gui,
	})
	local function fit()
		local size = gui.AbsoluteSize
		if size.X < 10 then
			return
		end
		local layout = OverlayLayout.compute(size.X, size.Y)
		holder.Position = UDim2.fromOffset(layout.toasts.x, layout.toasts.y)
		holder.Size = UDim2.fromOffset(layout.toasts.w, 0)
		maxToasts = layout.maxToasts
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	task.defer(fit)
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

local function show(kind: string, key: string, message: string)
	local holder = container
	local line = `{iconFor(kind, key)}  {message}`
	if holder == nil then
		return
	end
	-- Same message already visible: just keep it alive instead of stacking.
	for _, existing in toasts do
		local text = existing:FindFirstChild("Text")
		if text and text:IsA("TextLabel") and text.Text == line then
			return
		end
	end
	while #toasts >= maxToasts do
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
		Text = line,
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

-- A toast from client-side prediction (e.g. a skill button pressed too early).
function NotificationController:ShowKey(kind: string, textKey: string, params: { [string]: string }?)
	local message = STRINGS[textKey]
	if message then
		show(kind, textKey, withParams(message, params))
	end
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
		show(tostring(payload.kind), payload.textKey, withParams(message, payload.params))
	end)
end

return NotificationController
