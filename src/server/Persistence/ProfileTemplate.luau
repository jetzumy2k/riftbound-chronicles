--!strict
--[[
	ProfileTemplate — player profile schema v2 (docs/DATA_MODEL.md §2).
	v2 (Phase 5, D-45): OwnedSkills maps skill id -> rank (skill tree).
	v3 (equipment overhaul, D-68): the "Accessory" equipment slot is "Necklace".
	v4 (character slots, D-115): Characters / ActiveSlot (Persistence/
	CharacterSlots). The top level stays the played character.
	HeadStyle (D-72) and Attributes / AttributeResetAt (D-90) need no
	migration: a missing field is filled with the default on load
	(ProfileValidator).

	`new()` returns a fresh deep copy. Fields owned by later phases ship as empty
	defaults so those phases can fill them without a migration.

	Pure module: no engine APIs beyond requires (tests load it via tests/pure/loader).
]]

local ProfileTemplate = {}

ProfileTemplate.SCHEMA_VERSION = 4

-- Top-level keys that are allowed to be nil, with their expected type.
ProfileTemplate.OPTIONAL_KEYS = table.freeze({
	Race = "string",
	Job = "string",
	EquippedTitle = "string",
	-- D-115: the slot to switch to on the next load.
	PendingSlot = "number",
	-- D-116: the realm the account converts to on the next load.
	PendingRace = "string",
})

-- Whitelisted lifetime counter keys (DATA_MODEL.md §2). Later phases add keys.
ProfileTemplate.COUNTER_KEYS = table.freeze({} :: { [string]: true })

function ProfileTemplate.new(): { [string]: any }
	return {
		SchemaVersion = ProfileTemplate.SCHEMA_VERSION,
		CreatedAt = 0,
		LastLoginAt = 0,
		-- D-111: the last system reset applied to this profile.
		ResetVersion = 0,

		-- D-115: the other characters ("<slot>" -> stored character) and
		-- the slot the top level belongs to.
		Characters = {},
		ActiveSlot = 1,

		-- D-117: Mall Points moved by the Exchanger today (UTC day number),
		-- per direction (account-wide, for the daily limits).
		ExchangeDay = { Day = 0, ToGold = 0, ToMallPoints = 0 },

		-- Identity (Phase 3/4). Race and Job are nil until chosen.
		FacePreset = 1,
		-- D-72: the adult head (Enums.HeadStyle), changeable any time.
		HeadStyle = "Man",
		-- D-101: the anime look's skin tone and hair colour (Complexion ids;
		-- "Default" = the realm's), changeable any time.
		SkinTone = "Default",
		HairColor = "Default",

		-- Progression (Phase 2)
		Level = 0,
		Experience = 0,
		TotalExperience = 0,

		-- D-90: attribute points spent (Logic/AttributeRules; 5 per level),
		-- and when they were last reset (UTC seconds; one free reset a day).
		Attributes = { REC = 0, INT = 0, WIS = 0, STR = 0, AGI = 0 },
		AttributeResetAt = 0,

		-- Skills (Phase 5, D-45): learned skill id -> rank, and the 6 + 1 bar (D-75).
		OwnedSkills = {},
		EquippedSkills = { Regular = {} },

		-- Items (Phase 7/8)
		Inventory = {},
		Equipment = {},
		Stackables = {},
		-- D-93: MallPoints bought with Robux (MallService) or given by events.
		-- PurchasedMallPoints: lifetime points bought with Robux (D-111: a
		-- system reset never takes those).
		Wallet = { Gold = 0, PvPMarks = 0, MallPoints = 0, PurchasedMallPoints = 0 },
		-- D-93: running Mall buffs, buff id -> expiry (UTC seconds; BuffRules).
		Buffs = {},

		-- Quests and story (Phase 11)
		QuestState = {},
		StoryFlags = {},
		ClaimedRewardIds = {},

		-- Cosmetics (Phase 11/14)
		Titles = {},
		Cosmetics = {},
		EquippedCosmetics = {},

		-- D-120: permanent attribute points from the Fortune Wheel (not
		-- refunded by resets), and today's free spins.
		BonusAttributes = { REC = 0, INT = 0, WIS = 0, STR = 0, AGI = 0 },
		Roulette = { Day = 0, Used = 0 },

		-- D-122: items / Gold on their way into the auction (key -> entry),
		-- kept until the shared store confirms it (AuctionService).
		Escrow = {},

		-- D-121: the last trades (newest first), as evidence for reports.
		TradeHistory = {},

		-- D-119: the Warden's trial chain (Logic/ChainRules).
		Chain = { Active = false, Step = 1, Progress = 0, CompletedAt = 0, Cycles = 0 },

		-- PvP (Phase 12/14)
		PvPStats = {
			Victories = 0,
			Defeats = 0,
			Participations = 0,
			RecentVictims = {},
			DailyCredit = { Day = 0, Count = 0 },
		},

		-- Events (Phase 18)
		EventProgress = {},

		-- Moderation flags (Phase 17)
		Restrictions = {},

		Settings = {
			MusicVolume = 70,
			SfxVolume = 80,
			GraphicsTier = "Auto",
			ShowDamageNumbers = true,
			-- D-74: HUD pieces the player moved (Layout/HudSlots).
			HudLayout = {},
			-- D-126: which potion the quick button (H) drinks.
			QuickPotion = "Auto",
		},

		Counters = {},
	}
end

return table.freeze(ProfileTemplate)
