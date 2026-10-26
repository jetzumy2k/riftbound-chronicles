--!strict
--[[
	WeaponTrail — a glowing streak behind the weapon while a character
	swings (D-103 stage B). Built once per character on its weapon hand:
	two attachments, one at the grip and one out at the weapon's tip
	(along the grip's +Y, OutfitBuilder.FORWARD_GRIP), joined by a Trail in
	the character's glow colour. `swing` switches it on for one attack or
	skill; it fades by itself.

	Melee swings only: Warriors (sword), Healers and Mages (staff / mace,
	shorter streak); Archers draw a bow and get none. Client-only, one
	Trail per character, no new parts. Display only.
]]

local Players = game:GetService("Players")

local CombatVfx = require(script.Parent.CombatVfx)

local WeaponTrail = {}

-- Same as OutfitBuilder.FORWARD_GRIP: +Y from the grip to the weapon tip.
local FORWARD_GRIP = CFrame.new(0, -0.1, 0) * CFrame.Angles(math.rad(-110), 0, 0)
-- Streak length (studs from the grip) by job; 0 = no trail.
local REACH: { [string]: number } = { Warrior = 4.2, Healer = 3, Mage = 3, Archer = 0 }
local TRAIL = "RC_WeaponTrail"

type Rig = { trail: Trail, hand: BasePart, offAt: number }

local rigs: { [Model]: Rig } = setmetatable({}, { __mode = "k" }) :: any

local function jobOf(model: Model): string?
	local player = Players:GetPlayerFromCharacter(model)
	local job = if player then player:GetAttribute("Job") else model:GetAttribute("Job")
	return if type(job) == "string" then job else nil
end

local function handOf(model: Model): BasePart?
	for _, name in { "RightHand", "Right Arm" } do
		local part = model:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			return part
		end
	end
	return nil
end

local function build(model: Model): Rig?
	local reach = REACH[jobOf(model) or "Warrior"] or 0
	local hand = handOf(model)
	if reach <= 0 or hand == nil then
		return nil
	end
	local old = hand:FindFirstChild(TRAIL)
	if old then
		old:Destroy()
	end
	local holder = Instance.new("Folder")
	holder.Name = TRAIL
	local grip = Instance.new("Attachment")
	grip.Name = "RC_TrailGrip"
	grip.CFrame = FORWARD_GRIP * CFrame.new(0, reach * 0.35, 0)
	grip.Parent = hand
	local tip = Instance.new("Attachment")
	tip.Name = "RC_TrailTip"
	tip.CFrame = FORWARD_GRIP * CFrame.new(0, reach, 0)
	tip.Parent = hand
	local color = CombatVfx.glowColor(model)
	local trail = Instance.new("Trail")
	trail.Attachment0 = grip
	trail.Attachment1 = tip
	trail.Lifetime = 0.2
	trail.MinLength = 0.05
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.FaceCamera = false
	trail.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(0.6, 0.6),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new(1, 0.3)
	trail.Enabled = false
	trail.Parent = holder
	holder.Parent = hand
	-- The attachments go with the folder when the trail is rebuilt.
	holder.Destroying:Connect(function()
		grip:Destroy()
		tip:Destroy()
	end)
	return { trail = trail, hand = hand, offAt = 0 }
end

-- Streaks the weapon for `seconds` (one swing or skill).
function WeaponTrail.swing(model: Model, seconds: number)
	local rig = rigs[model]
	if rig == nil or rig.trail.Parent == nil or rig.hand.Parent ~= model then
		local built = build(model)
		if built == nil then
			return
		end
		rigs[model] = built
		rig = built
	end
	local active = rig :: Rig
	local offAt = os.clock() + math.clamp(seconds, 0.1, 1.5)
	active.offAt = offAt
	active.trail.Enabled = true
	task.delay(offAt - os.clock(), function()
		-- A later swing extends it.
		if active.offAt == offAt and active.trail.Parent then
			active.trail.Enabled = false
		end
	end)
end

return WeaponTrail
