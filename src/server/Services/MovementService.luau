--!strict
--[[
	MovementService (Layer 4) — Walk / Sprint / Crouch.

	  - Clients only send the *wanted* mode (`SetMovementMode`); the server
	    sets Humanoid.WalkSpeed from config, so the movement validator
	    (AntiExploitService) always checks against the legitimate speed.
	  - Sprint needs Movement.SprintMinFocus to start and spends Focus while
	    actually moving; it falls back to Walk when Focus runs out.
	  - Publishes the character attribute "Stance" ("Sprint" / "Crouch" / nil)
	    so every client plays the right loop (AnimationController).
	  - Skill statuses scale the speed: stunned / rooted 0, slowed by its %
	    (CombatService.StatusChanged).
	  - Slowing down (sprint -> walk/crouch, a stun) grants a short speed
	    allowance so deceleration is never flagged as a speed hack.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Log = require(ReplicatedStorage.Shared.Util.Log)

local ConfigurationService = require(script.Parent.ConfigurationService)
local NetService = require(script.Parent.NetService)
local AntiExploitService = require(script.Parent.AntiExploitService)
local CombatService = require(script.Parent.CombatService)

local TICK_SECONDS = 0.25
local MOVING_SPEED = 2 -- studs/s: below this a sprinting player spends no Focus

local log = Log.new("MovementService")

local MovementService = {}

local modes: { [Player]: string } = {}

local function movementConfig(): any
	return ConfigurationService:Get("Movement")
end

local function humanoidOf(player: Player): Humanoid?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid
end

local function speedFor(mode: string): number
	local config = movementConfig()
	if mode == "Sprint" then
		return config.SprintSpeed
	elseif mode == "Crouch" then
		return config.CrouchSpeed
	end
	return config.WalkSpeed
end

-- The mode's speed after stuns, roots and slows (skills, Phase 5).
local function controlledSpeed(player: Player, mode: string): number
	local entity = CombatService:GetPlayerEntity(player)
	local scale = if entity then CombatService:ControlOf(entity).speedScale else 1
	return speedFor(mode) * scale
end

local function apply(player: Player, mode: string)
	modes[player] = mode
	local character = player.Character
	local humanoid = humanoidOf(player)
	if character == nil or humanoid == nil or CombatService:IsDefeated(player) then
		return
	end
	local oldSpeed = humanoid.WalkSpeed
	local newSpeed = controlledSpeed(player, mode)
	if newSpeed < oldSpeed then
		-- The body still carries momentum for a moment.
		AntiExploitService:GrantSpeedAllowance(player, oldSpeed - newSpeed, 1)
	end
	humanoid.WalkSpeed = newSpeed
	character:SetAttribute("Stance", if mode == "Walk" then nil else mode)
end

local function onSetMode(player: Player, mode: string)
	if modes[player] == mode then
		return
	end
	if mode == "Sprint" and CombatService:GetFocus(player) < movementConfig().SprintMinFocus then
		NetService:FireClient("Notify", player, { kind = "Warning", textKey = "movement.noFocus" })
		return
	end
	apply(player, mode)
end

local function tick(dt: number)
	local config = movementConfig()
	for player, mode in modes do
		if mode ~= "Sprint" then
			continue
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root == nil or not root:IsA("BasePart") then
			continue
		end
		local velocity = root.AssemblyLinearVelocity
		if Vector3.new(velocity.X, 0, velocity.Z).Magnitude < MOVING_SPEED then
			continue
		end
		if not CombatService:SpendFocus(player, config.SprintFocusPerSecond * dt) then
			apply(player, "Walk")
			NetService:FireClient("Notify", player, { kind = "Warning", textKey = "movement.noFocus" })
		end
	end
end

function MovementService:Init()
	NetService:Handle("SetMovementMode", onSetMode)
	-- Stun / root / slow started or ended: re-apply the speed.
	CombatService.StatusChanged:Connect(function(entity)
		local player = entity.player
		if entity.kind == "Player" and player and player.Character == entity.model then
			apply(player, modes[player] or "Walk")
		end
	end)
end

function MovementService:Start()
	local function watch(player: Player)
		player.CharacterAdded:Connect(function()
			modes[player] = "Walk"
			task.defer(apply, player, "Walk")
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		modes[player] = nil
	end)
	task.spawn(function()
		while true do
			tick(task.wait(TICK_SECONDS))
		end
	end)
	log:Info(
		"movement modes ready (walk %d / sprint %d / crouch %d)",
		speedFor("Walk"),
		speedFor("Sprint"),
		speedFor("Crouch")
	)
end

function MovementService:GetMode(player: Player): string
	return modes[player] or "Walk"
end

return MovementService
