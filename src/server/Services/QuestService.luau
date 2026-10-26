--!strict
--[[
	QuestService (Layer 6) — story quests (CLAUDE.md §16-17, PLAN.md Phase
	11, D-73; SECURITY_MODEL T-12, T-13, T-14).

	  - Definitions: Definitions/QuestDefinitions; rules: Logic/QuestRules.
	  - Progress only from server events, never from a remote (T-13):
	      Kill            MobService.MobDefeated (everyone who earned the
	                      EXP or damaged it)
	      EnterZone       war zone (PvPService's "WarZone" attribute) or
	                      dungeon floor (DungeonService:FloorOf), polled
	      Visit           server-observed position near the place, polled
	      Interact        a quest object's ProximityPrompt, re-checked for
	                      reach on the server (T-14), once per target
	      ReturnSafely    PvPService.ReturnedHome (the camp's Return portal)
	      ParticipatePvP  CombatService.PlayerHit between realms in a war zone
	  - A quest giver stands in each capital (QuestDefinitions.Givers). Its
	    prompt sends the dialogue (QuestDialogue); QuestAccept / QuestTurnIn
	    need the player within reach of their own realm's giver, plus the
	    prerequisites, level and status checks of QuestRules.
	  - Rewards are claimed once per profile as "Q:<id>" (RewardClaims,
	    T-12): EXP, items (rolled for the player's class and level through
	    InventoryService:GrantItem), stackables, PvP Marks, titles,
	    cosmetics, story flags. Completion and grants happen in one
	    synchronous block.
	  - Quest 1 is accepted automatically once a character has a job (the
	    onboarding path, GM-2); the tracker then always shows the next step.
	  - Titles: `EquipTitle(id?)` wears an owned title, published as the
	    "Title" player attribute (display only).
	  - Analytics: onboarding funnel steps for Quest 1, a funnel step per
	    quest completed (Roblox AnalyticsService, failures ignored).
]]

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local QuestDefinitions = require(Shared.Definitions.QuestDefinitions)
local ItemDefinitions = require(Shared.Definitions.ItemDefinitions)
local WorldLayout = require(Shared.Definitions.WorldLayout)
local QuestRules = require(Shared.Logic.QuestRules)
local GearLook = require(Shared.Logic.GearLook)
local Log = require(Shared.Util.Log)

local AuditLogService = require(script.Parent.AuditLogService)
local ConfigurationService = require(script.Parent.ConfigurationService)
local NetService = require(script.Parent.NetService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local LevelService = require(script.Parent.LevelService)
local JobService = require(script.Parent.JobService)
local CombatService = require(script.Parent.CombatService)
local SkillService = require(script.Parent.SkillService)
local InventoryService = require(script.Parent.InventoryService)
local MobService = require(script.Parent.MobService)
local DungeonService = require(script.Parent.DungeonService)
local PvPService = require(script.Parent.PvPService)
local ProfileView = require(script.Parent.Parent.Persistence.ProfileView)
local BodyStyle = require(script.Parent.Parent.Appearance.BodyStyle)
local Wardrobe = require(script.Parent.Parent.Appearance.Wardrobe)
local CharacterFactory = require(script.Parent.Parent.Appearance.Anime.CharacterFactory)

local AnimeArchetypes = require(Shared.Definitions.AnimeArchetypes)
local FacePresets = require(Shared.Definitions.FacePresets)

local log = Log.new("QuestService")

-- Extra studs allowed over the prompt range for lag (T-14).
local REACH_TOLERANCE = 4
-- How long to wait for the dungeon copies before placing their objects.
local DUNGEON_WAIT_SECONDS = 60
-- The commanders' look (creator review 2026-10-24: grey plastic skin, no
-- hair, a helm hiding the face and a stiff pose looked ugly, D-74): the
-- adult head of D-72, warm skin, Roblox's free hair from the base-body
-- bundles (Addison's / Harper's, checked 2026-10-22), no helm, and the
-- standard R15 idle (a Roblox animation free to use).
local GIVER_STYLE: { [string]: { head: string, skin: Color3, hair: number } } = {
	Angel = { head = "Woman", skin = Color3.fromRGB(241, 199, 168), hair = 6993754725 },
	Devil = { head = "Man", skin = Color3.fromRGB(176, 116, 86), hair = 9244021842 },
}
local GIVER_IDLE = "rbxassetid://507766666"

local QuestService = {}

local random = Random.new()
-- Quest objects in the world: prompt part -> interactable id, and per-realm
-- position (dungeon copies are per realm; war-zone objects are shared).
local objectAt: { [string]: { [string]: Vector3 } } = {}
local giverModels: { [string]: Model } = {}

local function config(): any
	return ConfigurationService:Get("Quests")
end

local function notify(player: Player, kind: string, key: string, params: { [string]: string }?)
	NetService:FireClient("Notify", player, { kind = kind, textKey = key, params = params })
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function push(player: Player)
	local data = PlayerDataService:GetData(player)
	if data then
		NetService:FireClient("QuestUpdate", player, ProfileView.quests(data))
	end
end

local function analytics(fn: () -> ())
	local ok, err = pcall(fn :: any)
	if not ok then
		log:Debug("analytics: %s", tostring(err))
	end
end

local function onboardingStep(player: Player, step: number, name: string)
	analytics(function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, step, name)
	end)
end

local function publishTitle(player: Player, data: { [string]: any })
	local title = data.EquippedTitle
	player:SetAttribute("Title", if type(title) == "string" then QuestDefinitions.Titles[title] else nil)
end

--------------------------------------------------------------------------------
-- Places
--------------------------------------------------------------------------------

local function groundAt(x: number, z: number, fromY: number): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {}
	params.IgnoreWater = false
	local hit = Workspace:Raycast(Vector3.new(x, fromY + 400, z), Vector3.new(0, -900, 0), params)
	return if hit then hit.Position.Y else fromY
end

-- World position of `place` for a player of `race` (nil if not built yet).
local function placePosition(place: QuestDefinitions.Place, race: string): Vector3?
	local realm = WorldLayout.Realms[race]
	if place.kind == "city" and realm and place.at then
		local p = WorldLayout.toWorld(realm, place.at)
		return Vector3.new(p[1], p[2], p[3])
	elseif place.kind == "gate" and realm and place.gate then
		local p = WorldLayout.gateFront(realm, place.gate, place.distance or 8)
		return if p then Vector3.new(p[1], p[2], p[3]) else nil
	elseif place.kind == "yard" and realm then
		local center = WorldLayout.trainingYard(realm)
		return Vector3.new(center[1], center[2], center[3])
	elseif place.kind == "dungeon" and place.floor and place.room then
		local cf = DungeonService:RoomCFrame(race, place.floor, place.room, place.x or 0, place.z or 0)
		return if cf then cf.Position else nil
	elseif place.kind == "warZone" and place.zone then
		local zone = WorldLayout.WarZones[place.zone]
		if zone == nil then
			return nil
		end
		local x, z = zone.center[1] + (place.x or 0), zone.center[3] + (place.z or 0)
		return Vector3.new(x, groundAt(x, z, zone.center[2]), z)
	end
	return nil
end

local function inYard(position: Vector3, race: string): boolean
	local realm = WorldLayout.Realms[race]
	if realm == nil then
		return false
	end
	local center, size = WorldLayout.trainingYard(realm)
	return math.abs(position.X - center[1]) <= size[1] / 2
		and math.abs(position.Z - center[3]) <= size[3] / 2
		and math.abs(position.Y - center[2]) <= 30
end

-- The zones a player is in: "Dungeon", "DungeonFloor<N>", a war zone id.
local function zonesOf(player: Player): { [string]: boolean }
	local zones = {}
	local war = player:GetAttribute("WarZone")
	if type(war) == "string" then
		zones[war] = true
	end
	local floor = DungeonService:FloorOf(player)
	if floor then
		zones.Dungeon = true
		zones[`DungeonFloor{floor}`] = true
	end
	return zones
end

--------------------------------------------------------------------------------
-- Progress
--------------------------------------------------------------------------------

--[[
	Applies a world event to every active quest of `player`. Synchronous;
	no yields. Returns true if anything changed.
]]
local function advance(player: Player, event: QuestRules.Event): boolean
	local data = PlayerDataService:GetData(player)
	if data == nil or not config().Enabled then
		return false
	end
	local changed = false
	for _, quest in QuestDefinitions.List do
		local progress = data.QuestState[quest.id]
		if progress and progress.Status == "Active" and QuestRules.advance(quest, progress, event) then
			changed = true
			local status: string = progress.Status
			if status == "ReadyToTurnIn" then
				notify(player, "Info", "quest.ready", { name = quest.name })
			end
			if quest.id == "FirstSpark" then
				local objective = QuestRules.current(quest, progress)
				if objective == nil then
					onboardingStep(player, 4, "Rift Sprites defeated")
				elseif objective.id == "sprites" and (progress.Objectives.sprites or 0) == 0 then
					onboardingStep(player, 3, "Reached the Training Grounds")
				end
			end
		end
	end
	if changed then
		push(player)
	end
	return changed
end

local function accept(player: Player, questId: string, auto: boolean): boolean
	local data = PlayerDataService:GetData(player)
	local quest = QuestDefinitions.get(questId)
	if data == nil or quest == nil or not config().Enabled then
		return false
	end
	local ok = QuestRules.canAccept(data.QuestState, questId, data.Level)
	if not ok then
		return false
	end
	data.QuestState[questId] = QuestRules.newProgress(quest, os.time())
	log:Info("user=%d accepted %s%s", player.UserId, questId, if auto then " (auto)" else "")
	notify(player, "Info", "quest.accepted", { name = quest.name })
	push(player)
	if questId == "FirstSpark" then
		onboardingStep(player, 2, "First quest accepted")
	end
	return true
end

-- Quests offered on their own (Quest 1) once a character has a job.
local function autoAccept(player: Player)
	local data = PlayerDataService:GetData(player)
	if data == nil or data.Job == nil then
		return
	end
	for _, quest in QuestDefinitions.List do
		if quest.autoAccept and data.QuestState[quest.id] == nil then
			accept(player, quest.id, true)
		end
	end
end

--------------------------------------------------------------------------------
-- Rewards
--------------------------------------------------------------------------------

local function pickDef(
	player: Player,
	data: { [string]: any },
	kind: string,
	itemLevel: number
): ItemDefinitions.ItemDef?
	local job = data.Job
	local slot = kind
	if kind == "gear" then
		slot = if random:NextNumber() < 0.5 then "weapon" else "armor"
	end
	if slot == "weapon" then
		local usable = {}
		for _, family in ItemDefinitions.familiesOf(job) do
			if JobService:CanUseWeapon(player, family) then
				table.insert(usable, family)
			end
		end
		if #usable == 0 then
			return nil
		end
		return ItemDefinitions.defFor(job, "Weapon", usable[random:NextInteger(1, #usable)], itemLevel)
	elseif slot == "armor" then
		local slots = ItemDefinitions.ARMOR_SLOTS
		return ItemDefinitions.defFor(job, slots[random:NextInteger(1, #slots)], nil, itemLevel)
	elseif slot == "necklace" then
		return ItemDefinitions.defFor(job, "Necklace", nil, itemLevel)
	elseif slot == "earrings" then
		return ItemDefinitions.defFor(job, "Earrings", nil, itemLevel)
	end
	return nil
end

-- Everything a quest gives, inside the "Q:<id>" claim (no yields).
local function grant(player: Player, data: { [string]: any }, quest: QuestDefinitions.Quest): { string }
	local given = {}
	local rewards = quest.rewards
	local source = `Quest:{quest.id}`
	local xp = QuestRules.xpFor(quest)
	if xp > 0 then
		LevelService:GrantXP(player, xp, source)
		table.insert(given, `{xp} EXP`)
	end
	local itemLevel = math.clamp(data.Level, 0, 30)
	for _, reward in (rewards.items or {}) :: { QuestDefinitions.ItemReward } do
		local rarity = QuestRules.rollRarity(reward.rarity, random:NextNumber())
		local def = pickDef(player, data, reward.kind, itemLevel)
		local item = def and InventoryService:GrantItem(player, def.id, rarity, itemLevel, source)
		if item and def then
			table.insert(given, `{rarity} {def.name}`)
			NetService:FireClient("Notify", player, {
				kind = "Info",
				textKey = "loot.drop",
				params = { name = def.name, rarity = rarity, level = tostring(itemLevel) },
			})
		else
			log:Warn("user=%d quest %s item %s not granted", player.UserId, quest.id, reward.kind)
		end
	end
	for id, count in (rewards.stackables or {}) :: { [string]: number } do
		local added = InventoryService:GrantStackable(player, id, count, source)
		table.insert(given, `{added} {id}`)
	end
	for currency, amount in (rewards.wallet or {}) :: { [string]: number } do
		if type(data.Wallet[currency]) == "number" then
			data.Wallet[currency] += amount
			table.insert(given, `{amount} {currency}`)
		end
	end
	for _, title in (rewards.titles or {}) :: { string } do
		data.Titles[title] = true
		table.insert(given, `title {title}`)
		notify(player, "Info", "quest.title", { title = QuestDefinitions.Titles[title] })
	end
	for _, cosmetic in (rewards.cosmetics or {}) :: { string } do
		data.Cosmetics[cosmetic] = true
		table.insert(given, `cosmetic {cosmetic}`)
	end
	for _, flag in (rewards.flags or {}) :: { string } do
		data.StoryFlags[flag] = true
		table.insert(given, `flag {flag}`)
	end
	return given
end

local function turnIn(player: Player, questId: string)
	local data = PlayerDataService:GetData(player)
	local quest = QuestDefinitions.get(questId)
	if data == nil or quest == nil then
		return
	end
	local progress = data.QuestState[questId]
	if progress == nil or progress.Status ~= "ReadyToTurnIn" then
		return
	end
	local given: { string } = {}
	local status = (PlayerDataService :: any):ClaimReward(player, `Q:{questId}`, function()
		progress.Status = "Completed"
		progress.CompletedAt = os.time()
		given = grant(player, data, quest)
	end)
	if status == "already" then
		-- Rewarded before (e.g. a state repaired from an older save): just close it.
		progress.Status = "Completed"
		progress.CompletedAt = progress.CompletedAt or os.time()
	elseif status ~= "granted" then
		return
	end
	AuditLogService:Audit({
		actorUserId = player.UserId,
		action = "QuestComplete",
		target = questId,
		details = { status = status, rewards = table.concat(given, ", ") },
	})
	log:Info("user=%d completed %s (%s)", player.UserId, questId, status)
	notify(player, "Welcome", "quest.complete", { name = quest.name })
	if quest.rewards.flags and table.find(quest.rewards.flags, "RiftToken") then
		SkillService:RefreshBonus(player)
		notify(player, "Info", "quest.token")
	end
	push(player)
	InventoryService:Push(player)
	if questId == "FirstSpark" then
		onboardingStep(player, 5, "First quest completed")
	end
	analytics(function()
		AnalyticsService:LogFunnelStepEvent(player, "StoryQuests", nil, quest.order, quest.name)
	end)
end

--------------------------------------------------------------------------------
-- Quest givers and dialogue
--------------------------------------------------------------------------------

local function nearGiver(player: Player, race: string): boolean
	local model = giverModels[race]
	local root = rootOf(player)
	local giverRoot = model and model:FindFirstChild("HumanoidRootPart")
	if root == nil or giverRoot == nil or not giverRoot:IsA("BasePart") then
		return false
	end
	return (root.Position - giverRoot.Position).Magnitude <= QuestDefinitions.GIVER_REACH + REACH_TOLERANCE
end

local function sendDialogue(player: Player)
	local data = PlayerDataService:GetData(player)
	local giver = data and QuestDefinitions.Givers[data.Race]
	if data == nil or giver == nil then
		return
	end
	local function fill(text: string): string
		return QuestDefinitions.fill(text, data.Race, player.DisplayName)
	end
	local entries = {}
	for _, quest in QuestDefinitions.List do
		local progress = data.QuestState[quest.id]
		if progress and progress.Status == "ReadyToTurnIn" then
			table.insert(entries, { Quest = quest.id, Mode = "TurnIn", Text = fill(quest.dialogue.complete) })
		elseif progress and progress.Status == "Active" then
			table.insert(
				entries,
				{ Quest = quest.id, Mode = "Progress", Text = fill(quest.dialogue.progress) }
			)
		end
	end
	local offers, later = QuestRules.offers(data.QuestState, data.Level)
	for _, quest in offers do
		table.insert(entries, { Quest = quest.id, Mode = "Offer", Text = fill(quest.dialogue.offer) })
	end
	if later and #offers == 0 then
		table.insert(entries, {
			Quest = later.id,
			Mode = "Later",
			Text = `Grow stronger, {player.DisplayName}. Come back at level {later.level} for "{later.name}".`,
		})
	end
	local idle = nil
	if #entries == 0 then
		idle = if QuestRules.isCompleted(data.QuestState, "TheNullbornGate")
			then fill("The gate is sealed, Nullbane. The depths remain for those who would guard them.")
			else fill("The Rift is quiet for now, {player}. Train, and return when you are ready.")
	end
	NetService:FireClient("QuestDialogue", player, {
		Giver = giver.name,
		Title = giver.title,
		Entries = entries,
		Idle = idle,
	})
end

-- A commander in a full tier-3 Legendary set of plate (display only).
local GIVER_LOOK: GearLook.Look = {}
for _, slot in { "Shoulders", "Chest", "Hands", "Legs", "Boots" } do
	GIVER_LOOK[slot] = { tier = 3, rarity = "Legendary", kind = slot, enhancement = 0 }
end
GIVER_LOOK.Weapon = { tier = 3, rarity = "Legendary", family = "Sword", kind = "Weapon", enhancement = 7 }
GIVER_LOOK.OffHand = { tier = 3, rarity = "Legendary", kind = "Shield", enhancement = 0 }

local function buildGiver(race: string, giver: QuestDefinitions.Giver)
	local realm = WorldLayout.Realms[race]
	if realm == nil then
		return
	end
	local style = GIVER_STYLE[race]
	-- D-100: a commander whose realm has an anime warrior wears that look
	-- (the Angel commander shows the Divine Angel Warrior).
	local anime = ConfigurationService:Get("Appearance.AnimeStyle") == true
		and AnimeArchetypes.forCharacter(race, "Warrior") ~= nil
	local description = Instance.new("HumanoidDescription")
	for _, part in { "Head", "Torso", "LeftArm", "RightArm", "LeftLeg", "RightLeg" } do
		(description :: any)[`{part}Color`] = style.skin
	end
	if anime then
		CharacterFactory.dress(description)
	else
		description.HairAccessory = tostring(style.hair)
		BodyStyle.dress(description, style.head)
	end
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescriptionAsync(description, Enum.HumanoidRigType.R15)
	end)
	if not ok or model == nil then
		log:Warn("quest giver %s not built: %s", race, tostring(model))
		return
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		if not anime then
			BodyStyle.athlete(humanoid)
		end
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		pcall(function()
			humanoid:BuildRigFromAttachments()
		end)
	end
	model.Name = giver.name
	local p = WorldLayout.toWorld(realm, giver.at)
	local spawn = realm.spawnPosition
	local at = Vector3.new(p[1], p[2] + 3.2, p[3])
	model:PivotTo(CFrame.lookAt(at, Vector3.new(spawn[1], at.Y, spawn[3])))
	model.Parent = Workspace
	-- Joints settle in the world; then hold still.
	task.wait(0.2)
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		root.Anchored = true
	end
	Wardrobe.dress(
		model,
		race,
		FacePresets.defaultFor(race),
		"Warrior",
		GIVER_LOOK,
		if anime then { variant = style.head } else nil
	)
	model:SetAttribute("RC_QuestGiver", race)
	if humanoid then
		local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
		animator.Parent = humanoid
		local animation = Instance.new("Animation")
		animation.AnimationId = GIVER_IDLE
		local played = pcall(function()
			local track = animator:LoadAnimation(animation)
			track.Looped = true
			track:Play()
		end)
		if not played then
			log:Warn("quest giver %s idle not played", race)
		end
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Talk"
	prompt.ObjectText = giver.name
	prompt.MaxActivationDistance = QuestDefinitions.GIVER_REACH - 4
	prompt.RequiresLineOfSight = false
	prompt.HoldDuration = 0
	prompt.Parent = root or model.PrimaryPart
	prompt.Triggered:Connect(function(player)
		local data = PlayerDataService:GetData(player)
		if data and data.Race == race and nearGiver(player, race) then
			sendDialogue(player)
		end
	end)
	giverModels[race] = model
end

--------------------------------------------------------------------------------
-- Quest objects (fragments, gates to inspect, clues)
--------------------------------------------------------------------------------

local function buildObject(interactable: QuestDefinitions.Interactable, race: string?, position: Vector3)
	local part = Instance.new("Part")
	part.Name = `Quest_{interactable.id}`
	part.Size = Vector3.new(1.6, 1.6, 1.6)
	part.CFrame = CFrame.new(position + Vector3.new(0, 2.4, 0)) * CFrame.Angles(math.rad(45), 0, math.rad(45))
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Material = Enum.Material.Neon
	part.Color = Color3.fromRGB(150, 210, 255)
	part:SetAttribute("RC_QuestTarget", interactable.id)
	local light = Instance.new("PointLight")
	light.Color = part.Color
	light.Range = 12
	light.Brightness = 1.5
	light.Parent = part
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = interactable.action
	prompt.ObjectText = interactable.label
	prompt.MaxActivationDistance = QuestDefinitions.INTERACT_REACH - 2
	prompt.RequiresLineOfSight = false
	prompt.HoldDuration = 0.6
	prompt.Parent = part
	prompt.Triggered:Connect(function(player)
		local data = PlayerDataService:GetData(player)
		local root = rootOf(player)
		if data == nil or root == nil or (race and data.Race ~= race) then
			return
		end
		-- T-14: reach from the server-observed position.
		if (root.Position - part.Position).Magnitude > QuestDefinitions.INTERACT_REACH + REACH_TOLERANCE then
			return
		end
		if advance(player, { type = "Interact", target = interactable.id }) then
			notify(player, "Info", "quest.found", { name = interactable.label })
		end
	end)
	part.Parent = Workspace
	local positions = objectAt[interactable.id] or {}
	objectAt[interactable.id] = positions
	positions[race or "*"] = part.Position
end

local function buildObjects()
	local pending: { { interactable: QuestDefinitions.Interactable, race: string } } = {}
	for _, interactable in QuestDefinitions.Interactables do
		if interactable.place.kind == "warZone" then
			local position = placePosition(interactable.place, "Angel")
			if position then
				buildObject(interactable, nil, position)
			end
		else
			for race: string in WorldLayout.Realms :: { [string]: any } do
				table.insert(pending, { interactable = interactable, race = race })
			end
		end
	end
	-- Dungeon copies are built at start-up; wait for them if needed.
	local deadline = os.clock() + DUNGEON_WAIT_SECONDS
	while #pending > 0 and os.clock() < deadline do
		for index = #pending, 1, -1 do
			local entry = pending[index]
			local position = placePosition(entry.interactable.place, entry.race)
			if position then
				buildObject(entry.interactable, entry.race, position)
				table.remove(pending, index)
			end
		end
		if #pending > 0 then
			task.wait(1)
		end
	end
	for _, entry in pending do
		log:Warn("quest object %s (%s) has no place", entry.interactable.id, entry.race)
	end
end

--------------------------------------------------------------------------------
-- Polling: Visit and EnterZone steps
--------------------------------------------------------------------------------

local function poll()
	for _, player in Players:GetPlayers() do
		local data = PlayerDataService:GetData(player)
		local root = rootOf(player)
		if data == nil or root == nil or data.Race == nil or CombatService:IsDefeated(player) then
			continue
		end
		local zones: { [string]: boolean }? = nil
		for _, quest in QuestDefinitions.List do
			local progress = data.QuestState[quest.id]
			local objective = progress and progress.Status == "Active" and QuestRules.current(quest, progress)
			if not objective then
				continue
			end
			if objective.type == "EnterZone" then
				zones = zones or zonesOf(player)
				local zone = objective.zone
				if zone and (zones :: { [string]: boolean })[zone] then
					advance(player, { type = "EnterZone", zone = zone })
				end
			elseif objective.type == "Visit" and objective.place then
				local place = objective.place
				local arrived = false
				if place.kind == "yard" then
					arrived = inYard(root.Position, data.Race)
				else
					local position = placePosition(place, data.Race)
					local flat = position
						and Vector3.new(position.X - root.Position.X, 0, position.Z - root.Position.Z)
					arrived = flat ~= nil
						and flat.Magnitude <= (objective.radius or 12)
						and math.abs((position :: Vector3).Y - root.Position.Y) <= 30
				end
				if arrived then
					advance(player, { type = "Visit", objective = objective.id })
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Remotes
--------------------------------------------------------------------------------

local function onAccept(player: Player, questId: string)
	local data = PlayerDataService:GetData(player)
	if data == nil or data.Race == nil then
		return
	end
	if not nearGiver(player, data.Race) then
		AuditLogService:Security(player, "QuestAcceptFar", questId)
		return
	end
	local ok, reason = QuestRules.canAccept(data.QuestState, questId, data.Level)
	if not ok then
		if reason == "level" then
			local quest = QuestDefinitions.get(questId)
			notify(player, "Warning", "quest.level", { level = tostring(quest and quest.level or 0) })
		end
		return
	end
	accept(player, questId, false)
	sendDialogue(player)
end

local function onTurnIn(player: Player, questId: string)
	local data = PlayerDataService:GetData(player)
	if data == nil or data.Race == nil then
		return
	end
	if not nearGiver(player, data.Race) then
		AuditLogService:Security(player, "QuestTurnInFar", questId)
		return
	end
	turnIn(player, questId)
	sendDialogue(player)
end

local function onEquipTitle(player: Player, titleId: string?)
	local data = PlayerDataService:GetData(player)
	if data == nil then
		return
	end
	if titleId ~= nil and data.Titles[titleId] ~= true then
		AuditLogService:Security(player, "TitleNotOwned", tostring(titleId))
		return
	end
	data.EquippedTitle = titleId
	publishTitle(player, data)
	push(player)
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function QuestService:Init()
	NetService:Handle("QuestAccept", onAccept)
	NetService:Handle("QuestTurnIn", onTurnIn)
	NetService:Handle("EquipTitle", onEquipTitle)

	PlayerDataService.ProfileLoaded:Connect(function(player, data)
		publishTitle(player, data)
		autoAccept(player)
	end)
	JobService.JobChosen:Connect(function(player)
		autoAccept(player)
	end)

	MobService.MobDefeated:Connect(function(mob, contributors, recipients)
		local credited: { [Player]: boolean } = {}
		for _, player in (recipients or {}) :: { Player } do
			credited[player] = true
		end
		if type(contributors) == "table" then
			for player in contributors do
				if typeof(player) == "Instance" and player:IsA("Player") then
					credited[player] = true
				end
			end
		end
		for player in credited do
			advance(player, { type = "Kill", enemy = mob.enemy.id, owner = mob.owner })
		end
	end)
	PvPService.ReturnedHome:Connect(function(player, zoneId)
		advance(player, { type = "ReturnSafely", zone = zoneId })
	end)
	CombatService.PlayerHit:Connect(function(attacker, victim)
		local zone = attacker:GetAttribute("WarZone")
		if zone == nil or zone ~= victim:GetAttribute("WarZone") then
			return
		end
		local a, v = PlayerDataService:GetData(attacker), PlayerDataService:GetData(victim)
		if a and v and a.Race ~= v.Race then
			advance(attacker, { type = "ParticipatePvP" })
			advance(victim, { type = "ParticipatePvP" })
		end
	end)
end

function QuestService:Start()
	for race, giver in QuestDefinitions.Givers do
		task.spawn(buildGiver, race, giver)
	end
	task.spawn(buildObjects)
	task.spawn(function()
		while true do
			task.wait(1 / config().PollHz)
			local ok, err = pcall(poll :: any)
			if not ok then
				log:Error("poll failed: %s", tostring(err))
			end
		end
	end)
	for _, player in Players:GetPlayers() do
		local data = PlayerDataService:GetData(player)
		if data then
			publishTitle(player, data)
			autoAccept(player)
		end
	end
	log:Info(
		"%d quests, %d quest objects",
		#QuestDefinitions.List,
		(function()
			local n = 0
			for _ in QuestDefinitions.Interactables do
				n += 1
			end
			return n
		end)()
	)
end

-- Where a quest object is for `race` (client markers use the parts; this is
-- for tests and tools).
--[[
	Admin (quests.manage, Phase 17): clears a quest's progress so a stuck
	player can start it again. Its reward claim stays, so a repeat hand-in
	never pays twice. Returns false when there was nothing to clear.
]]
function QuestService:AdminReset(player: Player, questId: string): boolean
	local data = PlayerDataService:GetData(player)
	if data == nil or data.QuestState[questId] == nil then
		return false
	end
	data.QuestState[questId] = nil
	push(player)
	return true
end

function QuestService:ObjectPosition(id: string, race: string): Vector3?
	local positions = objectAt[id]
	return positions and (positions[race] or positions["*"])
end

return QuestService
