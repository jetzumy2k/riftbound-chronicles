--!strict
--[[
	AuditLogService (Layer 0) — skeleton
	Two streams (SECURITY_MODEL.md §7):
	  - Audit: every admin/moderator action and config change. Never throttled.
	  - Security: remote rejections, repairs, anti-exploit corrections.
	    Throttled per (player, code) so floods cannot flood the log.

	Entries go to the server log and an in-memory ring buffer (the panel's
	audit view). Phase 17 (D-13) adds the batched DataStore sink: every
	minute pending entries are saved under `RC_Audit_v1` /
	"<YYYY-MM-DD>:<server>:<n>" (partitioned by day; up to 300 per key).
	Retention cleanup is an owner job for later (D-13).
]]

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Log = require(Shared.Util.Log)

local ConfigurationService = require(script.Parent.ConfigurationService)

local BUFFER_CAPACITY = 500
local SINK_STORE = "RC_Audit_v1"
local SINK_SECONDS = 60
local SINK_BATCH = 300

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
-- Not yet saved to the DataStore sink.
local pending: { AuditEntry } = {}
local sinkSeq = 0

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
	if #pending < BUFFER_CAPACITY * 4 then
		table.insert(pending, record)
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

-- Saves pending entries (one key per batch). Studio without access: kept local.
local function flush()
	if #pending == 0 then
		return
	end
	local batch = table.move(pending, 1, math.min(#pending, SINK_BATCH), 1, {})
	sinkSeq += 1
	local server = if game.JobId ~= "" then string.sub(game.JobId, 1, 8) else "studio"
	local key = `{os.date("!%Y-%m-%d")}:{server}:{sinkSeq}`
	local ok, err = pcall(function()
		DataStoreService:GetDataStore(SINK_STORE):SetAsync(key, HttpService:JSONEncode(batch))
	end)
	if ok then
		table.move(pending, #batch + 1, #pending, 1)
		for _ = 1, #batch do
			table.remove(pending)
		end
	elseif not RunService:IsStudio() then
		auditLog:Warn("audit sink save failed (%s); %d entries waiting", tostring(err), #pending)
	else
		table.clear(pending)
	end
end

function AuditLogService:Start()
	Players.PlayerRemoving:Connect(function(player)
		Log.clearThrottle(securityKeyPrefix(player.UserId))
	end)
	task.spawn(function()
		while true do
			task.wait(SINK_SECONDS)
			flush()
		end
	end)
	game:BindToClose(flush)
end

return AuditLogService
