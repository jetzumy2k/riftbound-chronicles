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

		Combat = S.struct({
			PowerScalePerLevel = S.number(1, 1.2),
			DefenseKBase = S.number(1, 10000),
			DefenseKPerLevel = S.number(0, 1000),
			TagSeconds = S.number(1, 60),
			DefeatDelaySeconds = S.number(0.5, 10),
			SpawnProtectSeconds = S.number(0, 60),
			ExitBubbleSeconds = S.number(0, 10),
			RegenDelaySeconds = S.number(0, 60),
			SafeZoneRegenPctPerSecond = S.number(0, 100),
			FocusMax = S.int(10, 1000),
			FocusRegenPerSecond = S.number(0, 200),
			RangeToleranceStuds = S.number(0, 20),
			MaxPingCompensationSeconds = S.number(0, 1),
			ResetCooldownSeconds = S.number(0, 300),
			RelevanceRadius = S.number(20, 1000),
		}),

		AntiExploit = S.struct({
			Mode = S.enum({ "Off", "Shadow", "Enforce" }),
			SampleHz = S.int(2, 30),
			SpeedFactor = S.number(1, 3),
			SpeedToleranceStuds = S.number(0, 50),
			MaxAirSeconds = S.number(1, 30),
			RubberBandPoints = S.number(1, 100),
			StrikePoints = S.number(1, 1000),
			TeleportStuds = S.number(20, 2000),
		}),
	})
end
