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
		-- Players may switch on hands-free Auto-attack (creator review
		-- 2026-10-24). Off hides the switch and stops it for everyone.
		AutoAttack = true,
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

	-- Phase 17 admin panel (D-77). Not editable from the panel.
	Admin = {
		-- Studio play-tests only: the local-server test player "Player1"
		-- (UserId -1) is Owner and Player2 stays a normal player, so both
		-- the panel and the refusals can be tried. Play Solo uses Roles
		-- (the creator is Owner). Live servers always use Roles.
		StudioPlayer1Owner = true,
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
		-- Rest regen (creator review 2026-10-17): out of combat for
		-- RegenDelaySeconds with no creature within RestCreatureRadius studs,
		-- players also recover this % of max HP per second anywhere.
		RestRegenPctPerSecond = 2,
		RestCreatureRadius = 40,
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

	-- Phase 5 skills (PLAN.md D-45; SECURITY_MODEL T-03/T-04).
	Skills = {
		-- Seconds between any two skill casts.
		GlobalCooldownSeconds = 0.6,
		-- Casts this early (network jitter) still count as off cooldown.
		CooldownSlackSeconds = 0.15,
		-- Crowd control lasts this fraction as long when a player hits a player.
		PvPControlScale = 0.5,
		-- After a stun / freeze ends, a player can't be stunned / frozen again this long.
		ControlImmunitySeconds = 3,
		-- Area skills: targets per wave (also capped per skill).
		MaxAreaTargets = 10,
		-- Studio play-tests only (RunService:IsStudio()): set true / raise to
		-- learn skills at any level with extra points and try the whole tree.
		-- Off by default so Studio shows the real level gates (creator review
		-- 2026-10-17); live servers always use them and 1 point per level.
		StudioUnlockAll = false,
		StudioBonusPoints = 0,
		-- Resetting the tree (free) is allowed only in a safe zone, out of combat.
		ResetNeedsSafeZone = true,
		-- D-105: the free Reset buttons. Off: the skill tree's Reset uses a
		-- Scroll of Relearning, the attributes' Reset a Scroll of Rebirth.
		FreeTreeReset = true,
		FreeAttributeReset = true,
		-- D-103 combat modernization (creator decisions 2026-10-26).
		-- Extender: seconds after an area skill's last wave it can still be extended.
		ExtendWindowSeconds = 4,
		-- Extender: the widest an extended area may grow (studs).
		ExtendMaxRadius = 30,
		-- Reflect: at most this % of the reflector's max HP per hit, and this
		-- share of it between players.
		ReflectCapPctOfMaxHp = 25,
		PvPReflectScale = 0.5,
		-- Immune (Healer ultimate): between players it only cuts damage by this %.
		ImmunePvPCutPct = 60,
		-- Execute combos finish normal creatures at once (never bosses or players).
		ExecuteCreatures = true,
		-- Ultimates' per-attribute-point bonus is capped at this % in total.
		AttributeBonusCapPct = 100,
	},

	-- Movement modes (Walk / Sprint / Crouch). Speeds are server-set so the
	-- movement validator always knows the legitimate speed.
	Movement = {
		WalkSpeed = 16,
		SprintSpeed = 25,
		CrouchSpeed = 8,
		-- Sprinting spends Focus while moving; it stops when Focus runs out.
		SprintFocusPerSecond = 6,
		SprintMinFocus = 10,
	},

	-- Phase 9 dungeons (PLAN.md D-20, D-32).
	Dungeon = {
		Enabled = true,
		-- D-42: one persistent dungeon per realm; creatures respawn on timers.
		MobRespawnSeconds = 45,
		MiniBossRespawnMinutes = 20,
		-- D-47: floor bosses (they guard the way down; nothing is sealed).
		FloorBossRespawnMinutes = 30,
		BossRespawnHours = 3,
		-- Studio play-tests only (RunService:IsStudio()): short boss timers.
		StudioMiniBossRespawnSeconds = 60,
		StudioFloorBossRespawnSeconds = 120,
		StudioBossRespawnSeconds = 180,
		-- D-32: party members within this distance share kill EXP.
		XpShareRadius = 150,
		-- With no living player in the boss room this long, an engaged boss resets.
		WipeResetSeconds = 6,
	},

	-- Parties (D-39): leader invites, members accept.
	Party = {
		MaxMembers = 4,
		InviteSeconds = 45,
		-- D-48: party leaders join up to this many parties into a union.
		UnionMaxParties = 4,
	},

	-- War zones (Phase 12/13; PLAN.md D-16, SECURITY_MODEL T-15/T-17/T-18).
	PvP = {
		-- D-16: portal access (Quest 4 is added with the quest system, Phase 11).
		MinLevel = 10,
		-- Studio play-tests only (RunService:IsStudio()), so the zone can be
		-- tested without grinding; live servers always use MinLevel.
		StudioMinLevel = 1,
		-- D-16: damage normalization against lower-level players.
		LevelGap = 5,
		PortalReach = 18,
		-- T-18 victory credit rules.
		RepeatVictimMinutes = 30,
		DailyCreditCap = 50,
		-- GD-10 / D-76: no credit for a victim whose spawn protection ended
		-- less than this long ago (anti-spawn-camping).
		FreshSpawnGraceSeconds = 15,
		-- D-76 PvP Marks: per credited victory, and per war-zone boss earned
		-- (once per boss spawn).
		MarksPerVictory = 5,
		MarksPerBoss = 10,
		-- Field creature camps.
		CampRespawnSeconds = 30,
		-- D-49: the five war-zone bosses per zone return this long after falling.
		BossRespawnMinutes = 45,
		StudioBossRespawnSeconds = 120,
		-- D-108: camp guardians strike players of the other realm who come
		-- within GuardRadius studs of a camp's centre (the camp ring is 40),
		-- for GuardHitPct of their max HP every GuardHitSeconds. No PvP credit.
		Guards = true,
		GuardRadius = 110,
		GuardHitPct = 20,
		GuardHitSeconds = 1,
	},

	-- Equipment overhaul stage 4 (D-70): every character gets the smooth
	-- Base Body (Appearance/BodyStyle), keeping head, face, hair and skin.
	-- D-100: realms and jobs with an anime archetype (AnimeArchetypes) are
	-- built from Parts in the anime style; the rest keep the classic look.
	-- Phase 23 (D-102): how often PerfService logs the performance report.
	Perf = {
		ReportSeconds = 60,
	},

	Appearance = {
		SmoothBody = true,
		AnimeStyle = true,
	},

	-- D-117: the Merchant (Gold). GearBase: one piece at level 0, x (1 +
	-- level x LevelStepPct %). SellBase x SellPct % is what it pays back,
	-- + EnhanceBonusPct % per enhancement level.
	Shop = {
		Enabled = true,
		PotionPrice = 40,
		GearBase = { Standard = 80, Uncommon = 200, Rare = 800 },
		SellBase = {
			Standard = 80,
			Uncommon = 200,
			Rare = 800,
			Epic = 2500,
			Legendary = 6000,
			Mythical = 15000,
		},
		LevelStepPct = 25,
		SellPct = 20,
		EnhanceBonusPct = 10,
	},
	-- D-118: gear durability (Constants.Durability.Max = 100). Wear per
	-- creature whose EXP the owner earns; % of the maximum on defeat (by a
	-- player only if PvPDefeatWear). Repair: missing points x the rarity's
	-- Gold per point x (1 + item level x RepairLevelStepPct %).
	Durability = {
		Enabled = true,
		WeaponWearPerKill = 0.5,
		ArmorWearPerKill = 0.2,
		DefeatWearPct = 10,
		PvPDefeatWear = false,
		RepairGoldPerPoint = { Standard = 1, Uncommon = 2, Rare = 4, Epic = 8, Legendary = 15, Mythical = 30 },
		RepairLevelStepPct = 10,
	},
	-- D-121: player trading. Both players: this level or more, inside a
	-- safe zone, within Reach studs of each other; same realm unless
	-- CrossRealm.
	Trade = {
		Enabled = true,
		MinLevel = 5,
		Reach = 30,
		CrossRealm = false,
	},
	-- D-120: the Fortune Wheel. Free spins a day per character, then Gold
	-- (never Robux / Mall Points). Weights out of 100, must add up to 100.
	Roulette = {
		Enabled = true,
		FreeSpinsPerDay = 1,
		GoldPerSpin = 500,
		Weights = {
			ThankYou = 40,
			Standard = 25,
			Rare = 17,
			Consumable = 10,
			Attribute = 4,
			Level = 2,
			Legendary = 2,
		},
	},
	-- D-119: the Warden's trial chain. CollectChancePct: chance a Collect
	-- step's creature drops its trophy; CooldownHours between chains.
	ChainQuest = {
		Enabled = true,
		MinLevel = 25,
		CollectChancePct = 50,
		CooldownHours = 20,
	},
	-- D-117: the Exchanger. 1 MP -> GoldPerMallPoint Gold; 1 MP costs
	-- GoldForMallPoint Gold. Daily limits in Mall Points per account (0 =
	-- none).
	Exchange = {
		Enabled = true,
		GoldPerMallPoint = 100,
		GoldForMallPoint = 400,
		DailyMallPointsToGold = 0,
		DailyGoldToMallPoints = 50,
	},

	-- D-109: Item Mall prices in Mall Points, by catalog id (admin). Must
	-- list every MallDefinitions entry (tested); a missing id falls back to
	-- the catalog price.
	Mall = {
		Prices = {
			Insight = 60,
			Fortune = 80,
			StoneSeeker = 60,
			Might = 50,
			Iron = 50,
			Vigor = 50,
			Clarity = 40,
			Rebirth = 100,
			Relearn = 100,
			RaceRune = 1500,
			Potions10 = 30,
			GreaterPotions10 = 60,
			MajorPotions10 = 100,
			SupremePotions10 = 160,
			Perfect1 = 150,
			Perfect5 = 700,
			LegendarySet = 2500,
		},
	},

	-- Phase 10 dungeon loot (D-06 / D-07 / D-67). Each table: the chance
	-- anything drops, then rarity weights (must sum to 100; an invalid table
	-- is rejected and the built-in default used). CLAUDE.md §12
	-- interpretation: a regular mob's "30% rare / 70% rare" means 30% Rare /
	-- 70% Standard-or-Uncommon, split 45 / 25 (D-07); bosses 20% Legendary /
	-- 80% Rare and always drop. Elites (⭐) drop more often (D-06).
	Loot = {
		-- D-117: Gold from creatures, as a % of their EXP (split like EXP).
		GoldPctOfXp = 25,
		Tables = {
			DungeonMob = { DropChancePct = 12, Rarity = { Standard = 45, Uncommon = 25, Rare = 30 } },
			DungeonElite = { DropChancePct = 35, Rarity = { Standard = 45, Uncommon = 25, Rare = 30 } },
			DungeonMiniBoss = { DropChancePct = 100, Rarity = { Rare = 80, Legendary = 20 } },
			DungeonFloorBoss = { DropChancePct = 100, Rarity = { Rare = 80, Legendary = 20 } },
			DungeonBoss = { DropChancePct = 100, Rarity = { Rare = 80, Legendary = 20 } },
			-- CLAUDE.md §15 PvP boss (the ten war-zone bosses, D-49 / D-76).
			WarZoneBoss = { DropChancePct = 100, Rarity = { Rare = 80, Mythical = 20 } },
		},
		-- CLAUDE.md §15 PvP regular creatures: given a drop, 30% Perfect
		-- Enhancement Stone / 70% Enhancement Stone. The 25% drop chance is
		-- ours (D-76, like D-06 for dungeons); every helper rolls personally.
		StoneTables = {
			WarZoneMob = { DropChancePct = 25, Stones = { PerfectStone = 30, EnhancementStone = 70 } },
		},
	},

	-- Phase 8 (D-08 / D-66): percent chance to reach +1 … +10 with an
	-- Enhancement Stone (a Perfect Stone always succeeds). Shown to players.
	Enhancement = {
		RatesPct = { 100, 100, 100, 100, 100, 90, 80, 70, 60, 50 },
	},

	-- Phase 18 live events (D-89, D-12): running and scheduled windows
	-- { Id, StartsAt, EndsAt, By } in UTC seconds. Written by the admin
	-- panel's Events tab (EventService), never by the settings editor.
	Events = {
		Windows = {},
		-- D-113: one random event a day at a set time (off until an admin
		-- turns it on). 12:00 UTC = 20:00 in UTC+8. Excluded: events the
		-- admin unticked.
		Daily = {
			Enabled = false,
			TimeUtcMinutes = 720,
			Minutes = 60,
			Excluded = {},
		},
	},

	-- Server mob AI (ARCHITECTURE.md §7: one scheduler, ≤ 10 Hz, sleep when idle).
	-- Phase 11 (D-73): story quests.
	Quests = {
		Enabled = true,
		-- Quest unlocks (dungeon gate, enhancement, war-zone gates, D-73)
		-- also apply in Studio when true; off so testers aren't locked out.
		GatesInStudio = false,
		-- Visit / zone checks per second for players with such a step.
		PollHz = 2,
	},

	Mobs = {
		TickHz = 8,
		SleepRadius = 150,
		-- Training Grounds sprites per capital, and their respawn delay.
		TrainingSprites = 5,
		TrainingRespawnSeconds = 8,
	},

	-- SECURITY_MODEL §5A.2 movement validation. Shadow = log only (Phase 6).
	-- Phase 21 (D-97): Enforce (was Shadow, logging only, since Phase 6):
	-- speed / teleport / fly cheats are rubber-banded. Every legitimate
	-- server move grants grace or a speed allowance first (TravelService,
	-- PvPService, dashes, lunges, run / crouch changes).
	AntiExploit = {
		Mode = "Enforce",
		SampleHz = 10,
		SpeedFactor = 1.25,
		SpeedToleranceStuds = 4,
		MaxAirSeconds = 3,
		RubberBandPoints = 3,
		StrikePoints = 10,
		TeleportStuds = 150,
		-- D-97: this many tampered requests (StrikeRules) within the window
		-- kick the player (logged, no ban).
		TamperKickCount = 20,
		TamperWindowSeconds = 60,
	},
}
