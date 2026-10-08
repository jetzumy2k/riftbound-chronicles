local load = require("../loader")
local Schema = load("src/shared/Logic/Schema")
local ConfigCore = load("src/server/Config/ConfigCore")
local Defaults = load("src/server/Config/Defaults")
local buildSchema = load("src/server/Config/ConfigSchema")

return function(t)
	local spec = buildSchema(Schema)

	t.it("defaults validate against the schema (no missing or extra keys)", function()
		local ok, result = ConfigCore.resolve(Defaults, nil, spec, Schema)
		t.ok(ok, tostring(result))
	end)

	t.it("effective config is deep-frozen and a copy of defaults", function()
		local _, config = ConfigCore.resolve(Defaults, nil, spec, Schema)
		t.ok(table.isfrozen(config))
		t.ok(table.isfrozen(config.Net))
		t.ok(not table.isfrozen(Defaults))
		t.ok(config ~= Defaults)
	end)

	t.it("applies a valid partial override", function()
		local ok, config = ConfigCore.resolve(Defaults, {
			version = 3,
			values = { Net = { GlobalCapacity = 60 }, Flags = { Maintenance = true } },
		}, spec, Schema)
		t.ok(ok, tostring(config))
		t.eq(config.Net.GlobalCapacity, 60)
		t.eq(config.Net.GlobalRefillPerSecond, Defaults.Net.GlobalRefillPerSecond)
		t.eq(config.Flags.Maintenance, true)
		t.eq(config.Flags.ConfigOverrides, true)
	end)

	t.it("rejects unknown keys in overrides", function()
		local ok, reason = ConfigCore.resolve(Defaults, {
			version = 1,
			values = { Net = { Typo = 1 } },
		}, spec, Schema)
		t.rejects("unexpected key", ok, reason)
	end)

	t.it("rejects out-of-range and wrong-type values", function()
		t.rejects(
			nil,
			ConfigCore.resolve(
				Defaults,
				{ version = 1, values = { Net = { GlobalCapacity = 0 } } },
				spec,
				Schema
			)
		)
		t.rejects(
			nil,
			ConfigCore.resolve(
				Defaults,
				{ version = 1, values = { Flags = { Maintenance = "yes" } } },
				spec,
				Schema
			)
		)
		t.rejects(
			nil,
			ConfigCore.resolve(Defaults, { version = 1, values = { Log = { Level = "Loud" } } }, spec, Schema)
		)
	end)

	t.it("rejects malformed override envelopes", function()
		t.rejects(nil, ConfigCore.resolve(Defaults, { values = {} } :: any, spec, Schema))
		t.rejects(nil, ConfigCore.resolve(Defaults, { version = 0, values = {} }, spec, Schema))
		t.rejects(nil, ConfigCore.resolve(Defaults, { version = 1.5, values = {} }, spec, Schema))
		t.rejects(nil, ConfigCore.resolve(Defaults, { version = 1 } :: any, spec, Schema))
	end)

	t.it("deepMerge replaces arrays wholesale and merges dictionaries", function()
		local merged = ConfigCore.deepMerge(
			{ list = { 1, 2, 3 }, d = { a = 1, b = 2 } },
			{ list = { 9 }, d = { b = 5 } }
		)
		t.eq(#merged.list, 1)
		t.eq(merged.list[1], 9)
		t.eq(merged.d.a, 1)
		t.eq(merged.d.b, 5)
	end)

	t.it("getPath reads dotted paths", function()
		local _, config = ConfigCore.resolve(Defaults, nil, spec, Schema)
		t.eq(ConfigCore.getPath(config, "Net.GlobalCapacity"), Defaults.Net.GlobalCapacity)
		t.eq(ConfigCore.getPath(config, "Net.Missing"), nil)
		t.eq(ConfigCore.getPath(config, "Log.Level.Deeper"), nil)
	end)
end
