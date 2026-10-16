--!strict
--[[
	TelegraphVfx — ground warnings for telegraphed attacks (boss abilities).

	Each shape is drawn flat on the ground in warning red with a bright edge,
	and a fill that grows from the centre (or from the boss for cones) as the
	hit approaches, so the timing is readable without relying on colour
	alone. Ring attacks show a calm inner circle: stand there to be safe.
	Display only; the server tests positions when the attack lands.
]]

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local TelegraphVfx = {}

local WARN = Color3.fromRGB(255, 70, 52)
local EDGE = Color3.fromRGB(255, 196, 120)
local SAFE = Color3.fromRGB(120, 220, 255)

local function folder(): Folder
	local existing = Workspace:FindFirstChild("RC_ClientVfx")
	if existing and existing:IsA("Folder") then
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = "RC_ClientVfx"
	created.Parent = Workspace
	return created
end

local function flat(
	size: Vector3,
	cf: CFrame,
	color: Color3,
	transparency: number,
	shape: Enum.PartType?
): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Transparency = transparency
	if shape then
		part.Shape = shape
	end
	part.Size = size
	part.CFrame = cf
	part.Parent = folder()
	return part
end

local function disc(center: Vector3, radius: number, lift: number, color: Color3, transparency: number): Part
	return flat(
		Vector3.new(0.08, radius * 2, radius * 2),
		CFrame.new(center + Vector3.new(0, lift, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		color,
		transparency,
		Enum.PartType.Cylinder
	)
end

local function ring(
	center: Vector3,
	radius: number,
	width: number,
	lift: number,
	color: Color3,
	transparency: number,
	segments: number
): { Part }
	local parts = {}
	local chord = 2 * radius * math.sin(math.pi / segments) + 0.05
	for i = 0, segments - 1 do
		local a = (i + 0.5) / segments * math.pi * 2
		table.insert(
			parts,
			flat(
				Vector3.new(chord, 0.08, width),
				CFrame.new(center + Vector3.new(0, lift, 0))
					* CFrame.Angles(0, -a, 0)
					* CFrame.new(0, 0, -radius),
				color,
				transparency
			)
		)
	end
	return parts
end

local function finish(parts: { Part }, duration: number)
	for _, part in parts do
		Debris:AddItem(part, duration + 0.25)
		task.delay(duration, function()
			if part.Parent then
				TweenService:Create(part, TweenInfo.new(0.2), { Transparency = 1 }):Play()
			end
		end)
	end
end

export type Payload = {
	shape: string,
	center: Vector3,
	radius: number,
	inner: number?,
	angle: number?,
	facing: Vector3?,
	duration: number,
}

function TelegraphVfx.show(payload: Payload)
	local center, radius, duration = payload.center, payload.radius, math.max(0.1, payload.duration)
	local parts: { Part } = {}
	local grow = TweenInfo.new(duration, Enum.EasingStyle.Linear)

	if payload.shape == "Circle" then
		table.insert(parts, disc(center, radius, 0.06, WARN, 0.72))
		for _, p in ring(center, radius, 0.5, 0.1, EDGE, 0.15, 36) do
			table.insert(parts, p)
		end
		local fill = disc(center, 0.2, 0.08, WARN, 0.4)
		TweenService:Create(fill, grow, { Size = Vector3.new(0.08, radius * 2, radius * 2) }):Play()
		table.insert(parts, fill)
	elseif payload.shape == "Ring" then
		local inner = payload.inner or 0
		local mid = (inner + radius) / 2
		local width = radius - inner
		for _, p in ring(center, mid, width, 0.06, WARN, 0.72, 48) do
			table.insert(parts, p)
		end
		for _, p in ring(center, radius, 0.5, 0.1, EDGE, 0.15, 48) do
			table.insert(parts, p)
		end
		for _, p in ring(center, inner, 0.5, 0.1, SAFE, 0.1, 32) do
			table.insert(parts, p)
		end
		table.insert(parts, disc(center, inner, 0.05, SAFE, 0.8))
		-- Fill: a band sweeping outward from the safe edge.
		local fills = ring(center, inner + 0.5, 1.2, 0.09, WARN, 0.35, 48)
		for i, p in fills do
			local a = (i - 0.5) / #fills * math.pi * 2
			TweenService:Create(p, grow, {
				CFrame = CFrame.new(center + Vector3.new(0, 0.09, 0))
					* CFrame.Angles(0, -a, 0)
					* CFrame.new(0, 0, -(radius - 0.6)),
			}):Play()
			table.insert(parts, p)
		end
	elseif payload.shape == "Cone" then
		local facing = payload.facing or Vector3.new(0, 0, -1)
		local base = math.atan2(-facing.X, -facing.Z)
		local angle = math.rad(payload.angle or 90)
		local slices = 14
		for i = 0, slices - 1 do
			local a = base - angle / 2 + (i + 0.5) / slices * angle
			local width = 2 * radius * math.sin(angle / slices / 2) + 0.1
			local slice = flat(
				Vector3.new(0.1, 0.08, radius),
				CFrame.new(center + Vector3.new(0, 0.06, 0))
					* CFrame.Angles(0, a, 0)
					* CFrame.new(0, 0, -radius / 2),
				WARN,
				0.7
			)
			-- Wedge-shaped slice: thin at the boss, wide at the edge.
			slice.Size = Vector3.new(width, 0.08, radius)
			table.insert(parts, slice)
			local fill = flat(
				Vector3.new(width, 0.08, 0.2),
				CFrame.new(center + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -0.1),
				WARN,
				0.35
			)
			TweenService:Create(fill, grow, {
				Size = Vector3.new(width, 0.08, radius),
				CFrame = CFrame.new(center + Vector3.new(0, 0.08, 0))
					* CFrame.Angles(0, a, 0)
					* CFrame.new(0, 0, -radius / 2),
			}):Play()
			table.insert(parts, fill)
			table.insert(
				parts,
				flat(
					Vector3.new(width, 0.1, 0.5),
					CFrame.new(center + Vector3.new(0, 0.1, 0))
						* CFrame.Angles(0, a, 0)
						* CFrame.new(0, 0, -radius),
					EDGE,
					0.15
				)
			)
		end
	end
	finish(parts, duration)
end

return TelegraphVfx
