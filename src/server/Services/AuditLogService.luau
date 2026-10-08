--!strict
--[[
	AuditLogService (Layer 0) — skeleton
	Two streams (SECURITY_MODEL.md §7):
	  - Audit: every admin/moderator action and config change. Never throttled.
	  - Security: remote rejections, repairs, anti-exploit corrections.
	    Throttled per (player, code) so floods cannot flood the log.

	Phase 1: entries go to the server log and an in-memory ring buffer.
	Phase 17 adds the batched DataStore sink (`RC_Audit_v1`, partitioned by day).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Log = require(Shared.Util.Log)

local ConfigurationService = require(script.Parent.ConfigurationService)

local BUFFER_CAPACITY = 500

local auditLog = Log.new("Audit")
local securityLog = Log.new("Security")

export type AuditEntry = {
	actorUserId: number,
	action: string,
	target: string?,
	details: { [string]: any }?,
	at: number?,
	jobId: string?,
}

local AuditLogService = {}

local buffer: { AuditEntry } = {}
local dropped = 0

local function securityKeyPrefix(userId: number): string
	-- Trailing colon so user 12 never matches user 123.
	return `sec:{userId}:`
end

--[[
	Records an audit entry. Callers pass structured data only — never chat text
	or unfiltered player-written text.
]]
function AuditLogService:Audit(entry: AuditEntry)
	local record = table.clone(entry)
	record.at = os.time()
	record.jobId = game.JobId
	table.insert(buffer, record)
	if #buffer > BUFFER_CAPACITY then
		table.remove(buffer, 1)
		dropped += 1
	end
	auditLog:Info("actor=%d action=%s target=%s", record.actorUserId, record.action, tostring(record.target))
end

--[[
	Records a security-relevant event for `player` (throttled per player+code).
]]
function AuditLogService:Security(player: Player, code: string, detail: string)
	local seconds = ConfigurationService:Get("Net.SecurityLogThrottleSeconds")
	securityLog:Throttled(
		securityKeyPrefix(player.UserId) .. code,
		seconds,
		"Warn",
		"user=%d code=%s %s",
		player.UserId,
		code,
		detail
	)
end

-- Returns a copy of buffered audit entries (Phase 17 flushes these).
function AuditLogService:GetBuffered(): ({ AuditEntry }, number)
	return table.clone(buffer), dropped
end

function AuditLogService:Start()
	Players.PlayerRemoving:Connect(function(player)
		Log.clearThrottle(securityKeyPrefix(player.UserId))
	end)
end

return AuditLogService
