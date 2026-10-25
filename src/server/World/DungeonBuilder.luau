--!strict
--[[
	DungeonBuilder — builds a dungeon's floors from DungeonDefinitions
	(Phase 9, D-42, D-47; style per the "Dungeon Example" concept: ruined
	gothic halls, candlelight, rift crystals, a stone sanctum per boss).

	Built once per realm copy. In the copy's frame: origin = floor 1's
	landing entry, floor top at y = 0, x right, deeper = -Z. Floor f sits
	`offsetX` to the right. Each floor is themed:
	  Crystal  grey stone, blue rift crystals, candlelight     (floor 1)
	  Ember    basalt, glowing lava seams, orange fire          (floor 2)
	  Frost    pale ice-stone, icicles, cold blue light         (floor 3)
	  Void     violet-black stone, Nullborn crystals            (floor 4)

	Rooms are rectangles with door openings in their walls under a vaulted
	stone ceiling with rib beams and hanging theme dressing (D-87: crystals,
	glowing chains, icicles, floating void shards); passages join them
	(roofed corridors). Markers (invisible, non-colliding, named):
	  Floor_<f>          the floor's Model
	  Room_<f>_<i>       room volume
	  Arrival_<f>        where players arrive on floor f
	  Leave_<f>          portal surface: leave the dungeon
	  Up_<f>             portal surface: back to floor f-1 (floors 2-4)
	  Down_<f>           portal surface: down to floor f+1 (in the lair)
	(DungeonService makes the portal surfaces walk-through.)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DungeonDefinitions = require(ReplicatedStorage.Shared.Definitions.DungeonDefinitions)
local Architecture = require(script.Parent.Architecture)

local A = Architecture

local DungeonBuilder = {}

type Floor = DungeonDefinitions.Floor
type Room = DungeonDefinitions.Room

type Theme = {
	stone: Color3,
	stoneDark: Color3,
	floor: Color3,
	material: Enum.Material,
	-- The walking surface (D-87): flagstones on the crypt and void floors.
	floorMaterial: Enum.Material,
	trim: Color3,
	glow: Color3,
	flame: Color3,
	style: Architecture.Style,
}

local function theme(
	stone: Color3,
	stoneDark: Color3,
	floor: Color3,
	material: Enum.Material,
	glow: Color3,
	flame: Color3,
	floorMaterial: Enum.Material?
): Theme
	local trim = Color3.fromRGB(186, 150, 92)
	return {
		stone = stone,
		stoneDark = stoneDark,
		floor = floor,
		material = material,
		floorMaterial = floorMaterial or material,
		trim = trim,
		glow = glow,
		flame = flame,
		style = {
			race = "Dungeon",
			stone = stone,
			stoneMaterial = material,
			stoneDark = stoneDark,
			trim = trim,
			trimMaterial = Enum.Material.Metal,
			roof = stoneDark,
			roofMaterial = material,
			glow = glow,
			window = glow,
			cloth = Color3.fromRGB(70, 60, 92),
			light = flame,
			towerTop = "spire",
		},
	}
end

local THEMES: { [string]: Theme } = {
	Crystal = theme(
		Color3.fromRGB(122, 116, 112),
		Color3.fromRGB(84, 80, 82),
		Color3.fromRGB(104, 98, 96),
		Enum.Material.Slate,
		Color3.fromRGB(110, 200, 255),
		Color3.fromRGB(255, 190, 110),
		Enum.Material.Cobblestone
	),
	Ember = theme(
		Color3.fromRGB(78, 64, 60),
		Color3.fromRGB(46, 38, 38),
		Color3.fromRGB(64, 52, 50),
		Enum.Material.Basalt,
		Color3.fromRGB(255, 120, 40),
		Color3.fromRGB(255, 150, 70)
	),
	Frost = theme(
		Color3.fromRGB(170, 184, 200),
		Color3.fromRGB(110, 124, 146),
		Color3.fromRGB(150, 164, 182),
		Enum.Material.Slate,
		Color3.fromRGB(140, 220, 255),
		Color3.fromRGB(200, 236, 255)
	),
	Void = theme(
		Color3.fromRGB(64, 56, 80),
		Color3.fromRGB(38, 32, 50),
		Color3.fromRGB(52, 46, 64),
		Enum.Material.Slate,
		Color3.fromRGB(180, 110, 255),
		Color3.fromRGB(220, 170, 255),
		Enum.Material.Cobblestone
	),
}

local WALL = 3
local DOOR_HEIGHT = 26

-- Floor-frame (x, z) to the copy frame (deeper = -Z).
local function at(floor: Floor, x: number, y: number, z: number): CFrame
	return CFrame.new(floor.offsetX + x, y, -z)
end

local function marker(parent: Instance, name: string, size: Vector3, cf: CFrame): Part
	return A.part(
		parent,
		size,
		cf,
		Color3.new(1, 1, 1),
		Enum.Material.SmoothPlastic,
		{ name = name, decor = true, transparency = 1 }
	)
end

local function light(parent: Instance, color: Color3, range: number, brightness: number)
	local point = Instance.new("PointLight")
	point.Color = color
	point.Range = range
	point.Brightness = brightness
	point.Shadows = false
	point.Parent = parent
end

local function candelabra(parent: Instance, cf: CFrame, t: Theme, lit: boolean)
	A.cylinder(parent, 0.5, 6, cf, t.trim, Enum.Material.Metal)
	A.part(
		parent,
		Vector3.new(3, 0.4, 0.4),
		cf * CFrame.new(0, 6, 0),
		t.trim,
		Enum.Material.Metal,
		{ decor = true }
	)
	for _, x in { -1.3, 0, 1.3 } do
		local flame = A.part(
			parent,
			Vector3.new(0.3, 0.5, 0.3),
			cf * CFrame.new(x, 7, 0),
			t.flame,
			Enum.Material.Neon,
			{ decor = true, shape = Enum.PartType.Ball }
		)
		if lit and x == 0 then
			light(flame, t.flame, 28, 1.6)
		end
	end
end

--[[
	A vaulted ceiling over a room (D-87): the stone slab, rib beams across
	the room every ~24 studs and hanging dressing by theme. The slab is
	solid (flying creatures sense it as headroom); ribs and dressing are
	decor.
]]
local function ceiling(parent: Instance, floor: Floor, room: Room, t: Theme, seed: number)
	local rng = Random.new(seed)
	local cx, cz = room.center[1], room.center[2]
	local w, h, d = room.size[1], room.size[2], room.size[3]
	A.part(
		parent,
		Vector3.new(w + WALL * 2, 3, d + WALL * 2),
		at(floor, cx, h + 1.5, cz),
		t.stoneDark,
		t.material
	)
	local ribs = math.max(1, math.floor(d / 24))
	for i = 1, ribs do
		local z = cz - d / 2 + i * d / (ribs + 1)
		A.part(
			parent,
			Vector3.new(w, 2.4, 2.4),
			at(floor, cx, h - 1.2, z),
			t.stone:Lerp(t.trim, 0.15),
			t.material,
			{ decor = true }
		)
	end
	-- Hanging dressing: a few per room, kept off the middle third so the
	-- camera and flying creatures have a clear centre.
	local count = if room.kind == "Chamber" then 1 else math.clamp(math.floor(w * d / 5000), 2, 6)
	for i = 1, count do
		local side = if i % 2 == 0 then 1 else -1
		local x = cx + side * rng:NextNumber(w * 0.2, w * 0.4)
		local z = cz + rng:NextNumber(-0.4, 0.4) * d
		local top = at(floor, x, h, z)
		if floor.theme == "Frost" then
			for k = 1, 3 do
				local length = rng:NextNumber(4, 9)
				A.part(
					parent,
					Vector3.new(1, length, 1),
					top * CFrame.new(k * 2 - 4, -length / 2, rng:NextNumber(-1, 1)) * CFrame.Angles(0, k, 0),
					Color3.fromRGB(205, 238, 255),
					Enum.Material.Ice,
					{ decor = true, transparency = 0.2 }
				)
			end
		elseif floor.theme == "Ember" then
			local drop = rng:NextNumber(8, 16)
			A.part(
				parent,
				Vector3.new(0.4, drop, 0.4),
				top * CFrame.new(0, -drop / 2, 0),
				Color3.fromRGB(60, 54, 52),
				Enum.Material.Metal,
				{ decor = true }
			)
			A.part(
				parent,
				Vector3.new(2.2, 2.6, 2.2),
				top * CFrame.new(0, -drop - 1.3, 0),
				t.glow,
				Enum.Material.Neon,
				{ decor = true, transparency = 0.1 }
			)
		elseif floor.theme == "Void" then
			-- A shard hanging in the air, no support: the Nullborn's pull.
			A.part(
				parent,
				Vector3.new(2.4, rng:NextNumber(5, 9), 2.4),
				top
					* CFrame.new(0, -h * rng:NextNumber(0.3, 0.45), 0)
					* CFrame.Angles(
						rng:NextNumber(-0.5, 0.5),
						rng:NextNumber(0, 3),
						rng:NextNumber(-0.5, 0.5)
					),
				t.glow,
				Enum.Material.Neon,
				{ decor = true, transparency = 0.2 }
			)
		else
			A.crystals(parent, top * CFrame.Angles(math.pi, 0, 0), rng:NextNumber(5, 8), t.glow)
		end
	end
end

local function rubble(parent: Instance, cf: CFrame, t: Theme, seed: number)
	local rng = Random.new(seed)
	for _ = 1, 3 do
		local s = rng:NextNumber(1, 2.6)
		A.part(
			parent,
			Vector3.new(s, s * 0.6, s * 0.8),
			cf
				* CFrame.new(rng:NextNumber(-3, 3), s * 0.3, rng:NextNumber(-3, 3))
				* CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, 3), rng:NextNumber(-0.4, 0.4)),
			t.stoneDark,
			t.material
		)
	end
end

-- Theme accents: lava seams (Ember), icicles (Frost), crystals otherwise.
local function accent(parent: Instance, cf: CFrame, t: Theme, kind: string, seed: number)
	local rng = Random.new(seed)
	if kind == "Ember" then
		A.part(
			parent,
			Vector3.new(rng:NextNumber(6, 12), 0.2, rng:NextNumber(1.2, 2.4)),
			cf * CFrame.new(0, 0.1, 0) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0),
			t.glow,
			Enum.Material.Neon,
			{ decor = true }
		)
	elseif kind == "Frost" then
		for i = 1, 3 do
			A.part(
				parent,
				Vector3.new(1.2, rng:NextNumber(3, 6), 1.2),
				cf
					* CFrame.new(i * 1.8 - 3.6, rng:NextNumber(1.5, 3), 0)
					* CFrame.Angles(0, 0, rng:NextNumber(-0.2, 0.2)),
				Color3.fromRGB(200, 236, 255),
				Enum.Material.Ice,
				{ decor = true, transparency = 0.2 }
			)
		end
	else
		A.crystals(parent, cf, rng:NextNumber(5, 8), t.glow)
	end
end

--[[
	One wall of a room with its door openings. `side` N (toward the
	entry, smaller z), S, E (+x) or W. Openings get a lintel above.
]]
local function wall(parent: Instance, floor: Floor, room: Room, side: string, t: Theme)
	local cx, cz = room.center[1], room.center[2]
	local w, h, d = room.size[1], room.size[2], room.size[3]
	local alongX = side == "N" or side == "S"
	local length = if alongX then w + WALL * 2 else d
	local openings = {}
	for _, door in room.doors do
		if door.side == side then
			table.insert(openings, { door.offset - door.width / 2, door.offset + door.width / 2 })
		end
	end
	table.sort(openings, function(a, b)
		return a[1] < b[1]
	end)
	local function piece(from: number, to: number, y0: number, y1: number)
		local len = to - from
		if len <= 0.05 or y1 - y0 <= 0.05 then
			return
		end
		local mid = (from + to) / 2
		local y = (y0 + y1) / 2
		local cf, size
		if alongX then
			local z = if side == "N" then cz - d / 2 - WALL / 2 else cz + d / 2 + WALL / 2
			cf = at(floor, cx + mid, y, z)
			size = Vector3.new(len, y1 - y0, WALL)
		else
			local x = if side == "W" then cx - w / 2 - WALL / 2 else cx + w / 2 + WALL / 2
			cf = at(floor, x, y, cz + mid)
			size = Vector3.new(WALL, y1 - y0, len)
		end
		A.part(parent, size, cf, t.stone, t.material)
	end
	local cursor = -length / 2
	for _, o in openings do
		piece(cursor, o[1], 0, h)
		piece(o[1], o[2], math.min(DOOR_HEIGHT, h), h)
		cursor = o[2]
	end
	piece(cursor, length / 2, 0, h)
end

local function roomVolume(parent: Instance, floor: Floor, room: Room, index: number)
	local cx, cz = room.center[1], room.center[2]
	local w, h, d = room.size[1], room.size[2], room.size[3]
	marker(parent, `Room_{floor.index}_{index}`, Vector3.new(w, h, d), at(floor, cx, h / 2, cz))
end

local function buildRoom(parent: Instance, floor: Floor, room: Room, index: number, t: Theme)
	local model = Instance.new("Model")
	model.Name = `Room{index}_{room.id}`
	local cx, cz = room.center[1], room.center[2]
	local w, h, d = room.size[1], room.size[2], room.size[3]
	A.part(model, Vector3.new(w, 2, d), at(floor, cx, -1, cz), t.floor, t.floorMaterial)
	for _, side in { "N", "S", "E", "W" } do
		wall(model, floor, room, side, t)
	end
	ceiling(model, floor, room, t, floor.index * 1000 + index * 17 + 5)
	local seed = floor.index * 1000 + index * 17
	local rng = Random.new(seed)
	if room.kind == "Hall" then
		-- Candelabras against the walls between the chamber doors (no pillars:
		-- they would crowd the doorways).
		local doorZ = {}
		for _, door in room.doors do
			if door.side == "E" then
				table.insert(doorZ, cz + door.offset)
			end
		end
		table.sort(doorZ)
		for i, z in doorZ do
			local between = z + 26
			if i < #doorZ or between < cz + d / 2 - 10 then
				for _, s in { -1, 1 } do
					candelabra(
						model,
						at(floor, cx + s * (w / 2 - 3), 0, between),
						t,
						(i + (if s > 0 then 1 else 0)) % 2 == 0
					)
				end
			end
		end
		A.part(
			model,
			Vector3.new(3, 0.15, d - 20),
			at(floor, cx, 0.08, cz),
			t.glow,
			Enum.Material.Neon,
			{ decor = true, transparency = 0.35 }
		)
	elseif room.kind == "Chamber" then
		-- A small vault: rune ring under the mini boss, two crystals, one light.
		local mid = at(floor, cx, 0, cz)
		A.ring(model, 14, 0.8, 0.22, 28, mid, t.glow, Enum.Material.Neon, { decor = true })
		for _, s in { -1, 1 } do
			accent(model, at(floor, cx + s * (w / 2 - 6), 0, cz + s * (d / 2 - 6)), t, floor.theme, seed + s)
		end
		local lamp = marker(model, "Lamp", Vector3.new(1, 1, 1), at(floor, cx, h - 6, cz))
		light(lamp, t.glow, 40, 1.4)
	else
		-- Pillars down both long sides, candelabras between them.
		local pillars = math.max(2, math.floor(d / 26))
		for i = 0, pillars - 1 do
			local z = cz - d / 2 + (i + 0.5) * d / pillars
			for _, s in { -1, 1 } do
				A.column(model, at(floor, cx + s * (w / 2 - 2.5), 0, z), 1.6, h - 4, t.style)
			end
			if i % 2 == 1 then
				local lit = i % 4 == 1
				candelabra(model, at(floor, cx - (w / 2 - 7), 0, z + 6), t, lit)
				candelabra(model, at(floor, cx + (w / 2 - 7), 0, z - 6), t, not lit)
			end
		end
		if room.kind ~= "Start" then
			for i = 1, math.max(3, math.floor(w * d / 4000)) do
				local s = if i % 2 == 0 then 1 else -1
				local z = cz - d / 2 + rng:NextNumber(0.15, 0.85) * d
				accent(model, at(floor, cx + s * (w / 2 - 10), 0, z), t, floor.theme, seed + i)
				rubble(model, at(floor, cx - s * (w / 2 - 12), 0, z), t, seed + i * 3)
			end
		end
		if room.kind == "Lair" or room.kind == "Sanctum" then
			local mid = at(floor, cx, 0, cz + 20)
			A.ring(model, 28, 1.2, 0.25, 40, mid, t.glow, Enum.Material.Neon, { decor = true })
			A.ring(model, 19, 0.6, 0.22, 32, mid, t.trim, Enum.Material.Metal, { decor = true })
			for _, s in { -1, 1 } do
				local statue = at(floor, cx + s * (w / 2 - 16), 0, cz - d * 0.2)
				A.part(model, Vector3.new(8, 4, 8), statue * CFrame.new(0, 2, 0), t.stoneDark, t.material)
				A.part(model, Vector3.new(5, 12, 3.5), statue * CFrame.new(0, 10, 0), t.stone, t.material)
			end
			local crystal = A.part(
				model,
				Vector3.new(7, 22, 7),
				at(floor, cx + (if room.kind == "Lair" then 40 else 0), 13, cz + d / 2 - 10)
					* CFrame.Angles(0, math.rad(45), math.rad(8)),
				t.glow,
				Enum.Material.Neon,
				{ decor = true, transparency = 0.15 }
			)
			light(crystal, t.glow, 60, 2)
		end
	end
	roomVolume(model, floor, room, index)
	model.Parent = parent
end

local function buildPassage(
	parent: Instance,
	floor: Floor,
	passage: DungeonDefinitions.Passage,
	index: number,
	t: Theme
)
	local model = Instance.new("Model")
	model.Name = `Passage{index}`
	local cx, cz = passage.center[1], passage.center[2]
	local w, d = passage.size[1], passage.size[2]
	local height = DOOR_HEIGHT + 2
	A.part(model, Vector3.new(w, 2, d), at(floor, cx, -1, cz), t.floor, t.floorMaterial)
	if passage.axis == "Z" then
		for _, s in { -1, 1 } do
			A.part(
				model,
				Vector3.new(WALL, height, d),
				at(floor, cx + s * (w / 2 + WALL / 2), height / 2, cz),
				t.stone,
				t.material
			)
		end
		A.part(
			model,
			Vector3.new(w + WALL * 2, 3, d),
			at(floor, cx, height + 1.5, cz),
			t.stoneDark,
			t.material
		)
		if d >= 30 then
			candelabra(model, at(floor, cx - (w / 2 - 2), 0, cz), t, true)
		end
	else
		for _, s in { -1, 1 } do
			A.part(
				model,
				Vector3.new(w, height, WALL),
				at(floor, cx, height / 2, cz + s * (d / 2 + WALL / 2)),
				t.stone,
				t.material
			)
		end
		A.part(
			model,
			Vector3.new(w, 3, d + WALL * 2),
			at(floor, cx, height + 1.5, cz),
			t.stoneDark,
			t.material
		)
	end
	model.Parent = parent
end

-- A portal gate at floor-frame (x, z); `facingDeeper` turns it toward +z.
local function portal(
	parent: Instance,
	floor: Floor,
	point: { number },
	label: string,
	name: string,
	facingDeeper: boolean,
	t: Theme
): BasePart
	local cf = at(floor, point[1], 0, point[2])
		* (if facingDeeper then CFrame.Angles(0, math.pi, 0) else CFrame.new())
	local surface = A.portalGate(parent, cf, { label = label, opensIn = "", active = true }, t.style)
	surface.Name = name
	return surface
end

local function buildFloor(parent: Instance, dungeon: DungeonDefinitions.Dungeon, floor: Floor)
	local t = THEMES[floor.theme] or THEMES.Crystal
	local model = Instance.new("Model")
	model.Name = `Floor_{floor.index}`
	for index, room in floor.rooms do
		buildRoom(model, floor, room, index, t)
	end
	for index, passage in floor.passages do
		buildPassage(model, floor, passage, index, t)
	end
	marker(
		model,
		`Arrival_{floor.index}`,
		Vector3.new(4, 1, 4),
		at(floor, floor.arrival[1], 3, floor.arrival[2])
	)
	portal(model, floor, floor.leavePortal, "Leave Dungeon", `Leave_{floor.index}`, true, t)
	if floor.upPortal then
		portal(model, floor, floor.upPortal, `Up to Floor {floor.index - 1}`, `Up_{floor.index}`, true, t)
	end
	if floor.downPortal then
		portal(
			model,
			floor,
			floor.downPortal,
			`Down to Floor {floor.index + 1}`,
			`Down_{floor.index}`,
			false,
			t
		)
	end
	local _ = dungeon
	model.Parent = parent
end

--[[
	Builds every floor of `dungeon` (unparented Model, PrimaryPart "Origin"
	at floor 1's landing entry, floor top y = 0).
]]
function DungeonBuilder.build(dungeon: DungeonDefinitions.Dungeon): Model
	local model = Instance.new("Model")
	model.Name = `Dungeon_{dungeon.id}`
	local origin = marker(model, "Origin", Vector3.new(1, 1, 1), CFrame.new(0, 0.5, 0))
	model.PrimaryPart = origin
	for _, floor in dungeon.floors do
		buildFloor(model, dungeon, floor)
	end
	return model
end

-- Copy-frame CFrame of floor-frame point (x, z) on `floor`, facing the entry.
function DungeonBuilder.pointCFrame(floor: Floor, x: number, z: number): CFrame
	local position = Vector3.new(floor.offsetX + x, 0, -z)
	return CFrame.lookAt(position, position + Vector3.new(0, 0, 1))
end

-- Copy-frame CFrame of a camp spot (relative to its room's centre).
function DungeonBuilder.campCFrame(floor: Floor, room: Room, x: number, z: number): CFrame
	return DungeonBuilder.pointCFrame(floor, room.center[1] + x, room.center[2] + z)
end

return DungeonBuilder
