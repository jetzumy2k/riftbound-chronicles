--!strict
--[[
	BodyStyle — every character's body and head (equipment overhaul stage 4,
	PLAN.md D-70; creator's reviews 2026-10-19: smooth body for all; the
	slim realistic body with the classic head looked thin and ugly; the
	anime body read as a child, then a baby; the creator asked for an adult
	with some muscle, "like a pro athlete"; 2026-10-22: still too thin and
	the faces looked like children, so the build is broader and the head is
	an adult one the player picks, D-72; the "Man Face" / "Woman Face"
	cartoon heads tried next looked ugly, so the heads are the most mature
	of the realistic base-body heads).

	Every character gets Roblox's free official "Base Body - Jordan"
	(bundle 994, creator Roblox, free; asset ids checked against the
	catalog API 2026-10-19) for the torso, arms and legs. The head is the
	player's pick (profile HeadStyle, Enums.HeadStyle) of the two most
	mature realistic heads among the 16 free official base bodies (the
	others have large, childlike eyes): "Man" is Harper's (bundle 989:
	strong nose and jaw, smaller eyes), "Woman" Addison's (bundle 988),
	each with its own brows and eyelashes and the realistic mood face (ids
	checked against the catalog API 2026-10-22). The player's own hair and skin
	colours stay. The build is made athletic after the body is applied:
	the Humanoid's width / depth scale values are raised past the avatar
	defaults (broad shoulders, muscular limbs) at full adult height, with a
	slightly smaller head for adult proportions. Everyone gets the same
	build, so gear fits every character alike.

	`apply` runs once per character (again when the head style changes),
	on the server, before the outfit is built; it yields
	(HumanoidDescription), so callers must allow that. Turn it off with
	config Appearance.SmoothBody.
]]

local BodyStyle = {}

-- Base Body - Jordan (bundle 994).
BodyStyle.PARTS = table.freeze({
	Torso = 11740060397,
	LeftArm = 11740050465,
	RightArm = 11740055375,
	LeftLeg = 11740052832,
	RightLeg = 11740057815,
})

-- The adult heads (Enums.HeadStyle): head, mood face, brows.
export type Head = { Head: number, Mood: number, Eyebrows: number, Eyelashes: number }
BodyStyle.HEADS = table.freeze({
	-- Base Body - Harper (bundle 989).
	Man = table.freeze({
		Head = 11702751287,
		Mood = 11573370910,
		Eyebrows = 11702755085,
		Eyelashes = 11702757409,
	}),
	-- Base Body - Addison (bundle 988).
	Woman = table.freeze({
		Head = 11702291006,
		Mood = 11573370910,
		Eyebrows = 11702295477,
		Eyelashes = 11702297008,
	}),
})
BodyStyle.DEFAULT_HEAD = "Man"

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
-- editor's limits): broader shoulders and chest, thicker limbs, and a
-- head a little smaller than the body's default (adult proportions).
BodyStyle.ATHLETE = table.freeze({
	Width = 1.45,
	Depth = 1.4,
	Head = 0.92,
})

local APPLIED_ATTRIBUTE = "RC_SmoothBody"
local HEAD_ATTRIBUTE = "RC_HeadStyle"

local function headFor(style: string?): Head
	return BodyStyle.HEADS[style or ""] or BodyStyle.HEADS[BodyStyle.DEFAULT_HEAD]
end

-- Puts the body, head and scales on `description` (players' hair and
-- colours untouched). Also used for the realm previews.
function BodyStyle.dress(description: HumanoidDescription, headStyle: string?)
	local parts = BodyStyle.PARTS
	local head = headFor(headStyle)
	description.Torso = parts.Torso
	description.LeftArm = parts.LeftArm
	description.RightArm = parts.RightArm
	description.LeftLeg = parts.LeftLeg
	description.RightLeg = parts.RightLeg
	description.Head = head.Head
	-- The animated head draws its own face.
	description.Face = 0
	description.MoodAnimation = head.Mood
	-- The head's own brows and lashes replace the avatar's (hair and other
	-- accessories stay; casual ones are stripped by the Wardrobe).
	local accessories = {}
	for _, entry in description:GetAccessories(true) do
		local kind = entry.AccessoryType
		if kind ~= Enum.AccessoryType.Eyebrow and kind ~= Enum.AccessoryType.Eyelash then
			-- Layered entries need an Order (SetAccessories warns without
			-- one); rigid ones must not carry one.
			if entry.IsLayered and entry.Order == nil then
				entry.Order = #accessories + 1
			end
			table.insert(accessories, entry)
		end
	end
	for kind, id in
		{ [Enum.AccessoryType.Eyebrow] = head.Eyebrows, [Enum.AccessoryType.Eyelash] = head.Eyelashes }
	do
		table.insert(accessories, { AssetId = id, AccessoryType = kind, IsLayered = false })
	end
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
	set("HeadScale", BodyStyle.ATHLETE.Head)
end

--[[
	Gives `character` the body with the `headStyle` head (once; again only
	if the head style changed). Returns true if it is on (now or already),
	or false and why. Failures leave the character as it was.
]]
function BodyStyle.apply(character: Model, headStyle: string?): (boolean, string?)
	local style = if BodyStyle.HEADS[headStyle or ""] then headStyle :: string else BodyStyle.DEFAULT_HEAD
	if
		character:GetAttribute(APPLIED_ATTRIBUTE) == true
		and character:GetAttribute(HEAD_ATTRIBUTE) == style
	then
		return true, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil or humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		return false, "not an R15 humanoid"
	end
	local ok, err = pcall(function()
		local description = humanoid:GetAppliedDescription()
		BodyStyle.dress(description, style)
		humanoid:ApplyDescriptionAsync(description)
		BodyStyle.athlete(humanoid)
	end)
	if not ok then
		return false, tostring(err)
	end
	character:SetAttribute(APPLIED_ATTRIBUTE, true)
	character:SetAttribute(HEAD_ATTRIBUTE, style)
	return true, nil
end

return table.freeze(BodyStyle)
