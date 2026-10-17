--!strict
--[[
	PartyService (Layer 5) — player parties (PLAN.md D-39, SECURITY_MODEL
	T-31).

	  - The player who sends the first invite creates the party and is its
	    leader. Only the leader invites and removes members.
	  - Invites target a player of the same realm who is not in a party; they
	    expire after Party.InviteSeconds. The invited player accepts or
	    declines (PartyRespond); a stale or forged answer does nothing.
	  - Leaving (or disconnecting) passes leadership to the longest-standing
	    member; a party of one dissolves.
	  - While the party is in a dungeon run no one new can be invited.
	  - Unions (D-48): a party leader invites other party leaders of the
	    same realm (UnionInvite / UnionRespond); up to Party.UnionMaxParties
	    parties fight as one group: kill EXP is shared across the whole
	    union nearby (D-32). Only the union leader (the first party's
	    leader) invites and removes parties; any party leader can take
	    their party out (UnionLeave). A party that dissolves leaves its
	    union; a union of one party dissolves.
	  - Membership lives only on the server; clients get the roster
	    (PartyState) and invites (PartyInvited) for display.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local PartyRules = require(Shared.Logic.PartyRules)
local Log = require(Shared.Util.Log)
local Signal = require(Shared.Util.Signal)

local ConfigurationService = require(script.Parent.ConfigurationService)
local NetService = require(script.Parent.NetService)
local PlayerDataService = require(script.Parent.PlayerDataService)

local log = Log.new("PartyService")

export type Party = {
	id: number,
	leader: Player,
	-- Join order (leader first when created).
	members: { Player },
	-- Pending invites: invited player -> expiry (os.clock).
	invites: { [Player]: number },
}

local PartyService = {
	-- (party) whenever membership or leadership changes.
	Changed = Signal.new(),
	-- (party, player) when a member leaves or is removed (party may be empty).
	MemberLeft = Signal.new(),
}

export type Union = {
	id: number,
	-- Parties in join order; the first one's leader runs the union.
	parties: { Party },
	-- Pending invites: invited party leader -> expiry (os.clock).
	invites: { [Player]: number },
}

local partyOf: { [Player]: Party } = {}
local unionOf: { [Party]: Union } = {}
local nextId = 0
-- DungeonService tells us which parties are inside a run.
local inDungeon: ((party: Party) -> boolean)? = nil

local function config(): any
	return ConfigurationService:Get("Party")
end

local function notify(player: Player, kind: string, key: string, params: { [string]: string }?)
	NetService:FireClient("Notify", player, { kind = kind, textKey = key, params = params })
end

local function raceOf(player: Player): string?
	local data = PlayerDataService:GetData(player)
	return if data then data.Race else nil
end

local function clearUnionView(player: Player)
	if player.Parent == Players then
		NetService:FireClient("UnionState", player, { parties = {}, maxParties = config().UnionMaxParties })
	end
end

local function clear(player: Player)
	if player.Parent == Players then
		NetService:FireClient("PartyState", player, { members = {}, maxMembers = config().MaxMembers })
		clearUnionView(player)
	end
end

--------------------------------------------------------------------------------
-- Unions (D-48)
--------------------------------------------------------------------------------

local function unionMembers(union: Union): { Player }
	local out = {}
	for _, party in union.parties do
		for _, member in party.members do
			table.insert(out, member)
		end
	end
	return out
end

local function pushUnion(union: Union)
	local roster = {}
	for index, party in union.parties do
		table.insert(
			roster,
			{ leaderUserId = party.leader.UserId, size = #party.members, leads = index == 1 }
		)
	end
	for _, member in unionMembers(union) do
		NetService:FireClient(
			"UnionState",
			member,
			{ parties = roster, maxParties = config().UnionMaxParties }
		)
	end
end

local function pushUnionOf(party: Party)
	local union = unionOf[party]
	if union then
		pushUnion(union)
	end
end

-- Takes `party` out of its union (dissolving a union of one).
local function leaveUnion(party: Party)
	local union = unionOf[party]
	if union == nil then
		return
	end
	local index = table.find(union.parties, party)
	if index then
		table.remove(union.parties, index)
	end
	unionOf[party] = nil
	for _, member in party.members do
		clearUnionView(member)
	end
	if #union.parties <= 1 then
		for _, last in table.clone(union.parties) do
			unionOf[last] = nil
			for _, member in last.members do
				clearUnionView(member)
			end
			if last.leader.Parent == Players then
				notify(last.leader, "Info", "union.dissolved")
			end
		end
		union.parties = {}
		union.invites = {}
		return
	end
	for _, member in unionMembers(union) do
		notify(member, "Info", "union.partyLeft", { name = party.leader.DisplayName })
	end
	pushUnion(union)
end

local function push(party: Party)
	local roster = {}
	for _, member in party.members do
		table.insert(roster, { userId = member.UserId, leader = member == party.leader })
		-- Display only: the union picker lists party leaders.
		member:SetAttribute("PartyLeader", if member == party.leader then true else nil)
		member:SetAttribute("PartySize", #party.members)
	end
	for _, member in party.members do
		NetService:FireClient("PartyState", member, { members = roster, maxMembers = config().MaxMembers })
	end
	pushUnionOf(party)
end

local function forget(player: Player)
	partyOf[player] = nil
	player:SetAttribute("PartyLeader", nil)
	player:SetAttribute("PartySize", nil)
	clear(player)
end

local function removeMember(party: Party, player: Player)
	local index = table.find(party.members, player)
	if index == nil then
		return
	end
	table.remove(party.members, index)
	forget(player)
	if party.leader == player then
		local successor = PartyRules.nextLeader(party.members, player)
		if successor then
			party.leader = successor
			notify(successor, "Info", "party.nowLeader")
		end
	end
	PartyService.MemberLeft:Fire(party, player)
	if #party.members <= 1 then
		-- A party of one dissolves (and leaves its union).
		leaveUnion(party)
		for _, last in table.clone(party.members) do
			forget(last)
		end
		party.members = {}
		party.invites = {}
		PartyService.Changed:Fire(party)
		return
	end
	push(party)
	PartyService.Changed:Fire(party)
end

local function onInvite(player: Player, target: Player)
	local party = partyOf[player]
	local facts: PartyRules.InviteFacts = {
		isSelf = target == player,
		inviterInParty = party ~= nil,
		inviterIsLeader = party ~= nil and party.leader == player,
		partySize = if party then #party.members else 1,
		maxMembers = config().MaxMembers,
		sameRace = raceOf(target) ~= nil and raceOf(target) == raceOf(player),
		targetInParty = partyOf[target] ~= nil,
		targetLoaded = target.Parent == Players and PlayerDataService:IsLoaded(target),
		alreadyInvited = party ~= nil and party.invites[target] ~= nil and os.clock() < party.invites[target],
		partyInDungeon = party ~= nil and inDungeon ~= nil and (inDungeon :: (Party) -> boolean)(party),
	}
	local ok, reason = PartyRules.canInvite(facts)
	if not ok then
		notify(player, "Warning", `party.invite.{reason}`)
		return
	end
	if party == nil then
		nextId += 1
		local created: Party = { id = nextId, leader = player, members = { player }, invites = {} }
		partyOf[player] = created
		party = created
		push(created)
	end
	local seconds = config().InviteSeconds;
	(party :: Party).invites[target] = os.clock() + seconds
	NetService:FireClient("PartyInvited", target, { fromUserId = player.UserId, expiresIn = seconds })
	notify(player, "Info", "party.invite.sent", { name = target.DisplayName })
end

local function onRespond(player: Player, inviter: Player, accept: boolean)
	local party = partyOf[inviter]
	local expiry = party and party.invites[player]
	if party == nil or expiry == nil then
		return
	end
	party.invites[player] = nil
	if os.clock() > expiry then
		notify(player, "Warning", "party.invite.expired")
		return
	end
	if not accept then
		notify(inviter, "Info", "party.invite.declined", { name = player.DisplayName })
		return
	end
	-- Re-check: things may have changed since the invite was sent.
	if
		partyOf[player] ~= nil
		or #party.members >= config().MaxMembers
		or raceOf(player) ~= raceOf(party.leader)
	then
		notify(player, "Warning", "party.invite.unavailable")
		return
	end
	if inDungeon and inDungeon(party) then
		notify(player, "Warning", "party.invite.inDungeon")
		return
	end
	table.insert(party.members, player)
	partyOf[player] = party
	for _, member in party.members do
		notify(member, "Info", "party.joined", { name = player.DisplayName })
	end
	push(party)
	PartyService.Changed:Fire(party)
end

local function onLeave(player: Player)
	local party = partyOf[player]
	if party then
		removeMember(party, player)
	end
end

local function onKick(player: Player, target: Player)
	local party = partyOf[player]
	if party == nil or party.leader ~= player or target == player or partyOf[target] ~= party then
		return
	end
	removeMember(party, target)
	notify(target, "Warning", "party.removed")
end

local function onUnionInvite(player: Player, target: Player)
	local party = partyOf[player]
	local targetParty = partyOf[target]
	local union = if party then unionOf[party] else nil
	local facts: PartyRules.UnionInviteFacts = {
		inviterHasParty = party ~= nil,
		inviterIsLeader = party ~= nil and party.leader == player,
		inviterInUnion = union ~= nil,
		inviterLeadsUnion = union ~= nil and union.parties[1] == party,
		sameParty = targetParty ~= nil and targetParty == party,
		targetIsLeader = targetParty ~= nil and targetParty.leader == target,
		targetInUnion = targetParty ~= nil and unionOf[targetParty] ~= nil,
		sameRace = raceOf(target) ~= nil and raceOf(target) == raceOf(player),
		unionSize = if union then #union.parties else 1,
		maxParties = config().UnionMaxParties,
		alreadyInvited = union ~= nil and union.invites[target] ~= nil and os.clock() < union.invites[target],
	}
	local ok, reason = PartyRules.canUnionInvite(facts)
	if not ok or party == nil then
		notify(player, "Warning", `union.invite.{reason or "unavailable"}`)
		return
	end
	local active: Union
	if union then
		active = union
	else
		nextId += 1
		active = { id = nextId, parties = { party }, invites = {} }
		unionOf[party] = active
	end
	local seconds = config().InviteSeconds
	active.invites[target] = os.clock() + seconds
	NetService:FireClient("UnionInvited", target, { fromUserId = player.UserId, expiresIn = seconds })
	notify(player, "Info", "union.invite.sent", { name = target.DisplayName })
end

local function onUnionRespond(player: Player, inviter: Player, accept: boolean)
	local inviterParty = partyOf[inviter]
	local union = if inviterParty then unionOf[inviterParty] else nil
	local expiry = if union then union.invites[player] else nil
	if union == nil or inviterParty == nil or expiry == nil then
		return
	end
	union.invites[player] = nil
	local function dropIfUnformed()
		-- A union nobody joined yet is only a pending invite list.
		if #union.parties <= 1 and next(union.invites) == nil then
			unionOf[inviterParty] = nil
		end
	end
	if os.clock() > expiry then
		notify(player, "Warning", "union.invite.expired")
		dropIfUnformed()
		return
	end
	if not accept then
		notify(inviter, "Info", "union.invite.declined", { name = player.DisplayName })
		dropIfUnformed()
		return
	end
	-- Re-check: things may have changed since the invite was sent.
	local party = partyOf[player]
	if
		party == nil
		or party.leader ~= player
		or unionOf[party] ~= nil
		or #union.parties >= config().UnionMaxParties
		or raceOf(player) ~= raceOf(inviter)
	then
		notify(player, "Warning", "union.invite.unavailable")
		dropIfUnformed()
		return
	end
	table.insert(union.parties, party)
	unionOf[party] = union
	for _, member in unionMembers(union) do
		notify(member, "Info", "union.joined", { name = player.DisplayName })
	end
	pushUnion(union)
end

local function onUnionLeave(player: Player)
	local party = partyOf[player]
	if party and party.leader == player then
		leaveUnion(party)
	end
end

local function onUnionKick(player: Player, target: Player)
	local party = partyOf[player]
	local targetParty = partyOf[target]
	local union = if party then unionOf[party] else nil
	if
		union == nil
		or party == nil
		or union.parties[1] ~= party
		or party.leader ~= player
		or targetParty == nil
		or targetParty == party
		or unionOf[targetParty] ~= union
	then
		return
	end
	leaveUnion(targetParty)
	notify(target, "Warning", "union.removed")
end

function PartyService:Init()
	NetService:Handle("UnionInvite", onUnionInvite)
	NetService:Handle("UnionRespond", onUnionRespond)
	NetService:Handle("UnionLeave", onUnionLeave)
	NetService:Handle("UnionKick", onUnionKick)
	NetService:Handle("PartyInvite", onInvite)
	NetService:Handle("PartyRespond", onRespond)
	NetService:Handle("PartyLeave", onLeave)
	NetService:Handle("PartyKick", onKick)
end

function PartyService:Start()
	Players.PlayerRemoving:Connect(function(player)
		local party = partyOf[player]
		if party then
			removeMember(party, player)
		end
		for _, other in partyOf do
			other.invites[player] = nil
		end
		for _, union in unionOf do
			union.invites[player] = nil
		end
	end)
	log:Info("parties ready (max %d)", config().MaxMembers)
end

--------------------------------------------------------------------------------
-- API (server-internal)
--------------------------------------------------------------------------------

function PartyService:GetParty(player: Player): Party?
	return partyOf[player]
end

-- Party members (the player alone if not in a party).
function PartyService:GetMembers(player: Player): { Player }
	local party = partyOf[player]
	return if party then table.clone(party.members) else { player }
end

-- Everyone the player fights alongside: the whole union, else the party,
-- else just the player (D-48 EXP sharing).
function PartyService:GetGroupMembers(player: Player): { Player }
	local party = partyOf[player]
	if party == nil then
		return { player }
	end
	local union = unionOf[party]
	return if union then unionMembers(union) else table.clone(party.members)
end

function PartyService:GetUnion(player: Player): Union?
	local party = partyOf[player]
	return if party then unionOf[party] else nil
end

-- The party leader (the player itself if not in a party).
function PartyService:GetLeader(player: Player): Player
	local party = partyOf[player]
	return if party then party.leader else player
end

function PartyService:SetDungeonCheck(check: (party: Party) -> boolean)
	inDungeon = check
end

return PartyService
