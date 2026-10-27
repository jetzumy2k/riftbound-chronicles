--!strict
--[[
	NpcBuilder — a standing, anchored town NPC dressed in its realm's look
	(D-117; the same recipe as the quest givers, QuestService). Display
	only: anything the NPC does is checked by the service that owns it.
	Yields (builds the avatar).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local AnimeArchetypes = require(Shared.Definitions.AnimeArchetypes)
local FacePresets = require(Shared.Definitions.FacePresets)
local JobDefinitions = require(Shared.Definitions.JobDefinitions)
local GearLook = require(Shared.Logic.GearLook)

local Wardrobe = require(script.Parent.Wardrobe)
local BodyStyle = require(script.Parent.BodyStyle)
local CharacterFactory = require(script.Parent.Anime.CharacterFactory)

local NpcBuilder = {}

local SKIN = { Angel = Color3.fromRGB(241, 199, 168), Devil = Color3.fromRGB(176, 116, 86) }
local IDLE = "rbxassetid://507766666"

-- Tier-2 Rare gear of the class (display only).
local function lookFor(race: string, job: string): GearLook.Look
	local look: GearLook.Look = {}
	for _, slot in { "Shoulders", "Chest", "Hands", "Legs", "Boots" } do
		look[slot] = { tier = 2, rarity = "Rare", kind = slot, enhancement = 0 }
	end
	local definition = JobDefinitions.get(job)
	local families = definition and definition.weaponsByRace[race]
	look.Weapon = {
		tier = 2,
		rarity = "Rare",
		family = if families then families[1] else nil,
		kind = "Weapon",
		enhancement = 0,
	}
	return look
end

local function nameplate(root: BasePart, name: string, title: string)
	local board = Instance.new("BillboardGui")
	board.Size = UDim2.fromOffset(200, 44)
	board.StudsOffset = Vector3.new(0, 3.8, 0)
	board.MaxDistance = 90
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = `{name}\n{title}`
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.fromRGB(255, 236, 190)
	label.TextStrokeTransparency = 0.4
	label.Parent = board
	board.Parent = root
end

--[[
	Builds the NPC standing at `at` (the root's CFrame: about 3.2 studs
	above the floor). Returns the model and its root, or nil.
]]
function NpcBuilder.build(
	race: string,
	job: string,
	name: string,
	title: string,
	at: CFrame,
	parent: Instance
): (Model?, BasePart?)
	local anime = AnimeArchetypes.forCharacter(race, job) ~= nil
	local description = Instance.new("HumanoidDescription")
	for _, part in { "Head", "Torso", "LeftArm", "RightArm", "LeftLeg", "RightLeg" } do
		(description :: any)[`{part}Color`] = SKIN[race] or SKIN.Angel
	end
	if anime then
		CharacterFactory.dress(description)
	end
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescriptionAsync(description, Enum.HumanoidRigType.R15)
	end)
	if not ok or model == nil then
		return nil, nil
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		if not anime then
			BodyStyle.athlete(humanoid)
		end
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		pcall(function()
			humanoid:BuildRigFromAttachments()
		end)
	end
	model.Name = name
	model:PivotTo(at)
	model.Parent = parent
	task.wait(0.2)
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root == nil then
		model:Destroy()
		return nil, nil
	end
	root.Anchored = true
	Wardrobe.dress(
		model,
		race,
		FacePresets.defaultFor(race),
		job,
		lookFor(race, job),
		if anime then {} else nil
	)
	nameplate(root, name, title)
	if humanoid then
		local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
		animator.Parent = humanoid
		local animation = Instance.new("Animation")
		animation.AnimationId = IDLE
		pcall(function()
			local track = animator:LoadAnimation(animation)
			track.Looped = true
			track:Play()
		end)
	end
	return model, root
end

return NpcBuilder
