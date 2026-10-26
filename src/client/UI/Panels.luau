--!strict
--[[
	Panels — one full panel open at a time, above the HUD (creator review
	2026-10-24: panels overlapped each other and the HUD and were hard to
	close; PLAN.md D-74).

	Every big screen (bag, skills, quests, party invites) puts its panel in
	the shared "RC_Panels" layer:
	  - drawn above every HUD piece (DisplayOrder 15; toasts stay above);
	  - a dim backdrop behind the panel: tapping it closes the panel
	    (unless the panel registered `keepOnBackdrop`, e.g. the admin
	    panel, where a stray tap would throw away typed values);
	  - opening one panel closes the one that was open;
	  - world prompts ("Talk", "Collect") are hidden while a panel is open,
	    so they never sit on top of it;
	  - the HUD steps aside while a panel is open (creator review
	    2026-10-26: buttons and pills around an open panel looked
	    disorganised): the HUD layers in HUD_LAYERS are hidden and come
	    back as they were when the panel closes. Toasts stay.

	    Panels.register("bag", function() setOpen(false) end)
	    Panels.opened("bag")   -- when it opens
	    Panels.closed("bag")   -- when it closes
	    frame.Parent = Panels.layer()
]]

local Players = game:GetService("Players")

local Tooltip = require(script.Parent.Tooltip)
local ProximityPromptService = game:GetService("ProximityPromptService")

local Panels = {}

local gui: ScreenGui? = nil
local backdrop: TextButton? = nil
local current: string? = nil
local closers: { [string]: () -> () } = {}
local keepOnBackdrop: { [string]: boolean } = {}

-- HUD layers hidden while a panel is open (skill bar, combat buttons,
-- SKILLS / BAG / quest / party pills, chips, target plate, HUD panels).
local HUD_LAYERS = {
	"RC_Hud",
	"RC_Combat",
	"RC_AutoAttack",
	"RC_Skills",
	"RC_SkillTree",
	"RC_Inventory",
	"RC_Quests",
	"RC_Party",
	"RC_Dungeon",
	"RC_Events",
	"RC_Buffs",
	"RC_AdminButton",
	"RC_Movement",
	"RC_TargetPlate",
	"RC_HudEditButton",
}
-- The layers this module hid (only these are shown again).
local hidden: { ScreenGui } = {}

local function setHud(visible: boolean)
	if visible then
		for _, layer in hidden do
			layer.Enabled = true
		end
		table.clear(hidden)
		return
	end
	local playerGui = (Players.LocalPlayer :: Player):FindFirstChildOfClass("PlayerGui")
	if playerGui == nil then
		return
	end
	for _, name in HUD_LAYERS do
		local layer = playerGui:FindFirstChild(name)
		if layer and layer:IsA("ScreenGui") and layer.Enabled then
			layer.Enabled = false
			table.insert(hidden, layer)
		end
	end
end

local function setPrompts(enabled: boolean)
	pcall(function()
		ProximityPromptService.Enabled = enabled
	end)
end

-- The layer every panel is parented to (made on first use).
function Panels.layer(): ScreenGui
	local existing = gui
	if existing then
		return existing
	end
	local layer = Instance.new("ScreenGui")
	layer.Name = "RC_Panels"
	layer.ResetOnSpawn = false
	layer.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	layer.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	layer.DisplayOrder = 15
	local dim = Instance.new("TextButton")
	dim.Name = "Backdrop"
	dim.Text = ""
	dim.AutoButtonColor = false
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 0.5
	dim.Size = UDim2.fromScale(1, 1)
	dim.ZIndex = 0
	dim.Visible = false
	dim.Parent = layer
	dim.Activated:Connect(function()
		local name = current
		if name and keepOnBackdrop[name] then
			return
		end
		local close = name and closers[name]
		if close then
			close()
		end
	end)
	layer.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")
	gui, backdrop = layer, dim
	return layer
end

-- `close` shuts the named panel (called when another one opens or the
-- backdrop is tapped). It must call Panels.closed. With `keep` true a
-- backdrop tap leaves the panel open.
function Panels.register(name: string, close: () -> (), keep: boolean?)
	closers[name] = close
	keepOnBackdrop[name] = keep == true
end

function Panels.opened(name: string)
	Panels.layer()
	local previous = current
	current = name
	if previous and previous ~= name then
		local close = closers[previous]
		if close then
			close()
		end
	end
	if backdrop then
		backdrop.Visible = true
	end
	setPrompts(false)
	setHud(false)
	Tooltip.hide()
end

function Panels.closed(name: string)
	if current ~= name then
		return
	end
	current = nil
	if backdrop then
		backdrop.Visible = false
	end
	setPrompts(true)
	setHud(true)
end

function Panels.isOpen(): boolean
	return current ~= nil
end

return Panels
