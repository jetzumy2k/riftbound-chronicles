--!strict
--[[
	PartyRules — pure party rules (PLAN.md D-39).

	  canInvite      who may invite whom
	  nextLeader     who leads after the leader leaves (longest-standing member)
	  respawnChoice  where a member defeated in a dungeon comes back:
	                 next to the party leader if the leader is alive in the
	                 run, else next to any living member, else (the whole
	                 party is down) outside the dungeon gate

	Pure module.
]]

local PartyRules = {}

export type InviteFacts = {
	isSelf: boolean,
	inviterInParty: boolean,
	inviterIsLeader: boolean,
	partySize: number,
	maxMembers: number,
	sameRace: boolean,
	targetInParty: boolean,
	targetLoaded: boolean,
	alreadyInvited: boolean,
	partyInDungeon: boolean,
}

function PartyRules.canInvite(f: InviteFacts): (boolean, string?)
	if f.isSelf then
		return false, "self"
	elseif not f.targetLoaded then
		return false, "unavailable"
	elseif f.inviterInParty and not f.inviterIsLeader then
		return false, "notLeader"
	elseif not f.sameRace then
		return false, "otherRace"
	elseif f.targetInParty then
		return false, "targetInParty"
	elseif f.partySize >= f.maxMembers then
		return false, "full"
	elseif f.alreadyInvited then
		return false, "alreadyInvited"
	elseif f.partyInDungeon then
		return false, "inDungeon"
	end
	return true, nil
end

-- The member that leads after `leaving` goes (members in join order).
function PartyRules.nextLeader<T>(members: { T }, leaving: T): T?
	for _, member in members do
		if member ~= leaving then
			return member
		end
	end
	return nil
end

export type RespawnChoice = "Leader" | "Ally" | "Gate"

function PartyRules.respawnChoice(leaderAlive: boolean, anyAlive: boolean): RespawnChoice
	if leaderAlive then
		return "Leader"
	elseif anyAlive then
		return "Ally"
	end
	return "Gate"
end

return table.freeze(PartyRules)
