--!strict
--[[
	ConfigSchema
	Schema for the *effective* config (defaults merged with overrides). Structs
	are strict: unknown keys in an override are rejected.

	Exported as a function of the Schema module so it stays pure and testable.
]]

return function(S: any)
	return S.struct({
		Log = S.struct({
			Level = S.enum({ "Debug", "Info", "Warn", "Error" }),
		}),

		Flags = S.struct({
			ConfigOverrides = S.boolean(),
			Maintenance = S.boolean(),
		}),

		Net = S.struct({
			GlobalCapacity = S.int(5, 500),
			GlobalRefillPerSecond = S.number(1, 500),
			SecurityLogThrottleSeconds = S.number(1, 600),
		}),

		Config = S.struct({
			PollSeconds = S.int(30, 3600),
		}),
	})
end
