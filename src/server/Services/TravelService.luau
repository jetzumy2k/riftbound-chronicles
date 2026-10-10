--!strict
--[[
	TravelService (Layer 5)
	Owns where and when characters spawn (ARCHITECTURE.md §2, named to avoid
	shadowing the engine's TeleportService).

	Phase 3 rules:
	  - `Players.CharacterAutoLoads` is false (default.project.json). A player
	    without a race never gets a character; the race screen is shown.
	  - Players always spawn at their own race's fixed SpawnLocation
	    (deterministic), after streaming that area in.
	  - On death the player respawns at home after a short delay. Phase 6
	    replaces this with the authoritative defeat flow (SECURITY_MODEL §5A.1).
	  - After spawning, the server verifies the character is near the expected
	    spawn and corrects it if not.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Log = require(ReplicatedStorage.Shared.Util.Log)

local PlayerDataService = require(script.Parent.PlayerDataService)
local RaceService = require(script.Parent.RaceService)
local WorldService = require(script.Parent.WorldService)

local RESPAWN_DELAY = 3
local STREAM_TIMEOUT = 5
local SPAWN_TOLERANCE = 40

local log = Log.new("TravelService")

local TravelService = {}

local spawning: { [Player]: boolean } = {}

local function homeSpawn(player: Player): SpawnLocation?
	local data = PlayerDataService:GetData(player)
	if data == nil or data.Race == nil then
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

		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid and humanoid:IsA("Humanoid") then
			humanoid.Died:Connect(function()
				task.delay(RESPAWN_DELAY, function()
					-- Only respawn if this is still the player's current character.
					if player.Parent == Players and player.Character == character then
						TravelService:SpawnAtHome(player)
					end
				end)
			end)
		end
	end)
end

function TravelService:Init()
	-- Returning players: spawn as soon as the profile is ready.
	PlayerDataService.ProfileLoaded:Connect(function(player, data)
		if data.Race ~= nil then
			task.spawn(TravelService.SpawnAtHome, TravelService, player)
		end
	end)
	-- New players: spawn right after choosing a race.
	RaceService.RaceChosen:Connect(function(player)
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
