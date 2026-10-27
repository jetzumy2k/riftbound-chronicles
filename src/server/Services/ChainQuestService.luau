--!strict
--[[
	ChainQuestService (Layer 6) — the Warden's trial chain (creator request
	2026-10-27, PLAN.md D-119; steps in Definitions/ChainQuestDefinitions,
	rules in Logic/ChainRules, numbers in config ChainQuest).

	The 🗝️ Warden stands in each capital (built by ShopService with the
	other town NPCs). Remote ChainQuest, always checked on the server:

	  Status  the chain's state for the screen
	  Start   begin the chain (level, cooldown, not already on it)
	  Claim   once every step is done: "Legendary" (a Legendary piece of
	          the player's class at their level; needs a free bag slot) or
	          "Buff" (a random Mall buff for a day). One reward claim per
	          chain (C:<n>) makes a double payout impossible.

	Progress: MobDefeated, for every player who earned the EXP; Collect
	steps roll the drop chance here on the server. The player is told each
	step and the finish; the screen asks for Status when opened.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local ChainQuestDefinitions = require(Shared.Definitions.ChainQuestDefinitions)
local ChainRules = require(Shared.Logic.ChainRules)
local BuffRules = require(Shared.Logic.BuffRules)
local Log = require(Shared.Util.Log)

local ConfigurationService = require(script.Parent.ConfigurationService)
local AuditLogService = require(script.Parent.AuditLogService)
local NetService = require(script.Parent.NetService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local InventoryService = require(script.Parent.InventoryService)
local BuffService = require(script.Parent.BuffService)
local MobService = require(script.Parent.MobService)
local ShopService = require(script.Parent.ShopService)

local log = Log.new("ChainQuestService")

local NPC = "Warden"

local ChainQuestService = {}

local random = Random.new()

local function config(): ChainRules.Config
	return ConfigurationService:Get("ChainQuest")
end

local function notify(player: Player, kind: string, textKey: string, params: { [string]: string }?)
	NetService:FireClient("Notify", player, { kind = kind, textKey = textKey, params = params })
end

local function status(data: { [string]: any }): { [string]: any }
	local c = config()
	local chain: ChainRules.Chain = data.Chain
	local ok, reason = ChainRules.canStart(chain, c, data.Level or 0, os.time())
	return {
		ok = true,
		active = chain.Active,
		step = chain.Step,
		progress = chain.Progress,
		ready = ChainRules.ready(chain),
		cycles = chain.Cycles,
		canStart = ok,
		why = reason,
		cooldown = ChainRules.cooldownLeft(chain, c, os.time()),
		minLevel = c.MinLevel,
		chance = c.CollectChancePct,
	}
end

local function onRequest(player: Player, action: string, reward: string?): { [string]: any }
	local data = PlayerDataService:GetData(player)
	if data == nil or data.Job == nil then
		return { ok = false, reason = "notLoaded" }
	end
	if not ShopService:Near(player, data, NPC) then
		return { ok = false, reason = "far" }
	end
	local chain: ChainRules.Chain = data.Chain
	if action == "Status" then
		local out = status(data)
		out.bagFree = InventoryService:FreeSlots(player)
		return out
	elseif action == "Start" then
		local ok, reason = ChainRules.canStart(chain, config(), data.Level or 0, os.time())
		if not ok then
			return { ok = false, reason = reason }
		end
		ChainRules.start(chain)
		AuditLogService:Audit({
			actorUserId = player.UserId,
			action = "ChainStart",
			target = tostring(chain.Cycles + 1),
		})
		local out = status(data)
		out.bagFree = InventoryService:FreeSlots(player)
		return out
	elseif action == "Claim" then
		if not ChainRules.ready(chain) then
			return { ok = false, reason = "notDone" }
		end
		if reward ~= "Legendary" and reward ~= "Buff" then
			return { ok = false, reason = "reward" }
		end
		if reward == "Legendary" and InventoryService:FreeSlots(player) < 1 then
			return { ok = false, reason = "bag" }
		end
		local given = ""
		local status_ = (PlayerDataService :: any):ClaimReward(player, ChainRules.claimId(chain), function()
			if reward == "Legendary" then
				local name = InventoryService:GrantRandomPiece(player, "Legendary", "Chain:Warden")
				given = if name then `Legendary {name}` else ""
			else
				local id = BuffRules.IDS[random:NextInteger(1, #BuffRules.IDS)]
				if BuffService:GrantFor(player, id, ChainQuestDefinitions.BUFF_SECONDS) then
					local buff = BuffRules.get(id)
					given = `{if buff then buff.name else id} buff for a day`
				end
			end
		end)
		if status_ ~= "granted" then
			return { ok = false, reason = "claim" }
		end
		ChainRules.finish(chain, os.time())
		AuditLogService:Audit({
			actorUserId = player.UserId,
			action = "ChainReward",
			target = tostring(chain.Cycles),
			details = { reward = reward, given = given },
		})
		if given == "" then
			log:Error("chain reward %s for %d gave nothing", reward, player.UserId)
		end
		notify(player, "Info", "chain.reward", { what = if given ~= "" then given else reward })
		PlayerDataService:PushSnapshot(player)
		local out = status(data)
		out.bagFree = InventoryService:FreeSlots(player)
		out.given = given
		return out
	end
	return { ok = false, reason = "action" }
end

local function onMobDefeated(mob: any, _contributors: any, recipients: { Player }?)
	if recipients == nil then
		return
	end
	local c = config()
	if not c.Enabled then
		return
	end
	local enemyId = mob.enemy and mob.enemy.id
	if type(enemyId) ~= "string" then
		return
	end
	for _, player in recipients do
		local data = PlayerDataService:GetData(player)
		local chain = data and data.Chain
		if chain == nil or not chain.Active then
			continue
		end
		local stepIndex = chain.Step
		local step = ChainQuestDefinitions.Steps[stepIndex]
		local counted, stepDone = ChainRules.onKill(chain, c, enemyId, random:NextNumber())
		if not counted or step == nil then
			continue
		end
		if stepDone then
			if ChainRules.ready(chain) then
				notify(player, "Info", "chain.finished", { name = ChainQuestDefinitions.NAME })
			else
				notify(player, "Info", "chain.step", {
					done = tostring(stepIndex),
					total = tostring(ChainRules.stepCount()),
					next = ChainQuestDefinitions.Steps[chain.Step].label,
				})
			end
		elseif step.kind == "Collect" then
			notify(player, "Info", "chain.collect", {
				item = `{step.icon} {step.item or "Trophy"}`,
				have = tostring(chain.Progress),
				need = tostring(step.count),
			})
		end
	end
end

function ChainQuestService:Init()
	NetService:Handle("ChainQuest", onRequest)
	MobService.MobDefeated:Connect(onMobDefeated)
end

return ChainQuestService
