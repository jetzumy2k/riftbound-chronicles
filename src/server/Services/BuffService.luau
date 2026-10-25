--!strict
--[[
	BuffService (Layer 4) — temporary buffs from Mall consumables (PLAN.md
	D-93; rules in Logic/BuffRules).

	`Activate` starts (or lengthens) a buff when a buff consumable is used
	from the bag (InventoryService). Reward buffs are read where rewards are
	earned (EventService); stat buffs change the character's stats, so the
	stats are re-read when a buff starts and again when one runs out (checked
	every few seconds). The owner gets BuffsUpdate (id -> seconds left).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local BuffRules = require(Shared.Logic.BuffRules)

local ProfileView = require(script.Parent.Parent.Persistence.ProfileView)
local AuditLogService = require(script.Parent.AuditLogService)
local NetService = require(script.Parent.NetService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local CombatService = require(script.Parent.CombatService)

local BuffService = {}

local CHECK_SECONDS = 5
-- How many buffs each player had running at the last check.
local runningCount: { [Player]: number } = {}

local function push(player: Player, data: { [string]: any })
	NetService:FireClient("BuffsUpdate", player, ProfileView.buffs(data))
end

-- Starts or lengthens buff `id` for `player`. Returns false if unknown.
function BuffService:Activate(player: Player, id: string): boolean
	local data = PlayerDataService:GetData(player)
	if data == nil then
		return false
	end
	data.Buffs = data.Buffs or {}
	local expires = BuffRules.extend(data.Buffs, id, os.time())
	if expires == nil then
		return false
	end
	runningCount[player] = #BuffRules.active(data.Buffs, os.time())
	AuditLogService:Audit({
		actorUserId = player.UserId,
		action = "BuffUsed",
		target = id,
		details = { expires = expires },
	})
	CombatService:RefreshStats(player)
	push(player, data)
	return true
end

function BuffService:Start()
	task.spawn(function()
		while true do
			task.wait(CHECK_SECONDS)
			local now = os.time()
			for _, player in Players:GetPlayers() do
				local data = PlayerDataService:GetData(player)
				if data then
					local count = #BuffRules.active(data.Buffs, now)
					if count < (runningCount[player] or 0) then
						-- A buff ran out: stats back, the client's list too.
						CombatService:RefreshStats(player)
						push(player, data)
					end
					runningCount[player] = count
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		runningCount[player] = nil
	end)
	PlayerDataService.ProfileLoaded:Connect(function(player, data)
		runningCount[player] = #BuffRules.active(data.Buffs, os.time())
	end)
end

return BuffService
