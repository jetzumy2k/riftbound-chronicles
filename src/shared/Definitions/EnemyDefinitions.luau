--!strict
--[[
	EnemyDefinitions — dungeon and field creatures (CLAUDE.md §11/§18,
	Phase 9). Non-graphic, believable fantasy creatures.

	Stats start from the player formula at the enemy's level
	(StatFormulas.forLevel) and are scaled:
	  hpScale / attackScale / defenseScale   multipliers
	  attackCoefficient                       per-hit damage coefficient
	Behaviour (MobBrain):
	  aggroRadius   notices players this close
	  leashRadius   gives up beyond this distance from its spawn
	  attackRange   studs; windup = telegraph seconds before the hit lands
	  attackCooldown seconds between attacks
	  moveSpeed     Humanoid.WalkSpeed
	Rewards: xp per defeat (shared with the party, DungeonRules.shareXp).
	Visual: body plan + palette for the procedural creature builder.

	Display-safe data only. Pure module.
]]

export type Body = "Wolf" | "Beetle" | "Golem" | "Sprite" | "Guardian"

export type Enemy = {
	id: string,
	name: string,
	level: number,
	elite: boolean,
	hpScale: number,
	attackScale: number,
	defenseScale: number,
	attackCoefficient: number,
	attackRange: number,
	windup: number,
	attackCooldown: number,
	aggroRadius: number,
	leashRadius: number,
	moveSpeed: number,
	xp: number,
	body: Body,
	scale: number,
	-- {r, g, b}
	color: { number },
	glow: { number },
}

local EnemyDefinitions = {}

local enemies: { [string]: Enemy } = {
	-- Training Grounds critter (Quest 1: "defeat 5 training creatures").
	RiftSprite = {
		id = "RiftSprite",
		name = "Rift Sprite",
		level = 0,
		elite = false,
		hpScale = 0.9,
		attackScale = 0.5,
		defenseScale = 0.6,
		attackCoefficient = 0.12,
		attackRange = 5,
		windup = 0.45,
		attackCooldown = 2.2,
		aggroRadius = 14,
		leashRadius = 40,
		moveSpeed = 10,
		xp = 20,
		body = "Sprite",
		scale = 0.8,
		color = { 150, 200, 255 },
		glow = { 190, 240, 255 },
	},
	RiftWolf = {
		id = "RiftWolf",
		name = "Rift Wolf",
		level = 1,
		elite = false,
		hpScale = 1.1,
		attackScale = 0.9,
		defenseScale = 1,
		attackCoefficient = 0.22,
		attackRange = 6,
		windup = 0.4,
		attackCooldown = 1.6,
		aggroRadius = 34,
		leashRadius = 90,
		moveSpeed = 17,
		xp = 30,
		body = "Wolf",
		scale = 1,
		color = { 70, 76, 96 },
		glow = { 120, 200, 255 },
	},
	CrystalBeetle = {
		id = "CrystalBeetle",
		name = "Crystal Beetle",
		level = 2,
		elite = false,
		hpScale = 1.6,
		attackScale = 0.9,
		defenseScale = 1.4,
		attackCoefficient = 0.28,
		attackRange = 6.5,
		windup = 0.6,
		attackCooldown = 2.2,
		aggroRadius = 30,
		leashRadius = 90,
		moveSpeed = 11,
		xp = 45,
		body = "Beetle",
		scale = 1.1,
		color = { 52, 70, 88 },
		glow = { 140, 110, 255 },
	},
	StonebackGuardian = {
		id = "StonebackGuardian",
		name = "Stoneback Guardian",
		level = 3,
		elite = true,
		hpScale = 4,
		attackScale = 1.1,
		defenseScale = 1.6,
		attackCoefficient = 0.45,
		attackRange = 9,
		windup = 0.9,
		attackCooldown = 2.8,
		aggroRadius = 34,
		leashRadius = 90,
		moveSpeed = 10,
		xp = 120,
		body = "Golem",
		scale = 1.5,
		color = { 112, 106, 98 },
		glow = { 120, 220, 255 },
	},
	-- Boss: abilities and phases live in DungeonDefinitions (Bosses).
	RiftGuardian = {
		id = "RiftGuardian",
		name = "Rift Guardian",
		level = 4,
		elite = true,
		hpScale = 14,
		attackScale = 1.1,
		defenseScale = 1.6,
		attackCoefficient = 0.4,
		attackRange = 11,
		windup = 0.8,
		attackCooldown = 2.6,
		aggroRadius = 60,
		leashRadius = 70,
		moveSpeed = 12,
		xp = 350,
		body = "Guardian",
		scale = 2.4,
		color = { 96, 92, 104 },
		glow = { 110, 200, 255 },
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

EnemyDefinitions.ById = deepFreeze(enemies) :: { [string]: Enemy }

function EnemyDefinitions.get(id: any): Enemy?
	if type(id) ~= "string" then
		return nil
	end
	return EnemyDefinitions.ById[id]
end

return table.freeze(EnemyDefinitions)
