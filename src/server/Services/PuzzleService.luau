--!strict
--[[
	PuzzleService (Layer 6) — the Puzzle Sage (creator request 2026-10-30,
	PLAN.md D-128; puzzles in Logic/PuzzleRules). The 🧩 Sage stands in
	each capital (built by ShopService with the other town NPCs).

	Remote Puzzle:
	  Status  today's rewarded solve used or not, the puzzle in play
	  Start   a new random puzzle (Slide or Lights, Medium or Hard), made
	          here; one at a time. The day's first one is the rewarded one
	          (needs a free bag slot); after that, practice (no reward)
	  Submit  the player's moves: replayed here (PuzzleRules.check) within
	          the time limit; a solved rewarded puzzle gives a random
	          Legendary gear piece, weapon or accessory of the player's
	          class at their level, once a day (reward claim P:<day>)
	  GiveUp  ends the puzzle (a rewarded one counts as used: no
	          re-rolling for an easier puzzle)
	Audit logged.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local PuzzleRules = require(Shared.Logic.PuzzleRules)
local Log = require(Shared.Util.Log)

local ConfigurationService = require(script.Parent.ConfigurationService)
local AuditLogService = require(script.Parent.AuditLogService)
local NetService = require(script.Parent.NetService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local InventoryService = require(script.Parent.InventoryService)
local ShopService = require(script.Parent.ShopService)

local log = Log.new("PuzzleService")

local NPC = "Sage"

type Active = { puzzle: PuzzleRules.Puzzle, startedAt: number, endsAt: number, rewarded: boolean }

local PuzzleService = {}

local active: { [Player]: Active } = {}
local random = Random.new()

local function today(): number
	return os.time() // 86400
end

local function claimId(): string
	return `P:{today()}`
end

local function view(player: Player, data: { [string]: any }): { [string]: any }
	local a = active[player]
	return {
		ok = true,
		enabled = ConfigurationService:Get("Puzzle").Enabled,
		rewardUsed = data.ClaimedRewardIds[claimId()] ~= nil or (data.PuzzleDay == today()),
		puzzle = if a
			then {
				Kind = a.puzzle.kind,
				Level = a.puzzle.level,
				Size = a.puzzle.size,
				Board = table.clone(a.puzzle.board),
				Seconds = math.max(0, math.floor(a.endsAt - os.clock())),
				Rewarded = a.rewarded,
			}
			else nil,
	}
end

local function onRequest(player: Player, action: string, moves: { number }?): { [string]: any }
	local data = PlayerDataService:GetData(player)
	if data == nil or data.Job == nil then
		return { ok = false, reason = "notLoaded" }
	end
	if not ShopService:Near(player, data, NPC) then
		return { ok = false, reason = "far" }
	end
	if action == "Status" then
		return view(player, data)
	end
	if not ConfigurationService:Get("Puzzle").Enabled then
		return { ok = false, reason = "closed" }
	end
	if action == "Start" then
		if active[player] then
			return view(player, data)
		end
		-- The day's rewarded try is used once it starts (no re-rolling).
		local rewarded = data.ClaimedRewardIds[claimId()] == nil and data.PuzzleDay ~= today()
		if rewarded and InventoryService:FreeSlots(player) < 1 then
			return { ok = false, reason = "bag" }
		end
		local kind = PuzzleRules.KINDS[random:NextInteger(1, #PuzzleRules.KINDS)]
		local level = PuzzleRules.LEVELS[random:NextInteger(1, #PuzzleRules.LEVELS)]
		local puzzle = PuzzleRules.make(kind, level, function(n)
			return random:NextInteger(1, n)
		end)
		if rewarded then
			data.PuzzleDay = today()
		end
		active[player] = {
			puzzle = puzzle,
			startedAt = os.clock(),
			endsAt = os.clock() + PuzzleRules.SECONDS[level],
			rewarded = rewarded,
		}
		AuditLogService:Audit({
			actorUserId = player.UserId,
			action = "PuzzleStart",
			target = `{kind}:{level}`,
			details = { rewarded = rewarded },
		})
		return view(player, data)
	end
	local a = active[player]
	if a == nil then
		return { ok = false, reason = "noPuzzle" }
	end
	if action == "GiveUp" then
		active[player] = nil
		return view(player, data)
	end
	if action ~= "Submit" then
		return { ok = false, reason = "action" }
	end
	if os.clock() > a.endsAt then
		active[player] = nil
		return { ok = false, reason = "time" }
	end
	if type(moves) ~= "table" or not PuzzleRules.check(a.puzzle, moves) then
		return { ok = false, reason = "wrong" }
	end
	active[player] = nil
	local seconds = math.floor(os.clock() - a.startedAt)
	local given: string? = nil
	if a.rewarded then
		local status = (PlayerDataService :: any):ClaimReward(player, claimId(), function()
			given = InventoryService:GrantRandomPiece(player, "Legendary", "Puzzle:Sage")
		end)
		if status ~= "granted" then
			given = nil
		end
	end
	AuditLogService:Audit({
		actorUserId = player.UserId,
		action = "PuzzleSolved",
		target = `{a.puzzle.kind}:{a.puzzle.level}`,
		details = { seconds = seconds, moves = #moves, reward = given },
	})
	log:Info("user=%d solved %s %s in %ds", player.UserId, a.puzzle.kind, a.puzzle.level, seconds)
	PlayerDataService:PushSnapshot(player)
	local out = view(player, data)
	out.solved = true
	out.seconds = seconds
	out.given = given
	return out
end

function PuzzleService:Init()
	NetService:Handle("Puzzle", onRequest)
end

function PuzzleService:Start()
	Players.PlayerRemoving:Connect(function(player)
		active[player] = nil
	end)
end

return PuzzleService
