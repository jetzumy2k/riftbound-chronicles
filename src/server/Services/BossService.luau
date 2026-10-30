--!strict
--[[
	BossService (Layer 5) — boss phases and telegraphed abilities (Phase 9;
	DungeonDefinitions.Bosses).

	A boss is a MobService mob (it chases and uses its basic attack) plus an
	ability loop while it has players to fight:
	  - The phase follows its HP (Logic/DungeonRules.phaseFor); entering a
	    phase announces it and speeds the boss up.
	  - Every phase.cooldown seconds it picks the next ability, holds still,
	    and sends a ground warning (Telegraph) to nearby players. When the
	    warning ends the server tests players' *current* positions against
	    the shape (Logic/Telegraph) and resolves hits through
	    CombatService:NpcStrike. Moving out of the marked area dodges.
	  - Summon abilities call adds through MobService (owned by the run).
	  - Enrage (D-47): engaged for enrageSeconds without being defeated, the
	    boss deals 4x damage, uses abilities twice as often and moves
	    faster, so a group too small to kill it in time can't win.
	  - Reset() (wipe or everyone left) returns the boss home at full HP,
	    removes its adds and restarts at phase 1.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local DungeonDefinitions = require(Shared.Definitions.DungeonDefinitions)
local DungeonRules = require(Shared.Logic.DungeonRules)
local Telegraph = require(Shared.Logic.Telegraph)
local Log = require(Shared.Util.Log)

local NetService = require(script.Parent.NetService)
local CombatService = require(script.Parent.CombatService)
local MobService = require(script.Parent.MobService)

local TICK_SECONDS = 0.2
-- Damage multiplier once a boss enrages (DungeonDefinitions enrageSeconds).
local ENRAGE_DAMAGE = 4
local TELEGRAPH_RADIUS = 200

local log = Log.new("BossService")

export type Boss = {
	def: DungeonDefinitions.Boss,
	mob: MobService.Mob,
	phase: number,
	nextAbilityAt: number,
	abilityIndex: number,
	adds: { MobService.Mob },
	-- Called with a notify text key (and params) when a phase begins or the
	-- boss enrages; the owner tells the players around it.
	announce: (key: string, params: { [string]: string }?) -> (),
	owner: string,
	engaged: boolean,
	engagedAt: number,
	enraged: boolean,
	-- The follow-up of a signature combo, used next (D-61).
	pendingCombo: string?,
}

local BossService = {}

local bosses: { [MobService.Mob]: Boss } = {}

local function flat(v: Vector3): { number }
	return { v.X, v.Z }
end

local function sendTelegraph(boss: Boss, payload: { [string]: any })
	local origin = boss.mob.root.Position
	local recipients = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and (root.Position - origin).Magnitude <= TELEGRAPH_RADIUS then
			table.insert(recipients, player)
		end
	end
	if #recipients > 0 then
		NetService:FireClients("Telegraph", recipients, payload)
	end
end

local function nearestPlayerRoot(boss: Boss): BasePart?
	local best: BasePart? = nil
	local bestDistance = math.huge
	local origin = boss.mob.root.Position
	for _, entity in CombatService:LivePlayers() do
		local distance = (entity.root.Position - origin).Magnitude
		if
			distance < bestDistance
			and distance < 90
			and CombatService:CanHarm(boss.mob.model, entity.model)
		then
			best, bestDistance = entity.root, distance
		end
	end
	return best
end

-- How the body moves for each ability shape (MobVisualController).
local MOVE_OF: { [string]: string } = { Circle = "Roar", Cone = "Sweep", Ring = "Slam" }

local function useAbility(boss: Boss, ability: DungeonDefinitions.Ability, now: number)
	local mob = boss.mob
	local root = mob.root
	mob.busyUntil = now + ability.telegraph + 0.35
	local floorY = root.Position.Y - mob.humanoid.HipHeight - root.Size.Y / 2

	if ability.shape == "Summon" then
		CombatService:Broadcast(
			mob.model,
			{ kind = "MobAttack", target = mob.model, windup = ability.telegraph, move = "Roar" }
		)
		task.delay(ability.telegraph, function()
			if mob.dead then
				return
			end
			for i = 1, ability.count or 1 do
				local angle = (i / (ability.count or 1)) * math.pi * 2
				local at = CFrame.new(
					root.Position.X + math.cos(angle) * 10,
					floorY,
					root.Position.Z + math.sin(angle) * 10
				)
				local add = MobService:Spawn(ability.enemy or "RiftWolf", at, {
					owner = boss.owner,
					xpRecipients = mob.xpRecipients,
					level = ability.level,
					-- D-133: a war-zone boss's summons follow the cap too.
					capScaled = mob.capScaled,
				})
				if add then
					add.state = "Chase"
					table.insert(boss.adds, add)
				end
			end
		end)
		return
	end

	-- Where the area lands is fixed when the warning appears.
	local center: Vector3
	local facing = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	if ability.shape == "Circle" then
		local targetRoot = nearestPlayerRoot(boss)
		center = if targetRoot
			then Vector3.new(targetRoot.Position.X, floorY, targetRoot.Position.Z)
			else Vector3.new(root.Position.X, floorY, root.Position.Z)
	else
		center = Vector3.new(root.Position.X, floorY, root.Position.Z)
		local targetRoot = nearestPlayerRoot(boss)
		if targetRoot then
			local toTarget = targetRoot.Position - root.Position
			local flatDir = Vector3.new(toTarget.X, 0, toTarget.Z)
			if flatDir.Magnitude > 0.1 then
				facing = flatDir.Unit
				root.CFrame = CFrame.lookAt(root.Position, root.Position + facing)
			end
		end
	end
	if facing.Magnitude < 0.1 then
		facing = Vector3.new(0, 0, -1)
	end
	facing = facing.Unit

	CombatService:Broadcast(
		mob.model,
		{ kind = "MobAttack", target = mob.model, windup = ability.telegraph, move = MOVE_OF[ability.shape] }
	)
	sendTelegraph(boss, {
		shape = ability.shape,
		center = center,
		radius = ability.radius or 10,
		inner = ability.inner,
		angle = ability.angle,
		facing = facing,
		duration = ability.telegraph,
	})

	task.delay(ability.telegraph, function()
		if mob.dead or bosses[mob] ~= boss then
			return
		end
		local c = flat(center)
		local f = { facing.X, facing.Z }
		for _, entity in CombatService:LivePlayers() do
			local p = flat(entity.root.Position)
			local hit = false
			if ability.shape == "Circle" then
				hit = Telegraph.inCircle(c, ability.radius or 10, p)
			elseif ability.shape == "Cone" then
				hit = Telegraph.inCone(c, f, ability.radius or 10, ability.angle or 90, p)
			elseif ability.shape == "Ring" then
				hit = Telegraph.inRing(c, ability.inner or 0, ability.radius or 10, p)
			end
			-- Height check: no hits through floors.
			if hit and math.abs(entity.root.Position.Y - center.Y) < 12 then
				CombatService:NpcStrike(mob.model, entity.model, ability.coefficient or 0.5, nil, true)
			end
		end
	end)
end

local function stepBoss(boss: Boss, now: number)
	local mob = boss.mob
	if mob.dead then
		return
	end
	local engaged = mob.state == "Chase" or mob.state == "Windup"
	if not engaged then
		boss.engaged = false
		if boss.enraged then
			-- Gave up the fight (leashed home): the rage passes.
			boss.enraged = false
			mob.model:SetAttribute("RC_Enraged", nil)
			CombatService:SetOutgoingScale(mob.model, 1)
		end
		boss.pendingCombo = nil
		return
	end
	if not boss.engaged then
		boss.engaged = true
		boss.engagedAt = now
		boss.nextAbilityAt = now + 3
	end
	-- Enrage (D-47): too slow a fight and the boss overwhelms whoever is left.
	if not boss.enraged and now - boss.engagedAt >= boss.def.enrageSeconds then
		boss.enraged = true
		mob.model:SetAttribute("RC_Enraged", true)
		CombatService:SetOutgoingScale(mob.model, ENRAGE_DAMAGE)
		mob.speedScale = math.max(mob.speedScale, 1.4)
		boss.announce("boss.enraged", { name = mob.enemy.name })
		log:Info("%s enraged after %ds", boss.def.id, boss.def.enrageSeconds)
	end

	local hp = CombatService:HpFraction(mob.model)
	local phaseIndex = DungeonRules.phaseFor(boss.def.phases, hp)
	if phaseIndex ~= boss.phase then
		boss.phase = phaseIndex
		local phase = boss.def.phases[phaseIndex]
		mob.speedScale = phase.speedScale
		if phase.announce then
			boss.announce(`boss.{boss.def.id}.phase{phaseIndex}`)
		end
		boss.nextAbilityAt = math.min(boss.nextAbilityAt, now + 1.5)
	end

	-- Fliers use their abilities on the ground (their dive is the air attack).
	if
		now < boss.nextAbilityAt
		or now < mob.busyUntil
		or mob.state == "Windup"
		or MobService:IsAirborne(mob)
	then
		return
	end
	local phase = boss.def.phases[boss.phase]
	local ability: DungeonDefinitions.Ability?
	local cooldown = if boss.enraged then phase.cooldown * 0.5 else phase.cooldown
	local pending = boss.pendingCombo
	boss.pendingCombo = nil
	if pending then
		ability = boss.def.abilities[pending]
	else
		boss.abilityIndex = boss.abilityIndex % #phase.abilities + 1
		ability = boss.def.abilities[phase.abilities[boss.abilityIndex]]
	end
	boss.nextAbilityAt = now + cooldown + (if ability then ability.telegraph else 0)
	-- Signature combo (second phase on): the follow-up comes straight after.
	local combo = boss.def.combo
	if ability and not pending and combo and boss.phase >= 2 and ability.id == combo.first then
		boss.pendingCombo = combo.second
		boss.nextAbilityAt = now + ability.telegraph + 0.5
	end
	if ability then
		useAbility(boss, ability, now)
	end
end

--[[
	Makes `mob` a boss using definition `bossId`. `announce(textKey)` tells
	the run about phase changes.
]]
function BossService:Attach(
	mob: MobService.Mob,
	bossId: string,
	owner: string,
	announce: (key: string, params: { [string]: string }?) -> ()
): Boss?
	local def = DungeonDefinitions.boss(bossId)
	if def == nil then
		log:Error("unknown boss %s", tostring(bossId))
		return nil
	end
	local boss: Boss = {
		def = def,
		mob = mob,
		phase = 1,
		nextAbilityAt = math.huge,
		abilityIndex = 0,
		adds = {},
		announce = announce,
		owner = owner,
		engaged = false,
		engagedAt = 0,
		enraged = false,
	}
	bosses[mob] = boss
	mob.model:SetAttribute("RC_Boss", bossId)
	-- Bosses shrug off stuns, roots and slows (taunts still work).
	CombatService:SetControlImmune(mob.model, true)
	return boss
end

function BossService:Detach(mob: MobService.Mob)
	bosses[mob] = nil
end

-- Wipe / everyone left: home, full HP, phase 1, adds removed.
function BossService:Reset(boss: Boss)
	for _, add in boss.adds do
		MobService:Despawn(add)
	end
	boss.adds = {}
	boss.phase = 1
	boss.abilityIndex = 0
	boss.engaged = false
	boss.enraged = false
	boss.pendingCombo = nil
	boss.mob.model:SetAttribute("RC_Enraged", nil)
	boss.nextAbilityAt = math.huge
	boss.mob.speedScale = 1
	CombatService:SetOutgoingScale(boss.mob.model, 1)
	MobService:Reset(boss.mob)
	CombatService:RestoreNpc(boss.mob.model)
end

function BossService:Start()
	task.spawn(function()
		while true do
			task.wait(TICK_SECONDS)
			local now = os.clock()
			for _, boss in bosses do
				local ok, err = pcall(stepBoss :: any, boss, now)
				if not ok then
					log:Error("boss %s tick failed: %s", boss.def.id, tostring(err))
				end
			end
		end
	end)
end

return BossService
