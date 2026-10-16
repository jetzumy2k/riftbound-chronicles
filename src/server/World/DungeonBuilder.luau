--!strict
--[[
	DungeonBuilder — builds a dungeon map from DungeonDefinitions
	(Phase 9; style per the "Dungeon Example" concept: a ruined gothic hall,
	candlelight, rift crystals, a stone sanctum for the guardian).

	The map is built once as a template (DungeonService keeps it in
	ServerStorage) and cloned per run. Layout, in the template's frame
	(origin = entry edge of the first room, floor top at y = 0, deeper = -Z):

	  Start          small landing with the exit portal (leave the dungeon)
	  rooms[i]       floor, walls with pillars, candelabras, crystals
	  corridors      wide open passages between rooms (the map is open, D-42)
	Markers (invisible, non-colliding, named parts):
	  Checkpoint_<i> respawn / arrival point at room i's entry
	  Room_<i>       room volume (boss-room presence checks)
	  Exit           exit portal surface (ProximityPrompt added by DungeonService)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DungeonDefinitions = require(ReplicatedStorage.Shared.Definitions.DungeonDefinitions)
local Architecture = require(script.Parent.Architecture)

local DungeonBuilder = {}

-- Width of the openings between rooms and corridors (set per dungeon in build()).
local opening = 28

local A = Architecture

local STONE = Color3.fromRGB(122, 116, 112)
local STONE_DARK = Color3.fromRGB(84, 80, 82)
local FLOOR = Color3.fromRGB(104, 98, 96)
local TRIM = Color3.fromRGB(186, 150, 92)
local CRYSTAL = Color3.fromRGB(110, 200, 255)
local FLAME = Color3.fromRGB(255, 190, 110)

-- A stone style for the shared kit pieces (arches, columns, stairs).
local STYLE: Architecture.Style = {
	race = "Dungeon",
	stone = STONE,
	stoneMaterial = Enum.Material.Slate,
	stoneDark = STONE_DARK,
	trim = TRIM,
	trimMaterial = Enum.Material.Metal,
	roof = STONE_DARK,
	roofMaterial = Enum.Material.Slate,
	glow = CRYSTAL,
	window = CRYSTAL,
	cloth = Color3.fromRGB(70, 60, 92),
	light = FLAME,
	towerTop = "spire",
}

local function marker(parent: Instance, name: string, size: Vector3, cf: CFrame): Part
	local part = A.part(
		parent,
		size,
		cf,
		Color3.new(1, 1, 1),
		Enum.Material.SmoothPlastic,
		{ name = name, decor = true, transparency = 1 }
	)
	return part
end

local function candelabra(parent: Instance, cf: CFrame, light: boolean)
	A.cylinder(parent, 0.5, 6, cf, TRIM, Enum.Material.Metal)
	A.part(
		parent,
		Vector3.new(3, 0.4, 0.4),
		cf * CFrame.new(0, 6, 0),
		TRIM,
		Enum.Material.Metal,
		{ decor = true }
	)
	for _, x in { -1.3, 0, 1.3 } do
		A.cylinder(
			parent,
			0.22,
			1,
			cf * CFrame.new(x, 6.2, 0),
			Color3.fromRGB(240, 232, 214),
			Enum.Material.SmoothPlastic,
			{ decor = true }
		)
		local flame = A.part(
			parent,
			Vector3.new(0.3, 0.5, 0.3),
			cf * CFrame.new(x, 7.5, 0),
			FLAME,
			Enum.Material.Neon,
			{ decor = true, shape = Enum.PartType.Ball }
		)
		if light and x == 0 then
			local point = Instance.new("PointLight")
			point.Color = FLAME
			point.Range = 26
			point.Brightness = 1.6
			point.Shadows = false
			point.Parent = flame
		end
	end
end

local function rubble(parent: Instance, cf: CFrame, seed: number)
	local rng = Random.new(seed)
	for _ = 1, 4 do
		local s = rng:NextNumber(1, 2.6)
		A.part(
			parent,
			Vector3.new(s, s * 0.6, s * 0.8),
			cf
				* CFrame.new(rng:NextNumber(-3, 3), s * 0.3, rng:NextNumber(-3, 3))
				* CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, 3), rng:NextNumber(-0.4, 0.4)),
			STONE_DARK,
			Enum.Material.Slate
		)
	end
end

local function room(
	parent: Instance,
	index: number,
	def: DungeonDefinitions.Room,
	z0: number,
	isBoss: boolean,
	lastRoom: boolean
)
	local model = Instance.new("Model")
	model.Name = `Room{index}_{def.id}`
	local w, h, d = def.size[1], def.size[2], def.size[3]
	local center = CFrame.new(0, 0, z0 - d / 2)
	-- Floor with a darker border and slab lines.
	A.part(model, Vector3.new(w, 2, d), center * CFrame.new(0, -1, 0), FLOOR, Enum.Material.Slate)
	for i = 1, math.floor(d / 12) do
		A.part(
			model,
			Vector3.new(w - 4, 0.12, 0.5),
			CFrame.new(0, 0.06, z0 - i * 12),
			STONE_DARK,
			Enum.Material.Slate,
			{ decor = true }
		)
	end
	-- Side walls with pillars and arches.
	for _, side in { -1, 1 } do
		A.part(
			model,
			Vector3.new(3, h, d),
			center * CFrame.new(side * (w / 2 + 1.5), h / 2, 0),
			STONE,
			Enum.Material.Slate
		)
		local pillars = math.max(2, math.floor(d / 22))
		for i = 0, pillars - 1 do
			local z = z0 - (i + 0.5) * d / pillars
			local pillarCF = CFrame.new(side * (w / 2 - 2), 0, z)
			A.column(model, pillarCF, 1.8, h - 4, STYLE)
			-- Gothic rib arching across the hall from this pillar.
			if i % 2 == 0 and side == -1 then
				A.part(
					model,
					Vector3.new(w, 2, 2),
					CFrame.new(0, h - 1, z),
					STONE_DARK,
					Enum.Material.Slate,
					{ decor = true }
				)
			end
			if i % 2 == 1 then
				candelabra(model, CFrame.new(side * (w / 2 - 6), 0, z), i % 4 == 1)
			end
		end
		-- Tall lancet windows glowing with rift light.
		for i = 0, 1 do
			A.part(
				model,
				Vector3.new(0.4, h * 0.45, 4),
				CFrame.new(side * (w / 2 + 0.05), h * 0.5, z0 - (i + 0.5) * d / 2),
				CRYSTAL,
				Enum.Material.Neon,
				{ decor = true, transparency = 0.2 }
			)
		end
	end
	-- Entry wall (with an opening) and far wall (opening unless last room).
	local walls: { { any } } = { { z0, true }, { z0 - d, not lastRoom } }
	for _, spec in walls do
		local z, open = spec[1], spec[2]
		if open then
			local side = (w - opening) / 2
			local archHeight = 30
			for _, s in { -1, 1 } do
				A.part(
					model,
					Vector3.new(side, h, 3),
					CFrame.new(s * (opening / 2 + side / 2), h / 2, z),
					STONE,
					Enum.Material.Slate
				)
			end
			A.part(
				model,
				Vector3.new(opening, h - archHeight, 3),
				CFrame.new(0, archHeight + (h - archHeight) / 2, z),
				STONE,
				Enum.Material.Slate
			)
			A.arch(
				model,
				CFrame.new(0, 0, z + (if z == z0 then -1.6 else 1.6)),
				opening - 2,
				archHeight,
				1,
				2,
				STYLE
			)
		else
			A.part(model, Vector3.new(w, h, 3), CFrame.new(0, h / 2, z - 1.5), STONE, Enum.Material.Slate)
		end
	end
	-- Rift crystals and rubble for storytelling.
	local rng = Random.new(index * 17)
	for i = 1, math.max(3, math.floor(w * d / 3500)) do
		local side = if i % 2 == 0 then 1 else -1
		A.crystals(
			model,
			CFrame.new(side * (w / 2 - 8 - rng:NextNumber(0, 6)), 0, z0 - rng:NextNumber(0.2, 0.9) * d),
			rng:NextNumber(5, 9),
			CRYSTAL
		)
		rubble(model, CFrame.new(-side * (w / 2 - 10), 0, z0 - rng:NextNumber(0.2, 0.9) * d), index * 10 + i)
	end
	if isBoss then
		-- Rune circle, broken statues and the great rift crystal behind the boss.
		local mid = CFrame.new(0, 0, z0 - d * 0.62)
		A.ring(model, 26, 1.2, 0.25, 40, mid, CRYSTAL, Enum.Material.Neon, { decor = true })
		A.ring(model, 18, 0.6, 0.22, 32, mid, TRIM, Enum.Material.Metal, { decor = true })
		for _, side in { -1, 1 } do
			local statue = CFrame.new(side * (w / 2 - 14), 0, z0 - d * 0.3)
			A.part(model, Vector3.new(8, 4, 8), statue * CFrame.new(0, 2, 0), STONE_DARK, Enum.Material.Slate)
			A.part(model, Vector3.new(5, 12, 3.5), statue * CFrame.new(0, 10, 0), STONE, Enum.Material.Slate)
			A.part(model, Vector3.new(3, 3, 3), statue * CFrame.new(0, 17.5, 0), STONE, Enum.Material.Slate)
		end
		local crystal = A.part(
			model,
			Vector3.new(7, 22, 7),
			CFrame.new(0, 13, z0 - d + 10) * CFrame.Angles(0, math.rad(45), math.rad(8)),
			CRYSTAL,
			Enum.Material.Neon,
			{ decor = true, transparency = 0.15 }
		)
		local light = Instance.new("PointLight")
		light.Color = CRYSTAL
		light.Range = 50
		light.Brightness = 2
		light.Parent = crystal
	end
	marker(model, `Room_{index}`, Vector3.new(w, h, d), center * CFrame.new(0, h / 2, 0))
	marker(model, `Checkpoint_{index}`, Vector3.new(4, 1, 4), CFrame.new(0, 3, z0 - 8))
	model.Parent = parent
end

local function corridor(parent: Instance, index: number, z0: number, length: number, width: number)
	local model = Instance.new("Model")
	model.Name = `Corridor{index}`
	local height = 32
	local center = CFrame.new(0, 0, z0 - length / 2)
	A.part(model, Vector3.new(width, 2, length), center * CFrame.new(0, -1, 0), FLOOR, Enum.Material.Slate)
	for _, side in { -1, 1 } do
		A.part(
			model,
			Vector3.new(3, height, length),
			center * CFrame.new(side * (width / 2 + 1.5), height / 2, 0),
			STONE,
			Enum.Material.Slate
		)
	end
	A.part(
		model,
		Vector3.new(width + 6, 3, length),
		center * CFrame.new(0, height + 1.5, 0),
		STONE_DARK,
		Enum.Material.Slate
	)
	candelabra(model, CFrame.new(-(width / 2 - 2), 0, z0 - length / 2), true)
	candelabra(model, CFrame.new(width / 2 - 2, 0, z0 - length / 4), false)
	A.crystals(model, CFrame.new(width / 2 - 4, 0, z0 - length * 0.7), 6, CRYSTAL)
	model.Parent = parent
end

--[[
	Builds the template for `dungeon` (unparented Model, PrimaryPart "Origin"
	at the first room's entry edge, floor top y = 0).
]]
function DungeonBuilder.build(dungeon: DungeonDefinitions.Dungeon): Model
	opening = dungeon.corridorWidth
	local model = Instance.new("Model")
	model.Name = `Dungeon_{dungeon.id}`
	local origin = marker(model, "Origin", Vector3.new(1, 1, 1), CFrame.new(0, 0.5, 0))
	model.PrimaryPart = origin

	-- Start landing with the exit portal behind the arrival point.
	A.part(model, Vector3.new(34, 2, 24), CFrame.new(0, -1, 12), FLOOR, Enum.Material.Slate)
	for _, side in { -1, 1 } do
		A.part(model, Vector3.new(3, 24, 24), CFrame.new(side * 18.5, 12, 12), STONE, Enum.Material.Slate)
	end
	A.part(model, Vector3.new(40, 24, 3), CFrame.new(0, 12, 25.5), STONE, Enum.Material.Slate)
	local exit = A.portalGate(
		model,
		CFrame.new(0, 0, 16) * CFrame.Angles(0, math.pi, 0),
		{ label = "Leave Dungeon", opensIn = "", active = true },
		STYLE
	)
	exit.Name = "Exit"
	marker(model, "Arrival", Vector3.new(4, 1, 4), CFrame.new(0, 3, 4))

	local offsets = DungeonDefinitions.roomOffsets(dungeon)
	for index, def in dungeon.rooms do
		local z0 = -offsets[index]
		room(model, index, def, z0, def.boss ~= nil, index == #dungeon.rooms)
		if index < #dungeon.rooms then
			corridor(model, index, z0 - def.size[3], dungeon.corridorLength, dungeon.corridorWidth)
		end
	end
	return model
end

-- Template-frame CFrame of a spawn in room `index` (facing the entry).
function DungeonBuilder.spawnCFrame(
	dungeon: DungeonDefinitions.Dungeon,
	index: number,
	x: number,
	z: number
): CFrame
	local offsets = DungeonDefinitions.roomOffsets(dungeon)
	local position = Vector3.new(x, 0, -offsets[index] - z)
	return CFrame.lookAt(position, position + Vector3.new(0, 0, 1))
end

return DungeonBuilder
