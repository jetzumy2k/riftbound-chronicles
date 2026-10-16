--!strict
--[[
	PvPRules — pure rules for race-vs-race PvP (PLAN.md D-16, SECURITY_MODEL
	T-15, T-17, T-18).

	  normalizedLevel  D-16: attacking a lower-level player, you fight at
	                   min(ownLevel, opponentLevel + gap)
	  creditVictory    T-18 anti-farming: no victory credit for the same
	                   victim again within the repeat window, for victims far
	                   below your level, or past the daily cap
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
	repeatWindowSeconds: number,
	creditsToday: number,
	dailyCap: number,
}

function PvPRules.creditVictory(f: CreditFacts): (boolean, string?)
	if f.victimLevel < f.attackerLevel - f.levelGap then
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

-- UTC day number for the daily credit counter.
function PvPRules.day(unixTime: number): number
	return math.floor(unixTime / 86400)
end

return table.freeze(PvPRules)
