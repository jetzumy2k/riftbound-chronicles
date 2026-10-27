--!strict
--[[
	Registry
	Declares every remote in the game. The server creates remote instances from
	this table at boot; nothing else may create remotes (ARCHITECTURE.md §6).

	Exported as a function of the Schema module so callers share one Schema
	instance. Pure module (tests load it through tests/pure/loader).

	Fields per remote:
	  direction   "ClientToServer" | "ServerToClient"
	  kind        "Event" | "Function"   (Function is allowed ClientToServer only)
	  args        ordered list of Schema specs (trailing optional specs allowed)
	  rate        { capacity, refillPerSecond }  (required for ClientToServer)
	  states      player-state checks that must pass before the handler runs;
	              each name must have a checker registered with NetService
	  permission  admin permission name (Phase 17), checked server-side

	Remotes accepting damage, XP, loot, rarity, quest progress, roles or
	positions must never be added (SECURITY_MODEL.md §6.2 / ARCHITECTURE.md §6.2).
]]

local Enums = require(script.Parent.Parent.Enums)
local Constants = require(script.Parent.Parent.Constants)

local FacePresets = require(script.Parent.Parent.Definitions.FacePresets)
local Complexion = require(script.Parent.Parent.Definitions.Complexion)
local AnimationClips = require(script.Parent.Parent.Definitions.AnimationClips)
local SkillDefinitions = require(script.Parent.Parent.Definitions.SkillDefinitions)
local PassiveDefinitions = require(script.Parent.Parent.Definitions.PassiveDefinitions)
local ItemDefinitions = require(script.Parent.Parent.Definitions.ItemDefinitions)
local ItemRules = require(script.Parent.Parent.Logic.ItemRules)
local QuestDefinitions = require(script.Parent.Parent.Definitions.QuestDefinitions)
local EventDefinitions = require(script.Parent.Parent.Definitions.EventDefinitions)
local AttributeRules = require(script.Parent.Parent.Logic.AttributeRules)
local BuffRules = require(script.Parent.Parent.Logic.BuffRules)
local MallDefinitions = require(script.Parent.Parent.Definitions.MallDefinitions)
local HudSlots = require(script.Parent.Parent.Layout.HudSlots)
local AdminRules = require(script.Parent.Parent.Logic.AdminRules)
local StaffRules = require(script.Parent.Parent.Logic.StaffRules)

local NotifyKind = { "Info", "Warning", "Welcome" }
local MAX_LEVEL = Constants.Level.Max

local ACTION_NAMES = table.clone(AnimationClips.NAMES)
local SKILL_IDS = table.clone(SkillDefinitions.IDS)
-- What LearnSkill accepts and OwnedSkills holds: tree skills + passives (D-104).
local LEARNABLE_IDS = table.clone(SKILL_IDS)
for _, id in PassiveDefinitions.IDS do
	table.insert(LEARNABLE_IDS, id)
end
local COMBO_NAMES = {}
for _, skill in SkillDefinitions.All do
	if skill.combo and table.find(COMBO_NAMES, skill.combo.name) == nil then
		table.insert(COMBO_NAMES, skill.combo.name)
	end
end

local QUEST_IDS = table.clone(QuestDefinitions.IDS)
local TITLE_IDS = {}
for id in QuestDefinitions.Titles do
	table.insert(TITLE_IDS, id)
end
local COSMETIC_IDS = {}
for id in QuestDefinitions.Cosmetics do
	table.insert(COSMETIC_IDS, id)
end
local INTERACTABLE_IDS = {}
for id in QuestDefinitions.Interactables do
	table.insert(INTERACTABLE_IDS, id)
end
table.sort(TITLE_IDS)
table.sort(COSMETIC_IDS)
table.sort(INTERACTABLE_IDS)
local ITEM_IDS = table.clone(ItemDefinitions.IDS)
local STACKABLE_IDS = table.clone(ItemDefinitions.STACKABLE_IDS)
local CONSUMABLE_IDS = table.clone(ItemDefinitions.CONSUMABLE_IDS)
local STAT_IDS = table.clone(ItemRules.STAT_ORDER)
-- Room above the 150 cap so an over-full profile still syncs (grants stop at the cap).
local MAX_ITEMS = 200

return function(S: any)
	-- Phase 7 (D-64): an item as its owner sees it, and the item-side state.
	local guid = S.string(36, 36, "^[%x%-]+$")
	local itemView = S.struct({
		Guid = guid,
		DefId = S.enum(ITEM_IDS),
		Rarity = S.enum(Enums.Rarity),
		ItemLevel = S.int(0, MAX_LEVEL),
		Attributes = S.array(S.struct({ Stat = S.enum(STAT_IDS), Value = S.number(0, 10000000) }), 4),
		Enhancement = S.int(0, Constants.Enhancement.Max),
		Locked = S.boolean(),
		CreatedAt = S.number(0),
	})
	local equipment = S.map(S.enum(Enums.ItemSlot), guid, 12)
	local stackables = S.map(S.enum(STACKABLE_IDS), S.int(0), 16)
	local wallet = S.struct({ Gold = S.int(0), PvPMarks = S.int(0), MallPoints = S.optional(S.int(0)) })
	-- D-93: running buffs, id -> seconds left.
	local buffsView = S.map(S.enum(table.clone(BuffRules.IDS)), S.int(0, 6 * 3600), 16)
	-- D-74: moved HUD pieces, centre as a screen fraction.
	local hudLayout = S.map(
		S.enum(table.clone(HudSlots.IDS)),
		S.struct({ X = S.number(0, 1), Y = S.number(0, 1) }),
		#HudSlots.IDS
	)
	-- D-90: attribute points spent and seconds to the next free reset.
	local points = S.int(0, 10000)
	local attributesView = S.struct({
		Attributes = S.struct({ REC = points, INT = points, WIS = points, STR = points, AGI = points }),
		ResetIn = S.int(0, 24 * 3600),
	})
	-- Phase 11 (D-73): the owner's quests and story state (ProfileView.quests).
	local questsView = S.struct({
		Quests = S.map(
			S.enum(QUEST_IDS),
			S.struct({
				Status = S.enum({ "Active", "ReadyToTurnIn", "Completed" }),
				Objectives = S.map(S.string(32, 1, "^[%w_]+$"), S.int(0, 1000), 8),
				Found = S.array(S.enum(INTERACTABLE_IDS), 16),
			}),
			32
		),
		Flags = S.array(S.string(32, 1, "^[%w_]+$"), 32),
		Titles = S.array(S.enum(TITLE_IDS), 32),
		EquippedTitle = S.optional(S.enum(TITLE_IDS)),
		Cosmetics = S.array(S.enum(COSMETIC_IDS), 32),
	})

	return {
		-- Client tells the server its controllers are initialised and it can
		-- receive pushes. Handled by NetService itself.
		ClientReady = {
			direction = "ClientToServer",
			kind = "Event",
			args = {},
			rate = { capacity = 2, refillPerSecond = 0.05 },
			states = {},
		},

		-- First-time race choice (Phase 3). One-shot: the server rejects it once a
		-- race is set. The preset id must belong to the chosen race (checked by
		-- RaceService against FacePresets; the client never sends asset ids).
		SelectRace = {
			direction = "ClientToServer",
			kind = "Event",
			args = { S.enum(Enums.Race), S.int(1, FacePresets.maxId()) },
			rate = { capacity = 3, refillPerSecond = 0.2 },
			states = { "ProfileLoaded" },
		},

		-- The adult head (D-72): any time after the profile loads (realm
		-- screen and bag). The server re-applies the body; rate-limited
		-- because each change rebuilds the character's appearance.
		SetHeadStyle = {
			direction = "ClientToServer",
			kind = "Event",
			args = { S.enum(Enums.HeadStyle) },
			rate = { capacity = 2, refillPerSecond = 0.2 },
			states = { "ProfileLoaded" },
		},

		-- The anime look's skin tone / hair colour (D-101): allowlisted ids
		-- only (Complexion); the server checks the id belongs to the kind.
		-- The client batches taps, so a few per second at most.
		SetComplexion = {
			direction = "ClientToServer",
			kind = "Event",
			args = { S.enum(Complexion.KINDS), S.enum(Complexion.ALL_IDS) },
			rate = { capacity = 4, refillPerSecond = 0.5 },
			states = { "ProfileLoaded" },
		},

		-- Phase 11 (D-73): accept / turn in a quest at your realm's quest
		-- giver (server checks reach, prerequisites, level and status; the
		-- rewards are claimed once as "Q:<id>"). There is no progress remote.
		QuestAccept = {
			direction = "ClientToServer",
			kind = "Event",
			args = { S.enum(QUEST_IDS) },
			rate = { capacity = 4, refillPerSecond = 0.5 },
			states = { "ProfileLoaded", "HasJob" },
		},
		QuestTurnIn = {
			direction = "ClientToServer",
			kind = "Event",
			args = { S.enum(QUEST_IDS) },
			rate = { capacity = 4, refillPerSecond = 0.5 },
			states = { "ProfileLoaded", "HasJob" },
		},
		-- D-74: save where the player moved their HUD pieces (display only;
		-- known ids, numbers 0..1).
		SetHudLayout = {
			direction = "ClientToServer",
			kind = "Event",
			args = { hudLayout },
			rate = { capacity = 3, refillPerSecond = 0.1 },
			states = { "ProfileLoaded" },
		},

		-- Wear an owned title (or none). Display only.
		EquipTitle = {
			direction = "ClientToServer",
			kind = "Event",
			args = { S.optional(S.enum(TITLE_IDS)) },
			rate = { capacity = 4, refillPerSecond = 0.5 },
			states = { "ProfileLoaded" },
		},

		-- First-time job choice (Phase 4). One-shot, after a race is chosen.
		-- Job changes are an admin action (PLAN.md D-21).
		SelectJob = {
			direction = "ClientToServer",
			kind = "Event",
			args = { S.enum(Enums.Job) },
			rate = { capacity = 3, refillPerSecond = 0.2 },
			states = { "ProfileLoaded", "HasRace" },
		},

		-- Basic attack intent (Phase 6). Optional target model; the server picks
		-- the nearest hostile in front if omitted, and validates everything:
		-- cooldown, hostility, safe zones, protection, range, line of sight.
		BasicAttack = {
			direction = "ClientToServer",
			kind = "Event",
			args = { S.optional(S.instance("Model")) },
			rate = { capacity = 6, refillPerSecond = 4 },
			states = { "ProfileLoaded", "HasJob", "Alive" },
		},

		-- Skill cast intent (Phase 5). The skill must be equipped; the optional
		-- target is a hint (enemy or ally model; dashes are moved by the client
		-- within a server-granted speed allowance). The server checks ownership, job, loadout,
		-- level, cooldown, Focus, stun, target, range and line of sight, and
		-- computes every effect (SECURITY_MODEL T-02/T-03/T-04).
		SkillCast = {
			direction = "ClientToServer",
			kind = "Event",
			args = { S.enum(SKILL_IDS), S.optional(S.instance("Model")) },
			rate = { capacity = 4, refillPerSecond = 2.5 },
			states = { "ProfileLoaded", "HasJob", "Alive" },
		},

		-- Skill tree (D-45): spend one skill point to learn a skill or raise
		-- its rank. The server checks job, level, prerequisite, points, rank.
		LearnSkill = {
			direction = "ClientToServer",
			kind = "Event",
			args = { S.enum(LEARNABLE_IDS) },
			rate = { capacity = 6, refillPerSecond = 2 },
			states = { "ProfileLoaded", "HasJob" },
		},

		-- Skill tree reset (D-45): refunds every point. Only in a safe zone
		-- and out of combat (checked by the server).
		ResetSkills = {
			direction = "ClientToServer",
			kind = "Event",
			args = {},
			rate = { capacity = 2, refillPerSecond = 0.1 },
			states = { "ProfileLoaded", "HasJob" },
		},

		-- Skill loadout intent (Phase 5, D-75): up to 6 regular skills + 1
		-- special. A 7th regular entry fails the schema; SkillService checks
		-- the rest.
		SetLoadout = {
			direction = "ClientToServer",
			kind = "Event",
			args = {
				S.array(S.enum(SKILL_IDS), Constants.Loadout.RegularSlots),
				S.optional(S.enum(SKILL_IDS)),
			},
			rate = { capacity = 4, refillPerSecond = 0.5 },
			states = { "ProfileLoaded", "HasJob" },
		},

		-- Inventory intents (Phase 7, D-64). The server owns every item: it
		-- checks ownership (the guid must be in the caller's own inventory),
		-- job, race weapon family, level, slot, locks and combat state.
		-- D-68: the optional slot picks Ring1 / Ring2, or OffHand for a
		-- second sword (dual swords); the server applies the hand rules.
		EquipItem = {
			direction = "ClientToServer",
			kind = "Event",
			args = { guid, S.optional(S.enum({ "OffHand", "Ring1", "Ring2" })) },
			rate = { capacity = 6, refillPerSecond = 2 },
			states = { "ProfileLoaded", "HasJob" },
		},
		UnequipItem = {
			direction = "ClientToServer",
			kind = "Event",
			args = { S.enum(Enums.ItemSlot) },
			rate = { capacity = 6, refillPerSecond = 2 },
			states = { "ProfileLoaded", "HasJob" },
		},
		-- Salvage up to 25 items at once into Stone Fragments (D-09);
		-- equipped and locked items are refused.
		SalvageItems = {
			direction = "ClientToServer",
			kind = "Event",
			args = { S.array(guid, 25) },
			rate = { capacity = 4, refillPerSecond = 1 },
			states = { "ProfileLoaded", "HasJob" },
		},
		LockItem = {
			direction = "ClientToServer",
			kind = "Event",
			args = { guid, S.boolean() },
			rate = { capacity = 8, refillPerSecond = 3 },
			states = { "ProfileLoaded", "HasJob" },
		},
		-- 10 Stone Fragments -> 1 Enhancement Stone, `count` times (D-09).
		CombineFragments = {
			direction = "ClientToServer",
			kind = "Event",
			args = { S.int(1, 100) },
			rate = { capacity = 4, refillPerSecond = 1 },
			states = { "ProfileLoaded", "HasJob" },
		},
		UseConsumable = {
			direction = "ClientToServer",
			kind = "Event",
			args = { S.enum(CONSUMABLE_IDS) },
			rate = { capacity = 4, refillPerSecond = 1 },
			states = { "ProfileLoaded", "HasJob", "Alive" },
		},
		-- Enhancement intent (Phase 8, D-08 / D-66): the caller's own item
		-- and whether to use a Perfect Stone. The server checks ownership,
		-- the +10 cap and stones, then consumes one stone, rolls and applies
		-- in one synchronous step (SECURITY_MODEL T-11).
		-- D-90: spend attribute points ({ REC = 2, ... }; the server checks
		-- the total against the level) and the free daily reset.
		SpendAttributes = {
			direction = "ClientToServer",
			kind = "Event",
			args = {
				S.struct({
					REC = S.optional(S.int(0, AttributeRules.MAX_STEP)),
					INT = S.optional(S.int(0, AttributeRules.MAX_STEP)),
					WIS = S.optional(S.int(0, AttributeRules.MAX_STEP)),
					STR = S.optional(S.int(0, AttributeRules.MAX_STEP)),
					AGI = S.optional(S.int(0, AttributeRules.MAX_STEP)),
				}),
			},
			rate = { capacity = 10, refillPerSecond = 4 },
			states = { "ProfileLoaded", "HasJob" },
		},
		-- D-93: buy a Mall entry with Mall Points (price and grant from
		-- MallDefinitions on the server; the client only names the entry).
		BuyMallItem = {
			direction = "ClientToServer",
			kind = "Function",
			args = { S.enum(table.clone(MallDefinitions.IDS)) },
			rate = { capacity = 4, refillPerSecond = 1 },
			states = { "ProfileLoaded", "HasJob" },
		},
		ResetAttributes = {
			direction = "ClientToServer",
			kind = "Event",
			args = {},
			rate = { capacity = 2, refillPerSecond = 0.2 },
			states = { "ProfileLoaded", "HasJob" },
		},
		EnhanceItem = {
			direction = "ClientToServer",
			kind = "Event",
			args = { guid, S.boolean() },
			rate = { capacity = 3, refillPerSecond = 2 },
			states = { "ProfileLoaded", "HasJob" },
		},

		-- D-115: the character screen. List the slots; switch to one (an
		-- empty slot starts a new character; the player rejoins); delete one
		-- (needs the typed confirmation).
		CharacterSlots = {
			direction = "ClientToServer",
			kind = "Function",
			args = {
				S.enum({ "List", "Switch", "Delete" }),
				S.optional(S.int(1, Constants.Characters.MaxSlots)),
				S.optional(S.string(10)),
			},
			rate = { capacity = 6, refillPerSecond = 0.5 },
			states = { "ProfileLoaded" },
		},

		-- Admin / moderator panel (Phase 17, D-77, SECURITY_MODEL §6, T-19 /
		-- T-20). Each remote names a permission that NetService checks
		-- server-side (from Roles) before the handler runs; handlers check
		-- the finer permission per action / config path again and audit
		-- every change. These carry staff edits (level, items, rarity,
		-- config), never anything a player decides for themselves.
		AdminPlayers = {
			direction = "ClientToServer",
			kind = "Function",
			args = { S.string(20) },
			rate = { capacity = 6, refillPerSecond = 1 },
			states = { "ProfileLoaded" },
			permission = "player.inspect",
		},
		AdminInspect = {
			direction = "ClientToServer",
			kind = "Function",
			args = { S.int(1, 9007199254740991) },
			rate = { capacity = 6, refillPerSecond = 1 },
			states = { "ProfileLoaded" },
			permission = "player.inspect",
		},
		AdminPlayerAction = {
			direction = "ClientToServer",
			kind = "Function",
			args = {
				S.int(1, 9007199254740991),
				S.enum(AdminRules.ACTIONS),
				S.struct({
					Number = S.optional(S.int(-AdminRules.MAX_CURRENCY_STEP, AdminRules.MAX_CURRENCY_STEP)),
					Currency = S.optional(S.enum({ "Gold", "PvPMarks", "MallPoints" })),
					DefId = S.optional(S.enum(ITEM_IDS)),
					Rarity = S.optional(S.enum(Enums.Rarity)),
					Stackable = S.optional(S.enum(STACKABLE_IDS)),
					Guid = S.optional(guid),
					Quest = S.optional(S.enum(QUEST_IDS)),
					Reason = S.optional(S.enum(AdminRules.REASONS)),
				}),
			},
			rate = { capacity = 6, refillPerSecond = 1 },
			states = { "ProfileLoaded" },
			permission = "panel.open",
		},
		AdminConfigGet = {
			direction = "ClientToServer",
			kind = "Function",
			args = {},
			rate = { capacity = 4, refillPerSecond = 0.5 },
			states = { "ProfileLoaded" },
			permission = "config.view",
		},
		AdminConfigSet = {
			direction = "ClientToServer",
			kind = "Function",
			args = {
				S.int(0),
				S.array(
					S.struct({
						Path = S.string(96, 1, "^[%w%.]+$"),
						Number = S.optional(S.number(-1e9, 1e9)),
						Bool = S.optional(S.boolean()),
						Text = S.optional(S.string(40)),
						Reset = S.optional(S.boolean()),
					}),
					AdminRules.MAX_CHANGES
				),
			},
			rate = { capacity = 3, refillPerSecond = 0.2 },
			states = { "ProfileLoaded" },
			permission = "config.view",
		},
		AdminBoss = {
			direction = "ClientToServer",
			kind = "Function",
			args = { S.enum({ "RespawnAll" }) },
			rate = { capacity = 2, refillPerSecond = 0.1 },
			states = { "ProfileLoaded" },
			permission = "bosses.manage",
		},
		-- Live events (Phase 18, D-89): list the windows, start one now,
		-- schedule one (UTC seconds), stop one. Durations and cooldowns are
		-- checked against the template on the server.
		AdminEvents = {
			direction = "ClientToServer",
			kind = "Function",
			args = {
				S.enum({ "List", "Start", "Schedule", "Stop", "Daily" }),
				S.struct({
					Id = S.optional(S.enum(table.clone(EventDefinitions.IDS))),
					Minutes = S.optional(S.int(1, 30 * 24 * 60)),
					StartsAt = S.optional(S.int(0, 4102444800)),
					-- D-113: the daily random event settings (needs config.game).
					Daily = S.optional(S.struct({
						Enabled = S.boolean(),
						TimeUtcMinutes = S.int(0, 1439),
						Minutes = S.int(15, 1440),
						Excluded = S.array(S.enum(table.clone(EventDefinitions.IDS)), 64),
					})),
					-- D-93 stage 2: rewards for playing during the run (needs
					-- items.grant; EventRewards checks the content).
					Rewards = S.optional(S.array(
						S.struct({
							Kind = S.enum({ "MallPoints", "Item", "Set" }),
							Id = S.optional(S.string(32, 1, "^[%w_]+$")),
							Count = S.int(1, 10000),
						}),
						4
					)),
				}),
			},
			rate = { capacity = 10, refillPerSecond = 1 },
			states = { "ProfileLoaded" },
			permission = "events.activate",
		},
		-- D-111: the Owner's whole-game reset (SystemResetService). Status
		-- reads the last reset; Reset needs the typed confirmation.
		AdminSystemReset = {
			direction = "ClientToServer",
			kind = "Function",
			args = {
				S.enum({ "Status", "Reset" }),
				S.struct({
					Keep = S.optional(S.struct({
						Items = S.optional(S.boolean()),
						Gear = S.optional(S.boolean()),
						MallPoints = S.optional(S.boolean()),
						Levels = S.optional(S.boolean()),
						Rankings = S.optional(S.boolean()),
					})),
					Confirm = S.optional(S.string(10)),
				}),
			},
			rate = { capacity = 3, refillPerSecond = 0.1 },
			states = { "ProfileLoaded" },
			permission = "system.reset",
		},
		-- D-112: the panel staff list and pay (StaffService; StaffRules
		-- decides what the Owner / an Admin may do and clamps features).
		AdminStaff = {
			direction = "ClientToServer",
			kind = "Function",
			args = {
				S.enum({ "List", "Assign", "SetPerms", "SetSalary", "Remove", "Approve", "Reject" }),
				S.struct({
					UserId = S.optional(S.int(1, 9007199254740991)),
					Role = S.optional(S.enum(StaffRules.ROLES)),
					Perms = S.optional(S.array(S.enum(AdminRules.PERMISSIONS), 16)),
					Salary = S.optional(S.struct({
						Enabled = S.boolean(),
						Period = S.enum(StaffRules.PERIODS),
						MallPoints = S.int(0, StaffRules.MAX_SALARY_POINTS),
						Items = S.array(
							S.struct({
								Id = S.enum(STACKABLE_IDS),
								Count = S.int(1, StaffRules.MAX_ITEM_COUNT),
							}),
							StaffRules.MAX_SALARY_ITEMS
						),
						SetRarity = S.optional(S.enum(StaffRules.SET_RARITIES)),
					})),
				}),
			},
			rate = { capacity = 8, refillPerSecond = 0.5 },
			states = { "ProfileLoaded" },
			permission = "staff.manage",
		},
		AdminAudit = {
			direction = "ClientToServer",
			kind = "Function",
			args = {},
			rate = { capacity = 4, refillPerSecond = 0.5 },
			states = { "ProfileLoaded" },
			permission = "audit.view",
		},
		-- Server -> a staff member only: their role and permissions (never
		-- sent to anyone else, so the staff list isn't public).
		AdminHello = {
			direction = "ServerToClient",
			kind = "Event",
			args = {
				S.struct({
					Role = S.enum(AdminRules.ROLES),
					Permissions = S.array(S.enum(AdminRules.PERMISSIONS), 32),
				}),
			},
		},

		-- Server -> owner: how an enhancement attempt went (display only).
		EnhanceResult = {
			direction = "ServerToClient",
			kind = "Event",
			args = {
				S.struct({
					Guid = guid,
					Success = S.boolean(),
					Level = S.int(0, Constants.Enhancement.Max),
					Perfect = S.boolean(),
				}),
			},
		},

		-- Studio play-tests only: a handful of random gear and stackables to
		-- try the inventory before loot exists (Phase 10). Live servers
		-- refuse it and log a security event.
		StudioTestGear = {
			direction = "ClientToServer",
			kind = "Event",
			args = {},
			rate = { capacity = 2, refillPerSecond = 0.2 },
			states = { "ProfileLoaded", "HasJob" },
		},

		-- Server -> owner: what changed in their items (Phase 7). `Changed`
		-- items replace the client's copies, `Removed` guids are gone; the
		-- equipment, stackables and wallet are sent whole. `ReadyIn`: seconds
		-- until each consumable can be used again.
		InventoryUpdate = {
			direction = "ServerToClient",
			kind = "Event",
			args = {
				S.struct({
					Changed = S.map(guid, itemView, MAX_ITEMS),
					Removed = S.array(guid, MAX_ITEMS),
					Equipment = equipment,
					Stackables = stackables,
					Wallet = wallet,
					ReadyIn = S.optional(S.map(S.enum(CONSUMABLE_IDS), S.number(0, 600), 24)),
				}),
			},
		},

		-- Server -> caster: a skill's authoritative cooldown after a cast
		-- attempt (0 = ready; corrects the client's predicted sweep).
		SkillCooldown = {
			direction = "ServerToClient",
			kind = "Event",
			args = {
				S.struct({
					skill = S.enum(SKILL_IDS),
					readyIn = S.number(0, 600),
				}),
			},
		},

		-- Movement mode intent (Walk / Sprint / Crouch). The server decides the
		-- speed, drains Focus for sprinting and publishes the "Stance" attribute.
		SetMovementMode = {
			direction = "ClientToServer",
			kind = "Event",
			args = { S.enum({ "Walk", "Sprint", "Crouch" }) },
			rate = { capacity = 8, refillPerSecond = 4 },
			states = { "ProfileLoaded", "Alive" },
		},

		-- Leave the dungeon rally or run (Phase 9). No arguments: the server
		-- knows which rally/run the player is in. Entering uses the gate's
		-- ProximityPrompt (server-side Triggered), so it needs no remote.
		DungeonLeave = {
			direction = "ClientToServer",
			kind = "Event",
			args = {},
			rate = { capacity = 3, refillPerSecond = 0.5 },
			states = { "ProfileLoaded" },
		},

		-- Parties (D-39). Intents only; PartyService checks leadership, race,
		-- party size and pending invites. Targets are Player instances.
		PartyInvite = {
			direction = "ClientToServer",
			kind = "Event",
			args = { S.instance("Player") },
			rate = { capacity = 4, refillPerSecond = 0.5 },
			states = { "ProfileLoaded", "HasJob" },
		},
		PartyRespond = {
			direction = "ClientToServer",
			kind = "Event",
			args = { S.instance("Player"), S.boolean() },
			rate = { capacity = 4, refillPerSecond = 0.5 },
			states = { "ProfileLoaded", "HasJob" },
		},
		PartyLeave = {
			direction = "ClientToServer",
			kind = "Event",
			args = {},
			rate = { capacity = 3, refillPerSecond = 0.3 },
			states = { "ProfileLoaded" },
		},
		PartyKick = {
			direction = "ClientToServer",
			kind = "Event",
			args = { S.instance("Player") },
			rate = { capacity = 4, refillPerSecond = 0.5 },
			states = { "ProfileLoaded" },
		},

		-- Unions (D-48): party leaders join up to Party.UnionMaxParties
		-- parties. Intents only; PartyService checks leadership, race, size
		-- and pending invites. Targets are the other parties' leaders.
		UnionInvite = {
			direction = "ClientToServer",
			kind = "Event",
			args = { S.instance("Player") },
			rate = { capacity = 4, refillPerSecond = 0.5 },
			states = { "ProfileLoaded", "HasJob" },
		},
		UnionRespond = {
			direction = "ClientToServer",
			kind = "Event",
			args = { S.instance("Player"), S.boolean() },
			rate = { capacity = 4, refillPerSecond = 0.5 },
			states = { "ProfileLoaded", "HasJob" },
		},
		UnionLeave = {
			direction = "ClientToServer",
			kind = "Event",
			args = {},
			rate = { capacity = 3, refillPerSecond = 0.3 },
			states = { "ProfileLoaded" },
		},
		UnionKick = {
			direction = "ClientToServer",
			kind = "Event",
			args = { S.instance("Player") },
			rate = { capacity = 4, refillPerSecond = 0.5 },
			states = { "ProfileLoaded" },
		},

		-- Server -> union members: the parties in the union (display only).
		UnionState = {
			direction = "ServerToClient",
			kind = "Event",
			args = {
				S.struct({
					parties = S.array(
						S.struct({
							leaderUserId = S.int(),
							size = S.int(1, 8),
							-- The union leader's party.
							leads = S.boolean(),
						}),
						8
					),
					maxParties = S.int(1, 8),
				}),
			},
		},

		-- Server -> invited party leader: join a union (Accept / Decline).
		UnionInvited = {
			direction = "ServerToClient",
			kind = "Event",
			args = {
				S.struct({
					fromUserId = S.int(),
					expiresIn = S.number(0, 300),
				}),
			},
		},

		-- Server -> party members: the party roster (display only).
		PartyState = {
			direction = "ServerToClient",
			kind = "Event",
			args = {
				S.struct({
					members = S.array(
						S.struct({
							-- Any integer: Studio test players have negative ids.
							userId = S.int(),
							leader = S.boolean(),
						}),
						8
					),
					maxMembers = S.int(1, 8),
				}),
			},
		},

		-- Server -> invited player: someone invites you (Accept / Decline).
		PartyInvited = {
			direction = "ServerToClient",
			kind = "Event",
			args = {
				S.struct({
					fromUserId = S.int(),
					expiresIn = S.number(0, 300),
				}),
			},
		},

		-- Server -> players inside a dungeon: tracker state (D-42).
		DungeonState = {
			direction = "ServerToClient",
			kind = "Event",
			args = {
				S.struct({
					phase = S.enum({ "None", "Inside" }),
					dungeon = S.optional(S.string(60)),
					-- D-47: floors.
					floor = S.optional(S.int(1, 10)),
					floorCount = S.optional(S.int(1, 10)),
					floorName = S.optional(S.string(60)),
					levels = S.optional(S.string(20)),
					enraged = S.optional(S.boolean()),
					room = S.optional(S.string(60)),
					objective = S.optional(S.string(120)),
					progress = S.optional(S.int(0, 1000)),
					goal = S.optional(S.int(0, 1000)),
					roomIndex = S.optional(S.int(1, 64)),
					roomCount = S.optional(S.int(1, 64)),
					members = S.optional(S.int(0, 50)),
					maxMembers = S.optional(S.int(1, 50)),
					countdown = S.optional(S.number(0, 600)),
					leader = S.optional(S.string(60)),
					-- "Stoneback Guardian: returns in 12m 05s" / ": awake".
					miniBoss = S.optional(S.string(100)),
					bossStatus = S.optional(S.string(100)),
					charges = S.optional(S.int(0, 10)),
					xp = S.optional(S.int(0)),
					bossName = S.optional(S.string(60)),
					bossHp = S.optional(S.number(0, 1)),
				}),
			},
		},

		-- Server -> nearby clients: ground warning for a telegraphed attack
		-- (display only; the server tests positions when it lands).
		Telegraph = {
			direction = "ServerToClient",
			kind = "Event",
			args = {
				S.struct({
					shape = S.enum({ "Circle", "Cone", "Ring" }),
					center = S.vector3(),
					radius = S.number(0, 200),
					inner = S.optional(S.number(0, 200)),
					angle = S.optional(S.number(0, 360)),
					facing = S.optional(S.vector3()),
					duration = S.number(0, 5),
				}),
			},
		},

		-- Server -> nearby clients: combat feedback for display only
		-- (damage numbers, hit flash, non-graphic defeat effect).
		CombatEvent = {
			direction = "ServerToClient",
			kind = "Event",
			args = {
				S.struct({
					-- "Attack": `target` is the attacker, `action` the AnimationClips
					-- clip every nearby client plays on it, `step` its combo step.
					-- "Skill": `target` is the caster, `skill` the skill, `aim` its
					-- target and `point` where an area skill lands.
					-- "Dodge" (D-90): `target` evaded a hit from `source`.
					kind = S.enum({
						"Damage",
						"Heal",
						"Defeat",
						"Revive",
						"Attack",
						"MobAttack",
						"Skill",
						"Dodge",
					}),
					target = S.instance("Model"),
					amount = S.optional(S.int(0)),
					crit = S.optional(S.boolean()),
					action = S.optional(S.enum(ACTION_NAMES)),
					-- "Attack": the target the attack was aimed at (if any).
					aim = S.optional(S.instance("Model")),
					step = S.optional(S.int(1, 3)),
					-- "Damage": who dealt it, and whether it was a finisher.
					source = S.optional(S.instance("Model")),
					heavy = S.optional(S.boolean()),
					-- "MobAttack": seconds until the creature's hit lands.
					windup = S.optional(S.number(0, 5)),
					-- "MobAttack": the motion's shape (MobVisualController).
					move = S.optional(S.enum({ "Strike", "Slam", "Roar", "Sweep" })),
					-- "MobAttack": a creature's roar on noticing a player, not an attack.
					alert = S.optional(S.boolean()),
					skill = S.optional(S.enum(SKILL_IDS)),
					point = S.optional(S.vector3()),
					-- "Damage": how much a shield soaked up, and the skill combo
					-- that powered the hit ("Shatter", "Execute", ...).
					absorbed = S.optional(S.int(0)),
					combo = S.optional(S.enum(COMBO_NAMES)),
					-- "Damage" / "Heal" over time (poison, burn, regen ticks).
					tick = S.optional(S.enum({ "Poison", "Burn", "Regen" })),
					-- D-103 "Damage": the Healer's Immune stopped it / a Reflect sent it back.
					immune = S.optional(S.boolean()),
					reflect = S.optional(S.boolean()),
					-- D-103 "Skill": an Extender re-pulsed the caster's active area.
					extend = S.optional(S.struct({
						skill = S.enum(SKILL_IDS),
						point = S.optional(S.vector3()),
						radius = S.number(0, 40),
						pulses = S.int(1, 3),
						delay = S.number(0, 5),
					})),
				}),
			},
		},

		-- Server -> client notification. Text is a localization key plus
		-- server-generated parameters (never player-written text).
		Notify = {
			direction = "ServerToClient",
			kind = "Event",
			args = {
				S.struct({
					kind = S.enum(NotifyKind),
					textKey = S.string(64, 1, "^[%w%._]+$"),
					params = S.optional(S.map(S.string(32, 1, "^[%w_]+$"), S.string(200), 8)),
				}),
			},
		},

		-- Server -> owning client: quests, flags, titles, cosmetics (D-73).
		QuestUpdate = {
			direction = "ServerToClient",
			kind = "Event",
			args = { questsView },
		},

		-- Server -> owning client: what the quest giver says (on talking to
		-- them; text is from QuestDefinitions, never player input).
		QuestDialogue = {
			direction = "ServerToClient",
			kind = "Event",
			args = {
				S.struct({
					Giver = S.string(64, 1),
					Title = S.string(64),
					Entries = S.array(
						S.struct({
							Quest = S.enum(QUEST_IDS),
							Mode = S.enum({ "Offer", "Progress", "TurnIn", "Later" }),
							Text = S.string(600),
						}),
						12
					),
					Idle = S.optional(S.string(600)),
				}),
			},
		},

		-- Server -> owning client: replicated profile view (DATA_MODEL.md §6).
		-- Sent once the profile is loaded and the client is ready. Phase 2 fields;
		-- later phases extend this schema together with ProfileView.
		ProfileSnapshot = {
			direction = "ServerToClient",
			kind = "Event",
			args = {
				S.struct({
					Race = S.optional(S.enum(Enums.Race)),
					Job = S.optional(S.enum(Enums.Job)),
					FacePreset = S.int(1, FacePresets.maxId()),
					HeadStyle = S.enum(Enums.HeadStyle),
					SkinTone = S.enum(Complexion.SKIN_IDS),
					HairColor = S.enum(Complexion.HAIR_IDS),
					Level = S.int(0, MAX_LEVEL),
					Experience = S.int(0),
					XPToNext = S.int(0),
					-- Phase 5 (D-45): learned skill id -> rank, and the 6 + 1 bar (D-75).
					OwnedSkills = S.map(S.enum(LEARNABLE_IDS), S.int(1, 5), 64),
					EquippedSkills = S.struct({
						Regular = S.array(S.enum(SKILL_IDS), Constants.Loadout.RegularSlots),
						Special = S.optional(S.enum(SKILL_IDS)),
					}),
					-- Phase 7 (D-64): the owner's items.
					Inventory = S.map(guid, itemView, MAX_ITEMS),
					Equipment = equipment,
					Stackables = stackables,
					Wallet = wallet,
					-- Phase 14 (D-76): PvP record.
					PvP = S.struct({ Victories = S.int(0), Defeats = S.int(0) }),
					-- Phase 11 (D-73).
					Quests = questsView,
					-- D-74.
					HudLayout = hudLayout,
					-- D-90.
					Attributes = attributesView,
					-- D-93.
					Buffs = buffsView,
				}),
			},
		},

		-- Server -> owning client: running buffs after a change (D-93).
		BuffsUpdate = {
			direction = "ServerToClient",
			kind = "Event",
			args = { buffsView },
		},

		-- Server -> owning client: attribute points after a change (D-90).
		AttributesUpdate = {
			direction = "ServerToClient",
			kind = "Event",
			args = { attributesView },
		},

		-- Server -> owning client: level/XP changed (display only).
		ProgressionUpdate = {
			direction = "ServerToClient",
			kind = "Event",
			args = {
				S.struct({
					Level = S.int(0, MAX_LEVEL),
					Experience = S.int(0),
					XPToNext = S.int(0),
					LevelsGained = S.int(0, MAX_LEVEL),
				}),
			},
		},
	}
end
