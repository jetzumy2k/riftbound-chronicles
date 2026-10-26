--!strict
--[[
	ArmorBuilder — layered anime armour sets (PLAN.md D-100).

	Sizes come from each rig part (so the set fits any body), and the
	visible limbs are slimmer than the rig's block limbs (anime
	proportions; the rig itself is hidden). Each body part gets a dark
	under-suit layer, then the plates over it.

	Sets (colours from the archetype palette, so each realm differs):
	  Plate   knight plate (warriors): breastplate with a V trim, collar
	          and a glowing chest gem between two feathers (Devils: horn
	          spikes); banded waist and belt; six tassets with hems and a
	          tabard; layered pauldrons with feather fins (Devils: long
	          horn spikes); vambraces, gauntlets; cuisses, knee guards,
	          tall greaves and plated boots.
	  Robe    healer robe: capelet with a trim rim, a front panel, sash,
	          a long flared skirt of ten panels (front panels in the
	          accent colour), bell sleeves with cuffs.
	  Coat    mage coat: high collar, open front over a light shirt with
	          trim strips, epaulettes, belt, coat tails to the knee open at
	          the front, flared sleeves, trousers and trimmed boots.
	  Ranger  archer leathers: shirt and vest, chest strap, a quiver with
	          arrows, a hooded half cloak, one pauldron, belt pouches,
	          bracers, gloves and tall boots.
	  Tunic   recruit tunic: belted tunic with four flaps, sleeves,
	          trousers and boots.
]]

local Kit = require(script.Parent.Kit)

local ArmorBuilder = {}

local V = Vector3.new
local C = CFrame.new
local A = CFrame.Angles
local rad = math.rad

local function devil(ctx: Kit.Ctx): boolean
	return ctx.archetype.race == "Devil"
end

local function chest(ctx: Kit.Ctx, upper: BasePart)
	local s = upper.Size
	local x, y, z = s.X, s.Y, s.Z
	Kit.ellipsoid(ctx, upper, "suit", V(x * 0.8, y * 1.08, z * 0.92), C(0, -y * 0.02, 0))
	-- Breastplate: a rounded shell and a forward chest plate.
	Kit.ellipsoid(ctx, upper, "plate", V(x * 0.88, y * 0.9, z * 1.04), C(0, y * 0.06, 0))
	Kit.ellipsoid(ctx, upper, "plate", V(x * 0.74, y * 0.56, z * 0.5), C(0, y * 0.14, -z * 0.3))
	-- Lower rib plate, shaded.
	Kit.ellipsoid(ctx, upper, "plateShade", V(x * 0.7, y * 0.36, z * 0.9), C(0, -y * 0.3, -z * 0.04))
	-- V trim from the shoulders to the gem.
	for _, sign in Kit.SIDES do
		Kit.block(
			ctx,
			upper,
			"trim",
			V(0.09, y * 0.52, 0.08),
			C(sign * x * 0.15, y * 0.2, -z * 0.56) * A(rad(8), 0, rad(sign * -30))
		)
	end
	-- Collar.
	Kit.ring(ctx, upper, "trim", C(0, y * 0.48, 0), x * 0.2, 0.1, 0.16, 10)
	-- Chest gem between two gold feathers.
	Kit.gem(ctx, upper, 0.26, C(0, y * 0.06, -z * 0.6))
	for _, sign in Kit.SIDES do
		Kit.ellipsoid(
			ctx,
			upper,
			if devil(ctx) then "horn" else "trim",
			if devil(ctx) then V(0.1, 0.56, 0.08) else V(0.12, 0.5, 0.06),
			C(sign * 0.26, y * 0.1, -z * 0.56) * A(0, 0, rad(sign * (if devil(ctx) then -40 else -62)))
		)
	end
	-- Back plate ridge (under the wings).
	Kit.block(ctx, upper, "trim", V(0.12, y * 0.6, 0.08), C(0, y * 0.05, z * 0.53))
end

local function waist(ctx: Kit.Ctx, lower: BasePart)
	local s = lower.Size
	local x, y, z = s.X, s.Y, s.Z
	Kit.ellipsoid(ctx, lower, "plate", V(x * 0.8, y * 1.8, z * 0.98), C(0, y * 0.35, 0))
	-- Belt and buckle.
	Kit.block(ctx, lower, "trim", V(x * 0.86, y * 0.5, z * 1.02), C(0, -y * 0.05, 0))
	Kit.gem(ctx, lower, 0.2, C(0, -y * 0.05, -z * 0.55))
	-- Tassets: front pair, sides, back pair, flaring out from the belt.
	local drop = y * 0.3 + 0.36
	local plates: { { number } } = {
		-- x, z, X turn (deg), Z turn (deg), width: each hem flares outward
		{ -0.2, -0.5, 12, -4, 0.34 },
		{ 0.2, -0.5, 12, 4, 0.34 },
		{ -0.5, 0, 0, -16, 0.3 },
		{ 0.5, 0, 0, 16, 0.3 },
		{ -0.2, 0.5, -12, -4, 0.34 },
		{ 0.2, 0.5, -12, 4, 0.34 },
	}
	for _, p in plates do
		local frame = C(p[1] * x, -drop, p[2] * z * 1.05) * A(rad(p[3]), 0, rad(p[4]))
		local width = p[5] * x
		if p[2] == 0 then
			-- Side plates face sideways.
			frame = frame * A(0, rad(90), 0)
			width = z * 0.7
		end
		Kit.block(ctx, lower, "plate", V(width, 0.72, 0.07), frame)
		Kit.block(ctx, lower, "trim", V(width * 1.04, 0.09, 0.09), frame * C(0, -0.34, 0))
	end
	-- Tabard between the front tassets.
	local tabard = C(0, -drop - 0.12, -z * 0.58) * A(rad(-8), 0, 0)
	Kit.block(ctx, lower, "cloth", V(x * 0.26, 0.98, 0.05), tabard)
	Kit.block(ctx, lower, "trim", V(x * 0.27, 0.08, 0.07), tabard * C(0, -0.47, 0))
	Kit.ellipsoid(ctx, lower, "trim", V(0.18, 0.18, 0.06), tabard * C(0, -0.1, -0.03))
end

local function shoulder(ctx: Kit.Ctx, arm: BasePart, sign: number)
	local s = arm.Size
	local x, y, z = s.X, s.Y, s.Z
	-- Under-sleeve.
	Kit.ellipsoid(ctx, arm, "suit", V(x * 0.66, y * 1.0, z * 0.66), C(0, -y * 0.05, 0))
	local tilt = A(0, 0, rad(-sign * 14))
	-- Dome, gold rim, second lame and its rim.
	Kit.ellipsoid(ctx, arm, "plate", V(x * 1.5, y * 0.66, z * 1.42), C(sign * x * 0.12, y * 0.4, 0) * tilt)
	Kit.ellipsoid(ctx, arm, "trim", V(x * 1.56, y * 0.16, z * 1.48), C(sign * x * 0.15, y * 0.2, 0) * tilt)
	Kit.ellipsoid(
		ctx,
		arm,
		"plateShade",
		V(x * 1.3, y * 0.42, z * 1.28),
		C(sign * x * 0.17, y * 0.08, 0) * tilt
	)
	Kit.ellipsoid(ctx, arm, "trim", V(x * 1.34, y * 0.1, z * 1.32), C(sign * x * 0.19, -y * 0.08, 0) * tilt)
	-- Feather fins at the top outer edge (Devils: long horn spikes).
	local spiky = devil(ctx)
	local finRole = if spiky then "horn" else "trim"
	local finK = if spiky then 1.45 else 1
	Kit.ellipsoid(
		ctx,
		arm,
		finRole,
		V(0.14, 0.72 * finK, if spiky then 0.14 else 0.07),
		C(sign * x * 0.62, y * (0.7 + (finK - 1) * 0.5), 0) * A(0, 0, rad(-sign * 38))
	)
	Kit.ellipsoid(
		ctx,
		arm,
		finRole,
		V(0.11, 0.5 * finK, if spiky then 0.11 else 0.06),
		C(sign * x * 0.74, y * 0.52, z * 0.12) * A(0, 0, rad(-sign * 58))
	)
	Kit.gem(ctx, arm, 0.16, C(sign * x * 0.3, y * 0.45, -z * 0.66) * A(rad(-20), 0, 0))
end

local function forearm(ctx: Kit.Ctx, arm: BasePart)
	local s = arm.Size
	local x, y = s.X, s.Y
	Kit.part(ctx, arm, "plate", "Cylinder", V(x * 0.74, y * 0.84, x * 0.74), C(0, -y * 0.06, 0))
	Kit.part(ctx, arm, "trim", "Cylinder", V(x * 0.8, 0.1, x * 0.8), C(0, y * 0.34, 0))
	Kit.part(ctx, arm, "trim", "Cylinder", V(x * 0.84, 0.12, x * 0.84), C(0, -y * 0.44, 0))
	-- Elbow cop.
	Kit.ellipsoid(ctx, arm, "trim", V(x * 0.5, x * 0.42, x * 0.4), C(0, y * 0.46, x * 0.3))
end

local function gauntlet(ctx: Kit.Ctx, hand: BasePart)
	local s = hand.Size
	Kit.ellipsoid(
		ctx,
		hand,
		"plate",
		V(s.X * 0.74, math.max(s.Y * 2.1, 0.55), s.Z * 0.8),
		C(0, -s.Y * 0.55, 0)
	)
	Kit.block(ctx, hand, "trim", V(s.X * 0.62, 0.1, 0.12), C(0, -s.Y * 0.9, -s.Z * 0.36))
end

local function thigh(ctx: Kit.Ctx, leg: BasePart)
	local s = leg.Size
	local x, y, z = s.X, s.Y, s.Z
	Kit.ellipsoid(ctx, leg, "suit", V(x * 0.76, y * 1.06, z * 0.76), C(0, 0, 0))
	Kit.ellipsoid(ctx, leg, "plate", V(x * 0.78, y * 0.78, z * 0.52), C(0, -y * 0.04, -z * 0.2))
	Kit.block(ctx, leg, "trim", V(x * 0.09, y * 0.6, 0.06), C(0, -y * 0.04, -z * 0.46))
end

local function shin(ctx: Kit.Ctx, leg: BasePart)
	local s = leg.Size
	local x, y, z = s.X, s.Y, s.Z
	Kit.ellipsoid(ctx, leg, "plate", V(x * 0.84, y * 1.06, z * 0.88), C(0, -y * 0.03, 0))
	Kit.part(ctx, leg, "trim", "Cylinder", V(x * 0.86, 0.1, z * 0.86), C(0, y * 0.36, 0))
	Kit.block(ctx, leg, "trim", V(0.09, y * 0.66, 0.07), C(0, -y * 0.05, -z * 0.43))
	-- Knee guard with a small fin.
	Kit.ellipsoid(ctx, leg, "trim", V(x * 0.52, x * 0.46, x * 0.36), C(0, y * 0.47, -z * 0.36))
	Kit.ellipsoid(
		ctx,
		leg,
		"plate",
		V(x * 0.14, x * 0.4, x * 0.1),
		C(0, y * 0.62, -z * 0.5) * A(rad(-20), 0, 0)
	)
end

local function boot(ctx: Kit.Ctx, foot: BasePart, role: string?)
	local s = foot.Size
	local x, y, z = s.X, s.Y, s.Z
	Kit.ellipsoid(
		ctx,
		foot,
		role or "plate",
		V(x * 0.8, math.max(y * 1.9, 0.5), z * 1.25),
		C(0, y * 0.1, -z * 0.14)
	)
	Kit.ellipsoid(
		ctx,
		foot,
		"trim",
		V(x * 0.56, math.max(y * 1.1, 0.3), z * 0.36),
		C(0, -y * 0.05, -z * 0.62)
	)
	Kit.block(ctx, foot, "plateShade", V(x * 0.82, 0.08, z * 1.12), C(0, -y * 0.46, -z * 0.12))
end

--------------------------------------------------------------------------------
-- Cloth sets
--------------------------------------------------------------------------------

-- A slim shell over a limb part.
local function shell(ctx: Kit.Ctx, part: BasePart?, role: string, k: number)
	if part == nil then
		return
	end
	local s = part.Size
	Kit.ellipsoid(ctx, part, role, V(s.X * k, s.Y * 1.06, s.Z * k), C(0, 0, 0))
end

-- A bare or gloved hand.
local function hand(ctx: Kit.Ctx, part: BasePart?, role: string)
	if part == nil then
		return
	end
	local s = part.Size
	Kit.ellipsoid(ctx, part, role, V(s.X * 0.62, math.max(s.Y * 1.9, 0.5), s.Z * 0.68), C(0, -s.Y * 0.5, 0))
end

-- A cuff ring round a limb part at `y` (fraction of its height).
local function cuff(ctx: Kit.Ctx, part: BasePart?, role: string, diameter: number, y: number)
	if part == nil then
		return
	end
	local s = part.Size
	Kit.part(ctx, part, role, "Cylinder", V(s.X * diameter, 0.1, s.X * diameter), C(0, s.Y * y, 0))
end

-- How far the legs reach below the lower torso (for skirts and tails).
local function legLength(body: Kit.Body): number
	local leg = body.legs.Right
	local total = 0
	for _, part in { leg.upper, leg.lower } do
		if part then
			total += part.Size.Y
		end
	end
	return if total > 0 then total else 2.2
end

--[[
	A ring of hanging panels from the lower torso: `count` panels round
	`fromDeg..toDeg` (0 = the front), `length` long, flaring from radius r0
	to r1; `accent(angle)` picks each panel's colour role.
]]
local function skirt(
	ctx: Kit.Ctx,
	lower: BasePart,
	count: number,
	fromDeg: number,
	toDeg: number,
	length: number,
	r0: number,
	r1: number,
	accent: (number) -> string
)
	local top = -lower.Size.Y * 0.3
	local tilt = math.atan2(r1 - r0, length)
	local full = toDeg - fromDeg >= 359
	local steps = if full then count else count - 1
	local width = (rad(toDeg - fromDeg) / count) * (r0 + r1) / 2 * 1.25
	for i = 0, count - 1 do
		local deg = fromDeg + (toDeg - fromDeg) * i / math.max(steps, 1)
		local frame = A(0, rad(deg), 0) * C(0, top - length / 2, -(r0 + r1) / 2) * A(tilt, 0, 0)
		Kit.block(ctx, lower, accent(deg), V(width, length, 0.07), frame)
		Kit.block(ctx, lower, "trim", V(width * 1.02, 0.1, 0.09), frame * C(0, -length / 2 + 0.05, 0))
	end
end

local function robe(ctx: Kit.Ctx, body: Kit.Body)
	local upper, lower = body.upper, body.lower
	if upper then
		local s = upper.Size
		local x, y, z = s.X, s.Y, s.Z
		Kit.ellipsoid(ctx, upper, "plate", V(x * 0.84, y * 1.06, z * 0.95), C(0, -y * 0.02, 0))
		-- Capelet with a trim rim.
		Kit.ellipsoid(ctx, upper, "plateShade", V(x * 1.12, y * 0.46, z * 1.16), C(0, y * 0.36, 0))
		Kit.ellipsoid(ctx, upper, "trim", V(x * 1.14, y * 0.08, z * 1.18), C(0, y * 0.17, 0))
		-- Front panel and gem.
		Kit.block(ctx, upper, "cloth", V(x * 0.22, y * 0.75, 0.06), C(0, -y * 0.12, -z * 0.5))
		for _, sign in Kit.SIDES do
			Kit.block(ctx, upper, "trim", V(0.06, y * 0.75, 0.08), C(sign * x * 0.12, -y * 0.12, -z * 0.5))
		end
		Kit.gem(ctx, upper, 0.24, C(0, y * 0.2, -z * 0.62))
		Kit.ring(ctx, upper, "trim", C(0, y * 0.5, 0), x * 0.19, 0.08, 0.12, 8)
	end
	if lower then
		local s = lower.Size
		Kit.block(ctx, lower, "cloth", V(s.X * 0.86, s.Y * 0.7, s.Z * 1.02), C(0, 0, 0))
		Kit.gem(ctx, lower, 0.18, C(0, 0, -s.Z * 0.55))
		skirt(ctx, lower, 10, 0, 360, legLength(body) * 0.95, s.X * 0.42, s.X * 0.66, function(deg)
			return if deg < 20 or deg > 340 then "cloth" else "plate"
		end)
	end
	for side in Kit.SIDES do
		local arm, leg = body.arms[side], body.legs[side]
		shell(ctx, arm.upper, "plate", 0.72)
		if arm.lower then
			-- Bell sleeve, wider at the wrist.
			local s = arm.lower.Size
			Kit.ellipsoid(
				ctx,
				arm.lower,
				"plate",
				V(s.X * 1.05, s.Y * 1.05, s.Z * 1.05),
				C(0, -s.Y * 0.15, 0)
			)
			cuff(ctx, arm.lower, "trim", 1.0, -0.55)
		end
		hand(ctx, arm.hand, "skin")
		shell(ctx, leg.upper, "suit", 0.7)
		shell(ctx, leg.lower, "plateShade", 0.74)
		if leg.foot then
			boot(ctx, leg.foot, "plateShade")
		end
	end
end

local function coat(ctx: Kit.Ctx, body: Kit.Body)
	local upper, lower = body.upper, body.lower
	if upper then
		local s = upper.Size
		local x, y, z = s.X, s.Y, s.Z
		Kit.ellipsoid(ctx, upper, "plate", V(x * 0.86, y * 1.06, z * 0.98), C(0, -y * 0.02, 0))
		-- Light shirt in the open front, trim strips either side.
		Kit.block(ctx, upper, "cloth", V(x * 0.24, y * 0.9, 0.06), C(0, -y * 0.02, -z * 0.5))
		for _, sign in Kit.SIDES do
			Kit.block(ctx, upper, "trim", V(0.07, y * 0.95, 0.08), C(sign * x * 0.15, -y * 0.02, -z * 0.5))
			-- High collar wings.
			local collar = C(sign * x * 0.2, y * 0.62, z * 0.05)
				* A(rad(-10), rad(sign * 30), rad(sign * -10))
			Kit.block(ctx, upper, "plate", V(x * 0.3, y * 0.42, 0.08), collar)
			Kit.block(ctx, upper, "trim", V(x * 0.3, 0.06, 0.1), collar * C(0, y * 0.21, 0))
		end
		local back = C(0, y * 0.62, z * 0.32) * A(rad(-14), 0, 0)
		Kit.block(ctx, upper, "plate", V(x * 0.5, y * 0.45, 0.08), back)
		Kit.block(ctx, upper, "trim", V(x * 0.5, 0.06, 0.1), back * C(0, y * 0.22, 0))
		Kit.gem(ctx, upper, 0.2, C(0, y * 0.36, -z * 0.58))
	end
	if lower then
		local s = lower.Size
		Kit.block(ctx, lower, "trim", V(s.X * 0.88, s.Y * 0.55, s.Z * 1.03), C(0, 0, 0))
		Kit.gem(ctx, lower, 0.16, C(0, 0, -s.Z * 0.56))
		skirt(ctx, lower, 7, 40, 320, legLength(body) * 0.62, s.X * 0.46, s.X * 0.6, function()
			return "plate"
		end)
	end
	for side, sign in Kit.SIDES do
		local arm, leg = body.arms[side], body.legs[side]
		if arm.upper then
			shell(ctx, arm.upper, "plate", 0.72)
			local s = arm.upper.Size
			-- Epaulette with a trim rim.
			local at = C(sign * s.X * 0.1, s.Y * 0.38, 0)
			Kit.ellipsoid(ctx, arm.upper, "plateShade", V(s.X * 1.1, s.Y * 0.36, s.Z * 1.1), at)
			Kit.ellipsoid(
				ctx,
				arm.upper,
				"trim",
				V(s.X * 1.14, s.Y * 0.08, s.Z * 1.14),
				at * C(0, -s.Y * 0.16, 0)
			)
		end
		if arm.lower then
			local s = arm.lower.Size
			Kit.ellipsoid(
				ctx,
				arm.lower,
				"plate",
				V(s.X * 0.86, s.Y * 1.05, s.Z * 0.86),
				C(0, -s.Y * 0.08, 0)
			)
			cuff(ctx, arm.lower, "trim", 0.9, -0.48)
		end
		hand(ctx, arm.hand, "skin")
		shell(ctx, leg.upper, "suit", 0.72)
		shell(ctx, leg.lower, "plateShade", 0.78)
		cuff(ctx, leg.lower, "trim", 0.8, 0.38)
		if leg.foot then
			boot(ctx, leg.foot, "plateShade")
		end
	end
end

local function ranger(ctx: Kit.Ctx, body: Kit.Body)
	local upper, lower = body.upper, body.lower
	if upper then
		local s = upper.Size
		local x, y, z = s.X, s.Y, s.Z
		Kit.ellipsoid(ctx, upper, "suit", V(x * 0.8, y * 1.06, z * 0.92), C(0, 0, 0))
		Kit.ellipsoid(ctx, upper, "plate", V(x * 0.84, y * 0.82, z * 1.0), C(0, -y * 0.08, 0))
		-- Chest strap, front and back.
		for _, zs in { -1, 1 } do
			Kit.block(
				ctx,
				upper,
				"grip",
				V(0.14, y * 1.25, 0.06),
				C(0, -y * 0.02, zs * z * 0.52) * A(0, 0, rad(36))
			)
		end
		Kit.ellipsoid(ctx, upper, "trim", V(0.2, 0.2, 0.08), C(-x * 0.12, y * 0.12, -z * 0.56))
		-- Quiver with three arrows.
		local quiver = C(x * 0.18, y * 0.05, z * 0.78) * A(0, 0, rad(-24))
		Kit.part(ctx, upper, "grip", "Cylinder", V(0.42, 1.6, 0.42), quiver)
		Kit.part(ctx, upper, "trim", "Cylinder", V(0.46, 0.08, 0.46), quiver * C(0, 0.78, 0))
		for i = -1, 1 do
			local arrow = quiver * C(i * 0.1, 1.0, i * 0.05)
			Kit.part(ctx, upper, "blade", "Cylinder", V(0.05, 0.5, 0.05), arrow)
			Kit.ellipsoid(ctx, upper, "glow", V(0.14, 0.26, 0.04), arrow * C(0, 0.25, 0))
		end
		-- Hooded half cloak.
		Kit.ellipsoid(ctx, upper, "cloth", V(x * 1.1, y * 0.48, z * 1.18), C(0, y * 0.36, z * 0.04))
		Kit.ellipsoid(ctx, upper, "cloth", V(x * 0.62, y * 0.36, z * 0.6), C(0, y * 0.56, z * 0.46))
		local length = y * 0.9 + legLength(body) * 0.4
		local cloak = C(0, y * 0.3 - length / 2, z * 0.62) * A(rad(-6), 0, 0)
		Kit.block(ctx, upper, "cloth", V(x * 0.9, length, 0.06), cloak)
		Kit.block(ctx, upper, "trim", V(x * 0.92, 0.08, 0.08), cloak * C(0, -length / 2 + 0.04, 0))
	end
	if lower then
		local s = lower.Size
		Kit.block(ctx, lower, "grip", V(s.X * 0.88, s.Y * 0.55, s.Z * 1.02), C(0, 0, 0))
		Kit.ellipsoid(ctx, lower, "trim", V(0.2, 0.18, 0.08), C(0, 0, -s.Z * 0.55))
		for _, sign in Kit.SIDES do
			Kit.block(ctx, lower, "grip", V(0.32, 0.36, 0.22), C(sign * s.X * 0.36, -s.Y * 0.5, -s.Z * 0.3))
		end
	end
	for side, sign in Kit.SIDES do
		local arm, leg = body.arms[side], body.legs[side]
		shell(ctx, arm.upper, "suit", 0.68)
		if sign < 0 and arm.upper then
			-- One pauldron, on the bow arm.
			local s = arm.upper.Size
			local at = C(-s.X * 0.12, s.Y * 0.38, 0) * A(0, 0, rad(14))
			Kit.ellipsoid(ctx, arm.upper, "plate", V(s.X * 1.3, s.Y * 0.56, s.Z * 1.3), at)
			Kit.ellipsoid(
				ctx,
				arm.upper,
				"trim",
				V(s.X * 1.34, s.Y * 0.1, s.Z * 1.34),
				at * C(0, -s.Y * 0.2, 0)
			)
		end
		shell(ctx, arm.lower, "suit", 0.66)
		if arm.lower then
			local s = arm.lower.Size
			Kit.part(
				ctx,
				arm.lower,
				"grip",
				"Cylinder",
				V(s.X * 0.76, s.Y * 0.6, s.X * 0.76),
				C(0, -s.Y * 0.15, 0)
			)
			cuff(ctx, arm.lower, "trim", 0.8, 0.15)
		end
		hand(ctx, arm.hand, "grip")
		shell(ctx, leg.upper, "plateShade", 0.74)
		shell(ctx, leg.lower, "grip", 0.8)
		cuff(ctx, leg.lower, "trim", 0.86, 0.4)
		if leg.foot then
			boot(ctx, leg.foot, "grip")
		end
	end
end

local function tunic(ctx: Kit.Ctx, body: Kit.Body)
	local upper, lower = body.upper, body.lower
	if upper then
		local s = upper.Size
		Kit.ellipsoid(ctx, upper, "plate", V(s.X * 0.84, s.Y * 1.06, s.Z * 0.95), C(0, -s.Y * 0.02, 0))
		Kit.block(ctx, upper, "cloth", V(s.X * 0.22, s.Y * 0.3, 0.06), C(0, s.Y * 0.3, -s.Z * 0.48))
		Kit.ring(ctx, upper, "cloth", C(0, s.Y * 0.48, 0), s.X * 0.19, 0.08, 0.1, 8)
	end
	if lower then
		local s = lower.Size
		Kit.block(ctx, lower, "grip", V(s.X * 0.88, s.Y * 0.55, s.Z * 1.02), C(0, 0, 0))
		Kit.block(ctx, lower, "trim", V(0.24, 0.2, 0.06), C(0, 0, -s.Z * 0.54))
		skirt(ctx, lower, 4, 0, 360, legLength(body) * 0.3, s.X * 0.44, s.X * 0.52, function()
			return "plate"
		end)
	end
	for side in Kit.SIDES do
		local arm, leg = body.arms[side], body.legs[side]
		shell(ctx, arm.upper, "plate", 0.72)
		shell(ctx, arm.lower, "suit", 0.66)
		hand(ctx, arm.hand, "skin")
		shell(ctx, leg.upper, "suit", 0.74)
		shell(ctx, leg.lower, "suit", 0.72)
		if leg.foot then
			boot(ctx, leg.foot, "grip")
		end
	end
end

local SETS: { [string]: (Kit.Ctx, Kit.Body) -> () } = {
	Robe = robe,
	Coat = coat,
	Ranger = ranger,
	Tunic = tunic,
	Plate = function(ctx, body)
		if body.upper then
			chest(ctx, body.upper)
		end
		if body.lower then
			waist(ctx, body.lower)
		end
		for side, sign in Kit.SIDES do
			local arm, leg = body.arms[side], body.legs[side]
			if arm.upper then
				shoulder(ctx, arm.upper, sign)
			end
			if arm.lower then
				forearm(ctx, arm.lower)
			end
			if arm.hand then
				gauntlet(ctx, arm.hand)
			end
			if leg.upper then
				thigh(ctx, leg.upper)
			end
			if leg.lower then
				shin(ctx, leg.lower)
			end
			if leg.foot then
				boot(ctx, leg.foot)
			end
		end
	end,
}

function ArmorBuilder.build(ctx: Kit.Ctx, body: Kit.Body)
	local set = SETS[ctx.archetype.armor]
	if set then
		set(ctx, body)
	end
end

return ArmorBuilder
