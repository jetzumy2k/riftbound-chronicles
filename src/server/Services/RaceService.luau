--!strict
--[[
	RaceService (Layer 2)
	Server-authoritative race and face preset (CLAUDE.md §3.1, Phase 3).

	  - A race is chosen once, through `SelectRace(race, presetId)`. Any later
	    attempt is rejected and logged; changing race is an admin action
	    (Phase 17).
	  - The preset must belong to the chosen race (FacePresets allowlist).
	  - Publishes the public "Race" player attribute and dresses every
	    character the player spawns in its race look (Appearance/Wardrobe).
	  - While a player is choosing, builds one preview model per race from
	    their own avatar and places it in their PlayerGui (replicates to that
	    player only) for the 3D preview on the selection screen.
	  - Fires `RaceChosen(player, race)`; TravelService (Layer 5) listens to
	    spawn the player at home.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Enums = require(Shared.Enums)
local FacePresets = require(Shared.Definitions.FacePresets)
local Log = require(Shared.Util.Log)
local Signal = require(Shared.Util.Signal)

local Wardrobe = require(script.Parent.Parent.Appearance.Wardrobe)

local AuditLogService = require(script.Parent.AuditLogService)
local NetService = require(script.Parent.NetService)
local PlayerDataService = require(script.Parent.PlayerDataService)

local log = Log.new("RaceService")

local RaceService = {
	-- (player, race). Fired once per player, when the race is first chosen.
	RaceChosen = Signal.new(),
}

local function publish(player: Player, race: string?)
	player:SetAttribute("Race", race)
end

local APPEARANCE_WAIT = 10
local PREVIEW_FOLDER = "RC_Previews"

local function applyToCharacter(player: Player, character: Model)
	-- The avatar (including dynamic heads) can be rebuilt after CharacterAdded;
	-- attach cosmetics only once the appearance has loaded so they weld to the
	-- final head.
	local deadline = os.clock() + APPEARANCE_WAIT
	while not player:HasAppearanceLoaded() and os.clock() < deadline and player.Character == character do
		task.wait(0.1)
	end
	if player.Character ~= character then
		return
	end
	local data = PlayerDataService:GetData(player)
	if data and data.Race then
		Wardrobe.dress(character, data.Race, data.FacePreset)
	end
end

local function removePreviews(player: Player)
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local folder = playerGui and playerGui:FindFirstChild(PREVIEW_FOLDER)
	if folder then
		folder:Destroy()
	end
end

--[[
	Builds the selection-screen preview models: the player's own avatar dressed
	in each race's default look. Studio test players (UserId <= 0) and avatar
	lookup failures fall back to a default body.
]]
local function buildPreviews(player: Player)
	local description: HumanoidDescription
	local fetched, result = false, nil
	if player.UserId > 0 then
		fetched, result = pcall(function()
			return Players:GetHumanoidDescriptionFromUserIdAsync(player.UserId)
		end)
	end
	description = if fetched and result then result else Instance.new("HumanoidDescription")

	local built, rig = pcall(function()
		return Players:CreateHumanoidModelFromDescriptionAsync(description, Enum.HumanoidRigType.R15)
	end)
	if not built or rig == nil then
		log:Warn("preview rig failed for %d: %s", player.UserId, tostring(rig))
		return
	end

	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local data = PlayerDataService:GetData(player)
	if playerGui == nil or data == nil or data.Race ~= nil or player.Parent ~= Players then
		rig:Destroy()
		return
	end

	removePreviews(player)
	local folder = Instance.new("Folder")
	folder.Name = PREVIEW_FOLDER
	for _, race in Enums.Race do
		local model = rig:Clone()
		model.Name = race
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
			end
		end
		Wardrobe.dress(model, race, FacePresets.defaultFor(race))
		model:PivotTo(CFrame.new())
		model.Parent = folder
	end
	rig:Destroy()
	folder.Parent = playerGui
end

local function onSelectRace(player: Player, race: string, presetId: number)
	local data = PlayerDataService:GetData(player)
	if data == nil then
		return
	end
	if data.Race ~= nil then
		-- The UI never offers this; a repeat call is a stale client or tampering.
		AuditLogService:Security(player, "RaceAlreadyChosen", `has {data.Race}, asked {race}`)
		return
	end
	if not Enums.has(Enums.Race, race) or not FacePresets.isValidFor(presetId, race) then
		AuditLogService:Security(player, "InvalidFacePreset", `race={race} preset={presetId}`)
		NetService:FireClient("Notify", player, { kind = "Warning", textKey = "race.invalidPreset" })
		return
	end

	-- Synchronous commit.
	data.Race = race
	data.FacePreset = presetId

	publish(player, race)
	removePreviews(player)
	log:Info("user=%d chose %s (preset %d)", player.UserId, race, presetId)
	PlayerDataService:PushSnapshot(player)
	RaceService.RaceChosen:Fire(player, race)
end

local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		task.spawn(applyToCharacter, player, character)
	end)
	if player.Character then
		task.spawn(applyToCharacter, player, player.Character)
	end
end

function RaceService:Init()
	NetService:RegisterStateCheck("HasRace", function(player)
		local data = PlayerDataService:GetData(player)
		return data ~= nil and data.Race ~= nil
	end)

	NetService:Handle("SelectRace", onSelectRace)

	PlayerDataService.ProfileLoaded:Connect(function(player, data)
		publish(player, data.Race)
		if data.Race == nil then
			task.spawn(buildPreviews, player)
		end
	end)
end

function RaceService:Start()
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
end

function RaceService:GetRace(player: Player): string?
	local data = PlayerDataService:GetData(player)
	return if data then data.Race else nil
end

return RaceService
