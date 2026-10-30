--!strict
--[[
	AttributeService (Layer 4) — attribute points (creator request
	2026-10-25, PLAN.md D-90; rules in Logic/AttributeRules).

	  SpendAttributes { REC = n, ... }  adds points; the server checks the
	                                    total against the level (5 a level)
	  ResetAttributes                   returns every point, free once every
	                                    24 hours

	After a change the player's combat stats are re-read (StatsService adds
	the attributes; CombatService:RefreshStats keeps the health fraction)
	and the owner gets AttributesUpdate. A level set down (admin) that
	leaves more points spent than the level gives returns them all.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local AttributeRules = require(Shared.Logic.AttributeRules)
local Log = require(Shared.Util.Log)

local ProfileView = require(script.Parent.Parent.Persistence.ProfileView)
local AuditLogService = require(script.Parent.AuditLogService)
local ConfigurationService = require(script.Parent.ConfigurationService)
local NetService = require(script.Parent.NetService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local LevelService = require(script.Parent.LevelService)
local CombatService = require(script.Parent.CombatService)

local log = Log.new("AttributeService")

local AttributeService = {}

local function notify(player: Player, kind: string, key: string, params: { [string]: string }?)
	NetService:FireClient("Notify", player, { kind = kind, textKey = key, params = params })
end

local function push(player: Player, data: { [string]: any })
	NetService:FireClient("AttributesUpdate", player, ProfileView.attributes(data))
end

local function onSpend(player: Player, adds: { [string]: number })
	local data = PlayerDataService:GetData(player)
	if data == nil then
		return
	end
	local ok, result = AttributeRules.spend(data.Attributes, adds, data.Level, data.TowerPoints)
	if not ok then
		if result == "points" then
			notify(player, "Warning", "attributes.noPoints")
		else
			AuditLogService:Security(player, "AttributeSpend", tostring(result))
		end
		push(player, data)
		return
	end
	data.Attributes = result
	log:Debug("user=%d attributes %s", player.UserId, tostring(AttributeRules.spent(result)))
	CombatService:RefreshStats(player)
	push(player, data)
end

local function onReset(player: Player)
	local data = PlayerDataService:GetData(player)
	if data == nil then
		return
	end
	if AttributeRules.spent(data.Attributes) == 0 then
		notify(player, "Info", "attributes.nothingToReset")
		return
	end
	-- D-105: with the free reset off (admin), the button uses a Scroll of
	-- Rebirth.
	if ConfigurationService:Get("Skills").FreeAttributeReset ~= true then
		if (data.Stackables.RebirthScroll or 0) <= 0 then
			notify(player, "Warning", "attributes.needScroll")
			return
		end
		data.Stackables.RebirthScroll -= 1
		AttributeService:ResetNow(player)
		PlayerDataService:PushSnapshot(player)
		return
	end
	local now = os.time()
	local ok, wait = AttributeRules.canReset(data.AttributeResetAt or 0, now)
	if not ok then
		local hours = math.ceil(wait / 3600)
		notify(player, "Warning", "attributes.resetWait", { hours = tostring(hours) })
		return
	end
	data.Attributes = AttributeRules.empty()
	data.AttributeResetAt = now
	AuditLogService:Audit({ actorUserId = player.UserId, action = "AttributeReset" })
	CombatService:RefreshStats(player)
	notify(player, "Info", "attributes.reset")
	push(player, data)
end

--[[
	Returns every point now, ignoring the 24 h wait (Scroll of Rebirth,
	D-93). The free reset's timer is left as it is. False if nothing was
	spent.
]]
function AttributeService:ResetNow(player: Player): boolean
	local data = PlayerDataService:GetData(player)
	if data == nil or AttributeRules.spent(data.Attributes) == 0 then
		return false
	end
	data.Attributes = AttributeRules.empty()
	AuditLogService:Audit({ actorUserId = player.UserId, action = "AttributeReset", target = "RebirthScroll" })
	CombatService:RefreshStats(player)
	notify(player, "Info", "attributes.reset")
	push(player, data)
	return true
end

function AttributeService:Init()
	NetService:Handle("SpendAttributes", onSpend)
	NetService:Handle("ResetAttributes", onReset)
end

function AttributeService:Start()
	LevelService.LevelChanged:Connect(function(player: Player)
		local data = PlayerDataService:GetData(player)
		if data == nil then
			return
		end
		local repaired, changed = AttributeRules.repair(data.Attributes, data.Level, data.TowerPoints)
		if changed then
			-- More spent than the new level gives (level set down): all back.
			data.Attributes = repaired
			CombatService:RefreshStats(player)
		end
		push(player, data)
	end)
end

return AttributeService
