--!strict
--[[
	MobBrain — one decision step of a mob's AI (MobService runs it at
	≤ 10 Hz for every awake mob; ARCHITECTURE.md §7 performance budget).

	States
	  Idle     at its post; notices players inside aggroRadius
	  Alert    has just noticed one: turns to it and roars for
	           ALERT_SECONDS before giving chase (D-61)
	  Chase    runs at its target; attacks when in range and ready
	  Windup   telegraphs an attack (stands still) until the hit lands
	  Return   lost its target or left its leash: walks home, ignores players,
	           and is restored to full HP on arrival

	The brain only decides; MobService moves the Humanoid and asks
	CombatService to resolve the hit (server-authoritative damage). The
	recovery after a strike and a stagger from a heavy hit hold the
	creature still in MobService (Logic/MobAttacks).

	Pure module.
]]

export type State = "Idle" | "Alert" | "Chase" | "Windup" | "Return"
export type Action =
	"None"
	| "StartAlert"
	| "MoveToTarget"
	| "Stop"
	| "StartWindup"
	| "Strike"
	| "MoveHome"
	| "Restore"

export type Input = {
	state: State,
	now: number,
	-- Distance to the nearest valid target (nil = none).
	targetDistance: number?,
	distanceFromHome: number,
	attackReadyAt: number,
	windupEndsAt: number,
	-- When an Alert ends (default: at once).
	alertEndsAt: number?,
}

export type Profile = {
	aggroRadius: number,
	leashRadius: number,
	attackRange: number,
}

local MobBrain = {}

-- A chasing mob drops its target beyond this multiple of its aggro radius.
MobBrain.LOSE_TARGET_FACTOR = 2.5
-- Within this distance of home a returning mob counts as home.
MobBrain.HOME_RADIUS = 3
-- How long a creature takes to size up a player it has just noticed.
MobBrain.ALERT_SECONDS = 0.8

function MobBrain.step(input: Input, profile: Profile): (State, Action)
	local state = input.state
	if state == "Return" then
		if input.distanceFromHome <= MobBrain.HOME_RADIUS then
			return "Idle", "Restore"
		end
		return "Return", "MoveHome"
	end

	if state == "Windup" then
		-- Committed: the telegraphed hit always resolves (CombatService re-checks range).
		if input.now >= input.windupEndsAt then
			return "Chase", "Strike"
		end
		return "Windup", "None"
	end

	if input.distanceFromHome > profile.leashRadius then
		return "Return", "MoveHome"
	end

	local distance = input.targetDistance
	if distance == nil then
		if state == "Chase" then
			return "Return", "MoveHome"
		end
		-- Idle, or an Alert whose player slipped away.
		return "Idle", "None"
	end

	if state == "Idle" then
		if distance > profile.aggroRadius then
			return "Idle", "None"
		end
		return "Alert", "StartAlert"
	end
	if state == "Alert" then
		if input.now < (input.alertEndsAt or 0) then
			return "Alert", "None"
		end
		-- Sized it up: the chase is on.
		state = "Chase"
	end
	if state == "Chase" and distance > profile.aggroRadius * MobBrain.LOSE_TARGET_FACTOR then
		return "Return", "MoveHome"
	end

	if distance <= profile.attackRange then
		if input.now >= input.attackReadyAt then
			return "Windup", "StartWindup"
		end
		return "Chase", "Stop"
	end
	return "Chase", "MoveToTarget"
end

return table.freeze(MobBrain)
