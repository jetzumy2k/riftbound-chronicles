--!strict
--[[
	Telegraph — ground-area hit tests for telegraphed attacks (boss
	abilities). Points are {x, z} on the ground plane; the server tests
	players' positions at the moment the attack lands, the client draws the
	same shapes as warnings beforehand.

	Pure module.
]]

export type Point = { number }

local Telegraph = {}

local function delta(a: Point, b: Point): (number, number)
	return b[1] - a[1], b[2] - a[2]
end

function Telegraph.inCircle(center: Point, radius: number, point: Point): boolean
	local dx, dz = delta(center, point)
	return dx * dx + dz * dz <= radius * radius
end

-- Ring: between `inner` and `radius` (standing close to the centre is safe).
function Telegraph.inRing(center: Point, inner: number, radius: number, point: Point): boolean
	local dx, dz = delta(center, point)
	local d2 = dx * dx + dz * dz
	return d2 >= inner * inner and d2 <= radius * radius
end

-- Cone from `origin` along unit `facing` {x, z}, `angle` degrees wide in total.
function Telegraph.inCone(origin: Point, facing: Point, radius: number, angle: number, point: Point): boolean
	local dx, dz = delta(origin, point)
	local d2 = dx * dx + dz * dz
	if d2 > radius * radius then
		return false
	end
	if d2 < 1e-6 then
		return true
	end
	local d = math.sqrt(d2)
	local cosTo = (dx * facing[1] + dz * facing[2]) / d
	return cosTo >= math.cos(math.rad(angle / 2))
end

return table.freeze(Telegraph)
