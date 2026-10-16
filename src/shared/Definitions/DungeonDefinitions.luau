--!strict
--[[
	DungeonDefinitions — dungeon layouts, objectives and bosses
	(CLAUDE.md §11, PLAN.md Phase 9).

	A dungeon is a straight run of rooms joined by corridors, built along
	the instance's -Z ("forward" = deeper). Each room:
	  size        {width, height, depth} studs
	  spawns      enemies placed in the room's local frame {x, z} (x right,
	              z forward from the room's entry edge)
	  objective   text shown in the tracker while the room is active
	  checkpoint  defeated players with rejoin charges respawn at the entry
	              of the latest room that is reached (D-20)
	Clearing a room opens the door to the next. The last room holds the boss;
	defeating it clears the dungeon.

	Boss abilities are telegraphed on the ground before they land:
	  Circle  {radius} at the targeted player's position
	  Cone    {radius, angle} in front of the boss
	  Ring    {inner, radius} around the boss (stand close to dodge)
	  Summon  spawns `count` of `enemy` near the boss
	Phases switch at HP fractions; later phases add abilities and speed.

	Display-safe data only. Pure module.
]]

export type Spawn = { enemy: string, x: number, z: number }

export type Room = {
	id: string,
	name: string,
	size: { number },
	spawns: { Spawn },
	objective: string,
	boss: string?,
}

export type Ability = {
	id: string,
	shape: "Circle" | "Cone" | "Ring" | "Summon",
	radius: number?,
	inner: number?,
	angle: number?,
	telegraph: number,
	coefficient: number?,
	enemy: string?,
	count: number?,
}

export type Phase = {
	untilHpFraction: number,
	abilities: { string },
	cooldown: number,
	speedScale: number,
	announce: string?,
}

export type Boss = {
	id: string,
	enemy: string,
	abilities: { [string]: Ability },
	phases: { Phase },
}

export type Dungeon = {
	id: string,
	name: string,
	minLevel: number,
	maxParty: number,
	corridorLength: number,
	rooms: { Room },
	clearXp: number,
	-- Atmosphere preset (ZoneAtmosphere) inside the instance.
	atmosphere: string,
}

local DungeonDefinitions = {}

local bosses: { [string]: Boss } = {
	RiftGuardian = {
		id = "RiftGuardian",
		enemy = "RiftGuardian",
		abilities = {
			Slam = { id = "Slam", shape = "Circle", radius = 9, telegraph = 1.3, coefficient = 0.7 },
			Sweep = {
				id = "Sweep",
				shape = "Cone",
				radius = 16,
				angle = 100,
				telegraph = 1.1,
				coefficient = 0.6,
			},
			Shockwave = {
				id = "Shockwave",
				shape = "Ring",
				inner = 9,
				radius = 30,
				telegraph = 1.6,
				coefficient = 0.8,
			},
			CallWolves = {
				id = "CallWolves",
				shape = "Summon",
				enemy = "RiftWolf",
				count = 2,
				telegraph = 1.2,
			},
		},
		phases = {
			{ untilHpFraction = 0.6, abilities = { "Slam", "Sweep" }, cooldown = 4.5, speedScale = 1 },
			{
				untilHpFraction = 0.25,
				abilities = { "Slam", "Sweep", "CallWolves" },
				cooldown = 3.8,
				speedScale = 1.1,
				announce = "The Rift Guardian calls the pack!",
			},
			{
				untilHpFraction = 0,
				abilities = { "Slam", "Sweep", "Shockwave" },
				cooldown = 3,
				speedScale = 1.25,
				announce = "The Rift Guardian is enraged! Stay close to dodge the shockwave.",
			},
		},
	},
}

local dungeons: { [string]: Dungeon } = {
	RiftHollow = {
		id = "RiftHollow",
		name = "Rift Hollow",
		minLevel = 1,
		maxParty = 4,
		corridorLength = 40,
		clearXp = 250,
		atmosphere = "Dungeon",
		rooms = {
			{
				id = "EntryHall",
				name = "Shattered Entry Hall",
				size = { 70, 34, 80 },
				objective = "Defeat the Rift Wolves",
				spawns = {
					{ enemy = "RiftWolf", x = -14, z = 40 },
					{ enemy = "RiftWolf", x = 14, z = 44 },
					{ enemy = "RiftWolf", x = 0, z = 62 },
				},
			},
			{
				id = "CrystalGallery",
				name = "Crystal Gallery",
				size = { 80, 40, 100 },
				objective = "Clear the Crystal Gallery",
				spawns = {
					{ enemy = "CrystalBeetle", x = -20, z = 34 },
					{ enemy = "CrystalBeetle", x = 20, z = 38 },
					{ enemy = "RiftWolf", x = -8, z = 56 },
					{ enemy = "RiftWolf", x = 10, z = 58 },
					{ enemy = "StonebackGuardian", x = 0, z = 78 },
				},
			},
			{
				id = "GuardianSanctum",
				name = "Guardian's Sanctum",
				size = { 110, 56, 110 },
				objective = "Defeat the Rift Guardian",
				boss = "RiftGuardian",
				spawns = {
					{ enemy = "RiftGuardian", x = 0, z = 70 },
				},
			},
		},
	},
}

local function deepFreeze(value: any): any
	if type(value) == "table" and not table.isfrozen(value) then
		for _, child in value do
			deepFreeze(child)
		end
		table.freeze(value)
	end
	return value
end

DungeonDefinitions.ById = deepFreeze(dungeons) :: { [string]: Dungeon }
DungeonDefinitions.Bosses = deepFreeze(bosses) :: { [string]: Boss }

function DungeonDefinitions.get(id: any): Dungeon?
	if type(id) ~= "string" then
		return nil
	end
	return DungeonDefinitions.ById[id]
end

function DungeonDefinitions.boss(id: any): Boss?
	if type(id) ~= "string" then
		return nil
	end
	return DungeonDefinitions.Bosses[id]
end

-- Z offset (studs, along -Z from the instance origin) of each room's entry edge.
function DungeonDefinitions.roomOffsets(dungeon: Dungeon): { number }
	local offsets = {}
	local z = 0
	for _, room in dungeon.rooms do
		table.insert(offsets, z)
		z += room.size[3] + dungeon.corridorLength
	end
	return offsets
end

-- Total length of the dungeon in studs.
function DungeonDefinitions.length(dungeon: Dungeon): number
	local offsets = DungeonDefinitions.roomOffsets(dungeon)
	local last = dungeon.rooms[#dungeon.rooms]
	return offsets[#offsets] + last.size[3]
end

return table.freeze(DungeonDefinitions)
