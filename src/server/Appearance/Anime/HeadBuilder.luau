--!strict
--[[
	HeadBuilder — the large anime head and its face (PLAN.md D-100).

	The rig's own head is hidden; the visible head is an ellipsoid skull
	with a narrower jaw ellipsoid (soft cheeks, small chin) about as wide
	as the shoulders (chibi proportions, after the creator's reference
	sheet), welded to the rig head so it follows every head move. Its chin
	sits on a short neck just above the torso.

	The face is made of thin parts laid on the skull's surface (they render
	in the bag's 3D preview too, unlike a SurfaceGui): big eyes (white,
	two-tone iris, pupil, two shines, a bold upper lash line with a flick),
	brows, a tiny nose and a small mouth. The eye pieces are named
	(Eye_<side>_<layer>) so the expression controller can drive them later.

	`build` returns the head frame (centre and size) the hair and crown
	builders place themselves on.
]]

local Kit = require(script.Parent.Kit)

export type HeadFrame = {
	anchor: BasePart, -- the rig head
	center: CFrame, -- the skull's centre in the rig head's space
	size: Vector3, -- the skull's width, height, depth
}

local HeadBuilder = {}

-- Head width from the torso width (about the shoulders' width).
HeadBuilder.WIDTH_PER_TORSO = 1.08
HeadBuilder.MIN_WIDTH = 1.5
HeadBuilder.MAX_WIDTH = 2.6

-- A point on the skull: yaw 0 = the face (-Z), 90 = the right side (+X);
-- pitch 90 = the crown. `grow` > 1 lifts it off the surface.
function HeadBuilder.surface(frame: HeadFrame, yaw: number, pitch: number, grow: number?): Vector3
	local k = grow or 1
	local s = frame.size / 2
	local y, p = math.rad(yaw), math.rad(pitch)
	return Vector3.new(s.X * math.cos(p) * math.sin(y), s.Y * math.sin(p), -s.Z * math.cos(p) * math.cos(y))
		* k
end

-- The outward normal of the skull at a local point.
function HeadBuilder.normal(frame: HeadFrame, point: Vector3): Vector3
	local s = frame.size / 2
	return Vector3.new(point.X / (s.X * s.X), point.Y / (s.Y * s.Y), point.Z / (s.Z * s.Z)).Unit
end

-- The face surface (front) at x, y (skull space), and the frame there
-- (-Z out of the face).
local function facePoint(frame: HeadFrame, x: number, y: number, lift: number): CFrame
	local s = frame.size / 2
	local q = 1 - (x / s.X) ^ 2 - (y / s.Y) ^ 2
	local z = -s.Z * math.sqrt(math.max(q, 0.02))
	local p = Vector3.new(x, y, z)
	local n = HeadBuilder.normal(frame, p)
	return CFrame.lookAt(p + n * lift, p + n * (lift + 1))
end

-- Eye and brow styles (fractions of the head width).
type FaceStyle = {
	eyeX: number,
	eyeY: number,
	eyeW: number,
	eyeH: number,
	browTilt: number, -- degrees; positive = inner end down (determined)
	lashes: boolean?, -- a second, longer lash flick (feminine faces)
	mouthW: number,
}
local FACES: { [string]: FaceStyle } = {
	Valiant = { eyeX = 0.215, eyeY = -0.06, eyeW = 0.2, eyeH = 0.25, browTilt = 14, mouthW = 0.09 },
	Gentle = {
		eyeX = 0.215,
		eyeY = -0.07,
		eyeW = 0.22,
		eyeH = 0.28,
		browTilt = -6,
		mouthW = 0.07,
		lashes = true,
	},
	Fierce = { eyeX = 0.21, eyeY = -0.05, eyeW = 0.21, eyeH = 0.21, browTilt = 24, mouthW = 0.1 },
	Sly = {
		eyeX = 0.215,
		eyeY = -0.06,
		eyeW = 0.22,
		eyeH = 0.24,
		browTilt = 10,
		mouthW = 0.07,
		lashes = true,
	},
}

-- Eye layers hidden on far characters (DetailRules class 1).
local FINE_EYE_LAYERS: { [string]: boolean } = {
	IrisLight = true,
	Shine = true,
	Shine2 = true,
	Flick = true,
	Flick2 = true,
}

local function eye(ctx: Kit.Ctx, frame: HeadFrame, style: FaceStyle, side: string, sign: number)
	local head = frame.anchor
	local w = frame.size.X
	local ew, eh = style.eyeW * w, style.eyeH * w
	local base = facePoint(frame, sign * style.eyeX * w, style.eyeY * w, 0)
	local function at(dx: number, dy: number, lift: number): CFrame
		return frame.center * base * CFrame.new(dx, dy, -lift)
	end
	local function named(part: BasePart, layer: string)
		part.Name = `Eye_{side}_{layer}`
		-- D-102: the eye's shape always shows; only its sparkle drops far away.
		part:SetAttribute("RC_Lod", FINE_EYE_LAYERS[layer] and 1 or nil)
	end
	named(Kit.ellipsoid(ctx, head, "eyeWhite", Vector3.new(ew, eh, 0.05), at(0, 0, 0.005)), "White")
	-- Two-tone iris: deep at the top, bright below.
	named(
		Kit.ellipsoid(ctx, head, "irisDeep", Vector3.new(ew * 0.78, eh * 0.86, 0.05), at(0, -eh * 0.03, 0.02)),
		"Iris"
	)
	named(
		Kit.ellipsoid(ctx, head, "iris", Vector3.new(ew * 0.62, eh * 0.5, 0.05), at(0, -eh * 0.18, 0.03)),
		"IrisLight"
	)
	named(
		Kit.ellipsoid(ctx, head, "line", Vector3.new(ew * 0.34, eh * 0.42, 0.05), at(0, eh * 0.02, 0.04)),
		"Pupil"
	)
	-- Shines (white, neon): a big one up and to the outside, a small one low.
	local shine = Kit.ellipsoid(
		ctx,
		head,
		"eyeWhite",
		Vector3.new(ew * 0.26, ew * 0.26, 0.05),
		at(sign * ew * 0.16, eh * 0.18, 0.055)
	)
	shine.Material = Enum.Material.Neon
	named(shine, "Shine")
	local small = Kit.ellipsoid(
		ctx,
		head,
		"eyeWhite",
		Vector3.new(ew * 0.12, ew * 0.12, 0.05),
		at(-sign * ew * 0.14, -eh * 0.24, 0.055)
	)
	small.Material = Enum.Material.Neon
	named(small, "Shine2")
	-- Upper lash line: a bold arc and a flick at the outer corner.
	named(
		Kit.block(
			ctx,
			head,
			"line",
			Vector3.new(ew * 1.08, eh * 0.13, 0.06),
			at(0, eh * 0.47, 0.05) * CFrame.Angles(0, 0, math.rad(sign * -6))
		),
		"Lash"
	)
	named(
		Kit.block(
			ctx,
			head,
			"line",
			Vector3.new(ew * 0.34, eh * 0.1, 0.06),
			at(sign * ew * 0.6, eh * 0.4, 0.05) * CFrame.Angles(0, 0, math.rad(sign * -32))
		),
		"Flick"
	)
	if style.lashes then
		named(
			Kit.block(
				ctx,
				head,
				"line",
				Vector3.new(ew * 0.3, eh * 0.08, 0.06),
				at(sign * ew * 0.62, eh * 0.24, 0.05) * CFrame.Angles(0, 0, math.rad(sign * -12))
			),
			"Flick2"
		)
	end
	-- Brow.
	named(
		Kit.ellipsoid(
			ctx,
			head,
			"hair",
			Vector3.new(ew * 0.95, eh * 0.12, 0.05),
			frame.center
				* facePoint(frame, sign * (style.eyeX + 0.01) * w, style.eyeY * w + eh * 0.82, 0.01)
				* CFrame.Angles(0, 0, math.rad(sign * style.browTilt))
		),
		"Brow"
	)
end

function HeadBuilder.build(ctx: Kit.Ctx, body: Kit.Body): HeadFrame?
	local head = body.head
	local upper = body.upper
	if head == nil or upper == nil then
		return nil
	end
	local w =
		math.clamp(upper.Size.X * HeadBuilder.WIDTH_PER_TORSO, HeadBuilder.MIN_WIDTH, HeadBuilder.MAX_WIDTH)
	local size = Vector3.new(w, w * 0.96, w * 0.94)
	-- The chin (jaw bottom) sits just above the rig head's base.
	local neck = head.Size.Y / 2
	local center = CFrame.new(0, -neck + 0.12 + size.Y * 0.5 + w * 0.02, -w * 0.02)
	local frame: HeadFrame = { anchor = head, center = center, size = size }

	-- Neck, skull, jaw / cheeks.
	Kit.part(
		ctx,
		head,
		"skin",
		"Cylinder",
		Vector3.new(w * 0.24, 0.55, w * 0.24),
		CFrame.new(0, -neck + 0.05, 0.02)
	)
	Kit.ellipsoid(ctx, head, "skin", size, center)
	Kit.ellipsoid(
		ctx,
		head,
		"skin",
		-- Kept just behind the skull's front so the mouth and nose show.
		Vector3.new(w * 0.76, w * 0.58, w * 0.74),
		center * CFrame.new(0, -w * 0.22, 0)
	)
	-- Ears (mostly under the hair).
	for _, sign in Kit.SIDES do
		Kit.ellipsoid(
			ctx,
			head,
			"skin",
			Vector3.new(w * 0.08, w * 0.2, w * 0.14),
			center * CFrame.new(sign * w * 0.49, -w * 0.06, w * 0.02)
		)
	end

	local style = FACES[ctx.archetype.face[ctx.variant] or ""] or FACES.Valiant
	for side, sign in Kit.SIDES do
		eye(ctx, frame, style, side, sign)
	end
	-- Tiny nose and a small mouth.
	Kit.ellipsoid(
		ctx,
		head,
		"skin",
		Vector3.new(w * 0.05, w * 0.06, 0.08),
		center * facePoint(frame, 0, -w * 0.2, 0.01)
	)
	local mouth = Kit.block(
		ctx,
		head,
		"line",
		Vector3.new(style.mouthW * w, w * 0.018, 0.05),
		center * facePoint(frame, 0, -w * 0.3, 0.0)
	)
	mouth.Name = "Mouth"
	mouth:SetAttribute("RC_Lod", nil)
	-- A soft blush under each eye.
	for _, sign in Kit.SIDES do
		local blush = Kit.ellipsoid(
			ctx,
			head,
			"blush",
			Vector3.new(w * 0.13, w * 0.05, 0.04),
			center * facePoint(frame, sign * w * 0.27, -w * 0.21, 0)
		)
		blush.Transparency = 0.45
	end
	return frame
end

return HeadBuilder
