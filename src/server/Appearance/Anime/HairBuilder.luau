--!strict
--[[
	HairBuilder — layered anime hair from ellipsoid clumps (PLAN.md D-100).

	A cap covers the crown and the back of the skull down to a hairline
	above the brows; a back volume fills the nape. On top, each clump is a
	flat ellipsoid root with a narrower tip (two tones), laid along the
	skull at a yaw / pitch (HeadBuilder.surface) and grown in a direction
	(skull space: +X right, +Y up, -Z the face). Sizes are fractions of the
	head width, so the hair fits any head size.

	Styles:
	  HeroSpikes  swept-back spikes, face-framing bangs (Angel warrior)
	  WildSpikes  messy spikes standing up and out (Devil warrior, mage)
	  SoftFluff   soft rounded clumps and a lifted strand (healer, mage)
	  Tousled     bangs swept to one side, loose drooping spikes
	  LongFlow    parted bangs, long side locks and hair down the back
	              (every Woman head style)
]]

local HeadBuilder = require(script.Parent.HeadBuilder)
local Kit = require(script.Parent.Kit)

type Clump = {
	yaw: number,
	pitch: number,
	dir: Vector3,
	len: number,
	width: number,
	mirror: boolean, -- also on the other side (yaw and dir.X flipped)
}

local function c(
	yaw: number,
	pitch: number,
	dx: number,
	dy: number,
	dz: number,
	len: number,
	width: number,
	mirror: boolean?
): Clump
	return {
		yaw = yaw,
		pitch = pitch,
		dir = Vector3.new(dx, dy, dz),
		len = len,
		width = width,
		mirror = mirror == true,
	}
end

local M = true

local STYLES: { [string]: { Clump } } = {
	HeroSpikes = {
		c(0, 54, 0.05, -1, -0.45, 0.32, 0.22),
		c(22, 52, 0.3, -1, -0.4, 0.3, 0.22, M),
		c(46, 46, 0.5, -1, -0.25, 0.4, 0.22, M),
		c(78, 15, 0.12, -1, -0.15, 0.58, 0.2, M),
		c(0, 80, 0.25, 1, 0.45, 0.34, 0.17),
		c(35, 70, 0.55, 0.55, 0.6, 0.55, 0.3, M),
		c(100, 45, 0.85, 0.25, 0.45, 0.5, 0.28, M),
		c(180, 55, 0, 0.45, 1, 0.6, 0.32),
		c(150, 25, 0.45, -0.15, 1, 0.55, 0.3, M),
		c(125, 0, 0.6, -0.6, 0.8, 0.45, 0.28, M),
		c(180, 0, 0, -0.5, 1, 0.5, 0.3),
	},
	WildSpikes = {
		c(0, 54, -0.2, -1, -0.5, 0.36, 0.22),
		c(20, 50, 0.45, -1, -0.4, 0.36, 0.22, M),
		c(45, 44, 0.7, -1, -0.2, 0.4, 0.22, M),
		c(80, 15, 0.3, -1, -0.1, 0.5, 0.2, M),
		c(0, 78, 0.1, 1, 0.2, 0.5, 0.26),
		c(40, 65, 0.7, 0.8, 0.2, 0.55, 0.28, M),
		c(100, 40, 1, 0.4, 0.2, 0.5, 0.28, M),
		c(150, 45, 0.5, 0.6, 0.8, 0.55, 0.3, M),
		c(180, 60, 0, 0.7, 0.8, 0.55, 0.3),
		c(180, 10, 0, -0.3, 1, 0.5, 0.3),
		c(140, 5, 0.6, -0.5, 0.7, 0.45, 0.28, M),
	},
	SoftFluff = {
		c(0, 55, 0, -1, -0.5, 0.3, 0.3),
		c(22, 52, 0.2, -1, -0.45, 0.3, 0.3, M),
		c(48, 44, 0.4, -1, -0.3, 0.36, 0.3, M),
		c(80, 15, 0.15, -1, -0.1, 0.45, 0.28, M),
		c(110, 35, 0.7, -0.4, 0.5, 0.38, 0.36, M),
		c(150, 30, 0.4, -0.5, 0.8, 0.4, 0.38, M),
		c(180, 40, 0, -0.4, 1, 0.4, 0.4),
		c(60, 70, 0.6, 0.3, 0.6, 0.35, 0.36, M),
		c(0, 85, 0.2, 0.6, 0.8, 0.3, 0.2),
	},
	Tousled = {
		c(0, 54, 0.5, -1, -0.4, 0.34, 0.23),
		c(-24, 50, 0.6, -1, -0.4, 0.34, 0.22),
		c(24, 50, 0.6, -1, -0.3, 0.34, 0.22),
		c(48, 44, 0.5, -1, -0.2, 0.4, 0.22, M),
		c(80, 15, 0.15, -1, -0.1, 0.5, 0.21, M),
		c(30, 70, 0.6, 0.2, 0.7, 0.5, 0.3, M),
		c(100, 40, 0.8, -0.2, 0.5, 0.45, 0.28, M),
		c(150, 30, 0.4, -0.4, 0.9, 0.5, 0.3, M),
		c(180, 50, 0, 0, 1, 0.5, 0.32),
		c(180, 5, 0, -0.6, 0.8, 0.45, 0.3),
	},
	LongFlow = {
		c(0, 56, 0.35, -1, -0.4, 0.34, 0.22),
		c(14, 54, 0.4, -1, -0.4, 0.32, 0.22, M),
		c(40, 46, 0.45, -1, -0.25, 0.5, 0.22, M),
		c(80, 15, 0.1, -1, -0.25, 1.0, 0.22, M),
		c(95, 5, 0.2, -1, 0.1, 1.05, 0.26, M),
		c(180, 30, 0, -1, 0.3, 1.35, 0.4),
		c(150, 25, 0.25, -1, 0.3, 1.3, 0.38, M),
		c(125, 15, 0.35, -1, 0.2, 1.2, 0.34, M),
		c(180, -10, 0, -1, 0.35, 1.2, 0.42),
		c(0, 85, 0, 0.4, 1, 0.45, 0.4),
		c(60, 65, 0.6, 0.1, 0.8, 0.45, 0.35, M),
	},
}

local HairBuilder = {}

local function clump(ctx: Kit.Ctx, frame: HeadBuilder.HeadFrame, cl: Clump, flip: number)
	local w = frame.size.X
	local root = HeadBuilder.surface(frame, cl.yaw * flip, cl.pitch, 0.98)
	local normal = HeadBuilder.normal(frame, root)
	local d = Vector3.new(cl.dir.X * flip, cl.dir.Y, cl.dir.Z).Unit
	local len, width = cl.len * w, cl.width * w
	local function at(v: Vector3): Vector3
		return frame.center * v
	end
	Kit.span(
		ctx,
		frame.anchor,
		"hair",
		at(root - d * 0.06 * w),
		at(root + d * len * 0.75),
		width,
		width * 0.55,
		normal
	)
	Kit.span(
		ctx,
		frame.anchor,
		"hairTip",
		at(root + d * len * 0.45),
		at(root + d * len),
		width * 0.55,
		width * 0.4,
		normal
	)
end

function HairBuilder.build(ctx: Kit.Ctx, frame: HeadBuilder.HeadFrame)
	local clumps = STYLES[ctx.archetype.hair[ctx.variant] or ""] or STYLES.HeroSpikes
	local w = frame.size.X
	local s = frame.size
	-- Cap over the crown and back, hairline just above the brows.
	Kit.ellipsoid(
		ctx,
		frame.anchor,
		"hair",
		Vector3.new(s.X * 1.07, s.Y * 0.86, s.Z * 1.07),
		frame.center * CFrame.new(0, w * 0.1, w * 0.05)
	)
	-- The nape.
	Kit.ellipsoid(
		ctx,
		frame.anchor,
		"hair",
		Vector3.new(w * 0.98, w * 0.62, w * 0.55),
		frame.center * CFrame.new(0, -w * 0.12, w * 0.24)
	)
	for _, cl in clumps do
		clump(ctx, frame, cl, 1)
		if cl.mirror then
			clump(ctx, frame, cl, -1)
		end
	end
end

return HairBuilder
