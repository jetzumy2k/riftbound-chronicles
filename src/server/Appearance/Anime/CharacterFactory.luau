--!strict
--[[
	CharacterFactory — the modern fantasy anime characters (PLAN.md D-100;
	the creator's reference: "Riftbound Chronicles Class Showcase").

	Everything is built on the server from Roblox Parts on a normal R15
	rig, so movement, animations, combat and every gameplay system are
	untouched:
	  1. `applyBody` gives the rig a plain R15 body at the anime
	     proportions (AnimeArchetypes.BODY, inside the avatar ranges). It
	     yields (HumanoidDescription).
	  2. `dressInto` hides the rig's own parts (they still carry the joints,
	     collisions and hit boxes) and welds the look onto them: head and
	     face (HeadBuilder), hair (HairBuilder), halo (CrownBuilder),
	     armour (ArmorBuilder), wings (WingBuilder), weapons
	     (WeaponBuilder) and the aura (AuraBuilder). Every piece is
	     massless, non-colliding and non-queryable (Kit).
	  3. `Create` builds a standalone character (NPCs, showcases).

	The pieces go into the character's RC_Outfit folder (rebuilt on every
	dress), so the systems that read the outfit (combat glow colour, the
	bag's 3D preview) keep working. No meshes, textures or Creator Store
	assets.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local AnimeArchetypes = require(ReplicatedStorage.Shared.Definitions.AnimeArchetypes)
local Complexion = require(ReplicatedStorage.Shared.Definitions.Complexion)
local GearLook = require(ReplicatedStorage.Shared.Logic.GearLook)

local ArmorBuilder = require(script.Parent.ArmorBuilder)
local AuraBuilder = require(script.Parent.AuraBuilder)
local CrownBuilder = require(script.Parent.CrownBuilder)
local HairBuilder = require(script.Parent.HairBuilder)
local HeadBuilder = require(script.Parent.HeadBuilder)
local Kit = require(script.Parent.Kit)
local WeaponBuilder = require(script.Parent.WeaponBuilder)
local WingBuilder = require(script.Parent.WingBuilder)

local CharacterFactory = {}

-- The player's choices for the anime look: head style ("Man" / "Woman"),
-- skin tone and hair colour (Complexion ids; nil / "Default" = the realm's).
export type Look = { variant: string?, skin: string?, hair: string? }

CharacterFactory.BODY_ATTRIBUTE = "RC_AnimeBody"

local BODY_PARTS = { "Torso", "LeftArm", "RightArm", "LeftLeg", "RightLeg", "Head", "Face" }
local CLOTHES = { "Shirt", "Pants", "GraphicTShirt" }

-- Puts the anime body on `description` (plain R15 parts, no face, no
-- accessories or clothes; the look is built from Parts).
function CharacterFactory.dress(description: HumanoidDescription)
	for _, name in BODY_PARTS do
		(description :: any)[name] = 0
	end
	for _, name in CLOTHES do
		(description :: any)[name] = 0
	end
	description:SetAccessories({}, true)
	local scales = AnimeArchetypes.BODY
	description.HeightScale = scales.Height
	description.WidthScale = scales.Width
	description.DepthScale = scales.Depth
	description.HeadScale = scales.Head
	description.ProportionScale = scales.Proportion
	description.BodyTypeScale = scales.BodyType
end

function CharacterFactory.description(): HumanoidDescription
	local description = Instance.new("HumanoidDescription")
	CharacterFactory.dress(description)
	return description
end

--[[
	Gives a live character the anime body (yields). Returns true when it is
	on (now or already), or false and why; failures leave the body as it was
	(the look is still built on it, sized from its parts).
]]
function CharacterFactory.applyBody(character: Model): (boolean, string?)
	if character:GetAttribute(CharacterFactory.BODY_ATTRIBUTE) == true then
		return true, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil or humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		return false, "not an R15 humanoid"
	end
	local ok, err = pcall(function()
		local description = humanoid:GetAppliedDescription()
		CharacterFactory.dress(description)
		humanoid:ApplyDescriptionAsync(description)
	end)
	if not ok then
		return false, tostring(err)
	end
	character:SetAttribute(CharacterFactory.BODY_ATTRIBUTE, true)
	-- The classic smooth body (BodyStyle) is gone from this character.
	character:SetAttribute("RC_SmoothBody", nil)
	character:SetAttribute("RC_HeadStyle", nil)
	return true, nil
end

-- Hides the rig's own body (joints, collisions and hit boxes stay) and
-- drops anything worn over it.
local function hideRig(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	for _, child in character:GetChildren() do
		if
			child:IsA("Accessory")
			or child:IsA("Shirt")
			or child:IsA("Pants")
			or child:IsA("ShirtGraphic")
		then
			child:Destroy()
		elseif child:IsA("BasePart") and child.Name ~= "HumanoidRootPart" then
			if humanoid == nil or humanoid:GetBodyPartR15(child) ~= Enum.BodyPartR15.Unknown then
				child.Transparency = 1
				for _, item in child:GetChildren() do
					if item:IsA("Decal") then
						item:Destroy()
					end
				end
			end
		end
	end
end

--[[
	Which weapons the anime builder draws for `look` (nil = the full look:
	previews and NPCs). Returns whether it draws the hands at all (false:
	the classic OutfitBuilder weapon for that family), the off-hand
	("Shield" / "Sword" / nil) and whether the weapon sparkles.
]]
function CharacterFactory.weaponPlan(
	archetype: AnimeArchetypes.Archetype,
	look: GearLook.Look?
): (boolean, string?, boolean)
	if archetype.weapon == nil then
		return false, nil, false
	end
	if look == nil then
		return true, if archetype.offHand == "KiteShield" then "Shield" else nil, true
	end
	local main, off = look.Weapon, look.OffHand
	local offKind: string? = nil
	if off and off.kind == "Shield" then
		offKind = "Shield"
	elseif off and off.family == "Sword" then
		offKind = "Sword"
	end
	if main == nil then
		return true, if offKind == "Shield" then "Shield" else nil, false
	end
	if main.family ~= "Sword" then
		return false, nil, false
	end
	return true, offKind, GearLook.sparkles(main)
end

--[[
	Builds the anime look into `folder` (the character's RC_Outfit) on
	`character`. `hands` = draw the weapons (see weaponPlan). Returns the
	number of parts built.
]]
function CharacterFactory.dressInto(
	folder: Folder,
	character: Model,
	archetype: AnimeArchetypes.Archetype,
	look: GearLook.Look?,
	hands: boolean,
	choice: Look?
): number
	hideRig(character)
	local palette = table.clone(archetype.palette)
	local skin = Complexion.skin(archetype.race, choice and choice.skin)
	local hair = Complexion.hair(archetype.race, choice and choice.hair)
	palette.skin = skin.rgb
	palette.blush = Complexion.blush(skin.rgb)
	palette.hair = hair.rgb
	palette.hairTip = hair.tip
	local ctx: Kit.Ctx = {
		folder = folder,
		archetype = archetype,
		palette = palette,
		variant = if choice and choice.variant == "Woman" then "Woman" else "Man",
		count = 0,
	}
	local body = Kit.readBody(character)
	local frame = HeadBuilder.build(ctx, body)
	if frame then
		HairBuilder.build(ctx, frame)
		CrownBuilder.build(ctx, frame)
	end
	ArmorBuilder.build(ctx, body)
	WingBuilder.build(ctx, body)
	if hands then
		local _, offHand, sparkle = CharacterFactory.weaponPlan(archetype, look)
		WeaponBuilder.build(ctx, body, offHand, sparkle)
	end
	AuraBuilder.build(ctx, body)
	folder:SetAttribute("RC_Archetype", archetype.id)
	folder:SetAttribute("RC_AnimeParts", ctx.count)
	return ctx.count
end

export type Spec = {
	archetype: string,
	choice: Look?,
	name: string?,
	look: GearLook.Look?,
	cframe: CFrame?,
	parent: Instance?,
}

--[[
	A standalone character (NPCs, showcases): an R15 rig with the anime
	body, settled in the world, its root anchored, dressed in the full look
	of `spec.archetype`. Yields. Returns nil (and why) on failure.
]]
function CharacterFactory.Create(spec: Spec): (Model?, string?)
	local archetype = AnimeArchetypes.get(spec.archetype)
	if archetype == nil then
		return nil, "unknown archetype"
	end
	local ok, result = pcall(function()
		return Players:CreateHumanoidModelFromDescriptionAsync(
			CharacterFactory.description(),
			Enum.HumanoidRigType.R15
		)
	end)
	if not ok or result == nil then
		return nil, tostring(result)
	end
	local model = result :: Model
	model.Name = spec.name or archetype.title
	model:SetAttribute(CharacterFactory.BODY_ATTRIBUTE, true)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end
	model:PivotTo(spec.cframe or CFrame.new(0, 5000, 0))
	model.Parent = spec.parent or Workspace
	-- Joints settle in the world; then hold still.
	RunService.Heartbeat:Wait()
	RunService.Heartbeat:Wait()
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.Anchored = true
	end
	local folder = Instance.new("Folder")
	folder.Name = "RC_Outfit"
	CharacterFactory.dressInto(folder, model, archetype, spec.look, true, spec.choice)
	folder.Parent = model
	return model, nil
end

return CharacterFactory
