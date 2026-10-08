--!strict
--[[
	NetService (Layer 0)
	Creates every remote from the shared Registry and runs the validation
	pipeline for client -> server calls (SECURITY_MODEL.md §4):

	  rate limit (global, then per remote) -> arity -> schema -> player state
	  -> permission -> handler (error boundary) -> result

	Every rejection is counted, logged to the security stream (throttled) and
	fired on `NetService.Rejected` so AntiExploitService (Phase 6) can act.

	Usage from other services (during their Init):
	    NetService:Handle("EquipSkill", function(player, skillId, slot) ... end)
	    NetService:RegisterStateCheck("Alive", function(player) return ... end)
	    NetService:FireClient("Notify", player, payload)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Constants = require(Shared.Constants)
local Schema = require(Shared.Logic.Schema)
local NetSpec = require(Shared.Net.NetSpec)
local Registry: { [string]: NetSpec.RemoteSpec } = require(Shared.Net.Registry)(Schema) :: any
local Log = require(Shared.Util.Log)
local Guard = require(Shared.Util.Guard)
local Signal = require(Shared.Util.Signal)

local ConfigurationService = require(script.Parent.ConfigurationService)
local AuditLogService = require(script.Parent.AuditLogService)
local RateLimitService = require(script.Parent.RateLimitService)

local GLOBAL_BUCKET_KEY = "net:global"

local log = Log.new("NetService")

local NetService = {
	-- (player, remoteName, rejectCode)
	Rejected = Signal.new(),
	-- (player) — client finished initialising and can receive pushes.
	PlayerReady = Signal.new(),
}

type Handler = (player: Player, ...any) -> ...any

local remotes: { [string]: Instance } = {}
local handlers: { [string]: Handler } = {}
local stateCheckers: { [string]: (player: Player) -> boolean } = {}
local permissionChecker: ((player: Player, permission: string) -> boolean)? = nil
local readyPlayers: { [Player]: true } = {}
local rejectCounts: { [Player]: number } = {}

--------------------------------------------------------------------------------
-- Pipeline
--------------------------------------------------------------------------------

local function reject(player: Player, name: string, code: string, detail: string?)
	rejectCounts[player] = (rejectCounts[player] or 0) + 1
	AuditLogService:Security(player, code, `{name}: {detail or ""}`)
	NetService.Rejected:Fire(player, name, code)
	return { ok = false, code = code }
end

local function dispatch(name: string, spec: NetSpec.RemoteSpec, player: Player, count: number, args: { any })
	local globalCapacity = ConfigurationService:Get("Net.GlobalCapacity")
	local globalRefill = ConfigurationService:Get("Net.GlobalRefillPerSecond")
	if not RateLimitService:Consume(player, GLOBAL_BUCKET_KEY, globalCapacity, globalRefill) then
		return reject(player, name, "RateLimited", "global budget")
	end
	local rate = spec.rate :: NetSpec.RateSpec
	if not RateLimitService:Consume(player, `net:{name}`, rate.capacity, rate.refillPerSecond) then
		return reject(player, name, "RateLimited", "remote budget")
	end

	local valid, reason, code = Schema.validateArgs(spec.args, count, args)
	if not valid then
		return reject(player, name, code or "BadArgs", reason)
	end

	for _, state in spec.states :: { string } do
		local checker = stateCheckers[state]
		-- Fail closed: an unregistered state check rejects.
		if checker == nil or not checker(player) then
			return reject(player, name, "BadState", state)
		end
	end

	if spec.permission ~= nil then
		local permission = spec.permission :: string
		if permissionChecker == nil or not permissionChecker(player, permission) then
			return reject(player, name, "NoPermission", permission)
		end
	end

	local handler = handlers[name]
	if handler == nil then
		return reject(player, name, "NoHandler")
	end

	local results =
		table.pack(Guard.call(log, `remote {name}`, handler, player, table.unpack(args, 1, #spec.args)))
	if not results[1] then
		-- Never send internal error text to the client.
		return reject(player, name, "HandlerError")
	end
	return table.unpack(results, 2, results.n)
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function NetService:Init()
	local valid, errors = NetSpec.validateRegistry(Registry, Schema)
	if not valid then
		error("invalid remote registry: " .. table.concat(errors :: { string }, "; "))
	end

	local existing = ReplicatedStorage:FindFirstChild(Constants.Net.RemotesFolderName)
	if existing then
		log:Warn("replacing pre-existing remotes folder")
		existing:Destroy()
	end

	-- Build off-DataModel, then parent once so clients see a complete set.
	local folder = Instance.new("Folder")
	folder.Name = Constants.Net.RemotesFolderName
	for name, spec in Registry do
		local remote = Instance.new(if spec.kind == "Function" then "RemoteFunction" else "RemoteEvent")
		remote.Name = name
		remote.Parent = folder
		remotes[name] = remote
	end

	self:RegisterStateCheck("Ready", function(player)
		return readyPlayers[player] == true
	end)

	self:Handle("ClientReady", function(player)
		if readyPlayers[player] then
			return
		end
		readyPlayers[player] = true
		log:Debug("client ready: %d", player.UserId)
		NetService.PlayerReady:Fire(player)
		NetService:FireClient("Notify", player, { kind = "Welcome", textKey = "system.welcome" })
	end)

	folder.Parent = ReplicatedStorage
end

function NetService:Start()
	for name, spec in Registry do
		if spec.direction ~= "ClientToServer" then
			continue
		end
		if handlers[name] == nil then
			log:Error("no handler registered for '%s' (calls will be rejected)", name)
		end
		-- validateRegistry guarantees ClientToServer remotes declare states.
		for _, state in spec.states :: { string } do
			if stateCheckers[state] == nil then
				log:Error("remote '%s' uses unregistered state '%s' (calls will be rejected)", name, state)
			end
		end

		local remote = remotes[name]
		if spec.kind == "Function" then
			(remote :: RemoteFunction).OnServerInvoke = function(player: Player, ...: any)
				return dispatch(name, spec, player, select("#", ...), { ... })
			end
		else
			(remote :: RemoteEvent).OnServerEvent:Connect(function(player: Player, ...: any)
				dispatch(name, spec, player, select("#", ...), { ... })
			end)
		end
	end

	Players.PlayerRemoving:Connect(function(player)
		readyPlayers[player] = nil
		rejectCounts[player] = nil
	end)

	local count = 0
	for _ in remotes do
		count += 1
	end
	log:Info("published %d remotes", count)
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

-- Registers the single handler for a ClientToServer remote.
function NetService:Handle(name: string, handler: Handler)
	local spec = Registry[name]
	assert(spec ~= nil, `unknown remote '{name}'`)
	assert(spec.direction == "ClientToServer", `'{name}' is not a ClientToServer remote`)
	assert(handlers[name] == nil, `handler for '{name}' already registered`)
	handlers[name] = handler
end

-- Registers a named player-state predicate referenced by Registry `states`.
function NetService:RegisterStateCheck(state: string, checker: (player: Player) -> boolean)
	assert(stateCheckers[state] == nil, `state check '{state}' already registered`)
	stateCheckers[state] = checker
end

-- Installs the permission checker used for remotes with `permission` (Phase 17).
function NetService:SetPermissionChecker(checker: (player: Player, permission: string) -> boolean)
	assert(permissionChecker == nil, "permission checker already set")
	permissionChecker = checker
end

local function checkOutgoing(name: string, count: number, args: { any }): boolean
	local spec = Registry[name]
	if spec == nil or spec.direction ~= "ServerToClient" then
		log:Error("'%s' is not a ServerToClient remote", name)
		return false
	end
	local valid, reason = Schema.validateArgs(spec.args, count, args)
	if not valid then
		-- Server bug: refuse to send malformed payloads.
		log:Error("outgoing '%s' payload invalid: %s", name, tostring(reason))
		return false
	end
	return true
end

function NetService:FireClient(name: string, player: Player, ...: any)
	if checkOutgoing(name, select("#", ...), { ... }) then
		(remotes[name] :: RemoteEvent):FireClient(player, ...)
	end
end

function NetService:FireAllClients(name: string, ...: any)
	if checkOutgoing(name, select("#", ...), { ... }) then
		(remotes[name] :: RemoteEvent):FireAllClients(...)
	end
end

function NetService:FireClients(name: string, players: { Player }, ...: any)
	if checkOutgoing(name, select("#", ...), { ... }) then
		local remote = remotes[name] :: RemoteEvent
		for _, player in players do
			remote:FireClient(player, ...)
		end
	end
end

function NetService:IsReady(player: Player): boolean
	return readyPlayers[player] == true
end

function NetService:GetRejectCount(player: Player): number
	return rejectCounts[player] or 0
end

return NetService
