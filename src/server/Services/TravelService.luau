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
	  - Respawn resolvers may pick a different spawn, e.g. the dungeon
	    checkpoint while rejoin charges remain (D-20) or a run a
	    disconnected member is rejoining. D-107: defeated in a war zone ->
	    your realm's camp in that zone (PvPService). Otherwise: the race
	    home spawn.
	  - `Teleport` moves a living character (dungeon entry / return home);
	    destinations always come from server data, never from clients.

	Walk-through portals (creator review 2026-10-17: no prompt to hold):
	  - `AddWalkPortal(surface, onEnter)`: walking into a portal surface
	    (its glowing plane, with a little depth either side) calls
	    `onEnter(player)` once per entry, checked on the server 10 times a
	    second from the character's position. The handler keeps its own
	    checks (level, reach, combat tag) and teleports.
	  - After any teleport the player must step out of every portal before
	    another can fire (so arriving next to one never chains), and
	    portals rest for PORTAL_COOLDOWN seconds.
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
local PORTAL_HZ = 10
local PORTAL_COOLDOWN = 1.5
-- How far in front of / behind the portal plane, and around its edges,
-- a character counts as walking through it (studs).
local PORTAL_DEPTH = 3
local PORTAL_MARGIN = 1.5
local SPAWN_TOLERANCE = 40

local log = Log.new("TravelService")

local TravelService = {}

local spawning: { [Player]: boolean } = {}
-- Where each player's current character is supposed to appear.
local expected: { [Player]: CFrame } = {}
-- The portal each player is standing in (false: just teleported, must step
-- out of every portal first), and when portals may fire again for them.
local insidePortal: { [Player]: BasePart | false } = {}
local portalReadyAt: { [Player]: number } = {}
-- Asked in order; the first CFrame wins (D-107: nearest safe spawn).
local respawnResolvers: { (Player) -> CFrame? } = {}

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
			-- A respawn point may sit in a portal (a war-zone camp's return
			-- portal, a dungeon floor's entrance): arriving never fires it
			-- (D-107); walk out and back in to use it.
			insidePortal[player] = false
			portalReadyAt[player] = os.clock() + PORTAL_COOLDOWN
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
	-- A dungeon checkpoint (or a run being rejoined) or a war-zone camp
	-- overrides home.
	local override: CFrame? = nil
	for _, resolve in respawnResolvers do
		override = resolve(player)
		if override then
			break
		end
	end
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
	Adds a decider for non-home respawns (DungeonService, PvPService).
	`resolver(player)` returns a CFrame to spawn at, or nil to pass. Must
	not yield.
]]
function TravelService:AddRespawnResolver(resolver: (Player) -> CFrame?)
	table.insert(respawnResolvers, resolver)
end

type WalkPortal = { surface: BasePart, onEnter: (Player) -> () }
local portals: { WalkPortal } = {}

--[[
	Walking into `surface` (a portal's plane: thinnest axis is its depth)
	calls `onEnter(player)` once per entry. Server-side, from the character's
	position; no remote and no prompt.
]]
function TravelService:AddWalkPortal(surface: BasePart, onEnter: (Player) -> ())
	table.insert(portals, { surface = surface, onEnter = onEnter })
end

local function insideOf(surface: BasePart, position: Vector3): boolean
	local p = surface.CFrame:PointToObjectSpace(position)
	local size = surface.Size
	-- The thinnest axis is the plane's depth.
	local depthAxis = if size.X <= size.Y and size.X <= size.Z
		then "X"
		elseif size.Y <= size.Z then "Y"
		else "Z"
	local function within(axis: string, value: number, half: number): boolean
		local pad = if axis == depthAxis then PORTAL_DEPTH else PORTAL_MARGIN
		return math.abs(value) <= half + pad
	end
	return within("X", p.X, size.X / 2) and within("Y", p.Y, size.Y / 2) and within("Z", p.Z, size.Z / 2)
end

local function sweepPortals()
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root == nil or not root:IsA("BasePart") then
			continue
		end
		local inside: BasePart? = nil
		local entered: WalkPortal? = nil
		for _, portal in portals do
			if portal.surface.Parent and insideOf(portal.surface, root.Position) then
				inside = portal.surface
				entered = portal
				break
			end
		end
		local previous = insidePortal[player]
		if inside == nil then
			insidePortal[player] = nil
		elseif previous == nil and now >= (portalReadyAt[player] or 0) then
			insidePortal[player] = inside
			local portal = entered :: WalkPortal
			task.spawn(portal.onEnter, player)
		elseif previous ~= false and previous ~= inside then
			insidePortal[player] = inside
		end
	end
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
	-- Arriving never fires a portal: step out of every portal first.
	insidePortal[player] = false
	portalReadyAt[player] = os.clock() + PORTAL_COOLDOWN
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
		insidePortal[player] = nil
		portalReadyAt[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(1 / PORTAL_HZ)
			local ok, err = pcall(sweepPortals :: any)
			if not ok then
				log:Error("portal sweep failed: %s", tostring(err))
			end
		end
	end)
end

return TravelService
