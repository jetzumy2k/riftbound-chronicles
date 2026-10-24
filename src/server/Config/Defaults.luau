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
		-- Field creature camps.
		CampRespawnSeconds = 30,
		-- D-49: the five war-zone bosses per zone return this long after falling.
		BossRespawnMinutes = 45,
		StudioBossRespawnSeconds = 120,
	},

	-- Equipment overhaul stage 4 (D-70): every character gets the smooth
	-- Base Body (Appearance/BodyStyle), keeping head, face, hair and skin.
	Appearance = {
		SmoothBody = true,
	},

	-- Phase 10 dungeon loot (D-06 / D-07 / D-67). Each table: the chance
	-- anything drops, then rarity weights (must sum to 100; an invalid table
	-- is rejected and the built-in default used). CLAUDE.md §12
	-- interpretation: a regular mob's "30% rare / 70% rare" means 30% Rare /
	-- 70% Standard-or-Uncommon, split 45 / 25 (D-07); bosses 20% Legendary /
	-- 80% Rare and always drop. Elites (⭐) drop more often (D-06).
	Loot = {
		Tables = {
			DungeonMob = { DropChancePct = 12, Rarity = { Standard = 45, Uncommon = 25, Rare = 30 } },
			DungeonElite = { DropChancePct = 35, Rarity = { Standard = 45, Uncommon = 25, Rare = 30 } },
			DungeonMiniBoss = { DropChancePct = 100, Rarity = { Rare = 80, Legendary = 20 } },
			DungeonFloorBoss = { DropChancePct = 100, Rarity = { Rare = 80, Legendary = 20 } },
			DungeonBoss = { DropChancePct = 100, Rarity = { Rare = 80, Legendary = 20 } },
		},
	},

	-- Phase 8 (D-08 / D-66): percent chance to reach +1 … +10 with an
	-- Enhancement Stone (a Perfect Stone always succeeds). Shown to players.
	Enhancement = {
		RatesPct = { 100, 100, 100, 100, 100, 90, 80, 70, 60, 50 },
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
