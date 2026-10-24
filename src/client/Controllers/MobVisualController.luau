--!strict
--[[
	MobVisualController — procedural creature animation (Phase 9, D-42;
	creature-like bosses, creator review 2026-10-17; authored creature art
	is Phase 16 / D-40). Display only.

	Creatures from World/CreatureBuilder carry their limbs on Motor6D joints
	named after the part (chains such as tails, necks, wing tips and jaws
	joint to the limb before them). Each frame, for nearby creatures, this
	sets the joints' Transform from a small body simulation. Every offset is
	scaled by the creature's size (RC_Scale), so a giant boss moves as much
	as a wolf does for its size:

	  Locomotion  (D-51) legs are three bones solved by inverse kinematics
	              (Logic/CreatureIK) to reach foot targets: each foot is
	              planted through its stance and lifted along an arc through
	              its swing, the step cycle advancing with the distance
	              walked (Animation/CreatureRigs gaits), so feet never
	              slide. Wolves walk in a 4-beat sequence and gallop; giant
	              beasts walk long and trot, dropping their weight on every
	              footfall; beetles step in alternating tripods; golems
	              stride with swaying hips and counter-swinging arms and
	              elbows. Near the camera each foot follows the ground
	              (raycasts) and the body pitches with the slope. Serpents
	              slither (a wave travels down the body); sprites hover.
	  Meshes      (D-52) sculpted creatures (RC_Shape: Hound, Cerberus,
	              Serpent, Hydra) are skinned meshes on Bones; the same
	              motions drive the bones (Bone.Transform), legs solved from
	              the bone they hang from (forward kinematics through the
	              Body / Chest / Hips bones), with the generated skeleton
	              data (Animation/CreatureMeshes). Hounds flex the spine at a
	              gallop; hydras sprawl, trot and sway three necks.
	  Turning     the body banks into turns and the head leads them; it
	              pitches back when speeding up and forward when braking.
	  Awareness   heads turn to watch the nearest player in range; a
	              creature with several heads looks every way at rest.
	  Idle        breathing, tail sway, and now and then an idle action:
	              wolves sniff, howl or shake; bipeds roar or stretch;
	              serpents rise, hiss or coil; beetles rear.
	  Anatomy     jaws open to bite, howl and roar; wings fold at rest,
	              spread and beat when alert, rise in a wind-up and beat
	              down on the strike; serpent tails sway in a wave.
	  Actions     attack: a wind-up then the strike, shaped by the move
	              (MobAttack `move`): Strike lunges, Slam rears up and
	              crashes down, Roar throws the head back with jaws wide,
	              Sweep swings across; hit: a short recoil; defeat: the
	              body sinks and rolls onto its side before it fades.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CreatureRigs = require(ReplicatedStorage.Shared.Animation.CreatureRigs)
local CreatureIK = require(ReplicatedStorage.Shared.Logic.CreatureIK)
local CreatureSlither = require(ReplicatedStorage.Shared.Animation.CreatureSlither)
local CreatureGait = require(ReplicatedStorage.Shared.Animation.CreatureGait)
local CreatureMeshes = require(ReplicatedStorage.Shared.Animation.CreatureMeshes)
local CreatureSounds = require(ReplicatedStorage.Shared.Definitions.CreatureSounds)
local CameraShake = require(script.Parent.Parent.Effects.CameraShake)
local CreatureFx = require(script.Parent.Parent.Effects.CreatureFx)
local CreatureSfx = require(script.Parent.Parent.Effects.CreatureSfx)

local UPDATE_DISTANCE = 160
local STRIKE_SECONDS = 0.16
local RECOVER_SECONDS = 0.4
local HIT_SECONDS = 0.3
-- A stagger (server attribute RC_Stagger, D-61): a bigger recoil.
local STAGGER_SECONDS = 0.6
local DEFEAT_SECONDS = 0.9
-- Watching players: how often the nearest one is looked up, and how far.
local TRACK_SECONDS = 0.25
local TRACK_BASE_RANGE = 26
local TRACK_RANGE_PER_SCALE = 10
local TRACK_MAX_RANGE = 90
-- Feet follow the ground (raycasts) within this distance of the camera.
local GROUND_DETAIL_DISTANCE = 70

local MobVisualController = {}

type LegState = {
	spec: CreatureRigs.Leg,
	upper: any,
	lower: any,
	foot: any,
	-- The joint whose frame the leg hangs from ("Body", or a mesh's
	-- "Chest" / "Hips").
	parent: string,
	-- Upper joint's C0 without its rest bend, and the rest angles.
	base: CFrame,
	rest: Vector3,
	bend: number,
	splay: number,
	-- Scaled bone lengths; foot home on flat ground (root space, studs).
	lengths: { number },
	home: Vector3,
	-- Step cycle position (0..1), smoothed ground offset (studs), and the
	-- body plan's action offset this frame (up, forward; size-1 studs).
	t: number,
	-- Last frame's t (a wrap to 0 is the foot coming down).
	prevT: number,
	ground: number,
	mod: Vector2,
}

type Rig = {
	model: Model,
	root: BasePart,
	body: string,
	scale: number,
	-- Joints by name: Motor6Ds (procedural bodies) or Bones (meshes).
	motors: { [string]: any },
	-- Meshes: the generated skeleton and each bone's parent bone.
	mesh: CreatureMeshes.Shape?,
	boneParent: { [string]: string },
	-- Root-space frames of bones this frame (forward kinematics cache), and
	-- where root bones rest relative to the root (measured when tracked).
	frames: { [string]: CFrame },
	boneRest: { [string]: CFrame },
	-- Anatomy found on the rig ("" / "L" / "R" heads, tail and body chains).
	heads: { string },
	tailCount: number,
	segments: number,
	-- Legged body plans: skeleton, gait and per-frame gait state.
	plan: CreatureRigs.Plan?,
	gait: CreatureRigs.Gait?,
	legs: { LegState }?,
	run: number,
	stepAmp: number,
	stride: number,
	duty: number,
	lift: number,
	footfall: number,
	slope: number,
	groundLift: number,
	-- Smoothed state.
	speed: number,
	-- Root position last frame (speed is measured from it).
	lastPosition: Vector3,
	-- Flight (D-60, server attribute RC_Flight): 0..1 in the air, diving.
	air: number,
	dive: number,
	-- Effects and sound (D-62): sculpted shape, voice, accent colour, the
	-- current attack's kind and which of its moments have played, and the
	-- attributes last seen.
	shape: string?,
	voice: CreatureSounds.Sound,
	glow: Color3?,
	attackAlert: boolean,
	fxWindup: boolean,
	fxStruck: boolean,
	flightSeen: any,
	enragedSeen: boolean,
	-- D-81: the eye parts and their resting colour (found once).
	eyes: { BasePart }?,
	eyeColor: Color3?,
	-- Serpents: where the body has been (world, newest first), the body's
	-- rest layout, and the neck's counter-turn against the weave (degrees).
	trail: { Vector3 },
	slither: CreatureSlither.Layout?,
	neckCounter: number,
	-- Serpents: studs travelled (the weave's phase); this frame's dt.
	travel: number,
	dt: number,
	phase: number,
	yaw: number,
	turnRate: number,
	accel: number,
	-- Idle look-around.
	look: Vector2,
	lookTarget: Vector2,
	nextLookAt: number,
	-- Watching the nearest player (yaw, pitch in degrees; alert 0..1).
	trackRoot: BasePart?,
	nextTrackAt: number,
	track: Vector2,
	alert: number,
	-- Idle actions.
	idle: string?,
	idleStart: number,
	idleLength: number,
	nextIdleAt: number,
	-- Actions.
	attackStart: number?,
	windup: number,
	move: string,
	hitStart: number?,
	-- Stagger (D-61): when it began, and the server stamp last seen.
	staggerStart: number?,
	staggerStamp: any,
	defeatStart: number?,
}

local rigs: { [Model]: Rig } = {}
local rng = Random.new()

-- Stride length (studs per full gait cycle) per body plan, before scaling.
local STRIDE: { [string]: number } =
	{ Wolf = 4.2, Beetle = 2.4, Golem = 4.6, Guardian = 4.6, Sprite = 6, Serpent = 7, Hydra = 6 }

local IDLE_ACTIONS: { [string]: { string } } = {
	Hydra = { "Rise", "Hiss", "Coil" },
	Wolf = { "Sniff", "Howl", "Shake" },
	Beetle = { "Rear" },
	Golem = { "Roar", "Stretch" },
	Guardian = { "Roar", "Stretch" },
	Serpent = { "Rise", "Hiss", "Coil" },
	Sprite = {},
}

local MOVES = { Strike = true, Slam = true, Roar = true, Sweep = true }

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function approach(current: number, target: number, rate: number, dt: number): number
	return current + (target - current) * (1 - math.exp(-rate * dt))
end

local function rx(deg: number): CFrame
	return CFrame.Angles(math.rad(deg), 0, 0)
end

local function angles(x: number, y: number, z: number): CFrame
	return CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
end

-- Offsets are authored for a size-1 creature; scale them with the rig.
local function set(rig: Rig, name: string, cf: CFrame)
	local motor = rig.motors[name]
	if motor then
		motor.Transform = CFrame.new(cf.Position * rig.scale) * cf.Rotation
	end
end

-- 0..1 anticipation and strike weights for the current attack.
local function attackWeights(rig: Rig, now: number): (number, number)
	local start = rig.attackStart
	if start == nil then
		return 0, 0
	end
	local t = now - start
	local windup = rig.windup
	if t < windup then
		return smooth(t / windup), 0
	elseif t < windup + STRIKE_SECONDS then
		local s = (t - windup) / STRIKE_SECONDS
		return 1 - s, smooth(s)
	elseif t < windup + STRIKE_SECONDS + RECOVER_SECONDS then
		return 0, 1 - smooth((t - windup - STRIKE_SECONDS) / RECOVER_SECONDS)
	end
	rig.attackStart = nil
	return 0, 0
end

local function pulse(start: number?, now: number, seconds: number): number
	if start == nil then
		return 0
	end
	local t = (now - start) / seconds
	if t >= 1 then
		return 0
	end
	-- Fast in, eased out.
	return math.sin(math.min(t * 4, 1) * math.pi / 2) * (1 - smooth(t))
end

-- The current idle action and its 0..1 weight (rises and falls).
local function idleWeight(rig: Rig, now: number): (string?, number)
	local name = rig.idle
	if name == nil then
		return nil, 0
	end
	local t = (now - rig.idleStart) / rig.idleLength
	if t >= 1 then
		rig.idle = nil
		return nil, 0
	end
	return name, smooth(math.min(t * 4, 1)) * smooth(math.min((1 - t) * 3, 1))
end

local function weightOf(name: string?, idle: string?, w: number): number
	return if name == idle then w else 0
end

-- Where head `index` of `count` looks (yaw, pitch degrees): roaming at
-- rest (several heads each their own way), on the watched player when alert.
local function headLook(rig: Rig, index: number, count: number, now: number, moving: number): Vector2
	local roam = rig.look
	if count > 1 then
		roam += Vector2.new(math.sin(now * 0.55 + index * 2.3) * 22, math.sin(now * 0.8 + index * 1.7) * 6)
	end
	return roam * (1 - moving) * (1 - rig.alert) + rig.track * rig.alert
end

--------------------------------------------------------------------------------
-- Shared anatomy: jaws, wings, tails
--------------------------------------------------------------------------------

local function jaw(rig: Rig, tag: string, open: number)
	set(rig, `Jaw{tag}`, rx(-math.clamp(open, 0, 45)))
end

local function wingsMotion(rig: Rig, now: number, rear: number, strike: number, hit: number, down: number)
	if not rig.motors["WingL"] or rig.body == "Sprite" then
		return
	end
	local moving = math.clamp(rig.speed / 8, 0, 1)
	local air, dive = rig.air, rig.dive
	-- Folded along the back at rest; spread when alert, running or striking;
	-- beating hard in flight, swept back in a dive.
	local fold = math.clamp(0.9 - rig.alert * 0.6 - moving * 0.5 - rear * 0.9 - strike, 0, 1) * (1 - air)
	local rate = 3 + rig.alert * 1.6 + moving * 2 + air * 2.5
	local strokes = (1 - fold) * (1 - rear) * (1 - dive)
	local beat = math.sin(now * rate) * (30 + air * 22) * strokes
	local lag = math.sin(now * rate - 0.7) * (22 + air * 12) * strokes
	local breathe = math.sin(now * 1.4) * 3
	local lift = -fold * 28 + beat + rear * 55 - strike * 50 - hit * 10 + breathe - down * 30 - dive * 25
	local sweep = fold * 60 + dive * 55
	set(rig, "WingL", angles(0, sweep, -lift))
	set(rig, "WingR", angles(0, -sweep, lift))
	set(rig, "WingL2", angles(0, fold * 70, fold * 35 - lag))
	set(rig, "WingR2", angles(0, -fold * 70, -fold * 35 + lag))
end

local function tailMotion(rig: Rig, now: number, rear: number, strike: number, down: number)
	if rig.tailCount < 2 then
		return
	end
	local moving = math.clamp(rig.speed / 6, 0, 1)
	local rate = 2.2 + moving * 2.5 + rig.alert
	for i = 1, rig.tailCount do
		-- The wolf's first tail joint is driven by its body plan.
		if i == 1 and rig.body == "Wolf" then
			continue
		end
		local name = if i == 1 then "Tail" else `Tail{i}`
		local yaw = math.sin(now * rate - i * 0.75) * (7 + 5 * rig.alert) * (1 - down)
		local pitch = math.sin(now * 1.3 - i * 0.5) * 4 + rear * 7 - strike * 5 + down * 6
		set(rig, name, angles(pitch, yaw, 0))
	end
	-- The snake head at the tip looks around and snaps with the strike.
	set(
		rig,
		"TailHead",
		angles(
			math.sin(now * 0.9) * 10 - rear * 25 + strike * 35,
			math.sin(now * 0.7 + 1) * 30 * (1 - down),
			0
		)
	)
end

--------------------------------------------------------------------------------
-- Legs: gait cycle, ground following and inverse kinematics (D-51)
--------------------------------------------------------------------------------

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

--------------------------------------------------------------------------------
-- Effects and sound (creature overhaul stage 5, D-62): Effects/CreatureFx
-- and Effects/CreatureSfx at the moments the motion already knows (wind-up,
-- strike, footfall, take-off, dive, stagger, enrage, defeat).
--------------------------------------------------------------------------------

-- The creature's accent colour (its glowing parts), found once.
local function glowOf(rig: Rig): Color3
	local cached = rig.glow
	if cached then
		return cached
	end
	local found = Color3.fromRGB(255, 200, 120)
	for _, d in rig.model:GetDescendants() do
		if
			d:IsA("BasePart")
			and d.Name ~= "Shine"
			and (d.Name == "Glow" or d.Name == "Eye" or d.Material == Enum.Material.Neon)
		then
			found = d.Color
			break
		end
	end
	rig.glow = found
	return found
end

--[[
	D-81: eye expressions. "Calm" is the resting glow, "Fierce" flares it
	(enraged), "Out" dims the eyes to a dull, unlit tone (defeated: a
	non-graphic "lights out").
]]
local function setEyes(rig: Rig, mood: "Calm" | "Fierce" | "Out")
	if rig.eyes == nil then
		local found = {}
		for _, d in rig.model:GetDescendants() do
			if d:IsA("BasePart") and (d.Name == "Eye" or d.Name == "Shine") then
				table.insert(found, d)
			end
		end
		rig.eyes = found
	end
	for _, part in rig.eyes :: { BasePart } do
		if part.Name == "Shine" then
			part.Transparency = if mood == "Out" then 1 else 0
			continue
		end
		local base = rig.eyeColor or part.Color
		rig.eyeColor = base
		if mood == "Fierce" then
			part.Color = base:Lerp(Color3.new(1, 1, 1), 0.35)
			part.Material = Enum.Material.Neon
		elseif mood == "Out" then
			part.Color = base:Lerp(Color3.new(0, 0, 0), 0.7)
			part.Material = Enum.Material.SmoothPlastic
		else
			part.Color = base
			part.Material = Enum.Material.Neon
		end
	end
end

-- Height of the ground under the creature.
local function groundY(rig: Rig): number
	local humanoid = rig.model:FindFirstChildOfClass("Humanoid")
	local hip = if humanoid then humanoid.HipHeight else 0
	return rig.root.Position.Y - rig.root.Size.Y / 2 - hip
end

-- The head's world frame (facing the creature's way).
local function headFrame(rig: Rig): CFrame
	local joint = rig.motors["Head"]
	local position: Vector3
	if joint and joint:IsA("Bone") then
		position = joint.WorldPosition
	elseif joint and joint:IsA("Motor6D") and joint.Part1 then
		position = joint.Part1.Position
	else
		position = (rig.root.CFrame * CFrame.new(0, 0.5 * rig.scale, -1.5 * rig.scale)).Position
	end
	return CFrame.new(position) * rig.root.CFrame.Rotation
end

-- Shakes the camera when the local player stands within `radius`.
local function shakeNear(position: Vector3, radius: number, amount: number)
	local character = Players.LocalPlayer and Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") and (root.Position - position).Magnitude <= radius then
		CameraShake.add(amount)
	end
end

local function voice(rig: Rig, cooldown: number)
	CreatureSfx.play(rig.voice, rig.root, rig.scale, "voice", cooldown)
end

-- A heavy foot comes down (big creatures, near the camera).
local function footDown(rig: Rig, leg: LegState)
	if rig.scale < 1.6 or rig.air > 0.3 then
		return
	end
	local position = rig.root.CFrame:PointToWorldSpace(leg.home + Vector3.new(0, leg.ground, 0))
	CreatureFx.dust(position, rig.scale * 0.45)
	CreatureSfx.play(
		CreatureSounds.Cues.Footstep,
		rig.root,
		rig.scale,
		"step",
		0.12,
		math.clamp(rig.scale / 3, 0.4, 1.2)
	)
end

-- The moment a wound-up move lands: its sound and effect.
local function strikeFx(rig: Rig)
	local s = rig.scale
	local move = rig.move
	local front = rig.root.CFrame * CFrame.new(0, 0, -(1.4 + 1.2 * s))
	local floor = groundY(rig)
	local color = glowOf(rig)
	if move == "Strike" or move == "Sweep" then
		CreatureSfx.play(CreatureSounds.Cues.Swish, rig.root, s, "swish", 0.2)
		if move == "Sweep" then
			-- A weapon or great limb: one wide streak; claws: three.
			local streaks = if rig.shape == "Golem"
					or rig.shape == "Knight"
					or rig.shape == "Harpy"
				then 1
				else 3
			CreatureFx.trail(front, 2.4 * s, color, streaks)
		end
		if rig.shape == "Knight" then
			CreatureSfx.play(CreatureSounds.Cues.Clank, rig.root, s, "clank", 0.3)
		end
		return
	end
	-- Slam / Roar (stomp): something heavy meets the ground.
	local at = if move == "Roar" then rig.root.Position else front.Position
	local ground = Vector3.new(at.X, floor, at.Z)
	local radius = if move == "Roar" then 4 + 2.5 * s else 3 + 2 * s
	local impact = if rig.shape == "Golem" then CreatureSounds.Cues.RockImpact else CreatureSounds.Cues.Impact
	CreatureSfx.play(impact, rig.root, s, "impact", 0.3)
	if rig.shape == "Knight" then
		CreatureSfx.play(CreatureSounds.Cues.Clank, rig.root, s, "clank", 0.3)
	end
	CreatureFx.shockwave(ground, radius, color)
	shakeNear(ground, radius + 4, 0.25 + 0.08 * s)
end

--[[
	Per frame: watches the motion and the server's attributes for the
	moments that make a sound or an effect. `near`: close to the camera
	(footfall dust only there).
]]
local function effects(rig: Rig, now: number)
	local s = rig.scale
	-- Wind-up begins / the strike lands.
	local start = rig.attackStart
	if start and not rig.fxWindup then
		rig.fxWindup = true
		local head = headFrame(rig)
		if rig.attackAlert then
			-- Noticed a player: a roar.
			voice(rig, 2)
			CreatureFx.roar(head, s, glowOf(rig))
			if rig.shape == "Dragon" or rig.shape == "Chimera" then
				CreatureFx.breath(head, s, glowOf(rig))
			end
		elseif rig.move == "Roar" or rng:NextNumber() < 0.35 then
			voice(rig, 2.5)
		end
	end
	if start and not rig.fxStruck and now >= start + rig.windup then
		rig.fxStruck = true
		if not rig.attackAlert then
			strikeFx(rig)
		end
	end
	-- Flight: take-off, beats, the dive and its landing.
	local flight = rig.model:GetAttribute("RC_Flight")
	if flight ~= rig.flightSeen then
		local was = rig.flightSeen
		rig.flightSeen = flight
		local floor = groundY(rig)
		local under = Vector3.new(rig.root.Position.X, floor, rig.root.Position.Z)
		if flight == "Rise" then
			CreatureSfx.play(CreatureSounds.Cues.Wings, rig.root, s, "wings", 0.3)
			CreatureFx.dust(under, s * 1.2)
		elseif flight == "Dive" then
			CreatureSfx.play(CreatureSounds.Cues.Dive, rig.root, s, "dive", 1)
			voice(rig, 1.5)
		elseif flight == "Land" and was == "Dive" then
			CreatureSfx.play(CreatureSounds.Cues.Impact, rig.root, s, "impact", 0.3)
			CreatureFx.shockwave(under, 4 + 1.4 * s, glowOf(rig))
			shakeNear(under, 8 + 2 * s, 0.35)
		elseif flight == nil and was ~= nil then
			CreatureFx.dust(under, s)
		end
	end
	if flight == "Rise" or flight == "Circle" or flight == "Warn" then
		CreatureSfx.play(CreatureSounds.Cues.Wings, rig.root, s, "wings", 1.1, 0.6)
	end
	-- Enraged: embers.
	local enraged = rig.model:GetAttribute("RC_Enraged") == true and rig.defeatStart == nil
	if enraged ~= rig.enragedSeen then
		rig.enragedSeen = enraged
		CreatureFx.embers(rig.root, enraged, glowOf(rig))
		if rig.defeatStart == nil then
			setEyes(rig, if enraged then "Fierce" else "Calm")
		end
		if enraged then
			voice(rig, 1)
		end
	end
end

-- Finds the leg bones once they have streamed in.
local function buildLegs(rig: Rig): { LegState }?
	local plan = rig.plan
	if plan == nil then
		return nil
	end
	local s = rig.scale
	local out: { LegState } = {}
	for _, spec in plan.legs do
		local upper = rig.motors[spec.name]
		local lower = rig.motors[`{spec.name}b`]
		local foot = rig.motors[`{spec.name}c`]
		if not upper or not lower or not foot then
			return nil
		end
		local meshRest = (spec :: any).rest
		local rest = if typeof(meshRest) == "Vector3" then meshRest else upper:GetAttribute("RestAngles")
		if typeof(rest) ~= "Vector3" then
			local forward, down = CreatureRigs.restReach(plan, spec)
			local a1, a2, a3 =
				CreatureIK.solve(spec.lengths, spec.bend, math.rad(spec.footAngle), forward, down)
			rest = Vector3.new(a1, a2, a3)
		end
		local restAngles = rest :: Vector3
		local hipRoot = plan.bodyCenter + spec.hip
		table.insert(out, {
			spec = spec,
			upper = upper,
			lower = lower,
			foot = foot,
			parent = (spec :: any).parent or "Body",
			-- The upper joint's offset from its parent, without its rest bend.
			base = (if upper:IsA("Bone") then upper.CFrame else upper.C0)
				* CFrame.Angles(-restAngles.X, 0, 0),
			rest = restAngles,
			bend = spec.bend,
			splay = spec.splay,
			lengths = { spec.lengths[1] * s, spec.lengths[2] * s, spec.lengths[3] * s },
			home = Vector3.new(
				hipRoot.X + spec.reach.X,
				-plan.height + CreatureRigs.FOOT_CLEARANCE,
				hipRoot.Z + spec.reach.Y
			) * s,
			t = 0,
			prevT = 0,
			ground = 0,
			mod = Vector2.zero,
		})
	end
	return out
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true
local rayFilterAt = 0
local npcFolder: Instance? = nil

-- Creatures and player characters never count as ground.
local function refreshRayFilter(now: number)
	if now < rayFilterAt then
		return
	end
	rayFilterAt = now + 2
	local list: { Instance } = {}
	if npcFolder then
		table.insert(list, npcFolder)
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(list, player.Character)
		end
	end
	rayParams.FilterDescendantsInstances = list
end

--[[
	Advances the step cycle from the distance walked (and turned), works out
	each foot's phase, the footfall pulse, and (near the camera) how far the
	ground under each foot is above / below flat, from which the body takes
	its slope.
]]
local function gaitPrep(rig: Rig, dt: number, detailed: boolean)
	local gait = rig.gait :: CreatureRigs.Gait
	local legs = rig.legs :: { LegState }
	local s = rig.scale
	local speed = rig.speed + math.abs(rig.turnRate) * 1.2 * s
	local state = CreatureGait.state(gait, rig.plan :: CreatureRigs.Plan, s, speed)
	local run, duty = state.run, state.duty
	rig.run = run
	rig.duty = duty
	rig.stride = state.stride
	rig.lift = state.lift
	rig.stepAmp = state.amp
	rig.phase = (rig.phase + speed * dt / state.cycle) % 1
	local footfall = 0
	local frontSum, frontCount, backSum, backCount, liftSum = 0, 0, 0, 0, 0
	local frontZ, backZ = 0, 0
	for _, leg in legs do
		local spec = leg.spec
		local offset = lerp(spec.walk, if gait.trot then spec.trot else spec.run, run)
		leg.prevT = leg.t
		leg.t = (rig.phase + offset) % 1
		-- Wrapped round to 0: this foot just came down (big creatures thud).
		if detailed and leg.t < leg.prevT and leg.prevT - leg.t > 0.5 and rig.stepAmp > 0.3 then
			footDown(rig, leg)
		end
		if leg.t < duty then
			footfall = math.max(footfall, math.exp(-((leg.t / duty) / 0.14) ^ 2))
		end
		leg.mod = Vector2.zero
		local groundTarget = 0
		if detailed then
			local origin = rig.root.CFrame * Vector3.new(leg.home.X, 0, leg.home.Z)
			local reach = leg.lengths[1] + leg.lengths[2] + leg.lengths[3]
			local result =
				Workspace:Raycast(origin, Vector3.new(0, -(rig.root.Size.Y + reach * 2), 0), rayParams)
			if result then
				local localY = rig.root.CFrame:PointToObjectSpace(result.Position).Y
				groundTarget = math.clamp(
					localY - (leg.home.Y - CreatureRigs.FOOT_CLEARANCE * s),
					-reach * 0.5,
					reach * 0.5
				)
			end
		end
		leg.ground = approach(leg.ground, groundTarget, 14, dt)
		liftSum += leg.ground
		if leg.home.Z < 0 then
			frontSum += leg.ground
			frontCount += 1
			frontZ += leg.home.Z
		elseif leg.home.Z > 0 then
			backSum += leg.ground
			backCount += 1
			backZ += leg.home.Z
		end
	end
	rig.footfall = footfall * rig.stepAmp
	-- Uneven ground lifts the body; at a run it also sinks so the legs
	-- reach long strides (CreatureGait.state).
	rig.groundLift = liftSum / #legs * 0.6 - state.crouch
	if frontCount > 0 and backCount > 0 then
		local span = backZ / backCount - frontZ / frontCount
		local rise = frontSum / frontCount - backSum / backCount
		rig.slope = math.clamp(math.deg(math.atan2(rise, span)), -25, 25)
	else
		rig.slope = 0
	end
end

--[[
	Root-space frame of joint `name` with this frame's Transforms. Motor6D
	bodies: the Body part (C0 * Transform * C1^-1). Meshes: forward
	kinematics down the bones; the root bone (Body) rests on the root.
]]
local function frameOf(rig: Rig, name: string): CFrame
	local cached = rig.frames[name]
	if cached then
		return cached
	end
	local joint = rig.motors[name]
	local frame: CFrame
	if joint == nil then
		frame = CFrame.identity
	elseif joint:IsA("Bone") then
		local parent = rig.boneParent[name]
		if parent then
			frame = frameOf(rig, parent) * joint.CFrame * joint.Transform
		else
			frame = (rig.boneRest[name] or CFrame.identity) * joint.Transform
		end
	else
		frame = joint.C0 * joint.Transform * joint.C1:Inverse()
	end
	rig.frames[name] = frame
	return frame
end

--[[
	Places every foot: on the ground and planted through its stance, lifted
	along an arc through its swing (forelegs curl the paw), shifted by the
	body plan's action offsets (`leg.mod`: up, forward), tucked in as the
	creature falls. The bones are then solved to reach it, from wherever the
	Body has moved to (so the body can bob, lean and lunge over planted feet).
]]
local function stepLegs(rig: Rig, down: number)
	local legs = rig.legs
	if legs == nil or not rig.motors["Body"] then
		return
	end
	local s = rig.scale
	table.clear(rig.frames)
	local amp = rig.stepAmp
	local duty = rig.duty
	local curlScale = if rig.body == "Wolf" then 1 elseif rig.body == "Beetle" then 0 else 0.3
	for _, leg in legs do
		local spec = leg.spec
		local body = frameOf(rig, leg.parent)
		local target, curl =
			CreatureGait.footTarget(leg.home, leg.t, duty, rig.stride, rig.lift, amp, leg.ground)
		target += Vector3.new(0, leg.mod.X * s, -leg.mod.Y * s)
		-- Tucked in when falling and in flight (trailing back in a dive).
		local tuck = math.max(down, rig.air)
		if tuck > 0 then
			local total = leg.lengths[1] + leg.lengths[2] + leg.lengths[3]
			local tucked =
				body:PointToWorldSpace(spec.hip * s + Vector3.new(0, -total * 0.45, total * 0.3 * rig.dive))
			target = target:Lerp(tucked, tuck)
		end
		local footAngle = math.rad(spec.footAngle + (if spec.front then -55 else 25) * curl * amp * curlScale)
		leg.upper.Transform, leg.lower.Transform, leg.foot.Transform =
			CreatureGait.solveLeg(body, leg :: any, target, footAngle)
	end
end

--------------------------------------------------------------------------------
-- Body plans
--------------------------------------------------------------------------------

local function quadruped(rig: Rig, now: number, rear: number, strike: number, hit: number, down: number)
	local run = rig.run
	local moving = rig.stepAmp
	local cycle = rig.phase * math.pi * 2
	local gait = rig.gait
	local idle, w = idleWeight(rig, now)
	local sniff = weightOf("Sniff", idle, w)
	local howl = weightOf("Howl", idle, w)
	local shake = weightOf("Shake", idle, w)
	-- Attack shapes.
	local slam = if rig.move == "Slam" then rear else 0
	local slamDown = if rig.move == "Slam" then strike else 0
	local roar = if rig.move == "Roar" then rear else 0
	local sweep = if rig.move == "Sweep" then 1 else 0
	local lunge = if rig.move == "Strike" then 1 else 0.35
	-- Feet: forepaws claw at the air while rearing, reach out on a lunge.
	for _, leg in (rig.legs or {}) :: { LegState } do
		local spec = leg.spec
		if spec.front then
			local paw = math.sin(now * 9 + (if spec.side > 0 then 2 else 0)) * 0.3 * slam
			leg.mod = Vector2.new(
				slam * 1.5 + paw + sniff * 0.05,
				slam * 0.5 + strike * lunge * 0.9 - slamDown * 0.3 + rear * -0.15
			)
		else
			leg.mod = Vector2.new(0, rear * 0.2)
		end
	end
	local breathe = math.sin(now * 2.1) * (1 - moving)
	local flex = math.sin(cycle * 2) * 5 * run
	-- Weight drops onto each footfall; at a gallop the body also bounds.
	local bob = -(gait and gait.bob or 0.08) * rig.footfall
		+ math.abs(math.sin(cycle * 2)) * 0.18 * run * moving
	local sway = math.sin(cycle) * (gait and gait.sway or 2) * moving * (1 - run)
	local bank = math.clamp(-rig.turnRate * 9, -14, 14) * (1 + rig.air)
	local pitch = math.clamp(-rig.accel * 0.8, -6, 6) + rig.slope * (1 - rig.air) - rig.dive * 26
	-- In flight the body rises and falls with each wingbeat.
	bob += math.sin(now * (5.5 + rig.alert * 1.6)) * 0.18 * rig.air * (1 - rig.dive)
	local shakeRoll = math.sin(now * 22) * 10 * shake
	set(
		rig,
		"Body",
		CFrame.new(
			0,
			rig.groundLift / rig.scale
				+ bob
				+ breathe * 0.05
				- rear * 0.35 * (1 - slam)
				+ slam * 0.9
				- slamDown * 0.4
				- sniff * 0.15
				- down * 1.1,
			-strike * 1.4 * lunge + hit * 0.5
		)
			* angles(
				flex
					+ pitch
					+ rear * 8
					+ slam * 24
					- strike * 10 * lunge
					- slamDown * 14
					- hit * 8
					+ howl * 7
					+ roar * 6
					- sniff * 5,
				sweep * (rear * 12 - strike * 14),
				bank + sway + down * 75 + shakeRoll
			)
	)
	-- Spine (meshes): chest and hips flex against each other at a gallop
	-- and roll with the stride.
	set(
		rig,
		"Chest",
		angles(
			math.sin(cycle * 2) * 7 * run - sniff * 6 + slam * 6,
			math.clamp(rig.turnRate * 6, -10, 10),
			-sway * 0.5
		)
	)
	set(
		rig,
		"Hips",
		angles(-math.sin(cycle * 2) * 8 * run - slam * 10, -math.clamp(rig.turnRate * 6, -10, 10), sway * 0.5)
	)
	-- Necks carry the heads: the neck takes part of each turn and nod, the
	-- head the rest. Heads lead turns, counter-bob at speed, watch players.
	local count = #rig.heads
	for index, tag in rig.heads do
		local look = headLook(rig, index, count, now, moving)
		local headPitch = look.Y
			+ rear * 16 * (1 - roar)
			+ roar * 40
			- strike * 28 * lunge
			- math.sin(cycle * 2) * 6 * run
			+ hit * 12
			+ breathe * 2
			+ howl * 48
			- sniff * 34
			- down * 20
		local headYaw = look.X
			+ math.clamp(rig.turnRate * 14, -25, 25)
			+ sweep * (rear * 35 - strike * 45)
			+ math.sin(now * 3 + index) * 6 * sniff
		set(
			rig,
			`Neck{tag}`,
			CFrame.new(0, -bob * 0.4, -strike * 0.6 * lunge) * angles(headPitch * 0.4, headYaw * 0.4, 0)
		)
		set(
			rig,
			`Head{tag}`,
			CFrame.new(0, -sniff * 0.1, -strike * 0.5 * lunge)
				* angles(headPitch * 0.6, headYaw * 0.6, math.sin(now * 22 + 0.6) * 12 * shake)
		)
		jaw(rig, tag, rear * 18 + strike * 14 + roar * 30 + howl * 32 + hit * 8 + sniff * 4)
	end
	local excited = math.max(moving, rig.alert)
	local wag = math.sin(now * (if excited > 0.3 then 10 else 3.5)) * (if excited > 0.3 then 12 else 18)
	set(
		rig,
		"Tail",
		CFrame.Angles(math.rad(-run * 18 + rear * 10 - down * 20 + howl * 10), math.rad(wag * (1 - down)), 0)
	)
end

local function beetle(rig: Rig, now: number, rear: number, strike: number, hit: number, down: number)
	local moving = rig.stepAmp
	local cycle = rig.phase * math.pi * 2
	local idle, w = idleWeight(rig, now)
	local rearUp = weightOf("Rear", idle, w) + (if rig.move == "Slam" then rear else 0)
	-- Front legs wave in the air while rearing; all legs brace for the strike.
	for _, leg in (rig.legs or {}) :: { LegState } do
		if leg.spec.front then
			leg.mod = Vector2.new(
				rearUp * (1.3 + math.sin(now * 8 + leg.spec.side) * 0.3),
				rearUp * 0.4 + strike * 0.5
			)
		end
	end
	local sway = math.sin(cycle * 2) * 3 * moving
	local breathe = math.sin(now * 1.6) * (1 - moving)
	set(
		rig,
		"Body",
		CFrame.new(
			0,
			rig.groundLift / rig.scale
				+ breathe * 0.05
				+ rear * 0.35
				+ rearUp * 0.4
				- rig.footfall * 0.04
				- down * 0.8,
			strike * -0.9 + hit * 0.4
		)
			* CFrame.Angles(
				math.rad(rig.slope + rear * 10 + rearUp * 16 - strike * 6 - hit * 6),
				0,
				math.rad(sway + math.clamp(-rig.turnRate * 6, -8, 8) + down * 160)
			)
	)
	local look = headLook(rig, 1, 1, now, moving)
	set(
		rig,
		"Head",
		CFrame.new(0, 0, strike * -1.1)
			* CFrame.Angles(math.rad(rear * 22 - strike * 26 + look.Y * 0.5), math.rad(look.X * 0.6), 0)
	)
	-- Meshes: mandibles / fangs spread in the wind-up and snap shut on the
	-- strike, twitch at rest; a spider's abdomen sways with the steps.
	local twitch = math.sin(now * 5.3) * 4 * (1 - moving)
	local open = rear * 28 - strike * 12 + twitch + rig.alert * 6
	set(rig, "MandL", angles(0, -open, 0))
	set(rig, "MandR", angles(0, open, 0))
	set(
		rig,
		"Abdomen",
		angles(math.sin(cycle * 2) * 4 * moving + breathe * 3 - rear * 8, math.sin(cycle) * 6 * moving, 0)
	)
end

local function biped(rig: Rig, now: number, rear: number, strike: number, hit: number, down: number)
	local moving = rig.stepAmp
	local cycle = rig.phase * math.pi * 2
	local gait = rig.gait
	local idle, w = idleWeight(rig, now)
	local roar = weightOf("Roar", idle, w) + (if rig.move == "Roar" then rear else 0)
	local stretch = weightOf("Stretch", idle, w)
	local slam = if rig.move == "Slam" then 1 else 0
	local sweep = if rig.move == "Sweep" then 1 else 0
	-- Arms swing against the legs (left arm back as the left foot leads);
	-- in flight (a harpy's wings are its arms) they spread and beat.
	local armSwing = math.cos(cycle) * 26 * moving * (1 - rig.air)
	local breathe = math.sin(now * 1.5)
	-- Arms spread wide to roar; a slam brings both overhead and down.
	local spread = roar * 55
		+ stretch * 30
		+ rig.air * (55 + math.sin(now * 6.5) * 40) * (1 - rig.dive)
		+ rig.dive * 20
	set(
		rig,
		"ArmL",
		rx(-armSwing + breathe * 2 - hit * 20 + slam * (rear * 150 + strike * 40) + stretch * 40)
			* CFrame.Angles(0, 0, math.rad(-down * 40 - spread))
	)
	set(rig, "ArmL2", rx(15 + math.max(0, armSwing) * 0.5 + slam * rear * 30 - strike * slam * 20))
	-- The weapon arm raises overhead in the wind-up and slams down; a sweep
	-- swings it across the front.
	set(
		rig,
		"ArmR",
		rx(armSwing + rear * 150 * (1 - sweep) + rear * 85 * sweep + strike * 40 - hit * 20)
			* CFrame.Angles(0, math.rad(sweep * (rear * 50 - strike * 90)), math.rad(down * 40 + spread))
	)
	set(rig, "ArmR2", rx(15 + math.max(0, -armSwing) * 0.5 + rear * 35 - strike * 25))
	-- Heavy stride: weight shifts over the planted foot and drops at each
	-- footfall; the hips counter-rotate with the step.
	local roll = math.sin(cycle) * (gait and gait.sway or 3) * moving + math.sin(now * 1.2) * 4 * stretch
	local dip = -(gait and gait.bob or 0.12) * rig.footfall
	set(
		rig,
		"Body",
		CFrame.new(
			0,
			rig.groundLift / rig.scale
				+ dip
				+ breathe * 0.06
				- rear * 0.25
				- strike * 0.3
				- strike * slam * 0.4
				- down * 1.6,
			hit * 0.4
		)
			* CFrame.Angles(
				math.rad(
					rear * 8
						- strike * 16
						- strike * slam * 12
						- hit * 10
						+ roar * 12
						+ math.clamp(-rig.accel * 0.6, -5, 5)
						+ moving * 4
						- down * 35
				),
				math.rad(math.sin(cycle) * 6 * moving + rear * -12 + sweep * (rear * -15 + strike * 25)),
				math.rad(roll + math.clamp(-rig.turnRate * 6, -8, 8))
			)
	)
	local look = headLook(rig, 1, 1, now, moving)
	set(
		rig,
		"Head",
		CFrame.Angles(
			math.rad(breathe * 2 + rear * 6 + look.Y * 0.6 + roar * 30 - down * 25 - moving * 4),
			math.rad(look.X * 0.8 - math.sin(cycle) * 6 * moving),
			0
		)
	)
	-- Meshes: the golem's jaw drops to roar.
	jaw(rig, "", roar * 30 + rear * 8)
end

local serpentNecks: (
	rig: Rig,
	now: number,
	rear: number,
	strike: number,
	hit: number,
	down: number,
	moving: number,
	rise: number,
	hiss: number,
	sweep: number,
	lunge: number
) -> ()

-- A serpent body's rest layout (Animation/CreatureSlither), once its
-- segments have streamed in.
local function slitherLayout(rig: Rig): CreatureSlither.Layout?
	local body = rig.motors["Body"]
	if rig.segments == 0 or body == nil then
		return nil
	end
	local layout = rig.slither
	if layout == nil or layout.count ~= rig.segments then
		local bodyRest = if body:IsA("Bone")
			then rig.boneRest["Body"] or CFrame.identity
			else body.C0 * body.C1:Inverse()
		layout = CreatureSlither.layout(rig.motors, rig.segments, bodyRest)
		rig.slither = layout
	end
	return layout
end

-- Serpent bodies follow the chest's trail.
local function slither(rig: Rig, sway: (number) -> number)
	local layout = slitherLayout(rig)
	if layout == nil then
		return
	end
	table.clear(rig.frames)
	CreatureSlither.step(
		layout,
		rig.motors,
		frameOf(rig, "Body"),
		rig.root.CFrame,
		rig.trail,
		rig.scale,
		sway
	)
end

local function serpent(rig: Rig, now: number, rear: number, strike: number, hit: number, down: number)
	local moving = math.clamp(rig.speed / 3, 0, 1)
	local still = 1 - moving
	local idle, w = idleWeight(rig, now)
	local rise = weightOf("Rise", idle, w) + (if rig.move == "Slam" then rear else 0)
	local hiss = weightOf("Hiss", idle, w) + (if rig.move == "Roar" then rear else 0)
	local coil = weightOf("Coil", idle, w)
	local sweep = if rig.move == "Sweep" then 1 else 0
	local lunge = if rig.move == "Strike" or rig.move == "Slam" then 1 else 0.4
	-- The chest weaves along an S as it travels, pointing along its trail
	-- (Animation/CreatureSlither).
	local layout = slitherLayout(rig)
	local weaveX, weaveYaw = 0, 0
	if layout then
		rig.travel += rig.speed * rig.dt
		weaveX = CreatureSlither.weave(layout, rig.travel)
		local heading = CreatureSlither.heading(layout, rig.trail, rig.root.CFrame, weaveX)
		weaveYaw = if heading then math.clamp(math.deg(heading), -50, 50) else 0
	end
	local breathe = math.sin(now * 1.5) * still
	set(
		rig,
		"Body",
		CFrame.new(weaveX / rig.scale, breathe * 0.06 - down * 0.6, -strike * 1.2 * lunge + hit * 0.4)
			* angles(
				rear * 5 - strike * 4 - hit * 6,
				weaveYaw + math.sin(now * 0.7) * 4 * still + sweep * (rear * 15 - strike * 25),
				math.clamp(-rig.turnRate * 8, -12, 12) + down * 80
			)
	)
	-- The neck turns back against the weave: the head holds its heading.
	rig.neckCounter = -weaveYaw * 0.75
	serpentNecks(rig, now, rear, strike, hit, down, moving, rise, hiss, sweep, lunge)
	-- A gorgon's arms (meshes): spread and raised in the wind-up, sweeping
	-- forward on the strike, swaying at rest.
	if rig.motors["ArmL"] then
		local reach = rear * 70 - strike * 40 + rise * 30
		local spread = 15 + rear * 35 + hiss * 20 + down * 30
		set(rig, "ArmL", angles(reach + math.sin(now * 1.2) * 6 * still, 0, -spread))
		set(rig, "ArmR", angles(reach + math.sin(now * 1.2 + 1) * 6 * still, 0, spread))
		set(rig, "ArmL2", rx(20 + rear * 30 + hit * 15))
		set(rig, "ArmR2", rx(20 + rear * 30 + hit * 15))
	end
	-- The body follows the chest's trail; at rest it sways and coils a little.
	slither(rig, function(i: number): number
		return (math.sin(now * 0.8 - i * 0.6) * 3 + coil * 10 + rig.alert * 1.5) * still * (1 - down * 0.6)
	end)
end

-- Raised serpent necks: rear back in an S for the wind-up, strike down and
-- forward, sway and watch at rest (serpents and hydras).
function serpentNecks(
	rig: Rig,
	now: number,
	rear: number,
	strike: number,
	hit: number,
	down: number,
	moving: number,
	rise: number,
	hiss: number,
	sweep: number,
	lunge: number
)
	local still = 1 - moving
	local count = #rig.heads
	for index, tag in rig.heads do
		local look = headLook(rig, index, count, now, moving)
		local sway = math.sin(now * 1.3 + index * 1.9) * 5 * still
		-- Each head of a hydra strikes a beat apart.
		local beat = if count > 1 then math.sin(now * 2 + index * 2.1) * 6 * rig.alert else 0
		-- Rear back (S-curve) in the wind-up, then strike down and forward.
		set(
			rig,
			`Neck{tag}`,
			angles(
				rear * 22 - strike * 42 * lunge + rise * 18 + hit * 10 + sway - down * 45,
				look.X * 0.45 + rig.neckCounter + sweep * (rear * 30 - strike * 40),
				0
			)
		)
		set(
			rig,
			`NeckB{tag}`,
			angles(rear * 20 - strike * 26 * lunge + rise * 10 - down * 30 + beat, look.X * 0.35, 0)
		)
		set(
			rig,
			`NeckC{tag}`,
			angles(rear * 10 - strike * 14 * lunge + rise * 6 - down * 15, look.X * 0.2, 0)
		)
		set(
			rig,
			`Head{tag}`,
			angles(
				-(rear * 42 - strike * 68 * lunge) * 0.8 - rise * 22 + look.Y + hiss * 8 + down * 20,
				look.X * 0.2,
				0
			)
		)
		jaw(rig, tag, rear * 25 + strike * 10 + hiss * 38 + hit * 8)
	end
end

-- Hydra: a heavy sprawling body (legs by IK, trotting) carrying three
-- swaying serpent necks; the tail drags and sways.
local function hydraBody(rig: Rig, now: number, rear: number, strike: number, hit: number, down: number)
	local moving = rig.stepAmp
	local cycle = rig.phase * math.pi * 2
	local idle, w = idleWeight(rig, now)
	local rise = weightOf("Rise", idle, w) + (if rig.move == "Slam" then rear else 0)
	local hiss = weightOf("Hiss", idle, w) + (if rig.move == "Roar" then rear else 0)
	local sweep = if rig.move == "Sweep" then 1 else 0
	local lunge = if rig.move == "Strike" or rig.move == "Slam" then 1 else 0.4
	local breathe = math.sin(now * 1.3) * (1 - moving)
	rig.neckCounter = math.sin(cycle + 1) * 6 * moving
	-- The forelegs plant and brace while the necks strike.
	for _, leg in (rig.legs or {}) :: { LegState } do
		if leg.spec.front then
			leg.mod = Vector2.new(rise * 0.4, strike * 0.3 * lunge)
		end
	end
	set(
		rig,
		"Body",
		CFrame.new(
			0,
			rig.groundLift / rig.scale + breathe * 0.06 - rig.footfall * 0.15 + rise * 0.3 - down * 0.9,
			-strike * 0.5 * lunge + hit * 0.3
		)
			* angles(
				rig.slope + rear * 6 + rise * 8 - strike * 6 * lunge - hit * 5,
				math.sin(cycle) * 6 * moving + sweep * (rear * 10 - strike * 15),
				math.sin(cycle) * 4 * moving + math.clamp(-rig.turnRate * 6, -8, 8) + down * 60
			)
	)
	serpentNecks(rig, now, rear, strike, hit, down, moving, rise, hiss, sweep, lunge)
end

local function sprite(rig: Rig, now: number, rear: number, strike: number, hit: number, down: number)
	local moving = math.clamp(rig.speed / 4, 0, 1)
	local hover = math.sin(now * 2.4) * 0.45 + math.sin(now * 1.1) * 0.2
	local drift = math.sin(now * 0.9) * 0.3
	set(
		rig,
		"Body",
		CFrame.new(drift, hover + rear * 0.6 - down * 2, strike * -1.8 + hit * 0.6)
			* CFrame.Angles(
				math.rad(-moving * 18 - hit * 15),
				0,
				math.rad(math.clamp(-rig.turnRate * 10, -20, 20))
			)
	)
	local flap = math.sin(now * (14 + rear * 10 + moving * 6)) * math.rad(40) * (1 - down)
	set(rig, "WingL", CFrame.Angles(0, flap, 0) * CFrame.new(0, hover, 0))
	set(rig, "WingR", CFrame.Angles(0, -flap, 0) * CFrame.new(0, hover, 0))
end

--------------------------------------------------------------------------------

-- Nearest living player character within watching range.
local function nearestPlayerRoot(rig: Rig): BasePart?
	local range = math.min(TRACK_BASE_RANGE + TRACK_RANGE_PER_SCALE * rig.scale, TRACK_MAX_RANGE)
	local origin = rig.root.Position
	local best: BasePart? = nil
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local distance = (root.Position - origin).Magnitude
			if distance < range then
				best, range = root, distance
			end
		end
	end
	return best
end

local function watch(rig: Rig, dt: number, now: number)
	if now >= rig.nextTrackAt then
		rig.nextTrackAt = now + TRACK_SECONDS
		rig.trackRoot = if rig.defeatStart then nil else nearestPlayerRoot(rig)
	end
	local target = rig.trackRoot
	if target and target.Parent then
		local v = rig.root.CFrame:PointToObjectSpace(target.Position)
		local flatDistance = math.sqrt(v.X * v.X + v.Z * v.Z)
		local yaw = math.clamp(math.deg(math.atan2(-v.X, -v.Z)), -70, 70)
		local pitch = math.clamp(math.deg(math.atan2(v.Y, math.max(flatDistance, 1))), -25, 30)
		rig.track = rig.track:Lerp(Vector2.new(yaw, pitch), 1 - math.exp(-5 * dt))
		rig.alert = approach(rig.alert, 1, 3, dt)
	else
		rig.alert = approach(rig.alert, 0, 1.5, dt)
	end
end

local function idleActions(rig: Rig, now: number)
	if rig.idle or now < rig.nextIdleAt then
		return
	end
	local actions = IDLE_ACTIONS[rig.body]
	if actions == nil or #actions == 0 or rig.speed > 1.5 or rig.attackStart or rig.defeatStart then
		rig.nextIdleAt = now + 1
		return
	end
	rig.idle = actions[rng:NextInteger(1, #actions)]
	rig.idleStart = now
	rig.idleLength = rng:NextNumber(1.6, 2.6)
	rig.nextIdleAt = now + rig.idleLength + rng:NextNumber(4, 10) * (if rig.alert > 0.5 then 0.6 else 1)
end

local function animate(rig: Rig, dt: number, now: number, detailed: boolean)
	-- Speed from how far the root actually moved on this screen: the server
	-- simulates creatures, so the replicated velocity can read ~0 here
	-- (the legs would then stand still while the body glides). A jump of
	-- many studs in one frame is a teleport / respawn, not a step.
	if rig.root.Parent == nil then
		-- The root was re-sent by streaming: follow the new one (the old
		-- one stays where it was, which reads as standing still).
		local root = rig.model:FindFirstChild("HumanoidRootPart")
		if root == nil or not root:IsA("BasePart") then
			return
		end
		rig.root = root
		rig.lastPosition = root.Position
		rig.legs = nil
	end
	local position = rig.root.Position
	local moved = Vector3.new(position.X - rig.lastPosition.X, 0, position.Z - rig.lastPosition.Z).Magnitude
	rig.lastPosition = position
	rig.dt = dt
	local measured = if moved > 8 then 0 else moved / math.max(dt, 1e-3)
	local previous = rig.speed
	rig.speed = approach(rig.speed, measured, 8, dt)
	local flight = rig.model:GetAttribute("RC_Flight")
	local airTarget = if flight == "Land" then 0.5 elseif type(flight) == "string" then 1 else 0
	rig.air = approach(rig.air, airTarget, 3, dt)
	rig.dive = approach(rig.dive, if flight == "Dive" then 1 else 0, 6, dt)
	rig.accel = approach(rig.accel, (rig.speed - previous) / math.max(dt, 1e-3), 6, dt)
	-- Legged plans: the step cycle and the ground (gaitPrep). Others: the
	-- phase still advances with the distance moved.
	if rig.gait and rig.legs == nil then
		rig.legs = buildLegs(rig)
	end
	if rig.gait and rig.legs then
		-- In the air the feet have no ground to find.
		gaitPrep(rig, dt, detailed and rig.air < 0.3)
	else
		local stride = (STRIDE[rig.body] or 4) * rig.scale
		rig.phase = (rig.phase + rig.speed * dt / stride) % 1
		rig.stepAmp = math.clamp(rig.speed / 3, 0, 1)
		rig.run = smooth((rig.speed - 6) / 8)
	end
	-- Turning rate (radians per second), smoothed.
	local look = rig.root.CFrame.LookVector
	local yaw = math.atan2(-look.X, -look.Z)
	local delta = (yaw - rig.yaw + math.pi) % (math.pi * 2) - math.pi
	rig.yaw = yaw
	rig.turnRate = approach(rig.turnRate, delta / math.max(dt, 1e-3), 6, dt)
	-- Idle look-around.
	if now >= rig.nextLookAt then
		rig.nextLookAt = now + rng:NextNumber(2.5, 6)
		rig.lookTarget = if rng:NextNumber() < 0.35
			then Vector2.zero
			else Vector2.new(rng:NextNumber(-35, 35), rng:NextNumber(-10, 12))
	end
	rig.look = rig.look:Lerp(rig.lookTarget, 1 - math.exp(-2.5 * dt))
	watch(rig, dt, now)
	-- Enraged (low health, or a boss out of patience): locked on, never at ease.
	if rig.model:GetAttribute("RC_Enraged") then
		rig.alert = 1
	end
	-- Staggered by a heavy hit: a big recoil, and the wind-up is broken.
	local stagger = rig.model:GetAttribute("RC_Stagger")
	if stagger ~= rig.staggerStamp then
		rig.staggerStamp = stagger
		rig.staggerStart = now
		rig.attackStart = nil
		rig.idle = nil
		CreatureSfx.play(CreatureSounds.Cues.Stagger, rig.root, rig.scale, "stagger", 1)
		CreatureFx.dust(Vector3.new(rig.root.Position.X, groundY(rig), rig.root.Position.Z), rig.scale * 0.7)
	end
	idleActions(rig, now)
	-- Moving or fighting ends an idle action early.
	if rig.idle and (rig.speed > 2.5 or rig.attackStart or rig.defeatStart) then
		rig.idle = nil
	end

	effects(rig, now)
	local rear, strike = attackWeights(rig, now)
	local hit =
		math.max(pulse(rig.hitStart, now, HIT_SECONDS), pulse(rig.staggerStart, now, STAGGER_SECONDS) * 1.8)
	local down = if rig.defeatStart then smooth((now - rig.defeatStart) / DEFEAT_SECONDS) else 0
	if rig.body == "Wolf" then
		quadruped(rig, now, rear, strike, hit, down)
	elseif rig.body == "Beetle" then
		beetle(rig, now, rear, strike, hit, down)
	elseif rig.body == "Golem" or rig.body == "Guardian" then
		biped(rig, now, rear, strike, hit, down)
	elseif rig.body == "Serpent" then
		serpent(rig, now, rear, strike, hit, down)
	elseif rig.body == "Hydra" then
		hydraBody(rig, now, rear, strike, hit, down)
	else
		sprite(rig, now, rear, strike, hit, down)
	end
	wingsMotion(rig, now, rear, strike, hit, down)
	tailMotion(rig, now, rear, strike, down)
	-- Last: the feet, from wherever the body ended up this frame.
	stepLegs(rig, down)
end

-- Records a joint and what it says about the rig's anatomy.
local function addMotor(rig: Rig, motor: any)
	local name = motor.Name
	local replaced = rig.motors[name]
	rig.motors[name] = motor
	if replaced and replaced ~= motor then
		-- Re-sent by streaming: the legs and the serpent body hold the old
		-- joints, so they are rebuilt from the new ones.
		rig.legs = nil
		rig.slither = nil
	end
	if motor:IsA("Bone") then
		if motor.Parent and motor.Parent:IsA("Bone") then
			rig.boneParent[name] = motor.Parent.Name
		else
			-- A root bone: its rest frame relative to the root (no Transform yet).
			rig.boneRest[name] = rig.root.CFrame:ToObjectSpace(motor.WorldCFrame * motor.Transform:Inverse())
		end
	end
	local headTag = string.match(name, "^Head(%u?)$")
	if headTag and not table.find(rig.heads, headTag) then
		table.insert(rig.heads, headTag)
		table.sort(rig.heads)
	end
	if name == "Tail" then
		rig.tailCount = math.max(rig.tailCount, 1)
	end
	local tail = tonumber(string.match(name, "^Tail(%d+)$"))
	if tail then
		rig.tailCount = math.max(rig.tailCount, tail)
	end
	local seg = tonumber(string.match(name, "^Seg(%d+)$"))
	if seg then
		rig.segments = math.max(rig.segments, seg)
	end
end

local function track(model: Model)
	if rigs[model] then
		return
	end
	local body = model:GetAttribute("RC_Body")
	local root = model:WaitForChild("HumanoidRootPart", 5)
	if type(body) ~= "string" or root == nil or not root:IsA("BasePart") then
		return
	end
	local scale = model:GetAttribute("RC_Scale")
	local rigScale = if type(scale) == "number"
		then math.clamp(scale, 0.3, 6)
		else math.max(0.5, root.Size.Y / 2)
	local look = root.CFrame.LookVector
	-- Sculpted meshes (D-52): skeleton data, plan and gait from the shape.
	local shapeName = model:GetAttribute("RC_Shape")
	local mesh = if type(shapeName) == "string" then CreatureMeshes.Shapes[shapeName] else nil
	local plan = CreatureRigs.plan(body)
	local gait = CreatureRigs.gaitFor(body, rigScale)
	if mesh then
		local meshPlan = mesh.bodyPlan
		body = if meshPlan == "Quadruped"
			then "Wolf"
			elseif meshPlan == "Sprawler" then "Hydra"
			elseif meshPlan == "Hexapod" or meshPlan == "Octopod" then "Beetle"
			elseif meshPlan == "Biped" then (if body == "Guardian" then "Guardian" else "Golem")
			elseif meshPlan == "Sprite" then "Sprite"
			else "Serpent"
		plan = if #mesh.legs > 0
			then { bodyCenter = Vector3.zero, height = mesh.height, legs = mesh.legs :: any } :: any
			else nil
		local gaitName = if rigScale >= CreatureRigs.HEAVY_SCALE then mesh.heavyGait else mesh.gait
		gait = if gaitName and plan then CreatureRigs.Gaits[gaitName] else nil
	end
	local rig: Rig = {
		model = model,
		root = root,
		body = body,
		scale = rigScale,
		motors = {},
		mesh = mesh,
		boneParent = {},
		frames = {},
		boneRest = {},
		heads = {},
		tailCount = 0,
		segments = 0,
		plan = plan,
		gait = gait,
		legs = nil,
		run = 0,
		stepAmp = 0,
		stride = 0,
		duty = 0.6,
		lift = 0,
		footfall = 0,
		slope = 0,
		groundLift = 0,
		speed = 0,
		lastPosition = root.Position,
		air = 0,
		dive = 0,
		shape = if type(shapeName) == "string" then shapeName else nil,
		voice = CreatureSounds.voiceFor(if type(shapeName) == "string" then shapeName else nil, body),
		glow = nil,
		attackAlert = false,
		fxWindup = true,
		fxStruck = true,
		flightSeen = model:GetAttribute("RC_Flight"),
		enragedSeen = false,
		eyes = nil,
		eyeColor = nil,
		trail = {},
		slither = nil,
		neckCounter = 0,
		travel = 0,
		dt = 0,
		phase = rng:NextNumber(),
		yaw = math.atan2(-look.X, -look.Z),
		turnRate = 0,
		accel = 0,
		look = Vector2.zero,
		lookTarget = Vector2.zero,
		nextLookAt = os.clock() + rng:NextNumber(0, 3),
		trackRoot = nil,
		nextTrackAt = 0,
		track = Vector2.zero,
		alert = 0,
		idle = nil,
		idleStart = 0,
		idleLength = 1,
		nextIdleAt = os.clock() + rng:NextNumber(2, 8),
		attackStart = nil,
		windup = 0.5,
		move = "Strike",
		hitStart = nil,
		staggerStart = nil,
		staggerStamp = model:GetAttribute("RC_Stagger"),
		defeatStart = nil,
	}
	-- Joints hang off the root and off other limbs (chains); with streaming
	-- some arrive later.
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") or d:IsA("Bone") then
			addMotor(rig, d)
		end
	end
	model.DescendantAdded:Connect(function(d)
		if d:IsA("Motor6D") or d:IsA("Bone") then
			addMotor(rig, d)
		end
	end)
	rigs[model] = rig
	model.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			rigs[model] = nil
		end
	end)
end

-- Plays the wind-up -> strike motion; `windup` seconds until the hit lands,
-- `move` its shape (Strike / Slam / Roar / Sweep).
-- `alert`: not an attack but the roar of a creature that has just noticed
-- a player (no strike effect).
function MobVisualController.attack(model: Model, windup: number, move: string?, alert: boolean?)
	local rig = rigs[model]
	if rig then
		rig.attackStart = os.clock()
		rig.windup = math.max(0.15, windup)
		rig.move = if move and MOVES[move] then move else "Strike"
		rig.idle = nil
		rig.attackAlert = alert == true
		rig.fxWindup = false
		rig.fxStruck = false
	end
end

-- A short recoil when the creature takes damage.
function MobVisualController.hit(model: Model)
	local rig = rigs[model]
	if rig and rig.defeatStart == nil then
		rig.hitStart = os.clock()
	end
end

-- Sinks and rolls over (the body then fades, CombatFeedbackController).
function MobVisualController.defeat(model: Model)
	local rig = rigs[model]
	if rig then
		rig.defeatStart = os.clock()
		rig.attackStart = nil
		rig.idle = nil
		-- A last, deeper cry in its own voice (D-63: one shared lion cry made
		-- golems and birds roar), then the body settles in a puff of dust.
		CreatureFx.embers(rig.root, false, Color3.new())
		setEyes(rig, "Out")
		CreatureSfx.play(rig.voice, rig.root, rig.scale * 1.5, "defeat", 5, 0.8)
		task.delay(0.75, function()
			if rig.root.Parent then
				CreatureSfx.play(CreatureSounds.Cues.BodyFall, rig.root, rig.scale, "fall", 5)
				CreatureFx.dust(
					Vector3.new(rig.root.Position.X, groundY(rig), rig.root.Position.Z),
					rig.scale * 1.3
				)
			end
		end)
	end
end

function MobVisualController.isCreature(model: Model): boolean
	return model:GetAttribute("RC_Body") ~= nil
end

function MobVisualController:Start()
	CreatureSfx.preload()
	task.spawn(function()
		local npcs = Workspace:WaitForChild("RC_Npcs", 30)
		if npcs == nil then
			return
		end
		npcFolder = npcs
		npcs.ChildAdded:Connect(function(child)
			if child:IsA("Model") and (child :: Model):GetAttribute("RC_Body") ~= nil then
				task.spawn(track, child :: Model)
			end
		end)
		for _, child in npcs:GetChildren() do
			if child:IsA("Model") and (child :: Model):GetAttribute("RC_Body") ~= nil then
				task.spawn(track, child :: Model)
			end
		end
	end)
	-- After the Animator (Character priority) so these transforms win.
	RunService:BindToRenderStep("RC_MobVisual", Enum.RenderPriority.Character.Value + 2, function(dt: number)
		local camera = Workspace.CurrentCamera
		local origin = if camera then camera.CFrame.Position else Vector3.zero
		local now = os.clock()
		refreshRayFilter(now)
		for _, rig in rigs do
			local distance = (rig.root.Position - origin).Magnitude
			if distance <= UPDATE_DISTANCE then
				animate(rig, dt, now, distance <= GROUND_DETAIL_DISTANCE)
			else
				-- Out of range: keep its position current so the first step
				-- back in range does not read a burst of speed.
				rig.lastPosition = rig.root.Position
			end
		end
	end)
end

return MobVisualController
