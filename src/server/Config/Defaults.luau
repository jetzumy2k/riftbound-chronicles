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
}
