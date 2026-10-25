--!strict
--[[
	CapitalTerrain — the capitals' landforms as Roblox Terrain (Phase 16
	stage 4, PLAN.md D-85). Pure: World/CapitalBuilder writes the voxels,
	tests check the shapes offline.

	  island   Skyreach's floating rock: balls of rock in rings that taper
	           downward from just under the platform, ragged by seeded
	           jitter, with hanging spires (stalactites). Terrain can float,
	           so the island is one smooth craggy mass instead of stacked
	           slabs.
	  volcano  Emberdeep's volcano: a heightfield with concave flanks,
	           radial ridges and gullies, a sunken crater and cracked-lava
	           channels down six sides. Heights are relative to the lava
	           sea; coordinates relative to the volcano's centre.

	math.noise and the seeded generator below are deterministic, so every
	server builds the same shapes.
]]

local CapitalTerrain = {}

export type Ball = { x: number, y: number, z: number, r: number, material: string }

CapitalTerrain.SEED = 23.57

-- Island: depth below the platform's underside, top radius as a share of
-- the platform's half width, and the hanging spires.
CapitalTerrain.ISLAND_DEPTH = 150
CapitalTerrain.ISLAND_TOP_SHARE = 0.92
CapitalTerrain.SPIRES = 7
CapitalTerrain.SPIRE_LENGTH = 48

CapitalTerrain.VOLCANO = table.freeze({
	radius = 270,
	height = 250,
	craterRadius = 46,
	craterDepth = 34,
	-- Lava channels: how many, and their half width (studs).
	channels = 6,
	channelHalfWidth = 5,
})

-- Small seeded generator (pure modules can't use Random in tests).
type Rng = { NextNumber: (Rng, number, number) -> number, state: number }

local function newRng(seed: number): Rng
	local rng = { state = seed % 2147483647 }
	function rng.NextNumber(self: Rng, low: number, high: number): number
		self.state = (self.state * 48271) % 2147483647
		return low + (high - low) * (self.state / 2147483647)
	end
	return rng :: any
end

--[[
	Rock balls for a floating island under a platform whose underside is at
	`bottom` (world Y) centred on (cx, cz) with half width `half`. Every ball
	stays below `bottom` + 1, so nothing pokes through the platform.
	Returns the balls and the spire tips' world positions {x, y, z}.
]]
function CapitalTerrain.island(
	cx: number,
	bottom: number,
	cz: number,
	half: number
): ({ Ball }, { { number } })
	local rng = newRng(2357)
	local balls: { Ball } = {}
	local topRadius = half * CapitalTerrain.ISLAND_TOP_SHARE
	local depth = CapitalTerrain.ISLAND_DEPTH
	local step = 9
	for y = 0, depth, step do
		local t = y / depth
		-- Fat near the top, narrowing faster toward the point.
		local ring = topRadius * (1 - t) ^ 1.05
		-- Each layer's centre wanders a little: a craggy, lopsided rock.
		local ox = 14 * t * math.noise(y / 30, CapitalTerrain.SEED, 1)
		local oz = 14 * t * math.noise(y / 30, CapitalTerrain.SEED, 2)
		local r = math.max(7, math.min(22, ring * 0.4))
		local material = if t < 0.25 then "Slate" elseif t < 0.6 then "Rock" else "Basalt"
		-- Concentric rings of balls fill the layer out to its ragged edge.
		local radial = math.max(0, ring - r * 0.6)
		while true do
			local count = math.max(1, math.ceil(2 * math.pi * radial / (r * 1.1)))
			for i = 1, count do
				local a = (i + rng:NextNumber(-0.3, 0.3)) / count * math.pi * 2
				local at = radial * rng:NextNumber(0.85, 1.05)
				local rr = r * rng:NextNumber(0.85, 1.15)
				-- Clamped so the top layer's balls stay under the platform.
				local cy = math.min(bottom - y - rng:NextNumber(0, step * 0.5), bottom + 1 - rr)
				table.insert(balls, {
					x = cx + ox + math.cos(a) * at,
					y = cy,
					z = cz + oz + math.sin(a) * at,
					r = rr,
					material = material,
				})
			end
			if radial <= 0 then
				break
			end
			radial = math.max(0, radial - r * 1.5)
		end
	end
	-- Hanging spires from the underside, each a chain of shrinking balls.
	local tips: { { number } } = {}
	for i = 1, CapitalTerrain.SPIRES do
		local a = i / CapitalTerrain.SPIRES * math.pi * 2 + rng:NextNumber(-0.25, 0.25)
		local reach = rng:NextNumber(0.25, 0.55)
		-- Start inside the island at the height where its ring is that wide.
		local startT = 1 - reach ^ (1 / 1.05)
		local sx = cx + math.cos(a) * topRadius * reach * 0.8
		local sz = cz + math.sin(a) * topRadius * reach * 0.8
		local sy = bottom - startT * depth
		local length = CapitalTerrain.SPIRE_LENGTH * rng:NextNumber(0.8, 1.3)
		local links = 6
		for k = 0, links do
			local f = k / links
			table.insert(balls, {
				x = sx,
				y = sy - f * length,
				z = sz,
				r = 7 * (1 - f) + 1.5,
				material = "Basalt",
			})
		end
		table.insert(tips, { sx, sy - length - 1.5, sz })
	end
	return balls, tips
end

local function smoothstep(e0: number, e1: number, x: number): number
	local t = math.clamp((x - e0) / (e1 - e0), 0, 1)
	return t * t * (3 - 2 * t)
end

-- Angle (radians) of the n-th lava channel at distance r from the centre:
-- each channel winds a little as it runs down the flank.
function CapitalTerrain.channelAngle(n: number, r: number): number
	return (n + 0.3) / CapitalTerrain.VOLCANO.channels * math.pi * 2 + 0.16 * math.sin(r / 38 + n * 1.7)
end

--[[
	Volcano surface at (x, z) relative to its centre: height above the lava
	sea (0 outside the base) and material ("Basalt", "Rock", "CrackedLava").
]]
function CapitalTerrain.volcano(x: number, z: number): (number, string)
	local v = CapitalTerrain.VOLCANO
	local r = math.sqrt(x * x + z * z)
	local angle = math.atan2(z, x)
	-- A ragged foot: the base radius swells and shrinks around the cone.
	local radius = v.radius
		* (1 + 0.12 * math.noise(math.cos(angle) * 1.6, math.sin(angle) * 1.6, CapitalTerrain.SEED + 5))
	if r >= radius then
		return 0, "Basalt"
	end
	-- Concave flanks: steep near the top, spreading out at the foot.
	local profile = (1 - r / radius) ^ 1.7
	-- Radial ridges and gullies, stronger lower down.
	local ridges = math.noise(math.cos(angle) * 4, math.sin(angle) * 4, r / 60 + CapitalTerrain.SEED)
	local height = v.height * profile * (1 + 0.1 * ridges * (r / radius))
	-- The crater: inside the rim the cone stops rising and sinks into a bowl.
	local rim = v.height * (1 - v.craterRadius / radius) ^ 1.7
	if r < v.craterRadius then
		local bowl = 1 - smoothstep(0, v.craterRadius, r) ^ 2
		height = rim + 3 - v.craterDepth * bowl
	end
	local material = if r > radius * 0.8 then "Rock" else "Basalt"
	if r < v.craterRadius * 0.6 then
		material = "CrackedLava"
	end
	-- Lava channels from the rim down six sides, narrowing toward the foot.
	if r > v.craterRadius and r < radius * 0.85 then
		for n = 0, v.channels - 1 do
			local da =
				math.abs((angle - CapitalTerrain.channelAngle(n, r) + math.pi) % (math.pi * 2) - math.pi)
			if da * r < v.channelHalfWidth * (1.2 - r / radius) then
				material = "CrackedLava"
				height -= 1.5
				break
			end
		end
	end
	return math.max(0, height), material
end

return table.freeze(CapitalTerrain)
