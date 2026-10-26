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
	would overwrite the expression).

	D-103: the Part-built anime faces (RC_Outfit parts named
	Eye_<side>_<layer>, Mouth; Appearance/Anime/HeadBuilder) follow the same
	expressions through FaceExpressions.animePose: the eyes squash shut
	(their sphere meshes scale), the lash lines drop with the lid, the brows
	lift / tilt and the mouth opens, widens and smiles, by changing the
	parts' weld offsets and sizes on this client only. Far away (or when the
	outfit is rebuilt) the face goes back to how it was built.

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

-- One moving piece of an anime face and how it was built.
type Piece = {
	part: BasePart,
	weld: Weld,
	baseC0: CFrame,
	baseSize: Vector3,
	mesh: SpecialMesh?,
	layer: string,
	sign: number,
}
type AnimeRig = {
	eyes: { Piece }, -- White, Iris, IrisLight, Pupil (squash)
	shines: { Piece }, -- Shine, Shine2 (vanish when the eye narrows)
	lashes: { Piece }, -- Lash, Flick, Flick2 (drop with the lid)
	brows: { Piece },
	mouth: Piece?,
	probe: BasePart, -- a white of the eye: gone = the outfit was rebuilt
	up: Vector3, -- the face's "up" in the rig head's space
	eyeHeight: number,
}

local EYE_LAYERS = { White = true, Iris = true, IrisLight = true, Pupil = true }
local SHINE_LAYERS = { Shine = true, Shine2 = true }
local LASH_LAYERS = { Lash = true, Flick = true, Flick2 = true }
local SIDE_SIGN = { Right = 1, Left = -1 }

type Face = {
	character: Model,
	controls: FaceControls?,
	anime: AnimeRig?,
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
	-- Anime faces go back to how they were built.
	local rig = face.anime
	if rig then
		for _, group in { rig.eyes, rig.shines, rig.lashes, rig.brows } do
			for _, piece in group do
				if piece.part.Parent then
					piece.weld.C0 = piece.baseC0
					if piece.mesh then
						piece.mesh.Scale = Vector3.one
					end
				end
			end
		end
		local mouth = rig.mouth
		if mouth and mouth.part.Parent then
			mouth.weld.C0 = mouth.baseC0
			mouth.part.Size = mouth.baseSize
		end
	end
end

-- The anime face pieces in the character's outfit (nil = not an anime face).
local function scanAnime(character: Model): AnimeRig?
	local folder = character:FindFirstChild("RC_Outfit")
	if folder == nil then
		return nil
	end
	local rig: AnimeRig = {
		eyes = {},
		shines = {},
		lashes = {},
		brows = {},
		mouth = nil,
		probe = nil :: any,
		up = Vector3.yAxis,
		eyeHeight = 0.4,
	}
	for _, child in folder:GetChildren() do
		if not child:IsA("BasePart") then
			continue
		end
		local weld = child:FindFirstChildOfClass("Weld")
		if weld == nil then
			continue
		end
		local side, layer = string.match(child.Name, "^Eye_(%a+)_(%a+)$")
		if child.Name == "Mouth" then
			side, layer = "Right", "Mouth"
		end
		if side == nil or layer == nil then
			continue
		end
		local piece: Piece = {
			part = child,
			weld = weld,
			baseC0 = weld.C0,
			baseSize = child.Size,
			mesh = child:FindFirstChildOfClass("SpecialMesh"),
			layer = layer,
			sign = (SIDE_SIGN :: any)[side] or 1,
		}
		if layer == "Mouth" then
			rig.mouth = piece
		elseif EYE_LAYERS[layer] then
			table.insert(rig.eyes, piece)
			if layer == "White" then
				rig.probe = child
				rig.up = weld.C0.UpVector
				rig.eyeHeight = child.Size.Y
			end
		elseif SHINE_LAYERS[layer] then
			table.insert(rig.shines, piece)
		elseif LASH_LAYERS[layer] then
			table.insert(rig.lashes, piece)
		elseif layer == "Brow" then
			table.insert(rig.brows, piece)
		end
	end
	if (rig.probe :: BasePart?) == nil then
		return nil
	end
	return rig
end

-- Poses the anime face pieces for the current weights.
local function applyAnime(rig: AnimeRig, weights: FaceExpressions.Weights)
	local pose = FaceExpressions.animePose(weights)
	local up, h = rig.up, rig.eyeHeight
	for _, piece in rig.eyes do
		if piece.mesh then
			piece.mesh.Scale = Vector3.new(1, pose.eye, 1)
		end
	end
	local shine = if pose.eye > 0.45 then 1 else 0
	for _, piece in rig.shines do
		if piece.mesh then
			piece.mesh.Scale = Vector3.new(shine, shine, 1)
		end
	end
	-- The lash line follows the lid down; shut, it is the closed eye.
	local drop = CFrame.new(up * -(1 - pose.eye) * h * 0.45)
	for _, piece in rig.lashes do
		piece.weld.C0 = drop * piece.baseC0
	end
	local lift = CFrame.new(up * pose.browLift * h)
	for _, piece in rig.brows do
		piece.weld.C0 = lift * piece.baseC0 * CFrame.Angles(0, 0, math.rad(piece.sign * pose.browTilt))
	end
	local mouth = rig.mouth
	if mouth then
		local base = mouth.baseSize
		local height = base.Y * pose.mouthOpen
		mouth.part.Size = Vector3.new(base.X * pose.mouthWide, height, base.Z)
		-- Opens downward from the lip line; a smile lifts it.
		local mouthUp = mouth.baseC0.UpVector
		mouth.weld.C0 = CFrame.new(mouthUp * (pose.mouthLift * h - (height - base.Y) / 2)) * mouth.baseC0
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
	-- An anime face wins over the hidden rig head's FaceControls.
	local anime = scanAnime(character)
	local controls = if anime then nil else head:FindFirstChildOfClass("FaceControls")
	if controls == nil and anime == nil then
		return nil
	end
	local now = os.clock()
	local face: Face = {
		character = character,
		controls = controls,
		anime = anime,
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
	if face.anime then
		applyAnime(face.anime, face.weights)
		return
	end
	local controls = face.controls :: any
	for control, value in face.weights do
		pcall(function()
			controls[control] = value
		end)
	end
end

local function update(face: Face, now: number, dt: number)
	local character = face.character
	local rig = face.anime
	if rig and rig.probe.Parent == nil then
		-- The outfit was rebuilt (new gear, colours): find the new face.
		forget(character)
		return
	end
	if now >= face.nextMoodCheck then
		face.nextMoodCheck = now + MOOD_CHECK_SECONDS
		if rig == nil and scanAnime(character) ~= nil then
			-- The anime face arrived after the character spawned (the outfit
			-- is drawn a moment later): drive it instead of the hidden head.
			forget(character)
			return
		end
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
