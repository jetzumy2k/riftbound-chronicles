--!strict
--[[
	PerfBudget — the server's performance targets and the check behind the
	periodic report (Phase 23, PLAN.md D-102; PerfService).

	Targets for one server: 30 players, both realms' dungeons busy and both
	war zones active. Measured over each report window:
	  frame time     the server's Heartbeat step, average and 95th
	                 percentile (60 Hz = 16.7 ms)
	  memory         Stats:GetTotalMemoryUsageMb()
	  remote traffic events sent to / received from clients, per player
	                 per second
	  characters     parts in the largest player outfit
	Pure module, unit-tested (tests/pure/specs/perf_budget.spec.luau).
]]

export type Report = {
	players: number,
	frameAvgMs: number,
	frameP95Ms: number,
	memoryMb: number,
	outPerPlayerPerSecond: number,
	inPerPlayerPerSecond: number,
	characterParts: number,
}
export type Over = { field: string, value: number, limit: number }

local PerfBudget = {}

PerfBudget.TARGET_PLAYERS = 30

-- Upper limits; a report above any of them is logged as a warning.
PerfBudget.LIMITS = table.freeze({
	frameAvgMs = 18,
	frameP95Ms = 25,
	memoryMb = 2500,
	outPerPlayerPerSecond = 30,
	inPerPlayerPerSecond = 15,
	characterParts = 320,
})

-- The `p` percentile (0..1) of `samples` (nearest rank); 0 when empty.
function PerfBudget.percentile(samples: { number }, p: number): number
	local n = #samples
	if n == 0 then
		return 0
	end
	local sorted = table.clone(samples)
	table.sort(sorted)
	local rank = math.clamp(math.ceil(p * n), 1, n)
	return sorted[rank]
end

function PerfBudget.average(samples: { number }): number
	local n = #samples
	if n == 0 then
		return 0
	end
	local total = 0
	for _, value in samples do
		total += value
	end
	return total / n
end

-- Events per player per second over `seconds` (0 players / time = 0).
function PerfBudget.rate(events: number, players: number, seconds: number): number
	if players <= 0 or seconds <= 0 then
		return 0
	end
	return events / players / seconds
end

-- Every field over its limit, in a fixed order.
function PerfBudget.check(report: Report): { Over }
	local overs: { Over } = {}
	for _, field in
		{
			"frameAvgMs",
			"frameP95Ms",
			"memoryMb",
			"outPerPlayerPerSecond",
			"inPerPlayerPerSecond",
			"characterParts",
		}
	do
		local value = (report :: any)[field] :: number
		local limit = (PerfBudget.LIMITS :: any)[field] :: number
		if value > limit then
			table.insert(overs, { field = field, value = value, limit = limit })
		end
	end
	return overs
end

return PerfBudget
