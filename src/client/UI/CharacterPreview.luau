--!strict
--[[
	CharacterPreview — a live 3D copy of the local character for the bag
	screen (equipment overhaul stage 6, PLAN.md D-72).

	A ViewportFrame with a WorldModel holding a clone of the character in
	its rest pose, framed head to toe. Drag sideways to turn it; it eases
	back to facing the viewer. The outfit is rebuilt by the server after
	every equip (RaceService:Redress), so the copy is re-made shortly after
	the real character's parts change, and when the character respawns.

	Client-only and cosmetic: nothing here is sent to the server. The
	frame survives the bag screen's re-renders (it is re-parented, not
	re-made), and it only watches the character while it is shown.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local CharacterPreview = {}

-- Seconds of quiet after the last outfit change before the copy is re-made.
local REBUILD_DELAY = 0.35
local FOV = 30
-- Resting turn (slightly three-quarter) and how fast a drag turns it.
local REST_YAW = math.rad(-18)
local DRAG_RADIANS_PER_PX = 0.012
local EASE_PER_SECOND = 2.5

-- Kept from the clone: the body, the outfit, the Humanoid (for clothing).
local STRIP = {
	"Script",
	"LocalScript",
	"Sound",
	"ForceField",
	"BillboardGui",
	"ProximityPrompt",
	"Animator",
}

-- The backdrop (shown in the bag) and the viewport on it. The backdrop's
-- gradient must not be on the viewport: a UIGradient tints the 3D render.
local frame: Frame? = nil
local viewport: ViewportFrame? = nil
local world: WorldModel? = nil
local camera: Camera? = nil
local copy: Model? = nil
local copyCenter = Vector3.zero
local copySize = Vector3.new(4, 6, 2)
local yaw = REST_YAW
local dragging: InputObject? = nil
local dragX = 0
local shown = false
local watched: Model? = nil
local connections: { RBXScriptConnection } = {}
local rebuildToken = 0

local function disconnectAll()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
end

local function pose()
	if copy and copy.PrimaryPart then
		copy:PivotTo(CFrame.Angles(0, yaw, 0))
	end
end

-- R15 body parts: the framing follows the body, not wide wings or capes.
local BODY_PARTS = {
	"Head",
	"UpperTorso",
	"LowerTorso",
	"LeftUpperArm",
	"LeftLowerArm",
	"LeftHand",
	"RightUpperArm",
	"RightLowerArm",
	"RightHand",
	"LeftUpperLeg",
	"LeftLowerLeg",
	"LeftFoot",
	"RightUpperLeg",
	"RightLowerLeg",
	"RightFoot",
}

-- Centre and size of the body's box (the copy at the origin, unturned).
local function bodyBounds(model: Model): (Vector3, Vector3)
	local low = Vector3.one * math.huge
	local high = -low
	for _, name in BODY_PARTS do
		local part = model:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			local half = part.Size / 2
			for _, corner in
				{
					Vector3.new(half.X, half.Y, half.Z),
					Vector3.new(-half.X, half.Y, half.Z),
					Vector3.new(half.X, -half.Y, half.Z),
					Vector3.new(half.X, half.Y, -half.Z),
					Vector3.new(-half.X, -half.Y, half.Z),
					Vector3.new(-half.X, half.Y, -half.Z),
					Vector3.new(half.X, -half.Y, -half.Z),
					-half,
				}
			do
				local point = part.CFrame:PointToWorldSpace(corner)
				low = low:Min(point)
				high = high:Max(point)
			end
		end
	end
	if low.X == math.huge then
		local box, size = model:GetBoundingBox()
		return box.Position, size
	end
	return (low + high) / 2, high - low
end

-- Frames the copy so the whole body fits the viewport at any turn.
local function frameCamera()
	local view, cam, model = viewport, camera, copy
	if view == nil or cam == nil or model == nil then
		return
	end
	local size = view.AbsoluteSize
	local aspect = if size.Y > 0 then size.X / size.Y else 0.5
	local extents = copySize
	local half = math.tan(math.rad(FOV / 2))
	local across = math.max(extents.X, extents.Z)
	local distance = math.max(extents.Y / 2 / half, across / 2 / (half * math.max(aspect, 0.1))) * 1.06
	cam.FieldOfView = FOV
	cam.CFrame = CFrame.lookAt(copyCenter + Vector3.new(0, 0, -distance - across / 2), copyCenter)
end

local function rebuild()
	local view, model = world, watched
	if view == nil then
		return
	end
	if copy then
		copy:Destroy()
		copy = nil
	end
	if model == nil or model.Parent == nil or model:FindFirstChild("HumanoidRootPart") == nil then
		return
	end
	local wasArchivable = model.Archivable
	model.Archivable = true
	local ok, clone = pcall(function(): Model?
		return model:Clone()
	end)
	model.Archivable = wasArchivable
	if not ok or not clone then
		return
	end
	for _, item in clone:GetDescendants() do
		local strip = false
		for _, className in STRIP do
			if item:IsA(className) then
				strip = true
				break
			end
		end
		if strip then
			item:Destroy()
		elseif item:IsA("Motor6D") then
			-- Rest pose: the live animation's offsets are not kept.
			item.Transform = CFrame.identity
		elseif item:IsA("BasePart") then
			item.Anchored = false
			item.CanCollide = false
			item.CastShadow = false
		end
	end
	local root = clone:FindFirstChild("HumanoidRootPart") :: BasePart
	root.Anchored = true
	root.Transparency = 1
	clone.PrimaryPart = root
	local humanoid = clone:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end
	clone:PivotTo(CFrame.identity)
	clone.Parent = view
	copy = clone
	-- The centre at the resting turn's origin: turning is about the root.
	local center, size = bodyBounds(clone)
	copyCenter = Vector3.new(0, center.Y, 0)
	copySize = size
	pose()
	frameCamera()
end

local function scheduleRebuild()
	rebuildToken += 1
	local token = rebuildToken
	task.delay(REBUILD_DELAY, function()
		if shown and token == rebuildToken then
			rebuild()
		end
	end)
end

local function watch(character: Model?)
	disconnectAll()
	watched = character
	if not shown then
		return
	end
	local player = Players.LocalPlayer
	if player then
		table.insert(
			connections,
			player.CharacterAdded:Connect(function(newCharacter)
				watch(newCharacter)
			end)
		)
	end
	if character then
		-- Outfit pieces only: combat effects on the character don't count.
		local function changed(item: Instance)
			if item:IsA("BasePart") or item:IsA("Accessory") or item:IsA("Clothing") then
				scheduleRebuild()
			end
		end
		table.insert(connections, character.DescendantAdded:Connect(changed))
		table.insert(connections, character.DescendantRemoving:Connect(changed))
	end
	table.insert(
		connections,
		RunService.RenderStepped:Connect(function(dt: number)
			if dragging == nil and math.abs(yaw - REST_YAW) > 1e-3 then
				yaw += (REST_YAW - yaw) * math.min(1, dt * EASE_PER_SECOND)
				pose()
			end
		end)
	)
	table.insert(
		connections,
		UserInputService.InputChanged:Connect(function(input: InputObject)
			local active = dragging
			if active == nil then
				return
			end
			local moved = input == active
				or (
					active.UserInputType == Enum.UserInputType.MouseButton1
					and input.UserInputType == Enum.UserInputType.MouseMovement
				)
			if moved then
				local x: number = input.Position.X
				yaw += (x - dragX) * DRAG_RADIANS_PER_PX
				dragX = x
				pose()
			end
		end)
	)
	table.insert(
		connections,
		UserInputService.InputEnded:Connect(function(input: InputObject)
			if input == dragging or input.UserInputType == Enum.UserInputType.MouseButton1 then
				dragging = nil
			end
		end)
	)
	scheduleRebuild()
end

local function make(): Frame
	local backdrop = Instance.new("Frame")
	backdrop.Name = "CharacterPreview"
	backdrop.BackgroundColor3 = Color3.new(1, 1, 1)
	backdrop.BackgroundTransparency = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = backdrop
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(Color3.fromRGB(120, 112, 150), Color3.fromRGB(46, 40, 66))
	gradient.Parent = backdrop
	local view = Instance.new("ViewportFrame")
	view.Name = "View"
	view.Size = UDim2.fromScale(1, 1)
	view.BackgroundTransparency = 1
	-- Bright and even: the outfit's colours must read on any screen.
	view.Ambient = Color3.fromRGB(215, 212, 222)
	view.LightColor = Color3.fromRGB(255, 248, 236)
	view.LightDirection = Vector3.new(-0.35, -1, 0.6)
	view.Active = true
	view.Parent = backdrop
	local cam = Instance.new("Camera")
	cam.FieldOfView = FOV
	cam.Parent = view
	view.CurrentCamera = cam
	local model = Instance.new("WorldModel")
	model.Parent = view
	view.InputBegan:Connect(function(input)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			dragging = input
			dragX = input.Position.X
		end
	end)
	view:GetPropertyChangedSignal("AbsoluteSize"):Connect(frameCamera)
	frame, viewport, camera, world = backdrop, view, cam, model
	return backdrop
end

--[[
	Shows the preview filling `parent` (a Frame sized for it). Calling it
	again on each re-render keeps the same copy.
]]
function CharacterPreview.show(parent: GuiObject)
	local view = frame or make()
	view.Size = UDim2.fromScale(1, 1)
	view.Parent = parent
	if not shown then
		shown = true
		local player = Players.LocalPlayer
		watch(if player then player.Character else nil)
	end
end

-- Takes the frame out of its parent (before the parent is destroyed on a
-- re-render); the copy and the watch stay for the next `show`.
function CharacterPreview.detach()
	if frame then
		frame.Parent = nil
	end
end

-- Takes the preview off screen and stops watching the character.
function CharacterPreview.hide()
	CharacterPreview.detach()
	if shown then
		shown = false
		dragging = nil
		disconnectAll()
	end
end

return CharacterPreview
