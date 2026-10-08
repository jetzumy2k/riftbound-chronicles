--!strict
--[[
	Service manifest: boot order and dependency layers (ARCHITECTURE.md §5.1).

	Rules (enforced by tests/pure/layering.spec.luau):
	  - A service may require only services in its own or a lower layer.
	  - A same-layer dependency must appear earlier in this list.
	  - Layers 0-1 are critical: an Init failure puts the server in maintenance.

	Pure data module.
]]

return {
	{ name = "ConfigurationService", layer = 0 },
	{ name = "AuditLogService", layer = 0 },
	{ name = "RateLimitService", layer = 0 },
	{ name = "NetService", layer = 0 },
	{ name = "PlayerDataService", layer = 1 },
	{ name = "LevelService", layer = 2 },
	{ name = "StatsService", layer = 2 },
}
