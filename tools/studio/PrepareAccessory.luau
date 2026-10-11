--[[
	PrepareAccessory — run in Roblox Studio's Command Bar (View → Command Bar).

	Turns ONE model you inserted from the Creator Store into a safe, wearable
	accessory for Riftbound Chronicles. Full walkthrough: docs/ASSET_GUIDE.md.

	HOW TO USE
	  1. In the Explorer, click the model you inserted (select only that one).
	  2. Edit the 2 lines marked "EDIT ME" below.
	  3. Copy this whole file, paste it into the Command Bar, press Enter.
	  4. The result appears in ServerStorage → RC_Import. Right-click it →
	     "Save to File…" → save it in the folder the Output window tells you.
]]

-- ▼▼▼ EDIT ME ▼▼▼
local SLOT = "Wings" -- Wings | Halo | Horns | Tail | Cape | Body | Weapon
local LOOK = "_Angel" -- _Angel or _Devil (every look of that race), or one look name, e.g. "Dawnlight"
-- ▲▲▲ EDIT ME ▲▲▲

-- Optional fine-tuning after you have tested it in Play mode:
local SCALE = 1 -- 1 = unchanged, 0.8 = 20% smaller, 1.2 = 20% bigger
local OFFSET = Vector3.new(0, 0, 0) -- studs: X = right, Y = up, Z = backward
local TURN = Vector3.new(0, 0, 0) -- degrees: use (0, 180, 0) if it faces the wrong way

local SLOT_INFO = {
	Wings = { attachment = "BodyBackAttachment", accessoryType = Enum.AccessoryType.Back },
	Cape = { attachment = "BodyBackAttachment", accessoryType = Enum.AccessoryType.Back },
	Halo = { attachment = "HatAttachment", accessoryType = Enum.AccessoryType.Hat },
	Horns = { attachment = "HatAttachment", accessoryType = Enum.AccessoryType.Hat },
	Tail = { attachment = "WaistBackAttachment", accessoryType = Enum.AccessoryType.Waist },
	Body = { attachment = "BodyFrontAttachment", accessoryType = Enum.AccessoryType.Front },
	-- Held in the right hand (left-hand bows: rotate with TURN after testing).
	Weapon = { attachment = "RightGripAttachment", accessoryType = Enum.AccessoryType.Unknown },
}

local LOOKS = {
	_Angel = true,
	_Devil = true,
	Dawnlight = true,
	Moonsilver = true,
	Rosegleam = true,
	Skyward = true,
	Emberhorn = true,
	Obsidian = true,
	Crimson = true,
	["Violet Flame"] = true,
}

local Selection = game:GetService("Selection")
local ServerStorage = game:GetService("ServerStorage")

local info = SLOT_INFO[SLOT]
assert(info, "SLOT must be one of: Wings, Halo, Horns, Tail, Cape, Body, Weapon")
assert(LOOKS[LOOK], `LOOK '{LOOK}' is not valid. Use _Angel, _Devil or a look name like Dawnlight.`)

local selected = Selection:Get()
assert(#selected == 1, "Select exactly ONE model in the Explorer first.")
local source = selected[1]
assert(not source:IsA("LuaSourceContainer"), "You selected a script. Select the model instead.")

-- 1. Remove everything that can run code, make sound or be clicked.
local removed = 0
for _, item in source:GetDescendants() do
	if
		item:IsA("LuaSourceContainer")
		or item:IsA("ClickDetector")
		or item:IsA("ProximityPrompt")
		or item:IsA("Sound")
		or item:IsA("Humanoid")
		or item:IsA("Tool")
	then
		item:Destroy()
		removed += 1
	end
end

-- 2. Collect the visible parts.
local parts = {}
if source:IsA("BasePart") then
	table.insert(parts, source)
end
for _, item in source:GetDescendants() do
	if item:IsA("BasePart") then
		table.insert(parts, item)
	end
end
assert(#parts > 0, "This model has no parts to wear.")
assert(
	#parts <= 60,
	`This model has {#parts} parts. Pick a lighter model (60 parts max) for mobile performance.`
)

if SCALE ~= 1 and source:IsA("Model") then
	source:ScaleTo(source:GetScale() * SCALE)
end

local center
if source:IsA("Model") then
	center = (source:GetBoundingBox()).Position
else
	center = (source :: BasePart).Position
end

-- 3. Build the accessory: an invisible Handle that every part is welded to.
local accessory = Instance.new("Accessory")
accessory.Name = `{LOOK}_{SLOT}`
accessory.AccessoryType = info.accessoryType
accessory:SetAttribute("RC_Slot", SLOT)

local handle = Instance.new("Part")
handle.Name = "Handle"
handle.Size = Vector3.new(0.2, 0.2, 0.2)
handle.Transparency = 1
handle.CFrame = CFrame.new(center)
handle.Parent = accessory

for _, part in parts do
	if part:IsA("BasePart") then
		part.Anchored = false
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.Massless = true
		part.CastShadow = false
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = part
		weld.Parent = handle
	end
end
for _, part in { handle } do
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
end

local attachment = Instance.new("Attachment")
attachment.Name = info.attachment
attachment.CFrame = CFrame.new(-OFFSET)
	* CFrame.Angles(math.rad(-TURN.X), math.rad(-TURN.Y), math.rad(-TURN.Z))
attachment.Parent = handle

source.Name = "Model"
source.Parent = accessory

-- 4. Put the result where it is easy to save.
local import = ServerStorage:FindFirstChild("RC_Import")
if import == nil then
	import = Instance.new("Folder")
	import.Name = "RC_Import"
	import.Parent = ServerStorage
end
accessory.Parent = import
Selection:Set({ accessory })

print(
	"────────────────────────────────────────────────────────"
)
print(`✅ Prepared "{accessory.Name}" ({#parts} parts, removed {removed} scripts/extras).`)
print(`   It is selected in ServerStorage → RC_Import.`)
print(`   Right-click it → "Save to File…" and save it as:`)
print(`   riftbound-chronicles/assets/Outfits/{LOOK}/{SLOT}.rbxm`)
print("   (create the folder if it does not exist yet)")
print(
	"────────────────────────────────────────────────────────"
)
