--!strict
--[[
	ZoneGeometry
	Point-in-volume tests for safe zones (SECURITY_MODEL.md §5A.3: membership is
	computed on the server with plain math, never from client triggers).

	Points are {x, y, z} tables. Pure module.
]]

local ZoneGeometry = {}

type Vec = { number }

function ZoneGeometry.contains(volume: { [string]: any }, point: Vec): boolean
	local center = volume.center
	local dx, dy, dz = point[1] - center[1], point[2] - center[2], point[3] - center[3]

	if volume.kind == "cylinder" then
		return math.abs(dy) <= volume.halfHeight and dx * dx + dz * dz <= volume.radius * volume.radius
	elseif volume.kind == "box" then
		local size = volume.size
		return math.abs(dx) <= size[1] / 2 and math.abs(dy) <= size[2] / 2 and math.abs(dz) <= size[3] / 2
	end
	error(`unknown volume kind '{tostring(volume.kind)}'`)
end

--[[
	Returns the first zone in `zones` containing `point`, or nil.
	Zones are { id, volume, ... } records (WorldLayout.SafeZones).
]]
function ZoneGeometry.findZone(zones: { any }, point: Vec): any
	for _, zone in zones do
		if ZoneGeometry.contains(zone.volume, point) then
			return zone
		end
	end
	return nil
end

return table.freeze(ZoneGeometry)
