--!strict
--[[
	StrikeRules — when rejected requests mean a tampered client (Phase 21,
	PLAN.md D-97; SECURITY_MODEL §4). Pure.

	The game's own client never sends a request that fails the schema
	(BadArgs / BadArity), calls a staff remote (NoPermission) or a remote
	with no handler (NoHandler): those come only from a modified client or
	an exploit tool. TAMPER_KICK_COUNT of them inside TAMPER_WINDOW_SECONDS
	kick the player (logged; no ban). Rate limits (RateLimited) and state
	checks (BadState, e.g. casting while defeated) are things a real player
	hits by tapping fast or lagging, so they never count.
]]

local StrikeRules = {}

StrikeRules.TAMPER_CODES = table.freeze({
	BadArgs = true,
	BadArity = true,
	NoPermission = true,
	NoHandler = true,
}) :: { [string]: boolean }

function StrikeRules.isTamper(code: string): boolean
	return StrikeRules.TAMPER_CODES[code] == true
end

--[[
	Adds a tamper strike at `now` to `times` (oldest first), drops the ones
	older than `window` seconds and returns whether the player should be
	kicked (`limit` or more inside the window).
]]
function StrikeRules.record(times: { number }, now: number, window: number, limit: number): boolean
	table.insert(times, now)
	while #times > 0 and times[1] <= now - window do
		table.remove(times, 1)
	end
	return #times >= limit
end

return StrikeRules
