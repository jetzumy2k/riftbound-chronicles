--!strict
--[[
	Config defaults (server-only; never replicated).

	Live overrides from the DataStore are deep-merged on top of these and the
	result is validated against ConfigSchema. Every key here must exist in
	ConfigSchema and vice versa (enforced by tests).

	Later phases add their own sections (Combat, Loot, Enhancement, Events, ...).
]]

return {
	Log = {
		-- Minimum level outside Studio. Studio always logs at Debug.
		Level = "Info",
	},

	Flags = {
		-- Read live overrides from the DataStore and listen for invalidations.
		ConfigOverrides = true,
		-- When true, players are kicked with a maintenance message.
		Maintenance = false,
	},

	Net = {
		-- Global per-player budget across all client->server remotes
		-- (SECURITY_MODEL.md §4). Per-remote limits live in the Registry.
		GlobalCapacity = 40,
		GlobalRefillPerSecond = 30,
		-- Security log throttle per (player, reject code).
		SecurityLogThrottleSeconds = 10,
	},

	Config = {
		-- Fallback poll interval if a MessagingService invalidation is missed.
		PollSeconds = 300,
	},

	-- Phase 6 combat (PLAN.md D-01..D-05, D-23, D-24; SECURITY_MODEL.md §5A).
	Combat = {
		-- D-01: outgoing damage/healing x PowerScalePerLevel ^ level.
		PowerScalePerLevel = 1.047,
		-- D-05: damage = raw * K / (K + Defense), K = base + perLevel * attackerLevel.
		DefenseKBase = 200,
		DefenseKPerLevel = 25,
		-- Seconds after the last hostile action before a player counts as out of combat.
		TagSeconds = 10,
		DefeatDelaySeconds = 2.5,
		SpawnProtectSeconds = 10,
		ExitBubbleSeconds = 3,
		-- D-04: HP regen (CLAUDE.md §5 % per second) only after this long out of combat.
		RegenDelaySeconds = 5,
		-- D-29 (approved): safe zones restore HP quickly (% of max HP per second).
		SafeZoneRegenPctPerSecond = 20,
		-- D-23: Focus resource.
		FocusMax = 100,
		FocusRegenPerSecond = 10,
		-- SECURITY_MODEL §5A.3 range tolerance.
		RangeToleranceStuds = 4,
		MaxPingCompensationSeconds = 0.3,
		-- Unsanctioned resets out of combat are allowed this often.
		ResetCooldownSeconds = 15,
		-- Players within this distance receive combat feedback events.
		RelevanceRadius = 160,
	},

	-- SECURITY_MODEL §5A.2 movement validation. Shadow = log only (Phase 6).
	AntiExploit = {
		Mode = "Shadow",
		SampleHz = 10,
		SpeedFactor = 1.25,
		SpeedToleranceStuds = 4,
		MaxAirSeconds = 3,
		RubberBandPoints = 3,
		StrikePoints = 10,
		TeleportStuds = 150,
	},
}
