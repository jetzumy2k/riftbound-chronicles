--!strict
--[[
	InventoryService (Layer 4)
	Items, equipment, stackables and the wallet (Phase 7, PLAN.md D-64;
	CLAUDE.md §8-9, D-09, D-14, D-25, DATA_MODEL.md §2.1 / §4).

	The item factory: `GrantItem` is the only way an item comes into being.
	It rolls the attributes on the server (ItemRules.roll), gives the item a
	server GUID and stores it in the owner's profile; items never move
	between profiles (no trading, D-14). Loot (Phase 10), quests (Phase 11)
	and admin tools (Phase 17) call it; no remote does.

	Player intents (all validated here, check -> mutate -> push in one
	synchronous block, DATA_MODEL.md §4.1):
	  EquipItem        own item, own job, race weapon family, level; out of combat
	  UnequipItem      out of combat
	  SalvageItems     not equipped, not locked -> Stone Fragments (D-09)
	  LockItem         protects an item from salvage
	  CombineFragments 10 fragments -> 1 Enhancement Stone
	  UseConsumable    a Healing Potion (alive, cooldown, not at full HP)
	  StudioTestGear   Studio only: random gear to try the screen

	Gear stats reach combat through StatsService:GetStats; after a change
	CombatService:RefreshStats re-reads them (health fraction kept).
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Enums = require(Shared.Enums)
local ItemDefinitions = require(Shared.Definitions.ItemDefinitions)
local ItemRules = require(Shared.Logic.ItemRules)
local Log = require(Shared.Util.Log)

local ProfileView = require(script.Parent.Parent.Persistence.ProfileView)

local AuditLogService = require(script.Parent.AuditLogService)
local NetService = require(script.Parent.NetService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local RaceService = require(script.Parent.RaceService)
local JobService = require(script.Parent.JobService)
local CombatService = require(script.Parent.CombatService)

type Item = ItemRules.Item

local SOURCE_PATTERN = "^[%w_:%-]+$"
-- "Why didn't that work?" toasts: at most this often per reason.
local NOTICE_SECONDS = 1.5

local log = Log.new("InventoryService")
local random = Random.new()

local InventoryService = {}

-- [player][consumable id] = os.clock() when it can be used again.
local readyAt: { [Player]: { [string]: number } } = {}
local lastNotice: { [Player]: { [string]: number } } = {}

local function notify(player: Player, kind: "Info" | "Warning", key: string, params: { [string]: string }?)
	local seen = lastNotice[player] or {}
	lastNotice[player] = seen
	local t = os.clock()
	if kind == "Warning" and t - (seen[key] or -math.huge) < NOTICE_SECONDS then
		return
	end
	seen[key] = t
	NetService:FireClient("Notify", player, { kind = kind, textKey = `inventory.{key}`, params = params })
end

local function countItems(data: { [string]: any }): number
	local count = 0
	for _ in data.Inventory do
		count += 1
	end
	return count
end

local function readyInFor(player: Player): { [string]: number }
	local out = {}
	local t = os.clock()
	local own: { [string]: number } = readyAt[player] or {}
	for id, at in own do
		if at > t then
			out[id] = math.min(at - t, 600)
		end
	end
	return out
end

-- Tells the owner what changed (InventoryUpdate).
local function push(player: Player, data: { [string]: any }, changed: { string }?, removed: { string }?)
	local changedView = {}
	local list: { string } = changed or {}
	for _, guid in list do
		local item = data.Inventory[guid]
		if item then
			changedView[guid] = ProfileView.item(item)
		end
	end
	NetService:FireClient("InventoryUpdate", player, {
		Changed = changedView,
		Removed = removed or {},
		Equipment = ProfileView.equipment(data),
		Stackables = ProfileView.stackables(data),
		Wallet = ProfileView.wallet(data),
		ReadyIn = readyInFor(player),
	})
end

-- The caller's own item, or nil (a forged / stale guid is logged).
local function ownItem(player: Player, data: { [string]: any }, guid: string): Item?
	local item = data.Inventory[guid]
	if item == nil then
		AuditLogService:Security(player, "ItemNotOwned", guid)
		notify(player, "Warning", "notOwned")
		return nil
	end
	return item
end

local function equippedSlotOf(data: { [string]: any }, guid: string): string?
	for slot, equipped in data.Equipment do
		if equipped == guid then
			return slot
		end
	end
	return nil
end

--------------------------------------------------------------------------------
-- Factory and grants (server-internal)
--------------------------------------------------------------------------------

--[[
	Creates a new item for `player` (server-internal only). The attributes
	are rolled here. `itemLevel` must fall in the def's tier band; `source`
	is a short tag such as "Boss:<runId>" or "Quest:FirstSpark".
	Returns the item, or nil and a reason ("unknown", "rarity", "level",
	"source", "noProfile", "full").
]]
function InventoryService:GrantItem(
	player: Player,
	defId: string,
	rarity: string,
	itemLevel: number,
	source: string
): (Item?, string?)
	local def = ItemDefinitions.get(defId)
	if def == nil then
		return nil, "unknown"
	end
	if not Enums.has(Enums.Rarity, rarity) then
		return nil, "rarity"
	end
	if
		type(itemLevel) ~= "number"
		or itemLevel % 1 ~= 0
		or itemLevel < def.minItemLevel
		or itemLevel > def.maxItemLevel
	then
		return nil, "level"
	end
	if
		type(source) ~= "string"
		or #source > ItemRules.MAX_SOURCE_LENGTH
		or string.match(source, SOURCE_PATTERN) == nil
	then
		return nil, "source"
	end
	local data = PlayerDataService:GetData(player)
	if data == nil then
		return nil, "noProfile"
	end
	if countItems(data) >= ItemRules.INVENTORY_CAP then
		notify(player, "Warning", "full", { cap = tostring(ItemRules.INVENTORY_CAP) })
		return nil, "full"
	end
	local guid = HttpService:GenerateGUID(false)
	while data.Inventory[guid] do
		guid = HttpService:GenerateGUID(false)
	end
	local item: Item = {
		Guid = guid,
		DefId = defId,
		Rarity = rarity,
		ItemLevel = itemLevel,
		Attributes = ItemRules.roll(def, rarity, itemLevel, function()
			return random:NextNumber()
		end),
		Enhancement = 0,
		Locked = false,
		Source = source,
		CreatedAt = os.time(),
	}
	data.Inventory[guid] = item
	push(player, data, { guid }, nil)
	log:Info("user=%d +item %s %s L%d (%s) %s", player.UserId, defId, rarity, itemLevel, source, guid)
	return item, nil
end

--[[
	Adds `count` of a stackable (server-internal). Anything above the stack
	cap is not added. Returns how many were added.
]]
function InventoryService:GrantStackable(player: Player, id: string, count: number, source: string): number
	local def = ItemDefinitions.stackable(id)
	local data = PlayerDataService:GetData(player)
	if def == nil or data == nil or type(count) ~= "number" or count % 1 ~= 0 or count <= 0 then
		return 0
	end
	local have = data.Stackables[id] or 0
	local added = math.min(count, def.maxStack - have)
	if added <= 0 then
		return 0
	end
	data.Stackables[id] = have + added
	push(player, data, nil, nil)
	log:Info("user=%d +%d %s (%s)", player.UserId, added, id, tostring(source))
	return added
end

function InventoryService:GetEquipped(player: Player, slot: string): Item?
	local data = PlayerDataService:GetData(player)
	local guid = data and data.Equipment[slot]
	return if data and guid then data.Inventory[guid] else nil
end

--------------------------------------------------------------------------------
-- Intents
--------------------------------------------------------------------------------

local EQUIP_REASON = {
	job = "equip.job",
	race = "equip.race",
	level = "equip.level",
	unknown = "notOwned",
}

local function onEquip(player: Player, guid: string)
	local data = PlayerDataService:GetData(player)
	if data == nil then
		return
	end
	local item = ownItem(player, data, guid)
	if item == nil then
		return
	end
	if CombatService:IsInCombat(player) then
		notify(player, "Warning", "inCombat")
		return
	end
	local ok, reason = ItemRules.canEquip(item, data.Job, data.Race, data.Level)
	if not ok then
		notify(
			player,
			"Warning",
			EQUIP_REASON[reason or "unknown"] or "notOwned",
			{ level = tostring(item.ItemLevel) }
		)
		return
	end
	local def = ItemDefinitions.get(item.DefId) :: ItemDefinitions.ItemDef
	if data.Equipment[def.slot] == guid then
		return
	end
	data.Equipment[def.slot] = guid
	push(player, data, nil, nil)
	CombatService:RefreshStats(player)
	RaceService:Redress(player)
end

local function onUnequip(player: Player, slot: string)
	local data = PlayerDataService:GetData(player)
	if data == nil or data.Equipment[slot] == nil then
		return
	end
	if CombatService:IsInCombat(player) then
		notify(player, "Warning", "inCombat")
		return
	end
	data.Equipment[slot] = nil
	push(player, data, nil, nil)
	CombatService:RefreshStats(player)
	RaceService:Redress(player)
end

local function onSalvage(player: Player, guids: { string })
	local data = PlayerDataService:GetData(player)
	if data == nil or #guids == 0 then
		return
	end
	-- Check every item first: one bad entry refuses the whole request.
	local seen = {}
	for _, guid in guids do
		local item = ownItem(player, data, guid)
		if item == nil or seen[guid] then
			return
		end
		seen[guid] = true
		if equippedSlotOf(data, guid) then
			notify(player, "Warning", "salvage.equipped")
			return
		end
		if item.Locked then
			notify(player, "Warning", "salvage.locked")
			return
		end
	end
	local fragments = 0
	for _, guid in guids do
		fragments += ItemRules.salvageYield(data.Inventory[guid])
	end
	local cap = (ItemDefinitions.stackable("StoneFragment") :: ItemDefinitions.StackableDef).maxStack
	local have = data.Stackables.StoneFragment or 0
	if have + fragments > cap then
		notify(player, "Warning", "salvage.full")
		return
	end
	for _, guid in guids do
		local item = data.Inventory[guid]
		log:Info(
			"user=%d salvaged %s %s %s L%d +%d",
			player.UserId,
			guid,
			item.DefId,
			item.Rarity,
			item.ItemLevel,
			item.Enhancement
		)
		data.Inventory[guid] = nil
	end
	data.Stackables.StoneFragment = have + fragments
	push(player, data, nil, guids)
	notify(player, "Info", "salvaged", { count = tostring(#guids), fragments = tostring(fragments) })
end

local function onLock(player: Player, guid: string, locked: boolean)
	local data = PlayerDataService:GetData(player)
	if data == nil then
		return
	end
	local item = ownItem(player, data, guid)
	if item == nil or item.Locked == locked then
		return
	end
	item.Locked = locked
	push(player, data, { guid }, nil)
end

local function onCombine(player: Player, count: number)
	local data = PlayerDataService:GetData(player)
	if data == nil then
		return
	end
	local need = count * ItemRules.FRAGMENTS_PER_STONE
	local have = data.Stackables.StoneFragment or 0
	if have < need then
		notify(player, "Warning", "combine.notEnough", { need = tostring(need) })
		return
	end
	local stoneCap = (ItemDefinitions.stackable("EnhancementStone") :: ItemDefinitions.StackableDef).maxStack
	local stones = data.Stackables.EnhancementStone or 0
	if stones + count > stoneCap then
		notify(player, "Warning", "combine.full")
		return
	end
	data.Stackables.StoneFragment = have - need
	data.Stackables.EnhancementStone = stones + count
	push(player, data, nil, nil)
	notify(player, "Info", "combined", { count = tostring(count) })
end

local function onUseConsumable(player: Player, id: string)
	local def = ItemDefinitions.stackable(id)
	local use = def and def.use
	local data = PlayerDataService:GetData(player)
	if def == nil or use == nil or data == nil then
		return
	end
	if (data.Stackables[id] or 0) <= 0 then
		notify(player, "Warning", "use.none", { name = def.name })
		return
	end
	local own = readyAt[player] or {}
	readyAt[player] = own
	local t = os.clock()
	if t < (own[id] or 0) then
		notify(player, "Warning", "use.cooldown", { seconds = tostring(math.ceil(own[id] - t)) })
		return
	end
	local entity = CombatService:GetPlayerEntity(player)
	if entity == nil or entity.defeated then
		return
	end
	if entity.hp >= entity.maxHp then
		notify(player, "Warning", "use.fullHp")
		return
	end
	-- Synchronous: consume, start the cooldown, heal.
	data.Stackables[id] -= 1
	own[id] = t + use.cooldown
	CombatService:RestoreHpPct(player, use.pct)
	push(player, data, nil, nil)
end

-- Studio only: one random piece for each slot of the player's job, at
-- random rarities and item levels up to theirs + 5, plus some stackables.
local function onStudioTestGear(player: Player)
	if not RunService:IsStudio() then
		AuditLogService:Security(player, "StudioOnlyRemote", "StudioTestGear")
		return
	end
	local data = PlayerDataService:GetData(player)
	if data == nil or data.Job == nil then
		return
	end
	local rarities = Enums.Rarity
	local families = ItemDefinitions.familiesOf(data.Job)
	local granted = 0
	for _, slot in Enums.ItemSlot do
		local level = math.clamp(data.Level + random:NextInteger(-2, 5), 0, 30)
		local family = if slot == "Weapon" then families[random:NextInteger(1, #families)] else nil
		local def = ItemDefinitions.defFor(data.Job, slot, family, level)
		if def then
			local item = InventoryService:GrantItem(
				player,
				def.id,
				rarities[random:NextInteger(1, #rarities)],
				level,
				"Studio:TestGear"
			)
			if item then
				granted += 1
			end
		end
	end
	InventoryService:GrantStackable(player, "HealingPotion", 5, "Studio:TestGear")
	InventoryService:GrantStackable(player, "StoneFragment", 25, "Studio:TestGear")
	notify(player, "Info", "testGear", { count = tostring(granted) })
end

--[[
	D-65: every character starts in a plain Standard set of its class (a
	weapon of its realm, chest, legs, boots; item level 0), worn at once.
	Granted once per profile (reward id "G:StarterGear"), also to
	characters made before gear existed.
]]
local STARTER_FAMILY = { Warrior = "Sword", Healer = "Staff", Archer = "Bow", Mage = "Wand" }

local function grantStarterGear(player: Player)
	local data = PlayerDataService:GetData(player)
	if data == nil or data.Job == nil or data.Race == nil then
		return
	end
	local status = (PlayerDataService :: any):ClaimReward(player, "G:StarterGear", function(profile)
		local families = ItemDefinitions.familiesOf(profile.Job)
		table.insert(families, 1, STARTER_FAMILY[profile.Job])
		local family = families[2]
		for _, candidate in families do
			if JobService:CanUseWeapon(player, candidate) then
				family = candidate
				break
			end
		end
		for _, slot in { "Weapon", "Chest", "Legs", "Boots" } do
			local def = ItemDefinitions.defFor(profile.Job, slot, if slot == "Weapon" then family else nil, 0)
			local item = def and InventoryService:GrantItem(player, def.id, "Standard", 0, "Gift:StarterGear")
			if item and def and profile.Equipment[slot] == nil then
				profile.Equipment[slot] = item.Guid
			end
		end
	end)
	if status == "granted" then
		push(player, data, nil, nil)
		CombatService:RefreshStats(player)
		RaceService:Redress(player)
		log:Info("user=%d starter gear granted", player.UserId)
	end
end

-- On load: anything equipped the character can no longer wear (an admin
-- job change, D-21) goes back to the bag.
local function checkEquipped(player: Player, data: { [string]: any })
	for slot, guid in data.Equipment do
		local item = data.Inventory[guid]
		if item == nil or not ItemRules.canEquip(item, data.Job, data.Race, data.Level) then
			data.Equipment[slot] = nil
			log:Warn(
				"user=%d unequipped %s from %s (no longer wearable)",
				player.UserId,
				tostring(guid),
				slot
			)
		end
	end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function InventoryService:Init()
	NetService:Handle("EquipItem", onEquip)
	NetService:Handle("UnequipItem", onUnequip)
	NetService:Handle("SalvageItems", onSalvage)
	NetService:Handle("LockItem", onLock)
	NetService:Handle("CombineFragments", onCombine)
	NetService:Handle("UseConsumable", onUseConsumable)
	NetService:Handle("StudioTestGear", onStudioTestGear)
	PlayerDataService.ProfileLoaded:Connect(function(player, data)
		checkEquipped(player, data)
		grantStarterGear(player)
	end)
	JobService.JobChosen:Connect(grantStarterGear)
end

function InventoryService:Start()
	Players.PlayerRemoving:Connect(function(player)
		readyAt[player] = nil
		lastNotice[player] = nil
	end)
	-- The inventory screen shows its Studio test button only here.
	if RunService:IsStudio() then
		ReplicatedStorage:SetAttribute("RC_StudioTestGear", true)
	end
end

return InventoryService
