--!strict
--[[
	TowerService (Layer 6) — the Tower Challenge (creator request
	2026-10-30, PLAN.md D-131; rules in Logic/TowerRules). The 🗼 Tower
	Keeper stands in each capital (built by ShopService with the other
	town NPCs).

	Open only while the "Tower Challenge" event runs (EventService). The
	admin's weekly schedule (Events.Tower) starts that event by itself,
	15 minutes early as "starting soon"; every server checks and the
	config's version check lets one write win.

	Remote Tower:
	  Status  the floors (open or not, cleared, best time), Tower points,
	          when the Tower is open / opens next
	  Enter   start floor <id>: the player alone, or a party leader with
	          the members standing near them (each must be level enough).
	          They go to a sealed arena of their own (TowerBuilder) and
	          fight its waves against the clock
	  Leave   leave the run (back to the capital)
	  Board   the week's 3 fastest clears of a floor (all servers)

	A run fails when everyone is down or gone, time runs out or the Tower
	closes. A clear gives each player still in the arena the floor's
	points on their first clear only (claim T:<floor>), keeps their best
	time, and enters the week's board when nobody was above the band
	(OrderedDataStore per week and floor, key "<user>_<slot>", the best
	time in tenths). Last week's top 3 of each floor get the floor's
	points again on their next visit (claim TW:<week>:<floor>). Creature
	EXP follows the usual rules (MobService); the Tower drops no loot.
	Audit logged.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local TowerRules = require(Shared.Logic.TowerRules)
local WorldLayout = require(Shared.Definitions.WorldLayout)
local Log = require(Shared.Util.Log)

local ProfileView = require(script.Parent.Parent.Persistence.ProfileView)
local TowerBuilder = require(script.Parent.Parent.World.TowerBuilder)
local ConfigurationService = require(script.Parent.ConfigurationService)
local AuditLogService = require(script.Parent.AuditLogService)
local NetService = require(script.Parent.NetService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local EventService = require(script.Parent.EventService)
local TravelService = require(script.Parent.TravelService)
local MobService = require(script.Parent.MobService)
local PartyService = require(script.Parent.PartyService)
local DungeonService = require(script.Parent.DungeonService)
local ShopService = require(script.Parent.ShopService)

local log = Log.new("TowerService")

local NPC = "Tower"
-- The dungeon slot the arenas use (slots 1-4: the two dungeons' copies).
local ARENA_SLOT = 6
local ARENA_SPACING = 400
local MAX_RUNS = 16
-- A party member must stand this close to the leader to come along.
local PARTY_REACH = 40
-- Seconds the result shows before everyone goes back.
local RESULT_SECONDS = 12
-- Seconds a week's board stays cached on this server.
local BOARD_SECONDS = 60

type Run = {
	id: number,
	slot: number,
	floor: TowerRules.Floor,
	origin: Vector3,
	model: Model,
	players: { Player },
	levels: { number },
	wave: number,
	phase: string,
	mobs: { MobService.Mob },
	startedAt: number,
	nextWaveAt: number,
	-- Between waves (the next one at nextWaveAt).
	waiting: boolean,
	-- Until then a player not yet in the arena is still arriving.
	arriveBy: number,
	ended: boolean,
}

local TowerService = {}

local runs: { [number]: Run } = {}
local runOf: { [Player]: Run } = {}
local slotsUsed: { [number]: boolean } = {}
local nextRunId = 0
local folder: Folder? = nil
local storesOk = true
local boards: { [string]: { at: number, entries: { { key: string, tenths: number } } } } = {}
local names: { [number]: string } = {}

local function notify(player: Player, kind: string, key: string, params: { [string]: string }?)
	NetService:FireClient("Notify", player, { kind = kind, textKey = key, params = params })
end

local function level60(): boolean
	return ConfigurationService:Get("Progression").Level60 == true
end

-- The running Tower Challenge window, or nil (closed).
local function openWindow(): any
	for _, w in EventService:GetRunning() do
		if w.Id == TowerRules.EVENT_ID then
			return w
		end
	end
	return nil
end

local function alive(player: Player): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function characterKey(player: Player, data: { [string]: any }): string
	return `{player.UserId}_{data.ActiveSlot or 1}`
end

local function storeName(week: number, floorId: string): string
	return `RC_TowerW{week}_{floorId}`
end

--------------------------------------------------------------------------------
-- The week's board (OrderedDataStore, all servers)
--------------------------------------------------------------------------------

local function topOf(week: number, floorId: string, fresh: boolean?): { { key: string, tenths: number } }
	local cacheKey = `{week}:{floorId}`
	local cached = boards[cacheKey]
	-- A past week never changes: kept for good once read.
	local thisWeek = week == TowerRules.weekOf(os.time())
	if cached and not fresh and (not thisWeek or os.clock() - cached.at < BOARD_SECONDS) then
		return cached.entries
	end
	local entries = {}
	if storesOk then
		local ok, err = pcall(function()
			local store = DataStoreService:GetOrderedDataStore(storeName(week, floorId))
			local page = store:GetSortedAsync(true, TowerRules.TOP):GetCurrentPage()
			for _, item in page do
				table.insert(entries, { key = item.key, tenths = item.value })
			end
		end)
		if not ok then
			log:Warn("board %s week %d unavailable: %s", floorId, week, tostring(err))
			return if cached then cached.entries else {}
		end
	end
	boards[cacheKey] = { at = os.clock(), entries = entries }
	return entries
end

local function nameOf(key: string): string
	local userId = tonumber(string.match(key, "^(%-?%d+)_"))
	if userId == nil then
		return "?"
	end
	local known = names[userId]
	if known then
		return known
	end
	local player = Players:GetPlayerByUserId(userId)
	local name = if player then player.Name else nil
	if name == nil then
		local ok, result = pcall(function()
			return Players:GetNameFromUserIdAsync(userId)
		end)
		name = if ok and type(result) == "string" then result else `Player {userId}`
	end
	names[userId] = name :: string
	return name :: string
end

-- Saves a clear time to the week's board (kept only if faster).
local function record(key: string, floorId: string, tenths: number)
	if not storesOk then
		return
	end
	local week = TowerRules.weekOf(os.time())
	local ok, err = pcall(function()
		local store = DataStoreService:GetOrderedDataStore(storeName(week, floorId))
		store:UpdateAsync(key, function(old: number?): number?
			if type(old) == "number" and old <= tenths then
				return nil
			end
			return tenths
		end)
	end)
	if ok then
		boards[`{week}:{floorId}`] = nil
	else
		log:Warn("record %s %s failed: %s", key, floorId, tostring(err))
	end
end

local function pushAttributes(player: Player, data: { [string]: any })
	NetService:FireClient("AttributesUpdate", player, ProfileView.attributes(data))
end

-- Gives `points` Tower points under claim `claimId` (once).
local function givePoints(player: Player, claimId: string, floor: TowerRules.Floor): number
	local given = 0
	local status = (PlayerDataService :: any):ClaimReward(player, claimId, function(data)
		given = TowerRules.grantable(floor, data.TowerPoints or 0)
		data.TowerPoints = (data.TowerPoints or 0) + given
	end)
	if status ~= "granted" then
		return 0
	end
	local data = PlayerDataService:GetData(player)
	if data then
		pushAttributes(player, data)
	end
	return given
end

-- Last week's top 3 places of floors this character cleared (once each).
local function claimWeekly(player: Player)
	local data = PlayerDataService:GetData(player)
	if data == nil then
		return
	end
	local week = TowerRules.weekOf(os.time()) - 1
	local key = characterKey(player, data)
	for _, floor in TowerRules.FLOORS do
		local claimId = `TW:{week}:{floor.id}`
		if data.ClaimedRewardIds[`T:{floor.id}`] == nil or data.ClaimedRewardIds[claimId] ~= nil then
			continue
		end
		for place, entry in topOf(week, floor.id) do
			if entry.key == key then
				if player.Parent ~= Players or PlayerDataService:GetData(player) ~= data then
					return
				end
				local given = givePoints(player, claimId, floor)
				AuditLogService:Audit({
					actorUserId = player.UserId,
					action = "TowerWeeklyTop",
					target = floor.id,
					details = { week = week, place = place, points = given },
				})
				notify(player, "Success", "tower.top", {
					place = tostring(place),
					floor = floor.id,
					points = tostring(given),
				})
				break
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Runs
--------------------------------------------------------------------------------

local function statePayload(run: Run, extra: { [string]: any }?): { [string]: any }
	local elapsed = if run.startedAt > 0 then os.clock() - run.startedAt else 0
	local payload = {
		Floor = run.floor.id,
		Phase = run.phase,
		Wave = run.wave,
		Waves = #run.floor.waves,
		Elapsed = math.clamp(elapsed, 0, 100000),
		Limit = run.floor.limitSeconds,
	}
	if extra then
		for k, v in extra do
			(payload :: any)[k] = v
		end
	end
	return payload
end

local function push(run: Run, extra: { [string]: any }?)
	for _, player in run.players do
		if player.Parent == Players then
			NetService:FireClient("TowerState", player, statePayload(run, extra))
		end
	end
end

local function sendHome(player: Player)
	if player.Parent ~= Players or not alive(player) then
		return
	end
	local home = TravelService:GetHomeCFrame(player)
	if home then
		task.spawn(function()
			TravelService:Teleport(player, home)
		end)
	end
end

-- Takes `player` out of `run` (they keep what they earned).
local function drop(run: Run, player: Player, why: string)
	local index = table.find(run.players, player)
	if index then
		table.remove(run.players, index)
	end
	if runOf[player] == run then
		runOf[player] = nil
	end
	if player.Parent == Players then
		NetService:FireClient("TowerState", player, statePayload(run, { Phase = "Gone", Why = why }))
	end
end

local function cleanup(run: Run)
	MobService:DespawnOwner(`tower:{run.id}`)
	run.model:Destroy()
	runs[run.id] = nil
	slotsUsed[run.slot] = nil
	for player, r in runOf do
		if r == run then
			runOf[player] = nil
		end
	end
end

local function fail(run: Run, why: string)
	if run.ended then
		return
	end
	run.ended = true
	run.phase = "Failed"
	push(run, { Why = why })
	AuditLogService:Audit({
		actorUserId = 0,
		action = "TowerFailed",
		target = run.floor.id,
		details = { why = why, wave = run.wave, players = #run.players },
	})
	local players = table.clone(run.players)
	MobService:DespawnOwner(`tower:{run.id}`)
	task.delay(4, function()
		for _, player in players do
			if runOf[player] == run then
				sendHome(player)
			end
		end
		cleanup(run)
	end)
end

local function clear(run: Run)
	if run.ended then
		return
	end
	run.ended = true
	run.phase = "Cleared"
	local tenths = TowerRules.tenths(os.clock() - run.startedAt)
	local board = TowerRules.countsForBoard(run.floor, run.levels)
	for _, player in run.players do
		local data = PlayerDataService:GetData(player)
		if data == nil or player.Parent ~= Players then
			continue
		end
		local points = givePoints(player, `T:{run.floor.id}`, run.floor)
		local before = data.TowerBest[run.floor.id]
		local best = before == nil or tenths < before
		if best then
			data.TowerBest[run.floor.id] = tenths
		end
		if board then
			local key = characterKey(player, data)
			task.spawn(record, key, run.floor.id, tenths)
		end
		NetService:FireClient(
			"TowerState",
			player,
			statePayload(run, { Points = points, Time = tenths, Best = best })
		)
		if points > 0 then
			notify(player, "Success", "tower.points", { floor = run.floor.id, points = tostring(points) })
		end
		AuditLogService:Audit({
			actorUserId = player.UserId,
			action = "TowerCleared",
			target = run.floor.id,
			details = { tenths = tenths, points = points, board = board, players = #run.players },
		})
	end
	log:Info("run %d cleared %s in %s", run.id, run.floor.id, TowerRules.formatTenths(tenths))
	local players = table.clone(run.players)
	task.delay(RESULT_SECONDS, function()
		for _, player in players do
			if runOf[player] == run then
				sendHome(player)
			end
		end
		cleanup(run)
	end)
end

local function spawnWave(run: Run)
	run.wave += 1
	run.phase = "Fight"
	run.mobs = {}
	local hp = TowerRules.partyHpScale(#run.players)
	local wave = run.floor.waves[run.wave]
	local total = 0
	for _, group in wave do
		total += group.count
	end
	local index = 0
	local recipients = function()
		local out = {}
		for _, player in run.players do
			if player.Parent == Players and alive(player) then
				table.insert(out, player)
			end
		end
		return out
	end
	for _, group in wave do
		for _ = 1, group.count do
			index += 1
			local mob = MobService:Spawn(group.enemy, TowerBuilder.spawnPoint(run.origin, index, total), {
				owner = `tower:{run.id}`,
				level = run.floor.level,
				hpScale = hp * (group.hpScale or 1),
				xpRecipients = recipients,
			})
			if mob then
				table.insert(run.mobs, mob)
			end
		end
	end
	push(run)
end

local function tickRun(run: Run, now: number)
	if run.ended then
		return
	end
	-- Who is still in: in the game, alive and inside the arena.
	for i = #run.players, 1, -1 do
		local player = run.players[i]
		local root = rootOf(player)
		-- Arriving takes a moment (the teleport streams the arena in).
		local outside = now >= run.arriveBy
			and root ~= nil
			and not TowerBuilder.inside(run.origin, root.Position)
		if player.Parent ~= Players or outside then
			drop(run, player, "left")
		elseif not alive(player) then
			-- Defeated: they respawn at home as usual.
			drop(run, player, "down")
		end
	end
	if #run.players == 0 then
		fail(run, "wiped")
		return
	end
	if openWindow() == nil then
		fail(run, "closed")
		for _, player in table.clone(run.players) do
			notify(player, "Warning", "tower.closed")
		end
		return
	end
	if run.startedAt > 0 and now - run.startedAt > run.floor.limitSeconds then
		fail(run, "time")
		return
	end
	if run.phase == "Countdown" then
		if now >= run.nextWaveAt then
			run.startedAt = now
			spawnWave(run)
		end
		return
	end
	for _, mob in run.mobs do
		if not mob.dead then
			return
		end
	end
	if run.wave >= #run.floor.waves then
		clear(run)
	elseif not run.waiting then
		-- The wave just fell: the next one after a short breath.
		run.waiting = true
		run.nextWaveAt = now + TowerRules.WAVE_GAP_SECONDS
	elseif now >= run.nextWaveAt then
		run.waiting = false
		spawnWave(run)
	end
end

local function freeSlot(): number?
	for slot = 1, MAX_RUNS do
		if not slotsUsed[slot] then
			return slot
		end
	end
	return nil
end

local function enter(player: Player, data: { [string]: any }, floor: TowerRules.Floor): { [string]: any }
	if openWindow() == nil then
		return { ok = false, reason = "closed" }
	end
	if runOf[player] then
		return { ok = false, reason = "inRun" }
	end
	if DungeonService:IsInRun(player) then
		return { ok = false, reason = "dungeon" }
	end
	local ok, why = TowerRules.canEnter(floor, data.Level or 0, level60())
	if not ok then
		return { ok = false, reason = why }
	end
	-- A party goes in together, started by its leader.
	local members = PartyService:GetMembers(player)
	if #members > 1 and PartyService:GetLeader(player) ~= player then
		return { ok = false, reason = "leader" }
	end
	local root = rootOf(player)
	if root == nil or not alive(player) then
		return { ok = false, reason = "dead" }
	end
	local going: { Player } = { player }
	local levels: { number } = { data.Level or 0 }
	local leftBehind = 0
	for _, member in members do
		if member == player then
			continue
		end
		local memberData = PlayerDataService:GetData(member)
		local memberRoot = rootOf(member)
		local near = memberRoot ~= nil and (memberRoot.Position - root.Position).Magnitude <= PARTY_REACH
		local memberOk = memberData ~= nil
			and near
			and alive(member)
			and runOf[member] == nil
			and not DungeonService:IsInRun(member)
			and TowerRules.canEnter(floor, memberData.Level or 0, level60())
		if memberOk then
			table.insert(going, member)
			table.insert(levels, (memberData :: any).Level or 0)
		else
			leftBehind += 1
		end
	end
	local slot = freeSlot()
	if slot == nil then
		return { ok = false, reason = "busy" }
	end
	nextRunId += 1
	local base = WorldLayout.dungeonSlotOrigin(ARENA_SLOT)
	local origin = Vector3.new(base[1], base[2], base[3] + (slot - 1) * ARENA_SPACING)
	local model = TowerBuilder.build(`{nextRunId}`, origin, floor.band)
	model.Parent = folder
	slotsUsed[slot] = true
	local run: Run = {
		id = nextRunId,
		slot = slot,
		floor = floor,
		origin = origin,
		model = model,
		players = going,
		levels = levels,
		wave = 0,
		phase = "Countdown",
		mobs = {},
		startedAt = 0,
		nextWaveAt = os.clock() + TowerRules.COUNTDOWN_SECONDS,
		waiting = false,
		arriveBy = os.clock() + 10,
		ended = false,
	}
	runs[run.id] = run
	for i, member in going do
		runOf[member] = run
		task.spawn(function()
			TravelService:Teleport(member, TowerBuilder.arrival(origin, i))
		end)
		if member ~= player then
			notify(member, "Info", "tower.partyIn", { floor = floor.id })
		end
	end
	push(run)
	AuditLogService:Audit({
		actorUserId = player.UserId,
		action = "TowerEnter",
		target = floor.id,
		details = { players = #going, levels = levels, behind = leftBehind },
	})
	log:Info("run %d: %s with %d player(s)", run.id, floor.id, #going)
	return { ok = true, entered = true, behind = leftBehind }
end

--------------------------------------------------------------------------------
-- Remote
--------------------------------------------------------------------------------

local function status(player: Player, data: { [string]: any }): { [string]: any }
	local now = os.time()
	local window = openWindow()
	local schedule = EventService:GetTower()
	local nextStart, nextEnd = TowerRules.nextOpening(schedule, now)
	local floors = {}
	for _, floor in TowerRules.available(level60()) do
		local ok, why = TowerRules.canEnter(floor, data.Level or 0, level60())
		table.insert(floors, {
			Id = floor.id,
			Name = floor.name,
			Min = floor.minLevel,
			Max = floor.maxLevel,
			Points = floor.points,
			Waves = #floor.waves,
			Limit = floor.limitSeconds,
			Cleared = data.ClaimedRewardIds[`T:{floor.id}`] ~= nil,
			Best = data.TowerBest[floor.id],
			Locked = if ok then nil else why,
		})
	end
	return {
		ok = true,
		open = window ~= nil,
		closesIn = if window then math.max(0, window.EndsAt - now) else nil,
		opensIn = if window == nil and nextStart then math.max(0, nextStart - now) else nil,
		opensFor = if window == nil and nextStart and nextEnd then nextEnd - nextStart else nil,
		points = data.TowerPoints or 0,
		maxPoints = TowerRules.MAX_POINTS,
		inRun = runOf[player] ~= nil,
		floors = floors,
	}
end

local function board(data: { [string]: any }, floor: TowerRules.Floor): { [string]: any }
	local week = TowerRules.weekOf(os.time())
	local function view(entries: { { key: string, tenths: number } }): { any }
		local out = {}
		for place, entry in entries do
			table.insert(out, { Place = place, Name = nameOf(entry.key), Time = entry.tenths })
		end
		return out
	end
	return {
		ok = true,
		floor = floor.id,
		online = storesOk,
		thisWeek = view(topOf(week, floor.id)),
		lastWeek = view(topOf(week - 1, floor.id)),
		best = data.TowerBest[floor.id],
		resetsIn = math.max(0, TowerRules.weekStart(week + 1) - os.time()),
	}
end

local function onRequest(player: Player, action: string, floorId: string?): { [string]: any }
	local data = PlayerDataService:GetData(player)
	if data == nil or data.Job == nil then
		return { ok = false, reason = "notLoaded" }
	end
	if action == "Leave" then
		local run = runOf[player]
		if run == nil then
			return { ok = false, reason = "noRun" }
		end
		drop(run, player, "left")
		sendHome(player)
		return { ok = true }
	end
	if not ShopService:Near(player, data, NPC) then
		return { ok = false, reason = "far" }
	end
	if action == "Status" then
		return status(player, data)
	end
	local floor = TowerRules.get(floorId)
	if floor == nil or (floor.needsCap and not level60()) then
		return { ok = false, reason = "floor" }
	end
	if action == "Board" then
		return board(data, floor)
	elseif action == "Enter" then
		return enter(player, data, floor)
	end
	return { ok = false, reason = "action" }
end

--------------------------------------------------------------------------------
-- The weekly schedule
--------------------------------------------------------------------------------

local function scheduleCheck()
	local schedule = EventService:GetTower()
	local now = os.time()
	local startsAt, endsAt = TowerRules.due(EventService:GetWindows() :: any, schedule, now)
	if startsAt == nil or endsAt == nil then
		return
	end
	local from = math.max(startsAt, now)
	local minutes = math.max(1, math.floor((endsAt - from) / 60))
	local ok, reason = EventService:Schedule(TowerRules.EVENT_ID, from, minutes, 0)
	if ok then
		AuditLogService:Audit({
			actorUserId = 0,
			action = "TowerScheduled",
			target = TowerRules.EVENT_ID,
			details = { startsAt = from, endsAt = from + minutes * 60 },
		})
		log:Info("scheduled opening %d-%d", from, from + minutes * 60)
	else
		-- Usually another server won the write; the next check sees it.
		log:Info("scheduled opening not started here (%s)", tostring(reason))
	end
end

function TowerService:Init()
	NetService:Handle("Tower", onRequest)
	local ok = pcall(function()
		DataStoreService:GetOrderedDataStore("RC_TowerProbe")
	end)
	storesOk = ok
	if not ok then
		log:Warn("Tower boards unavailable on this server (no DataStore access)")
	end
end

function TowerService:Start()
	local existing = Workspace:FindFirstChild("RC_Tower")
	if existing then
		existing:Destroy()
	end
	local f = Instance.new("Folder")
	f.Name = "RC_Tower"
	f.Parent = Workspace
	folder = f
	Players.PlayerRemoving:Connect(function(player)
		local run = runOf[player]
		if run then
			drop(run, player, "left")
		end
	end)
	PlayerDataService.ProfileLoaded:Connect(function(player)
		task.spawn(claimWeekly, player)
	end)
	task.spawn(function()
		local tick = 0
		while true do
			task.wait(0.5)
			local now = os.clock()
			for _, run in runs do
				xpcall(tickRun, function(err)
					log:Error("run %d tick failed: %s", run.id, tostring(err))
				end, run, now)
			end
			tick += 1
			-- Every ~20 s: the schedule; every ~15 min: last week's places.
			if tick % 40 == 7 then
				xpcall(scheduleCheck, function(err)
					log:Error("schedule check failed: %s", tostring(err))
				end)
			end
			if tick % 1800 == 0 then
				for _, player in Players:GetPlayers() do
					task.spawn(claimWeekly, player)
				end
			end
		end
	end)
end

-- Whether `player` is in a Tower run (other services may ask).
function TowerService:IsInRun(player: Player): boolean
	return runOf[player] ~= nil
end

return TowerService
