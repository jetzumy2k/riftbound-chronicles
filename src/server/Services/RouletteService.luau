--!strict
--[[
	RouletteService (Layer 6) — the Fortune Wheel NPC (creator request
	2026-10-27, PLAN.md D-120; rules in Logic/RouletteRules, numbers in
	config Roulette). The 🎡 Fortune Teller stands in each capital (built by
	ShopService with the other town NPCs).

	Remote Roulette:
	  Status  the odds, free spins left today, the Gold price
	  Spin    a free spin if one is left today, else GoldPerSpin Gold;
	          needs a free bag slot (any prize may be gear). The prize is
	          rolled here and given at once; the Gold or free spin is taken
	          in the same step (no yields).
	Never Robux or Mall Points (creator decision 2026-10-27). Every spin
	and prize is audit logged.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local RouletteRules = require(Shared.Logic.RouletteRules)
local AttributeRules = require(Shared.Logic.AttributeRules)
local BuffRules = require(Shared.Logic.BuffRules)
local ItemDefinitions = require(Shared.Definitions.ItemDefinitions)
local LevelCap = require(Shared.Logic.LevelCap)
local Log = require(Shared.Util.Log)

local ConfigurationService = require(script.Parent.ConfigurationService)
local AuditLogService = require(script.Parent.AuditLogService)
local NetService = require(script.Parent.NetService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local InventoryService = require(script.Parent.InventoryService)
local CombatService = require(script.Parent.CombatService)
local LevelService = require(script.Parent.LevelService)
local ShopService = require(script.Parent.ShopService)

local log = Log.new("RouletteService")

local NPC = "Fortune"
local DEFAULT_WEIGHTS =
	{ ThankYou = 40, Standard = 25, Rare = 17, Consumable = 10, Attribute = 4, Level = 2, Legendary = 2 }

local RouletteService = {}

local random = Random.new()

local function config(): RouletteRules.Config
	local c = table.clone(ConfigurationService:Get("Roulette"))
	-- An invalid table never reaches a spin: the built-in odds are used.
	if not RouletteRules.validate(c.Weights) then
		c.Weights = DEFAULT_WEIGHTS
	end
	return c
end

local function today(): number
	return os.time() // 86400
end

local function status(player: Player, data: { [string]: any }): { [string]: any }
	local c = config()
	return {
		ok = true,
		enabled = c.Enabled,
		weights = c.Weights,
		free = RouletteRules.freeLeft(data.Roulette, c, today()),
		price = c.GoldPerSpin,
		gold = data.Wallet.Gold or 0,
		bagFree = InventoryService:FreeSlots(player),
	}
end

-- Gives `prize`; returns what the player got, in words.
local function give(player: Player, data: { [string]: any }, prize: string): string
	if
		prize == "Level"
		and (data.Level or 0) >= LevelCap.of(ConfigurationService:Get("Progression").Level60)
	then
		prize = "Consumable"
	end
	if prize == "Standard" or prize == "Rare" or prize == "Legendary" then
		local name = InventoryService:GrantRandomPiece(player, prize, "Roulette:Fortune")
		return if name then `{prize} {name}` else "nothing (bag full)"
	elseif prize == "Consumable" then
		local pick = RouletteRules.CONSUMABLES[random:NextInteger(1, #RouletteRules.CONSUMABLES)]
		local id, count = pick.id, pick.count
		if id == "Buff" then
			id = `Buff_{BuffRules.IDS[random:NextInteger(1, #BuffRules.IDS)]}`
		end
		local added = InventoryService:GrantStackable(player, id, count, "Roulette:Fortune")
		local def = ItemDefinitions.stackable(id)
		return `{added} × {if def then def.name else id}`
	elseif prize == "Attribute" then
		local ids = AttributeRules.IDS
		local id = ids[random:NextInteger(1, #ids)]
		data.BonusAttributes[id] = math.min((data.BonusAttributes[id] or 0) + 1, RouletteRules.MAX_BONUS)
		CombatService:RefreshStats(player)
		return `+1 {AttributeRules.NAMES[id] or id} (permanent)`
	elseif prize == "Level" then
		local level = (data.Level or 0) + 1
		LevelService:SetLevel(player, level)
		return `Level {level}!`
	end
	return "Thank you for playing!"
end

local function onRequest(player: Player, action: string): { [string]: any }
	local data = PlayerDataService:GetData(player)
	if data == nil or data.Job == nil then
		return { ok = false, reason = "notLoaded" }
	end
	if not ShopService:Near(player, data, NPC) then
		return { ok = false, reason = "far" }
	end
	if action == "Status" then
		return status(player, data)
	end
	if action ~= "Spin" then
		return { ok = false, reason = "action" }
	end
	local c = config()
	if not c.Enabled then
		return { ok = false, reason = "closed" }
	end
	if InventoryService:FreeSlots(player) < 1 then
		return { ok = false, reason = "bag" }
	end
	local day = today()
	local free = RouletteRules.freeLeft(data.Roulette, c, day) > 0
	if not free and (data.Wallet.Gold or 0) < c.GoldPerSpin then
		return { ok = false, reason = "gold" }
	end
	-- Pay (a free spin or Gold), roll, give: all in one step.
	if free then
		local used = if data.Roulette.Day == day then data.Roulette.Used else 0
		data.Roulette = { Day = day, Used = used + 1 }
	else
		data.Wallet.Gold -= c.GoldPerSpin
	end
	local prize = RouletteRules.pick(c.Weights, random:NextNumber())
	local given = give(player, data, prize)
	AuditLogService:Audit({
		actorUserId = player.UserId,
		action = "RouletteSpin",
		target = prize,
		details = { free = free, gold = if free then 0 else c.GoldPerSpin, given = given },
	})
	log:Info("user=%d spun %s: %s", player.UserId, prize, given)
	PlayerDataService:PushSnapshot(player)
	local out = status(player, data)
	out.prize = prize
	out.given = given
	return out
end

function RouletteService:Init()
	NetService:Handle("Roulette", onRequest)
end

return RouletteService
