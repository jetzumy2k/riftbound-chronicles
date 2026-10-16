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

	Phase 9:
	  - A respawn resolver (DungeonService) may pick a different spawn, e.g.
	    the dungeon checkpoint while rejoin charges remain (D-20) or a run a
	    disconnected member is rejoining. Otherwise: the race home spawn.
	  - `Teleport` moves a living character (dungeon entry / return home);
	    destinations always come from server data, never from clients.
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
-- Where each player's current character is supposed to appear.
local expected: { [Player]: CFrame } = {}
local respawnResolver: ((Player) -> CFrame?)? = nil

local function homeSpawn(player: Player): SpawnLocation?
	local data = PlayerDataService:GetData(player)
	-- A character only enters the world once race and job are both chosen.
	if data == nil or data.Race == nil or data.Job == nil then
		return nil
	end
	return WorldService:GetSpawnLocation(data.Race)
end

-- How long after a spawn the server keeps checking the character's position.
local VERIFY_SECONDS = 3
local VERIFY_INTERVAL = 0.25

--[[
	Places a new character at its expected spawn. The client owns its
	character's physics and may briefly keep simulating from where the
	engine first put it (the home SpawnLocation), which can undo a single
	server move, so this re-checks for a few seconds and corrects again.
]]
local function verifySpawn(player: Player, character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if root == nil or not root:IsA("BasePart") then
		return
	end
	local deadline = os.clock() + VERIFY_SECONDS
	local corrected = 0
	while os.clock() < deadline and character.Parent ~= nil and player.Character == character do
		local target: CFrame? = expected[player]
		if target == nil then
			local spawn = homeSpawn(player)
			if spawn == nil then
				return
			end
			target = spawn.CFrame + Vector3.new(0, 4, 0)
		end
		if (root.Position - (target :: CFrame).Position).Magnitude > SPAWN_TOLERANCE then
			if corrected == 0 then
				-- Make sure the client has the destination's floor loaded.
				pcall(function()
					player:RequestStreamAroundAsync((target :: CFrame).Position, STREAM_TIMEOUT)
				end)
				if not character:IsDescendantOf(game) or player.Character ~= character then
					return
				end
			end
			AntiExploitService:GrantGrace(player, 2)
			character:PivotTo(target :: CFrame)
			-- Stop any fall speed carried over from the spawn point.
			root.AssemblyLinearVelocity = Vector3.zero
			corrected += 1
		end
		task.wait(VERIFY_INTERVAL)
	end
	if corrected > 0 then
		log:Info("user=%d placed at its spawn (%d corrections)", player.UserId, corrected)
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
	-- A dungeon checkpoint (or a run being rejoined) overrides home.
	local override = if respawnResolver then respawnResolver(player) else nil
	local target = override or (spawn.CFrame + Vector3.new(0, 4, 0))

	spawning[player] = true
	player.RespawnLocation = spawn
	expected[player] = target
	AntiExploitService:GrantGrace(player, 3)
	pcall(function()
		player:RequestStreamAroundAsync(target.Position, STREAM_TIMEOUT)
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

--[[
	Sets who decides non-home respawns (DungeonService). `resolver(player)`
	returns a CFrame to spawn at, or nil for the home spawn. Must not yield.
]]
function TravelService:SetRespawnResolver(resolver: (Player) -> CFrame?)
	respawnResolver = resolver
end

-- The player's home spawn CFrame (standing height), if they have a race.
function TravelService:GetHomeCFrame(player: Player): CFrame?
	local spawn = homeSpawn(player)
	return if spawn then spawn.CFrame + Vector3.new(0, 4, 0) else nil
end

--[[
	Moves a living character to `target` (server data only). Streams the area
	in first and grants a movement-validation grace window. Yields.
]]
function TravelService:Teleport(player: Player, target: CFrame): boolean
	local character = player.Character
	if character == nil or character.Parent == nil then
		return false
	end
	expected[player] = target
	AntiExploitService:GrantGrace(player, 3)
	pcall(function()
		player:RequestStreamAroundAsync(target.Position, STREAM_TIMEOUT)
	end)
	if player.Character ~= character or character.Parent == nil then
		return false
	end
	character:PivotTo(target)
	return true
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
		expected[player] = nil
	end)
end

return TravelService
