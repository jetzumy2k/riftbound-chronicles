--!strict
--[[
	RaceService (Layer 2)
	Server-authoritative race and face preset (CLAUDE.md §3.1, Phase 3).

	  - A race is chosen once, through `SelectRace(race, presetId)`. Any later
	    attempt is rejected and logged; changing race is an admin action
	    (Phase 17).
	  - The preset must belong to the chosen race (FacePresets allowlist).
	  - `SetHeadStyle(style)` picks the adult head (D-72; Man / Woman) any
	    time: before a race, the previews are rebuilt; after, the body is
	    re-applied and the outfit rebuilt on the live character.
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
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Enums = require(Shared.Enums)
local FacePresets = require(Shared.Definitions.FacePresets)
local Log = require(Shared.Util.Log)
local Signal = require(Shared.Util.Signal)
local GearLook = require(Shared.Logic.GearLook)
local WeaponRules = require(Shared.Definitions.WeaponRules)
local HudSlots = require(Shared.Layout.HudSlots)

local Wardrobe = require(script.Parent.Parent.Appearance.Wardrobe)
local BodyStyle = require(script.Parent.Parent.Appearance.BodyStyle)

local AuditLogService = require(script.Parent.AuditLogService)
local NetService = require(script.Parent.NetService)
local ConfigurationService = require(script.Parent.ConfigurationService)
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
	-- D-70: the smooth body first (yields), then the outfit on top of it.
	if ConfigurationService:Get("Appearance.SmoothBody") then
		-- Again if the head style changed during the yield (SetHeadStyle
		-- leaves a character whose body is still being applied to this).
		local data = PlayerDataService:GetData(player)
		repeat
			local ok, err = BodyStyle.apply(character, data and data.HeadStyle)
			if not ok then
				log:Warn("smooth body not applied for %d: %s", player.UserId, tostring(err))
				break
			end
		until player.Character ~= character
			or data == nil
			or character:GetAttribute("RC_HeadStyle") == data.HeadStyle
		if player.Character ~= character then
			return
		end
	end
	RaceService:Redress(player)
end

--[[
	Dresses the player's current character in their race look and what they
	have equipped (D-65). InventoryService calls this when gear changes.
]]
function RaceService:Redress(player: Player)
	local character = player.Character
	local data = PlayerDataService:GetData(player)
	if character == nil or data == nil or data.Race == nil then
		return
	end
	local look = GearLook.fromEquipment(data.Equipment, data.Inventory)
	Wardrobe.dress(character, data.Race, data.FacePreset, data.Job, look)
	-- D-69: how the hands hold what's worn, for the animation (display only).
	local main, off = look.Weapon, look.OffHand
	character:SetAttribute(
		"WeaponProfile",
		WeaponRules.profileFor(
			main and main.family,
			if off then (if off.kind == "Shield" then "Shield" else "Weapon") else nil
		)
	)
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
	-- D-70: previews show the same smooth body the character will get.
	if ConfigurationService:Get("Appearance.SmoothBody") then
		local owner = PlayerDataService:GetData(player)
		BodyStyle.dress(description, owner and owner.HeadStyle)
	end

	local built, rig = pcall(function()
		return Players:CreateHumanoidModelFromDescriptionAsync(description, Enum.HumanoidRigType.R15)
	end)
	if not built or rig == nil then
		log:Warn("preview rig failed for %d: %s", player.UserId, tostring(rig))
		return
	end
	-- D-70: joints only settle in the world. Outside it, a scaled body keeps
	-- its parts where the unscaled rig had them (the head floated above a
	-- long gap). Rebuild the rig, let it settle out of sight, then use it.
	local rigHumanoid = rig:FindFirstChildOfClass("Humanoid")
	if rigHumanoid then
		if ConfigurationService:Get("Appearance.SmoothBody") then
			BodyStyle.athlete(rigHumanoid)
		end
		pcall(function()
			rigHumanoid:BuildRigFromAttachments()
		end)
	end
	rig:PivotTo(CFrame.new(0, 5000, 0))
	rig.Parent = Workspace
	RunService.Heartbeat:Wait()
	RunService.Heartbeat:Wait()
	rig.Parent = nil

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

-- Players whose head change is being applied (one at a time).
local restyling: { [Player]: boolean } = {}

local function onSetHeadStyle(player: Player, style: string)
	local data = PlayerDataService:GetData(player)
	if data == nil or not Enums.has(Enums.HeadStyle, style) or data.HeadStyle == style then
		return
	end
	data.HeadStyle = style
	PlayerDataService:PushSnapshot(player)
	log:Info("user=%d head style %s", player.UserId, style)
	if data.Race == nil then
		task.spawn(buildPreviews, player)
		return
	end
	local character = player.Character
	if
		character == nil
		or restyling[player]
		or character:GetAttribute("RC_SmoothBody") ~= true
		or not ConfigurationService:Get("Appearance.SmoothBody")
	then
		-- No body yet: the spawn path applies the new style when it gets there.
		return
	end
	restyling[player] = true
	task.spawn(function()
		-- Repeat while the choice moved on during the yield.
		while player.Character == character and character:GetAttribute("RC_HeadStyle") ~= data.HeadStyle do
			local ok, err = BodyStyle.apply(character, data.HeadStyle)
			if not ok then
				log:Warn("head style not applied for %d: %s", player.UserId, tostring(err))
				break
			end
		end
		restyling[player] = nil
		if player.Character == character then
			RaceService:Redress(player)
		end
	end)
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
	NetService:Handle("SetHeadStyle", onSetHeadStyle)
	-- D-74: where the player moved their HUD pieces (display only).
	NetService:Handle("SetHudLayout", function(player: Player, layout: any)
		local data = PlayerDataService:GetData(player)
		if data then
			data.Settings.HudLayout = HudSlots.sanitize(layout)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		restyling[player] = nil
	end)

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
