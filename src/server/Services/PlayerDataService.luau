--!strict
--[[
	PlayerDataService (Layer 1, critical)
	Owns every player profile session (docs/DATA_MODEL.md):

	  join  -> start session (ProfileStore lock) -> migrate (on a copy)
	        -> validate/repair -> ProfileLoaded -> snapshot to client
	  leave -> ProfileReleasing -> end session (final save)

	Rules:
	  - Never play on a blank profile: any load failure kicks the player.
	  - A profile saved by a newer build is never loaded or downgraded.
	  - Other services read/mutate `GetData(player)` synchronously (no yields
	    between check and write, DATA_MODEL.md §4.1).
	  - Rewards go through `ClaimReward` (idempotent, DATA_MODEL.md §4.2).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Log = require(Shared.Util.Log)
local Signal = require(Shared.Util.Signal)

local Persistence = script.Parent.Parent.Persistence
local PersistenceAdapter = require(Persistence.PersistenceAdapter)
local ProfileTemplate = require(Persistence.ProfileTemplate)
local ProfileValidator = require(Persistence.ProfileValidator)
local Migrations = require(Persistence.Migrations)
local RewardClaims = require(Persistence.RewardClaims)
local ProfileView = require(Persistence.ProfileView)

local AuditLogService = require(script.Parent.AuditLogService)
local NetService = require(script.Parent.NetService)

local STORE_NAME = "RC_Profiles_v1"

local KICK_LOAD_FAILED = "We couldn't load your save. Please rejoin in a moment — your progress is safe."
local KICK_NEWER_VERSION = "The game was just updated. Please rejoin to continue."
local KICK_SESSION_ENDED = "Your save was opened on another server. Please rejoin."

local log = Log.new("PlayerDataService")

local PlayerDataService = {
	-- (player, data) after load + repair. Handlers must not yield.
	ProfileLoaded = Signal.new(),
	-- (player, data) right before the session ends (last chance to write).
	ProfileReleasing = Signal.new(),
}

local store: PersistenceAdapter.Store
-- True once the server is closing; ProfileStore then ends every session itself.
local shuttingDown = false
local sessions: { [Player]: PersistenceAdapter.Session } = {}

local function profileKey(player: Player): string
	return `Player_{player.UserId}`
end

local function stillHere(player: Player): boolean
	return player.Parent == Players
end

local function sendSnapshot(player: Player)
	local session = sessions[player]
	if session and NetService:IsReady(player) then
		NetService:FireClient("ProfileSnapshot", player, ProfileView.snapshot(session:getData()))
	end
end

local function load(player: Player)
	local session = store:startSession(profileKey(player), function()
		return not stillHere(player)
	end)

	if session == nil then
		if stillHere(player) then
			log:Error("profile session failed for %d", player.UserId)
			player:Kick(KICK_LOAD_FAILED)
		end
		return
	end

	session:addUserId(player.UserId)

	if not stillHere(player) then
		session:endSession()
		return
	end

	-- Migrate a copy; adopt only on success so stored data is never half-migrated.
	local status, result = Migrations.migrate(session:getData())
	if status == "newer" then
		log:Warn("profile for %d is schema v%s (newer than this build)", player.UserId, tostring(result))
		player:Kick(KICK_NEWER_VERSION)
		session:endSession()
		return
	elseif status == "error" then
		log:Error("migration failed for %d: %s", player.UserId, tostring(result))
		player:Kick(KICK_LOAD_FAILED)
		session:endSession()
		return
	end
	session:setData(result)
	local data = result

	local repairs = ProfileValidator.repair(data)
	if #repairs > 0 then
		AuditLogService:Security(player, "ProfileRepair", table.concat(repairs, "; "))
	end

	local now = os.time()
	RewardClaims.prune(data, now)
	if data.CreatedAt == 0 then
		data.CreatedAt = now
	end
	data.LastLoginAt = now

	sessions[player] = session
	session:onSessionEnd(function()
		if sessions[player] == session then
			sessions[player] = nil
			if stillHere(player) and not shuttingDown then
				-- Another server took the session (or the save was lost); never keep playing.
				player:Kick(KICK_SESSION_ENDED)
			end
		end
	end)

	log:Debug("profile loaded for %d (L%d)", player.UserId, data.Level)
	PlayerDataService.ProfileLoaded:Fire(player, data)
	sendSnapshot(player)
end

local function release(player: Player)
	local session = sessions[player]
	if session == nil then
		return
	end
	PlayerDataService.ProfileReleasing:Fire(player, session:getData())
	sessions[player] = nil
	session:endSession()
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function PlayerDataService:Init()
	store = PersistenceAdapter.open(STORE_NAME, ProfileTemplate.new())

	NetService:RegisterStateCheck("ProfileLoaded", function(player)
		return sessions[player] ~= nil
	end)

	NetService.PlayerReady:Connect(sendSnapshot)
end

function PlayerDataService:Start()
	game:BindToClose(function()
		shuttingDown = true
	end)
	Players.PlayerAdded:Connect(load)
	Players.PlayerRemoving:Connect(release)
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end
	log:Info("DataStore state: %s", PersistenceAdapter.getDataStoreState())
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--[[
	Returns the live profile data for a loaded player, or nil. Callers must not
	yield between reading and writing it, and must never store client payloads
	in it.
]]
function PlayerDataService:GetData(player: Player): { [string]: any }?
	local session = sessions[player]
	return if session then session:getData() else nil
end

function PlayerDataService:IsLoaded(player: Player): boolean
	return sessions[player] ~= nil
end

--[[
	Grants a reward at most once. `grant` mutates the data synchronously.
	Returns the claim status ("granted" | "already" | "invalid" | "error" |
	"notLoaded").
]]
function PlayerDataService:ClaimReward(
	player: Player,
	rewardId: string,
	grant: (data: { [string]: any }) -> ()
): string
	local data = self:GetData(player)
	if data == nil then
		return "notLoaded"
	end
	local status, err = RewardClaims.claim(data, rewardId, os.time(), grant)
	if status == "error" then
		-- Claim stays recorded (no duplication); support can restore from this log line.
		log:Error("reward grant failed user=%d reward=%s: %s", player.UserId, rewardId, tostring(err))
	elseif status == "invalid" then
		log:Error("invalid reward id from server code: %s", tostring(rewardId))
	end
	return status
end

-- Re-sends the snapshot (used by later phases after identity changes).
function PlayerDataService:PushSnapshot(player: Player)
	sendSnapshot(player)
end

return PlayerDataService
