--!strict
--[[
	CreatureRigs — skeletons and gaits of the procedural creatures
	(creature overhaul stage 1, PLAN.md D-51). Display data only; the
	server builds the bones (World/CreatureBuilder) and the client walks
	them (MobVisualController, Logic/CreatureIK).

	Per body plan:
	  bodyCenter  centre of the "Body" part relative to the root (unscaled)
	  height      standing height of the root centre above the ground
	  legs        three-bone legs jointed to the Body part:
	                name     upper joint; lower `name.."b"`, foot `name.."c"`
	                hip      joint in the Body frame
	                reach    foot home (x, z) from the hip, Body frame
	                splay    yaw of the leg's plane in degrees (0 = forward;
	                         insects reach sideways)
	                lengths  upper, lower, foot bones; widths their thickness
	                bend     +1 knee forward / outward, -1 back (a dog's
	                         elbow; its stifle is forward, hock back)
	                footAngle  the foot bone's angle from vertical (degrees)
	                walk / run / trot  phase offsets of the step cycle
	Gaits (stride per cycle in studs at size 1; duty = share of the cycle a
	foot is on the ground):
	  Predator    wolves: 4-beat walk into a rotary gallop
	  Heavy       giant beasts: long deliberate walk into a trot, deep
	              footfalls
	  Crawler     insects: alternating tripods
	  Biped       golems and knights: alternating strides
	  HeavyBiped  colossal bipeds: slow, swaying, deep footfalls
]]

local CreatureRigs = {}

export type Leg = {
	name: string,
	hip: Vector3,
	reach: Vector2,
	splay: number,
	lengths: { number },
	widths: { number },
	bend: number,
	footAngle: number,
	walk: number,
	run: number,
	trot: number,
	front: boolean,
	side: number,
}

export type Plan = {
	bodyCenter: Vector3,
	height: number,
	legs: { Leg },
}

export type Gait = {
	name: string,
	stride: number,
	runStride: number,
	duty: number,
	runDuty: number,
	lift: number,
	runLift: number,
	-- Speed (studs/s at size 1) where the run gait is fully reached.
	runSpeed: number,
	-- Body dip at each footfall and side-to-side sway (studs / degrees).
	bob: number,
	sway: number,
	-- Run with diagonal pairs (trot) instead of a gallop.
	trot: boolean,
	-- How far the body sinks at a full run (studs at size 1): bent legs
	-- reach further, so strides lengthen instead of pattering.
	crouch: number,
}

-- The foot bone's tip rests this far above the ground (paws / soles
-- reach below it).
CreatureRigs.FOOT_CLEARANCE = 0.12

local function quadLeg(
	name: string,
	side: number,
	front: boolean,
	hip: Vector3,
	lengths: { number },
	widths: { number },
	walk: number,
	run: number,
	trot: number
): Leg
	return {
		name = name,
		hip = hip,
		reach = Vector2.new(side * 0.05, if front then -0.1 else 0.15),
		splay = 0,
		lengths = lengths,
		widths = widths,
		-- Elbow back on the forelegs; stifle forward on the hind legs.
		bend = if front then -1 else 1,
		footAngle = if front then 4 else 18,
		walk = walk,
		run = run,
		trot = trot,
		front = front,
		side = side,
	}
end

local FORE = { 1.1, 1.05, 0.45 }
local FORE_W = { 0.78, 0.46, 0.34 }
local HIND = { 1.0, 1.1, 0.78 }
local HIND_W = { 0.95, 0.5, 0.32 }

-- Wolf (and the beasts built on it).
local WOLF: Plan = {
	bodyCenter = Vector3.new(0, 0.3, 0.2),
	height = 2.45,
	legs = {
		-- Walk: lateral sequence (LF, RH, RF, LH); run: rotary gallop.
		quadLeg("LegFL", -1, true, Vector3.new(-0.72, -0.45, -1.6), FORE, FORE_W, 0, 0, 0),
		quadLeg("LegFR", 1, true, Vector3.new(0.72, -0.45, -1.6), FORE, FORE_W, 0.5, 0.12, 0.5),
		quadLeg("LegBL", -1, false, Vector3.new(-0.72, -0.4, 1.2), HIND, HIND_W, 0.75, 0.55, 0.5),
		quadLeg("LegBR", 1, false, Vector3.new(0.72, -0.4, 1.2), HIND, HIND_W, 0.25, 0.65, 0),
	},
}

-- Beetle: six legs reaching out sideways, front pair angled forward,
-- back pair angled back. Tripods: legs 1, 4, 5 and 2, 3, 6.
local BEETLE_LEGS: { Leg } = {}
do
	local index = 0
	for row, z in { -1.2, 0, 1.2 } do
		for _, side in { -1, 1 } do
			index += 1
			-- Plane yaw: -Z of the leg points outward (+ forward / back).
			local lean = if row == 1 then 45 elseif row == 2 then 90 else 135
			local splay = -side * lean
			local yaw = math.rad(splay)
			local out = Vector2.new(-math.sin(yaw), -math.cos(yaw)) * 1.7
			local tripod = if index == 1 or index == 4 or index == 5 then 0 else 0.5
			table.insert(BEETLE_LEGS, {
				name = `Leg{index}`,
				hip = Vector3.new(side * 1.4, -0.2, z),
				reach = out,
				splay = splay,
				lengths = { 1.4, 2.0, 0.35 },
				widths = { 0.36, 0.28, 0.2 },
				bend = 1,
				footAngle = 12,
				walk = tripod,
				run = tripod,
				trot = tripod,
				front = row == 1,
				side = side,
			})
		end
	end
end

local BEETLE: Plan = {
	bodyCenter = Vector3.new(0, 0.45, 0),
	height = 2.0,
	legs = BEETLE_LEGS,
}

local BIPED_LEG = { 1.45, 1.45, 0.35 }
local BIPED_W = { 1.4, 1.25, 0.9 }

-- Golems and armoured knights.
local BIPED: Plan = {
	bodyCenter = Vector3.new(0, 1.6, 0),
	height = 3.2,
	legs = {
		{
			name = "LegL",
			hip = Vector3.new(-0.85, -1.8, 0),
			reach = Vector2.new(-0.1, 0),
			splay = 0,
			lengths = BIPED_LEG,
			widths = BIPED_W,
			bend = 1,
			footAngle = 0,
			walk = 0,
			run = 0,
			trot = 0,
			front = false,
			side = -1,
		},
		{
			name = "LegR",
			hip = Vector3.new(0.85, -1.8, 0),
			reach = Vector2.new(0.1, 0),
			splay = 0,
			lengths = BIPED_LEG,
			widths = BIPED_W,
			bend = 1,
			footAngle = 0,
			walk = 0.5,
			run = 0.5,
			trot = 0.5,
			front = false,
			side = 1,
		},
	},
}

CreatureRigs.Plans = table.freeze({
	Wolf = WOLF,
	Beetle = BEETLE,
	Golem = BIPED,
	Guardian = BIPED,
}) :: { [string]: Plan }

CreatureRigs.Gaits = table.freeze({
	Predator = {
		name = "Predator",
		stride = 4.2,
		runStride = 7.5,
		duty = 0.62,
		runDuty = 0.38,
		lift = 0.35,
		runLift = 0.7,
		runSpeed = 14,
		bob = 0.08,
		sway = 2,
		trot = false,
		crouch = 0.28,
	},
	Heavy = {
		name = "Heavy",
		stride = 3.4,
		runStride = 5,
		duty = 0.7,
		runDuty = 0.52,
		lift = 0.3,
		runLift = 0.5,
		runSpeed = 9,
		bob = 0.16,
		sway = 3,
		trot = true,
		crouch = 0.22,
	},
	Crawler = {
		name = "Crawler",
		stride = 2.4,
		runStride = 3.4,
		duty = 0.55,
		runDuty = 0.5,
		lift = 0.45,
		runLift = 0.55,
		runSpeed = 10,
		bob = 0.04,
		sway = 2,
		trot = false,
		crouch = 0.06,
	},
	Biped = {
		name = "Biped",
		stride = 4.6,
		runStride = 6.4,
		duty = 0.62,
		runDuty = 0.5,
		lift = 0.45,
		runLift = 0.7,
		runSpeed = 12,
		bob = 0.12,
		sway = 3,
		trot = false,
		crouch = 0.14,
	},
	HeavyBiped = {
		name = "HeavyBiped",
		stride = 3.8,
		runStride = 5,
		duty = 0.68,
		runDuty = 0.58,
		lift = 0.35,
		runLift = 0.5,
		runSpeed = 9,
		bob = 0.22,
		sway = 5,
		trot = false,
		crouch = 0.14,
	},
}) :: { [string]: Gait }

-- Bodies at or above this size move like heavy beasts.
CreatureRigs.HEAVY_SCALE = 2

function CreatureRigs.plan(body: string): Plan?
	return CreatureRigs.Plans[body]
end

function CreatureRigs.gaitFor(body: string, scale: number): Gait?
	local heavy = scale >= CreatureRigs.HEAVY_SCALE
	if body == "Wolf" then
		return CreatureRigs.Gaits[if heavy then "Heavy" else "Predator"]
	elseif body == "Beetle" then
		return CreatureRigs.Gaits.Crawler
	elseif body == "Golem" or body == "Guardian" then
		return CreatureRigs.Gaits[if heavy then "HeavyBiped" else "Biped"]
	end
	return nil
end

--[[
	Sculpted mesh (Animation/CreatureMeshes, imported model
	CreatureModels/<shape>) an enemy uses, when one carries all of its
	anatomy; nil keeps the procedural body (D-52 batch A: hounds, Cerberus,
	serpents, hydras; D-57 batch B: beetles, spiders, golems, knights,
	lions, the chimera; D-58 batch C: dragons, griffins, steeds, the bat,
	the harpy, the gorgon, the sprite). Traits the mesh does not model
	keep the procedural body until their mesh exists.
]]
local MESH_TRAITS: { [string]: { [string]: boolean } } = {
	-- Ahuizotl's serpent tail is drawn as the hound's tail.
	Hound = { Mane = true, Spikes = true, SerpentTail = true },
	Cerberus = { ThreeHeads = true, Mane = true, Spikes = true },
	Serpent = { Crest = true, Spikes = true },
	Hydra = { ThreeHeads = true, Spikes = true },
	Beetle = {},
	Spider = {},
	Golem = { Spikes = true },
	Knight = { Horns = true },
	Lion = { Mane = true, Wings = true, SerpentTail = true, Horns = true },
	Chimera = { Mane = true, Horns = true, Wings = true, SerpentTail = true },
	Dragon = { Wings = true, Horns = true, SerpentTail = true },
	Griffin = { Wings = true },
	Steed = { Wings = true, Horns = true },
	Bat = { Wings = true, Spikes = true },
	Harpy = { Wings = true },
	Gorgon = { SerpentTail = true },
	Sprite = {},
	-- D-133: the undead.
	Skeleton = {},
	Zombie = {},
	DeathKnight = {},
	Dullahan = {},
	DeathLord = {},
}

-- Enemies whose shape is not the default for their body.
local SHAPE_BY_ENEMY: { [string]: string } = {
	Arachne = "Spider",
	Scylla = "Spider",
	Charybdis = "Spider",
	NemeanLion = "Lion",
	Sphinx = "Lion",
	Manticore = "Lion",
	Chimera = "Chimera",
	Nian = "Lion",
	Taotie = "Lion",
	Ahuizotl = "Hound",
	Fafnir = "Dragon",
	Wyvern = "Dragon",
	Typhon = "Dragon",
	Griffin = "Griffin",
	Anzu = "Griffin",
	Cockatrice = "Griffin",
	Kelpie = "Steed",
	Peryton = "Steed",
	Camazotz = "Bat",
	HarpyQueen = "Harpy",
	Gorgon = "Gorgon",
	-- D-133: the Abyssal Spire's undead.
	SkeletonSoldier = "Skeleton",
	AshboneWarrior = "Skeleton",
	WraithboneSentry = "Skeleton",
	GraveGhoul = "Zombie",
	CinderHusk = "Zombie",
	DeathKnight = "DeathKnight",
	GraveKnight = "DeathKnight",
	Dullahan = "Dullahan",
	DreadDullahan = "Dullahan",
	DeathLord = "DeathLord",
}

--[[
	Optional parts of a mesh (a region with its own MeshPart): kept only
	when the enemy has the trait (wings on a lion, the Manticore's sting,
	helm horns, crystal spikes), or (`MESH_REPLACED_REGIONS`) only when it
	does not (a lion's tail tuft gives way to the sting).
]]
CreatureRigs.MESH_OPTIONAL_REGIONS = table.freeze({
	Wing = "Wings",
	Sting = "SerpentTail",
	Horns = "Horns",
	Spikes = "Spikes",
}) :: { [string]: string }

CreatureRigs.MESH_REPLACED_REGIONS = table.freeze({
	Tuft = "SerpentTail",
}) :: { [string]: string }

function CreatureRigs.meshShapeFor(body: string, traits: { string }?, enemyId: string?): string?
	local has: { [string]: boolean } = {}
	for _, trait in (traits or {}) :: { string } do
		has[trait] = true
	end
	local shape: string? = if enemyId then SHAPE_BY_ENEMY[enemyId] else nil
	if shape == nil then
		-- The default shape for the body.
		if body == "Wolf" then
			shape = if has.ThreeHeads then "Cerberus" else "Hound"
		elseif body == "Serpent" then
			shape = if has.ThreeHeads then "Hydra" else "Serpent"
		elseif body == "Beetle" then
			shape = "Beetle"
		elseif body == "Golem" then
			shape = "Golem"
		elseif body == "Guardian" then
			shape = "Knight"
		elseif body == "Sprite" then
			shape = "Sprite"
		end
	end
	if shape == nil then
		return nil
	end
	local allowed = MESH_TRAITS[shape]
	for trait in has do
		if not allowed[trait] then
			return nil
		end
	end
	return shape
end

-- Collision box of a meshed creature at size 1 (the root sits on the Body bone).
CreatureRigs.MESH_ROOT_SIZE = table.freeze({
	Hound = Vector3.new(1.8, 2, 3.6),
	Cerberus = Vector3.new(2.4, 2.2, 3.8),
	Serpent = Vector3.new(1.6, 1.2, 3),
	Hydra = Vector3.new(3, 2, 4.2),
	Beetle = Vector3.new(2, 1.2, 3),
	Spider = Vector3.new(2, 1.2, 2.6),
	Golem = Vector3.new(2.4, 2.4, 1.8),
	Knight = Vector3.new(1.8, 2.2, 1.4),
	Lion = Vector3.new(2, 2, 3.8),
	Chimera = Vector3.new(2.2, 2.2, 4),
	Dragon = Vector3.new(2.4, 2, 4.2),
	Griffin = Vector3.new(2, 2, 3.8),
	Steed = Vector3.new(1.8, 2.4, 3.6),
	Bat = Vector3.new(2, 2, 3.6),
	Harpy = Vector3.new(1.4, 2, 1.2),
	Gorgon = Vector3.new(1.6, 1.2, 3),
	Sprite = Vector3.new(1.2, 1.2, 1.2),
	Skeleton = Vector3.new(1.4, 2.2, 1.2),
	Zombie = Vector3.new(1.6, 2.1, 1.6),
	DeathKnight = Vector3.new(1.9, 2.3, 1.4),
	Dullahan = Vector3.new(1.9, 2.2, 1.4),
	DeathLord = Vector3.new(2, 2.4, 1.6),
}) :: { [string]: Vector3 }

-- Ground height in the Body frame at rest (unscaled).
function CreatureRigs.groundInBody(plan: Plan): number
	return -plan.height - plan.bodyCenter.Y
end

--[[
	Where a leg's foot rests, as (forward, down) in the leg's plane from its
	hip, on flat ground at rest (unscaled).
]]
function CreatureRigs.restReach(plan: Plan, leg: Leg): (number, number)
	local down = leg.hip.Y - CreatureRigs.groundInBody(plan) - CreatureRigs.FOOT_CLEARANCE
	local forward: number
	if leg.splay ~= 0 then
		forward = leg.reach.Magnitude
	else
		forward = -leg.reach.Y
	end
	return forward, down
end

return table.freeze(CreatureRigs)
