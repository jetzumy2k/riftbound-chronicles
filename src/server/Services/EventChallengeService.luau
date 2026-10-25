--!strict
--[[
	EventChallengeService (Layer 6) — the hunts and challenges (Phase 18
	stage 3, PLAN.md D-92; rules in Logic/EventChallenges).

	Follows EventService's running list. While an event runs:
	  Treasure / Hidden Chest Hunt  chests stand in the war zones (a
	                       ProximityPrompt each; the server checks the event
	                       is still running and the player is within reach);
	                       each player opens each chest once per run
	  Race Challenge /     credited PvP victories (PvPService.VictoryCredited)
	  Cross-Race Tournament  count per realm / per player
	  Angel / Devil Defense  five waves of Rift creatures come into that
	                       realm's training yard, a minute apart, at the
	                       defenders' level; each defeat counts for the
	                       realm's players who fought it
	  Cosmetic Parade      time spent in a capital; 5 minutes pays at once
	When a contest ends it pays everyone still online here (winners, the
	top 3, defenders). Every payment is a claim ("E:<event>:<start>:<what>")
	so nothing is paid twice. The live board (scores, clues, waves) is the
	ReplicatedStorage attribute RC_EventBoard (JSON, display only).
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local EventChallenges = require(Shared.Logic.EventChallenges)
local EventDefinitions = require(Shared.Definitions.EventDefinitions)
local EventRules = require(Shared.Logic.EventRules)
local QuestDefinitions = require(Shared.Definitions.QuestDefinitions)
local ItemDefinitions = require(Shared.Definitions.ItemDefinitions)
local WarZoneTerrain = require(Shared.Logic.WarZoneTerrain)
local WorldLayout = require(Shared.Definitions.WorldLayout)
local Log = require(Shared.Util.Log)

local AuditLogService = require(script.Parent.AuditLogService)
local NetService = require(script.Parent.NetService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local EventService = require(script.Parent.EventService)
local InventoryService = require(script.Parent.InventoryService)
local MobService = require(script.Parent.MobService)
local PvPService = require(script.Parent.PvPService)
local MallService = require(script.Parent.MallService)
local WorldEventService = require(script.Parent.WorldEventService)
local EventRewards = require(Shared.Logic.EventRewards)

local log = Log.new("EventChallengeService")

local EventChallengeService = {}

local BOARD = "RC_EventBoard"
local PARADE_TICK = 10

type Run = {
	id: string,
	startsAt: number,
	-- The event window (its admin rewards, D-93 stage 2).
	window: EventRules.Window,
	-- Hunts.
	chests: { Instance },
	-- Contests: score per realm / per player, and when each last scored.
	realm: { [string]: number },
	players: { [Player]: number },
	order: { [Player]: number },
	-- Defense: creatures alive, wave reached.
	mobs: { [MobService.Mob]: boolean },
	wave: number,
	race: string?,
	-- Parade: seconds per player.
	seconds: { [Player]: number },
}

local runs: { [string]: Run } = {}
local folder: Folder? = nil

local function chestFolder(): Folder
	if folder == nil or folder.Parent == nil then
		local f = Instance.new("Folder")
		f.Name = "RC_EventChests"
		f.Parent = Workspace
		folder = f
	end
	return folder :: Folder
end

local function notify(player: Player, kind: string, key: string, params: { [string]: string }?)
	NetService:FireClient("Notify", player, { kind = kind, textKey = key, params = params })
end

-- Pays `rewardKey` (EventChallenges.REWARDS) once per run.
local function pay(player: Player, run: Run, what: string, rewardKey: string)
	local reward = EventChallenges.REWARDS[rewardKey]
	local source = `Event:{run.id}`
	local granted = false
	local status = (PlayerDataService :: any):ClaimReward(
		player,
		EventChallenges.claimId(run.id, run.startsAt, what),
		function(data: any)
			data.Wallet.Gold += reward.gold
			if reward.stones > 0 then
				InventoryService:GrantStackable(player, "EnhancementStone", reward.stones, source)
			end
			if reward.title then
				data.Titles[reward.title] = true
			end
			granted = true
		end
	)
	if status ~= "granted" or not granted then
		return
	end
	AuditLogService:Audit({
		actorUserId = player.UserId,
		action = "EventReward",
		target = run.id,
		details = { what = what, gold = reward.gold, stones = reward.stones, title = reward.title },
	})
	notify(player, "Info", "event.reward", { gold = tostring(reward.gold), stones = tostring(reward.stones) })
	if reward.title then
		notify(
			player,
			"Info",
			"quest.title",
			{ title = QuestDefinitions.Titles[reward.title] or reward.title }
		)
	end
	PlayerDataService:PushSnapshot(player)
end

-- Grants a title once (claim per run) without gold.
local function grantTitle(player: Player, run: Run, title: string)
	local status = (PlayerDataService :: any):ClaimReward(
		player,
		EventChallenges.claimId(run.id, run.startsAt, title),
		function(data: any)
			data.Titles[title] = true
		end
	)
	if status == "granted" then
		AuditLogService:Audit({ actorUserId = player.UserId, action = "TitleGranted", target = title })
		notify(player, "Info", "quest.title", { title = QuestDefinitions.Titles[title] or title })
		PlayerDataService:PushSnapshot(player)
	end
end

--------------------------------------------------------------------------------
-- Admin rewards for an event run (D-93 stage 2): to whoever did the event's
-- thing (EventDefinitions rewardTo), once per run
--------------------------------------------------------------------------------

-- Gives the run's admin rewards to `player` once (false while there's no
-- room in the bag; the next qualifying moment tries again).
local function payPrize(player: Player, window: EventRules.Window): boolean
	local data = PlayerDataService:GetData(player)
	if data == nil or data.Job == nil then
		return false
	end
	local rewards: { any } = window.Rewards or {}
	if #rewards == 0 then
		return true
	end
	local claim = EventChallenges.claimId(window.Id, window.StartsAt, "prize")
	if data.ClaimedRewardIds[claim] ~= nil then
		return true
	end
	-- Room first, so a claim is never spent on rewards that can't fit.
	if
		InventoryService:FreeSlots(player) < EventRewards.slotsNeeded(rewards, MallService:SetSize(player))
	then
		notify(player, "Warning", "event.prizeRoom")
		return false
	end
	for _, entry in rewards do
		if entry.Kind == "Item" then
			local def = ItemDefinitions.stackable(entry.Id)
			if def == nil or (data.Stackables[entry.Id] or 0) + entry.Count > def.maxStack then
				notify(player, "Warning", "event.prizeRoom")
				return false
			end
		end
	end
	local source = `Event:{window.Id}`
	local status = (PlayerDataService :: any):ClaimReward(player, claim, function(d: any)
		for _, entry in rewards do
			if entry.Kind == "MallPoints" then
				d.Wallet.MallPoints = (d.Wallet.MallPoints or 0) + entry.Count
			elseif entry.Kind == "Item" then
				InventoryService:GrantStackable(player, entry.Id, entry.Count, source)
			elseif entry.Kind == "Set" then
				MallService:GrantSet(player, entry.Id, source)
			end
		end
	end)
	if status == "granted" then
		AuditLogService:Audit({
			actorUserId = player.UserId,
			action = "EventReward",
			target = window.Id,
			details = { what = "prize", rewards = rewards },
		})
		notify(player, "Info", "event.prize", { rewards = EventRewards.describe(rewards) })
		PlayerDataService:PushSnapshot(player)
	end
	return true
end

--------------------------------------------------------------------------------
-- The live board
--------------------------------------------------------------------------------

local function publish()
	local board: { [string]: any } = {}
	for id, run in runs do
		if id == "TreasureHunt" then
			local clues = {}
			for _, chest in EventChallenges.chests(id) do
				table.insert(clues, chest.clue)
			end
			board[id] = { clues = clues }
		elseif id == "HiddenChestHunt" then
			board[id] = { total = #run.chests }
		elseif id == "RaceChallenge" then
			board[id] = { Angel = run.realm.Angel or 0, Devil = run.realm.Devil or 0 }
		elseif id == "CrossRaceTournament" then
			local top = {}
			for index, player in EventChallenges.rank(run.players, run.order) do
				if index > 5 then
					break
				end
				table.insert(top, { name = player.DisplayName, score = run.players[player] })
			end
			board[id] = { top = top }
		elseif id == "AngelDefense" or id == "DevilDefense" then
			local kills = 0
			for _, n in run.players do
				kills += n
			end
			board[id] = { wave = run.wave, waves = EventChallenges.WAVES, kills = kills }
		elseif id == "CosmeticParade" then
			board[id] = { seconds = EventChallenges.PARADE_SECONDS }
		end
	end
	ReplicatedStorage:SetAttribute(BOARD, HttpService:JSONEncode(board))
end

--------------------------------------------------------------------------------
-- Hunts
--------------------------------------------------------------------------------

-- How many chests of this run the player has opened (their claims).
local function foundBy(player: Player, run: Run): number
	local data = PlayerDataService:GetData(player)
	if data == nil then
		return 0
	end
	local prefix = EventChallenges.claimId(run.id, run.startsAt, "chest")
	local count = 0
	for claimId in data.ClaimedRewardIds do
		if string.sub(claimId, 1, #prefix) == prefix then
			count += 1
		end
	end
	return count
end

local function makeChest(run: Run, index: number, spec: EventChallenges.Chest): Model?
	local zone = (WorldLayout.WarZones :: any)[spec.zone] :: WorldLayout.WarZone?
	if zone == nil then
		return nil
	end
	local c = zone.center
	local x, z = c[1] + spec.x, c[3] + spec.z
	local ground = WarZoneTerrain.groundY(zone, x, z)
	local s = if spec.treasure then 1.4 else 1
	local model = Instance.new("Model")
	model.Name = if spec.treasure then "TreasureChest" else "HiddenChest"
	local function part(size: Vector3, offset: Vector3, color: Color3, material: Enum.Material): Part
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Size = size * s
		p.CFrame = CFrame.new(x, ground, z) * CFrame.new(offset * s)
		p.Color = color
		p.Material = material
		p.Parent = model
		return p
	end
	local body =
		part(Vector3.new(3, 1.8, 2), Vector3.new(0, 0.9, 0), Color3.fromRGB(110, 70, 38), Enum.Material.Wood)
	part(Vector3.new(3.1, 0.8, 2.1), Vector3.new(0, 2.2, 0), Color3.fromRGB(124, 80, 44), Enum.Material.Wood)
	part(
		Vector3.new(3.2, 0.3, 0.3),
		Vector3.new(0, 1.8, -1.06),
		Color3.fromRGB(220, 180, 80),
		Enum.Material.Metal
	)
	if spec.treasure then
		-- A glow so treasure reads from a distance.
		part(
			Vector3.new(2.6, 0.2, 1.6),
			Vector3.new(0, 2.7, 0),
			Color3.fromRGB(255, 220, 110),
			Enum.Material.Neon
		)
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Open"
	prompt.ObjectText = if spec.treasure then "Treasure Chest" else "Hidden Chest"
	prompt.MaxActivationDistance = EventChallenges.OPEN_REACH - 2
	prompt.HoldDuration = 0.6
	prompt.RequiresLineOfSight = false
	prompt.Parent = body
	prompt.Triggered:Connect(function(player: Player)
		if runs[run.id] ~= run then
			return
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if
			root == nil
			or not root:IsA("BasePart")
			or (root.Position - body.Position).Magnitude > EventChallenges.OPEN_REACH
		then
			return
		end
		local data = PlayerDataService:GetData(player)
		if data == nil or data.Job == nil then
			return
		end
		local claim = EventChallenges.claimId(run.id, run.startsAt, `chest{index}`)
		if data.ClaimedRewardIds[claim] ~= nil then
			notify(player, "Info", "event.chestOpened")
			return
		end
		pay(player, run, `chest{index}`, if spec.treasure then "TreasureChest" else "HiddenChest")
		payPrize(player, run.window)
		local found = foundBy(player, run)
		local total = #run.chests
		notify(player, "Info", "event.chestFound", { found = tostring(found), total = tostring(total) })
		if spec.treasure and found >= total then
			grantTitle(player, run, EventChallenges.TREASURE_TITLE)
		elseif not spec.treasure and found >= EventChallenges.HIDDEN_TITLE_COUNT then
			grantTitle(player, run, EventChallenges.HIDDEN_TITLE)
		end
	end)
	model.Parent = chestFolder()
	return model
end

--------------------------------------------------------------------------------
-- Defense
--------------------------------------------------------------------------------

local function defenseWave(run: Run)
	local race = run.race :: string
	local levels = {}
	for _, player in Players:GetPlayers() do
		local data = PlayerDataService:GetData(player)
		if data and data.Race == race then
			table.insert(levels, data.Level)
		end
	end
	run.wave += 1
	local level = EventChallenges.waveLevel(levels)
	local enemy = EventChallenges.WAVE_CREATURES[run.wave] or "RiftWolf"
	for _, point in EventChallenges.wavePoints(race, EventChallenges.WAVE_SIZE) do
		local mob = MobService:Spawn(
			enemy,
			CFrame.new(point[1], point[2], point[3]),
			{ owner = `Defense:{race}`, level = level }
		)
		if mob then
			run.mobs[mob] = true
		end
	end
	for _, player in Players:GetPlayers() do
		local data = PlayerDataService:GetData(player)
		if data and data.Race == race then
			notify(
				player,
				"Warning",
				"event.wave",
				{ wave = tostring(run.wave), waves = tostring(EventChallenges.WAVES) }
			)
		end
	end
	publish()
end

--------------------------------------------------------------------------------
-- Runs
--------------------------------------------------------------------------------

local function start(window: EventRules.Window)
	local id = window.Id
	local run: Run = {
		id = id,
		startsAt = window.StartsAt,
		window = window,
		chests = {},
		realm = {},
		players = {},
		order = {},
		mobs = {},
		wave = 0,
		race = nil,
		seconds = {},
	}
	runs[id] = run
	for index, spec in EventChallenges.chests(id) do
		local chest = makeChest(run, index, spec)
		if chest then
			table.insert(run.chests, chest)
		end
	end
	if id == "AngelDefense" or id == "DevilDefense" then
		local e = EventDefinitions.get(id) :: EventDefinitions.Event
		run.race = e.eligible and e.eligible.race
		task.spawn(function()
			while runs[id] == run and run.wave < EventChallenges.WAVES do
				defenseWave(run)
				task.wait(EventChallenges.WAVE_SECONDS)
			end
		end)
	elseif id == "CosmeticParade" then
		task.spawn(function()
			while runs[id] == run do
				task.wait(PARADE_TICK)
				for _, player in Players:GetPlayers() do
					if EventService:ZoneOf(player) == "Capitals" then
						local seconds = (run.seconds[player] or 0) + PARADE_TICK
						run.seconds[player] = seconds
						if seconds >= EventChallenges.PARADE_SECONDS then
							pay(player, run, "parade", "Parade")
							payPrize(player, run.window)
						end
					end
				end
			end
		end)
	end
	log:Info("%s started (%d chests)", id, #run.chests)
	publish()
end

local function finish(id: string)
	local run = runs[id]
	runs[id] = nil
	if run == nil then
		return
	end
	for _, chest in run.chests do
		chest:Destroy()
	end
	for mob in run.mobs do
		if not mob.dead then
			MobService:Despawn(mob)
		end
	end
	if id == "RaceChallenge" then
		local winner = EventChallenges.raceWinner(run.realm)
		for player in run.players do
			if player.Parent == Players then
				local data = PlayerDataService:GetData(player)
				local won = data ~= nil and data.Race == winner
				pay(player, run, "result", if won then "RaceWinner" else "RaceTaking")
				if won then
					payPrize(player, run.window)
				end
			end
		end
	elseif id == "CrossRaceTournament" then
		for place, player in EventChallenges.rank(run.players, run.order) do
			if place > 3 then
				break
			end
			if player.Parent == Players then
				pay(player, run, "place", `Tournament{place}`)
				if place == 1 then
					payPrize(player, run.window)
				end
			end
		end
	elseif id == "AngelDefense" or id == "DevilDefense" then
		for player, kills in run.players do
			if player.Parent == Players and kills > 0 then
				pay(player, run, "defender", "Defender")
				payPrize(player, run.window)
				if kills >= EventChallenges.DEFENDER_TITLE_KILLS then
					grantTitle(player, run, EventChallenges.DEFENDER_TITLE)
				end
			end
		end
	end
	log:Info("%s ended", id)
	publish()
end

local function sync(running: { EventRules.Window })
	local live: { [string]: boolean } = {}
	for _, w in running do
		live[w.Id] = true
		local e = EventDefinitions.get(w.Id)
		local run: Run? = runs[w.Id]
		if run and run.startsAt ~= w.StartsAt then
			-- A new run of the same event: the old one is over.
			finish(w.Id)
			run = nil
		end
		if run == nil and e and (e.kind == "Hunt" or e.kind == "Challenge") then
			start(w)
		end
	end
	for id in runs do
		if not live[id] then
			finish(id)
		end
	end
end

function EventChallengeService:Start()
	ReplicatedStorage:SetAttribute(BOARD, "{}")
	PvPService.VictoryCredited:Connect(function(attacker: Player)
		local data = PlayerDataService:GetData(attacker)
		local race = data and data.Race
		for _, id in { "RaceChallenge", "CrossRaceTournament" } do
			local run = runs[id]
			if run and race then
				run.realm[race] = (run.realm[race] or 0) + 1
				run.players[attacker] = (run.players[attacker] or 0) + 1
				run.order[attacker] = os.clock()
			end
		end
		publish()
	end)
	MobService.MobDefeated:Connect(function(mob, contributors: { [Player]: number }?)
		-- World events (D-93 stage 2): everyone who helped defeat one of the
		-- event's creatures or bosses gets the run's admin rewards.
		local eventId = WorldEventService:EventOf(mob)
		if eventId then
			for _, w in EventService:GetRunning() do
				if w.Id == eventId then
					local helped: { [Player]: number } = contributors or {}
					for player in helped do
						if player.Parent == Players then
							payPrize(player, w)
						end
					end
				end
			end
		end
		for _, run in runs do
			if run.mobs[mob] then
				run.mobs[mob] = nil
				local fought: { [Player]: number } = contributors or {}
				for player in fought do
					local data = PlayerDataService:GetData(player)
					if data and data.Race == run.race then
						run.players[player] = (run.players[player] or 0) + 1
					end
				end
				publish()
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		for _, run in runs do
			run.seconds[player] = nil
		end
	end)
	EventService.Changed:Connect(sync)
	sync(EventService:GetRunning())
end

return EventChallengeService
