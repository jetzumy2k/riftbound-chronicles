local load = require("../loader")
local Schema = load("src/shared/Logic/Schema")
local Registry = load("src/shared/Net/Registry")(Schema)
local StrikeRules = load("src/shared/Logic/StrikeRules")
local Defaults = load("src/server/Config/Defaults")
local MallDefinitions = load("src/shared/Definitions/MallDefinitions")

-- Phase 21 security review (PLAN.md D-97, docs/security/SECURITY_REVIEW.md):
-- regression checks for "never trust the client".

-- Field names that would let a client state an outcome.
local OUTCOME_FIELDS = {
	damage = true,
	amount = true,
	xp = true,
	exp = true,
	experience = true,
	level = true,
	rarity = true,
	price = true,
	cost = true,
	gold = true,
	mallpoints = true,
	reward = true,
	rewards = true,
	attributes = true,
	enhancement = true,
	stats = true,
	hp = true,
	health = true,
	cooldown = true,
	role = true,
	permission = true,
}

-- Every struct field name inside `spec` (recursively).
local function fieldNames(spec: any, out: { string })
	if type(spec) ~= "table" then
		return
	end
	if spec.kind == "struct" then
		for name, child in spec.fields do
			table.insert(out, name)
			fieldNames(child, out)
		end
	elseif spec.kind == "array" then
		fieldNames(spec.of, out)
	elseif spec.kind == "map" then
		fieldNames(spec.keys, out)
		fieldNames(spec.of, out)
	end
end

-- The longest free string a spec accepts (0 if none).
local function longestString(spec: any): number
	if type(spec) ~= "table" then
		return 0
	end
	if spec.kind == "string" then
		return spec.maxLen or math.huge
	elseif spec.kind == "struct" then
		local best = 0
		for _, child in spec.fields do
			best = math.max(best, longestString(child))
		end
		return best
	elseif spec.kind == "array" then
		return longestString(spec.of)
	elseif spec.kind == "map" then
		return math.max(longestString(spec.keys), longestString(spec.of))
	end
	return 0
end

local function playerRemotes(): { [string]: any }
	local out = {}
	for name, spec in Registry do
		if spec.direction == "ClientToServer" and spec.permission == nil then
			out[name] = spec
		end
	end
	return out
end

return function(t)
	t.describe("Security (D-97)", function()
		t.it("no player remote lets the client state an outcome", function()
			for name, spec in playerRemotes() do
				local names = {}
				for _, arg in spec.args do
					fieldNames(arg, names)
				end
				for _, field in names do
					t.ok(OUTCOME_FIELDS[string.lower(field)] == nil, `{name} accepts "{field}"`)
				end
			end
		end)

		t.it("every player remote is rate-limited, state-checked and takes short strings", function()
			for name, spec in playerRemotes() do
				t.ok(spec.rate ~= nil and spec.rate.capacity <= 20, `{name} rate limit`)
				if name ~= "ClientReady" then
					t.ok(table.find(spec.states, "ProfileLoaded") ~= nil, `{name} needs a loaded profile`)
				end
				for _, arg in spec.args do
					t.ok(longestString(arg) <= 64, `{name} accepts a long string`)
				end
			end
		end)

		t.it("buying names a catalog entry only (price and goods are server-side)", function()
			local spec = Registry.BuyMallItem
			t.eq(#spec.args, 1)
			t.eq(spec.args[1].kind, "enum")
			t.eq(#spec.args[1].values, #MallDefinitions.IDS)
		end)

		t.it("attribute spending is bounded per request", function()
			local fields = Registry.SpendAttributes.args[1].fields
			for _, id in { "REC", "INT", "WIS", "STR", "AGI" } do
				t.ok(fields[id].max <= 150, `{id} capped`)
			end
		end)

		t.it("event rewards from staff are bounded and gated", function()
			local spec = Registry.AdminEvents
			t.eq(spec.permission, "events.activate")
			local rewards = spec.args[2].fields.Rewards
			t.ok(rewards.maxCount <= 4, "at most 4 rewards")
			t.ok(rewards.of.fields.Count.max <= 10000, "amounts capped")
		end)

		t.it("movement cheats are enforced, not just logged", function()
			t.eq(Defaults.AntiExploit.Mode, "Enforce")
			t.ok(Defaults.AntiExploit.TamperKickCount >= 10, "kick threshold leaves room for glitches")
		end)

		t.it("tampered requests kick; tapping fast or lag never does", function()
			t.ok(StrikeRules.isTamper("BadArgs") and StrikeRules.isTamper("NoPermission"), "tamper codes")
			t.ok(
				not StrikeRules.isTamper("RateLimited") and not StrikeRules.isTamper("BadState"),
				"normal play"
			)
			t.ok(not StrikeRules.isTamper("HandlerError"), "our own bugs never kick")
			local times = {}
			for i = 1, 19 do
				t.ok(not StrikeRules.record(times, i, 60, 20), `strike {i}`)
			end
			t.ok(StrikeRules.record(times, 20, 60, 20), "the 20th within a minute kicks")
			local slow = {}
			for i = 1, 40 do
				t.ok(not StrikeRules.record(slow, i * 10, 60, 20), "spread out over minutes: no kick")
			end
		end)
	end)
end
