--!strict
--[[
	PartyRules — pure party rules (PLAN.md D-39).

	  canInvite      who may invite whom
	  nextLeader     who leads after the leader leaves (longest-standing member)
	  canUnionInvite which party leader may invite which into a union (D-48:
	                 up to UnionMaxParties parties; leaders only)
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

export type UnionInviteFacts = {
	inviterHasParty: boolean,
	inviterIsLeader: boolean,
	inviterInUnion: boolean,
	inviterLeadsUnion: boolean,
	sameParty: boolean,
	targetIsLeader: boolean,
	targetInUnion: boolean,
	sameRace: boolean,
	unionSize: number,
	maxParties: number,
	alreadyInvited: boolean,
}

function PartyRules.canUnionInvite(f: UnionInviteFacts): (boolean, string?)
	if not f.inviterHasParty then
		return false, "noParty"
	elseif not f.inviterIsLeader then
		return false, "notLeader"
	elseif f.inviterInUnion and not f.inviterLeadsUnion then
		return false, "notUnionLeader"
	elseif f.sameParty then
		return false, "self"
	elseif not f.targetIsLeader then
		return false, "targetNotLeader"
	elseif not f.sameRace then
		return false, "otherRace"
	elseif f.targetInUnion then
		return false, "targetInUnion"
	elseif f.unionSize >= f.maxParties then
		return false, "full"
	elseif f.alreadyInvited then
		return false, "alreadyInvited"
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
