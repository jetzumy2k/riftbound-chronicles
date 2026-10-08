local load = require("../loader")
local Schema = load("src/shared/Logic/Schema")
local NetSpec = load("src/shared/Net/NetSpec")
local Registry = load("src/shared/Net/Registry")(Schema)

return function(t)
	t.it("the game registry is valid", function()
		local ok, errors = NetSpec.validateRegistry(Registry, Schema)
		t.ok(ok, if errors then table.concat(errors, "; ") else nil)
	end)

	t.it("every client->server remote has a rate limit and states list", function()
		for name, spec in Registry do
			if spec.direction == "ClientToServer" then
				t.ok(spec.rate ~= nil, name)
				t.ok(spec.states ~= nil, name)
			end
		end
	end)

	t.it("no forbidden authoritative remotes exist", function()
		-- SECURITY_MODEL.md: no remote may carry outcomes.
		local forbidden = {
			"damage",
			"heal",
			"xp",
			"experience",
			"level",
			"loot",
			"rarity",
			"role",
			"teleport",
			"position",
		}
		for name in Registry do
			local lower = string.lower(name)
			for _, word in forbidden do
				t.ok(not string.find(lower, word, 1, true), `remote '{name}' looks authoritative ('{word}')`)
			end
		end
	end)

	t.describe("validateRegistry rejects bad specs", function()
		local function check(registry, fragment)
			local ok, errors = NetSpec.validateRegistry(registry, Schema)
			t.eq(ok, false)
			t.ok(string.find(table.concat(errors, ";"), fragment, 1, true) ~= nil, table.concat(errors, ";"))
		end

		t.it("server-invoked RemoteFunctions", function()
			check({ Bad = { direction = "ServerToClient", kind = "Function", args = {} } }, "forbidden")
		end)

		t.it("missing rate limit", function()
			check({ Bad = { direction = "ClientToServer", kind = "Event", args = {}, states = {} } }, "rate")
		end)

		t.it("missing states", function()
			check({
				Bad = {
					direction = "ClientToServer",
					kind = "Event",
					args = {},
					rate = { capacity = 1, refillPerSecond = 1 },
				},
			}, "states")
		end)

		t.it("required arg after optional", function()
			check({
				Bad = {
					direction = "ClientToServer",
					kind = "Event",
					args = { Schema.optional(Schema.int()), Schema.int() },
					rate = { capacity = 1, refillPerSecond = 1 },
					states = {},
				},
			}, "required arg after optional")
		end)

		t.it("non-PascalCase names and invalid specs", function()
			check({ badName = { direction = "ServerToClient", kind = "Event", args = {} } }, "PascalCase")
			check(
				{ Bad = { direction = "ServerToClient", kind = "Event", args = { { kind = "nope" } } } },
				"not a valid spec"
			)
		end)

		t.it("server->client remotes declaring rate/states", function()
			check({
				Bad = {
					direction = "ServerToClient",
					kind = "Event",
					args = {},
					rate = { capacity = 1, refillPerSecond = 1 },
				},
			}, "must not declare")
		end)
	end)

	t.describe("Notify payload contract", function()
		local specs = Registry.Notify.args

		t.it("accepts server-shaped payloads", function()
			t.ok(Schema.validateArgs(specs, 1, { { kind = "Welcome", textKey = "system.welcome" } }))
			t.ok(
				Schema.validateArgs(
					specs,
					1,
					{ { kind = "Info", textKey = "quest.done", params = { name = "First Spark" } } }
				)
			)
		end)

		t.it("rejects malformed payloads", function()
			local function expectBadArgs(payload)
				local ok, _, code = Schema.validateArgs(specs, 1, { payload })
				t.eq(ok, false)
				t.eq(code, "BadArgs")
			end
			expectBadArgs({ kind = "Shout", textKey = "x" })
			expectBadArgs({ kind = "Info", textKey = "has spaces" })
			expectBadArgs({ kind = "Info", textKey = "k", extra = 1 })
		end)
	end)

	t.it("ClientReady accepts no arguments", function()
		t.ok(Schema.validateArgs(Registry.ClientReady.args, 0, {}))
		local ok, _, code = Schema.validateArgs(Registry.ClientReady.args, 1, { "spoof" })
		t.eq(ok, false)
		t.eq(code, "BadArity")
	end)
end
