--!strict
--[[
	MobLevelController — a name and level plate over every creature, the
	level coloured by how it compares to this player (PLAN.md D-63, the
	tiers in UI/LevelTier and Logic/LevelGap). Display only; the server
	applies the same rule to EXP.

	Replaces the Humanoid's own name label (hidden locally) on models tagged
	"RC_Combatant" that aren't players. Plates show within PLATE_DISTANCE,
	hide once the creature is defeated, and recolour when either level
	changes.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local UI = script.Parent.Parent.UI
local Theme = require(UI.Theme)
local LevelTier = require(UI.LevelTier)

local TAG = "RC_Combatant"
local PLATE_DISTANCE = 60

type Plate = {
	model: Model,
	gui: BillboardGui,
	level: TextLabel,
	connections: { RBXScriptConnection },
}

local MobLevelController = {}

local plates: { [Model]: Plate } = {}

local function label(parent: Instance, y: number, height: number, size: number, font: Font): TextLabel
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Position = UDim2.fromOffset(0, y)
	text.Size = UDim2.new(1, 0, 0, height)
	text.TextSize = size
	text.FontFace = font
	text.TextStrokeTransparency = 0.3
	text.TextStrokeColor3 = Theme.Colors.Ink
	text.Parent = parent
	return text
end

local function refresh(plate: Plate)
	local model = plate.model
	local level = model:GetAttribute("Level")
	local hp = model:GetAttribute("HP")
	plate.gui.Enabled = type(level) == "number" and not (type(hp) == "number" and hp <= 0)
	if type(level) ~= "number" then
		return
	end
	local style = LevelTier.styleFor(level)
	local mark = if style.mark ~= "" then ` {style.mark}` else ""
	local word = if style.word ~= "" then `  ·  {style.word}` else ""
	plate.level.Text = `Lv {level}{mark}{word}`
	plate.level.TextColor3 = style.color
end

local function attach(model: Instance)
	if not model:IsA("Model") or plates[model] or Players:GetPlayerFromCharacter(model) then
		return
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if root == nil or not root:IsA("BasePart") or humanoid == nil then
		return
	end
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	local cf, size = model:GetBoundingBox()
	local top = cf.Position.Y + size.Y / 2 - root.Position.Y

	local gui = Instance.new("BillboardGui")
	gui.Name = "RC_LevelPlate"
	gui.Adornee = root
	gui.Size = UDim2.fromOffset(220, 38)
	gui.StudsOffsetWorldSpace = Vector3.new(0, top + 1.2, 0)
	gui.MaxDistance = PLATE_DISTANCE
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	local name = label(gui, 0, 20, 15, Theme.Fonts.Display)
	name.Text = humanoid.DisplayName
	name.TextColor3 = Theme.Colors.Text
	local level = label(gui, 20, 16, 12, Theme.Fonts.BodyBold)

	local plate: Plate = { model = model, gui = gui, level = level, connections = {} }
	plates[model] = plate
	for _, attribute in { "Level", "HP" } do
		table.insert(
			plate.connections,
			model:GetAttributeChangedSignal(attribute):Connect(function()
				refresh(plate)
			end)
		)
	end
	table.insert(
		plate.connections,
		humanoid:GetPropertyChangedSignal("DisplayName"):Connect(function()
			name.Text = humanoid.DisplayName
		end)
	)
	refresh(plate)
	gui.Parent = root
end

local function detach(model: Instance)
	local plate = plates[model :: Model]
	if plate == nil then
		return
	end
	plates[model :: Model] = nil
	for _, connection in plate.connections do
		connection:Disconnect()
	end
	plate.gui:Destroy()
end

function MobLevelController:Start()
	CollectionService:GetInstanceAddedSignal(TAG):Connect(attach)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(detach)
	for _, model in CollectionService:GetTagged(TAG) do
		attach(model)
	end
	-- This player levelled: every plate's colour may change.
	local player = Players.LocalPlayer
	if player then
		player:GetAttributeChangedSignal("Level"):Connect(function()
			for _, plate in plates do
				refresh(plate)
			end
		end)
	end
end

return MobLevelController
