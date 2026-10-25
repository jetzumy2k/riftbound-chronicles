--!strict
--[[
	AdminService (Layer 7) — the admin / moderator panel (Phase 17, PLAN.md
	D-77; CLAUDE.md §21; SECURITY_MODEL §6, T-19 / T-20).

	Roles: Owner / Admin / Moderator by UserId from server/Config/Roles (the
	creator of a user-owned place is Owner). Resolved on join; every admin
	remote names a permission that NetService checks through this service on
	**every** call, and handlers check the finer permission per action or
	config path again. A denied call is audited (never throttled). In a
	Studio local-server test (config Admin.StudioPlayer1Owner) Player1 is
	Owner and Player2 a normal player. Only staff
	are told their role (AdminHello), so the staff list never reaches
	players.

	  AdminPlayers / AdminInspect   find online players; inspect (Moderators
	                                get the limited view: no wallet / items)
	  AdminPlayerAction             kick, ban (Roblox Ban API), set level,
	                                add Gold / PvP Marks, set PvP victories
	                                ("kill points"), grant / remove items and
	                                stones, reset a stuck quest. Staff can't
	                                kick or ban staff of their rank or above.
	  AdminConfigGet / AdminConfigSet  every editable config value (drop rates,
	                                enhancement, PvP, quests, feature flags...)
	                                with its default; a batch of changes is
	                                checked against the schema and the loot
	                                rules, then saved as the next override
	                                version for every server
	                                (ConfigurationService:Write)
	  AdminBoss                     respawn the war-zone bosses now
	  AdminAudit                    recent audit entries (Moderators: only
	                                their own)
	  AdminEvents                   live events (Phase 18, D-89): the
	                                windows, start now, schedule, stop
	                                (EventService checks the template's
	                                duration, cooldown and stage)

	Every change is an audit entry with the actor, role, target and the
	before / after values. Staff stay in game during flag maintenance.
	Targets must be online on this server (offline edits would need the
	profile's session lock; later).
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local AdminRules = require(Shared.Logic.AdminRules)
local LootRules = require(Shared.Logic.LootRules)
local ItemDefinitions = require(Shared.Definitions.ItemDefinitions)
local QuestDefinitions = require(Shared.Definitions.QuestDefinitions)
local Constants = require(Shared.Constants)
local Log = require(Shared.Util.Log)

local Roles = require(script.Parent.Parent.Config.Roles)
local Maintenance = require(script.Parent.Parent.Maintenance)

local AuditLogService = require(script.Parent.AuditLogService)
local ConfigurationService = require(script.Parent.ConfigurationService)
local NetService = require(script.Parent.NetService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local LevelService = require(script.Parent.LevelService)
local InventoryService = require(script.Parent.InventoryService)
local PvPService = require(script.Parent.PvPService)
local QuestService = require(script.Parent.QuestService)
local EventService = require(script.Parent.EventService)

local log = Log.new("AdminService")

local AdminService = {}

local RANK = { Owner = 3, Admin = 2, Moderator = 1 }
local MAX_RESULTS = 30
local AUDIT_ROWS = 100

local roles: { [Player]: AdminRules.Role } = {}

local function creatorUserId(): number?
	return if game.CreatorType == Enum.CreatorType.User then game.CreatorId else nil
end

local function resolveRole(player: Player): AdminRules.Role?
	if
		RunService:IsStudio()
		and player.UserId == -1
		and ConfigurationService:Get("Admin").StudioPlayer1Owner
	then
		return "Owner"
	end
	return AdminRules.roleFor(player.UserId, creatorUserId(), Roles)
end

local function can(player: Player, permission: string): boolean
	return AdminRules.has(roles[player], permission, Roles.ModeratorGrants)
end

local function audit(actor: Player, action: string, target: string?, details: { [string]: any }?)
	local info = table.clone(details or {})
	info.role = roles[actor]
	AuditLogService:Audit({ actorUserId = actor.UserId, action = action, target = target, details = info })
end

local function fail(reason: string): { [string]: any }
	return { ok = false, reason = reason }
end

local function online(userId: number): Player?
	return Players:GetPlayerByUserId(userId)
end

-- Rank of a UserId (online staff by role; offline by the Roles list).
local function rankOf(userId: number): number
	local player = online(userId)
	local role = if player then roles[player] else AdminRules.roleFor(userId, creatorUserId(), Roles)
	return if role then RANK[role] else 0
end

--------------------------------------------------------------------------------
-- Players
--------------------------------------------------------------------------------

local function onPlayers(_actor: Player, query: string): { [string]: any }
	local needle = string.lower(query)
	local rows = {}
	for _, player in Players:GetPlayers() do
		local data = PlayerDataService:GetData(player)
		local match = needle == ""
			or string.find(string.lower(player.Name), needle, 1, true) ~= nil
			or string.find(string.lower(player.DisplayName), needle, 1, true) ~= nil
			or tostring(player.UserId) == query
		if match and #rows < MAX_RESULTS then
			table.insert(rows, {
				UserId = player.UserId,
				Name = player.Name,
				DisplayName = player.DisplayName,
				Level = if data then data.Level else 0,
				Race = if data then data.Race else nil,
				Job = if data then data.Job else nil,
			})
		end
	end
	return { ok = true, players = rows }
end

local function onInspect(actor: Player, userId: number): { [string]: any }
	local target = online(userId)
	local data = target and PlayerDataService:GetData(target)
	if target == nil or data == nil then
		return fail("offline")
	end
	local view: { [string]: any } = {
		UserId = userId,
		Name = target.Name,
		DisplayName = target.DisplayName,
		Level = data.Level,
		Experience = data.Experience,
		Race = data.Race,
		Job = data.Job,
		Victories = data.PvPStats.Victories,
		Defeats = data.PvPStats.Defeats,
		Full = false,
	}
	if can(actor, "player.inspectFull") then
		view.Full = true
		view.Wallet = { Gold = data.Wallet.Gold, PvPMarks = data.Wallet.PvPMarks }
		view.Stackables = table.clone(data.Stackables)
		local equipped = {}
		for _, guid in data.Equipment do
			equipped[guid] = true
		end
		local items = {}
		for guid, item in data.Inventory do
			local def = ItemDefinitions.get(item.DefId)
			table.insert(items, {
				Guid = guid,
				Name = if def then def.name else item.DefId,
				Rarity = item.Rarity,
				ItemLevel = item.ItemLevel,
				Enhancement = item.Enhancement,
				Equipped = equipped[guid] == true,
			})
		end
		table.sort(items, function(a, b)
			return a.ItemLevel > b.ItemLevel
		end)
		view.Items = items
		local quests = {}
		for _, quest in QuestDefinitions.List do
			local progress = data.QuestState[quest.id]
			table.insert(
				quests,
				{ Id = quest.id, Name = quest.name, Status = if progress then progress.Status else nil }
			)
		end
		view.Quests = quests
	end
	audit(actor, "AdminInspect", tostring(userId))
	return { ok = true, player = view }
end

local function kickOrBan(actor: Player, userId: number, action: string, args: any): { [string]: any }
	if userId == actor.UserId then
		return fail("self")
	end
	if rankOf(userId) >= RANK[roles[actor]] then
		return fail("rank")
	end
	local reason = args.Reason or "Other"
	local text = AdminRules.REASON_TEXT[reason]
	if action == "Kick" then
		local target = online(userId)
		if target == nil then
			return fail("offline")
		end
		audit(actor, "AdminKick", tostring(userId), { reason = reason })
		target:Kick(text)
		return { ok = true }
	end
	local minutes = args.Number
	if minutes == nil or table.find(AdminRules.BAN_MINUTES, minutes) == nil then
		return fail("duration")
	end
	local ok, err = pcall(function()
		Players:BanAsync({
			UserIds = { userId },
			ApplyToUniverse = true,
			Duration = if minutes == 0 then -1 else minutes * 60,
			DisplayReason = text,
			PrivateReason = `{reason} by {actor.UserId}`,
			ExcludeAltAccounts = false,
		})
	end)
	audit(actor, "AdminBan", tostring(userId), { reason = reason, minutes = minutes, applied = ok })
	if not ok then
		log:Warn("ban of %d failed: %s", userId, tostring(err))
		return fail("banFailed")
	end
	return { ok = true }
end

local function onPlayerAction(actor: Player, userId: number, action: string, args: any): { [string]: any }
	local permission = AdminRules.ACTION_PERMISSION[action]
	if permission == nil or not can(actor, permission) then
		audit(actor, "AdminDenied", tostring(userId), { action = action })
		return fail("permission")
	end
	if action == "Kick" or action == "Ban" then
		return kickOrBan(actor, userId, action, args)
	end
	local target = online(userId)
	local data = target and PlayerDataService:GetData(target)
	if target == nil or data == nil then
		return fail("offline")
	end
	local number = args.Number
	local before, after: any = nil, nil
	if action == "SetLevel" then
		if number == nil or number < 0 or number > Constants.Level.Max then
			return fail("value")
		end
		before = data.Level
		if not LevelService:SetLevel(target, number) then
			return fail("value")
		end
		after = number
	elseif action == "AddCurrency" then
		local currency = args.Currency
		if currency == nil or number == nil or number == 0 then
			return fail("value")
		end
		before = data.Wallet[currency]
		data.Wallet[currency] = math.max(before + number, 0)
		after = data.Wallet[currency]
	elseif action == "SetVictories" then
		if number == nil or number < 0 or number > AdminRules.MAX_VICTORIES then
			return fail("value")
		end
		before = data.PvPStats.Victories
		data.PvPStats.Victories = number
		after = number
		PvPService:RefreshTitles(target)
	elseif action == "GrantItem" then
		if args.DefId == nil or args.Rarity == nil or number == nil then
			return fail("value")
		end
		local item, why =
			InventoryService:GrantItem(target, args.DefId, args.Rarity, number, `Admin:{actor.UserId}`)
		if item == nil then
			return fail(why or "grant")
		end
		after = { guid = item.Guid, def = args.DefId, rarity = args.Rarity, itemLevel = number }
	elseif action == "GrantStackable" then
		if args.Stackable == nil or number == nil or number < 1 or number > 999 then
			return fail("value")
		end
		local added = InventoryService:GrantStackable(target, args.Stackable, number, `Admin:{actor.UserId}`)
		if added <= 0 then
			return fail("full")
		end
		after = { id = args.Stackable, added = added }
	elseif action == "RemoveItem" then
		if args.Guid == nil then
			return fail("value")
		end
		local item = data.Inventory[args.Guid]
		local ok, why = InventoryService:RemoveItem(target, args.Guid)
		if not ok then
			return fail(why or "remove")
		end
		before = { guid = args.Guid, def = item and item.DefId, rarity = item and item.Rarity }
	elseif action == "ResetQuest" then
		if args.Quest == nil or not QuestService:AdminReset(target, args.Quest) then
			return fail("value")
		end
		before = args.Quest
	end
	PlayerDataService:PushSnapshot(target)
	audit(
		actor,
		`Admin{action}`,
		tostring(userId),
		{ before = before, after = after, currency = args.Currency }
	)
	return { ok = true }
end

--------------------------------------------------------------------------------
-- Config
--------------------------------------------------------------------------------

local function onConfigGet(actor: Player): { [string]: any }
	local entries = AdminRules.flatten(
		ConfigurationService:GetSpec(),
		ConfigurationService:GetEffective(),
		ConfigurationService:GetDefaults()
	)
	local visible = {}
	for _, entry in entries do
		local permission = AdminRules.permissionForPath(entry.path)
		if permission and can(actor, permission) then
			table.insert(visible, entry)
		end
	end
	return { ok = true, version = ConfigurationService:GetVersion(), entries = visible }
end

-- Loot weights must sum to 100 (the schema alone can't say that).
local function lootProblem(config: any): string?
	for id, t in config.Loot.Tables do
		local ok, reason = LootRules.validate(t)
		if not ok then
			return `Loot.Tables.{id}: {reason}`
		end
	end
	for id, t in config.Loot.StoneTables do
		local ok, reason = LootRules.validateStones(t)
		if not ok then
			return `Loot.StoneTables.{id}: {reason}`
		end
	end
	return nil
end

local function onConfigSet(
	actor: Player,
	baseVersion: number,
	changes: { AdminRules.Change }
): { [string]: any }
	if #changes == 0 then
		return fail("empty")
	end
	for _, change in changes do
		local permission = AdminRules.permissionForPath(change.Path)
		if permission == nil or not can(actor, permission) then
			audit(actor, "AdminDenied", change.Path, { action = "ConfigSet" })
			return fail(`permission {change.Path}`)
		end
	end
	if baseVersion ~= ConfigurationService:GetVersion() then
		return fail("stale")
	end
	local effective = ConfigurationService:GetEffective()
	local values, why = AdminRules.applyChanges(
		ConfigurationService:GetSpec(),
		ConfigurationService:GetOverrideValues(),
		effective,
		changes
	)
	if values == nil then
		return fail(why or "invalid")
	end
	local checked, candidate = ConfigurationService:Check(values)
	if not checked then
		return fail(tostring(candidate))
	end
	local problem = lootProblem(candidate)
	if problem then
		return fail(problem)
	end
	local ok, reason, saved = ConfigurationService:Write(values, baseVersion, actor.UserId)
	if not ok then
		return fail(reason or "save")
	end
	local diff = {}
	for _, change in changes do
		table.insert(diff, {
			path = change.Path,
			before = AdminRules.getPath(effective, change.Path),
			after = AdminRules.getPath(candidate, change.Path),
		})
	end
	audit(actor, "ConfigChange", `v{ConfigurationService:GetVersion()}`, { changes = diff, saved = saved })
	return { ok = true, version = ConfigurationService:GetVersion(), saved = saved }
end

--------------------------------------------------------------------------------
-- World and audit
--------------------------------------------------------------------------------

local function onBoss(actor: Player, action: string): { [string]: any }
	local count = PvPService:RespawnBosses()
	audit(actor, "AdminBossRespawn", action, { count = count })
	return { ok = true, count = count }
end

local function onEvents(actor: Player, action: string, args: { [string]: any }): { [string]: any }
	if action == "List" then
		return { ok = true, now = os.time(), windows = EventService:GetWindows() }
	end
	local id = args.Id
	if type(id) ~= "string" then
		return fail("event")
	end
	if action == "Stop" then
		local ok, reason = EventService:Stop(id, actor.UserId)
		if not ok then
			return fail(reason or "stop")
		end
		audit(actor, "EventStop", id)
		return { ok = true }
	end
	local minutes = args.Minutes
	if type(minutes) ~= "number" then
		return fail("duration")
	end
	local startsAt = if action == "Schedule" then args.StartsAt else os.time()
	if type(startsAt) ~= "number" then
		return fail("time")
	end
	local ok, reason, window = EventService:Schedule(id, startsAt, minutes, actor.UserId)
	if not ok or window == nil then
		return fail(reason or "schedule")
	end
	audit(
		actor,
		if action == "Start" then "EventStart" else "EventSchedule",
		id,
		{ startsAt = window.StartsAt, endsAt = window.EndsAt }
	)
	return { ok = true, window = window }
end

local function short(value: any): string
	local ok, text = pcall(HttpService.JSONEncode, HttpService, value)
	text = if ok then text else tostring(value)
	return if #text > 240 then string.sub(text, 1, 237) .. "..." else text
end

local function onAudit(actor: Player): { [string]: any }
	local entries = AuditLogService:GetBuffered()
	local all = can(actor, "audit.viewAll")
	local rows = {}
	for index = #entries, 1, -1 do
		local entry = entries[index]
		if all or entry.actorUserId == actor.UserId then
			table.insert(rows, {
				At = entry.at or 0,
				Actor = entry.actorUserId,
				Action = entry.action,
				Target = entry.target,
				Details = if entry.details then short(entry.details) else nil,
			})
			if #rows >= AUDIT_ROWS then
				break
			end
		end
	end
	return { ok = true, rows = rows }
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

local function hello(player: Player)
	local role = roles[player]
	if role then
		NetService:FireClient("AdminHello", player, {
			Role = role,
			Permissions = AdminRules.permissionsFor(role :: AdminRules.Role, Roles.ModeratorGrants),
		})
	end
end

function AdminService:Init()
	NetService:SetPermissionChecker(function(player, permission)
		if can(player, permission) then
			return true
		end
		AuditLogService:Audit({ actorUserId = player.UserId, action = "AdminDenied", target = permission })
		return false
	end)
	Maintenance.setExempt(function(player)
		local role = resolveRole(player)
		return role == "Owner" or role == "Admin"
	end)
	NetService:Handle("AdminPlayers", onPlayers)
	NetService:Handle("AdminInspect", onInspect)
	NetService:Handle("AdminPlayerAction", onPlayerAction)
	NetService:Handle("AdminConfigGet", onConfigGet)
	NetService:Handle("AdminConfigSet", onConfigSet)
	NetService:Handle("AdminBoss", onBoss)
	NetService:Handle("AdminAudit", onAudit)
	NetService:Handle("AdminEvents", onEvents)
end

function AdminService:Start()
	local function join(player: Player)
		roles[player] = resolveRole(player) :: any
		if roles[player] then
			log:Info("%s joined as %s", player.Name, roles[player])
		end
	end
	for _, player in Players:GetPlayers() do
		join(player)
	end
	Players.PlayerAdded:Connect(join)
	Players.PlayerRemoving:Connect(function(player)
		roles[player] = nil
	end)
	NetService.PlayerReady:Connect(hello)
	for _, player in Players:GetPlayers() do
		if NetService:IsReady(player) then
			hello(player)
		end
	end
end

return AdminService
