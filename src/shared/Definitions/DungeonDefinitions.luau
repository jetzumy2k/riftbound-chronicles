--!strict
--[[
	DungeonDefinitions — dungeon layouts, creature camps and bosses
	(CLAUDE.md §11, PLAN.md Phase 9, D-42).

	Each realm has one persistent copy of a dungeon that every player of that
	realm shares. A dungeon is a run of open rooms joined by corridors, built
	along -Z ("deeper"). Each room:
	  size   {width, height, depth} studs
	  camps  creature groups in the room's frame {x, z} (x right, z forward
	         from the room's entry edge), each with a respawn class:
	           Mob       respawns Dungeon.MobRespawnSeconds after falling
	           MiniBoss  respawns after Dungeon.MiniBossRespawnMinutes
	           Boss      respawns after Dungeon.BossRespawnHours
	  boss   the boss definition used by this room's Boss camp

	Boss abilities are telegraphed on the ground before they land:
	  Circle  {radius} at the targeted player's position
	  Cone    {radius, angle} in front of the boss
	  Ring    {inner, radius} around the boss (stand close to dodge)
	  Summon  spawns `count` of `enemy` near the boss
	Phases switch at HP fractions; later phases add abilities and speed.

	Display-safe data only. Pure module.
]]

export type RespawnClass = "Mob" | "MiniBoss" | "Boss"

export type Camp = { enemy: string, x: number, z: number, count: number, class: RespawnClass }

export type Room = {
	id: string,
	name: string,
	size: { number },
	camps: { Camp },
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
	corridorLength: number,
	corridorWidth: number,
	rooms: { Room },
	-- One-time EXP for everyone who helped defeat a MiniBoss / Boss spawn.
	miniBossBonusXp: number,
	bossBonusXp: number,
	-- Atmosphere preset (ZoneAtmosphere) inside the dungeon.
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
		corridorLength = 60,
		corridorWidth = 28,
		miniBossBonusXp = 120,
		bossBonusXp = 400,
		atmosphere = "Dungeon",
		rooms = {
			{
				id = "EntryHall",
				name = "Shattered Entry Hall",
				size = { 140, 46, 150 },
				camps = {
					{ enemy = "RiftWolf", x = -34, z = 45, count = 3, class = "Mob" },
					{ enemy = "RiftWolf", x = 36, z = 70, count = 3, class = "Mob" },
					{ enemy = "RiftWolf", x = -10, z = 112, count = 2, class = "Mob" },
				},
			},
			{
				id = "CrystalGallery",
				name = "Crystal Gallery",
				size = { 170, 54, 200 },
				camps = {
					{ enemy = "CrystalBeetle", x = -50, z = 45, count = 2, class = "Mob" },
					{ enemy = "CrystalBeetle", x = 50, z = 60, count = 2, class = "Mob" },
					{ enemy = "RiftWolf", x = -45, z = 120, count = 3, class = "Mob" },
					{ enemy = "RiftWolf", x = 45, z = 130, count = 3, class = "Mob" },
					{ enemy = "StonebackGuardian", x = 0, z = 170, count = 1, class = "MiniBoss" },
				},
			},
			{
				id = "GuardianSanctum",
				name = "Guardian's Sanctum",
				size = { 190, 72, 190 },
				boss = "RiftGuardian",
				camps = {
					{ enemy = "RiftGuardian", x = 0, z = 120, count = 1, class = "Boss" },
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

-- Z offset (studs, along -Z from the dungeon origin) of each room's entry edge.
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

-- Index of the room containing local depth `z` (studs from the origin,
-- positive = deeper), or nil in a corridor / outside.
function DungeonDefinitions.roomAt(dungeon: Dungeon, z: number): number?
	for index, offset in DungeonDefinitions.roomOffsets(dungeon) do
		if z >= offset and z <= offset + dungeon.rooms[index].size[3] then
			return index
		end
	end
	return nil
end

return table.freeze(DungeonDefinitions)
