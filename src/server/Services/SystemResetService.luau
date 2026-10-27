--!strict
--[[
	SystemResetService (Layer 1) — the Owner's whole-game reset (creator
	decisions 2026-10-27, PLAN.md D-111).

	The Owner picks what to keep (ResetRules.KEEP_KEYS) and types RESET in
	the admin panel. That writes one record, { version, keep, at, by }, to
	a DataStore; nothing is wiped in bulk. Every profile carries the last
	reset it took (ResetVersion) and takes a newer one on its next load,
	offline players included, through PlayerDataService's load hook:

	  1. A copy of the whole profile is saved first (RC_ResetBackups_v1,
	     key Player_<id>_r<version>). If that save fails nothing is reset
	     this time; the next load tries again.
	  2. ResetRules.apply clears what was not kept (Robux Mall Points are
	     always kept).
	  3. Audit logged.

	Servers watch the record; when a new reset appears, everyone online is
	warned and, after RESET_KICK_SECONDS, asked to rejoin so the reset
	applies to them as well. Owner only: the remote needs "system.reset",
	which only the Owner role has (AdminRules).
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local ResetRules = require(Shared.Logic.ResetRules)
local Log = require(Shared.Util.Log)

local ProfileTemplate = require(script.Parent.Parent.Persistence.ProfileTemplate)
local CharacterSlots = require(script.Parent.Parent.Persistence.CharacterSlots)
local AuditLogService = require(script.Parent.AuditLogService)
local NetService = require(script.Parent.NetService)
local PlayerDataService = require(script.Parent.PlayerDataService)

local log = Log.new("SystemResetService")

local RECORD_STORE = "RC_SystemReset_v1"
local RECORD_KEY = "Current"
local BACKUP_STORE = "RC_ResetBackups_v1"
local POLL_SECONDS = 60
local RESET_KICK_SECONDS = 15
local KICK_TEXT = "The game world has been reset. Please rejoin to continue."

type Record = { version: number, keep: ResetRules.Keep, at: number, by: number }

local SystemResetService = {}

-- The newest reset record (nil: none yet / not fetched).
local record: Record? = nil
local fetched = false
-- The version this server started with; a newer one triggers the rejoin.
local seenVersion: number? = nil
local kicking = false

local function sanitize(raw: any): Record?
	if type(raw) ~= "table" or type(raw.version) ~= "number" or raw.version < 1 then
		return nil
	end
	return {
		version = math.floor(raw.version),
		keep = ResetRules.normalize(raw.keep),
		at = if type(raw.at) == "number" then raw.at else 0,
		by = if type(raw.by) == "number" then raw.by else 0,
	}
end

local function fetch(): boolean
	local ok, raw = pcall(function()
		return DataStoreService:GetDataStore(RECORD_STORE):GetAsync(RECORD_KEY)
	end)
	if not ok then
		log:Info("reset record unavailable (%s)", tostring(raw))
		return false
	end
	record = sanitize(raw)
	fetched = true
	return true
end

-- Warns everyone here, then sends them back to rejoin (the reset applies on
-- load).
local function rejoinAll()
	if kicking then
		return
	end
	kicking = true
	for _, player in Players:GetPlayers() do
		NetService:FireClient("Notify", player, {
			kind = "Warning",
			textKey = "system.reset",
			params = { seconds = tostring(RESET_KICK_SECONDS) },
		})
	end
	task.delay(RESET_KICK_SECONDS, function()
		for _, player in Players:GetPlayers() do
			player:Kick(KICK_TEXT)
		end
		kicking = false
	end)
end

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in value do
		out[k] = deepCopy(v)
	end
	return out
end

-- PlayerDataService load hook (may yield).
local function onLoad(player: Player, data: { [string]: any })
	if not fetched then
		fetch()
	end
	local current = record
	if current == nil or not ResetRules.due(data.ResetVersion, current.version) then
		return
	end
	-- A brand-new character has nothing to reset.
	if
		data.CreatedAt == data.LastLoginAt
		and (data.Level or 0) == 0
		and next(data.Inventory or {}) == nil
	then
		data.ResetVersion = current.version
		return
	end
	local backupKey = `Player_{player.UserId}_r{current.version}`
	local ok, err = pcall(function()
		DataStoreService:GetDataStore(BACKUP_STORE):SetAsync(backupKey, deepCopy(data), { player.UserId })
	end)
	if not ok then
		log:Error("backup failed for %d (%s); reset postponed to the next load", player.UserId, tostring(err))
		return
	end
	local cleared = ResetRules.apply(data, current.keep, current.version, ProfileTemplate.new())
	-- D-115: every stored character takes the same reset (Mall Points are
	-- the account's, already handled above).
	local keepStored = table.clone(current.keep)
	keepStored.MallPoints = true
	for key, blob in data.Characters do
		local scratch = ProfileTemplate.new()
		scratch.Race = data.Race
		CharacterSlots.install(scratch, blob)
		ResetRules.apply(scratch, keepStored, current.version, ProfileTemplate.new())
		data.Characters[key] = CharacterSlots.extract(scratch)
	end
	AuditLogService:Audit({
		actorUserId = player.UserId,
		action = "SystemResetApplied",
		target = `r{current.version}`,
		details = { cleared = table.concat(cleared, ","), backup = backupKey },
	})
	log:Info(
		"user=%d took reset r%d (cleared %s)",
		player.UserId,
		current.version,
		table.concat(cleared, ",")
	)
end

local function status(): { [string]: any }
	local current = record
	return {
		ok = true,
		version = if current then current.version else 0,
		at = if current then current.at else 0,
		keep = if current then current.keep else nil,
	}
end

local function onRequest(actor: Player, action: string, args: { [string]: any }): { [string]: any }
	if action == "Status" then
		if not fetched then
			fetch()
		end
		return status()
	end
	if args.Confirm ~= ResetRules.CONFIRM_TEXT then
		return { ok = false, reason = "confirm" }
	end
	local keep = ResetRules.normalize(args.Keep)
	local saved: Record? = nil
	local ok, err = pcall(function()
		DataStoreService:GetDataStore(RECORD_STORE):UpdateAsync(RECORD_KEY, function(old: any)
			local previous = sanitize(old)
			saved = {
				version = (if previous then previous.version else 0) + 1,
				keep = keep,
				at = os.time(),
				by = actor.UserId,
			}
			return saved
		end)
	end)
	if not ok or saved == nil then
		log:Error("reset record not saved: %s", tostring(err))
		return { ok = false, reason = "save" }
	end
	local new = saved :: Record
	record = new
	fetched = true
	seenVersion = new.version
	local kept = {}
	for _, key in ResetRules.KEEP_KEYS do
		if keep[key] then
			table.insert(kept, key)
		end
	end
	AuditLogService:Audit({
		actorUserId = actor.UserId,
		action = "SystemReset",
		target = `r{new.version}`,
		details = { keep = table.concat(kept, ",") },
	})
	log:Warn("SYSTEM RESET r%d by %d (keep: %s)", new.version, actor.UserId, table.concat(kept, ","))
	rejoinAll()
	return { ok = true, version = new.version, kickIn = RESET_KICK_SECONDS }
end

function SystemResetService:Init()
	PlayerDataService:AddLoadHook(onLoad)
	NetService:Handle("AdminSystemReset", onRequest)
end

function SystemResetService:Start()
	task.spawn(function()
		if fetch() then
			seenVersion = if record then record.version else 0
		end
		while true do
			task.wait(POLL_SECONDS)
			if fetch() then
				local version = if record then record.version else 0
				if seenVersion == nil then
					seenVersion = version
				elseif version > seenVersion then
					-- Another server started a reset.
					seenVersion = version
					rejoinAll()
				end
			end
		end
	end)
end

return SystemResetService
