--!strict
--[[
	ExpressionController — facial expressions on nearby characters (Phase 15,
	PLAN.md D-79; rules in Logic/FaceExpressions).

	Reads only what every client already sees, so it adds no network
	traffic:
	  Defeated attribute        -> Defeated (eyes closed, no blinking)
	  HP attribute going down   -> Pain for a moment
	  attack / skill animation  -> Effort (AnimationController)
	  Level attribute going up  -> Happy
	  a recent hit or action    -> Focused
	Characters also blink every few seconds.

	The animated head's FaceControls are eased toward the expression, and
	its looping mood animation is stopped on the characters we drive (it
	would overwrite the expression). Heads without FaceControls keep their
	face unchanged.

	Display only; local to this client.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FaceExpressions = require(Shared.Logic.FaceExpressions)

local AnimationController = require(script.Parent.AnimationController)

local ExpressionController = {}

local RANGE = 70
local FRAME_HZ = 30
local MOOD_CHECK_SECONDS = 0.5

type Face = {
	character: Model,
	controls: FaceControls,
	weights: FaceExpressions.Weights,
	hp: number,
	level: number,
	hurtAt: number,
	happyAt: number,
	fightAt: number,
	nextBlink: number,
	blinkStart: number,
	nextMoodCheck: number,
	connections: { RBXScriptConnection },
}

local faces: { [Model]: Face } = {}
local random = Random.new()

local function forget(character: Model)
	local face = faces[character]
	if face == nil then
		return
	end
	faces[character] = nil
	for _, connection in face.connections do
		connection:Disconnect()
	end
end

local function numberAttribute(character: Model, name: string): number
	local value = character:GetAttribute(name)
	return if type(value) == "number" then value else 0
end

local function track(character: Model): Face?
	local head = character:FindFirstChild("Head")
	if head == nil or not head:IsA("BasePart") then
		return nil
	end
	local controls = head:FindFirstChildOfClass("FaceControls")
	if controls == nil then
		return nil
	end
	local now = os.clock()
	local face: Face = {
		character = character,
		controls = controls,
		weights = {},
		hp = numberAttribute(character, "HP"),
		level = numberAttribute(character, "Level"),
		hurtAt = -math.huge,
		happyAt = -math.huge,
		fightAt = -math.huge,
		nextBlink = now + random:NextNumber(FaceExpressions.BLINK_MIN, FaceExpressions.BLINK_MAX),
		blinkStart = -math.huge,
		nextMoodCheck = 0,
		connections = {},
	}
	table.insert(
		face.connections,
		character:GetAttributeChangedSignal("HP"):Connect(function()
			local hp = numberAttribute(character, "HP")
			if hp < face.hp then
				face.hurtAt = os.clock()
				face.fightAt = face.hurtAt
			end
			face.hp = hp
		end)
	)
	table.insert(
		face.connections,
		character:GetAttributeChangedSignal("Level"):Connect(function()
			local level = numberAttribute(character, "Level")
			if level > face.level then
				face.happyAt = os.clock()
			end
			face.level = level
		end)
	)
	table.insert(
		face.connections,
		character.AncestryChanged:Connect(function(_, parent)
			if parent == nil then
				forget(character)
			end
		end)
	)
	faces[character] = face
	return face
end

-- Stops the Roblox head's looping mood animation (it would overwrite the face).
local function stopMood(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if animator == nil then
		return
	end
	for _, playing in animator:GetPlayingAnimationTracks() do
		local animation = playing.Animation
		local parent = animation and animation.Parent
		if parent and string.lower(parent.Name) == "mood" then
			playing:Stop(0.2)
		end
	end
end

local function applyControls(face: Face, name: string, dt: number, blink: number)
	FaceExpressions.step(face.weights, name, dt, blink)
	local controls = face.controls :: any
	for control, value in face.weights do
		pcall(function()
			controls[control] = value
		end)
	end
end

local function update(face: Face, now: number, dt: number)
	local character = face.character
	if now >= face.nextMoodCheck then
		face.nextMoodCheck = now + MOOD_CHECK_SECONDS
		stopMood(character)
	end
	local acting = AnimationController.isAttacking(character)
	if acting then
		face.fightAt = now
	end
	local defeated = character:GetAttribute("Defeated") == true
	local name = FaceExpressions.pick({
		defeated = defeated,
		hurtFor = now - face.hurtAt,
		acting = acting,
		happyFor = now - face.happyAt,
		fightingFor = now - face.fightAt,
	})
	-- Blinking (never while fainted).
	local blink = 0
	if not defeated then
		if now >= face.nextBlink then
			face.blinkStart = now
			face.nextBlink = now + random:NextNumber(FaceExpressions.BLINK_MIN, FaceExpressions.BLINK_MAX)
		end
		blink = FaceExpressions.blinkAt(now - face.blinkStart)
	end
	applyControls(face, name, dt, blink)
end

local function characters(): { Model }
	local out = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character then
			table.insert(out, character)
		end
	end
	-- Humanoid NPCs (quest givers, combatants) as well.
	for _, instance in CollectionService:GetTagged("RC_Combatant") do
		if instance:IsA("Model") and Players:GetPlayerFromCharacter(instance) == nil then
			table.insert(out, instance)
		end
	end
	return out
end

function ExpressionController:Start()
	local acc = 0
	local last = os.clock()
	RunService.RenderStepped:Connect(function(dt)
		acc += dt
		if acc < 1 / FRAME_HZ then
			return
		end
		acc = 0
		local now = os.clock()
		local step = math.min(now - last, 0.25)
		last = now
		local camera = Workspace.CurrentCamera
		local eye = if camera then camera.CFrame.Position else Vector3.zero
		local seen: { [Model]: boolean } = {}
		for _, character in characters() do
			local head = character:FindFirstChild("Head")
			if head and head:IsA("BasePart") and (head.Position - eye).Magnitude <= RANGE then
				local face = faces[character] or track(character)
				if face then
					seen[character] = true
					update(face, now, step)
				end
			end
		end
		-- Out of range: stop driving.
		for character in faces do
			if not seen[character] then
				forget(character)
			end
		end
	end)
end

return ExpressionController
