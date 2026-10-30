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

	D-113: the daily random event. When Events.Daily is on, at its time
	each day one ticked event that the usual rules allow is drawn at random
	and started like any other window (marked Daily, By = 0). Every server
	checks; the config's version check lets only one write win, and the
	others then see the day's window and stop. A server that only comes up
	after the grace period skips that day.

	Starting, scheduling and stopping are staff actions (AdminService,
	permission events.activate), audited there; this service checks the
	template rules (ready stage, duration, cooldown, overlap).
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local EventRules = require(Shared.Logic.EventRules)
local TowerRules = require(Shared.Logic.TowerRules)
local EventRewards = require(Shared.Logic.EventRewards)
local EventDefinitions = require(Shared.Definitions.EventDefinitions)
local BuffRules = require(Shared.Logic.BuffRules)
local Log = require(Shared.Util.Log)
local Signal = require(Shared.Util.Signal)

local ConfigurationService = require(script.Parent.ConfigurationService)
local AuditLogService = require(script.Parent.AuditLogService)
local PlayerDataService = require(script.Parent.PlayerDataService)

local log = Log.new("EventService")

local ATTRIBUTE = "RC_Events"
-- D-114: events starting within 15 minutes (JSON [{Id, StartsAt}]).
local SOON_ATTRIBUTE = "RC_EventsSoon"

local EventService = {
	-- Fired with (running windows) when the running set changes.
	Changed = Signal.new(),
}

local running: { EventRules.Window } = {}
local signature = ""
local soonSignature = ""

local function windows(): { EventRules.Window }
	local list = ConfigurationService:Get("Events.Windows")
	return if type(list) == "table" then list else {}
end

local function refresh()
	-- D-114: what starts soon, for the "starting in 15 minutes" notice.
	local soon = {}
	for _, w in EventRules.soon(windows(), os.time()) do
		table.insert(soon, { Id = w.Id, StartsAt = w.StartsAt })
	end
	local soonEncoded = HttpService:JSONEncode(soon)
	if soonEncoded ~= soonSignature then
		soonSignature = soonEncoded
		ReplicatedStorage:SetAttribute(SOON_ATTRIBUTE, soonEncoded)
	end
	running = EventRules.active(windows(), os.time())
	local view = {}
	for _, w in running do
		table.insert(view, { Id = w.Id, EndsAt = w.EndsAt, Rewards = w.Rewards })
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
	-- D-93: the player's Mall buffs add to the same categories (and caps).
	local data = if player then PlayerDataService:GetData(player) else nil
	local extra = if data then BuffRules.rewardBonus(data.Buffs, category, os.time()) else 0
	if #running == 0 and extra == 0 then
		return 1
	end
	return EventRules.factor(category, running, contextFor(player, zone), extra)
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
	local category = if string.sub(source, 1, 6) == "Quest:"
		then "QuestXP"
		elseif string.sub(source, 1, 5) == "Boss:" then "BossXP"
		else "XP"
	return EventRules.scaleXp(amount, factor(category, player))
end

-- Loot table `t` with the running events applied for `player`.
-- The player's Mall buffs as a pseudo-window for loot (D-93).
local function withBuffs(player: Player): { EventRules.Window }
	local data = PlayerDataService:GetData(player)
	local buffs: { string } = if data then BuffRules.active(data.Buffs, os.time()) else {}
	if #buffs == 0 then
		return running
	end
	local list = table.clone(running)
	for _, id in buffs do
		table.insert(list, { Id = `Buff:{id}`, StartsAt = 0, EndsAt = math.huge, By = 0 })
	end
	return list
end

function EventService:LootTable(t: any, player: Player): any
	local list = withBuffs(player)
	if #list == 0 then
		return t
	end
	return EventRules.lootTable(t, list, contextFor(player))
end

function EventService:StoneTable(t: any, player: Player): any
	local list = withBuffs(player)
	if #list == 0 then
		return t
	end
	return EventRules.stoneTable(t, list, contextFor(player))
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
	actorUserId: number,
	rewards: { any }?,
	daily: boolean?
): (boolean, string?, EventRules.Window?)
	local now = os.time()
	local list = EventRules.prune(windows(), now)
	local ok, reason = EventRules.canSchedule(list, id, startsAt, minutes, now)
	if not ok then
		return false, reason, nil
	end
	local def = EventDefinitions.get(id)
	local valid, problem = EventRewards.validate(rewards, def and def.rewards)
	if not valid then
		return false, `rewards:{problem}`, nil
	end
	local window = {
		Id = id,
		StartsAt = math.max(startsAt, now),
		EndsAt = math.max(startsAt, now) + minutes * 60,
		By = actorUserId,
		Rewards = if rewards and #rewards > 0 then rewards else nil,
		Daily = if daily then true else nil,
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
				local ended = table.clone(w)
				ended.EndsAt = now
				table.insert(out, ended)
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

-- The daily random event settings.
function EventService:GetDaily(): EventRules.Daily
	return ConfigurationService:Get("Events.Daily")
end

--[[
	Saves the daily random event settings (AdminService checks the
	permission and audits). `excluded` ids must be real events.
]]
function EventService:SetDaily(daily: EventRules.Daily, actorUserId: number): (boolean, string?)
	local excluded = {}
	for _, id in daily.Excluded do
		if EventDefinitions.get(id) and not table.find(excluded, id) then
			table.insert(excluded, id)
		end
	end
	local values = table.clone(ConfigurationService:GetOverrideValues())
	local events = table.clone(values.Events or {})
	events.Daily = {
		Enabled = daily.Enabled == true,
		TimeUtcMinutes = math.clamp(math.floor(daily.TimeUtcMinutes), 0, 1439),
		Minutes = math.clamp(math.floor(daily.Minutes), 15, 1440),
		Excluded = excluded,
	}
	values.Events = events
	local ok, reason = ConfigurationService:Write(values, ConfigurationService:GetVersion(), actorUserId)
	return ok == true, reason
end

-- D-131: the Tower Challenge schedule (TowerRules.Schedule).
function EventService:GetTower(): TowerRules.Schedule
	return ConfigurationService:Get("Events.Tower")
end

--[[
	Saves the Tower schedule (AdminService checks the permission and
	audits): 1-3 weekdays, a UTC time and 1-12 hours.
]]
function EventService:SetTower(tower: TowerRules.Schedule, actorUserId: number): (boolean, string?)
	local days = TowerRules.cleanDays(tower.Days)
	if #days == 0 then
		return false, "towerDays"
	end
	local values = table.clone(ConfigurationService:GetOverrideValues())
	local events = table.clone(values.Events or {})
	events.Tower = {
		Enabled = tower.Enabled == true,
		Days = days,
		TimeUtcMinutes = math.clamp(math.floor(tower.TimeUtcMinutes), 0, 1439),
		Hours = math.clamp(math.floor(tower.Hours), 1, 12),
	}
	values.Events = events
	local ok, reason = ConfigurationService:Write(values, ConfigurationService:GetVersion(), actorUserId)
	return ok == true, reason
end

-- Starts today's daily event if it is due (one server's write wins).
local function dailyCheck()
	local daily = EventService:GetDaily()
	local now = os.time()
	local list = EventRules.prune(windows(), now)
	local at = EventRules.dailyDue(list, daily, now)
	if at == nil then
		return
	end
	-- Drawn up to 15 minutes ahead (D-114) so everyone is told first.
	local startsAt = math.max(at, now)
	local candidates = EventRules.dailyCandidates(list, daily, startsAt, now)
	if #candidates == 0 then
		log:Info("daily event: nothing ticked can run today")
		return
	end
	local id = candidates[Random.new():NextInteger(1, #candidates)]
	local ok, reason, window =
		EventService:Schedule(id, startsAt, EventRules.dailyMinutes(daily, id), 0, nil, true)
	if ok and window then
		AuditLogService:Audit({
			actorUserId = 0,
			action = "DailyEvent",
			target = id,
			details = { startsAt = window.StartsAt, endsAt = window.EndsAt },
		})
		log:Info("daily event %s started until %d", id, window.EndsAt)
	else
		-- Usually another server won the write; the next check sees it.
		log:Info("daily event %s not started here (%s)", id, tostring(reason))
	end
end

function EventService:Init()
	ReplicatedStorage:SetAttribute(ATTRIBUTE, "[]")
	ReplicatedStorage:SetAttribute(SOON_ATTRIBUTE, "[]")
end

function EventService:Start()
	refresh()
	ConfigurationService.Changed:Connect(refresh)
	task.spawn(function()
		local tick = 0
		while true do
			task.wait(1)
			xpcall(refresh, function(err)
				log:Error("refresh failed: %s", tostring(err))
			end)
			tick += 1
			-- D-113: servers check at different seconds, so writes rarely clash.
			if tick % 20 == 0 then
				xpcall(dailyCheck, function(err)
					log:Error("daily event check failed: %s", tostring(err))
				end)
			end
		end
	end)
end

return EventService
