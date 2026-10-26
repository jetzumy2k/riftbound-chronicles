--!strict
--[[
	CrownBuilder — what floats above or grows from the head (PLAN.md D-100).

	Halo: a glowing gold ring of 16 segments tilted back over the hair,
	with four diamond studs pointing out and a soft gold light. Welded to
	the rig head, so it follows the head; it does not spin (no per-frame
	script on every character).

	Horns: a pair of curved horns from the top of the head, each a chain of
	tapering ellipsoids sweeping up, back and up again, darkening to a
	glowing tip.
]]

local HeadBuilder = require(script.Parent.HeadBuilder)
local Kit = require(script.Parent.Kit)

local CrownBuilder = {}

local function halo(ctx: Kit.Ctx, frame: HeadBuilder.HeadFrame)
	local w = frame.size.X
	local center = frame.center * CFrame.new(0, w * 0.86, w * 0.12) * CFrame.Angles(math.rad(-14), 0, 0)
	local radius = w * 0.4
	local segments = Kit.ring(ctx, frame.anchor, "glow", center, radius, 0.13, 0.08, 16)
	for i = 0, 3 do
		local turn = CFrame.Angles(0, i * math.pi / 2 + math.pi / 4, 0)
		Kit.ellipsoid(
			ctx,
			frame.anchor,
			"glow",
			Vector3.new(0.13, 0.13, 0.32),
			center * turn * CFrame.new(0, 0, -(radius + 0.18))
		)
	end
	local light = Instance.new("PointLight")
	light.Color = Kit.color(ctx, "glow")
	light.Brightness = 0.6
	light.Range = 6
	light.Shadows = false
	light.Parent = segments[1]
end

-- The horn's path from its root (skull space, right side; fractions of
-- the head width).
local HORN_PATH = {
	Vector3.new(0, 0, 0),
	Vector3.new(0.08, 0.2, 0.02),
	Vector3.new(0.14, 0.38, 0.14),
	Vector3.new(0.16, 0.5, 0.32),
	Vector3.new(0.14, 0.66, 0.44),
}

local function horns(ctx: Kit.Ctx, frame: HeadBuilder.HeadFrame)
	local w = frame.size.X
	for _, sign in Kit.SIDES do
		local root = HeadBuilder.surface(frame, sign * 38, 52, 0.95)
		local out = HeadBuilder.normal(frame, root)
		for i = 1, #HORN_PATH - 1 do
			local a = root + Vector3.new(HORN_PATH[i].X * sign, HORN_PATH[i].Y, HORN_PATH[i].Z) * w
			local b = root
				+ Vector3.new(HORN_PATH[i + 1].X * sign, HORN_PATH[i + 1].Y, HORN_PATH[i + 1].Z) * w
			local thick = w * (0.17 - i * 0.03)
			Kit.span(
				ctx,
				frame.anchor,
				if i == #HORN_PATH - 1 then "glow" else "horn",
				frame.center * (a - (b - a).Unit * thick * 0.3),
				frame.center * b,
				thick,
				thick,
				out
			)
		end
	end
end

function CrownBuilder.build(ctx: Kit.Ctx, frame: HeadBuilder.HeadFrame)
	if ctx.archetype.crown == "Halo" then
		halo(ctx, frame)
	elseif ctx.archetype.crown == "Horns" then
		horns(ctx, frame)
	end
end

return CrownBuilder
