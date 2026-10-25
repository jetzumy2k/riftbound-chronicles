--!strict
--[[
	WorldEventService (Layer 6) — the world events' creatures (Phase 18
	stage 2, PLAN.md D-91).

	Follows EventService's running list: when Rift Beast Invasion, Elite
	Mob Swarm, Mythical Boss Invasion or the Nullborn World Boss starts, it
	spawns that event's creatures in both war zones (Logic/EventSpawns,
	through PvPService so they pay stones / boss loot and Marks like the
	zone's own); when the event ends, whatever is still standing leaves. A
	server that starts mid-event spawns them at once. Boss Frenzy is applied
	by PvPService (respawn delay), the weather events (Desert Storm, Jungle
	Flood, Rift Eclipse) by the client's AtmosphereController.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local EventSpawns = require(Shared.Logic.EventSpawns)
local EventRules = require(Shared.Logic.EventRules)
local Log = require(Shared.Util.Log)

local NetService = require(script.Parent.NetService)
local EventService = require(script.Parent.EventService)
local MobService = require(script.Parent.MobService)
local PvPService = require(script.Parent.PvPService)

local log = Log.new("WorldEventService")

local WorldEventService = {}

type Spawned = { creatures: { MobService.Mob }, bosses: { MobService.Mob } }

local active: { [string]: Spawned } = {}

local function start(id: string)
	local spawned: Spawned = { creatures = {}, bosses = {} }
	local count = 0
	for _, zoneId in EventSpawns.ZONES do
		for _, spec in EventSpawns.plan(id, zoneId) do
			local mob = if spec.kind == "Boss"
				then PvPService:SpawnEventBoss(zoneId, spec.enemy, spec.x, spec.z)
				else PvPService:SpawnEventCreature(zoneId, spec.enemy, spec.level or 30, spec.x, spec.z)
			if mob then
				count += 1
				table.insert(if spec.kind == "Boss" then spawned.bosses else spawned.creatures, mob)
			end
		end
	end
	if count == 0 then
		return
	end
	active[id] = spawned
	log:Info("%s: %d creatures spawned", id, count)
	if id == "NullbornWorldBoss" then
		NetService:FireClients(
			"Notify",
			Players:GetPlayers(),
			{ kind = "Warning", textKey = "event.worldBoss" }
		)
	elseif id == "MythicalInvasion" then
		NetService:FireClients(
			"Notify",
			Players:GetPlayers(),
			{ kind = "Warning", textKey = "event.invasion" }
		)
	end
end

local function stop(id: string)
	local spawned = active[id]
	active[id] = nil
	if spawned == nil then
		return
	end
	for _, mob in spawned.bosses do
		if not mob.dead then
			PvPService:DespawnEventBoss(mob)
		end
	end
	for _, mob in spawned.creatures do
		if not mob.dead then
			MobService:Despawn(mob)
		end
	end
	log:Info("%s: ended", id)
end

local function sync(running: { EventRules.Window })
	local now: { [string]: boolean } = {}
	for _, w in running do
		now[w.Id] = true
		if active[w.Id] == nil and #EventSpawns.plan(w.Id, EventSpawns.ZONES[1]) > 0 then
			start(w.Id)
		end
	end
	for id in active do
		if not now[id] then
			stop(id)
		end
	end
end

function WorldEventService:Start()
	EventService.Changed:Connect(sync)
	sync(EventService:GetRunning())
end

return WorldEventService
