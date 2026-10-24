--!strict
--[[
	LootService (Layer 5)
	Dungeon loot (Phase 10, PLAN.md D-06 / D-07 / D-67; CLAUDE.md §12) and
	war-zone loot (Phase 14, D-76; CLAUDE.md §15).

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

	War zones (called by PvPService):
	  WarZoneBoss   always drops; 80% Rare, 20% Mythical. Claimed per boss
	                spawn; the level gap is measured against at most level 30
	                (`capGap`), so a level-50 boss pays level-30 players but
	                not a low-level party member standing by.
	  WarZoneMob    stone table (DropStonesFor): 25% chance of a stone, then
	                30% Perfect / 70% Enhancement Stone. A full stack loses
	                the stone (the player is told).
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
	WarZoneBoss = { DropChancePct = 100, Rarity = { Rare = 80, Mythical = 20 } },
}
local STONE_FALLBACK: { [string]: LootRules.StoneTable } = {
	WarZoneMob = { DropChancePct = 25, Stones = { PerfectStone = 30, EnhancementStone = 70 } },
}

export type DropOptions = {
	-- Measure the level gap against min(level, 30): bosses above the cap.
	capGap: boolean?,
	-- Runs inside the claim (once per player per claimId), e.g. PvP Marks.
	onClaim: ((player: Player) -> ())?,
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

local function stoneTableFor(id: string): LootRules.StoneTable
	local configured = ConfigurationService:Get("Loot.StoneTables")[id]
	local ok, reason = LootRules.validateStones(configured)
	if ok then
		warned[id] = nil
		return configured
	end
	if not warned[id] then
		warned[id] = true
		log:Error("stone table %s rejected (%s); using the default", id, tostring(reason))
	end
	return STONE_FALLBACK[id]
end

-- No loot where the level gap gives no EXP (D-63); `capGap` for bosses above 30.
local function earns(level: number, playerLevel: number, capGap: boolean?): boolean
	local gapLevel = if capGap then math.min(level, LootRules.itemLevelFor(level)) else level
	return LevelGap.tierFor(gapLevel, playerLevel).percent > 0
end

-- One player's roll on `tableId` for a creature of `level`. Returns the item.
local function rollFor(player: Player, tableId: string, level: number, source: string, capGap: boolean?): any?
	local data = PlayerDataService:GetData(player)
	if data == nil or data.Job == nil then
		return nil
	end
	if not earns(level, data.Level, capGap) then
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
	claimId: string?,
	options: DropOptions?
)
	if FALLBACK[tableId] == nil then
		log:Error("unknown loot table %s", tableId)
		return
	end
	local capGap = options and options.capGap
	local onClaim = options and options.onClaim
	for _, player in players do
		if claimId then
			(PlayerDataService :: any):ClaimReward(player, claimId, function()
				rollFor(player, tableId, level, source, capGap)
				if onClaim then
					onClaim(player)
				end
			end)
		else
			rollFor(player, tableId, level, source, capGap)
		end
	end
end

--[[
	Rolls stone table `tableId` for each of `players` (personal) for a
	creature of `level` (Phase 14: war-zone creatures). A creature is
	defeated once, so each kill pays once.
]]
function LootService:DropStonesFor(players: { Player }, tableId: string, level: number, source: string)
	if STONE_FALLBACK[tableId] == nil then
		log:Error("unknown stone table %s", tableId)
		return
	end
	local t = stoneTableFor(tableId)
	for _, player in players do
		local data = PlayerDataService:GetData(player)
		if data == nil or data.Job == nil or not earns(level, data.Level, false) then
			continue
		end
		local stone = LootRules.rollStone(t, random:NextNumber(), random:NextNumber())
		if stone == nil then
			continue
		end
		local added = InventoryService:GrantStackable(player, stone, 1, source)
		if added <= 0 then
			NetService:FireClient("Notify", player, {
				kind = "Warning",
				textKey = "loot.stoneFull",
				params = { stone = stone },
			})
			continue
		end
		AuditLogService:Audit({
			actorUserId = player.UserId,
			action = "LootDrop",
			target = stone,
			details = { table = tableId, stone = stone, source = source },
		})
		NetService:FireClient("Notify", player, {
			kind = "Info",
			textKey = if stone == "PerfectStone" then "loot.perfectStone" else "loot.stone",
		})
	end
end

function LootService:Init()
	for id, t in FALLBACK do
		assert(LootRules.validate(t), `built-in loot table {id} is invalid`)
	end
	for id, t in STONE_FALLBACK do
		assert(LootRules.validateStones(t), `built-in stone table {id} is invalid`)
	end
	for _, id in LootRules.STONE_TABLE_IDS do
		local ok, reason = LootRules.validateStones(ConfigurationService:Get("Loot.StoneTables")[id])
		if not ok then
			log:Error("stone table %s rejected at load (%s); using the default", id, tostring(reason))
		end
	end
	for _, id in LootRules.TABLE_IDS do
		local ok, reason = LootRules.validate(ConfigurationService:Get("Loot.Tables")[id])
		if not ok then
			log:Error("loot table %s rejected at load (%s); using the default", id, tostring(reason))
		end
	end
end

return LootService
