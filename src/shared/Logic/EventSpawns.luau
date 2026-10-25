--!strict
--[[
	EventSpawns — what the world events bring into the war zones (Phase 18
	stage 2, PLAN.md D-91). Pure; positions are relative to a war zone's
	centre, clear of the realm camps (bases) and the zone's own boss posts.

	  RiftBeastInvasion  six packs of Rift Wolves led by a Rift Guardian
	                     (level 32-33) on a ring round the oasis
	  EliteSwarm         an elite (the zone's golem) beside every other
	                     creature camp, a level above it
	  MythicalInvasion   two bosses from the other war zone
	  NullbornWorldBoss  the Nullborn Herald

	Event creatures don't respawn; whatever is left when the event ends
	leaves with it (WorldEventService).
]]

local WorldLayout = require(script.Parent.Parent.Definitions.WorldLayout)

local EventSpawns = {}

export type Spawn = { kind: "Boss" | "Creature", enemy: string, level: number?, x: number, z: number }

EventSpawns.ZONES = table.freeze({ "DesertRift", "JungleRift" })

-- Six points on a ring round the oasis, away from the camps north and south.
local PACK_RADIUS = 260
local PACK_ANGLES = { 0, 45, 135, 180, 225, 315 }
EventSpawns.INVADER_POINTS = table.freeze({ { -150, 120 }, { 150, 120 } })
EventSpawns.HERALD_POINT = table.freeze({ 180, -60 })

local ELITE_OF = { DesertRift = "SandstoneGolem", JungleRift = "MossbackGolem" }
local OTHER_ZONE = { DesertRift = "JungleRift", JungleRift = "DesertRift" }

local function zone(zoneId: string): any
	return (WorldLayout.WarZones :: any)[zoneId]
end

-- What event `eventId` spawns in war zone `zoneId` (empty when nothing).
function EventSpawns.plan(eventId: string, zoneId: string): { Spawn }
	local out: { Spawn } = {}
	local z = zone(zoneId)
	if z == nil then
		return out
	end
	if eventId == "RiftBeastInvasion" then
		for _, degrees in PACK_ANGLES do
			local a = math.rad(degrees)
			local cx, cz =
				math.floor(math.cos(a) * PACK_RADIUS + 0.5), math.floor(math.sin(a) * PACK_RADIUS + 0.5)
			for i = 1, 3 do
				local b = i * math.pi * 2 / 3
				table.insert(out, {
					kind = "Creature",
					enemy = "RiftWolf",
					level = 32,
					x = cx + math.floor(math.cos(b) * 7 + 0.5),
					z = cz + math.floor(math.sin(b) * 7 + 0.5),
				})
			end
			table.insert(out, { kind = "Creature", enemy = "RiftGuardian", level = 33, x = cx, z = cz })
		end
	elseif eventId == "EliteSwarm" then
		for index, camp in z.camps do
			if index % 2 == 1 then
				table.insert(out, {
					kind = "Creature",
					enemy = ELITE_OF[zoneId],
					level = math.min(camp.level + 1, 35),
					x = camp.x + 12,
					z = camp.z,
				})
			end
		end
	elseif eventId == "MythicalInvasion" then
		local other = zone(OTHER_ZONE[zoneId])
		for i, point in EventSpawns.INVADER_POINTS do
			local spec = other.bosses[(i - 1) * 2 + 1]
			table.insert(out, { kind = "Boss", enemy = spec.enemy, x = point[1], z = point[2] })
		end
	elseif eventId == "NullbornWorldBoss" then
		local p = EventSpawns.HERALD_POINT
		table.insert(out, { kind = "Boss", enemy = "NullbornHerald", x = p[1], z = p[2] })
	end
	return out
end

return EventSpawns
