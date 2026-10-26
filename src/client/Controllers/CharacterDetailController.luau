--!strict
--[[
	CharacterDetailController — distance detail for the Part-built
	characters (Phase 23, PLAN.md D-102; rules in Logic/DetailRules).

	Twice a second it measures the camera's distance to every other
	player's character and to the quest-giver commanders. Past
	DetailRules.NEAR the small outfit parts (attribute RC_Lod 1) are hidden
	and the outfit's particles and lights switch off; past DetailRules.FAR
	the medium parts (RC_Lod 2) are hidden too. The player's own character
	always keeps full detail. A rebuilt outfit (new gear, new colours) is
	picked up on the next check.

	Local only: transparency set here never replicates, and the server
	never sets it on outfit parts after building them. Display only.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DetailRules = require(Shared.Logic.DetailRules)

local CharacterDetailController = {}

local CHECK_SECONDS = 0.5
local OUTFIT = "RC_Outfit"

type Tracked = {
	folder: Instance,
	count: number,
	level: number,
	parts: { { part: BasePart, class: number, alpha: number } },
	effects: { Instance }, -- ParticleEmitters and PointLights
}

local tracked: { [Model]: Tracked } = setmetatable({}, { __mode = "k" }) :: any

local function scan(folder: Instance): Tracked
	local entry: Tracked = { folder = folder, count = 0, level = 0, parts = {}, effects = {} }
	entry.count = #folder:GetChildren()
	for _, item in folder:GetDescendants() do
		if item:IsA("BasePart") then
			local class = item:GetAttribute("RC_Lod")
			if type(class) == "number" and class > 0 then
				table.insert(entry.parts, { part = item, class = class, alpha = item.Transparency })
			end
		elseif item:IsA("ParticleEmitter") or item:IsA("PointLight") then
			table.insert(entry.effects, item)
		end
	end
	return entry
end

local function apply(entry: Tracked, level: number)
	entry.level = level
	for _, info in entry.parts do
		info.part.Transparency = if DetailRules.hidden(info.class, level) then 1 else info.alpha
	end
	local on = DetailRules.effectsOn(level)
	for _, effect in entry.effects do
		(effect :: any).Enabled = on
	end
end

local function update(model: Model, cameraAt: Vector3)
	local folder = model:FindFirstChild(OUTFIT)
	if folder == nil then
		tracked[model] = nil
		return
	end
	local entry = tracked[model]
	local count = #folder:GetChildren()
	if entry == nil or entry.folder ~= folder or entry.count ~= count then
		-- A new or still-arriving outfit: put back what was hidden, then
		-- start again from full detail.
		if entry and entry.folder == folder then
			apply(entry, 0)
		end
		entry = scan(folder)
		tracked[model] = entry
	end
	local distance = (model:GetPivot().Position - cameraAt).Magnitude
	local level = DetailRules.level(distance, entry.level)
	if level ~= entry.level then
		apply(entry, level)
	end
end

local function check()
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end
	local cameraAt = camera.CFrame.Position
	local me = Players.LocalPlayer
	local seen: { [Model]: boolean } = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if player ~= me and character then
			seen[character] = true
			update(character, cameraAt)
		end
	end
	for _, child in Workspace:GetChildren() do
		if child:IsA("Model") and child:GetAttribute("RC_QuestGiver") ~= nil then
			seen[child] = true
			update(child, cameraAt)
		end
	end
	for model in tracked do
		if not seen[model] then
			tracked[model] = nil
		end
	end
end

function CharacterDetailController:Start()
	task.spawn(function()
		while true do
			task.wait(CHECK_SECONDS)
			check()
		end
	end)
end

return CharacterDetailController
