--!strict
--[[
	BodyStyle — every character's body and head (equipment overhaul stage 4,
	PLAN.md D-70; creator's reviews 2026-10-19: smooth body for all; the
	slim realistic body with the classic head looked thin and ugly; the
	anime body read as a child, then a baby; the creator asked for an adult
	with some muscle, "like a pro athlete").

	Every character gets Roblox's free official "Base Body - Jordan"
	(bundle 994, creator Roblox, free; asset ids checked against the
	catalog API 2026-10-19): adult-proportioned smooth torso, arms and legs
	with the matching animated head, eyebrows, eyelashes and mood face.
	The player's own hair and skin colours stay. The build is made
	athletic after the body is applied: the Humanoid's width / depth scale
	values are raised past the avatar defaults (broad shoulders, muscular
	limbs) at full adult height. Everyone gets the same build, so gear
	fits every character alike.

	`apply` runs once per character, on the server, before the outfit is
	built; it yields (HumanoidDescription), so callers must allow that.
	Turn it off with config Appearance.SmoothBody.
]]

local BodyStyle = {}

-- Base Body - Jordan (bundle 994).
BodyStyle.PARTS = table.freeze({
	Torso = 11740060397,
	LeftArm = 11740050465,
	RightArm = 11740055375,
	LeftLeg = 11740052832,
	RightLeg = 11740057815,
	Head = 11740063830,
})
BodyStyle.FACE = table.freeze({
	Eyebrows = 11740066767,
	Eyelashes = 11740069153,
	Mood = 11573370910,
})

-- Adult proportions from the description (standard ranges)...
BodyStyle.SCALES = table.freeze({
	Height = 1.05,
	Width = 1,
	Depth = 1,
	Head = 1,
	Proportion = 0,
	BodyType = 0,
})

-- ...then an athletic build on the Humanoid itself (past the avatar
-- editor's limits): broader shoulders and chest, thicker limbs.
BodyStyle.ATHLETE = table.freeze({
	Width = 1.3,
	Depth = 1.25,
})

local APPLIED_ATTRIBUTE = "RC_SmoothBody"

-- Puts the body, head and scales on `description` (players' hair and
-- colours untouched). Also used for the realm previews.
function BodyStyle.dress(description: HumanoidDescription)
	local parts = BodyStyle.PARTS
	description.Torso = parts.Torso
	description.LeftArm = parts.LeftArm
	description.RightArm = parts.RightArm
	description.LeftLeg = parts.LeftLeg
	description.RightLeg = parts.RightLeg
	description.Head = parts.Head
	-- The animated head draws its own face.
	description.Face = 0
	description.MoodAnimation = BodyStyle.FACE.Mood
	-- The head's own eyebrows and eyelashes replace the avatar's (hair and
	-- other accessories stay; casual ones are stripped by the Wardrobe).
	local accessories = {}
	-- Only layered clothing carries an Order; rigid accessories must not.
	for _, entry in description:GetAccessories(true) do
		local kind = entry.AccessoryType
		if kind ~= Enum.AccessoryType.Eyebrow and kind ~= Enum.AccessoryType.Eyelash then
			table.insert(accessories, entry)
		end
	end
	table.insert(accessories, {
		AssetId = BodyStyle.FACE.Eyebrows,
		AccessoryType = Enum.AccessoryType.Eyebrow,
		IsLayered = false,
	})
	table.insert(accessories, {
		AssetId = BodyStyle.FACE.Eyelashes,
		AccessoryType = Enum.AccessoryType.Eyelash,
		IsLayered = false,
	})
	description:SetAccessories(accessories, true)
	local scales = BodyStyle.SCALES
	description.HeightScale = scales.Height
	description.WidthScale = scales.Width
	description.DepthScale = scales.Depth
	description.HeadScale = scales.Head
	description.ProportionScale = scales.Proportion
	description.BodyTypeScale = scales.BodyType
end

-- The athletic build: the Humanoid's own scale values (it rescales the
-- body parts and joints). Also used for the realm previews.
function BodyStyle.athlete(humanoid: Humanoid)
	local function set(name: string, value: number)
		local scale = humanoid:FindFirstChild(name)
		if scale and scale:IsA("NumberValue") then
			scale.Value = value
		end
	end
	set("BodyWidthScale", BodyStyle.ATHLETE.Width)
	set("BodyDepthScale", BodyStyle.ATHLETE.Depth)
end

--[[
	Gives `character` the body (once). Returns true if it is on (now or
	already), or false and why. Failures leave the avatar's own body.
]]
function BodyStyle.apply(character: Model): (boolean, string?)
	if character:GetAttribute(APPLIED_ATTRIBUTE) == true then
		return true, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil or humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		return false, "not an R15 humanoid"
	end
	local ok, err = pcall(function()
		local description = humanoid:GetAppliedDescription()
		BodyStyle.dress(description)
		humanoid:ApplyDescriptionAsync(description)
		BodyStyle.athlete(humanoid)
	end)
	if not ok then
		return false, tostring(err)
	end
	character:SetAttribute(APPLIED_ATTRIBUTE, true)
	return true, nil
end

return table.freeze(BodyStyle)
