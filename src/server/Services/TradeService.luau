--!strict
--[[
	TradeService (Layer 6) — player-to-player trading (creator request
	2026-10-27, PLAN.md D-121; what may be traded in Logic/TradeRules,
	numbers in config Trade).

	Scam protections, all on the server:
	  - Both players: same server and realm, level Trade.MinLevel+, inside
	    a safe zone, within reach of each other, out of combat.
	  - Each must accept the risk warning ("trades are at your own risk")
	    before locking.
	  - Any change to either offer clears BOTH players' lock and confirm.
	  - Both lock -> both see the final summary -> both confirm -> a
	    3-second countdown either can cancel -> the swap.
	  - The swap re-checks everything (ownership, counts, Gold, bag room,
	    reach, combat) and moves it all in one step (no yields), so it
	    either happens completely or not at all; then both profiles save.
	  - Never Mall Points, Mall gear, Mall-only consumables, equipped or
	    locked items (TradeRules).
	  - Every trade gets an id, is audit logged with both sides, and is
	    kept in each character's trade history (TradeHistory). Report sends
	    a trade id to staff (audit log + a notice to staff online) as
	    evidence (creator: report scams with the transaction history).

	Remote Trade (Function): Invite, Accept, Decline, Offer, Ack, Lock,
	Unlock, Confirm, Cancel, History, Report. TradeUpdate (event) pushes
	the session to both players; TradeInvite tells a player they were
	invited.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local TradeRules = require(Shared.Logic.TradeRules)
local ItemDefinitions = require(Shared.Definitions.ItemDefinitions)
local Log = require(Shared.Util.Log)

local ProfileView = require(script.Parent.Parent.Persistence.ProfileView)

local ConfigurationService = require(script.Parent.ConfigurationService)
local AuditLogService = require(script.Parent.AuditLogService)
local NetService = require(script.Parent.NetService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local CombatService = require(script.Parent.CombatService)
local SafeZoneService = require(script.Parent.SafeZoneService)

local log = Log.new("TradeService")

type Session = {
	id: string,
	players: { Player },
	offers: { [Player]: TradeRules.Offer },
	ack: { [Player]: boolean },
	locked: { [Player]: boolean },
	confirmed: { [Player]: boolean },
	countdownEnds: number?,
	token: number,
}

local TradeService = {}

local sessions: { [Player]: Session } = {}
-- target -> { from, at }
local invites: { [Player]: { from: Player, at: number } } = {}

local function config(): any
	return ConfigurationService:Get("Trade")
end

local function notify(player: Player, kind: string, textKey: string, params: { [string]: string }?)
	NetService:FireClient("Notify", player, { kind = kind, textKey = textKey, params = params })
end

local function other(session: Session, player: Player): Player
	return if session.players[1] == player then session.players[2] else session.players[1]
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Why `a` can't trade with `b` right now, or nil.
local function blocker(a: Player, b: Player): string?
	local c = config()
	local da, db = PlayerDataService:GetData(a), PlayerDataService:GetData(b)
	if not c.Enabled then
		return "closed"
	elseif da == nil or db == nil or da.Job == nil or db.Job == nil then
		return "notLoaded"
	elseif da.Race ~= db.Race and not c.CrossRealm then
		return "realm"
	elseif (da.Level or 0) < c.MinLevel or (db.Level or 0) < c.MinLevel then
		return "level"
	elseif not SafeZoneService:IsInSafeZone(a) or not SafeZoneService:IsInSafeZone(b) then
		return "safeZone"
	end
	local ra, rb = rootOf(a), rootOf(b)
	if ra == nil or rb == nil or (ra.Position - rb.Position).Magnitude > c.Reach then
		return "far"
	end
	for _, p in { a, b } do
		local entity = CombatService:GetPlayerEntity(p)
		if entity and CombatService:IsEntityInCombat(entity) then
			return "combat"
		end
	end
	return nil
end

local function offerView(player: Player, offer: TradeRules.Offer): { [string]: any }
	local data = PlayerDataService:GetData(player)
	local items = {}
	for _, guid in offer.Items do
		local item = data and data.Inventory[guid]
		if item then
			table.insert(items, ProfileView.item(item))
		end
	end
	return { Gold = offer.Gold, Items = items, Stackables = table.clone(offer.Stackables) }
end

local function push(session: Session)
	for _, player in session.players do
		local partner = other(session, player)
		NetService:FireClient("TradeUpdate", player, {
			Id = session.id,
			Open = true,
			Partner = { UserId = partner.UserId, Name = partner.DisplayName },
			Mine = offerView(player, session.offers[player]),
			Theirs = offerView(partner, session.offers[partner]),
			MeAck = session.ack[player] == true,
			MeLocked = session.locked[player] == true,
			ThemLocked = session.locked[partner] == true,
			MeConfirmed = session.confirmed[player] == true,
			ThemConfirmed = session.confirmed[partner] == true,
			CountdownIn = if session.countdownEnds
				then math.max(0, math.ceil(session.countdownEnds - os.clock()))
				else nil,
		})
	end
end

local function close(session: Session, reason: string)
	for _, player in session.players do
		if sessions[player] == session then
			sessions[player] = nil
		end
		if player.Parent == Players then
			NetService:FireClient("TradeUpdate", player, { Id = session.id, Open = false, Reason = reason })
		end
	end
	session.token += 1
end

-- Any change: both must lock and confirm again (and the countdown stops).
local function resetAgreement(session: Session)
	session.locked = {}
	session.confirmed = {}
	session.countdownEnds = nil
	session.token += 1
end

local function summary(player: Player, offer: TradeRules.Offer): string
	local data = PlayerDataService:GetData(player)
	local parts = {}
	if offer.Gold > 0 then
		table.insert(parts, `{offer.Gold} Gold`)
	end
	for _, guid in offer.Items do
		local item = data and data.Inventory[guid]
		local def = item and ItemDefinitions.get(item.DefId)
		if item and def then
			table.insert(
				parts,
				`{item.Rarity} {def.name}{if item.Enhancement > 0 then ` +{item.Enhancement}` else ""}`
			)
		end
	end
	for id, n in offer.Stackables do
		local def = ItemDefinitions.stackable(id)
		table.insert(parts, `{n} {if def then def.name else id}`)
	end
	return if #parts == 0 then "nothing" else table.concat(parts, ", ")
end

local function remember(data: { [string]: any }, entry: { [string]: any })
	data.TradeHistory = data.TradeHistory or {}
	table.insert(data.TradeHistory, 1, entry)
	while #data.TradeHistory > TradeRules.HISTORY do
		table.remove(data.TradeHistory)
	end
end

-- The swap: re-check everything, then move it all at once (no yields).
local function execute(session: Session)
	local a, b = session.players[1], session.players[2]
	local why = blocker(a, b)
	local da, db = PlayerDataService:GetData(a), PlayerDataService:GetData(b)
	if why == nil and (da == nil or db == nil) then
		why = "notLoaded"
	end
	local oa, ob = session.offers[a], session.offers[b]
	if why == nil then
		local ok1, r1 = TradeRules.checkOffer(da :: any, oa)
		local ok2, r2 = TradeRules.checkOffer(db :: any, ob)
		local ok3, r3 = TradeRules.canReceive(da :: any, oa, ob)
		local ok4, r4 = TradeRules.canReceive(db :: any, ob, oa)
		why = if not ok1 then r1 elseif not ok2 then r2 elseif not ok3 then r3 elseif not ok4 then r4 else nil
	end
	-- An item id already on the other side is never overwritten.
	if why == nil then
		for _, guid in oa.Items do
			if (db :: any).Inventory[guid] ~= nil then
				why = "item"
			end
		end
		for _, guid in ob.Items do
			if (da :: any).Inventory[guid] ~= nil then
				why = "item"
			end
		end
	end
	if why == nil and TradeRules.isEmpty(oa) and TradeRules.isEmpty(ob) then
		why = "empty"
	end
	if why then
		resetAgreement(session)
		for _, p in session.players do
			notify(p, "Warning", "trade.failed", { reason = why })
		end
		push(session)
		return
	end
	local A, B = da :: any, db :: any
	local gaveA, gaveB = summary(a, oa), summary(b, ob)
	-- Move: gold, items, stackables (a -> b, then b -> a).
	local function move(from: any, to: any, offer: TradeRules.Offer)
		from.Wallet.Gold -= offer.Gold
		to.Wallet.Gold = (to.Wallet.Gold or 0) + offer.Gold
		for _, guid in offer.Items do
			local item = from.Inventory[guid]
			from.Inventory[guid] = nil
			to.Inventory[guid] = item
		end
		for id, n in offer.Stackables do
			from.Stackables[id] -= n
			if from.Stackables[id] <= 0 then
				from.Stackables[id] = nil
			end
			to.Stackables[id] = (to.Stackables[id] or 0) + n
		end
	end
	move(A, B, oa)
	move(B, A, ob)
	local now = os.time()
	remember(
		A,
		{ Id = session.id, At = now, With = b.UserId, WithName = b.DisplayName, Gave = gaveA, Got = gaveB }
	)
	remember(
		B,
		{ Id = session.id, At = now, With = a.UserId, WithName = a.DisplayName, Gave = gaveB, Got = gaveA }
	)
	AuditLogService:Audit({
		actorUserId = a.UserId,
		action = "Trade",
		target = session.id,
		details = { a = a.UserId, b = b.UserId, aGave = gaveA, bGave = gaveB },
	})
	log:Info("trade %s: %d gave [%s], %d gave [%s]", session.id, a.UserId, gaveA, b.UserId, gaveB)
	close(session, "done")
	for _, p in { a, b } do
		notify(p, "Info", "trade.done", { name = other(session, p).DisplayName })
		PlayerDataService:PushSnapshot(p)
		PlayerDataService:SaveNow(p)
	end
end

local function startCountdown(session: Session)
	session.countdownEnds = os.clock() + TradeRules.COUNTDOWN_SECONDS
	session.token += 1
	local token = session.token
	push(session)
	task.delay(TradeRules.COUNTDOWN_SECONDS, function()
		if session.token == token and sessions[session.players[1]] == session then
			execute(session)
		end
	end)
end

local function readOffer(args: any): TradeRules.Offer
	local offer = TradeRules.emptyOffer()
	offer.Gold = if type(args.GoldOffered) == "number" then args.GoldOffered else 0
	offer.Items = if type(args.Items) == "table" then args.Items else {}
	offer.Stackables = if type(args.Stackables) == "table" then args.Stackables else {}
	return offer
end

local function onRequest(player: Player, action: string, args: { [string]: any }): { [string]: any }
	local data = PlayerDataService:GetData(player)
	if data == nil then
		return { ok = false, reason = "notLoaded" }
	end
	if action == "History" then
		return { ok = true, history = data.TradeHistory or {} }
	elseif action == "Report" then
		local id = args.TradeId
		local entry = nil
		for _, e in data.TradeHistory or {} do
			if e.Id == id then
				entry = e
			end
		end
		if entry == nil then
			return { ok = false, reason = "unknownTrade" }
		end
		AuditLogService:Audit({
			actorUserId = player.UserId,
			action = "TradeReport",
			target = entry.Id,
			details = { against = entry.With, gave = entry.Gave, got = entry.Got, at = entry.At },
		})
		for _, staff in Players:GetPlayers() do
			if staff:GetAttribute("RC_IsStaff") == true then
				notify(staff, "Warning", "trade.reported", { id = entry.Id, name = player.DisplayName })
			end
		end
		return { ok = true }
	end

	local session = sessions[player]
	if action == "Invite" then
		local target = Players:GetPlayerByUserId(args.UserId or 0)
		if target == nil or target == player then
			return { ok = false, reason = "player" }
		end
		if session or sessions[target] then
			return { ok = false, reason = "busy" }
		end
		local why = blocker(player, target)
		if why then
			return { ok = false, reason = why }
		end
		invites[target] = { from = player, at = os.clock() }
		NetService:FireClient("TradeInvite", target, { UserId = player.UserId, Name = player.DisplayName })
		return { ok = true }
	elseif action == "Accept" or action == "Decline" then
		local invite = invites[player]
		invites[player] = nil
		if
			invite == nil
			or invite.from.UserId ~= args.UserId
			or os.clock() - invite.at > TradeRules.INVITE_SECONDS
		then
			return { ok = false, reason = "expired" }
		end
		local from = invite.from
		if action == "Decline" then
			notify(from, "Info", "trade.declined", { name = player.DisplayName })
			return { ok = true }
		end
		if session or sessions[from] or from.Parent ~= Players then
			return { ok = false, reason = "busy" }
		end
		local why = blocker(from, player)
		if why then
			return { ok = false, reason = why }
		end
		local new: Session = {
			id = HttpService:GenerateGUID(false),
			players = { from, player },
			offers = { [from] = TradeRules.emptyOffer(), [player] = TradeRules.emptyOffer() },
			ack = {},
			locked = {},
			confirmed = {},
			countdownEnds = nil,
			token = 0,
		}
		sessions[from] = new
		sessions[player] = new
		push(new)
		return { ok = true }
	end

	if session == nil then
		return { ok = false, reason = "noTrade" }
	end
	if action == "Cancel" then
		close(session, "cancelled")
		notify(other(session, player), "Info", "trade.cancelled", { name = player.DisplayName })
		return { ok = true }
	elseif action == "Ack" then
		session.ack[player] = true
		push(session)
		return { ok = true }
	elseif action == "Offer" then
		local offer = readOffer(args)
		local ok, reason = TradeRules.checkOffer(data, offer)
		if not ok then
			return { ok = false, reason = reason }
		end
		session.offers[player] = offer
		resetAgreement(session)
		push(session)
		return { ok = true }
	elseif action == "Lock" then
		if not session.ack[player] then
			return { ok = false, reason = "ack" }
		end
		session.locked[player] = true
		push(session)
		return { ok = true }
	elseif action == "Unlock" then
		resetAgreement(session)
		push(session)
		return { ok = true }
	elseif action == "Confirm" then
		local partner = other(session, player)
		if not (session.locked[player] and session.locked[partner]) then
			return { ok = false, reason = "notLocked" }
		end
		session.confirmed[player] = true
		if session.confirmed[partner] then
			startCountdown(session)
		else
			push(session)
		end
		return { ok = true }
	end
	return { ok = false, reason = "action" }
end

function TradeService:Init()
	NetService:Handle("Trade", onRequest)
end

function TradeService:Start()
	Players.PlayerRemoving:Connect(function(player)
		invites[player] = nil
		local session = sessions[player]
		if session then
			close(session, "left")
		end
	end)
	-- Walking away, leaving the safe zone or a fight ends a trade.
	task.spawn(function()
		while true do
			task.wait(1)
			local seen: { [Session]: boolean } = {}
			for _, session in sessions do
				if not seen[session] then
					seen[session] = true
					local why = blocker(session.players[1], session.players[2])
					if why then
						close(session, why)
					end
				end
			end
		end
	end)
end

return TradeService
