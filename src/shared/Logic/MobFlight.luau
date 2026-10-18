--!strict
--[[
	MobFlight — when and how winged creatures take to the air (creature
	overhaul stage 3, PLAN.md D-60). Pure. MobService runs it for creatures
	that can fly, flies them with server-owned movers and resolves the dive.

	Modes:
	  Ground  walking and fighting as usual (MobBrain); while chasing, once
	          the flight is ready and there is headroom, it takes off
	  Rise    climbing to its cruising height
	  Circle  wheeling round the target overhead (out of melee reach)
	  Warn    hovering, the dive's landing spot marked on the ground
	  Dive    swooping onto the marked spot; the hit resolves on landing
	  Land    settling back to the ground (also when stunned, the target
	          is lost or it was cut short); then Ground for a while
	Grounded spells always run long enough for melee fighters to answer.
]]

local MobFlight = {}

export type Mode = "Ground" | "Rise" | "Circle" | "Warn" | "Dive" | "Land"

export type State = {
	mode: Mode,
	-- When the current mode ends.
	untilTime: number,
	-- Earliest time it may take off again.
	readyAt: number,
	-- +1 / -1: which way it wheels.
	orbitDir: number,
}

export type Input = {
	now: number,
	-- Chasing a target it may attack.
	chasing: boolean,
	stunned: boolean,
	-- Height above the ground and room overhead (studs).
	altitude: number,
	headroom: number,
	-- Creature size (scales the cruising height).
	scale: number,
	-- Reached the dive's spot.
	arrived: boolean,
	-- Server RNG 0..1.
	roll: number,
}

MobFlight.MIN_HEADROOM = 9
MobFlight.RISE_SECONDS = 2
MobFlight.WARN_SECONDS = 1.1
MobFlight.DIVE_SECONDS = 1.4
MobFlight.LAND_SECONDS = 2.5
-- Seconds on the ground between flights (plus up to GROUND_JITTER).
MobFlight.GROUND_SECONDS = 7
MobFlight.GROUND_JITTER = 4

-- Creatures with wings fly (the sprite only hovers).
function MobFlight.canFly(body: string, traits: { string }?): boolean
	if body == "Sprite" then
		return false
	end
	for _, trait in (traits or {}) :: { string } do
		if trait == "Wings" then
			return true
		end
	end
	return false
end

-- Cruising height above the ground: bigger creatures fly higher, never
-- into the ceiling.
function MobFlight.cruiseHeight(scale: number, headroom: number): number
	return math.min(7 + scale * 2.5, headroom - 3)
end

function MobFlight.isAirborne(mode: Mode): boolean
	return mode ~= "Ground"
end

-- Fresh state: grounded, first flight a few seconds after it notices you.
function MobFlight.initial(now: number, roll: number): State
	return { mode = "Ground", untilTime = 0, readyAt = now + 3 + roll * 3, orbitDir = 1 }
end

function MobFlight.step(state: State, input: Input): State
	local now = input.now
	local nextState: State = table.clone(state)
	local function switch(to: Mode, seconds: number)
		nextState.mode = to
		nextState.untilTime = now + seconds
	end
	local mode = state.mode
	if mode == "Ground" then
		if
			input.chasing
			and not input.stunned
			and now >= state.readyAt
			and input.headroom >= MobFlight.MIN_HEADROOM
		then
			switch("Rise", MobFlight.RISE_SECONDS)
			nextState.orbitDir = if input.roll < 0.5 then -1 else 1
		end
		return nextState
	end
	-- Airborne: stunned or nothing to fight, it comes down.
	local grounded = input.stunned or not input.chasing
	if mode == "Land" then
		if input.altitude <= 0.6 or now >= state.untilTime then
			switch("Ground", 0)
			nextState.readyAt = now + MobFlight.GROUND_SECONDS + input.roll * MobFlight.GROUND_JITTER
		end
	elseif grounded then
		switch("Land", MobFlight.LAND_SECONDS)
	elseif mode == "Rise" then
		local cruise = MobFlight.cruiseHeight(input.scale, input.headroom)
		if now >= state.untilTime or input.altitude >= cruise * 0.85 then
			switch("Circle", 2.5 + input.roll * 1.5)
		end
	elseif mode == "Circle" then
		if now >= state.untilTime then
			switch("Warn", MobFlight.WARN_SECONDS)
		end
	elseif mode == "Warn" then
		if now >= state.untilTime then
			switch("Dive", MobFlight.DIVE_SECONDS)
		end
	elseif mode == "Dive" then
		if input.arrived or now >= state.untilTime then
			switch("Land", MobFlight.LAND_SECONDS)
		end
	end
	return nextState
end

return table.freeze(MobFlight)
