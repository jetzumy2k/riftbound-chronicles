--[[
	Pure test runner. From the repository root:

	    lune run tests/pure/run

	Exits non-zero if any test fails.
]]

local process = require("@lune/process")

local harness = require("./harness")

-- Static list: keeps requires literal so they resolve the same in every Lune version.
local specs = {
	{ "enums_constants", require("./specs/enums_constants.spec") },
	{ "schema", require("./specs/schema.spec") },
	{ "rate_bucket", require("./specs/rate_bucket.spec") },
	{ "signal", require("./specs/signal.spec") },
	{ "log", require("./specs/log.spec") },
	{ "guard", require("./specs/guard.spec") },
	{ "config_core", require("./specs/config_core.spec") },
	{ "registry", require("./specs/registry.spec") },
	{ "xp_table", require("./specs/xp_table.spec") },
	{ "stat_formulas", require("./specs/stat_formulas.spec") },
	{ "profile_validator", require("./specs/profile_validator.spec") },
	{ "migrations", require("./specs/migrations.spec") },
	{ "reward_claims", require("./specs/reward_claims.spec") },
	{ "profile_view", require("./specs/profile_view.spec") },
	{ "structure", require("./specs/structure.spec") },
}

for _, entry in specs do
	harness.t.describe(entry[1], function()
		entry[2](harness.t)
	end)
end

local state = harness.state
for _, failure in state.failures do
	print(`FAIL {failure}\n`)
end
print(`\n{state.passed} passed, {state.failed} failed`)

process.exit(if state.failed == 0 then 0 else 1)
