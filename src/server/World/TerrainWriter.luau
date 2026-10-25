--!strict
--[[
	TerrainWriter — writes a war zone's heightmap into Roblox Terrain
	(Phases 12-13). Shared by DesertBuilder and JungleBuilder.

	For every 4-stud column it samples Logic/WarZoneTerrain: the surface
	material covers the top layers, `bedrock` (or the zone's rock band at
	that height, WarZoneTerrain.strataShift / band) fills below, and water fills
	any air below the column's water surface. Written in 32×32-column chunks
	so no single WriteVoxels call gets too large.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local WarZoneTerrain = require(ReplicatedStorage.Shared.Logic.WarZoneTerrain)
local WorldLayout = require(ReplicatedStorage.Shared.Definitions.WorldLayout)

local TerrainWriter = {}

local VOXEL = 4
local CHUNK = 32 -- columns per side per WriteVoxels call
-- Depth of the surface material before bedrock shows.
local TOPSOIL = VOXEL * 2.5

function TerrainWriter.write(
	zone: WorldLayout.WarZone,
	materials: { [string]: Enum.Material },
	bedrock: Enum.Material
)
	local terrain = Workspace.Terrain
	local c = zone.center
	local half = zone.size / 2
	local low, high = WarZoneTerrain.range(zone)
	local x0 = math.floor((c[1] - half) / VOXEL) * VOXEL
	local z0 = math.floor((c[3] - half) / VOXEL) * VOXEL
	local columns = math.ceil(zone.size / VOXEL)
	local yBottom = math.floor((c[2] + low) / VOXEL) * VOXEL
	local yTop = math.ceil((c[2] + high) / VOXEL) * VOXEL
	local layers = (yTop - yBottom) // VOXEL

	for ci = 0, columns - 1, CHUNK do
		for ck = 0, columns - 1, CHUNK do
			local nx = math.min(CHUNK, columns - ci)
			local nz = math.min(CHUNK, columns - ck)
			local mats = table.create(nx)
			local occupancy = table.create(nx)
			for i = 1, nx do
				local mi = table.create(layers)
				local oi = table.create(layers)
				for j = 1, layers do
					mi[j] = table.create(nz, Enum.Material.Air)
					oi[j] = table.create(nz, 0)
				end
				mats[i] = mi
				occupancy[i] = oi
				local wx = x0 + (ci + i - 0.5) * VOXEL
				for k = 1, nz do
					local wz = z0 + (ck + k - 0.5) * VOXEL
					local height, materialName, waterLevel = WarZoneTerrain.sample(zone, wx - c[1], wz - c[3])
					local surface = c[2] + height
					local water = if waterLevel then c[2] + waterLevel else -math.huge
					local top = materials[materialName] or bedrock
					local shift = WarZoneTerrain.strataShift(zone, wx - c[1], wz - c[3])
					for j = 1, layers do
						local yb = yBottom + (j - 1) * VOXEL
						local fill = math.clamp((surface - yb) / VOXEL, 0, 1)
						if fill > 0 then
							oi[j][k] = fill
							if surface - yb < TOPSOIL then
								mi[j][k] = top
							elseif shift then
								mi[j][k] = materials[WarZoneTerrain.band(zone, yb - c[2], shift)] or bedrock
							else
								mi[j][k] = bedrock
							end
						elseif yb < water then
							oi[j][k] = math.clamp((water - yb) / VOXEL, 0, 1)
							mi[j][k] = Enum.Material.Water
						end
					end
				end
			end
			local region = Region3.new(
				Vector3.new(x0 + ci * VOXEL, yBottom, z0 + ck * VOXEL),
				Vector3.new(x0 + (ci + nx) * VOXEL, yBottom + layers * VOXEL, z0 + (ck + nz) * VOXEL)
			)
			terrain:WriteVoxels(region, VOXEL, mats, occupancy)
		end
	end
end

--[[
	A free-standing heightfield (D-85: Emberdeep's volcano): `columns` x
	`columns` 4-stud columns from world (x0, z0), filled from yBottom up to
	each column's surface. sample(wx, wz) returns the surface world Y and
	its material; rock below the topsoil is `bedrock`.
]]
function TerrainWriter.writeField(
	x0: number,
	z0: number,
	columns: number,
	yBottom: number,
	yTop: number,
	sample: (number, number) -> (number, Enum.Material),
	bedrock: Enum.Material
)
	local terrain = Workspace.Terrain
	x0 = math.floor(x0 / VOXEL) * VOXEL
	z0 = math.floor(z0 / VOXEL) * VOXEL
	yBottom = math.floor(yBottom / VOXEL) * VOXEL
	local layers = math.ceil((yTop - yBottom) / VOXEL)
	for ci = 0, columns - 1, CHUNK do
		for ck = 0, columns - 1, CHUNK do
			local nx = math.min(CHUNK, columns - ci)
			local nz = math.min(CHUNK, columns - ck)
			local mats = table.create(nx)
			local occupancy = table.create(nx)
			for i = 1, nx do
				local mi = table.create(layers)
				local oi = table.create(layers)
				for j = 1, layers do
					mi[j] = table.create(nz, Enum.Material.Air)
					oi[j] = table.create(nz, 0)
				end
				mats[i] = mi
				occupancy[i] = oi
				local wx = x0 + (ci + i - 0.5) * VOXEL
				for k = 1, nz do
					local wz = z0 + (ck + k - 0.5) * VOXEL
					local surface, top = sample(wx, wz)
					for j = 1, layers do
						local yb = yBottom + (j - 1) * VOXEL
						local fill = math.clamp((surface - yb) / VOXEL, 0, 1)
						if fill > 0 then
							oi[j][k] = fill
							mi[j][k] = if surface - yb < TOPSOIL then top else bedrock
						end
					end
				end
			end
			local region = Region3.new(
				Vector3.new(x0 + ci * VOXEL, yBottom, z0 + ck * VOXEL),
				Vector3.new(x0 + (ci + nx) * VOXEL, yBottom + layers * VOXEL, z0 + (ck + nz) * VOXEL)
			)
			terrain:WriteVoxels(region, VOXEL, mats, occupancy)
		end
	end
end

return TerrainWriter
