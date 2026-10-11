--!strict
--[[
	BasicAttacks — each job's always-available attack, a 3-step combo chain
	(Phase 6 combat; Phase 5 adds the skill loadout on top). PLAN.md D-36.

	Pressing (or holding) attack walks the chain: step 1 -> 2 -> 3 (finisher)
	as long as each press comes within `window` seconds after the previous
	step's `recovery`; otherwise it starts again at step 1. After the
	finisher the chain pauses for `finisherCooldown`.

	  clip             AnimationClips name; its `Hit` marker is when the hit
	                   lands (melee) or the projectile leaves (ranged)
	  coefficient      multiplies the attacker's Attack (CombatMath.damage)
	  recovery         seconds after the step starts before the next press counts
	  window           seconds after `recovery` that continue the chain
	  projectileSpeed  studs/s for ranged steps (nil = lands at `Hit`)
	  lunge            studs a melee step may step in toward its target
	  heavy            finisher: heavy hit reaction, stronger hit-stop/shake
	  vfx              CombatVfx effect name

	The server owns all of these; clients only predict the animation.
	Display-safe data only. Pure module.
]]

local AnimationClips = require(script.Parent.AnimationClips)

export type Vfx =
	"SlashAcross"
	| "SlashRising"
	| "Cleave"
	| "Bolt"
	| "Nova"
	| "Missile"
	| "PalmMissile"
	| "Burst"
	| "Arrow"
	| "PowerArrow"

export type ComboStep = {
	clip: string,
	coefficient: number,
	recovery: number,
	window: number,
	projectileSpeed: number?,
	lunge: number?,
	heavy: boolean?,
	vfx: Vfx,
}

export type BasicAttack = {
	job: string,
	name: string,
	range: number,
	-- Melee attacks may auto-target within a forward cone; ranged need line of sight.
	style: "Melee" | "Ranged" | "Magic",
	steps: { ComboStep },
	finisherCooldown: number,
}

local BasicAttacks = {}

-- Combo chain timing shared by every job (seconds).
local WINDOW = 0.6

BasicAttacks.ByJob = {
	Warrior = {
		job = "Warrior",
		name = "Blade Combo",
		range = 8,
		style = "Melee",
		finisherCooldown = 0.35,
		steps = {
			{
				clip = "Warrior_Attack1",
				coefficient = 0.65,
				recovery = 0.45,
				window = WINDOW,
				lunge = 2.5,
				vfx = "SlashAcross",
			},
			{
				clip = "Warrior_Attack2",
				coefficient = 0.7,
				recovery = 0.45,
				window = WINDOW,
				lunge = 2.5,
				vfx = "SlashRising",
			},
			{
				clip = "Warrior_Attack3",
				coefficient = 1.15,
				recovery = 0.75,
				window = WINDOW,
				lunge = 3.5,
				heavy = true,
				vfx = "Cleave",
			},
		},
	},
	Healer = {
		job = "Healer",
		name = "Radiant Chain",
		range = 32,
		style = "Magic",
		finisherCooldown = 0.35,
		steps = {
			{
				clip = "Healer_Attack1",
				coefficient = 0.42,
				recovery = 0.5,
				window = WINDOW,
				projectileSpeed = 110,
				vfx = "Bolt",
			},
			{
				clip = "Healer_Attack2",
				coefficient = 0.45,
				recovery = 0.5,
				window = WINDOW,
				projectileSpeed = 110,
				vfx = "Bolt",
			},
			{
				clip = "Healer_Attack3",
				coefficient = 0.67,
				recovery = 0.85,
				window = WINDOW,
				heavy = true,
				vfx = "Nova",
			},
		},
	},
	Mage = {
		job = "Mage",
		name = "Arcane Chain",
		range = 40,
		style = "Magic",
		finisherCooldown = 0.4,
		steps = {
			{
				clip = "Mage_Attack1",
				coefficient = 0.55,
				recovery = 0.42,
				window = WINDOW,
				projectileSpeed = 120,
				vfx = "Missile",
			},
			{
				clip = "Mage_Attack2",
				coefficient = 0.6,
				recovery = 0.46,
				window = WINDOW,
				projectileSpeed = 120,
				vfx = "PalmMissile",
			},
			{
				clip = "Mage_Attack3",
				coefficient = 0.93,
				recovery = 0.9,
				window = WINDOW,
				projectileSpeed = 90,
				heavy = true,
				vfx = "Burst",
			},
		},
	},
	Archer = {
		job = "Archer",
		name = "Hunter's Volley",
		range = 48,
		style = "Ranged",
		finisherCooldown = 0.35,
		steps = {
			{
				clip = "Archer_Attack1",
				coefficient = 0.58,
				recovery = 0.5,
				window = WINDOW,
				projectileSpeed = 160,
				vfx = "Arrow",
			},
			{
				clip = "Archer_Attack2",
				coefficient = 0.6,
				recovery = 0.45,
				window = WINDOW,
				projectileSpeed = 160,
				vfx = "Arrow",
			},
			{
				clip = "Archer_Attack3",
				coefficient = 0.94,
				recovery = 0.95,
				window = WINDOW,
				projectileSpeed = 200,
				heavy = true,
				vfx = "PowerArrow",
			},
		},
	},
} :: { [string]: BasicAttack }

local function deepFreeze(value: any): any
	if type(value) == "table" and not table.isfrozen(value) then
		for _, child in value do
			deepFreeze(child)
		end
		table.freeze(value)
	end
	return value
end
deepFreeze(BasicAttacks.ByJob)

function BasicAttacks.forJob(job: any): BasicAttack?
	if type(job) ~= "string" then
		return nil
	end
	return BasicAttacks.ByJob[job]
end

-- When step `step` lands: its clip's Hit marker (seconds after it starts).
function BasicAttacks.hitTime(step: ComboStep): number
	local clip = AnimationClips.get(step.clip)
	local markers = clip and clip.markers
	return if markers and markers.Hit then markers.Hit else 0.2
end

-- The attack and step index that use `clip`, if any.
function BasicAttacks.stepForClip(clip: any): (BasicAttack?, number?)
	for _, attack in BasicAttacks.ByJob do
		for index, step in attack.steps do
			if step.clip == clip then
				return attack, index
			end
		end
	end
	return nil, nil
end

-- Full-chain damage per second (balance checks).
function BasicAttacks.chainDps(attack: BasicAttack): number
	local total, time = 0, attack.finisherCooldown
	for _, step in attack.steps do
		total += step.coefficient
		time += step.recovery
	end
	return total / time
end

return table.freeze(BasicAttacks)
