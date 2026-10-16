--!strict
--[[
	MobBrain — one decision step of a mob's AI (MobService runs it at
	≤ 10 Hz for every awake mob; ARCHITECTURE.md §7 performance budget).

	States
	  Idle     at its post; notices players inside aggroRadius
	  Chase    runs at its target; attacks when in range and ready
	  Windup   telegraphs an attack (stands still) until the hit lands
	  Return   lost its target or left its leash: walks home, ignores players,
	           and is restored to full HP on arrival

	The brain only decides; MobService moves the Humanoid and asks
	CombatService to resolve the hit (server-authoritative damage).

	Pure module.
]]

export type State = "Idle" | "Chase" | "Windup" | "Return"
export type Action = "None" | "MoveToTarget" | "Stop" | "StartWindup" | "Strike" | "MoveHome" | "Restore"

export type Input = {
	state: State,
	now: number,
	-- Distance to the nearest valid target (nil = none).
	targetDistance: number?,
	distanceFromHome: number,
	attackReadyAt: number,
	windupEndsAt: number,
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
		return "Idle", "None"
	end

	if state == "Idle" and distance > profile.aggroRadius then
		return "Idle", "None"
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
