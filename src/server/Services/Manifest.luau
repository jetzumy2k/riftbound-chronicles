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
	{ name = "SystemResetService", layer = 1 },
	{ name = "EventService", layer = 1 },
	{ name = "LevelService", layer = 2 },
	{ name = "StatsService", layer = 2 },
	{ name = "RaceService", layer = 2 },
	{ name = "JobService", layer = 2 },
	{ name = "SafeZoneService", layer = 4 },
	{ name = "AntiExploitService", layer = 4 },
	{ name = "CombatService", layer = 4 },
	{ name = "MovementService", layer = 4 },
	{ name = "SkillService", layer = 4 },
	{ name = "AttributeService", layer = 4 },
	{ name = "BuffService", layer = 4 },
	{ name = "InventoryService", layer = 4 },
	{ name = "EnhancementService", layer = 4 },
	{ name = "WorldService", layer = 5 },
	{ name = "TravelService", layer = 5 },
	{ name = "MobService", layer = 5 },
	{ name = "BossService", layer = 5 },
	{ name = "PartyService", layer = 5 },
	{ name = "LootService", layer = 5 },
	{ name = "DungeonService", layer = 5 },
	{ name = "PvPService", layer = 5 },
	-- D-108: war-zone camp guardians.
	{ name = "GuardService", layer = 5 },
	{ name = "MallService", layer = 5 },
	{ name = "QuestService", layer = 6 },
	{ name = "WorldEventService", layer = 6 },
	{ name = "EventChallengeService", layer = 6 },
	-- Phase 23 (D-102): reads NetService traffic and MobService counts.
	{ name = "PerfService", layer = 6 },
	-- D-118: gear wear (the Blacksmith's repairs are ShopService's).
	{ name = "DurabilityService", layer = 6 },
	-- D-117: Merchant / Exchanger NPCs and Gold from creatures.
	{ name = "ShopService", layer = 6 },
	-- D-119: the Warden's trial chain (after ShopService: its NPC).
	{ name = "ChainQuestService", layer = 6 },
	-- D-120: the Fortune Wheel (after ShopService: its NPC).
	{ name = "RouletteService", layer = 6 },
	-- D-121: player-to-player trading.
	{ name = "TradeService", layer = 6 },
	-- D-122: the cross-server Auction market (after ShopService: its NPC).
	{ name = "AuctionService", layer = 6 },
	-- D-128: the Puzzle Sage (after ShopService: its NPC).
	{ name = "PuzzleService", layer = 6 },
	-- D-131: the Tower Challenge (after ShopService: its NPC; EventService
	-- opens it).
	{ name = "TowerService", layer = 6 },
	-- D-115: character slots (switch / create / delete).
	{ name = "CharacterService", layer = 6 },
	-- Phase 17 (D-77): the admin panel uses the services below it.
	-- D-112: panel-assigned staff and their pay (AdminService reads it).
	{ name = "StaffService", layer = 7 },
	{ name = "AdminService", layer = 7 },
}
