--!strict
--[[
	EventRewards — rewards an admin attaches to an event run (creator request
	2026-10-25, PLAN.md D-93 stage 2). Pure.

	A window (EventRules) may carry Rewards: up to MAX_ENTRIES of
	  { Kind = "MallPoints", Count = n }
	  { Kind = "Item", Id = <stackable>, Count = n }   buffs, potions,
	                                                   stones, Scroll of Rebirth
	  { Kind = "Set", Id = "Legendary" | "Mythical", Count = 1 }
	Only events that list reward groups take rewards (EventDefinitions
	`rewards`; boosts such as Double EXP don't: the boost is the reward),
	and only items of those groups. Who receives them depends on the event
	(`rewardTo`, RECIPIENTS): the players who did the event's thing
	(defeated its creatures, opened a chest, won, defended, paraded), once
	per run (claim "E:<event>:<start>:prize"), on top of its usual prizes.
]]

local ItemDefinitions = require(script.Parent.Parent.Definitions.ItemDefinitions)

local EventRewards = {}

export type Entry = { Kind: string, Id: string?, Count: number }

EventRewards.KINDS = table.freeze({ "MallPoints", "Item", "Set" })
EventRewards.MAX_ENTRIES = 4

-- Reward groups an event may allow, in panel order, with their items.
EventRewards.GROUP_ORDER = table.freeze({ "MallPoints", "Stones", "Buffs", "Sets" })
EventRewards.GROUP_NAMES = table.freeze({
	MallPoints = "💠 Mall Points",
	Stones = "💎 Stones",
	Buffs = "🧪 Buffs & potions",
	Sets = "🔶 Gear sets",
})
EventRewards.GROUP_ITEMS = table.freeze({
	Stones = table.freeze({ "EnhancementStone", "PerfectStone" }),
	Buffs = table.freeze({
		"Buff_Insight",
		"Buff_Fortune",
		"Buff_StoneSeeker",
		"Buff_Might",
		"Buff_Iron",
		"Buff_Vigor",
		"Buff_Clarity",
		"RebirthScroll",
		"HealingPotion",
	}),
})

-- Who gets an event's rewards, in words (EventDefinitions `rewardTo`).
EventRewards.RECIPIENTS = table.freeze({
	Fighters = "everyone who helps defeat one of the event's creatures or bosses",
	Finders = "everyone who opens at least one of the event's chests",
	RaceWinners = "every fighter of the winning realm",
	TopPlayer = "the tournament winner (1st place)",
	Defenders = "every defender who defeats at least one attacker",
	Parade = "everyone who completes the 5-minute parade",
})

-- The group an entry belongs to.
function EventRewards.groupOf(entry: Entry): string?
	if entry.Kind == "MallPoints" then
		return "MallPoints"
	elseif entry.Kind == "Set" then
		return "Sets"
	end
	for group, items in EventRewards.GROUP_ITEMS :: { [string]: { string } } do
		if table.find(items, entry.Id or "") then
			return group
		end
	end
	return nil
end
EventRewards.MAX_POINTS = 10000
EventRewards.MAX_ITEMS = 99
EventRewards.SET_RARITIES = table.freeze({ "Legendary", "Mythical" })

-- Stackables an event may give (not salvage fragments).
EventRewards.ITEMS = table.freeze({
	"Buff_Insight",
	"Buff_Fortune",
	"Buff_StoneSeeker",
	"Buff_Might",
	"Buff_Iron",
	"Buff_Vigor",
	"Buff_Clarity",
	"RebirthScroll",
	"HealingPotion",
	"EnhancementStone",
	"PerfectStone",
})

--[[
	Checks a reward list. Returns (true) or (false, reason): "shape",
	"kind", "item", "count", "set", "many".
]]
function EventRewards.validate(list: any, allowed: { string }?): (boolean, string?)
	if list == nil or (type(list) == "table" and #list == 0) then
		return true, nil
	end
	if allowed == nil then
		return false, "none"
	end
	if type(list) ~= "table" then
		return false, "shape"
	end
	if #list > EventRewards.MAX_ENTRIES then
		return false, "many"
	end
	for _, entry in list do
		if
			type(entry) ~= "table"
			or type(entry.Count) ~= "number"
			or entry.Count % 1 ~= 0
			or entry.Count < 1
		then
			return false, "count"
		end
		if entry.Kind == "MallPoints" then
			if entry.Count > EventRewards.MAX_POINTS then
				return false, "count"
			end
		elseif entry.Kind == "Item" then
			if table.find(EventRewards.ITEMS, entry.Id) == nil then
				return false, "item"
			end
			if entry.Count > EventRewards.MAX_ITEMS then
				return false, "count"
			end
		elseif entry.Kind == "Set" then
			if table.find(EventRewards.SET_RARITIES, entry.Id) == nil then
				return false, "set"
			end
			if entry.Count ~= 1 then
				return false, "count"
			end
		else
			return false, "kind"
		end
		if table.find(allowed, EventRewards.groupOf(entry) :: any) == nil then
			return false, "group"
		end
	end
	return true, nil
end

-- One entry in words: "500 Mall Points", "2 x Perfect Enhancement Stone".
function EventRewards.describeEntry(entry: Entry): string
	if entry.Kind == "MallPoints" then
		return `{entry.Count} Mall Points`
	elseif entry.Kind == "Set" then
		return `{entry.Id} Set`
	end
	local def = ItemDefinitions.stackable(entry.Id)
	return `{entry.Count} x {if def then def.name else tostring(entry.Id)}`
end

-- The whole list in words ("" when empty).
function EventRewards.describe(list: { Entry }?): string
	local parts = {}
	local entries: { Entry } = list or {}
	for _, entry in entries do
		table.insert(parts, EventRewards.describeEntry(entry))
	end
	return table.concat(parts, ", ")
end

-- Bag slots the rewards need (a set fills one per piece; `setSize` pieces).
function EventRewards.slotsNeeded(list: { Entry }?, setSize: number): number
	local need = 0
	local entries: { Entry } = list or {}
	for _, entry in entries do
		if entry.Kind == "Set" then
			need += setSize
		end
	end
	return need
end

return EventRewards
