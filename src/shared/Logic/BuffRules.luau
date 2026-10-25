--!strict
--[[
	BuffRules — temporary buffs from Mall consumables (creator request
	2026-10-25, PLAN.md D-93). Pure.

	Saved as Buffs = { [buffId] = expiresAt } (UTC seconds). Using another
	of the same buff adds its duration (up to MAX_SECONDS left). Buffs work
	everywhere, PvP included (creator decision 2026-10-25).

	  Reward buffs   XP, DropChance, StoneChance: added to the live events'
	                 categories (EventRules.factor) and capped with them
	  Stat buffs     MaxHPPct, DefensePct, DamagePct, FocusBonus: added to
	                 the character's stats (StatsService)
]]

local BuffRules = {}

export type Buff = {
	id: string,
	name: string,
	icon: string,
	minutes: number,
	-- Reward category (EventRules) -> multiplier, or a stat -> amount.
	category: string,
	amount: number,
	description: string,
}

BuffRules.MAX_SECONDS = 6 * 3600

local BUFFS: { [string]: Buff } = {
	Insight = {
		id = "Insight",
		name = "Scroll of Insight",
		icon = "📜",
		minutes = 60,
		category = "XP",
		amount = 1.5,
		description = "+50% EXP for 60 minutes.",
	},
	Fortune = {
		id = "Fortune",
		name = "Fortune Charm",
		icon = "🍀",
		minutes = 60,
		category = "DropChance",
		amount = 1.5,
		description = "Gear drops 50% more often for 60 minutes.",
	},
	StoneSeeker = {
		id = "StoneSeeker",
		name = "Stone Seeker's Lantern",
		icon = "🏮",
		minutes = 60,
		category = "StoneChance",
		amount = 1.5,
		description = "War-zone creatures drop stones 50% more often for 60 minutes.",
	},
	Might = {
		id = "Might",
		name = "Draught of Might",
		icon = "💪",
		minutes = 30,
		category = "DamagePct",
		amount = 10,
		description = "+10% damage for 30 minutes.",
	},
	Iron = {
		id = "Iron",
		name = "Draught of Iron",
		icon = "🛡️",
		minutes = 30,
		category = "DefensePct",
		amount = 10,
		description = "+10% Defense for 30 minutes.",
	},
	Vigor = {
		id = "Vigor",
		name = "Draught of Vigor",
		icon = "💗",
		minutes = 30,
		category = "MaxHPPct",
		amount = 10,
		description = "+10% Max HP for 30 minutes.",
	},
	Clarity = {
		id = "Clarity",
		name = "Draught of Clarity",
		icon = "🔷",
		minutes = 30,
		category = "FocusBonus",
		amount = 30,
		description = "+30 max Focus for 30 minutes.",
	},
}

for _, buff in BUFFS do
	table.freeze(buff)
end
BuffRules.Buffs = table.freeze(BUFFS)
BuffRules.IDS = table.freeze({ "Insight", "Fortune", "StoneSeeker", "Might", "Iron", "Vigor", "Clarity" })

function BuffRules.get(id: any): Buff?
	return if type(id) == "string" then BUFFS[id] else nil
end

--[[
	`buffs` after using one more of `id` at `now`: the time left grows by
	the buff's length, at most MAX_SECONDS from now. Returns the new
	expiry, or nil for an unknown buff.
]]
function BuffRules.extend(buffs: { [string]: number }, id: string, now: number): number?
	local buff = BUFFS[id]
	if buff == nil then
		return nil
	end
	local from = math.max(buffs[id] or 0, now)
	local expires = math.min(from + buff.minutes * 60, now + BuffRules.MAX_SECONDS)
	buffs[id] = expires
	return expires
end

-- Ids of the buffs still running at `now`.
function BuffRules.active(buffs: any, now: number): { string }
	local out = {}
	if type(buffs) ~= "table" then
		return out
	end
	for _, id in BuffRules.IDS do
		local expires = buffs[id]
		if type(expires) == "number" and expires > now then
			table.insert(out, id)
		end
	end
	return out
end

--[[
	The running buffs' share of a reward category (EventRules), as the sum
	of (multiplier - 1), to add to the events' sum before the cap.
]]
function BuffRules.rewardBonus(buffs: any, category: string, now: number): number
	local sum = 0
	for _, id in BuffRules.active(buffs, now) do
		local buff = BUFFS[id]
		if buff.category == category then
			sum += buff.amount - 1
		end
	end
	return sum
end

-- `stats` (may be frozen) with the running stat buffs added, as a new table.
function BuffRules.applyTo(stats: any, buffs: any, now: number): any
	local active = BuffRules.active(buffs, now)
	if #active == 0 then
		return stats
	end
	local out: any = table.clone(stats)
	for _, id in active do
		local buff = BUFFS[id]
		if buff.category == "MaxHPPct" then
			out.MaxHP = out.MaxHP * (1 + buff.amount / 100)
		elseif buff.category == "DefensePct" then
			out.Defense = out.Defense * (1 + buff.amount / 100)
		elseif buff.category == "DamagePct" then
			out.DamagePct = (out.DamagePct or 0) + buff.amount
		elseif buff.category == "FocusBonus" then
			out.FocusBonus = (out.FocusBonus or 0) + buff.amount
		end
	end
	return out
end

--[[
	A stored Buffs value made safe: known ids, whole expiry times; expired
	ones dropped. Returns (buffs, changed).
]]
function BuffRules.repair(value: any, now: number): ({ [string]: number }, boolean)
	local out: { [string]: number } = {}
	local changed = type(value) ~= "table"
	if type(value) == "table" then
		for id, expires in value do
			if BUFFS[id] == nil or type(expires) ~= "number" or expires % 1 ~= 0 then
				changed = true
			elseif expires > now then
				out[id] = math.min(expires, now + BuffRules.MAX_SECONDS)
			end
		end
	end
	return out, changed
end

return BuffRules
