--!strict
--[[
	AnimationController — plays the authored character animation
	(AnimationClips) on every nearby character through its Animator
	(CLAUDE.md §19, PLAN.md D-36).

	Loops, chosen every frame from what the character is doing:
	  base     job idle (standing, full body) or weapon hold (moving or in
	           the air, upper body only, so the walk/jump legs keep playing)
	  overlay  Sprint, or CrouchIdle / CrouchWalk (server "Stance" attribute)
	Actions (one at a time): attacks, hit reactions, defeat (held).
	  - An attack that moves the legs switches to its upper-body variant at
	    the same moment if the character starts moving, so attacking never
	    roots you in place.
	  - hitStop() freezes the current action for a few frames on impact.

	Clip ids: AnimationAssets (published) or, until published, the clip is
	built from data and registered with KeyframeSequenceProvider for
	play-testing. Every client plays everything locally (attacks are driven
	by server CombatEvents), so animation Roblox replicates from another
	player's own client is stopped here to avoid playing it twice.

	Display only; never changes game state.
]]

local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AnimationAssets = require(Shared.Definitions.AnimationAssets)
local AnimationClips = require(Shared.Definitions.AnimationClips)
local ClipBuilder = require(Shared.Animation.ClipBuilder)
local Log = require(Shared.Util.Log)

local log = Log.new("Animation")

local UPDATE_DISTANCE = 160
local MOVING_SPEED = 1.5
local LOOP_FADE = 0.25
local ACTION_FADE = 0.08
local SPRINT_REFERENCE_SPEED = 25
local CROUCH_REFERENCE_SPEED = 8

type Variant = ClipBuilder.Variant

type Action = {
	name: string,
	variant: Variant,
	track: AnimationTrack,
	startedAt: number,
	speed: number,
	hold: boolean,
	frozen: boolean,
}

type State = {
	character: Model,
	humanoid: Humanoid,
	animator: Animator,
	tracks: { [string]: AnimationTrack },
	own: { [AnimationTrack]: boolean },
	loops: { base: string?, overlay: string? },
	action: Action?,
}

local AnimationController = {}

local states: { [Model]: State } = {}
local pending: { [Model]: boolean } = {}
local animationIds: { [string]: string | false } = {}
local ourIds: { [string]: boolean } = {}
-- Registered sequences are kept alive for the session.
local sequences: { KeyframeSequence } = {}
local warnedUnpublished = false

--------------------------------------------------------------------------------
-- Clip ids and tracks
--------------------------------------------------------------------------------

local function animationId(name: string, variant: Variant): string?
	local asset = ClipBuilder.assetName(name, variant)
	local cached = animationIds[asset]
	if cached ~= nil then
		return if cached == false then nil else cached :: string
	end
	local published = AnimationAssets[asset]
	if published then
		animationIds[asset] = published
		ourIds[published] = true
		return published
	end
	local clip = AnimationClips.get(name)
	if clip == nil then
		animationIds[asset] = false
		return nil
	end
	local sequence = ClipBuilder.build(name, clip, variant)
	local ok, result = pcall(function()
		return KeyframeSequenceProvider:RegisterKeyframeSequence(sequence)
	end)
	if not ok or result == nil then
		animationIds[asset] = false
		if not warnedUnpublished then
			warnedUnpublished = true
			log:Warn(
				"animation %s is not published and could not be registered (%s); see docs/ASSET_GUIDE.md",
				asset,
				tostring(result)
			)
		end
		return nil
	end
	local id = tostring(result)
	table.insert(sequences, sequence)
	log:Debug("registered %s for play-testing (%d clips)", asset, #sequences)
	animationIds[asset] = id
	ourIds[id] = true
	return id
end

local function trackFor(state: State, name: string, variant: Variant): AnimationTrack?
	local asset = ClipBuilder.assetName(name, variant)
	local existing = state.tracks[asset]
	if existing then
		return existing
	end
	local clip = AnimationClips.get(name)
	local id = animationId(name, variant)
	if clip == nil or id == nil then
		return nil
	end
	local animation = Instance.new("Animation")
	animation.Name = asset
	animation.AnimationId = id
	local ok, result = pcall(function()
		return state.animator:LoadAnimation(animation)
	end)
	if not ok then
		log:Debug("could not load %s on %s: %s", asset, state.character.Name, tostring(result))
		return nil
	end
	local track = result :: AnimationTrack
	track.Priority = (Enum.AnimationPriority :: any)[clip.priority]
	track.Looped = clip.looped
	state.tracks[asset] = track
	state.own[track] = true
	return track
end

--------------------------------------------------------------------------------
-- Character state
--------------------------------------------------------------------------------

local function rootOf(character: Model): BasePart?
	local root = character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function horizontalSpeed(character: Model): number
	local root = rootOf(character)
	if root == nil then
		return 0
	end
	local velocity = root.AssemblyLinearVelocity
	return Vector3.new(velocity.X, 0, velocity.Z).Magnitude
end

local function jobOf(character: Model): string?
	local player = Players:GetPlayerFromCharacter(character)
	local job = if player then player:GetAttribute("Job") else character:GetAttribute("Job")
	return if type(job) == "string" then job else nil
end

local function isAirborne(humanoid: Humanoid): boolean
	local state = humanoid:GetState()
	return state == Enum.HumanoidStateType.Jumping or state == Enum.HumanoidStateType.Freefall
end

local function blocksLoops(humanoid: Humanoid): boolean
	local state = humanoid:GetState()
	return state == Enum.HumanoidStateType.Climbing
		or state == Enum.HumanoidStateType.Swimming
		or state == Enum.HumanoidStateType.Seated
		or humanoid.Sit
end

local function stopLoop(state: State, slot: "base" | "overlay")
	local current = state.loops[slot]
	if current then
		local track = state.tracks[current]
		if track then
			track:Stop(LOOP_FADE)
		end
		state.loops[slot] = nil
	end
end

local function setLoop(state: State, slot: "base" | "overlay", name: string?, speed: number)
	if name == nil then
		stopLoop(state, slot)
		return
	end
	local track = trackFor(state, name, "Full")
	if track == nil then
		stopLoop(state, slot)
		return
	end
	if state.loops[slot] ~= name then
		stopLoop(state, slot)
		track:Play(LOOP_FADE, 1, speed)
		state.loops[slot] = name
	else
		track:AdjustSpeed(speed)
	end
end

local function updateState(state: State)
	local character = state.character
	local humanoid = state.humanoid
	local defeated = character:GetAttribute("Defeated") == true
	local speed = horizontalSpeed(character)
	local moving = speed > MOVING_SPEED

	-- Loops.
	if defeated or blocksLoops(humanoid) then
		setLoop(state, "base", nil, 1)
		setLoop(state, "overlay", nil, 1)
	else
		local job = jobOf(character)
		local airborne = isAirborne(humanoid)
		local base = if job == nil then nil elseif moving or airborne then job .. "_Hold" else job .. "_Idle"
		setLoop(state, "base", base, 1)

		local stance = character:GetAttribute("Stance")
		local overlay: string? = nil
		local overlaySpeed = 1
		if not airborne and stance == "Crouch" then
			overlay = if moving then "CrouchWalk" else "CrouchIdle"
			overlaySpeed = if moving then math.clamp(speed / CROUCH_REFERENCE_SPEED, 0.6, 1.4) else 1
		elseif not airborne and stance == "Sprint" and moving then
			overlay = "Sprint"
			overlaySpeed = math.clamp(speed / SPRINT_REFERENCE_SPEED, 0.75, 1.3)
		end
		setLoop(state, "overlay", overlay, overlaySpeed)
	end

	-- Action housekeeping.
	local action = state.action
	if action == nil then
		return
	end
	local track = action.track
	if action.hold then
		if not action.frozen and track.TimePosition >= track.Length - 0.06 then
			track:AdjustSpeed(0)
			action.frozen = true
		end
		return
	end
	if not track.IsPlaying then
		state.action = nil
		return
	end
	-- Started moving mid-attack: hand the legs back to locomotion.
	if action.variant == "Full" and moving then
		local clip = AnimationClips.get(action.name)
		if clip and ClipBuilder.hasLowerBody(clip) and track.TimePosition < track.Length - 0.12 then
			local upper = trackFor(state, action.name, "Upper")
			if upper then
				local position = track.TimePosition
				upper:Play(0.1, 1, action.speed)
				upper.TimePosition = position
				track:Stop(0.1)
				action.track = upper
				action.variant = "Upper"
			end
		end
	end
end

local function setup(character: Model)
	if states[character] or pending[character] then
		return
	end
	pending[character] = true
	task.spawn(function()
		local humanoid = character:WaitForChild("Humanoid", 10)
		pending[character] = nil
		if humanoid == nil or not humanoid:IsA("Humanoid") or character.Parent == nil then
			return
		end
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator == nil then
			animator = humanoid:WaitForChild("Animator", 3) :: Animator?
		end
		if animator == nil then
			-- Client-side Animator: plays locally only (NPCs).
			local created = Instance.new("Animator")
			created.Parent = humanoid
			animator = created
		end
		local state: State = {
			character = character,
			humanoid = humanoid,
			animator = animator :: Animator,
			tracks = {},
			own = {},
			loops = {},
			action = nil,
		}
		states[character] = state

		local localCharacter = (Players.LocalPlayer :: Player).Character
		if character ~= localCharacter then
			-- Our clips replicated from that player's client: we already play
			-- them locally from server events, so stop the copy.
			state.animator.AnimationPlayed:Connect(function(track: AnimationTrack)
				local animation = track.Animation
				if not state.own[track] and animation and ourIds[animation.AnimationId] then
					track:Stop(0)
				end
			end)
		end
		character.AncestryChanged:Connect(function(_, parent)
			if parent == nil then
				states[character] = nil
			end
		end)
	end)
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

export type PlayOptions = { speed: number? }

--[[
	Plays an AnimationClips action on `character` from the start, replacing
	the current action. Returns false if it cannot play (not tracked, unknown
	clip, or the character is held in its defeat pose).
]]
function AnimationController.play(character: Model, name: string, options: PlayOptions?): boolean
	local state = states[character]
	local clip = AnimationClips.get(name)
	if state == nil or clip == nil then
		return false
	end
	local current = state.action
	if current and current.name == "Defeat" and name ~= "Defeat" then
		return false
	end
	local moving = horizontalSpeed(character) > MOVING_SPEED
	local variant: Variant = if moving
			and name ~= "Defeat"
			and ClipBuilder.hasLowerBody(clip)
		then "Upper"
		else "Full"
	local track = trackFor(state, name, variant)
	if track == nil then
		return false
	end
	if current and current.track ~= track then
		current.track:Stop(ACTION_FADE)
	end
	local speed = (options and options.speed) or 1
	track:Play(ACTION_FADE, 1, speed)
	local action: Action = {
		name = name :: string,
		variant = variant,
		track = track,
		startedAt = os.clock(),
		speed = speed,
		hold = clip.hold == true,
		frozen = false,
	}
	state.action = action
	return true
end

-- Name of the action playing on `character`, if any.
function AnimationController.currentAction(character: Model): string?
	local state = states[character]
	local action = state and state.action
	return if action then action.name else nil
end

-- Seconds since `name` started on `character` (nil if it is not playing).
function AnimationController.actionElapsed(character: Model, name: string): number?
	local state = states[character]
	local action = state and state.action
	if action == nil or action.name ~= name then
		return nil
	end
	return os.clock() - action.startedAt
end

-- True while an attack (not a reaction) is playing.
function AnimationController.isAttacking(character: Model): boolean
	local name = AnimationController.currentAction(character)
	return name ~= nil and string.find(name, "_Attack", 1, true) ~= nil
end

-- Freezes the current action for `seconds` (impact hit-stop).
function AnimationController.hitStop(character: Model, seconds: number)
	local state = states[character]
	local action = state and state.action
	if action == nil or action.hold then
		return
	end
	action.track:AdjustSpeed(0)
	task.delay(seconds, function()
		if state and state.action == action then
			action.track:AdjustSpeed(action.speed)
		end
	end)
end

-- Ends any action (e.g. releases the defeat pose when a dummy revives).
function AnimationController.reset(character: Model)
	local state = states[character]
	local action = state and state.action
	if state and action then
		action.track:Stop(0.3)
		state.action = nil
	end
end

local function step()
	local camera = Workspace.CurrentCamera
	local origin = if camera then camera.CFrame.Position else Vector3.zero
	for character, state in states do
		local root = rootOf(character)
		if root == nil or (root.Position - origin).Magnitude > UPDATE_DISTANCE then
			continue
		end
		updateState(state)
	end
end

local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(setup)
	if player.Character then
		setup(player.Character)
	end
end

function AnimationController:Init()
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	-- Server NPCs (training dummies, later mobs).
	task.spawn(function()
		local npcs = Workspace:WaitForChild("RC_Npcs", 30)
		if npcs == nil then
			return
		end
		npcs.ChildAdded:Connect(function(child)
			if child:IsA("Model") then
				setup(child)
			end
		end)
		for _, child in npcs:GetChildren() do
			if child:IsA("Model") then
				setup(child)
			end
		end
	end)
	RunService:BindToRenderStep("RC_Animation", Enum.RenderPriority.Character.Value, step)
end

return AnimationController
