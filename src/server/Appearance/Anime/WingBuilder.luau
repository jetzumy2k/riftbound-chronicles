--!strict
--[[
	WingBuilder — large layered wings on the upper back (PLAN.md D-100).

	Feather: an angel wing in four layers along a curved leading edge
	(shoulder -> wrist -> tip): the wing arm (smooth ellipsoids), short
	marginal coverts, mid coverts, and long primaries that fan from
	hanging down near the back to sweeping out at the tip, each with a
	pale gold tip. Both wings are mirrored exactly and swept back 25°.
	The layers sit on the back face, which the third-person camera sees.
	About 37 parts a wing.

	Bat: a devil wing: arm bones (shoulder -> elbow -> wrist), four finger
	bones fanning from the wrist, a dark membrane between them made of
	flat triangles (two wedges each) with a scalloped trailing edge, a
	glowing edge line along it and a claw at the wrist. About 40 parts a
	wing.
]]

local Kit = require(script.Parent.Kit)

local WingBuilder = {}

-- The leading edge, wing space (+X out from the spine, +Y up, +Z back).
local EDGE = {
	Vector3.new(0, 0, 0),
	Vector3.new(1.2, 1.15, 0.3),
	Vector3.new(2.4, 1.95, 0.6),
	Vector3.new(3.5, 1.7, 0.85),
	Vector3.new(4.4, 1.05, 1.0),
}
local FEATHERS = 9

-- A point along the leading edge, t in 0..1.
local function along(t: number): Vector3
	local segments = #EDGE - 1
	local f = math.clamp(t, 0, 1) * segments
	local i = math.min(math.floor(f), segments - 1)
	return EDGE[i + 1]:Lerp(EDGE[i + 2], f - i)
end

local function feather(t: number): Vector3
	local hang = Vector3.new(-0.15, -1, 0.1)
	local sweep = Vector3.new(0.8, -0.6, 0.15)
	return hang:Lerp(sweep, t ^ 1.2).Unit
end

local function featherWing(ctx: Kit.Ctx, upper: BasePart, sign: number, k: number)
	local s = upper.Size
	local root = CFrame.new(sign * s.X * 0.2, s.Y * 0.22, s.Z * 0.5)
		* CFrame.Angles(0, math.rad(-sign * 25), 0)
	local back = root:VectorToWorldSpace(Vector3.new(0, 0, 1))
	local function point(v: Vector3): Vector3
		return root * (Vector3.new(v.X * sign, v.Y, v.Z) * k)
	end
	local function direction(v: Vector3): Vector3
		return root:VectorToWorldSpace(Vector3.new(v.X * sign, v.Y, v.Z))
	end
	-- Wing arm.
	for i = 1, #EDGE - 1 do
		Kit.span(ctx, upper, "feather", point(EDGE[i]), point(EDGE[i + 1]), 0.62 * k, 0.32 * k, back)
	end
	for i = 0, FEATHERS - 1 do
		local t = i / (FEATHERS - 1)
		local base = point(along(t))
		local d = direction(feather(t))
		local length = (1.5 + 2.3 * t ^ 1.3) * k
		local width = (0.5 + 0.08 * t) * k
		local lift = back * 0.03 * k
		-- Primary with its gold tip.
		Kit.span(ctx, upper, "feather", base, base + d * length, width, 0.1 * k, back)
		Kit.span(
			ctx,
			upper,
			"featherTip",
			base + d * length * 0.72 + lift,
			base + d * length * 0.99 + lift,
			width * 0.62,
			0.1 * k,
			back
		)
		if i < FEATHERS - 1 then
			-- Mid coverts between the primaries, then the short marginals.
			local mid = point(along(t + 0.5 / (FEATHERS - 1)))
			local md = direction(feather(t + 0.06))
			Kit.span(
				ctx,
				upper,
				"feather",
				mid + back * 0.07 * k,
				mid + md * length * 0.6 + back * 0.07 * k,
				width * 1.05,
				0.11 * k,
				back
			)
			if i % 2 == 0 or t > 0.5 then
				Kit.span(
					ctx,
					upper,
					"feather",
					base + back * 0.13 * k,
					base + d * length * 0.32 + back * 0.13 * k,
					width * 1.15,
					0.14 * k,
					back
				)
			end
		end
	end
end

-- Bat wing points, wing space like EDGE.
local BAT_ELBOW = Vector3.new(1.3, 1.0, 0.35)
local BAT_WRIST = Vector3.new(2.4, 1.9, 0.6)
local BAT_FINGERS = {
	Vector3.new(4.3, 1.6, 0.9),
	Vector3.new(4.1, 0.1, 0.95),
	Vector3.new(3.0, -1.0, 0.85),
	Vector3.new(1.7, -1.35, 0.6),
}
local BAT_ROOT_LOW = Vector3.new(0.3, -0.7, 0.2)

local function batWing(ctx: Kit.Ctx, upper: BasePart, sign: number, k: number)
	local s = upper.Size
	local root = CFrame.new(sign * s.X * 0.2, s.Y * 0.22, s.Z * 0.5)
		* CFrame.Angles(0, math.rad(-sign * 25), 0)
	local back = root:VectorToWorldSpace(Vector3.new(0, 0, 1))
	local function point(v: Vector3): Vector3
		return root * (Vector3.new(v.X * sign, v.Y, v.Z) * k)
	end
	local shoulder, elbow, wrist = point(Vector3.zero), point(BAT_ELBOW), point(BAT_WRIST)
	local tips = {}
	for _, f in BAT_FINGERS do
		table.insert(tips, point(f))
	end
	local low = point(BAT_ROOT_LOW)
	-- Bones.
	Kit.span(ctx, upper, "horn", shoulder, elbow, 0.24 * k, 0.2 * k, back)
	Kit.span(ctx, upper, "horn", elbow, wrist, 0.2 * k, 0.18 * k, back)
	for _, tip in tips do
		Kit.span(ctx, upper, "horn", wrist, tip, 0.11 * k, 0.1 * k, back)
	end
	Kit.ellipsoid(
		ctx,
		upper,
		"horn",
		Vector3.new(0.14, 0.42, 0.14) * k,
		Kit.frame(wrist + (wrist - elbow).Unit * 0.2 * k, Vector3.new(0, 1, 0), back)
	)
	-- Membrane panels with scalloped trailing edges and a glowing edge line.
	local thickness = 0.05 * k
	local function panel(a: Vector3, b: Vector3, hub: Vector3)
		local dip = a:Lerp(b, 0.5):Lerp(hub, 0.22)
		Kit.triangle(ctx, upper, "feather", hub, a, dip, thickness)
		Kit.triangle(ctx, upper, "feather", hub, dip, b, thickness)
		local lift = back * 0.04 * k
		Kit.span(ctx, upper, "featherTip", a + lift, dip + lift, 0.06 * k, 0.06 * k, back)
		Kit.span(ctx, upper, "featherTip", dip + lift, b + lift, 0.06 * k, 0.06 * k, back)
	end
	for i = 1, #tips - 1 do
		panel(tips[i], tips[i + 1], wrist)
	end
	panel(tips[#tips], elbow, wrist)
	panel(elbow, low, shoulder)
	-- The leading edge between shoulder, elbow and wrist.
	Kit.triangle(ctx, upper, "feather", shoulder, elbow, low, thickness)
end

function WingBuilder.build(ctx: Kit.Ctx, body: Kit.Body)
	local upper = body.upper
	if upper == nil or ctx.archetype.wings == nil then
		return
	end
	local k = ctx.archetype.wingScale * math.clamp(upper.Size.X / 1.8, 0.7, 1.4)
	if ctx.archetype.wings == "Feather" then
		for _, sign in Kit.SIDES do
			featherWing(ctx, upper, sign, k)
		end
	elseif ctx.archetype.wings == "Bat" then
		for _, sign in Kit.SIDES do
			batWing(ctx, upper, sign, k)
		end
	end
end

return WingBuilder
