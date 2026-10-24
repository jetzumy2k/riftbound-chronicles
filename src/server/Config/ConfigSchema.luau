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
			AutoAttack = S.boolean(),
		}),

		Net = S.struct({
			GlobalCapacity = S.int(5, 500),
			GlobalRefillPerSecond = S.number(1, 500),
			SecurityLogThrottleSeconds = S.number(1, 600),
		}),

		Config = S.struct({
			PollSeconds = S.int(30, 3600),
		}),

		Admin = S.struct({
			StudioPlayer1Owner = S.boolean(),
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
			RestRegenPctPerSecond = S.number(0, 20),
			RestCreatureRadius = S.number(0, 200),
			FocusMax = S.int(10, 1000),
			FocusRegenPerSecond = S.number(0, 200),
			RangeToleranceStuds = S.number(0, 20),
			MaxPingCompensationSeconds = S.number(0, 1),
			ResetCooldownSeconds = S.number(0, 300),
			RelevanceRadius = S.number(20, 1000),
		}),

		Skills = S.struct({
			GlobalCooldownSeconds = S.number(0, 5),
			CooldownSlackSeconds = S.number(0, 1),
			PvPControlScale = S.number(0, 1),
			ControlImmunitySeconds = S.number(0, 10),
			MaxAreaTargets = S.int(1, 50),
			StudioUnlockAll = S.boolean(),
			StudioBonusPoints = S.int(0, 200),
			ResetNeedsSafeZone = S.boolean(),
		}),

		Appearance = S.struct({
			SmoothBody = S.boolean(),
		}),

		Loot = S.struct({
			-- LootRules.validate also checks the weights sum to 100.
			Tables = S.map(
				S.enum({
					"DungeonMob",
					"DungeonElite",
					"DungeonMiniBoss",
					"DungeonFloorBoss",
					"DungeonBoss",
					"WarZoneBoss",
				}),
				S.struct({
					DropChancePct = S.number(0, 100),
					Rarity = S.map(
						S.enum({ "Standard", "Uncommon", "Rare", "Epic", "Legendary", "Mythical" }),
						S.number(0, 100),
						6
					),
				}),
				6
			),
			-- LootRules.validateStones also checks the weights sum to 100.
			StoneTables = S.map(
				S.enum({ "WarZoneMob" }),
				S.struct({
					DropChancePct = S.number(0, 100),
					Stones = S.map(S.enum({ "EnhancementStone", "PerfectStone" }), S.number(0, 100), 2),
				}),
				1
			),
		}),

		Enhancement = S.struct({
			-- One rate per level (+1 … +10); EnhanceRules falls back to the
			-- D-08 defaults if the list is not exactly 10 long.
			RatesPct = S.array(S.number(0, 100), 10),
		}),

		Movement = S.struct({
			WalkSpeed = S.number(4, 40),
			SprintSpeed = S.number(4, 60),
			CrouchSpeed = S.number(2, 40),
			SprintFocusPerSecond = S.number(0, 100),
			SprintMinFocus = S.number(0, 1000),
		}),

		Dungeon = S.struct({
			Enabled = S.boolean(),
			MobRespawnSeconds = S.number(5, 3600),
			MiniBossRespawnMinutes = S.number(1, 1440),
			FloorBossRespawnMinutes = S.number(1, 1440),
			BossRespawnHours = S.number(0.1, 72),
			StudioMiniBossRespawnSeconds = S.number(5, 3600),
			StudioFloorBossRespawnSeconds = S.number(5, 7200),
			StudioBossRespawnSeconds = S.number(5, 7200),
			XpShareRadius = S.number(10, 1000),
			WipeResetSeconds = S.number(1, 60),
		}),

		Party = S.struct({
			MaxMembers = S.int(1, 8),
			InviteSeconds = S.number(5, 600),
			UnionMaxParties = S.int(2, 8),
		}),

		PvP = S.struct({
			MinLevel = S.int(0, 30),
			StudioMinLevel = S.int(0, 30),
			LevelGap = S.int(0, 30),
			PortalReach = S.number(4, 60),
			RepeatVictimMinutes = S.number(0, 1440),
			DailyCreditCap = S.int(0, 1000),
			FreshSpawnGraceSeconds = S.number(0, 300),
			MarksPerVictory = S.int(0, 1000),
			MarksPerBoss = S.int(0, 1000),
			CampRespawnSeconds = S.number(5, 600),
			BossRespawnMinutes = S.number(1, 1440),
			StudioBossRespawnSeconds = S.number(5, 7200),
		}),

		Quests = S.struct({
			Enabled = S.boolean(),
			GatesInStudio = S.boolean(),
			PollHz = S.number(0.5, 10),
		}),

		Mobs = S.struct({
			TickHz = S.int(1, 10),
			SleepRadius = S.number(20, 1000),
			TrainingSprites = S.int(0, 20),
			TrainingRespawnSeconds = S.number(1, 300),
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
