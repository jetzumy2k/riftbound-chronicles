--!strict
--[[
	TravelService (Layer 5)
	Owns where and when characters spawn (ARCHITECTURE.md §2, named to avoid
	shadowing the engine's TeleportService).

	Phase 3 rules:
	  - `Players.CharacterAutoLoads` is false (default.project.json). A player
	    gets a character only after choosing a race and a job; until then the
	    selection screens are shown.
	  - Players always spawn at their own race's fixed SpawnLocation
	    (deterministic), after streaming that area in.
	  - Respawns happen when CombatService requests them (defeat or reset,
	    SECURITY_MODEL §5A.1). Every server-driven move grants an
	    AntiExploitService grace window first.
	  - After spawning, the server verifies the character is near the expected
	    spawn and corrects it if not.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Log = require(ReplicatedStorage.Shared.Util.Log)

local PlayerDataService = require(script.Parent.PlayerDataService)
local RaceService = require(script.Parent.RaceService)
local JobService = require(script.Parent.JobService)
local AntiExploitService = require(script.Parent.AntiExploitService)
local CombatService = require(script.Parent.CombatService)
local WorldService = require(script.Parent.WorldService)

local STREAM_TIMEOUT = 5
local SPAWN_TOLERANCE = 40

local log = Log.new("TravelService")

local TravelService = {}

local spawning: { [Player]: boolean } = {}

local function homeSpawn(player: Player): SpawnLocation?
	local data = PlayerDataService:GetData(player)
	-- A character only enters the world once race and job are both chosen.
	if data == nil or data.Race == nil or data.Job == nil then
		return nil
	end
	return WorldService:GetSpawnLocation(data.Race)
end

local function verifySpawn(player: Player, character: Model)
	local spawn = homeSpawn(player)
	if spawn == nil then
		return
	end
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if root == nil or not root:IsA("BasePart") or character.Parent == nil then
		return
	end
	if (root.Position - spawn.Position).Magnitude > SPAWN_TOLERANCE then
		log:Warn("user=%d spawned away from home spawn; correcting", player.UserId)
		AntiExploitService:GrantGrace(player, 2)
		character:PivotTo(spawn.CFrame + Vector3.new(0, 4, 0))
	end
end

--[[
	Spawns (or respawns) the player at their race's home spawn. Yields while the
	area streams in. No-op if the player has no race or is already spawning.
]]
function TravelService:SpawnAtHome(player: Player)
	if spawning[player] then
		return
	end
	local spawn = homeSpawn(player)
	if spawn == nil then
		return
	end

	spawning[player] = true
	player.RespawnLocation = spawn
	AntiExploitService:GrantGrace(player, 3)
	pcall(function()
		player:RequestStreamAroundAsync(spawn.Position, STREAM_TIMEOUT)
	end)
	if player.Parent == Players then
		local ok, err = pcall(function()
			player:LoadCharacterAsync()
		end)
		if not ok then
			log:Error("LoadCharacterAsync failed for %d: %s", player.UserId, tostring(err))
		end
	end
	spawning[player] = nil
end

local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		task.spawn(verifySpawn, player, character)
	end)
end

function TravelService:Init()
	-- Returning players: spawn as soon as the profile is ready.
	PlayerDataService.ProfileLoaded:Connect(function(player, data)
		if data.Race ~= nil and data.Job ~= nil then
			task.spawn(TravelService.SpawnAtHome, TravelService, player)
		end
	end)
	-- New players: spawn once the second of race/job is chosen (homeSpawn
	-- returns nil until both are set, so either signal may trigger it).
	RaceService.RaceChosen:Connect(function(player)
		task.spawn(TravelService.SpawnAtHome, TravelService, player)
	end)
	JobService.JobChosen:Connect(function(player)
		task.spawn(TravelService.SpawnAtHome, TravelService, player)
	end)
	-- Defeat / reset (CombatService decides when; SECURITY_MODEL §5A.1).
	CombatService.RespawnRequested:Connect(function(player)
		task.spawn(TravelService.SpawnAtHome, TravelService, player)
	end)
end

function TravelService:Start()
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		spawning[player] = nil
	end)
end

return TravelService
