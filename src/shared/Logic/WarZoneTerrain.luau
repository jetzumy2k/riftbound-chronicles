--!strict
--[[
	WarZoneTerrain — one entry point for every war zone's heightmap
	(Phases 12-13). A war zone names its terrain (WorldLayout.WarZone
	.terrain); this picks the matching pure module.

	  sample(zone, x, z)   height, material and water surface relative to the
	                       zone centre (studs; heights relative to its plaza)
	  groundY(zone, wx, wz) world Y of the ground at a world point
	  range(zone)          lowest / highest surface relative to the plaza,
	                       for the voxel writer's vertical extent

	Pure module.
]]

local DesertTerrain = require(script.Parent.DesertTerrain)
local JungleTerrain = require(script.Parent.JungleTerrain)

export type Zone = { terrain: string, size: number, center: { number } }

local WarZoneTerrain = {}

function WarZoneTerrain.sample(zone: Zone, x: number, z: number): (number, string, number?)
	if zone.terrain == "Jungle" then
		local height, material, water = JungleTerrain.sample(x, z, zone.size)
		return height, material, water
	end
	local height, material = DesertTerrain.sample(x, z, zone.size)
	return height, material, DesertTerrain.WATER_LEVEL
end

function WarZoneTerrain.groundY(zone: Zone, worldX: number, worldZ: number): number
	local c = zone.center
	local height = WarZoneTerrain.sample(zone, worldX - c[1], worldZ - c[3])
	return c[2] + height
end

function WarZoneTerrain.range(zone: Zone): (number, number)
	if zone.terrain == "Jungle" then
		return -JungleTerrain.POOL_DEPTH - 12, JungleTerrain.RIM_HEIGHT + 16
	end
	return -DesertTerrain.POOL_DEPTH - 12, DesertTerrain.RIM_HEIGHT + 16
end

return table.freeze(WarZoneTerrain)
