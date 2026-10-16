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

local partyOf: { [Player]: Party } = {}
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

local function push(party: Party)
	local roster = {}
	for _, member in party.members do
		table.insert(roster, { userId = member.UserId, leader = member == party.leader })
	end
	for _, member in party.members do
		NetService:FireClient("PartyState", member, { members = roster, maxMembers = config().MaxMembers })
	end
end

local function clear(player: Player)
	if player.Parent == Players then
		NetService:FireClient("PartyState", player, { members = {}, maxMembers = config().MaxMembers })
	end
end

local function removeMember(party: Party, player: Player)
	local index = table.find(party.members, player)
	if index == nil then
		return
	end
	table.remove(party.members, index)
	partyOf[player] = nil
	clear(player)
	if party.leader == player then
		local successor = PartyRules.nextLeader(party.members, player)
		if successor then
			party.leader = successor
			notify(successor, "Info", "party.nowLeader")
		end
	end
	PartyService.MemberLeft:Fire(party, player)
	if #party.members <= 1 then
		-- A party of one dissolves.
		for _, last in table.clone(party.members) do
			partyOf[last] = nil
			clear(last)
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

function PartyService:Init()
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

-- The party leader (the player itself if not in a party).
function PartyService:GetLeader(player: Player): Player
	local party = partyOf[player]
	return if party then party.leader else player
end

function PartyService:SetDungeonCheck(check: (party: Party) -> boolean)
	inDungeon = check
end

return PartyService
