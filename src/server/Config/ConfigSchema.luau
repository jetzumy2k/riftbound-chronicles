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
			FreeTreeReset = S.boolean(),
			FreeAttributeReset = S.boolean(),
			ExtendWindowSeconds = S.number(0, 15),
			ExtendMaxRadius = S.number(5, 40),
			ReflectCapPctOfMaxHp = S.number(0, 100),
			PvPReflectScale = S.number(0, 1),
			ImmunePvPCutPct = S.number(0, 90),
			ExecuteCreatures = S.boolean(),
			AttributeBonusCapPct = S.number(0, 200),
		}),

		Perf = S.struct({
			ReportSeconds = S.int(10, 3600),
		}),

		Appearance = S.struct({
			SmoothBody = S.boolean(),
			AnimeStyle = S.boolean(),
		}),

		Shop = S.struct({
			Enabled = S.boolean(),
			PotionPrice = S.int(1, 1000000),
			GearBase = S.map(S.enum({ "Standard", "Uncommon", "Rare" }), S.int(1, 10000000), 3),
			SellBase = S.map(
				S.enum({ "Standard", "Uncommon", "Rare", "Epic", "Legendary", "Mythical" }),
				S.int(0, 10000000),
				6
			),
			LevelStepPct = S.int(0, 500),
			SellPct = S.int(0, 100),
			EnhanceBonusPct = S.int(0, 100),
		}),

		Durability = S.struct({
			Enabled = S.boolean(),
			WeaponWearPerKill = S.number(0, 100),
			ArmorWearPerKill = S.number(0, 100),
			DefeatWearPct = S.number(0, 100),
			PvPDefeatWear = S.boolean(),
			RepairGoldPerPoint = S.map(
				S.enum({ "Standard", "Uncommon", "Rare", "Epic", "Legendary", "Mythical" }),
				S.number(0, 100000),
				6
			),
			RepairLevelStepPct = S.int(0, 500),
		}),

		Trade = S.struct({
			Enabled = S.boolean(),
			MinLevel = S.int(0, 30),
			Reach = S.number(5, 200),
			CrossRealm = S.boolean(),
		}),

		Roulette = S.struct({
			Enabled = S.boolean(),
			FreeSpinsPerDay = S.int(0, 20),
			GoldPerSpin = S.int(1, 10000000),
			-- RouletteRules.validate also checks they add up to 100.
			Weights = S.map(
				S.enum({ "ThankYou", "Standard", "Rare", "Consumable", "Attribute", "Level", "Legendary" }),
				S.int(0, 100),
				7
			),
		}),

		ChainQuest = S.struct({
			Enabled = S.boolean(),
			MinLevel = S.int(0, 30),
			CollectChancePct = S.int(1, 100),
			CooldownHours = S.number(0, 720),
		}),

		Exchange = S.struct({
			Enabled = S.boolean(),
			GoldPerMallPoint = S.int(1, 1000000),
			GoldForMallPoint = S.int(1, 1000000),
			DailyMallPointsToGold = S.int(0, 1000000),
			DailyGoldToMallPoints = S.int(0, 1000000),
		}),

		Mall = S.struct({
			Prices = S.map(S.string(32, 1), S.int(1, 1000000), 64),
		}),

		Loot = S.struct({
			GoldPctOfXp = S.number(0, 1000),
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
			Guards = S.boolean(),
			GuardRadius = S.number(45, 300),
			GuardHitPct = S.number(1, 100),
			GuardHitSeconds = S.number(0.25, 10),
		}),

		Events = S.struct({
			Windows = S.array(
				S.struct({
					Id = S.string(32, 1, "^%w+$"),
					StartsAt = S.int(0),
					EndsAt = S.int(0),
					By = S.int(0),
					-- D-93 stage 2: rewards for playing during the run
					-- (Logic/EventRewards checks the content).
					Rewards = S.optional(S.array(
						S.struct({
							Kind = S.enum({ "MallPoints", "Item", "Set" }),
							Id = S.optional(S.string(32, 1, "^[%w_]+$")),
							Count = S.int(1, 10000),
						}),
						4
					)),
					-- D-113: started by the daily random event.
					Daily = S.optional(S.boolean()),
				}),
				64
			),
			-- D-113: the daily random event (EventRules.Daily).
			Daily = S.struct({
				Enabled = S.boolean(),
				TimeUtcMinutes = S.int(0, 1439),
				Minutes = S.int(15, 1440),
				Excluded = S.array(S.string(32, 1, "^%w+$"), 64),
			}),
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
			TamperKickCount = S.int(3, 1000),
			TamperWindowSeconds = S.number(5, 3600),
		}),
	})
end
