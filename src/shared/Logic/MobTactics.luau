--!strict
--[[
	MobTactics — how each kind of creature closes in on its target
	(creature overhaul, creator review 2026-10-17; PLAN.md D-52). Pure.
	MobService runs it while a mob chases; MobBrain still decides when to
	wind up and strike once the target is in reach.

	Kinds:
	  Pack     wolves, hounds, Cerberus: stalk in a circle around the target
	           (a beat or two, either direction), then pounce in a burst of
	           speed.
	  Ambush   serpents, hydras: glide in, hold coiled just out of reach,
	           then lunge.
	  Brute    golems, knights, giants: stomp in; charge when the target
	           keeps its distance.
	  Skitter  beetles: zig-zag in.
	  Direct   anything else: straight in.

	Modes (MobService turns them into a goal and a speed):
	  Approach  towards the target (Skitter weaves)
	  Circle    orbit the target at CIRCLE_RADIUS x reach, `orbitDir` way
	  Hold      stand and face the target
	  Pounce    burst in at POUNCE_SPEED
	  Charge    run in at CHARGE_SPEED
	A tactic runs at most once per TACTIC_COOLDOWN seconds, so creatures
	never circle forever.
]]

local MobTactics = {}

export type Kind = "Pack" | "Ambush" | "Brute" | "Skitter" | "Direct"
export type Mode = "Approach" | "Circle" | "Hold" | "Pounce" | "Charge"

export type State = {
	mode: Mode,
	-- When the current mode ends (Circle / Hold / Pounce / Charge).
	untilTime: number,
	-- Earliest time the next tactic may start.
	readyAt: number,
	-- +1 / -1: which way a Circle orbits.
	orbitDir: number,
}

MobTactics.CIRCLE_RADIUS = 2.2
MobTactics.TACTIC_COOLDOWN = 6

local SPEED: { [Mode]: number } = {
	Approach = 1,
	Circle = 0.75,
	Hold = 0,
	Pounce = 1.7,
	Charge = 1.8,
}

function MobTactics.kindFor(body: string): Kind
	if body == "Wolf" then
		return "Pack"
	elseif body == "Serpent" then
		return "Ambush"
	elseif body == "Golem" or body == "Guardian" then
		return "Brute"
	elseif body == "Beetle" then
		return "Skitter"
	end
	return "Direct"
end

function MobTactics.initial(): State
	return { mode = "Approach", untilTime = 0, readyAt = 0, orbitDir = 1 }
end

-- Walk speed multiplier for a mode (Ambush creatures glide in a little slower).
function MobTactics.speedScale(kind: Kind, mode: Mode): number
	if kind == "Ambush" and mode == "Approach" then
		return 0.85
	end
	return SPEED[mode]
end

--[[
	The next tactic state while chasing. `distance` to the target, `reach`
	the mob's attack range, `roll` a random number 0..1 (server RNG).
]]
function MobTactics.step(
	kind: Kind,
	state: State,
	now: number,
	distance: number,
	reach: number,
	roll: number
): State
	local mode = state.mode
	local nextState: State = table.clone(state)
	local function switch(to: Mode, seconds: number)
		nextState.mode = to
		nextState.untilTime = now + seconds
	end
	if mode == "Approach" then
		if now < state.readyAt then
			return nextState
		end
		if kind == "Pack" and distance > reach * 1.3 and distance <= reach * 3.2 then
			switch("Circle", 1.2 + roll * 1.2)
			nextState.orbitDir = if roll < 0.5 then -1 else 1
		elseif kind == "Ambush" and distance > reach and distance <= reach * 1.8 then
			switch("Hold", 0.5 + roll * 0.6)
		elseif kind == "Brute" and distance > reach * 3 then
			switch("Charge", 2)
			nextState.readyAt = now + MobTactics.TACTIC_COOLDOWN + 1
		end
	elseif mode == "Circle" or mode == "Hold" then
		if now >= state.untilTime then
			-- Out of the stalk / coil: strike in.
			switch("Pounce", 1)
			nextState.readyAt = now + MobTactics.TACTIC_COOLDOWN
		end
	elseif mode == "Pounce" or mode == "Charge" then
		if now >= state.untilTime or distance <= reach * 1.1 then
			switch("Approach", 0)
		end
	end
	return nextState
end

return table.freeze(MobTactics)
