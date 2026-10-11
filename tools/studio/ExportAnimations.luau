--[[
	ExportAnimations — run in Roblox Studio's Command Bar (View → Command Bar)
	with the game place open (not in Play mode).

	Builds every authored animation (AnimationClips) as a KeyframeSequence so
	you can publish them to your Roblox account before release. Full
	walkthrough: docs/ASSET_GUIDE.md, "Publishing animations".

	HOW TO USE
	  1. Copy this whole file, paste it into the Command Bar, press Enter.
	  2. The clips appear in ServerStorage → RC_AnimationExport.
	  3. Right-click each one → "Save to Roblox…" → give it the same name →
	     Submit. Copy the asset id it shows.
	  4. Put the ids in src/shared/Definitions/AnimationAssets.luau, e.g.
	         Warrior_Attack1 = "rbxassetid://1234567890",

	Re-run any time the clips change; it replaces the folder.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AnimationClips = require(Shared.Definitions.AnimationClips)
local ClipBuilder = require(Shared.Animation.ClipBuilder)

local old = ServerStorage:FindFirstChild("RC_AnimationExport")
if old then
	old:Destroy()
end
local folder = Instance.new("Folder")
folder.Name = "RC_AnimationExport"

local count = 0
for _, name in AnimationClips.NAMES do
	local clip = AnimationClips.Clips[name]
	local variants = { "Full" }
	-- Attacks and hit reactions that move the legs also need an upper-body
	-- version (played while walking). Loops and Defeat are always full body.
	local action = string.find(name, "_Attack", 1, true) ~= nil or string.sub(name, 1, 3) == "Hit"
	if action and ClipBuilder.hasLowerBody(clip) then
		table.insert(variants, "Upper")
	end
	for _, variant in variants do
		local sequence = ClipBuilder.build(name, clip, variant :: any)
		sequence.Parent = folder
		count += 1
	end
end
folder.Parent = ServerStorage
print(`[RC] Exported {count} animations to ServerStorage.RC_AnimationExport. Publish each with "Save to Roblox…".`)
