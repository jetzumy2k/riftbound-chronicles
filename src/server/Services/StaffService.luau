--!strict
--[[
	StaffService (Layer 7) — Moderators and Game Masters assigned in the
	admin panel, with their weekly / monthly pay (creator decisions
	2026-10-27, PLAN.md D-112; rules in Logic/StaffRules).

	The staff list is one DataStore record (RC_Staff_v1 / Registry), changed
	only through UpdateAsync and re-read by every server each POLL_SECONDS.
	AdminService asks it for a panel role and its features on every admin
	call, so a change reaches every server within a minute (this server at
	once).

	AdminStaff (permission "staff.manage": the Owner and Admins):
	  List                       the staff, with any change waiting
	  Assign / SetPerms          the Owner: now; an Admin: waits for the
	                             Owner (Approve / Reject, Owner only)
	  SetSalary / Remove         now, for the Owner and Admins

	Pay: on join and every PAY_CHECK_SECONDS while online. One reward claim
	per period (S:<period>) on the profile makes a double payment
	impossible, even across servers. A gear set waits until the bag has
	room. Away StaffRules.INACTIVE_DAYS or more: the pay pauses on the next
	join until the Owner or an Admin turns it back on. Every change and
	every payment is audit logged.
]]

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local StaffRules = require(Shared.Logic.StaffRules)
local ItemDefinitions = require(Shared.Definitions.ItemDefinitions)
local Log = require(Shared.Util.Log)
local Signal = require(Shared.Util.Signal)

local AuditLogService = require(script.Parent.AuditLogService)
local NetService = require(script.Parent.NetService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local InventoryService = require(script.Parent.InventoryService)
local MallService = require(script.Parent.MallService)

local log = Log.new("StaffService")

local STORE = "RC_Staff_v1"
local KEY = "Registry"
local POLL_SECONDS = 60
local PAY_CHECK_SECONDS = 300

type Record = StaffRules.Record
type Records = { [string]: Record }

local StaffService = {
	-- Fired when the staff list changes (AdminService re-checks roles).
	Changed = Signal.new(),
}

local records: Records = {}
local fetchedOnce = false
local lastJson = ""
-- The actor's code role ("Owner" / "Admin" / ...), from AdminService.
local codeRoleOf: (Player) -> string? = function(_player: Player)
	return nil
end
local names: { [number]: string } = {}

local function isStackable(id: string): boolean
	return ItemDefinitions.stackable(id) ~= nil
end

-- A record read from the store, with every field checked.
local function clean(raw: any): Record?
	if type(raw) ~= "table" or not StaffRules.isRole(raw.role) then
		return nil
	end
	local pending: StaffRules.Pending? = nil
	if type(raw.pending) == "table" then
		local role = if StaffRules.isRole(raw.pending.role) then raw.pending.role else nil
		local perms = if type(raw.pending.perms) == "table"
			then StaffRules.clampPerms(role or raw.role, raw.pending.perms)
			else nil
		if role or perms then
			pending = {
				role = role,
				perms = perms,
				by = tonumber(raw.pending.by) or 0,
				at = tonumber(raw.pending.at) or 0,
			}
		end
	end
	return {
		role = raw.role,
		perms = StaffRules.clampPerms(raw.role, raw.perms),
		status = if raw.status == "Active" then "Active" else "Pending",
		assignedBy = tonumber(raw.assignedBy) or 0,
		approvedBy = tonumber(raw.approvedBy),
		at = tonumber(raw.at) or 0,
		salary = StaffRules.cleanSalary(raw.salary, isStackable),
		pending = pending,
		lastSeen = tonumber(raw.lastSeen) or 0,
	}
end

local function cleanAll(raw: any): Records
	local out: Records = {}
	if type(raw) == "table" and type(raw.records) == "table" then
		for key, value in raw.records do
			local userId = tonumber(key)
			local record = clean(value)
			if userId and userId > 0 and record then
				out[tostring(math.floor(userId))] = record
			end
		end
	end
	return out
end

local function fetch(): boolean
	local ok, raw = pcall(function()
		return DataStoreService:GetDataStore(STORE):GetAsync(KEY)
	end)
	if not ok then
		log:Info("staff list unavailable (%s)", tostring(raw))
		return false
	end
	records = cleanAll(raw)
	fetchedOnce = true
	local json = HttpService:JSONEncode(records)
	if json ~= lastJson then
		lastJson = json
		StaffService.Changed:Fire()
	end
	return true
end

--[[
	Changes the stored list: `mutate(list)` edits it in place and returns
	nil, or a reason to give up. Returns (ok, reason).
]]
local function change(mutate: (Records) -> string?): (boolean, string?)
	local reason: string? = nil
	local saved: Records? = nil
	local ok, err = pcall(function()
		DataStoreService:GetDataStore(STORE):UpdateAsync(KEY, function(old: any): any
			local list = cleanAll(old)
			reason = mutate(list)
			if reason then
				return nil -- cancels the write
			end
			saved = list
			return { records = list }
		end)
	end)
	if not ok then
		log:Error("staff list not saved: %s", tostring(err))
		return false, "save"
	end
	if reason then
		return false, reason
	end
	records = saved :: Records
	lastJson = HttpService:JSONEncode(records)
	StaffService.Changed:Fire()
	return true, nil
end

-- The panel record of `userId`, if any.
function StaffService:Get(userId: number): Record?
	return records[tostring(userId)]
end

-- AdminService gives the code role of a player (Owner / Admin / ...).
function StaffService:SetCodeRoleResolver(resolver: (Player) -> string?)
	codeRoleOf = resolver
end

local function nameOf(userId: number): string
	if names[userId] == nil then
		local ok, name = pcall(function()
			return Players:GetNameFromUserIdAsync(userId)
		end)
		names[userId] = if ok and type(name) == "string" then name else `User {userId}`
	end
	return names[userId]
end

--------------------------------------------------------------------------------
-- Pay
--------------------------------------------------------------------------------

local function notify(player: Player, kind: string, textKey: string, params: { [string]: string }?)
	NetService:FireClient("Notify", player, { kind = kind, textKey = textKey, params = params })
end

local function payNow(player: Player)
	local record = records[tostring(player.UserId)]
	if record == nil or record.status ~= "Active" then
		return
	end
	local salary = record.salary
	if not salary.enabled or not StaffRules.hasPay(salary) then
		return
	end
	local data = PlayerDataService:GetData(player)
	if data == nil or data.Job == nil then
		return
	end
	local claimId = StaffRules.claimId(salary.period, os.time())
	if data.ClaimedRewardIds[claimId] ~= nil then
		return
	end
	if salary.setRarity and InventoryService:FreeSlots(player) < MallService:SetSize(player) then
		notify(player, "Warning", "staff.payBag", { slots = tostring(MallService:SetSize(player)) })
		return
	end
	local source = `Staff:{claimId}`
	local given = {}
	local status = (PlayerDataService :: any):ClaimReward(player, claimId, function(d: any)
		if salary.mallPoints > 0 then
			d.Wallet.MallPoints = (d.Wallet.MallPoints or 0) + salary.mallPoints
			table.insert(given, `{salary.mallPoints} MP`)
		end
		for _, item in salary.items do
			local added = InventoryService:GrantStackable(player, item.id, item.count, source)
			if added > 0 then
				local def = ItemDefinitions.stackable(item.id)
				table.insert(given, `{added} {if def then def.name else item.id}`)
			end
		end
		if salary.setRarity and MallService:GrantSet(player, salary.setRarity, source) then
			table.insert(given, `{salary.setRarity} gear set`)
		end
	end)
	if status ~= "granted" then
		return
	end
	AuditLogService:Audit({
		actorUserId = player.UserId,
		action = "StaffPay",
		target = claimId,
		details = { role = record.role, given = table.concat(given, ", ") },
	})
	notify(player, "Info", "staff.paid", { what = table.concat(given, ", ") })
	PlayerDataService:PushSnapshot(player)
end

-- On join: note the visit; pause the pay after a long absence; then pay.
local function onJoin(player: Player)
	local deadline = os.clock() + 15
	while not fetchedOnce and os.clock() < deadline do
		task.wait(0.5)
	end
	local record = records[tostring(player.UserId)]
	if record == nil then
		return
	end
	local now = os.time()
	local paused = false
	change(function(list)
		local r = list[tostring(player.UserId)]
		if r == nil then
			return "gone"
		end
		if r.salary.enabled and StaffRules.inactive(r.lastSeen, now) then
			r.salary.enabled = false
			paused = true
		end
		r.lastSeen = now
		return nil
	end)
	if paused then
		AuditLogService:Audit({ actorUserId = player.UserId, action = "StaffPayPaused", target = "inactive" })
		notify(player, "Warning", "staff.paused")
	end
	payNow(player)
end

--------------------------------------------------------------------------------
-- Panel
--------------------------------------------------------------------------------

local function rows(): { any }
	local out = {}
	for key, r in records do
		local userId = tonumber(key) :: number
		table.insert(out, {
			UserId = userId,
			Name = nameOf(userId),
			Role = r.role,
			Perms = r.perms,
			Status = r.status,
			Salary = r.salary,
			Pending = r.pending,
			LastSeen = r.lastSeen,
			AssignedBy = r.assignedBy,
		})
	end
	table.sort(out, function(a, b)
		return a.UserId < b.UserId
	end)
	return out
end

local function audit(actor: Player, action: string, userId: number, details: { [string]: any }?)
	AuditLogService:Audit({
		actorUserId = actor.UserId,
		action = `Staff{action}`,
		target = tostring(userId),
		details = details,
	})
end

local function onStaff(actor: Player, action: string, args: { [string]: any }): { [string]: any }
	local actorRole = codeRoleOf(actor)
	local how = if action == "Approve" or action == "Reject"
		then (if actorRole == "Owner" then "now" else nil)
		else StaffRules.decide(actorRole, action)
	if how == nil then
		audit(actor, "Denied", 0, { action = action })
		return { ok = false, reason = "permission" }
	end
	if action == "List" then
		return { ok = true, staff = rows(), owner = actorRole == "Owner" }
	end
	local userId = args.UserId
	if type(userId) ~= "number" or userId < 1 then
		return { ok = false, reason = "user" }
	end
	local key = tostring(userId)
	local now = os.time()
	local ok, reason
	if action == "Assign" then
		local role = args.Role
		if not StaffRules.isRole(role) then
			return { ok = false, reason = "role" }
		elseif userId == actor.UserId then
			return { ok = false, reason = "self" }
		end
		local target = Players:GetPlayerByUserId(userId)
		local targetCode = if target then codeRoleOf(target) else nil
		if targetCode == "Owner" or targetCode == "Admin" then
			return { ok = false, reason = "codeStaff" }
		end
		ok, reason = change(function(list)
			local r = list[key]
			if r == nil then
				local count = 0
				for _ in list do
					count += 1
				end
				if count >= StaffRules.MAX_STAFF then
					return "full"
				end
				list[key] = {
					role = role,
					perms = table.clone(StaffRules.DEFAULTS[role]),
					status = if how == "now" then "Active" else "Pending",
					assignedBy = actor.UserId,
					approvedBy = if how == "now" then actor.UserId else nil,
					at = now,
					salary = StaffRules.emptySalary(),
					pending = nil,
					lastSeen = 0,
				}
			elseif how == "now" then
				r.role = role
				r.perms = table.clone(StaffRules.DEFAULTS[role])
				r.pending = nil
			else
				r.pending = {
					role = role,
					perms = table.clone(StaffRules.DEFAULTS[role]),
					by = actor.UserId,
					at = now,
				}
			end
			return nil
		end)
		audit(actor, "Assign", userId, { role = role, approval = how == "approval" })
	elseif action == "SetPerms" then
		ok, reason = change(function(list)
			local r = list[key]
			if r == nil then
				return "missing"
			end
			local role = if r.pending and r.pending.role then r.pending.role else r.role
			local perms = StaffRules.clampPerms(role, args.Perms)
			if how == "now" or r.status == "Pending" then
				-- A waiting assignment is still the Owner's to approve.
				r.perms = perms
			else
				r.pending =
					{ role = r.pending and r.pending.role, perms = perms, by = actor.UserId, at = now }
			end
			return nil
		end)
		audit(
			actor,
			"SetPerms",
			userId,
			{ perms = table.concat(args.Perms or {}, ","), approval = how == "approval" }
		)
	elseif action == "SetSalary" then
		local raw = args.Salary or {}
		local items = {}
		for _, item in raw.Items or {} do
			table.insert(items, { id = item.Id, count = item.Count })
		end
		local salary = StaffRules.cleanSalary({
			enabled = raw.Enabled,
			period = raw.Period,
			mallPoints = raw.MallPoints,
			items = items,
			setRarity = raw.SetRarity,
		}, isStackable)
		ok, reason = change(function(list)
			local r = list[key]
			if r == nil then
				return "missing"
			end
			r.salary = salary
			return nil
		end)
		audit(actor, "SetSalary", userId, {
			enabled = salary.enabled,
			period = salary.period,
			points = salary.mallPoints,
			items = #salary.items,
			set = salary.setRarity,
		})
	elseif action == "Remove" then
		ok, reason = change(function(list)
			if list[key] == nil then
				return "missing"
			end
			list[key] = nil
			return nil
		end)
		audit(actor, "Remove", userId)
	elseif action == "Approve" then
		ok, reason = change(function(list)
			local r = list[key]
			if r == nil then
				return "missing"
			end
			if r.status == "Pending" then
				r.status = "Active"
				r.approvedBy = actor.UserId
			end
			if r.pending then
				r.role = r.pending.role or r.role
				r.perms = StaffRules.clampPerms(r.role, r.pending.perms or r.perms)
				r.pending = nil
			end
			return nil
		end)
		audit(actor, "Approve", userId)
	elseif action == "Reject" then
		ok, reason = change(function(list)
			local r = list[key]
			if r == nil then
				return "missing"
			end
			if r.status == "Pending" then
				list[key] = nil
			else
				r.pending = nil
			end
			return nil
		end)
		audit(actor, "Reject", userId)
	else
		return { ok = false, reason = "action" }
	end
	if not ok then
		return { ok = false, reason = reason or "save" }
	end
	-- Pay a newly paid / re-enabled staff member who is online right away.
	local target = Players:GetPlayerByUserId(userId)
	if target and action == "SetSalary" then
		task.spawn(payNow, target)
	end
	return { ok = true, staff = rows(), owner = actorRole == "Owner" }
end

function StaffService:Init()
	NetService:Handle("AdminStaff", onStaff)
end

function StaffService:Start()
	PlayerDataService.ProfileLoaded:Connect(function(player)
		task.spawn(onJoin, player)
	end)
	task.spawn(function()
		fetch()
		local sincePay = 0
		while true do
			task.wait(POLL_SECONDS)
			fetch()
			sincePay += POLL_SECONDS
			if sincePay >= PAY_CHECK_SECONDS then
				sincePay = 0
				for _, player in Players:GetPlayers() do
					local okPay, err = pcall(payNow :: any, player)
					if not okPay then
						log:Error("staff pay check failed for %d: %s", player.UserId, tostring(err))
					end
				end
			end
		end
	end)
end

return StaffService
