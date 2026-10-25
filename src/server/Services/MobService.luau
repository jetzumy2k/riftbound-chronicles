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
	  - While chasing, each kind closes in its own way (Logic/MobTactics):
	    wolves circle then pounce, serpents hold coiled then lunge, brutes
	    charge, beetles zig-zag.
	  - Skill statuses (Phase 5): stunned mobs freeze and lose their wind-up,
	    rooted ones stay put, slowed ones move slower, taunted ones fight
	    the taunter.
	  - On defeat: EXP to the players who earned it (Logic/DungeonRules
	    shareXp over the recipients, D-32), then the body fades and is
	    removed; spawners respawn their mob after a delay.
	  - Training Grounds: Rift Sprites roam each capital's yard (Quest 1).
	  - Behaviour and attacks (D-61): a creature that notices a player
	    turns and roars (Alert) before the chase; each kind has its own
	    attack set (Logic/MobAttacks: bites, claws, pounces, smashes,
	    sweeps, stomps, rams) and keeps turning to its target through the
	    wind-up, so a strike only lands in front of it (area moves hit
	    everyone they cover); it stands open for a moment after each
	    strike; a heavy hit (a crit or 12% of its health) staggers it and
	    breaks its wind-up; below 30% health it enrages (faster, attacks
	    more often). A creature stuck on a rock jumps and side-steps.
	  - Winged creatures fly (Logic/MobFlight, D-60): they take off while
	    chasing, wheel overhead, mark a spot on the ground and dive onto
	    it (players still inside are hit), then land and fight on foot for
	    a while. Server-owned AlignPosition / AlignOrientation fly them.

	Display data only goes to clients; no remote here accepts input.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local DungeonRules = require(Shared.Logic.DungeonRules)
local LevelGap = require(Shared.Logic.LevelGap)
local EnemyDefinitions = require(Shared.Definitions.EnemyDefinitions)
local MobBrain = require(Shared.Logic.MobBrain)
local MobAttacks = require(Shared.Logic.MobAttacks)
local MobFlight = require(Shared.Logic.MobFlight)
local MobTactics = require(Shared.Logic.MobTactics)
local Telegraph = require(Shared.Logic.Telegraph)
local StatFormulas = require(Shared.Logic.StatFormulas)
local WorldLayout = require(Shared.Definitions.WorldLayout)
local Log = require(Shared.Util.Log)
local Signal = require(Shared.Util.Signal)

local ConfigurationService = require(script.Parent.ConfigurationService)
local CombatService = require(script.Parent.CombatService)
local NetService = require(script.Parent.NetService)
local LevelService = require(script.Parent.LevelService)
local CreatureBuilder = require(script.Parent.Parent.World.CreatureBuilder)

local NPC_FOLDER_NAME = "RC_Npcs"
local MOVE_REFRESH_SECONDS = 0.3
-- Idle wandering: radius around home and fraction of the run speed.
local WANDER_RADIUS = 10
local WANDER_SPEED = 0.35
-- Elites and bosses prowl a smaller patch, pausing longer between laps.
local ELITE_WANDER_RADIUS = 7
-- Most a creature turns per tick while squaring up to a target (radians):
-- a creature turns, it doesn't snap round.
local TURN_STEP = math.rad(35)
local ELITE_TURN_STEP = math.rad(22)
local wanderRng = Random.new()
local CORPSE_SECONDS = 2.6
-- Turn per tick while winding up: a player who circles fast can slip out
-- of the strike's arc.
local WINDUP_TURN_STEP = math.rad(16)
-- Stagger: a hit of this share of max health (or a crit) staggers a
-- creature for STAGGER_SECONDS, at most once per STAGGER_COOLDOWN.
local STAGGER_SHARE = 0.12
local STAGGER_SECONDS = 0.6
local STAGGER_COOLDOWN = 4
-- Enrage: below this share of health, faster and quicker to attack.
local ENRAGE_SHARE = 0.3
local ENRAGE_SPEED = 1.15
local ENRAGE_COOLDOWN = 0.7
-- Stuck: chasing but barely moving for this long, it jumps and side-steps.
local STUCK_SECONDS = 1.2
local DETOUR_SECONDS = 1

local log = Log.new("MobService")

export type Mob = {
	id: number,
	enemy: EnemyDefinitions.Enemy,
	-- Level it spawned at (a camp may set one other than the definition's).
	level: number,
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
	-- How it closes in while chasing (Logic/MobTactics).
	tacticKind: MobTactics.Kind,
	tactic: MobTactics.State,
	-- Its attack set (Logic/MobAttacks), the move being wound up and the
	-- last one used.
	attackSet: MobAttacks.SetName,
	move: MobAttacks.Move?,
	lastMoveId: string?,
	alertEndsAt: number,
	-- Stagger, enrage (D-61).
	staggerReadyAt: number,
	enraged: boolean,
	-- Getting unstuck: where it was last tick, how long it has barely
	-- moved, and a side-step in progress.
	lastPosition: Vector3,
	stuckFor: number,
	detourUntil: number,
	detourSide: number,
	-- Winged creatures (Logic/MobFlight); the spot a dive is aimed at.
	flight: MobFlight.State?,
	divePoint: Vector3?,
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
	level: number?,
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

	local level = math.clamp((options and options.level) or enemy.level, 0, StatFormulas.CREATURE_MAX)
	local base = StatFormulas.forCreatureLevel(level)
	local hpScale = enemy.hpScale * ((options and options.hpScale) or 1)
	CombatService:RegisterNpc(model, {
		name = enemy.name,
		level = level,
		maxHp = math.floor(base.MaxHP * hpScale + 0.5),
		attackScale = enemy.attackScale,
		defenseScale = enemy.defenseScale,
		autoRevive = false,
		regen = false,
		-- D-90: bosses' element attacks are magic (D-88 element).
		magic = enemy.element ~= nil,
	})

	nextId += 1
	local mob: Mob = {
		id = nextId,
		enemy = enemy,
		level = level,
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
		tacticKind = MobTactics.kindFor(enemy.body),
		tactic = MobTactics.initial(),
		flight = if MobFlight.canFly(enemy.body, enemy.traits :: any)
			then MobFlight.initial(os.clock(), wanderRng:NextNumber())
			else nil,
		divePoint = nil,
		attackSet = MobAttacks.setFor(enemy.body, model:GetAttribute("RC_Shape") :: string?),
		move = nil,
		lastMoveId = nil,
		alertEndsAt = 0,
		staggerReadyAt = 0,
		enraged = false,
		lastPosition = root.Position,
		stuckFor = 0,
		detourUntil = 0,
		detourSide = 1,
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

-- In the air (bosses hold their abilities until it lands).
function MobService:IsAirborne(mob: Mob): boolean
	return mob.flight ~= nil and MobFlight.isAirborne((mob.flight :: MobFlight.State).mode)
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

-- Faces `point`, at most `maxStep` radians this tick (nil: at once).
local function face(mob: Mob, point: Vector3, maxStep: number?)
	local from = mob.root.Position
	local look = flat(point - from)
	if look.Magnitude <= 0.1 then
		return
	end
	if maxStep then
		local current = flat(mob.root.CFrame.LookVector)
		if current.Magnitude > 0.1 then
			local a = math.atan2(-current.X, -current.Z)
			local b = math.atan2(-look.X, -look.Z)
			local delta = (b - a + math.pi) % (math.pi * 2) - math.pi
			local yaw = a + math.clamp(delta, -maxStep, maxStep)
			look = Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
		end
	end
	mob.root.CFrame = CFrame.lookAt(from, from + look)
end

--------------------------------------------------------------------------------
-- Flight (creature overhaul stage 3, D-60): winged creatures take off,
-- wheel over their target, mark a spot and dive onto it (Logic/MobFlight).
-- Server-owned movers fly them; the client animates from RC_Flight.
--------------------------------------------------------------------------------

-- Flight speeds as multiples of the walk speed.
local FLY_SPEED = 1.4
local CLIMB_SPEED = 1.1
local DIVE_SPEED = 3.2
-- The dive's ground area: this radius plus DIVE_RADIUS_PER_SCALE x size.
local DIVE_RADIUS = 4
local DIVE_RADIUS_PER_SCALE = 1.4
-- Dive damage relative to the creature's basic attack.
local DIVE_DAMAGE = 1.5
local TELEGRAPH_RADIUS = 200

local flightRay = RaycastParams.new()
flightRay.FilterType = Enum.RaycastFilterType.Exclude
flightRay.RespectCanCollide = true
local flightRayAt = 0

-- Creatures and player characters are never ground or ceiling.
local function refreshFlightRay(now: number)
	if now - flightRayAt < 0.5 then
		return
	end
	flightRayAt = now
	local exclude: { Instance } = {}
	for model in mobs do
		table.insert(exclude, model)
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(exclude, player.Character)
		end
	end
	flightRay.FilterDescendantsInstances = exclude
end

local function groundBelow(position: Vector3): number?
	local result = Workspace:Raycast(position, Vector3.new(0, -300, 0), flightRay)
	return if result then result.Position.Y else nil
end

local function headroomAbove(position: Vector3): number
	local result = Workspace:Raycast(position, Vector3.new(0, 60, 0), flightRay)
	return if result then result.Distance else 60
end

-- Height of the root centre above the ground when standing.
local function standHeight(mob: Mob): number
	return mob.humanoid.HipHeight + mob.root.Size.Y / 2
end

local function mover(mob: Mob): (AlignPosition, AlignOrientation)
	local root = mob.root
	local attachment = root:FindFirstChild("RC_FlyAttachment") :: Attachment?
	if attachment == nil then
		local made = Instance.new("Attachment")
		made.Name = "RC_FlyAttachment"
		made.Parent = root
		attachment = made
		local align = Instance.new("AlignPosition")
		align.Name = "RC_FlyPosition"
		align.Mode = Enum.PositionAlignmentMode.OneAttachment
		align.Attachment0 = made
		align.MaxForce = math.huge
		align.Responsiveness = 30
		align.Enabled = false
		align.Parent = root
		local orient = Instance.new("AlignOrientation")
		orient.Name = "RC_FlyOrientation"
		orient.Mode = Enum.OrientationAlignmentMode.OneAttachment
		orient.Attachment0 = made
		orient.MaxTorque = math.huge
		orient.Responsiveness = 20
		orient.Enabled = false
		orient.Parent = root
	end
	return root:FindFirstChild("RC_FlyPosition") :: AlignPosition,
		root:FindFirstChild("RC_FlyOrientation") :: AlignOrientation
end

-- Holds the creature up and steers it to `goal` at `speed`, facing `look`.
local function flyTo(mob: Mob, goal: Vector3, speed: number, look: Vector3)
	local align, orient = mover(mob)
	mob.humanoid.PlatformStand = true
	align.Enabled = true
	orient.Enabled = true
	align.Position = goal
	align.MaxVelocity = math.max(speed, 1)
	local flatLook = flat(look)
	if flatLook.Magnitude > 0.1 then
		orient.CFrame = CFrame.lookAt(Vector3.zero, flatLook)
	end
end

-- Back on its feet: the Humanoid walks it again.
local function stopFlying(mob: Mob)
	local root = mob.root
	local align = root:FindFirstChild("RC_FlyPosition")
	local orient = root:FindFirstChild("RC_FlyOrientation")
	if align then
		(align :: AlignPosition).Enabled = false
	end
	if orient then
		(orient :: AlignOrientation).Enabled = false
	end
	mob.humanoid.PlatformStand = false
end

local function setFlightMode(mob: Mob, mode: string)
	mob.model:SetAttribute("RC_Flight", if mode == "Ground" then nil else mode)
end

local function diveRadius(mob: Mob): number
	return DIVE_RADIUS + DIVE_RADIUS_PER_SCALE * mob.enemy.scale
end

-- The dive's spot is marked on the ground for everyone nearby.
local function markDive(mob: Mob, center: Vector3)
	local recipients = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and (root.Position - center).Magnitude <= TELEGRAPH_RADIUS then
			table.insert(recipients, player)
		end
	end
	if #recipients > 0 then
		NetService:FireClients("Telegraph", recipients, {
			shape = "Circle",
			center = center,
			radius = diveRadius(mob),
			facing = Vector3.new(0, 0, -1),
			duration = MobFlight.WARN_SECONDS + 0.4,
		})
	end
	CombatService:Broadcast(mob.model, {
		kind = "MobAttack",
		target = mob.model,
		windup = MobFlight.WARN_SECONDS + 0.3,
		move = "Slam",
	})
end

-- The dive lands: everyone (that it may harm) still inside the mark is hit.
local function resolveDive(mob: Mob, center: Vector3)
	local c = { center.X, center.Z }
	local radius = diveRadius(mob)
	for _, entity in CombatService:LivePlayers() do
		local p = entity.root.Position
		if Telegraph.inCircle(c, radius, { p.X, p.Z }) and math.abs(p.Y - center.Y) < 12 then
			CombatService:NpcStrike(
				mob.model,
				entity.model,
				mob.enemy.attackCoefficient * DIVE_DAMAGE,
				nil,
				true
			)
		end
	end
end

--[[
	One flight tick. Airborne creatures run only this (no walking or basic
	attacks); grounded ones call it while chasing to see whether to take off.
	Returns true when the creature is (now) in the air.
]]
local function stepFlight(mob: Mob, now: number, stunned: boolean): boolean
	local flight = mob.flight
	if flight == nil then
		return false
	end
	local enemy = mob.enemy
	local root = mob.root
	local position = root.Position
	refreshFlightRay(now)
	local stand = standHeight(mob)
	local floor = groundBelow(position)
	local altitude = if floor then position.Y - stand - floor else 0
	local headroom = headroomAbove(position)
	local target, _ = nearestTarget(mob, enemy.aggroRadius * MobBrain.LOSE_TARGET_FACTOR)
	local targetRoot = target and target:FindFirstChild("HumanoidRootPart") :: BasePart?
	local leashed = (flat(position) - flat(mob.home)).Magnitude > enemy.leashRadius
	local chasing = targetRoot ~= nil and not leashed and mob.state ~= "Return"
	local divePoint = mob.divePoint
	local arrived = flight.mode == "Dive"
		and divePoint ~= nil
		and (position - (divePoint + Vector3.new(0, stand, 0))).Magnitude < 3
	local nextState = MobFlight.step(flight, {
		now = now,
		chasing = chasing,
		stunned = stunned,
		altitude = altitude,
		headroom = headroom,
		scale = enemy.scale,
		arrived = arrived,
		roll = wanderRng:NextNumber(),
	})
	local from, to = flight.mode, nextState.mode
	mob.flight = nextState
	if to ~= from then
		setFlightMode(mob, to)
		if to == "Warn" and targetRoot then
			local below = groundBelow(targetRoot.Position) or (targetRoot.Position.Y - 3)
			mob.divePoint = Vector3.new(targetRoot.Position.X, below, targetRoot.Position.Z)
			markDive(mob, mob.divePoint :: Vector3)
		elseif to == "Land" and from == "Dive" and divePoint then
			resolveDive(mob, divePoint)
			mob.attackReadyAt = math.max(mob.attackReadyAt, now + enemy.attackCooldown)
		end
		if to == "Ground" then
			mob.divePoint = nil
			mob.lastMoveGoal = nil
			stopFlying(mob)
			return false
		end
	end
	if to == "Ground" then
		return false
	end

	local speed = enemy.moveSpeed * mob.speedScale
	local look = root.CFrame.LookVector
	if targetRoot then
		look = targetRoot.Position - position
	end
	local groundHere = floor or (position.Y - stand - altitude)
	if to == "Rise" then
		local cruise = MobFlight.cruiseHeight(enemy.scale, headroom + altitude)
		flyTo(
			mob,
			Vector3.new(position.X, groundHere + stand + cruise, position.Z),
			speed * CLIMB_SPEED,
			look
		)
	elseif to == "Circle" and targetRoot then
		-- Wheel round the target, a little further on each tick.
		local away = flat(position - targetRoot.Position)
		local angle = math.atan2(away.X, away.Z) + nextState.orbitDir * 0.55
		local radius = enemy.attackRange * 2 + 6 + enemy.scale * 2
		local base = groundBelow(targetRoot.Position) or groundHere
		local cruise = MobFlight.cruiseHeight(enemy.scale, headroom + altitude)
		local goal = Vector3.new(
			targetRoot.Position.X + math.sin(angle) * radius,
			base + stand + cruise,
			targetRoot.Position.Z + math.cos(angle) * radius
		)
		local tangent = Vector3.new(math.cos(angle), 0, -math.sin(angle)) * nextState.orbitDir
		flyTo(mob, goal, speed * FLY_SPEED, tangent)
	elseif to == "Warn" then
		-- Hover, turned to the marked spot.
		local spot = mob.divePoint or position
		flyTo(mob, position, speed, spot - position)
	elseif to == "Dive" then
		local spot = mob.divePoint or position
		flyTo(mob, spot + Vector3.new(0, stand, 0), speed * DIVE_SPEED, spot - position)
	else
		-- Land: straight down.
		flyTo(mob, Vector3.new(position.X, groundHere + stand, position.Z), speed * CLIMB_SPEED, look)
	end
	return true
end

local function stepMob(mob: Mob, now: number)
	local enemy = mob.enemy
	-- Skill statuses (Phase 5): stun / root / slow / taunt.
	local control = CombatService:ControlOfModel(mob.model)
	mob.humanoid.WalkSpeed = enemy.moveSpeed * mob.speedScale * (if control then control.speedScale else 1)
	-- In the air: flight runs the creature until it lands.
	if MobService:IsAirborne(mob) then
		stepFlight(mob, now, control ~= nil and control.stunned)
		return
	end
	if mob.state ~= "Idle" then
		mob.wandering = false
	end
	if control and control.stunned then
		-- Stunned: frozen, and a wind-up in progress is interrupted.
		mob.humanoid:Move(Vector3.zero)
		if mob.state == "Windup" then
			mob.state = "Chase"
			mob.target = nil
			mob.attackReadyAt = math.max(mob.attackReadyAt, now + 0.5)
		end
		return
	end
	if now < mob.busyUntil then
		mob.humanoid:Move(Vector3.zero)
		return
	end
	local distanceFromHome = (flat(mob.root.Position) - flat(mob.home)).Magnitude
	local search = enemy.aggroRadius * MobBrain.LOSE_TARGET_FACTOR
	local target, targetDistance = nearestTarget(mob, search)
	-- Taunted: fight the taunter while it can be harmed (even out of aggro range).
	local taunter = control and control.taunter
	if taunter and mob.state ~= "Return" and CombatService:CanHarm(mob.model, taunter) then
		local taunterRoot = taunter:FindFirstChild("HumanoidRootPart")
		if taunterRoot and taunterRoot:IsA("BasePart") then
			target = taunter
			targetDistance = math.min((taunterRoot.Position - mob.root.Position).Magnitude, enemy.aggroRadius)
		end
	end
	local state, action = MobBrain.step({
		state = mob.state,
		now = now,
		targetDistance = targetDistance,
		distanceFromHome = distanceFromHome,
		attackReadyAt = mob.attackReadyAt,
		windupEndsAt = mob.windupEndsAt,
		alertEndsAt = mob.alertEndsAt,
	}, { aggroRadius = enemy.aggroRadius, leashRadius = enemy.leashRadius, attackRange = enemy.attackRange })
	mob.state = state :: MobBrain.State

	if state ~= "Chase" then
		mob.tactic.mode = "Approach"
	end
	if action == "MoveToTarget" and target then
		local targetRoot = target:FindFirstChild("HumanoidRootPart") :: BasePart?
		if targetRoot then
			local reach = enemy.attackRange
			local offset = flat(mob.root.Position - targetRoot.Position)
			local away = if offset.Magnitude > 0.1 then offset.Unit else Vector3.new(0, 0, 1)
			mob.tactic = MobTactics.step(
				mob.tacticKind,
				mob.tactic,
				now,
				offset.Magnitude,
				reach,
				wanderRng:NextNumber()
			)
			local mode: MobTactics.Mode = mob.tactic.mode
			local speedScale = MobTactics.speedScale(mob.tacticKind, mode)
			mob.humanoid.WalkSpeed *= speedScale
			-- Stuck on a rock: jump and side-step for a moment.
			local moved = flat(mob.root.Position - mob.lastPosition).Magnitude
			if mode ~= "Hold" and moved < 0.25 and offset.Magnitude > reach * 1.5 then
				mob.stuckFor += 1 / config().TickHz
			else
				mob.stuckFor = 0
			end
			if mob.stuckFor >= STUCK_SECONDS then
				mob.stuckFor = 0
				mob.detourUntil = now + DETOUR_SECONDS
				mob.detourSide = if wanderRng:NextNumber() < 0.5 then -1 else 1
				mob.humanoid.Jump = true
			end
			if mob.flight and stepFlight(mob, now, false) then
				-- Took off.
				return
			elseif now < mob.detourUntil then
				local side = Vector3.new(-away.Z, 0, away.X) * mob.detourSide
				mob.nextMoveAt = 0
				moveTo(mob, mob.root.Position + side * 8 - away * 3, now)
			elseif mode == "Hold" then
				-- Coiled, watching: turn to face, don't move.
				mob.humanoid:Move(Vector3.zero)
				face(mob, targetRoot.Position, ELITE_TURN_STEP)
			elseif mode == "Circle" then
				-- Stalk round the target, a little ahead on the orbit each tick.
				local angle = math.atan2(away.X, away.Z) + mob.tactic.orbitDir * 0.9
				local radius = reach * MobTactics.CIRCLE_RADIUS
				local goal = targetRoot.Position + Vector3.new(math.sin(angle), 0, math.cos(angle)) * radius
				mob.nextMoveAt = 0
				moveTo(mob, goal, now)
			else
				-- Stop just inside reach rather than on top of the player;
				-- beetles weave side to side on the way in.
				local stand = targetRoot.Position + away * (reach * 0.6)
				if mob.tacticKind == "Skitter" and offset.Magnitude > reach * 1.5 then
					local side = Vector3.new(-away.Z, 0, away.X)
					stand += side * math.sin(now * 3 + mob.id) * reach * 0.9
				end
				moveTo(mob, stand, now)
			end
		end
	elseif action == "Stop" then
		mob.humanoid:Move(Vector3.zero)
		local targetRoot = target and target:FindFirstChild("HumanoidRootPart") :: BasePart?
		if targetRoot then
			face(mob, targetRoot.Position, if enemy.elite then ELITE_TURN_STEP else TURN_STEP)
		end
	elseif action == "StartAlert" then
		-- Noticed a player: turn to it and roar before the chase.
		mob.alertEndsAt = now + MobBrain.ALERT_SECONDS
		mob.humanoid:Move(Vector3.zero)
		local targetRoot = target and target:FindFirstChild("HumanoidRootPart") :: BasePart?
		if targetRoot then
			face(mob, targetRoot.Position, TURN_STEP * 2)
		end
		CombatService:Broadcast(mob.model, {
			kind = "MobAttack",
			target = mob.model,
			windup = MobBrain.ALERT_SECONDS,
			move = "Roar",
			alert = true,
		})
	elseif action == "None" and state == "Alert" then
		mob.humanoid:Move(Vector3.zero)
		local targetRoot = target and target:FindFirstChild("HumanoidRootPart") :: BasePart?
		if targetRoot then
			face(mob, targetRoot.Position, TURN_STEP)
		end
	elseif action == "StartWindup" and target then
		local move = MobAttacks.choose(
			mob.attackSet,
			targetDistance or 0,
			enemy.attackRange,
			wanderRng:NextNumber(),
			mob.lastMoveId
		)
		mob.move = move
		mob.lastMoveId = move.id
		mob.target = target
		local windup = enemy.windup * move.windup
		mob.windupEndsAt = now + windup
		mob.humanoid:Move(Vector3.zero)
		local targetRoot = target:FindFirstChild("HumanoidRootPart") :: BasePart?
		if targetRoot then
			face(mob, targetRoot.Position, TURN_STEP * 1.5)
		end
		CombatService:Broadcast(mob.model, {
			kind = "MobAttack",
			target = mob.model,
			aim = target,
			windup = windup,
			move = move.anim,
		})
	elseif action == "None" and state == "Windup" then
		-- Keeps turning to its target through the wind-up, but not instantly.
		local aimed = mob.target
		local aimedRoot = aimed and aimed:FindFirstChild("HumanoidRootPart") :: BasePart?
		if aimedRoot then
			face(mob, aimedRoot.Position, WINDUP_TURN_STEP)
		end
	elseif action == "Strike" then
		local move = mob.move or MobAttacks.Sets[mob.attackSet][1]
		mob.move = nil
		local cooldown = enemy.attackCooldown * (if mob.enraged then ENRAGE_COOLDOWN else 1)
		mob.attackReadyAt = now + cooldown
		-- Open for a moment after the strike.
		mob.busyUntil = math.max(mob.busyUntil, now + move.recover)
		local aimed = mob.target
		mob.target = nil
		-- Reach slack: the target may have stepped back during the wind-up.
		local reach = enemy.attackRange * move.reach * 1.25 + 2
		local look = mob.root.CFrame.LookVector
		local facing = flat(look)
		facing = if facing.Magnitude > 0.1 then facing.Unit else Vector3.new(0, 0, -1)
		local function covers(model: Model): boolean
			local entityRoot = model:FindFirstChild("HumanoidRootPart")
			if entityRoot == nil or not entityRoot:IsA("BasePart") then
				return false
			end
			local to = flat(entityRoot.Position - mob.root.Position)
			return MobAttacks.inArc({ facing.X, facing.Z }, { to.X, to.Z }, move.arc)
		end
		local coefficient = enemy.attackCoefficient * move.damage
		if move.area then
			for _, entity in CombatService:LivePlayers() do
				if covers(entity.model) then
					CombatService:NpcStrike(mob.model, entity.model, coefficient, reach, enemy.elite)
				end
			end
		elseif aimed and aimed.Parent and covers(aimed) then
			CombatService:NpcStrike(mob.model, aimed, coefficient, reach, enemy.elite)
		end
	elseif action == "None" and state == "Idle" then
		-- Idle creatures amble around their post instead of standing frozen;
		-- elites and bosses prowl their patch.
		if now >= mob.nextWanderAt then
			mob.nextWanderAt = now + wanderRng:NextNumber(4, 9) * (if enemy.elite then 1.4 else 1)
			if wanderRng:NextNumber() < 0.65 then
				local a = wanderRng:NextNumber(0, math.pi * 2)
				local r = wanderRng:NextNumber(3, if enemy.elite then ELITE_WANDER_RADIUS else WANDER_RADIUS)
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
		if mob.enraged then
			mob.enraged = false
			mob.speedScale /= ENRAGE_SPEED
			mob.model:SetAttribute("RC_Enraged", nil)
		end
	end
	mob.lastPosition = mob.root.Position
end

--[[
	A creature took a hit (D-61): a heavy one (a crit, or STAGGER_SHARE of
	its health) staggers it and breaks its wind-up; below ENRAGE_SHARE of
	its health it enrages. Bosses (control immune) don't stagger; their
	enrage is BossService's.
]]
local function onNpcHurt(model: Model, amount: number, crit: boolean)
	local mob = mobs[model]
	if mob == nil or mob.dead then
		return
	end
	local now = os.clock()
	local boss = model:GetAttribute("RC_Boss") ~= nil
	local maxHp = model:GetAttribute("MaxHP")
	local share = if type(maxHp) == "number" and maxHp > 0 then amount / maxHp else 0
	if
		not boss
		and not MobService:IsAirborne(mob)
		and now >= mob.staggerReadyAt
		and (crit or share >= STAGGER_SHARE)
	then
		mob.staggerReadyAt = now + STAGGER_COOLDOWN
		mob.busyUntil = math.max(mob.busyUntil, now + STAGGER_SECONDS)
		if mob.state == "Windup" then
			mob.state = "Chase"
			mob.target = nil
			mob.move = nil
			mob.attackReadyAt = math.max(mob.attackReadyAt, now + STAGGER_SECONDS)
		end
		mob.model:SetAttribute("RC_Stagger", now)
	end
	if not boss and not mob.enraged and CombatService:HpFraction(model) <= ENRAGE_SHARE then
		mob.enraged = true
		mob.speedScale *= ENRAGE_SPEED
		mob.model:SetAttribute("RC_Enraged", true)
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

--[[
	A recipients rule for camps / bosses: everyone who damaged the creature,
	plus their group (`groupOf`: party / union members), alive and within
	Dungeon.XpShareRadius of it (D-32, D-48).
]]
function MobService.groupRecipients(groupOf: (player: Player) -> { Player }): (mob: Mob) -> { Player }
	return function(mob: Mob): { Player }
		local radius = ConfigurationService:Get("Dungeon").XpShareRadius
		local seen: { [Player]: boolean } = {}
		local out = {}
		local function consider(player: Player)
			if seen[player] then
				return
			end
			seen[player] = true
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if
				player.Parent == Players
				and root
				and root:IsA("BasePart")
				and not CombatService:IsDefeated(player)
				and (root.Position - mob.root.Position).Magnitude <= radius
			then
				table.insert(out, player)
			end
		end
		for player in CombatService:GetContributors(mob.model) do
			if player.Parent == Players then
				consider(player)
				for _, member in groupOf(player) do
					consider(member)
				end
			end
		end
		return out
	end
end

local function onDefeated(entity: CombatService.Entity)
	local mob = mobs[entity.model]
	if mob == nil or mob.dead then
		return
	end
	mob.dead = true
	-- A flier falls out of the sky.
	if mob.flight then
		stopFlying(mob)
		mob.model:SetAttribute("RC_Flight", nil)
	end
	local contributors = CombatService:GetContributors(mob.model)
	local recipientsFn = mob.xpRecipients
	local recipients: { Player } = if recipientsFn
		then recipientsFn(mob)
		else defaultRecipients(mob, contributors)
	-- Only players who actually fought (or their party, per the recipient rule) earn EXP.
	-- D-63: each player's share then follows the level gap to the creature.
	local share = DungeonRules.shareXp(EnemyDefinitions.xpAt(mob.enemy, mob.level), #recipients)
	for _, player in recipients do
		local xp = LevelGap.scaleXp(share, mob.level, LevelService:GetLevel(player) or 0)
		if xp > 0 then
			LevelService:GrantXP(player, xp, `Mob:{mob.enemy.id}`)
		end
	end
	MobService.MobDefeated:Fire(mob, contributors, recipients)
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
	-- Creature level for this camp (default: the enemy's own).
	level: number?,
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
		{ owner = slot.owner, xpRecipients = slot.options.xpRecipients, level = slot.options.level }
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

-- Respawns a camp slot now if its creature is down (admin "respawn now").
function MobService:RespawnSlotNow(slot: CampSlot): boolean
	if slot.mob ~= nil then
		return false
	end
	spawnCampSlot(slot)
	return slot.mob ~= nil
end

function MobService:Init()
	CombatService.Defeated:Connect(onDefeated)
	CombatService.NpcHurt:Connect(onNpcHurt)
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
