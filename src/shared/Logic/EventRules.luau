--!strict
--[[
	EventRules — which live events are running and what they change
	(Phase 18, PLAN.md D-89; PLAN.md §5 "event stacking rules"). Pure.

	Windows: every running or scheduled event is a window
	{ Id, StartsAt, EndsAt, By } in UTC os.time() seconds, kept in the
	config section Events.Windows (D-12): every server reads the same list,
	so a server that starts mid-event sees it running without a message.

	Stacking: events add up per category, then the category is capped:
	  boost   (XP, drops, healing...) total = 1 + sum(m - 1), at most `cap`
	  reduce  (cooldowns, respawn delays) total = 1 - sum(1 - m), at least
	          `floor`
	Loot rarity weights are scaled and then re-normalized to 100.

	Ending an event changes nothing already earned: these only scale a
	reward at the moment it is granted.
]]

local EventDefinitions = require(script.Parent.Parent.Definitions.EventDefinitions)
local WorldLayout = require(script.Parent.Parent.Definitions.WorldLayout)

local EventRules = {}

export type Window = { Id: string, StartsAt: number, EndsAt: number, By: number }
export type Context = { zone: string?, race: string?, job: string?, level: number? }

-- mode: "boost" or "reduce".
type Category = { mode: string, cap: number?, floor: number? }

local CATEGORIES: { [string]: Category } = {
	-- EXP from creatures; quests; dungeon boss / class bonuses.
	XP = table.freeze({ mode = "boost", cap = 3 }),
	QuestXP = table.freeze({ mode = "boost", cap = 3 }),
	BossXP = table.freeze({ mode = "boost", cap = 3 }),
	-- Gear drop chance; rarity weights (re-normalized).
	DropChance = table.freeze({ mode = "boost", cap = 3 }),
	RareWeight = table.freeze({ mode = "boost", cap = 3 }),
	LegendaryWeight = table.freeze({ mode = "boost", cap = 3 }),
	MythicalWeight = table.freeze({ mode = "boost", cap = 3 }),
	-- War-zone stones: drop chance, the Perfect Stone's weight.
	StoneChance = table.freeze({ mode = "boost", cap = 3 }),
	PerfectWeight = table.freeze({ mode = "boost", cap = 3 }),
	Healing = table.freeze({ mode = "boost", cap = 2 }),
	Marks = table.freeze({ mode = "boost", cap = 3 }),
	-- Attribute value rolls on new gear (best of N).
	AttributeRolls = table.freeze({ mode = "boost", cap = 3 }),
	TrainingCooldown = table.freeze({ mode = "reduce", floor = 0.1 }),
	BossRespawn = table.freeze({ mode = "reduce", floor = 0.25 }),
}
EventRules.CATEGORIES = table.freeze(CATEGORIES)

-- The war zones' own zones.
local WAR_ZONES = { Desert = true, Jungle = true }

-- Longest window an admin can set, and how far ahead one can be scheduled.
EventRules.MAX_WINDOWS = 40
EventRules.MAX_AHEAD_SECONDS = 30 * 24 * 3600

-- War zone ids -> event zone names.
local ZONE_OF_WAR_ZONE = { DesertRift = "Desert", JungleRift = "Jungle" }

--[[
	The event zone at world point (x, z): Dungeon, Desert, Jungle, Training
	(a capital's training yard), Capitals, or nil (anywhere else).
]]
function EventRules.zoneAt(x: number, z: number): string?
	if WorldLayout.isInDungeonRegion(x) then
		return "Dungeon"
	end
	local war = WorldLayout.warZoneAt(x, z)
	if war then
		return ZONE_OF_WAR_ZONE[war.id]
	end
	for _, realm in WorldLayout.Realms :: { [string]: any } do
		local center, size = WorldLayout.trainingYard(realm)
		if math.abs(x - center[1]) <= size[1] / 2 and math.abs(z - center[3]) <= size[3] / 2 then
			return "Training"
		end
		local c, s = realm.platformCenter, realm.platformSize
		if math.abs(x - c[1]) <= s[1] / 2 and math.abs(z - c[3]) <= s[3] / 2 then
			return "Capitals"
		end
	end
	return nil
end

--[[
	The windows running at `now` (StartsAt <= now < EndsAt), one per event
	id (the latest-ending one when windows overlap), unknown ids dropped.
]]
function EventRules.active(windows: { Window }, now: number): { Window }
	local byId: { [string]: Window } = {}
	for _, w in windows do
		if EventDefinitions.get(w.Id) and w.StartsAt <= now and now < w.EndsAt then
			local existing = byId[w.Id]
			if existing == nil or w.EndsAt > existing.EndsAt then
				byId[w.Id] = w
			end
		end
	end
	local out = {}
	for _, id in EventDefinitions.IDS do
		if byId[id] then
			table.insert(out, byId[id])
		end
	end
	return out
end

-- Whether event `e` applies in `ctx` (its zone and who is eligible).
function EventRules.applies(e: EventDefinitions.Event, ctx: Context): boolean
	local zone = e.zone
	if zone ~= "All" then
		local here = ctx.zone
		if here == nil then
			return false
		end
		if zone == "WarZones" then
			if not WAR_ZONES[here] then
				return false
			end
		elseif zone ~= here then
			return false
		end
	end
	local eligible = e.eligible
	if eligible then
		if eligible.race and eligible.race ~= ctx.race then
			return false
		end
		if eligible.job and eligible.job ~= ctx.job then
			return false
		end
		if eligible.minLevel and (ctx.level or 0) < eligible.minLevel then
			return false
		end
	end
	return true
end

--[[
	The combined multiplier of `category` from the running windows that
	apply in `ctx` (1 when none). Unknown categories are 1.
]]
function EventRules.factor(category: string, running: { Window }, ctx: Context): number
	local spec = EventRules.CATEGORIES[category]
	if spec == nil then
		return 1
	end
	local sum = 0
	for _, w in running do
		local e = EventDefinitions.get(w.Id)
		local m = e and e.modifiers[category]
		if e and m and EventRules.applies(e, ctx) then
			sum += if spec.mode == "boost" then m - 1 else 1 - m
		end
	end
	if spec.mode == "boost" then
		return math.min(1 + math.max(sum, 0), spec.cap or math.huge)
	end
	return math.max(1 - math.max(sum, 0), spec.floor or 0)
end

-- `amount` EXP scaled by `factor`, rounded, never less than `amount`.
function EventRules.scaleXp(amount: number, factor: number): number
	return math.max(amount, math.floor(amount * factor + 0.5))
end

local WEIGHT_CATEGORY = { Rare = "RareWeight", Legendary = "LegendaryWeight", Mythical = "MythicalWeight" }

--[[
	A loot table (LootRules shape) with the running events applied: the
	drop chance times DropChance (at most 100), each rarity's weight times
	its category, then the weights re-normalized to 100. Returns the table
	itself when nothing changes.
]]
function EventRules.lootTable(t: any, running: { Window }, ctx: Context): any
	local chance = EventRules.factor("DropChance", running, ctx)
	local scaled: { [string]: number } = {}
	local changed = chance ~= 1
	local total = 0
	for rarity, weight in t.Rarity do
		local category = WEIGHT_CATEGORY[rarity]
		local f = if category then EventRules.factor(category, running, ctx) else 1
		if f ~= 1 then
			changed = true
		end
		scaled[rarity] = weight * f
		total += weight * f
	end
	if not changed or total <= 0 then
		return t
	end
	for rarity, weight in scaled do
		scaled[rarity] = weight / total * 100
	end
	return { DropChancePct = math.min(100, t.DropChancePct * chance), Rarity = scaled }
end

-- A stone table with StoneChance and PerfectWeight applied (re-normalized).
function EventRules.stoneTable(t: any, running: { Window }, ctx: Context): any
	local chance = EventRules.factor("StoneChance", running, ctx)
	local perfect = EventRules.factor("PerfectWeight", running, ctx)
	if chance == 1 and perfect == 1 then
		return t
	end
	local scaled: { [string]: number } = {}
	local total = 0
	for stone, weight in t.Stones do
		local w = if stone == "PerfectStone" then weight * perfect else weight
		scaled[stone] = w
		total += w
	end
	if total > 0 then
		for stone, weight in scaled do
			scaled[stone] = weight / total * 100
		end
	end
	return { DropChancePct = math.min(100, t.DropChancePct * chance), Stones = scaled }
end

--[[
	Checks a new window for event `id` from `startsAt` lasting `minutes`
	against the template and the stored windows (cooldown: the gap since
	the same event's last window ended, or before its next one starts).
	Returns (true) or (false, reason): unknown, notReady, duration, past,
	ahead, running, cooldown, full.
]]
function EventRules.canSchedule(
	windows: { Window },
	id: string,
	startsAt: number,
	minutes: number,
	now: number
): (boolean, string?)
	local e = EventDefinitions.get(id)
	if e == nil then
		return false, "unknown"
	end
	if not EventDefinitions.isReady(e) then
		return false, "notReady"
	end
	if minutes % 1 ~= 0 or minutes < 1 or minutes > e.maxMinutes then
		return false, "duration"
	end
	if startsAt < now - 60 then
		return false, "past"
	end
	if startsAt > now + EventRules.MAX_AHEAD_SECONDS then
		return false, "ahead"
	end
	local endsAt = startsAt + minutes * 60
	local gap = e.cooldownMinutes * 60
	local live = 0
	for _, w in windows do
		if w.EndsAt > now then
			live += 1
		end
		if w.Id == id then
			if startsAt < w.EndsAt and w.StartsAt < endsAt then
				return false, "running"
			end
			if startsAt < w.EndsAt + gap and w.StartsAt < endsAt + gap then
				return false, "cooldown"
			end
		end
	end
	if live >= EventRules.MAX_WINDOWS then
		return false, "full"
	end
	return true, nil
end

--[[
	The stored list after a change: windows that ended over a day ago are
	pruned (kept a day so cooldowns still see them).
]]
function EventRules.prune(windows: { Window }, now: number): { Window }
	local out = {}
	for _, w in windows do
		if w.EndsAt > now - 24 * 3600 then
			table.insert(out, w)
		end
	end
	return out
end

return EventRules
