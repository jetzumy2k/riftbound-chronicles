--!strict
--[[
	WorldBudget — performance budget per zone (Phase 16, PLAN.md D-82).

	Every built zone is measured once at startup (World/BudgetAudit) and its
	counts compared with the budget for its kind. Over budget logs a warning
	with the numbers so art passes can't quietly grow a zone past what a
	low-end phone streams and renders.

	Budgets are per built copy: one capital, one war zone, one realm's
	dungeon (all floors). Terrain voxels are not parts and are not counted.
	Lights and particle emitters are the costly items on mobile, so they get
	tight caps; emitterRate is the summed Rate of the zone's emitters
	(particles per second while every emitter is in view).
]]

export type Counts = {
	parts: number,
	meshParts: number,
	lights: number,
	shadowLights: number,
	emitters: number,
	emitterRate: number,
}

export type Budget = Counts

local WorldBudget = {}

WorldBudget.KINDS = table.freeze({ "Capital", "WarZone", "Dungeon" })

WorldBudget.BUDGETS = table.freeze({
	-- D-37: about 1,000 parts per capital, 300-stud city.
	-- Measured 2026-10-25: Skyreach 859 parts / 12 lights, Emberdeep 734 / 14.
	Capital = table.freeze({
		parts = 1400,
		meshParts = 120,
		lights = 48,
		shadowLights = 4,
		emitters = 8,
		emitterRate = 160,
	}),
	-- 1,000-stud terrain zone; most of the look is Terrain, parts are props.
	-- Measured 2026-10-25: Jungle 5,462 parts (the forest), Desert 887;
	-- both 31 lights.
	WarZone = table.freeze({
		parts = 7000,
		meshParts = 300,
		lights = 48,
		shadowLights = 2,
		emitters = 16,
		emitterRate = 240,
	}),
	-- One realm's Rift Hollow: four floors side by side, streamed by floor.
	-- Measured 2026-10-25: 5,410 parts / 160 lights per realm.
	Dungeon = table.freeze({
		parts = 9000,
		meshParts = 300,
		lights = 220,
		shadowLights = 0,
		emitters = 24,
		emitterRate = 320,
	}),
} :: { [string]: Budget })

-- Streaming radius the budgets assume (studs): Workspace.StreamingTargetRadius.
WorldBudget.STREAMING_TARGET_RADIUS = 1024

local FIELDS = table.freeze({ "parts", "meshParts", "lights", "shadowLights", "emitters", "emitterRate" })
WorldBudget.FIELDS = FIELDS

function WorldBudget.empty(): Counts
	return { parts = 0, meshParts = 0, lights = 0, shadowLights = 0, emitters = 0, emitterRate = 0 }
end

-- The fields over budget, in FIELDS order, as "field used/limit".
function WorldBudget.over(kind: string, counts: Counts): { string }
	local budget = WorldBudget.BUDGETS[kind]
	assert(budget, `unknown zone kind {kind}`)
	local out = {}
	for _, field in FIELDS do
		local used = (counts :: any)[field] :: number
		local limit = (budget :: any)[field] :: number
		if used > limit then
			table.insert(out, `{field} {used}/{limit}`)
		end
	end
	return out
end

-- One line for the log: "parts 812/1400 (58%), lights 20/48 (42%), ...".
function WorldBudget.summary(kind: string, counts: Counts): string
	local budget = WorldBudget.BUDGETS[kind]
	assert(budget, `unknown zone kind {kind}`)
	local bits = {}
	for _, field in FIELDS do
		local used = (counts :: any)[field] :: number
		local limit = (budget :: any)[field] :: number
		local share = if limit > 0
			then math.floor(used / limit * 100 + 0.5)
			else (if used > 0 then 999 else 0)
		table.insert(bits, `{field} {used}/{limit} ({share}%)`)
	end
	return table.concat(bits, ", ")
end

return table.freeze(WorldBudget)
