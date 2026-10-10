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

local NotifyKind = { "Info", "Warning", "Welcome" }
local MAX_LEVEL = Constants.Level.Max

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

		-- Server -> nearby clients: combat feedback for display only
		-- (damage numbers, hit flash, non-graphic defeat effect).
		CombatEvent = {
			direction = "ServerToClient",
			kind = "Event",
			args = {
				S.struct({
					kind = S.enum({ "Damage", "Heal", "Defeat", "Revive" }),
					target = S.instance("Model"),
					amount = S.optional(S.int(0)),
					crit = S.optional(S.boolean()),
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
