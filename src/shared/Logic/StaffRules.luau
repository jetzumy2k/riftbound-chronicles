--!strict
--[[
	StaffRules — panel-assigned staff and their pay (creator decisions
	2026-10-27, PLAN.md D-112). Pure module.

	Roles assigned in the panel (the Owner and Admins listed in
	server/Config/Roles stay code-only):

	  Moderator   support and moderation
	  GameMaster  the standard Game Master: moderation plus running the
	              world (events, bosses), full player inspection, granting
	              items and fixing stuck quests

	Each staff member's features are switched on or off one by one, but
	never past their role's CEILING. Economy settings, drop rates, data
	editing, item removal, roles and the system reset are never on it
	(CLAUDE.md §21).

	Assigning someone, or changing their features, takes effect at once when
	the Owner does it. When an Admin does it, it waits for the Owner's
	approval. Removing staff or pausing pay is immediate for both.

	Salary: Mall Points, consumables and/or a gear set, Weekly or Monthly.
	Paid once per period on the first check after it starts (on join, then
	every few minutes while online). Missed periods are not paid back. After
	INACTIVE_DAYS without joining, the pay pauses until the Owner or an
	Admin turns it back on.
]]

local StaffRules = {}

StaffRules.ROLES = table.freeze({ "Moderator", "GameMaster" })
StaffRules.ROLE_NAMES = table.freeze({ Moderator = "Moderator", GameMaster = "Game Master" })

-- Every feature a panel role may have, in display order.
StaffRules.CEILING = table.freeze({
	Moderator = table.freeze({
		"panel.open",
		"player.inspect",
		"moderation.kick",
		"moderation.ban",
		"events.activate",
		"audit.view",
	}),
	GameMaster = table.freeze({
		"panel.open",
		"player.inspect",
		"player.inspectFull",
		"moderation.kick",
		"moderation.ban",
		"events.activate",
		"bosses.manage",
		"items.grant",
		"quests.manage",
		"audit.view",
	}),
})

-- Switched on when someone is first assigned.
StaffRules.DEFAULTS = table.freeze({
	Moderator = table.freeze({ "panel.open", "player.inspect", "moderation.kick", "audit.view" }),
	GameMaster = StaffRules.CEILING.GameMaster,
})

StaffRules.FEATURE_NAMES = table.freeze({
	["panel.open"] = "Open the panel",
	["player.inspect"] = "Find and inspect players",
	["player.inspectFull"] = "See wallets and bags",
	["moderation.kick"] = "Kick",
	["moderation.ban"] = "Ban",
	["events.activate"] = "Start / stop events",
	["bosses.manage"] = "Respawn bosses",
	["items.grant"] = "Give items",
	["quests.manage"] = "Fix stuck quests",
	["audit.view"] = "See their own log",
})

StaffRules.PERIODS = table.freeze({ "Weekly", "Monthly" })
StaffRules.INACTIVE_DAYS = 30
StaffRules.MAX_SALARY_POINTS = 10000
StaffRules.MAX_SALARY_ITEMS = 4
StaffRules.MAX_ITEM_COUNT = 99
StaffRules.SET_RARITIES = table.freeze({ "Rare", "Epic", "Legendary" })
StaffRules.MAX_STAFF = 50

export type Item = { id: string, count: number }
export type Salary = {
	enabled: boolean,
	period: string,
	mallPoints: number,
	items: { Item },
	setRarity: string?,
}
export type Pending = { role: string?, perms: { string }?, by: number, at: number }
export type Record = {
	role: string,
	perms: { string },
	status: string, -- "Active" | "Pending" (assignment waits for the Owner)
	assignedBy: number,
	approvedBy: number?,
	at: number,
	salary: Salary,
	pending: Pending?, -- an Admin's change to an active record
	lastSeen: number,
}

function StaffRules.isRole(role: any): boolean
	return type(role) == "string" and StaffRules.CEILING[role] ~= nil
end

-- Only the features `role` may have, in ceiling order; "panel.open" is
-- always on (nothing works without it).
function StaffRules.clampPerms(role: string, perms: any): { string }
	local ceiling = StaffRules.CEILING[role]
	if ceiling == nil then
		return {}
	end
	local wanted: { [string]: boolean } = { ["panel.open"] = true }
	if type(perms) == "table" then
		for _, p in perms do
			if type(p) == "string" then
				wanted[p] = true
			end
		end
	end
	local out = {}
	for _, p in ceiling do
		if wanted[p] then
			table.insert(out, p)
		end
	end
	return out
end

function StaffRules.allows(record: Record?, permission: string): boolean
	return record ~= nil
		and record.status == "Active"
		and table.find(StaffRules.clampPerms(record.role, record.perms), permission) ~= nil
end

function StaffRules.emptySalary(): Salary
	return { enabled = false, period = "Monthly", mallPoints = 0, items = {}, setRarity = nil }
end

-- A salary with every value in range; `isStackable(id)` says which item
-- ids are real consumables.
function StaffRules.cleanSalary(raw: any, isStackable: (string) -> boolean): Salary
	local out = StaffRules.emptySalary()
	if type(raw) ~= "table" then
		return out
	end
	out.enabled = raw.enabled == true
	out.period = if table.find(StaffRules.PERIODS, raw.period) then raw.period else "Monthly"
	local points = tonumber(raw.mallPoints) or 0
	out.mallPoints = math.clamp(math.floor(points), 0, StaffRules.MAX_SALARY_POINTS)
	if type(raw.items) == "table" then
		for _, item in raw.items do
			if #out.items >= StaffRules.MAX_SALARY_ITEMS then
				break
			end
			if type(item) == "table" and type(item.id) == "string" and isStackable(item.id) then
				local count = math.clamp(math.floor(tonumber(item.count) or 0), 0, StaffRules.MAX_ITEM_COUNT)
				if count > 0 then
					table.insert(out.items, { id = item.id, count = count })
				end
			end
		end
	end
	out.setRarity = if table.find(StaffRules.SET_RARITIES, raw.setRarity) then raw.setRarity else nil
	return out
end

function StaffRules.hasPay(salary: Salary): boolean
	return salary.mallPoints > 0 or #salary.items > 0 or salary.setRarity ~= nil
end

-- Monday 1970-01-05 00:00 UTC: weeks start on Mondays.
local FIRST_MONDAY = 4 * 86400

--[[
	The pay period `t` (UTC seconds) falls in, as a stable key:
	"W<week number>" or "M<year>-<month>".
]]
function StaffRules.periodKey(period: string, t: number): string
	if period == "Weekly" then
		return `W{(t - FIRST_MONDAY) // (7 * 86400)}`
	end
	local date = os.date("!*t", t) :: any
	return string.format("M%04d-%02d", date.year, date.month)
end

-- The reward-claim id that stops a period being paid twice.
function StaffRules.claimId(period: string, t: number): string
	return `S:{StaffRules.periodKey(period, t)}`
end

-- True when the pay should pause: away INACTIVE_DAYS or more.
function StaffRules.inactive(lastSeen: number, now: number): boolean
	return lastSeen > 0 and now - lastSeen >= StaffRules.INACTIVE_DAYS * 86400
end

--[[
	Who may do what to the staff list. `actorRole` is the actor's code role
	("Owner" / "Admin"). Returns "now", "approval" or nil (refused).
]]
function StaffRules.decide(actorRole: string?, action: string): string?
	if actorRole == "Owner" then
		return "now"
	elseif actorRole == "Admin" then
		if action == "Assign" or action == "SetPerms" then
			return "approval"
		elseif action == "Remove" or action == "SetSalary" or action == "List" then
			return "now"
		end
	end
	return nil
end

return table.freeze(StaffRules)
