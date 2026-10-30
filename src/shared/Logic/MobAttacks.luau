--!strict
--[[
	MobAttacks — each kind of creature's set of basic attacks, how it picks
	one, and what a strike can hit (creature overhaul stage 4, PLAN.md
	D-61). Pure. MobService winds up the chosen move, resolves it when the
	wind-up ends (CombatService re-checks harm and range) and holds the
	creature still through its recovery.

	A move scales the creature's own numbers (EnemyDefinitions):
	  anim     the client motion (MobVisualController: Strike lunges, Slam
	           rears and slams, Roar stomps, Sweep swings across)
	  windup   x enemy.windup (heavier moves telegraph longer)
	  damage   x enemy.attackCoefficient
	  reach    x enemy.attackRange
	  arc      degrees in front it covers (360: all round); a target that
	           got behind the creature during the wind-up is missed
	  area     hits everyone it covers, not just the creature's target
	  recover  seconds it stands open afterwards
	  weight   how often it is picked
]]

local MobAttacks = {}

export type Anim = "Strike" | "Slam" | "Roar" | "Sweep"

export type Move = {
	id: string,
	anim: Anim,
	windup: number,
	damage: number,
	reach: number,
	arc: number,
	area: boolean,
	recover: number,
	weight: number,
}

export type SetName = "Predator" | "Serpent" | "Brute" | "Crawler" | "Beast" | "Sprite" | "Undead" | "Ghoul"

local function move(
	id: string,
	anim: Anim,
	windup: number,
	damage: number,
	reach: number,
	arc: number,
	area: boolean,
	recover: number,
	weight: number
): Move
	return table.freeze({
		id = id,
		anim = anim,
		windup = windup,
		damage = damage,
		reach = reach,
		arc = arc,
		area = area,
		recover = recover,
		weight = weight,
	})
end

MobAttacks.Sets = table.freeze({
	-- Hounds, big cats, the bat, griffins, the chimera: snapping bites,
	-- raking claws, and a long telegraphed pounce.
	Predator = {
		move("Bite", "Strike", 1, 1, 1, 80, false, 0.45, 5),
		move("Claw", "Sweep", 0.8, 0.8, 0.9, 150, true, 0.35, 3),
		move("Pounce", "Slam", 1.35, 1.35, 1.6, 70, false, 0.8, 2),
	},
	-- Serpents, hydras, the gorgon: a striking bite, a tail sweep all
	-- round, a long lunge.
	Serpent = {
		move("Bite", "Strike", 1, 1, 1, 70, false, 0.5, 5),
		move("TailSweep", "Sweep", 1.25, 0.85, 1.15, 360, true, 0.6, 2),
		move("Lunge", "Slam", 1.4, 1.3, 1.5, 50, false, 0.8, 2),
	},
	-- Golems, knights, the harpy: an overhead smash, a wide swing, a stomp
	-- that shakes everyone close.
	Brute = {
		move("Smash", "Slam", 1.15, 1.2, 1, 100, false, 0.7, 4),
		move("Swing", "Sweep", 0.9, 0.85, 1.05, 170, true, 0.45, 4),
		move("Stomp", "Roar", 1.4, 0.8, 0.85, 360, true, 0.7, 2),
	},
	-- Beetles and spiders: quick pincers, a charging ram, rearing up to
	-- crash down.
	Crawler = {
		move("Pincer", "Strike", 0.9, 0.9, 1, 80, false, 0.35, 5),
		move("Ram", "Strike", 1.3, 1.25, 1.5, 60, false, 0.7, 2),
		move("Rear", "Slam", 1.15, 1.1, 1, 100, true, 0.5, 2),
	},
	-- Dragons and steeds: a bite, a trampling stomp, a tail sweep.
	Beast = {
		move("Bite", "Strike", 1, 1, 1, 80, false, 0.5, 4),
		move("Trample", "Slam", 1.2, 1.15, 0.95, 120, true, 0.6, 3),
		move("TailSweep", "Sweep", 1.2, 0.9, 1.2, 360, true, 0.6, 2),
	},
	Sprite = {
		move("Zap", "Strike", 1, 1, 1, 120, false, 0.3, 1),
	},
	-- D-133: armed undead (skeletons, death knights, dullahans, the Death
	-- Lord): a quick thrust, a wide cleave, an overhead blow that cracks
	-- the ground.
	Undead = {
		move("Thrust", "Strike", 0.95, 1, 1.05, 70, false, 0.4, 5),
		move("Cleave", "Sweep", 1, 0.9, 1.1, 160, true, 0.5, 3),
		move("Doomblow", "Slam", 1.4, 1.35, 1.05, 90, true, 0.8, 2),
	},
	-- Ghouls: grasping claws, a flailing swipe, a lunge.
	Ghoul = {
		move("Claw", "Strike", 0.9, 0.95, 1, 80, false, 0.4, 5),
		move("Flail", "Sweep", 1, 0.8, 0.95, 150, true, 0.45, 3),
		move("Lunge", "Slam", 1.3, 1.25, 1.5, 60, false, 0.8, 2),
	},
}) :: { [SetName]: { Move } }

local SET_OF_SHAPE: { [string]: SetName } = {
	Hound = "Predator",
	Cerberus = "Predator",
	Lion = "Predator",
	Bat = "Predator",
	Griffin = "Predator",
	Chimera = "Predator",
	Serpent = "Serpent",
	Hydra = "Serpent",
	Gorgon = "Serpent",
	Golem = "Brute",
	Knight = "Brute",
	Harpy = "Brute",
	Beetle = "Crawler",
	Spider = "Crawler",
	Dragon = "Beast",
	Steed = "Beast",
	Sprite = "Sprite",
	Skeleton = "Undead",
	DeathKnight = "Undead",
	Dullahan = "Undead",
	DeathLord = "Undead",
	Zombie = "Ghoul",
}

local SET_OF_BODY: { [string]: SetName } = {
	Wolf = "Predator",
	Serpent = "Serpent",
	Golem = "Brute",
	Guardian = "Brute",
	Beetle = "Crawler",
}

-- The set for a creature's sculpted shape (CreatureRigs.meshShapeFor), or
-- its body plan when it has none.
function MobAttacks.setFor(body: string, shape: string?): SetName
	return (shape and SET_OF_SHAPE[shape]) or SET_OF_BODY[body] or "Sprite"
end

--[[
	Picks the next move: any move whose reach covers `distance`, weighted;
	a special move (not the first) is half as likely straight after itself.
	`roll` 0..1 (server RNG).
]]
function MobAttacks.choose(
	set: SetName,
	distance: number,
	attackRange: number,
	roll: number,
	lastId: string?
): Move
	local moves = MobAttacks.Sets[set]
	local candidates: { Move } = {}
	local weights: { number } = {}
	local total = 0
	for index, candidate in moves do
		if distance <= candidate.reach * attackRange + 0.5 then
			local weight = candidate.weight
			if index > 1 and candidate.id == lastId then
				weight *= 0.5
			end
			table.insert(candidates, candidate)
			table.insert(weights, weight)
			total += weight
		end
	end
	if #candidates == 0 then
		return moves[1]
	end
	local pick = roll * total
	for index, candidate in candidates do
		pick -= weights[index]
		if pick < 0 then
			return candidate
		end
	end
	return candidates[#candidates]
end

--[[
	Whether a point `to` (offset from the creature, {x, z}) lies inside a
	move's `arc` in front of `facing` (unit {x, z}). Right on top of the
	creature always counts.
]]
function MobAttacks.inArc(facing: { number }, to: { number }, arc: number): boolean
	if arc >= 360 then
		return true
	end
	local d = math.sqrt(to[1] * to[1] + to[2] * to[2])
	if d < 1 then
		return true
	end
	local cosTo = (to[1] * facing[1] + to[2] * facing[2]) / d
	return cosTo >= math.cos(math.rad(arc / 2))
end

return table.freeze(MobAttacks)
