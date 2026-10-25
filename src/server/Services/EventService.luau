--!strict
--[[
	EventService (Layer 1) — live events (CLAUDE.md §23, Phase 18, PLAN.md
	D-89).

	Every running or scheduled event is a window in config Events.Windows
	(Logic/EventRules, D-12): saved and pushed to every server by
	ConfigurationService:Write, and each server works out from os.time()
	which are running, so a server that starts mid-event sees it running
	and a scheduled event starts everywhere at the same second.

	Once a second the running list is refreshed and mirrored to clients as
	the ReplicatedStorage attribute RC_Events (JSON [{Id, EndsAt}], display
	only: EventController announces starts and ends and shows the HUD
	chips). Reward code asks this service for multipliers at the moment a
	reward is earned (`Factor`, `ScaleXp`, `LootTable`, `StoneTable`), so
	an event ending never touches anything already earned.

	Starting, scheduling and stopping are staff actions (AdminService,
	permission events.activate), audited there; this service checks the
	template rules (ready stage, duration, cooldown, overlap).
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local EventRules = require(Shared.Logic.EventRules)
local Log = require(Shared.Util.Log)
local Signal = require(Shared.Util.Signal)

local ConfigurationService = require(script.Parent.ConfigurationService)
local PlayerDataService = require(script.Parent.PlayerDataService)

local log = Log.new("EventService")

local ATTRIBUTE = "RC_Events"

local EventService = {
	-- Fired with (running windows) when the running set changes.
	Changed = Signal.new(),
}

local running: { EventRules.Window } = {}
local signature = ""

local function windows(): { EventRules.Window }
	local list = ConfigurationService:Get("Events.Windows")
	return if type(list) == "table" then list else {}
end

local function refresh()
	running = EventRules.active(windows(), os.time())
	local view = {}
	for _, w in running do
		table.insert(view, { Id = w.Id, EndsAt = w.EndsAt })
	end
	local encoded = HttpService:JSONEncode(view)
	if encoded ~= signature then
		signature = encoded
		ReplicatedStorage:SetAttribute(ATTRIBUTE, encoded)
		log:Info("running events: %s", encoded)
		EventService.Changed:Fire(running)
	end
end

-- The running windows (copy).
function EventService:GetRunning(): { EventRules.Window }
	return table.clone(running)
end

-- Every stored window (running, scheduled and recently ended).
function EventService:GetWindows(): { EventRules.Window }
	return table.clone(windows())
end

-- The event zone the player stands in (EventRules.zoneAt), or nil.
local function zoneOf(player: Player): string?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return EventRules.zoneAt(root.Position.X, root.Position.Z)
	end
	return nil
end

-- The player's event context: zone (where they stand unless given), race,
-- job, level.
local function contextFor(player: Player?, zone: string?): EventRules.Context
	if player == nil then
		return { zone = zone }
	end
	local data = PlayerDataService:GetData(player)
	return {
		zone = zone or zoneOf(player),
		race = data and data.Race,
		job = data and data.Job,
		level = data and data.Level,
	}
end

local function factor(category: string, player: Player?, zone: string?): number
	if #running == 0 then
		return 1
	end
	return EventRules.factor(category, running, contextFor(player, zone))
end

function EventService:ZoneOf(player: Player): string?
	return zoneOf(player)
end

-- The combined multiplier of `category` for `player` (1 when no event).
function EventService:Factor(category: string, player: Player?, zone: string?): number
	return factor(category, player, zone)
end

--[[
	EXP for `player` from `source` (LevelService:GrantXP sources): quests
	use QuestXP, dungeon boss / class bonuses BossXP, everything else XP.
]]
function EventService:ScaleXp(player: Player, amount: number, source: string): number
	if #running == 0 then
		return amount
	end
	local category = if string.sub(source, 1, 6) == "Quest:"
		then "QuestXP"
		elseif string.sub(source, 1, 5) == "Boss:" then "BossXP"
		else "XP"
	return EventRules.scaleXp(amount, factor(category, player))
end

-- Loot table `t` with the running events applied for `player`.
function EventService:LootTable(t: any, player: Player): any
	if #running == 0 then
		return t
	end
	return EventRules.lootTable(t, running, contextFor(player))
end

function EventService:StoneTable(t: any, player: Player): any
	if #running == 0 then
		return t
	end
	return EventRules.stoneTable(t, running, contextFor(player))
end

-- Saves `list` as Events.Windows (other override values kept).
local function save(list: { EventRules.Window }, actorUserId: number): (boolean, string?)
	local values = table.clone(ConfigurationService:GetOverrideValues())
	local events = table.clone(values.Events or {})
	events.Windows = list
	values.Events = events
	local ok, reason = ConfigurationService:Write(values, ConfigurationService:GetVersion(), actorUserId)
	if ok then
		refresh()
	end
	return ok == true, reason
end

--[[
	Adds a window for event `id` from `startsAt` (UTC seconds; now or later)
	lasting `minutes`. Returns (ok, reason, window).
]]
function EventService:Schedule(
	id: string,
	startsAt: number,
	minutes: number,
	actorUserId: number
): (boolean, string?, EventRules.Window?)
	local now = os.time()
	local list = EventRules.prune(windows(), now)
	local ok, reason = EventRules.canSchedule(list, id, startsAt, minutes, now)
	if not ok then
		return false, reason, nil
	end
	local window = {
		Id = id,
		StartsAt = math.max(startsAt, now),
		EndsAt = math.max(startsAt, now) + minutes * 60,
		By = actorUserId,
	}
	table.insert(list, window)
	local saved, why = save(list, actorUserId)
	if not saved then
		return false, why, nil
	end
	return true, nil, window
end

--[[
	Ends event `id` now (a running window ends; scheduled ones are removed).
	Returns (ok, reason).
]]
function EventService:Stop(id: string, actorUserId: number): (boolean, string?)
	local now = os.time()
	local list = EventRules.prune(windows(), now)
	local out = {}
	local found = false
	for _, w in list do
		if w.Id == id and w.EndsAt > now then
			found = true
			if w.StartsAt <= now then
				table.insert(out, { Id = w.Id, StartsAt = w.StartsAt, EndsAt = now, By = w.By })
			end
		else
			table.insert(out, w)
		end
	end
	if not found then
		return false, "notRunning"
	end
	return save(out, actorUserId)
end

function EventService:Init()
	ReplicatedStorage:SetAttribute(ATTRIBUTE, "[]")
end

function EventService:Start()
	refresh()
	ConfigurationService.Changed:Connect(refresh)
	task.spawn(function()
		while true do
			task.wait(1)
			xpcall(refresh, function(err)
				log:Error("refresh failed: %s", tostring(err))
			end)
		end
	end)
end

return EventService
