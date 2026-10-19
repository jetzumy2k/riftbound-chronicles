--!strict
--[[
	LootService (Layer 5)
	Dungeon loot (Phase 10, PLAN.md D-06 / D-07 / D-67; CLAUDE.md §12).

	When a dungeon creature falls, every player who earned it (the same
	players who share its EXP: the fighters and their party nearby) gets
	their **own** roll on its table (config Loot.Tables, Logic/LootRules):
	first whether anything drops, then the rarity. A drop is a piece of the
	player's own class (a weapon of a family their realm uses, armor or the
	accessory) at the creature's level (capped at 30), made by the item
	factory (InventoryService:GrantItem, attributes rolled there).

	  DungeonMob / DungeonElite   12% / 35% drop; 45% Standard, 25% Uncommon,
	                              30% Rare
	  DungeonMiniBoss / FloorBoss / Boss   always drop; 80% Rare, 20% Legendary

	Rules: no loot where the level gap gives no EXP (LevelGap: a creature 10+
	levels below, or 20+ above); each kill pays once (a creature is only
	defeated once; boss loot is also claimed per spawn, "B:<spawnId>:<boss>:L");
	every drop is audit-logged; an invalid table (weights not summing to 100)
	is rejected and the built-in default is used. A full bag loses the drop
	(the player is told).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local LootRules = require(Shared.Logic.LootRules)
local LevelGap = require(Shared.Logic.LevelGap)
local Log = require(Shared.Util.Log)

local AuditLogService = require(script.Parent.AuditLogService)
local ConfigurationService = require(script.Parent.ConfigurationService)
local NetService = require(script.Parent.NetService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local InventoryService = require(script.Parent.InventoryService)

local log = Log.new("LootService")
local random = Random.new()

local LootService = {}

-- Built-in tables, used when the configured one is invalid (D-67).
local FALLBACK: { [string]: LootRules.Table } = {
	DungeonMob = { DropChancePct = 12, Rarity = { Standard = 45, Uncommon = 25, Rare = 30 } },
	DungeonElite = { DropChancePct = 35, Rarity = { Standard = 45, Uncommon = 25, Rare = 30 } },
	DungeonMiniBoss = { DropChancePct = 100, Rarity = { Rare = 80, Legendary = 20 } },
	DungeonFloorBoss = { DropChancePct = 100, Rarity = { Rare = 80, Legendary = 20 } },
	DungeonBoss = { DropChancePct = 100, Rarity = { Rare = 80, Legendary = 20 } },
}

local warned: { [string]: boolean } = {}

local function tableFor(id: string): LootRules.Table
	local tables = ConfigurationService:Get("Loot.Tables")
	local configured = tables[id]
	local ok, reason = LootRules.validate(configured)
	if ok then
		warned[id] = nil
		return configured
	end
	if not warned[id] then
		warned[id] = true
		log:Error("loot table %s rejected (%s); using the default", id, tostring(reason))
	end
	return FALLBACK[id]
end

-- One player's roll on `tableId` for a creature of `level`. Returns the item.
local function rollFor(player: Player, tableId: string, level: number, source: string): any?
	local data = PlayerDataService:GetData(player)
	if data == nil or data.Job == nil then
		return nil
	end
	if LevelGap.tierFor(level, data.Level).percent <= 0 then
		return nil
	end
	local rarity = LootRules.roll(tableFor(tableId), random:NextNumber(), random:NextNumber())
	if rarity == nil then
		return nil
	end
	local itemLevel = LootRules.itemLevelFor(level)
	local def = LootRules.pickPiece(data.Job, data.Race, itemLevel, random:NextNumber(), random:NextNumber())
	if def == nil then
		return nil
	end
	local item, reason = InventoryService:GrantItem(player, def.id, rarity, itemLevel, source)
	if item == nil then
		if reason == "full" then
			NetService:FireClient("Notify", player, {
				kind = "Warning",
				textKey = "loot.bagFull",
				params = { name = def.name, rarity = rarity },
			})
		end
		return nil
	end
	AuditLogService:Audit({
		actorUserId = player.UserId,
		action = "LootDrop",
		target = item.Guid,
		details = { table = tableId, defId = def.id, rarity = rarity, itemLevel = itemLevel, source = source },
	})
	NetService:FireClient("Notify", player, {
		kind = "Info",
		textKey = "loot.drop",
		params = { name = def.name, rarity = rarity, level = tostring(itemLevel) },
	})
	return item
end

--[[
	Rolls `tableId` for each of `players` (personal loot) for a creature of
	`level`. `claimId` (bosses): each player can collect it only once
	("B:<spawnId>:<boss>:L"). `source` tags the items.
]]
function LootService:DropFor(
	players: { Player },
	tableId: string,
	level: number,
	source: string,
	claimId: string?
)
	if FALLBACK[tableId] == nil then
		log:Error("unknown loot table %s", tableId)
		return
	end
	for _, player in players do
		if claimId then
			(PlayerDataService :: any):ClaimReward(player, claimId, function()
				rollFor(player, tableId, level, source)
			end)
		else
			rollFor(player, tableId, level, source)
		end
	end
end

function LootService:Init()
	for id, t in FALLBACK do
		assert(LootRules.validate(t), `built-in loot table {id} is invalid`)
	end
	for _, id in LootRules.TABLE_IDS do
		local ok, reason = LootRules.validate(ConfigurationService:Get("Loot.Tables")[id])
		if not ok then
			log:Error("loot table %s rejected at load (%s); using the default", id, tostring(reason))
		end
	end
end

return LootService
