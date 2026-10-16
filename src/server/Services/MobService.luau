--!strict
--[[
	MobService (Layer 5) — server-authoritative creature AI (Phase 9;
	ARCHITECTURE.md §7: one scheduler, ≤ 10 Hz, mobs sleep with no player
	within Mobs.SleepRadius).

	  - Spawns creatures (World/CreatureBuilder) and registers them with
	    CombatService as NPCs that neither revive nor regenerate on their own.
	  - Each tick, every awake mob runs Logic/MobBrain: chase, telegraphed
	    attack (MobAttack event, then CombatService:NpcStrike re-validates
	    harm and reach), leash home and restore.
	  - Mobs never target players they can't harm (safe zones, protection).
	  - On defeat: EXP to the players who earned it (Logic/DungeonRules
	    shareXp over the recipients, D-32), then the body fades and is
	    removed; spawners respawn their mob after a delay.
	  - Training Grounds: Rift Sprites roam each capital's yard (Quest 1).

	Display data only goes to clients; no remote here accepts input.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local DungeonRules = require(Shared.Logic.DungeonRules)
local EnemyDefinitions = require(Shared.Definitions.EnemyDefinitions)
local MobBrain = require(Shared.Logic.MobBrain)
local StatFormulas = require(Shared.Logic.StatFormulas)
local WorldLayout = require(Shared.Definitions.WorldLayout)
local Log = require(Shared.Util.Log)
local Signal = require(Shared.Util.Signal)

local ConfigurationService = require(script.Parent.ConfigurationService)
local CombatService = require(script.Parent.CombatService)
local LevelService = require(script.Parent.LevelService)
local CreatureBuilder = require(script.Parent.Parent.World.CreatureBuilder)

local NPC_FOLDER_NAME = "RC_Npcs"
local MOVE_REFRESH_SECONDS = 0.3
-- Idle wandering: radius around home and fraction of the run speed.
local WANDER_RADIUS = 10
local WANDER_SPEED = 0.35
local wanderRng = Random.new()
local CORPSE_SECONDS = 2.6

local log = Log.new("MobService")

export type Mob = {
	id: number,
	enemy: EnemyDefinitions.Enemy,
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	home: Vector3,
	state: MobBrain.State,
	attackReadyAt: number,
	windupEndsAt: number,
	target: Model?,
	nextMoveAt: number,
	-- Idle wandering around home.
	nextWanderAt: number,
	wandering: boolean,
	lastMoveGoal: Vector3?,
	-- Bosses: BossService holds the mob still while it telegraphs.
	busyUntil: number,
	speedScale: number,
	-- Who earns EXP when it falls (default: nearby players who damaged it).
	xpRecipients: ((mob: Mob) -> { Player })?,
	-- Free-form owner tag ("training", a dungeon runId).
	owner: string,
	dead: boolean,
}

export type SpawnOptions = {
	owner: string?,
	hpScale: number?,
	parent: Instance?,
	xpRecipients: ((mob: Mob) -> { Player })?,
}

local MobService = {
	-- (mob, contributors) after a mob is defeated and EXP is granted.
	MobDefeated = Signal.new(),
}

local mobs: { [Model]: Mob } = {}
local nextId = 0
local npcFolder: Folder

local function config(): any
	return ConfigurationService:Get("Mobs")
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

--------------------------------------------------------------------------------
-- Spawning
--------------------------------------------------------------------------------

--[[
	Spawns `enemyId` standing at `at` (ground CFrame). Returns the mob or nil.
]]
function MobService:Spawn(enemyId: string, at: CFrame, options: SpawnOptions?): Mob?
	local enemy = EnemyDefinitions.get(enemyId)
	local model = CreatureBuilder.build(enemyId, at)
	if enemy == nil or model == nil then
		log:Error("unknown enemy %s", tostring(enemyId))
		return nil
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	model.Parent = if options and options.parent then options.parent else npcFolder
	pcall(function()
		root:SetNetworkOwner(nil) -- server-owned physics (SECURITY_MODEL T-33)
	end)

	local base = StatFormulas.forLevel(enemy.level)
	local hpScale = enemy.hpScale * ((options and options.hpScale) or 1)
	CombatService:RegisterNpc(model, {
		name = enemy.name,
		level = enemy.level,
		maxHp = math.floor(base.MaxHP * hpScale + 0.5),
		attackScale = enemy.attackScale,
		defenseScale = enemy.defenseScale,
		autoRevive = false,
		regen = false,
	})

	nextId += 1
	local mob: Mob = {
		id = nextId,
		enemy = enemy,
		model = model,
		humanoid = humanoid,
		root = root,
		home = at.Position,
		state = "Idle",
		attackReadyAt = 0,
		windupEndsAt = 0,
		target = nil,
		nextMoveAt = 0,
		nextWanderAt = os.clock() + math.random() * 4,
		wandering = false,
		lastMoveGoal = nil,
		busyUntil = 0,
		speedScale = 1,
		xpRecipients = options and options.xpRecipients,
		owner = (options and options.owner) or "world",
		dead = false,
	}
	mobs[model] = mob
	return mob
end

-- Removes a mob immediately (run cleanup, boss reset adds).
function MobService:Despawn(mob: Mob)
	if mobs[mob.model] ~= mob then
		return
	end
	mobs[mob.model] = nil
	mob.dead = true
	CombatService:UnregisterNpc(mob.model)
	mob.model:Destroy()
end

function MobService:DespawnOwner(owner: string)
	for _, mob in mobs do
		if mob.owner == owner then
			MobService:Despawn(mob)
		end
	end
end

function MobService:GetMob(model: Model): Mob?
	return mobs[model]
end

-- Sends a mob home at full HP (boss reset after a wipe).
function MobService:Reset(mob: Mob)
	mob.state = "Return"
	mob.target = nil
	mob.busyUntil = 0
	mob.lastMoveGoal = nil
end

--------------------------------------------------------------------------------
-- AI
--------------------------------------------------------------------------------

-- Nearest player this mob may attack, with its distance.
local function nearestTarget(mob: Mob, searchRadius: number): (Model?, number?)
	local best: Model? = nil
	local bestDistance = math.huge
	local origin = mob.root.Position
	for _, entity in CombatService:LivePlayers() do
		local distance = (entity.root.Position - origin).Magnitude
		if
			distance < bestDistance
			and distance <= searchRadius
			and CombatService:CanHarm(mob.model, entity.model)
		then
			best = entity.model
			bestDistance = distance
		end
	end
	return best, if best then bestDistance else nil
end

local function moveTo(mob: Mob, goal: Vector3, now: number)
	local last = mob.lastMoveGoal
	if now < mob.nextMoveAt and last and (last - goal).Magnitude < 2 then
		return
	end
	mob.nextMoveAt = now + MOVE_REFRESH_SECONDS
	mob.lastMoveGoal = goal
	mob.humanoid:MoveTo(goal)
end

local function face(mob: Mob, point: Vector3)
	local from = mob.root.Position
	local look = flat(point - from)
	if look.Magnitude > 0.1 then
		mob.root.CFrame = CFrame.lookAt(from, from + look)
	end
end

local function stepMob(mob: Mob, now: number)
	local enemy = mob.enemy
	mob.humanoid.WalkSpeed = enemy.moveSpeed * mob.speedScale
	if mob.state ~= "Idle" then
		mob.wandering = false
	end
	if now < mob.busyUntil then
		mob.humanoid:Move(Vector3.zero)
		return
	end
	local distanceFromHome = (flat(mob.root.Position) - flat(mob.home)).Magnitude
	local search = enemy.aggroRadius * MobBrain.LOSE_TARGET_FACTOR
	local target, targetDistance = nearestTarget(mob, search)
	local state, action = MobBrain.step({
		state = mob.state,
		now = now,
		targetDistance = targetDistance,
		distanceFromHome = distanceFromHome,
		attackReadyAt = mob.attackReadyAt,
		windupEndsAt = mob.windupEndsAt,
	}, { aggroRadius = enemy.aggroRadius, leashRadius = enemy.leashRadius, attackRange = enemy.attackRange })
	mob.state = state :: MobBrain.State

	if action == "MoveToTarget" and target then
		local targetRoot = target:FindFirstChild("HumanoidRootPart") :: BasePart?
		if targetRoot then
			-- Stop just inside reach rather than on top of the player.
			local offset = flat(mob.root.Position - targetRoot.Position)
			local stand = targetRoot.Position
				+ (if offset.Magnitude > 0.1 then offset.Unit else Vector3.zero)
					* (enemy.attackRange * 0.6)
			moveTo(mob, stand, now)
		end
	elseif action == "Stop" then
		mob.humanoid:Move(Vector3.zero)
		local targetRoot = target and target:FindFirstChild("HumanoidRootPart") :: BasePart?
		if targetRoot then
			face(mob, targetRoot.Position)
		end
	elseif action == "StartWindup" and target then
		mob.target = target
		mob.windupEndsAt = now + enemy.windup
		mob.humanoid:Move(Vector3.zero)
		local targetRoot = target:FindFirstChild("HumanoidRootPart") :: BasePart?
		if targetRoot then
			face(mob, targetRoot.Position)
		end
		CombatService:Broadcast(mob.model, {
			kind = "MobAttack",
			target = mob.model,
			aim = target,
			windup = enemy.windup,
		})
	elseif action == "Strike" then
		mob.attackReadyAt = now + enemy.attackCooldown
		local aimed = mob.target
		mob.target = nil
		if aimed and aimed.Parent then
			-- Reach slack: the target may have stepped back during the wind-up.
			CombatService:NpcStrike(
				mob.model,
				aimed,
				enemy.attackCoefficient,
				enemy.attackRange * 1.4 + 2,
				enemy.elite
			)
		end
	elseif action == "None" and state == "Idle" and not enemy.elite then
		-- Idle creatures amble around their post instead of standing frozen.
		if now >= mob.nextWanderAt then
			mob.nextWanderAt = now + wanderRng:NextNumber(4, 9)
			if wanderRng:NextNumber() < 0.65 then
				local a = wanderRng:NextNumber(0, math.pi * 2)
				local r = wanderRng:NextNumber(3, WANDER_RADIUS)
				mob.wandering = true
				mob.humanoid.WalkSpeed = enemy.moveSpeed * WANDER_SPEED
				mob.humanoid:MoveTo(mob.home + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r))
			end
		end
		if mob.wandering then
			mob.humanoid.WalkSpeed = enemy.moveSpeed * WANDER_SPEED
		end
	elseif action == "MoveHome" then
		moveTo(mob, mob.home, now)
	elseif action == "Restore" then
		mob.humanoid:Move(Vector3.zero)
		CombatService:RestoreNpc(mob.model)
	end
end

local function anyPlayerNear(position: Vector3, radius: number): boolean
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and (root.Position - position).Magnitude <= radius then
			return true
		end
	end
	return false
end

local function tick()
	local now = os.clock()
	local sleepRadius = config().SleepRadius
	for model, mob in mobs do
		if mob.dead or model.Parent == nil then
			continue
		end
		-- Sleep: nobody near, nothing to do (unless walking home).
		if mob.state == "Idle" and not anyPlayerNear(mob.root.Position, sleepRadius) then
			continue
		end
		local ok, err = pcall(stepMob :: any, mob, now)
		if not ok then
			log:Error("mob %s tick failed: %s", mob.enemy.id, tostring(err))
		end
	end
end

--------------------------------------------------------------------------------
-- Defeat and EXP
--------------------------------------------------------------------------------

local function defaultRecipients(mob: Mob, contributors: { [Player]: number }): { Player }
	local radius = ConfigurationService:Get("Dungeon").XpShareRadius
	local out = {}
	for player in contributors do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if
			player.Parent == Players
			and root
			and root:IsA("BasePart")
			and (root.Position - mob.root.Position).Magnitude <= radius
		then
			table.insert(out, player)
		end
	end
	return out
end

local function onDefeated(entity: CombatService.Entity)
	local mob = mobs[entity.model]
	if mob == nil or mob.dead then
		return
	end
	mob.dead = true
	local contributors = CombatService:GetContributors(mob.model)
	local recipientsFn = mob.xpRecipients
	local recipients: { Player } = if recipientsFn
		then recipientsFn(mob)
		else defaultRecipients(mob, contributors)
	-- Only players who actually fought (or their party, per the recipient rule) earn EXP.
	local share = DungeonRules.shareXp(mob.enemy.xp, #recipients)
	for _, player in recipients do
		if share > 0 then
			LevelService:GrantXP(player, share, `Mob:{mob.enemy.id}`)
		end
	end
	MobService.MobDefeated:Fire(mob, contributors)
	task.delay(CORPSE_SECONDS, function()
		if mobs[mob.model] == mob then
			mobs[mob.model] = nil
			CombatService:UnregisterNpc(mob.model)
			mob.model:Destroy()
		end
	end)
end

--------------------------------------------------------------------------------
-- Camps: groups that respawn where they stood (war zone creatures)
--------------------------------------------------------------------------------

export type CampOptions = {
	-- Seconds until respawn, asked each time the creature falls (so config
	-- changes apply without a restart).
	respawnSeconds: () -> number,
	xpRecipients: ((mob: Mob) -> { Player })?,
	-- Called after each (re)spawn, e.g. to attach a boss's ability loop.
	onSpawn: ((mob: Mob) -> ())?,
}

-- One spot in a camp: its creature while alive, its respawn time while not.
export type CampSlot = {
	enemy: string,
	at: CFrame,
	owner: string,
	options: CampOptions,
	mob: Mob?,
	respawnAt: number?,
}
local campSlots: { [Model]: CampSlot } = {}

local function spawnCampSlot(slot: CampSlot)
	slot.respawnAt = nil
	local mob = MobService:Spawn(
		slot.enemy,
		slot.at,
		{ owner = slot.owner, xpRecipients = slot.options.xpRecipients }
	)
	slot.mob = mob
	if mob then
		campSlots[mob.model] = slot
		local onSpawn = slot.options.onSpawn
		if onSpawn then
			onSpawn(mob)
		end
	end
end

--[[
	Spawns `count` of `enemyId` around `center` (a ground point); each one
	respawns at its own spot after it falls. `groundAt(x, z)` gives the
	ground height for each spot. Returns the camp's slots (for timers).
]]
function MobService:SpawnCamp(
	enemyId: string,
	center: Vector3,
	count: number,
	owner: string,
	groundAt: (x: number, z: number) -> number,
	options: CampOptions
): { CampSlot }
	local slots = {}
	for i = 1, count do
		local a = (i / count) * math.pi * 2
		local r = if count == 1 then 0 else 7
		local x, z = center.X + math.cos(a) * r, center.Z + math.sin(a) * r
		local at = CFrame.new(x, groundAt(x, z), z) * CFrame.Angles(0, a + math.pi, 0)
		local slot: CampSlot =
			{ enemy = enemyId, at = at, owner = owner, options = options, mob = nil, respawnAt = nil }
		table.insert(slots, slot)
		spawnCampSlot(slot)
	end
	return slots
end

--------------------------------------------------------------------------------
-- Training Grounds sprites
--------------------------------------------------------------------------------

local function spawnTrainingSprite(realm: WorldLayout.Realm, index: number)
	local yardCenter, yardSize = WorldLayout.trainingYard(realm)
	local top = yardCenter[2] + yardSize[2] / 2
	local rng = Random.new()
	-- Middle band of the yard, clear of the dummy line and the city edge.
	local x = yardCenter[1] + rng:NextNumber(-0.35, 0.35) * yardSize[1]
	local z = yardCenter[3] + rng:NextNumber(-0.2, 0.15) * yardSize[3] * WorldLayout.yardDirection(realm)
	local at = CFrame.new(x, top, z) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	local mob = MobService:Spawn("RiftSprite", at, { owner = "training" })
	if mob == nil then
		return
	end
	mob.model:SetAttribute("RC_Index", index)
end

function MobService:Init()
	CombatService.Defeated:Connect(onDefeated)
	MobService.MobDefeated:Connect(function(mob)
		local slot = campSlots[mob.model]
		if slot then
			campSlots[mob.model] = nil
			slot.mob = nil
			local seconds = slot.options.respawnSeconds()
			slot.respawnAt = os.clock() + seconds
			task.delay(seconds, function()
				-- Only if nothing respawned it meanwhile.
				if slot.respawnAt ~= nil and slot.mob == nil then
					spawnCampSlot(slot)
				end
			end)
			return
		end
		if mob.owner ~= "training" then
			return
		end
		local realm: WorldLayout.Realm? = nil
		local best = math.huge
		for _, candidate in WorldLayout.Realms :: { [string]: WorldLayout.Realm } do
			local c = candidate.platformCenter
			local d = (mob.home - Vector3.new(c[1], c[2], c[3])).Magnitude
			if d < best then
				best, realm = d, candidate
			end
		end
		local index = mob.model:GetAttribute("RC_Index")
		task.delay(config().TrainingRespawnSeconds, function()
			if realm then
				spawnTrainingSprite(realm, if type(index) == "number" then index else 0)
			end
		end)
	end)
end

function MobService:Start()
	local existing = Workspace:FindFirstChild(NPC_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		npcFolder = existing
	else
		local folder = Instance.new("Folder")
		folder.Name = NPC_FOLDER_NAME
		folder.Parent = Workspace
		npcFolder = folder
	end

	for _, realm in WorldLayout.Realms :: { [string]: WorldLayout.Realm } do
		for index = 1, config().TrainingSprites do
			spawnTrainingSprite(realm, index)
		end
	end

	task.spawn(function()
		while true do
			task.wait(1 / config().TickHz)
			tick()
		end
	end)
	log:Info("mob AI ready (%d Hz)", config().TickHz)
end

return MobService
