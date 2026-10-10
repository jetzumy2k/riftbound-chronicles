--!strict
--[[
	Wardrobe
	Dresses a character in its race look (PLAN.md decision 2026-10-11: game
	outfits over the player's avatar).

	  1. Strip casual avatar items: classic Shirt/Pants/T-shirt and every
	     accessory except hair, eyebrows and eyelashes. The player's face, body
	     shape and skin tone are kept.
	  2. Apply the look, slot by slot (Body, Cape, Wings, Halo, Horns, Tail):
	     - approved Creator Store accessories from ServerStorage.RC_Assets
	       (prepared with tools/studio/PrepareAccessory.luau);
	     - the procedural OutfitBuilder pieces for every slot not covered.
	  3. Apply the preset face texture, if one is defined.

	Only server-owned data is used: the preset comes from the FacePresets
	allowlist and assets from ServerStorage. Clients never supply ids.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local FacePresets = require(ReplicatedStorage.Shared.Definitions.FacePresets)

local OutfitBuilder = require(script.Parent.OutfitBuilder)

local KEEP_ACCESSORY_TYPES: { [Enum.AccessoryType]: boolean } = {
	[Enum.AccessoryType.Hair] = true,
	[Enum.AccessoryType.Eyebrow] = true,
	[Enum.AccessoryType.Eyelash] = true,
}

local Wardrobe = {}

local function stripCasual(character: Model)
	for _, child in character:GetChildren() do
		local isClothing = child:IsA("Shirt") or child:IsA("Pants") or child:IsA("ShirtGraphic")
		local isCasualAccessory = child:IsA("Accessory") and not KEEP_ACCESSORY_TYPES[child.AccessoryType]
		if isClothing or isCasualAccessory then
			child:Destroy()
		end
	end
end

local VALID_SLOTS: { [string]: boolean } = {}
for _, slot in OutfitBuilder.SLOTS do
	VALID_SLOTS[slot] = true
end

local function accessoriesIn(folder: Instance?): { Accessory }
	local list = {}
	if folder then
		for _, item in folder:GetChildren() do
			if item:IsA("Accessory") then
				table.insert(list, item)
			end
		end
	end
	return list
end

-- Slot an approved accessory replaces ("Extra" = adds without replacing).
local function slotOf(accessory: Accessory): string
	local slot = accessory:GetAttribute("RC_Slot")
	return if type(slot) == "string" and VALID_SLOTS[slot] then slot else "Extra"
end

--[[
	Approved Creator Store art for a look (PLAN.md D-27):
	  ServerStorage.RC_Assets.Outfits.<LookName>   only that look
	  ServerStorage.RC_Assets.Outfits._<Race>      every look of that race
	A look-specific item wins over a race-wide item for the same slot.
	Returns the accessories to wear and the set of slots they cover.
]]
local function approvedAccessories(preset: FacePresets.FacePreset): ({ Accessory }, { [string]: boolean })
	local root = ServerStorage:FindFirstChild("RC_Assets")
	local outfits = root and root:FindFirstChild("Outfits")
	if outfits == nil then
		return {}, {}
	end
	local chosen: { Accessory } = {}
	local covered: { [string]: boolean } = {}
	for _, accessory in accessoriesIn(outfits:FindFirstChild(preset.name)) do
		table.insert(chosen, accessory)
		local slot = slotOf(accessory)
		if slot ~= "Extra" then
			covered[slot] = true
		end
	end
	for _, accessory in accessoriesIn(outfits:FindFirstChild(`_{preset.race}`)) do
		local slot = slotOf(accessory)
		if slot == "Extra" or not covered[slot] then
			table.insert(chosen, accessory)
		end
	end
	for _, accessory in chosen do
		local slot = slotOf(accessory)
		if slot ~= "Extra" then
			covered[slot] = true
		end
	end
	return chosen, covered
end

local function applyFaceTexture(character: Model, texture: string?)
	if texture == nil then
		return -- keep the player's own face
	end
	assert(
		string.match(texture, "^rbxassetid://%d+$") or string.match(texture, "^rbxasset://"),
		"invalid face texture"
	)
	local head = character:FindFirstChild("Head")
	local decal = head and head:FindFirstChild("face")
	if decal and decal:IsA("Decal") then
		decal.Texture = texture
	end
end

--[[
	Dresses `character`. Safe to call repeatedly (previous outfit is replaced).
	Returns true if the look was applied.
]]
function Wardrobe.dress(character: Model, race: string, presetId: number): boolean
	local preset = FacePresets.get(presetId)
	if preset == nil or preset.race ~= race then
		return false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil or character:FindFirstChild("Head") == nil then
		return false
	end

	stripCasual(character)

	local approved, covered = approvedAccessories(preset)
	for _, accessory in approved do
		humanoid:AddAccessory(accessory:Clone())
	end
	-- Procedural pieces fill every slot the approved art does not cover.
	OutfitBuilder.build(character, race, preset, covered)

	applyFaceTexture(character, preset.faceTexture)
	return true
end

return Wardrobe
