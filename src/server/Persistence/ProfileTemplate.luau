--!strict
--[[
	ProfileTemplate — player profile schema v1 (docs/DATA_MODEL.md §2).

	`new()` returns a fresh deep copy. Fields owned by later phases ship as empty
	defaults so those phases can fill them without a migration.

	Pure module: no engine APIs beyond requires (tests load it via tests/pure/loader).
]]

local ProfileTemplate = {}

ProfileTemplate.SCHEMA_VERSION = 1

-- Top-level keys that are allowed to be nil, with their expected type.
ProfileTemplate.OPTIONAL_KEYS = table.freeze({
	Race = "string",
	Job = "string",
	EquippedTitle = "string",
})

-- Whitelisted lifetime counter keys (DATA_MODEL.md §2). Later phases add keys.
ProfileTemplate.COUNTER_KEYS = table.freeze({} :: { [string]: true })

function ProfileTemplate.new(): { [string]: any }
	return {
		SchemaVersion = ProfileTemplate.SCHEMA_VERSION,
		CreatedAt = 0,
		LastLoginAt = 0,

		-- Identity (Phase 3/4). Race and Job are nil until chosen.
		FacePreset = 1,

		-- Progression (Phase 2)
		Level = 0,
		Experience = 0,
		TotalExperience = 0,

		-- Skills (Phase 5)
		OwnedSkills = {},
		EquippedSkills = { Regular = {} },

		-- Items (Phase 7/8)
		Inventory = {},
		Equipment = {},
		Stackables = {},
		Wallet = { Gold = 0, PvPMarks = 0 },

		-- Quests and story (Phase 11)
		QuestState = {},
		StoryFlags = {},
		ClaimedRewardIds = {},

		-- Cosmetics (Phase 11/14)
		Titles = {},
		Cosmetics = {},
		EquippedCosmetics = {},

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
		},

		Counters = {},
	}
end

return table.freeze(ProfileTemplate)
