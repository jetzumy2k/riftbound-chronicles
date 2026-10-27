local load = require("../loader")
local ComboMath = load("src/shared/Logic/ComboMath")
local BasicAttacks = load("src/shared/Definitions/BasicAttacks")
local AnimationClips = load("src/shared/Definitions/AnimationClips")
local Enums = load("src/shared/Enums")

local STEPS = {
	{ recovery = 0.4, window = 0.6 },
	{ recovery = 0.4, window = 0.6 },
	{ recovery = 0.8, window = 0.6 },
}
local FINISHER_COOLDOWN = 0.3

local function press(state, now: number, slack: number?): number?
	local index = ComboMath.resolve(state, now, STEPS, slack)
	if index then
		ComboMath.commit(state, now, STEPS, index, FINISHER_COOLDOWN)
	end
	return index
end

return function(t)
	t.describe("ComboMath", function()
		t.it("chains 1 -> 2 -> 3 inside the windows", function()
			local s = ComboMath.new()
			t.eq(press(s, 10), 1)
			t.eq(press(s, 10.5), 2)
			t.eq(press(s, 11.0), 3)
		end)

		t.it("ignores presses before recovery", function()
			local s = ComboMath.new()
			t.eq(press(s, 10), 1)
			t.eq(press(s, 10.2), nil)
			t.eq(s.index, 1, "an early press does not advance the chain")
			t.eq(press(s, 10.4), 2)
		end)

		t.it("slack forgives slightly early presses (network jitter)", function()
			local s = ComboMath.new()
			press(s, 10)
			t.eq(press(s, 10.35, 0.1), 2)
		end)

		t.it("restarts at step 1 after the window closes", function()
			local s = ComboMath.new()
			press(s, 10)
			t.eq(press(s, 10 + 0.4 + 0.6 + 0.01), 1)
		end)

		t.it("pauses after the finisher, then starts over", function()
			local s = ComboMath.new()
			press(s, 10)
			press(s, 10.4)
			press(s, 10.8)
			t.eq(press(s, 10.8 + 0.8 + 0.1), nil, "finisher cooldown")
			t.eq(press(s, 10.8 + 0.8 + FINISHER_COOLDOWN), 1)
		end)

		t.it("waitTime counts down to zero", function()
			local s = ComboMath.new()
			t.eq(ComboMath.waitTime(s, 0), 0)
			press(s, 10)
			t.near(ComboMath.waitTime(s, 10.1), 0.3, 1e-9)
			t.eq(ComboMath.waitTime(s, 11), 0)
		end)
	end)

	t.describe("BasicAttacks combos", function()
		t.it("every job has a 3-step chain ending in a heavy finisher", function()
			for _, job in Enums.Job do
				local attack = BasicAttacks.forJob(job)
				t.ok(attack ~= nil, job)
				t.eq(#attack.steps, 3, job)
				t.eq(attack.steps[3].heavy, true, `{job} finisher`)
				t.ok(attack.finisherCooldown >= 0 and attack.finisherCooldown <= 2, job)
				t.ok(attack.range > 0 and attack.range <= 60, job)
			end
			t.eq(BasicAttacks.forJob("Bard"), nil)
		end)

		t.it("steps use real clips and never cut their own hit", function()
			for _, job in Enums.Job do
				for index, step in BasicAttacks.forJob(job).steps do
					local clip = AnimationClips.get(step.clip)
					t.ok(clip ~= nil, `{job} step {index}: clip {step.clip}`)
					local hit = BasicAttacks.hitTime(step)
					t.ok(hit > 0 and hit < clip.duration, `{job} step {index}: hit inside clip`)
					t.ok(step.recovery >= hit + 0.1, `{job} step {index}: recovery after the hit lands`)
					t.ok(step.recovery <= clip.duration, `{job} step {index}: recovery within the clip`)
					t.ok(step.coefficient > 0 and step.coefficient <= 2, `{job} step {index}: coefficient`)
					t.ok(step.window >= 0.2 and step.window <= 1.5, `{job} step {index}: window`)
					local _, found = BasicAttacks.stepForClip(step.clip)
					t.eq(found, index, `{step.clip} maps back to its step`)
				end
			end
		end)

		t.it("melee lunges, ranged and magic shoot projectiles", function()
			for _, job in Enums.Job do
				local attack = BasicAttacks.forJob(job)
				for index, step in attack.steps do
					if attack.style == "Melee" then
						t.ok(step.lunge ~= nil and step.lunge <= 4, `{job} step {index}: lunge`)
						t.eq(step.projectileSpeed, nil)
					else
						t.eq(step.lunge, nil, `{job} step {index}: no lunge`)
					end
					if step.projectileSpeed then
						t.ok(step.projectileSpeed >= 60 and step.projectileSpeed <= 300, `{job} step {index}`)
					end
				end
			end
			t.ok(BasicAttacks.forJob("Warrior").range < BasicAttacks.forJob("Healer").range)
			t.ok(BasicAttacks.forJob("Healer").range < BasicAttacks.forJob("Archer").range)
		end)

		t.it("the chain window opens after recovery and closes on time", function()
			local state = ComboMath.new()
			t.eq(ComboMath.window(state, 0, STEPS), nil, "resting: no window")
			press(state, 0)
			t.eq(ComboMath.window(state, 0.2, STEPS), nil, "still recovering")
			local left, nextStep = ComboMath.window(state, 0.4, STEPS)
			t.eq(left, 1)
			t.eq(nextStep, 2)
			left = ComboMath.window(state, 0.7, STEPS)
			t.ok(left ~= nil and math.abs(left - 0.5) < 1e-6, "half the window left")
			t.eq(ComboMath.window(state, 1.01, STEPS), nil, "closed")
			press(state, 0.5)
			press(state, 1.0)
			t.eq(ComboMath.window(state, 1.9, STEPS), nil, "no window after the finisher")
		end)

		t.it("full-chain damage keeps the Phase 6 balance", function()
			-- Same damage per second as the single attacks they replace (±10%).
			local expected = { Warrior = 1.25, Healer = 0.7, Mage = 0.955, Archer = 0.944 }
			for job, dps in expected do
				local actual = BasicAttacks.chainDps(BasicAttacks.forJob(job))
				t.ok(math.abs(actual - dps) / dps <= 0.1, `{job}: {actual} vs {dps}`)
			end
		end)
	end)
end
