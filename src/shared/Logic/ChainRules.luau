--!strict
--[[
	ChainRules — progress through the Warden's trial chain (PLAN.md D-119;
	steps in Definitions/ChainQuestDefinitions, numbers in config
	ChainQuest). Pure: the server passes the random roll in.

	State per character (profile `Chain`):
	  Active       on the chain now
	  Step         the current step (#Steps + 1 = all done, reward waiting)
	  Progress     done of the current step
	  CompletedAt  when the last chain was claimed (UTC seconds)
	  Cycles       chains finished so far (also the reward claim id)
]]

local ChainQuestDefinitions = require(script.Parent.Parent.Definitions.ChainQuestDefinitions)

local ChainRules = {}

export type Chain = { Active: boolean, Step: number, Progress: number, CompletedAt: number, Cycles: number }
export type Config = { Enabled: boolean, MinLevel: number, CollectChancePct: number, CooldownHours: number }

function ChainRules.new(): Chain
	return { Active = false, Step = 1, Progress = 0, CompletedAt = 0, Cycles = 0 }
end

function ChainRules.stepCount(): number
	return #ChainQuestDefinitions.Steps
end

-- True when every step is done and the reward waits.
function ChainRules.ready(chain: Chain): boolean
	return chain.Active and chain.Step > ChainRules.stepCount()
end

-- Seconds until a new chain may start (0 = now).
function ChainRules.cooldownLeft(chain: Chain, config: Config, now: number): number
	if chain.CompletedAt <= 0 then
		return 0
	end
	return math.max(0, chain.CompletedAt + config.CooldownHours * 3600 - now)
end

-- (ok, reason): closed, active, level, cooldown.
function ChainRules.canStart(chain: Chain, config: Config, level: number, now: number): (boolean, string?)
	if not config.Enabled then
		return false, "closed"
	elseif chain.Active then
		return false, "active"
	elseif level < config.MinLevel then
		return false, "level"
	elseif ChainRules.cooldownLeft(chain, config, now) > 0 then
		return false, "cooldown"
	end
	return true, nil
end

function ChainRules.start(chain: Chain)
	chain.Active = true
	chain.Step = 1
	chain.Progress = 0
end

--[[
	A creature `enemyId` was defeated (the player earned its EXP). `roll`
	is 0..1 (the server's random number, used by Collect steps). Returns
	(counted, stepDone): counted when progress went up.
]]
function ChainRules.onKill(chain: Chain, config: Config, enemyId: string, roll: number): (boolean, boolean)
	if not chain.Active or ChainRules.ready(chain) then
		return false, false
	end
	local step = ChainQuestDefinitions.Steps[chain.Step]
	if step == nil or table.find(step.enemies, enemyId) == nil then
		return false, false
	end
	if step.kind == "Collect" and roll * 100 >= config.CollectChancePct then
		return false, false
	end
	chain.Progress += 1
	if chain.Progress >= step.count then
		chain.Step += 1
		chain.Progress = 0
		return true, true
	end
	return true, false
end

-- Ends a finished chain after its reward is given.
function ChainRules.finish(chain: Chain, now: number)
	chain.Active = false
	chain.Step = 1
	chain.Progress = 0
	chain.CompletedAt = now
	chain.Cycles += 1
end

-- The reward claim id of the chain being finished (never paid twice).
function ChainRules.claimId(chain: Chain): string
	return `C:{chain.Cycles + 1}`
end

-- A stored chain with every field in range (old profiles: a fresh one).
function ChainRules.repair(raw: any): (Chain, boolean)
	local fresh = ChainRules.new()
	if type(raw) ~= "table" then
		return fresh, true
	end
	local n = ChainRules.stepCount()
	local function int(value: any, lo: number, hi: number, default: number): number
		return if type(value) == "number"
				and value == value
				and value % 1 == 0
				and value >= lo
				and value <= hi
			then value
			else default
	end
	local out: Chain = {
		Active = raw.Active == true,
		Step = int(raw.Step, 1, n + 1, 1),
		Progress = int(raw.Progress, 0, 1000, 0),
		CompletedAt = int(raw.CompletedAt, 0, 1e12, 0),
		Cycles = int(raw.Cycles, 0, 1e9, 0),
	}
	local changed = out.Active ~= raw.Active
		or out.Step ~= raw.Step
		or out.Progress ~= raw.Progress
		or out.CompletedAt ~= raw.CompletedAt
		or out.Cycles ~= raw.Cycles
	return out, changed
end

return table.freeze(ChainRules)
