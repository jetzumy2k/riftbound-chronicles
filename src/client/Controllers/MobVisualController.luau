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

	  Locomotion  speed is smoothed and the gait phase advances with the
	              distance actually walked (stride length per body plan), so
	              feet don't slide. Quadrupeds blend a 4-beat walk into a
	              gallop; beetles walk in alternating tripods; golems take
	              heavy swaying strides; serpents slither (a wave travels
	              down the body); sprites hover.
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
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local UPDATE_DISTANCE = 160
local STRIKE_SECONDS = 0.16
local RECOVER_SECONDS = 0.4
local HIT_SECONDS = 0.3
local DEFEAT_SECONDS = 0.9
-- Watching players: how often the nearest one is looked up, and how far.
local TRACK_SECONDS = 0.25
local TRACK_BASE_RANGE = 26
local TRACK_RANGE_PER_SCALE = 10
local TRACK_MAX_RANGE = 90

local MobVisualController = {}

type Rig = {
	model: Model,
	root: BasePart,
	body: string,
	scale: number,
	motors: { [string]: Motor6D },
	-- Anatomy found on the rig ("" / "L" / "R" heads, tail and body chains).
	heads: { string },
	tailCount: number,
	segments: number,
	-- Smoothed state.
	speed: number,
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
	defeatStart: number?,
}

local rigs: { [Model]: Rig } = {}
local rng = Random.new()

-- Stride length (studs per full gait cycle) per body plan, before scaling.
local STRIDE: { [string]: number } =
	{ Wolf = 4.2, Beetle = 2.4, Golem = 4.6, Guardian = 4.6, Sprite = 6, Serpent = 7 }

local IDLE_ACTIONS: { [string]: { string } } = {
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
	-- Folded along the back at rest; spread when alert, running or striking.
	local fold = math.clamp(0.9 - rig.alert * 0.6 - moving * 0.5 - rear * 0.9 - strike, 0, 1)
	local rate = 3 + rig.alert * 1.6 + moving * 2
	local beat = math.sin(now * rate) * 30 * (1 - fold) * (1 - rear)
	local lag = math.sin(now * rate - 0.7) * 22 * (1 - fold) * (1 - rear)
	local breathe = math.sin(now * 1.4) * 3
	local lift = -fold * 28 + beat + rear * 55 - strike * 50 - hit * 10 + breathe - down * 30
	local sweep = fold * 60
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
-- Body plans
--------------------------------------------------------------------------------

local function quadruped(rig: Rig, now: number, rear: number, strike: number, hit: number, down: number)
	local run = smooth((rig.speed - 6) / 8) -- 0 walk .. 1 gallop
	local moving = math.clamp(rig.speed / 3, 0, 1)
	local cycle = rig.phase * math.pi * 2
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
	-- Leg phase offsets: lateral-sequence walk -> rotary gallop.
	local offsets: { [string]: number } = {
		LegFL = 0,
		LegFR = 0.5 * (1 - run) + 0.12 * run,
		LegBL = 0.75 * (1 - run) + 0.55 * run,
		LegBR = 0.25 * (1 - run) + 0.65 * run,
	}
	local swingDeg = (24 + 22 * run) * moving
	for name, offset in offsets do
		local a = cycle + offset * math.pi * 2
		local swing = math.sin(a) * swingDeg
		-- Lift the paw while the leg swings forward (cos > 0), plant it otherwise.
		local lift = math.max(0, math.cos(a)) * (0.25 + 0.35 * run) * moving
		local front = string.sub(name, 4, 4) == "F"
		local brace = if front
			then rear * -20 + strike * 25 * lunge - slam * 55 + slamDown * 30 + sniff * 8
			else rear * 18 - strike * 10 + slam * 22
		-- Front paws paw at the air while rearing.
		local paw = if front then math.sin(now * 9 + (if name == "LegFL" then 0 else 2)) * 14 * slam else 0
		set(rig, name, CFrame.new(0, lift, 0) * rx(swing + brace + paw - down * 70))
	end
	local breathe = math.sin(now * 2.1) * (1 - moving)
	local flex = math.sin(cycle * 2) * 5 * run
	local bob = math.abs(math.sin(cycle)) * (0.08 + 0.18 * run) * moving
	local bank = math.clamp(-rig.turnRate * 9, -14, 14)
	local pitch = math.clamp(-rig.accel * 0.8, -6, 6)
	local shakeRoll = math.sin(now * 22) * 10 * shake
	set(
		rig,
		"Body",
		CFrame.new(
			0,
			bob
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
				bank + down * 75 + shakeRoll
			)
	)
	-- Heads lead turns, counter-bob at speed, watch players and look around.
	local count = #rig.heads
	for index, tag in rig.heads do
		local look = headLook(rig, index, count, now, moving)
		local headPitch = look.Y
			+ rear * 16 * (1 - roar)
			+ roar * 40
			- strike * 28 * lunge
			- math.sin(cycle) * 6 * run
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
			`Head{tag}`,
			CFrame.new(0, -bob * 0.6 - sniff * 0.2, -strike * 1.2 * lunge)
				* angles(headPitch, headYaw, math.sin(now * 22 + 0.6) * 12 * shake)
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
	local moving = math.clamp(rig.speed / 2.5, 0, 1)
	local cycle = rig.phase * math.pi * 2
	local idle, w = idleWeight(rig, now)
	local rearUp = weightOf("Rear", idle, w) + (if rig.move == "Slam" then rear else 0)
	for i = 1, 6 do
		-- Alternating tripods: legs 1, 4, 5 and 2, 3, 6.
		local group = if i == 1 or i == 4 or i == 5 then 0 else math.pi
		local a = cycle + group
		local swing = math.sin(a) * 26 * moving
		local lift = math.max(0, math.cos(a)) * 0.35 * moving
		local fold = down * (if i % 2 == 0 then 50 else -50)
		-- Front legs wave while rearing up.
		local wave = if i <= 2 then rearUp * (-40 + math.sin(now * 8 + i) * 15) else 0
		set(rig, `Leg{i}`, CFrame.new(0, lift, 0) * rx(swing + wave) * CFrame.Angles(0, 0, math.rad(fold)))
	end
	local sway = math.sin(cycle) * 3 * moving
	local breathe = math.sin(now * 1.6) * (1 - moving)
	set(
		rig,
		"Body",
		CFrame.new(0, breathe * 0.05 + rear * 0.35 + rearUp * 0.4 - down * 0.8, strike * -0.9 + hit * 0.4)
			* CFrame.Angles(
				math.rad(rear * 10 + rearUp * 16 - strike * 6 - hit * 6),
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
end

local function biped(rig: Rig, now: number, rear: number, strike: number, hit: number, down: number)
	local moving = math.clamp(rig.speed / 3, 0, 1)
	local cycle = rig.phase * math.pi * 2
	local idle, w = idleWeight(rig, now)
	local roar = weightOf("Roar", idle, w) + (if rig.move == "Roar" then rear else 0)
	local stretch = weightOf("Stretch", idle, w)
	local slam = if rig.move == "Slam" then 1 else 0
	local sweep = if rig.move == "Sweep" then 1 else 0
	local swing = math.sin(cycle) * 28 * moving
	local liftL = math.max(0, math.cos(cycle)) * 0.4 * moving
	local liftR = math.max(0, -math.cos(cycle)) * 0.4 * moving
	set(rig, "LegL", CFrame.new(0, liftL, 0) * rx(swing - down * 80))
	set(rig, "LegR", CFrame.new(0, liftR, 0) * rx(-swing - down * 60))
	local breathe = math.sin(now * 1.5)
	-- Arms spread wide to roar; a slam brings both overhead and down.
	local spread = roar * 55 + stretch * 30
	set(
		rig,
		"ArmL",
		rx(-swing * 0.7 + breathe * 2 - hit * 20 + slam * (rear * 165 + strike * 40) + stretch * 40)
			* CFrame.Angles(0, 0, math.rad(-down * 40 - spread))
	)
	-- The weapon arm raises overhead in the wind-up and slams down; a sweep
	-- swings it across the front.
	set(
		rig,
		"ArmR",
		rx(swing * 0.7 + rear * 165 * (1 - sweep) + rear * 85 * sweep + strike * 40 - hit * 20)
			* CFrame.Angles(0, math.rad(sweep * (rear * 50 - strike * 90)), math.rad(down * 40 + spread))
	)
	-- Heavy stride: weight shifts side to side and dips at each footfall.
	local roll = math.sin(cycle) * 4 * moving + math.sin(now * 1.2) * 4 * stretch
	local dip = -math.abs(math.cos(cycle)) * 0.18 * moving
	set(
		rig,
		"Body",
		CFrame.new(0, dip + breathe * 0.06 - strike * 0.3 - strike * slam * 0.4 - down * 1.6, hit * 0.4)
			* CFrame.Angles(
				math.rad(
					rear * 8
						- strike * 16
						- strike * slam * 12
						- hit * 10
						+ roar * 12
						+ math.clamp(-rig.accel * 0.6, -5, 5)
						- down * 35
				),
				math.rad(rear * -12 + sweep * (rear * -15 + strike * 25)),
				math.rad(roll + math.clamp(-rig.turnRate * 6, -8, 8))
			)
	)
	local look = headLook(rig, 1, 1, now, moving)
	set(
		rig,
		"Head",
		CFrame.Angles(
			math.rad(breathe * 2 + rear * 6 + look.Y * 0.6 + roar * 30 - down * 25),
			math.rad(look.X * 0.8),
			0
		)
	)
end

local function serpent(rig: Rig, now: number, rear: number, strike: number, hit: number, down: number)
	local moving = math.clamp(rig.speed / 3, 0, 1)
	local still = 1 - moving
	local cycle = rig.phase * math.pi * 2
	local idle, w = idleWeight(rig, now)
	local rise = weightOf("Rise", idle, w) + (if rig.move == "Slam" then rear else 0)
	local hiss = weightOf("Hiss", idle, w) + (if rig.move == "Roar" then rear else 0)
	local coil = weightOf("Coil", idle, w)
	local sweep = if rig.move == "Sweep" then 1 else 0
	local lunge = if rig.move == "Strike" or rig.move == "Slam" then 1 else 0.4
	-- Slithering: a wave travels from the chest to the tail tip.
	for i = 1, rig.segments do
		local wave = math.sin(cycle - i * 0.9) * 17 * moving
		local sway = math.sin(now * 0.8 - i * 0.6) * 6 * still
		set(rig, `Seg{i}`, angles(0, (wave + sway + coil * 22 + rig.alert * 3) * (1 - down * 0.6), down * 4))
	end
	local breathe = math.sin(now * 1.5) * still
	set(
		rig,
		"Body",
		CFrame.new(0, breathe * 0.06 - down * 0.6, -strike * 1.2 * lunge + hit * 0.4)
			* angles(
				rear * 5 - strike * 4 - hit * 6,
				math.sin(cycle) * 10 * moving
					+ math.sin(now * 0.7) * 4 * still
					+ sweep * (rear * 15 - strike * 25),
				math.clamp(-rig.turnRate * 8, -12, 12) + down * 80
			)
	)
	local count = #rig.heads
	for index, tag in rig.heads do
		local look = headLook(rig, index, count, now, moving)
		local sway = math.sin(now * 1.3 + index * 1.9) * 5 * still
		-- Rear back (S-curve) in the wind-up, then strike down and forward.
		set(
			rig,
			`Neck{tag}`,
			angles(
				rear * 22 - strike * 42 * lunge + rise * 18 + hit * 10 + sway - down * 45,
				look.X * 0.45 + math.sin(cycle + 1) * 6 * moving + sweep * (rear * 30 - strike * 40),
				0
			)
		)
		set(
			rig,
			`NeckB{tag}`,
			angles(rear * 20 - strike * 26 * lunge + rise * 10 - down * 30, look.X * 0.35, 0)
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

local function animate(rig: Rig, dt: number, now: number)
	local velocity = rig.root.AssemblyLinearVelocity
	local measured = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local previous = rig.speed
	rig.speed = approach(rig.speed, measured, 8, dt)
	rig.accel = approach(rig.accel, (rig.speed - previous) / math.max(dt, 1e-3), 6, dt)
	-- Gait phase from the distance walked (no foot sliding).
	local stride = (STRIDE[rig.body] or 4) * rig.scale
	rig.phase = (rig.phase + rig.speed * dt / stride) % 1
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
	idleActions(rig, now)
	-- Moving or fighting ends an idle action early.
	if rig.idle and (rig.speed > 2.5 or rig.attackStart or rig.defeatStart) then
		rig.idle = nil
	end

	local rear, strike = attackWeights(rig, now)
	local hit = pulse(rig.hitStart, now, HIT_SECONDS)
	local down = if rig.defeatStart then smooth((now - rig.defeatStart) / DEFEAT_SECONDS) else 0
	if rig.body == "Wolf" then
		quadruped(rig, now, rear, strike, hit, down)
	elseif rig.body == "Beetle" then
		beetle(rig, now, rear, strike, hit, down)
	elseif rig.body == "Golem" or rig.body == "Guardian" then
		biped(rig, now, rear, strike, hit, down)
	elseif rig.body == "Serpent" then
		serpent(rig, now, rear, strike, hit, down)
	else
		sprite(rig, now, rear, strike, hit, down)
	end
	wingsMotion(rig, now, rear, strike, hit, down)
	tailMotion(rig, now, rear, strike, down)
end

-- Records a joint and what it says about the rig's anatomy.
local function addMotor(rig: Rig, motor: Motor6D)
	local name = motor.Name
	rig.motors[name] = motor
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
	local look = root.CFrame.LookVector
	local rig: Rig = {
		model = model,
		root = root,
		body = body,
		scale = if type(scale) == "number" then math.clamp(scale, 0.3, 6) else math.max(0.5, root.Size.Y / 2),
		motors = {},
		heads = {},
		tailCount = 0,
		segments = 0,
		speed = 0,
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
		defeatStart = nil,
	}
	-- Joints hang off the root and off other limbs (chains); with streaming
	-- some arrive later.
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") then
			addMotor(rig, d)
		end
	end
	model.DescendantAdded:Connect(function(d)
		if d:IsA("Motor6D") then
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
function MobVisualController.attack(model: Model, windup: number, move: string?)
	local rig = rigs[model]
	if rig then
		rig.attackStart = os.clock()
		rig.windup = math.max(0.15, windup)
		rig.move = if move and MOVES[move] then move else "Strike"
		rig.idle = nil
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
	end
end

function MobVisualController.isCreature(model: Model): boolean
	return model:GetAttribute("RC_Body") ~= nil
end

function MobVisualController:Start()
	task.spawn(function()
		local npcs = Workspace:WaitForChild("RC_Npcs", 30)
		if npcs == nil then
			return
		end
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
		for _, rig in rigs do
			if (rig.root.Position - origin).Magnitude <= UPDATE_DISTANCE then
				animate(rig, dt, now)
			end
		end
	end)
end

return MobVisualController
