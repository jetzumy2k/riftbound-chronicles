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
local AnimationClips = require(script.Parent.Parent.Definitions.AnimationClips)
local SkillDefinitions = require(script.Parent.Parent.Definitions.SkillDefinitions)

local NotifyKind = { "Info", "Warning", "Welcome" }
local MAX_LEVEL = Constants.Level.Max

local ACTION_NAMES = table.clone(AnimationClips.NAMES)
local SKILL_IDS = table.clone(SkillDefinitions.IDS)
local COMBO_NAMES = {}
for _, skill in SkillDefinitions.All do
	if skill.combo and table.find(COMBO_NAMES, skill.combo.name) == nil then
		table.insert(COMBO_NAMES, skill.combo.name)
	end
end

return function(S: any)
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
			args = { S.enum(SKILL_IDS) },
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

		-- Skill loadout intent (Phase 5): up to 3 regular skills + 1 special.
		-- A 4th regular entry fails the schema; SkillService checks the rest.
		SetLoadout = {
			direction = "ClientToServer",
			kind = "Event",
			args = { S.array(S.enum(SKILL_IDS), 3), S.optional(S.enum(SKILL_IDS)) },
			rate = { capacity = 4, refillPerSecond = 0.5 },
			states = { "ProfileLoaded", "HasJob" },
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
					kind = S.enum({ "Damage", "Heal", "Defeat", "Revive", "Attack", "MobAttack", "Skill" }),
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
					Level = S.int(0, MAX_LEVEL),
					Experience = S.int(0),
					XPToNext = S.int(0),
					-- Phase 5 (D-45): learned skill id -> rank, and the 3 + 1 bar.
					OwnedSkills = S.map(S.enum(SKILL_IDS), S.int(1, 5), 64),
					EquippedSkills = S.struct({
						Regular = S.array(S.enum(SKILL_IDS), 3),
						Special = S.optional(S.enum(SKILL_IDS)),
					}),
				}),
			},
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
