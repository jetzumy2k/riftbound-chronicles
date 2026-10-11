--!strict
--[[
	ComboMath — the basic-attack combo chain (BasicAttacks). The server uses
	it to decide which step a press is; the client uses the same rules to
	predict the animation, so both agree unless the network jitters.

	State per attacker: the step last started, when it started, and when the
	next press is allowed.

	Pure module.
]]

-- Any table with `recovery` and `window` (BasicAttacks.ComboStep).
export type Step = { recovery: number, window: number, [any]: any }
export type State = { index: number, startedAt: number, readyAt: number }

local ComboMath = {}

function ComboMath.new(): State
	return { index = 0, startedAt = -math.huge, readyAt = -math.huge }
end

--[[
	The step a press at `now` starts, or nil if it is too early. `slack`
	forgives presses that arrive up to that many seconds early (network
	jitter on the server; 0 on the client).
]]
function ComboMath.resolve(state: State, now: number, steps: { any }, slack: number?): number?
	if now < state.readyAt - (slack or 0) then
		return nil
	end
	local current = steps[state.index]
	if current and state.index < #steps and now <= state.startedAt + current.recovery + current.window then
		return state.index + 1
	end
	return 1
end

-- Records that `index` started at `now`.
function ComboMath.commit(state: State, now: number, steps: { any }, index: number, finisherCooldown: number)
	state.index = index
	state.startedAt = now
	state.readyAt = now + steps[index].recovery + (if index == #steps then finisherCooldown else 0)
end

-- Seconds until a press is accepted (0 when ready).
function ComboMath.waitTime(state: State, now: number): number
	return math.max(0, state.readyAt - now)
end

return table.freeze(ComboMath)
