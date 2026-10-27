--[[
	D-119: the Warden's trial chain: 7-10 steps in order, Collect drops
	rolled on the server, start rules, the reward claim and repair.
]]
local load = require("../loader")
local ChainRules = load("src/shared/Logic/ChainRules")
local ChainQuestDefinitions = load("src/shared/Definitions/ChainQuestDefinitions")
local EnemyDefinitions = load("src/shared/Definitions/EnemyDefinitions")
local RewardClaims = load("src/server/Persistence/RewardClaims")
local Defaults = load("src/server/Config/Defaults")

return function(t)
	t.describe("Chain quest (D-119)", function()
		local c = Defaults.ChainQuest

		t.it("7 to 10 steps, every creature real", function()
			local n = ChainRules.stepCount()
			t.ok(n >= 7 and n <= 10, `{n} steps`)
			for _, step in ChainQuestDefinitions.Steps do
				t.ok(step.count >= 1)
				t.ok(step.kind == "Kill" or step.kind == "Collect")
				for _, id in step.enemies do
					t.ok(EnemyDefinitions.get(id) ~= nil, `enemy {id}`)
				end
			end
		end)

		t.it("starts only at level, off cooldown, once at a time", function()
			local chain = ChainRules.new()
			t.eq(select(2, ChainRules.canStart(chain, c, c.MinLevel - 1, 0)), "level")
			t.ok(ChainRules.canStart(chain, c, c.MinLevel, 0))
			ChainRules.start(chain)
			t.eq(select(2, ChainRules.canStart(chain, c, 30, 0)), "active")
			chain.Active = false
			chain.CompletedAt = 1000
			t.eq(select(2, ChainRules.canStart(chain, c, 30, 1000 + 3600)), "cooldown")
			t.ok(ChainRules.canStart(chain, c, 30, 1000 + c.CooldownHours * 3600))
		end)

		t.it("only the current step's creatures count; Collect needs the roll", function()
			local chain = ChainRules.new()
			ChainRules.start(chain)
			local first = ChainQuestDefinitions.Steps[1]
			t.ok(not ChainRules.onKill(chain, c, "NotThisOne", 0), "other creatures don't count")
			for i = 1, first.count do
				local counted, done = ChainRules.onKill(chain, c, first.enemies[1], 0.99)
				t.ok(counted)
				t.eq(done, i == first.count)
			end
			t.eq(chain.Step, 2)
			local second = ChainQuestDefinitions.Steps[2]
			t.eq(second.kind, "Collect")
			t.ok(not ChainRules.onKill(chain, c, second.enemies[1], 0.99), "no drop on a high roll")
			t.ok(ChainRules.onKill(chain, c, second.enemies[1], 0.01), "drop on a low roll")
			t.eq(chain.Progress, 1)
		end)

		t.it("finishing waits for the reward; one claim per chain", function()
			local chain = ChainRules.new()
			ChainRules.start(chain)
			chain.Step = ChainRules.stepCount() + 1
			t.ok(ChainRules.ready(chain))
			t.ok(not ChainRules.onKill(chain, c, "RiftWolf", 0), "nothing counts once done")
			local id = ChainRules.claimId(chain)
			t.ok(RewardClaims.isValidId(id))
			ChainRules.finish(chain, 500)
			t.ok(not chain.Active)
			t.eq(chain.Cycles, 1)
			t.ok(ChainRules.claimId(chain) ~= id, "the next chain has its own claim")
		end)

		t.it("a damaged stored chain is repaired", function()
			local fixed, changed = ChainRules.repair({ Active = true, Step = 99, Progress = -3, Cycles = 2 })
			t.ok(changed)
			t.eq(fixed.Step, 1)
			t.eq(fixed.Progress, 0)
			t.eq(fixed.Cycles, 2)
			local fresh, changed2 = ChainRules.repair(nil)
			t.ok(changed2)
			t.ok(not fresh.Active)
		end)
	end)
end
