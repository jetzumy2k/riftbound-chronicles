--!strict
--[[
	ShopService (Layer 6) — the Merchant and the Exchanger in each capital,
	and Gold from creatures (creator request 2026-10-27, PLAN.md D-117;
	prices and rules in Logic/ShopRules, numbers in config Shop / Exchange
	/ Loot.GoldPctOfXp).

	The NPCs (Definitions/NpcDefinitions) stand in both capitals; talking
	to one (ProximityPrompt, same realm, server-checked reach) sends
	NpcOpen to that player. Every NpcShop call is checked again on the
	server: reach to that NPC, the price from config, Gold / Mall Points /
	bag room, and the item rules. Purchases and exchanges change the
	profile synchronously (no yield between check and write, DATA_MODEL
	§4.1) and are audit logged.

	  Catalog     what this NPC offers the player now (prices at their level)
	  BuyPotion   Healing Potions for Gold
	  BuyGear     a Standard / Uncommon / Rare piece of the player's class
	              at their level, FIXED attributes (never a random roll)
	  Sell        up to 20 unused items (not equipped, not locked) for Gold
	  Exchange    Mall Points <-> Gold at the admin's ratios, daily limits
	              per account

	Gold from creatures: every player who earns a creature's EXP also gets
	Loot.GoldPctOfXp % of it in Gold (split like the EXP).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local NpcDefinitions = require(Shared.Definitions.NpcDefinitions)
local ItemDefinitions = require(Shared.Definitions.ItemDefinitions)
local JobDefinitions = require(Shared.Definitions.JobDefinitions)
local EnemyDefinitions = require(Shared.Definitions.EnemyDefinitions)
local WorldLayout = require(Shared.Definitions.WorldLayout)
local ShopRules = require(Shared.Logic.ShopRules)
local DurabilityRules = require(Shared.Logic.DurabilityRules)
local ItemRules = require(Shared.Logic.ItemRules)
local Log = require(Shared.Util.Log)

local NpcBuilder = require(script.Parent.Parent.Appearance.NpcBuilder)

local ConfigurationService = require(script.Parent.ConfigurationService)
local AuditLogService = require(script.Parent.AuditLogService)
local NetService = require(script.Parent.NetService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local InventoryService = require(script.Parent.InventoryService)
local MobService = require(script.Parent.MobService)
local CombatService = require(script.Parent.CombatService)

local log = Log.new("ShopService")

local REACH_TOLERANCE = 6
local MAX_SELL = 20
local SNAPSHOT_DELAY = 2

local ShopService = {}

-- NPC positions per realm: race -> npc id -> root position.
local npcAt: { [string]: { [string]: Vector3 } } = {}
local folder: Folder
-- Players whose wallet changed and wait for a (debounced) snapshot.
local snapshotDue: { [Player]: boolean } = {}

local function shopConfig(): ShopRules.ShopConfig
	return ConfigurationService:Get("Shop")
end

local function exchangeConfig(): ShopRules.ExchangeConfig
	return ConfigurationService:Get("Exchange")
end

local function notify(player: Player, kind: string, textKey: string, params: { [string]: string }?)
	NetService:FireClient("Notify", player, { kind = kind, textKey = textKey, params = params })
end

local function pushSoon(player: Player)
	if snapshotDue[player] then
		return
	end
	snapshotDue[player] = true
	task.delay(SNAPSHOT_DELAY, function()
		snapshotDue[player] = nil
		if player.Parent == Players then
			PlayerDataService:PushSnapshot(player)
		end
	end)
end

-- True if `player` (of the NPC's realm) stands within reach of NPC `id`.
local function near(player: Player, data: { [string]: any }, id: string): boolean
	local at = data.Race and npcAt[data.Race] and npcAt[data.Race][id]
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if at == nil or root == nil or not root:IsA("BasePart") then
		return false
	end
	return (root.Position - at).Magnitude <= NpcDefinitions.REACH + REACH_TOLERANCE
end

local function level(data: { [string]: any }): number
	return math.clamp(data.Level or 0, 0, 30)
end

-- The def and item level the Merchant makes for this piece, or nil.
local function stockPiece(
	data: { [string]: any },
	kind: string,
	family: string?
): (ItemDefinitions.ItemDef?, number)
	local job = data.Job
	if job == nil or table.find(ItemDefinitions.kindsOf(job), kind) == nil then
		return nil, 0
	end
	if kind == "Weapon" then
		local definition = JobDefinitions.get(job)
		local families = definition and definition.weaponsByRace[data.Race]
		if family == nil or families == nil or table.find(families, family) == nil then
			return nil, 0
		end
	else
		family = nil
	end
	local def = ItemDefinitions.defFor(job, kind, family, level(data))
	if def == nil then
		return nil, 0
	end
	return def, math.clamp(level(data), def.minItemLevel, def.maxItemLevel)
end

-- D-118: every worn-down item (bag and equipped) with its repair cost.
local function repairList(player: Player, data: { [string]: any }): { any }
	local c = ConfigurationService:Get("Durability")
	local out = {}
	for guid, item in data.Inventory do
		local cost = DurabilityRules.repairCost(c, item)
		if cost > 0 then
			local def = ItemDefinitions.get(item.DefId)
			table.insert(out, {
				Guid = guid,
				Name = if def then def.name else item.DefId,
				Rarity = item.Rarity,
				Level = item.ItemLevel or 0,
				Durability = DurabilityRules.of(item),
				Cost = cost,
				Equipped = InventoryService:EquippedSlot(player, guid) ~= nil,
			})
		end
	end
	-- Broken and equipped first.
	table.sort(out, function(a, b)
		if a.Equipped ~= b.Equipped then
			return a.Equipped
		end
		return a.Durability < b.Durability
	end)
	return out
end

local function catalog(player: Player, data: { [string]: any }, id: string): { [string]: any }
	if id == "Blacksmith" then
		return {
			ok = true,
			npc = id,
			repairs = repairList(player, data),
			max = DurabilityRules.MAX,
			gold = data.Wallet.Gold or 0,
		}
	end
	if id == "Exchanger" then
		local c = exchangeConfig()
		local today = ShopRules.day(os.time())
		local used = if data.ExchangeDay.Day == today
			then data.ExchangeDay
			else { ToGold = 0, ToMallPoints = 0 }
		return {
			ok = true,
			npc = id,
			enabled = c.Enabled,
			goldPerMallPoint = c.GoldPerMallPoint,
			goldForMallPoint = c.GoldForMallPoint,
			dailyToGold = c.DailyMallPointsToGold,
			dailyToMallPoints = c.DailyGoldToMallPoints,
			usedToGold = used.ToGold or 0,
			usedToMallPoints = used.ToMallPoints or 0,
			gold = data.Wallet.Gold or 0,
			mallPoints = data.Wallet.MallPoints or 0,
		}
	end
	local c = shopConfig()
	local stock = {}
	local job = data.Job
	if job then
		local definition = JobDefinitions.get(job)
		for _, kind in ItemDefinitions.kindsOf(job) do
			local families = if kind == "Weapon" and definition
				then definition.weaponsByRace[data.Race] or {}
				else { false }
			for _, family in families :: { any } do
				local fam = if family == false then nil else family
				local def, itemLevel = stockPiece(data, kind, fam)
				if def then
					for _, rarity in ShopRules.GEAR_RARITIES do
						table.insert(stock, {
							Kind = kind,
							Family = fam,
							Rarity = rarity,
							Pick = if fam then `{kind}:{fam}:{rarity}` else `{kind}:{rarity}`,
							DefId = def.id,
							Name = def.name,
							Level = itemLevel,
							Price = ShopRules.gearPrice(c, rarity, itemLevel),
						})
					end
				end
			end
		end
	end
	-- What the Merchant would pay for each unused item.
	local offers = {}
	for guid, item in data.Inventory do
		if not item.Locked and InventoryService:EquippedSlot(player, guid) == nil then
			local def = ItemDefinitions.get(item.DefId)
			table.insert(offers, {
				Guid = guid,
				Name = if def then def.name else item.DefId,
				Rarity = item.Rarity,
				Level = item.ItemLevel or 0,
				Enhancement = item.Enhancement or 0,
				Price = ShopRules.sellPrice(c, item.Rarity, item.ItemLevel or 0, item.Enhancement or 0),
			})
		end
	end
	table.sort(offers, function(a, b)
		return a.Price > b.Price
	end)
	return {
		ok = true,
		npc = id,
		enabled = c.Enabled,
		potionPrice = c.PotionPrice,
		stock = stock,
		offers = offers,
		gold = data.Wallet.Gold or 0,
		potions = data.Stackables[ShopRules.POTION] or 0,
	}
end

local function onShop(player: Player, action: string, args: { [string]: any }): { [string]: any }
	local data = PlayerDataService:GetData(player)
	if data == nil or data.Job == nil then
		return { ok = false, reason = "notLoaded" }
	end
	local id = args.Npc
	if NpcDefinitions.get(id) == nil then
		return { ok = false, reason = "npc" }
	end
	if not near(player, data, id) then
		return { ok = false, reason = "far" }
	end
	if action == "Catalog" then
		return catalog(player, data, id)
	end
	local wallet = data.Wallet
	if id == "Merchant" then
		local c = shopConfig()
		if not c.Enabled then
			return { ok = false, reason = "closed" }
		end
		if action == "BuyPotion" then
			local count = args.Count
			if type(count) ~= "number" or count % 1 ~= 0 or count < 1 or count > ShopRules.MAX_BUY then
				return { ok = false, reason = "count" }
			end
			local def = ItemDefinitions.stackable(ShopRules.POTION) :: ItemDefinitions.StackableDef
			if (data.Stackables[ShopRules.POTION] or 0) + count > def.maxStack then
				return { ok = false, reason = "full" }
			end
			local price = ShopRules.potionPrice(c, count)
			if (wallet.Gold or 0) < price then
				return { ok = false, reason = "gold" }
			end
			wallet.Gold -= price
			InventoryService:GrantStackable(player, ShopRules.POTION, count, "Shop:Merchant")
			AuditLogService:Audit({
				actorUserId = player.UserId,
				action = "ShopBuy",
				target = ShopRules.POTION,
				details = { count = count, gold = price, left = wallet.Gold },
			})
			pushSoon(player)
			return catalog(player, data, id)
		elseif action == "BuyGear" then
			local parts = string.split(if type(args.Pick) == "string" then args.Pick else "", ":")
			local kind = parts[1]
			local family = if #parts == 3 then parts[2] else nil
			local rarity = parts[#parts]
			local def, itemLevel = stockPiece(data, kind, family)
			local price = if def then ShopRules.gearPrice(c, rarity, itemLevel) else nil
			if def == nil or price == nil then
				return { ok = false, reason = "stock" }
			end
			if InventoryService:FreeSlots(player) < 1 then
				return { ok = false, reason = "bag" }
			end
			if (wallet.Gold or 0) < price then
				return { ok = false, reason = "gold" }
			end
			wallet.Gold -= price
			local item, why = InventoryService:GrantItem(
				player,
				def.id,
				rarity,
				itemLevel,
				"Shop:Merchant",
				ItemRules.fixedRoll(def, rarity, itemLevel)
			)
			if item == nil then
				wallet.Gold += price
				log:Error("shop item not made for %d: %s", player.UserId, tostring(why))
				return { ok = false, reason = "stock" }
			end
			AuditLogService:Audit({
				actorUserId = player.UserId,
				action = "ShopBuy",
				target = def.id,
				details = { rarity = rarity, level = itemLevel, gold = price, left = wallet.Gold },
			})
			pushSoon(player)
			return catalog(player, data, id)
		elseif action == "Sell" then
			local guids = args.Guids
			if type(guids) ~= "table" or #guids == 0 or #guids > MAX_SELL then
				return { ok = false, reason = "count" }
			end
			-- Check every item first: one bad entry refuses the whole sale.
			local seen, total = {}, 0
			for _, guid in guids do
				local item = data.Inventory[guid]
				if type(item) ~= "table" or seen[guid] then
					return { ok = false, reason = "item" }
				end
				seen[guid] = true
				if item.Locked then
					return { ok = false, reason = "locked" }
				end
				if InventoryService:EquippedSlot(player, guid) then
					return { ok = false, reason = "equipped" }
				end
				total += ShopRules.sellPrice(c, item.Rarity, item.ItemLevel or 0, item.Enhancement or 0)
			end
			local sold = {}
			for _, guid in guids do
				local item = data.Inventory[guid]
				table.insert(sold, `{item.DefId}:{item.Rarity}:{item.Enhancement or 0}`)
				InventoryService:RemoveItem(player, guid, "sold")
			end
			wallet.Gold = (wallet.Gold or 0) + total
			AuditLogService:Audit({
				actorUserId = player.UserId,
				action = "ShopSell",
				target = tostring(#guids),
				details = { gold = total, items = table.concat(sold, ","), left = wallet.Gold },
			})
			notify(player, "Info", "shop.sold", { count = tostring(#guids), gold = tostring(total) })
			pushSoon(player)
			return catalog(player, data, id)
		end
		return { ok = false, reason = "action" }
	end
	if id == "Blacksmith" then
		if action ~= "Repair" and action ~= "RepairAll" then
			return { ok = false, reason = "action" }
		end
		local c = ConfigurationService:Get("Durability")
		local guids: { string } = {}
		if action == "RepairAll" then
			for _, entry in repairList(player, data) do
				table.insert(guids, entry.Guid)
			end
		else
			guids = if type(args.Guids) == "table" then args.Guids else {}
		end
		if #guids == 0 then
			return { ok = false, reason = "nothing" }
		end
		-- Price everything first; pay once; then repair (no yields).
		local total, seen, wasBroken = 0, {}, false
		for _, guid in guids do
			local item = data.Inventory[guid]
			if type(item) ~= "table" or seen[guid] then
				return { ok = false, reason = "item" }
			end
			seen[guid] = true
			total += DurabilityRules.repairCost(c, item)
		end
		if total <= 0 then
			return { ok = false, reason = "nothing" }
		end
		if (wallet.Gold or 0) < total then
			return { ok = false, reason = "gold" }
		end
		wallet.Gold -= total
		for _, guid in guids do
			local item = data.Inventory[guid]
			if DurabilityRules.isBroken(item) and InventoryService:EquippedSlot(player, guid) then
				wasBroken = true
			end
			item.Durability = DurabilityRules.MAX
		end
		if wasBroken then
			CombatService:RefreshStats(player)
		end
		InventoryService:Push(player, guids)
		AuditLogService:Audit({
			actorUserId = player.UserId,
			action = "Repair",
			target = tostring(#guids),
			details = { gold = total, left = wallet.Gold },
		})
		notify(player, "Info", "shop.repaired", { count = tostring(#guids), gold = tostring(total) })
		pushSoon(player)
		return catalog(player, data, id)
	end
	-- Exchanger.
	if action ~= "Exchange" then
		return { ok = false, reason = "action" }
	end
	local direction, amount = args.Direction, args.Count
	local today = ShopRules.day(os.time())
	if data.ExchangeDay.Day ~= today then
		data.ExchangeDay = { Day = today, ToGold = 0, ToMallPoints = 0 }
	end
	local used = data.ExchangeDay[direction] or 0
	local gold, ok, reason = ShopRules.exchange(exchangeConfig(), direction, amount, used)
	if not ok then
		return { ok = false, reason = reason }
	end
	if direction == "ToGold" then
		if (wallet.MallPoints or 0) < amount then
			return { ok = false, reason = "points" }
		end
		wallet.MallPoints -= amount
		wallet.Gold = (wallet.Gold or 0) + gold
	else
		if (wallet.Gold or 0) < gold then
			return { ok = false, reason = "gold" }
		end
		wallet.Gold -= gold
		wallet.MallPoints = (wallet.MallPoints or 0) + amount
	end
	data.ExchangeDay[direction] = used + amount
	AuditLogService:Audit({
		actorUserId = player.UserId,
		action = "Exchange",
		target = direction,
		details = { mallPoints = amount, gold = gold, mp = wallet.MallPoints, goldLeft = wallet.Gold },
	})
	PlayerDataService:PushSnapshot(player)
	return catalog(player, data, id)
end

local function onMobDefeated(mob: any, _contributors: any, recipients: { Player }?)
	local pct = ConfigurationService:Get("Loot").GoldPctOfXp
	if recipients == nil or #recipients == 0 or type(pct) ~= "number" or pct <= 0 then
		return
	end
	local gold = ShopRules.killGold(EnemyDefinitions.xpAt(mob.enemy, mob.level), pct, #recipients)
	for _, player in recipients do
		local data = PlayerDataService:GetData(player)
		if data then
			data.Wallet.Gold = (data.Wallet.Gold or 0) + gold
			pushSoon(player)
		end
	end
end

local function buildNpc(race: string, npc: NpcDefinitions.Npc)
	local realm = WorldLayout.Realms[race]
	if realm == nil then
		return
	end
	local p = WorldLayout.toWorld(realm, npc.at)
	local spawn = realm.spawnPosition
	local at = Vector3.new(p[1], p[2] + 3.2, p[3])
	local name = npc.names[race] or npc.id
	local model, root = NpcBuilder.build(
		race,
		npc.look,
		name,
		`{npc.icon} {npc.title}`,
		CFrame.lookAt(at, Vector3.new(spawn[1], at.Y, spawn[3])),
		folder
	)
	if model == nil or root == nil then
		log:Warn("%s %s not built", race, npc.id)
		return
	end
	model:SetAttribute("RC_Npc", npc.id)
	npcAt[race] = npcAt[race] or {}
	npcAt[race][npc.id] = root.Position
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = npc.prompt
	prompt.ObjectText = name
	prompt.MaxActivationDistance = NpcDefinitions.REACH - 2
	prompt.RequiresLineOfSight = false
	prompt.HoldDuration = 0
	prompt.Parent = root
	prompt.Triggered:Connect(function(player)
		local data = PlayerDataService:GetData(player)
		if data and data.Race == race and data.Job ~= nil and near(player, data, npc.id) then
			NetService:FireClient("NpcOpen", player, { Npc = npc.id })
		end
	end)
end

function ShopService:Init()
	NetService:Handle("NpcShop", onShop)
	MobService.MobDefeated:Connect(onMobDefeated)
end

function ShopService:Start()
	folder = Instance.new("Folder")
	folder.Name = "RC_TownNpcs"
	folder.Parent = Workspace
	for race in WorldLayout.Realms :: { [string]: any } do
		for _, npc in NpcDefinitions.List do
			task.spawn(buildNpc, race, npc)
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		snapshotDue[player] = nil
	end)
end

return ShopService
