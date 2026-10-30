--!strict
--[[
	PvPRules — pure rules for race-vs-race PvP (PLAN.md D-16, SECURITY_MODEL
	T-15, T-17, T-18).

	  normalizedLevel  D-16: attacking a lower-level player, you fight at
	                   min(ownLevel, opponentLevel + gap)
	  creditVictory    T-18 / GD-10 anti-farming: no victory credit for a
	                   victim still protected or just out of spawn protection,
	                   for the same victim again within the repeat window, for
	                   victims far below your level, or past the daily cap
	  titlesFor        D-76: the victory titles a victory count has earned
	  nextTitle        the next victory title and how many victories it needs
	  canUsePortal     T-15: within reach of that portal, level requirement,
	                   not combat-tagged

	Pure module.
]]

local PvPRules = {}

function PvPRules.normalizedLevel(attackerLevel: number, targetLevel: number, gap: number): number
	return math.min(attackerLevel, targetLevel + gap)
end

export type CreditFacts = {
	attackerLevel: number,
	victimLevel: number,
	levelGap: number,
	-- Seconds since this attacker last got credit for this victim (nil = never).
	sinceLastCredit: number?,
	-- Seconds since the victim's spawn protection ended (negative = still
	-- protected; nil = never protected this life). Attacking ends it early.
	protectionEndedAgo: number?,
	freshSpawnSeconds: number,
	repeatWindowSeconds: number,
	creditsToday: number,
	dailyCap: number,
}

function PvPRules.creditVictory(f: CreditFacts): (boolean, string?)
	if f.protectionEndedAgo ~= nil and f.protectionEndedAgo < f.freshSpawnSeconds then
		return false, "protectedVictim"
	elseif f.victimLevel < f.attackerLevel - f.levelGap then
		return false, "victimTooLow"
	elseif f.sinceLastCredit ~= nil and f.sinceLastCredit < f.repeatWindowSeconds then
		return false, "repeatVictim"
	elseif f.creditsToday >= f.dailyCap then
		return false, "dailyCap"
	end
	return true, nil
end

export type PortalFacts = {
	distance: number,
	reach: number,
	level: number,
	minLevel: number,
	combatTagged: boolean,
	defeated: boolean,
}

function PvPRules.canUsePortal(f: PortalFacts): (boolean, string?)
	if f.defeated or f.distance > f.reach then
		return false, "reach"
	elseif f.combatTagged then
		return false, "inCombat"
	elseif f.level < f.minLevel then
		return false, "level"
	end
	return true, nil
end

--[[
	Titles earned by credited victories (CLAUDE.md §4 "PvP title based on
	kill counts", D-76). Only credited victories count, so the anti-farming
	rules above also guard the titles. Names in QuestDefinitions.Titles.

	D-134 (creator request 2026-10-31): three more tiers past 500, and
	from 150 victories each tier adds +1 % Attack (`attackPct`, not
	stacked: the highest reached counts), at most MAX_ATTACK_PCT. The bonus
	follows the current victory count; the titles, once earned, are kept.
]]
PvPRules.VICTORY_TITLES = table.freeze({
	table.freeze({ victories = 10, title = "Skirmisher", attackPct = 0 }),
	table.freeze({ victories = 50, title = "RiftVanguard", attackPct = 0 }),
	table.freeze({ victories = 150, title = "RiftChampion", attackPct = 1 }),
	table.freeze({ victories = 500, title = "TwinRealmLegend", attackPct = 2 }),
	table.freeze({ victories = 1000, title = "RiftWarlord", attackPct = 3 }),
	table.freeze({ victories = 2500, title = "RealmConqueror", attackPct = 4 }),
	table.freeze({ victories = 6000, title = "EternalWarbringer", attackPct = 5 }),
})
PvPRules.MAX_ATTACK_PCT = 5

-- The war bonus (+% Attack) for `victories`: the highest tier reached.
function PvPRules.attackPctFor(victories: number): number
	local pct = 0
	for _, entry in PvPRules.VICTORY_TITLES do
		if victories >= entry.victories then
			pct = math.max(pct, entry.attackPct)
		end
	end
	return math.min(pct, PvPRules.MAX_ATTACK_PCT)
end

-- Whether `id` is a victory title (auto-wear replaces only these).
function PvPRules.isVictoryTitle(id: string?): boolean
	for _, entry in PvPRules.VICTORY_TITLES do
		if entry.title == id then
			return true
		end
	end
	return false
end

function PvPRules.titlesFor(victories: number): { string }
	local titles = {}
	for _, entry in PvPRules.VICTORY_TITLES do
		if victories >= entry.victories then
			table.insert(titles, entry.title)
		end
	end
	return titles
end

-- The next title to earn and the victories it needs (nil when all are earned).
function PvPRules.nextTitle(victories: number): (string?, number?)
	for _, entry in PvPRules.VICTORY_TITLES do
		if victories < entry.victories then
			return entry.title, entry.victories
		end
	end
	return nil, nil
end

-- UTC day number for the daily credit counter.
function PvPRules.day(unixTime: number): number
	return math.floor(unixTime / 86400)
end

return table.freeze(PvPRules)
