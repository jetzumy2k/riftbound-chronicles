--!strict
--[[
	CharacterService (Layer 6) — character slots (creator request
	2026-10-27, PLAN.md D-115; data rules in Persistence/CharacterSlots).

	Up to Constants.Characters.MaxSlots characters per account, all of the
	account's realm, one played at a time. The character screen (remote
	CharacterSlots) can:

	  List    every slot: class and level, which one is being played
	  Switch  to another character, or an empty slot to create a new one
	          (the class screen opens). Not while in combat. The choice is
	          saved as PendingSlot and the player rejoins; the swap happens
	          on load (load hook) before any service sees the profile, so
	          no live state is ever swapped underneath a service.
	  Delete  a character, with the typed confirmation DELETE. A copy is
	          saved first (RC_DeletedCharacters_v1). Deleting the played
	          character moves to another one; deleting the last one frees
	          the realm (race selection opens again, D-116 option 1).

	ConvertRace (D-116): with a Race Conversion Rune, CONVERT typed and the
	other realm chosen, the rune is used and PendingRace saved; on the
	rejoin, after a backup of the whole profile (RC_RaceChanges_v1), the
	account and every character move to that realm
	(CharacterSlots.convertRace). If the backup fails the change waits for
	the next load (the rune is already spent, never lost twice).

	Rejoin: TeleportService to this place; in Studio (no teleports) the
	player is asked to rejoin. Every change is audit logged.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local CharacterSlots = require(script.Parent.Parent.Persistence.CharacterSlots)
local Log = require(game:GetService("ReplicatedStorage").Shared.Util.Log)

local AuditLogService = require(script.Parent.AuditLogService)
local NetService = require(script.Parent.NetService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local CombatService = require(script.Parent.CombatService)

local log = Log.new("CharacterService")

local BACKUP_STORE = "RC_DeletedCharacters_v1"
local RACE_BACKUP_STORE = "RC_RaceChanges_v1"
local CONFIRM = "DELETE"
local CONVERT = "CONVERT"
local RUNE = "RaceRune"
local KICK_TEXT = "Switching character: please rejoin the game to continue."

local CharacterService = {}

-- Players already on their way out (one switch at a time).
local leaving: { [Player]: boolean } = {}

local function rejoin(player: Player)
	leaving[player] = true
	NetService:FireClient("Notify", player, { kind = "Info", textKey = "character.switching" })
	PlayerDataService:SaveNow(player)
	task.delay(1, function()
		if player.Parent ~= Players then
			return
		end
		if not RunService:IsStudio() then
			local ok, err = pcall(function()
				TeleportService:TeleportAsync(game.PlaceId, { player })
			end)
			if ok then
				return
			end
			log:Warn("rejoin teleport failed for %d: %s", player.UserId, tostring(err))
		end
		player:Kick(KICK_TEXT)
	end)
end

-- Load hook: apply a switch saved before the player left.
local function onLoad(player: Player, data: { [string]: any })
	local from = data.ActiveSlot
	if CharacterSlots.applyPending(data) then
		log:Info("user=%d switched character slot %d -> %d", player.UserId, from, data.ActiveSlot)
	end
	local race = data.PendingRace
	if race ~= nil and race ~= data.Race then
		local key = `Player_{player.UserId}_{os.time()}`
		local saved, err = pcall(function()
			DataStoreService:GetDataStore(RACE_BACKUP_STORE):SetAsync(key, data, { player.UserId })
		end)
		if not saved then
			log:Error(
				"race change backup failed for %d (%s); waits for the next load",
				player.UserId,
				tostring(err)
			)
			return
		end
		local before = data.Race
		CharacterSlots.convertRace(data, race)
		data.PendingRace = nil
		AuditLogService:Audit({
			actorUserId = player.UserId,
			action = "RaceConverted",
			target = race,
			details = { from = before, characters = CharacterSlots.count(data), backup = key },
		})
		log:Info("user=%d converted %s -> %s", player.UserId, tostring(before), race)
	elseif race ~= nil then
		data.PendingRace = nil
	end
end

-- D-116: the Race Conversion Rune, confirmed on its screen.
local function onConvert(player: Player, race: string, confirm: string): { [string]: any }
	local data = PlayerDataService:GetData(player)
	if data == nil or data.Race == nil then
		return { ok = false, reason = "notLoaded" }
	end
	if leaving[player] then
		return { ok = false, reason = "busy" }
	end
	if confirm ~= CONVERT then
		return { ok = false, reason = "confirm" }
	end
	if race == data.Race then
		return { ok = false, reason = "same" }
	end
	if data.PendingRace ~= nil then
		return { ok = false, reason = "pending" }
	end
	local entity = CombatService:GetPlayerEntity(player)
	if entity and CombatService:IsEntityInCombat(entity) then
		return { ok = false, reason = "combat" }
	end
	if (data.Stackables[RUNE] or 0) < 1 then
		return { ok = false, reason = "noRune" }
	end
	-- Synchronous: spend the rune and record the change together.
	data.Stackables[RUNE] -= 1
	data.PendingRace = race
	AuditLogService:Audit({
		actorUserId = player.UserId,
		action = "RaceRuneUsed",
		target = race,
		details = { from = data.Race },
	})
	rejoin(player)
	return { ok = true, rejoin = true }
end

local function list(data: { [string]: any }): { [string]: any }
	return {
		ok = true,
		slots = CharacterSlots.summary(data),
		max = CharacterSlots.MAX,
		race = data.Race,
	}
end

local function onRequest(player: Player, action: string, slot: number?, confirm: string?): { [string]: any }
	local data = PlayerDataService:GetData(player)
	if data == nil then
		return { ok = false, reason = "notLoaded" }
	end
	if action == "List" then
		return list(data)
	end
	if leaving[player] then
		return { ok = false, reason = "busy" }
	end
	if slot == nil or not CharacterSlots.validSlot(slot) then
		return { ok = false, reason = "slot" }
	end
	local entity = CombatService:GetPlayerEntity(player)
	if entity and CombatService:IsEntityInCombat(entity) then
		return { ok = false, reason = "combat" }
	end
	if action == "Switch" then
		if slot == data.ActiveSlot then
			return { ok = false, reason = "same" }
		end
		data.PendingSlot = slot
		local isNew = (data.Characters or {})[tostring(slot)] == nil
		AuditLogService:Audit({
			actorUserId = player.UserId,
			action = "CharacterSwitch",
			target = tostring(slot),
			details = { from = data.ActiveSlot, new = isNew },
		})
		rejoin(player)
		return { ok = true, rejoin = true }
	end
	-- Delete.
	if confirm ~= CONFIRM then
		return { ok = false, reason = "confirm" }
	end
	local isActive = slot == data.ActiveSlot
	local blob = if isActive then CharacterSlots.extract(data) else (data.Characters or {})[tostring(slot)]
	if blob == nil or blob.Job == nil then
		return { ok = false, reason = "empty" }
	end
	local backupKey = `Player_{player.UserId}_s{slot}_{os.time()}`
	local saved, err = pcall(function()
		DataStoreService:GetDataStore(BACKUP_STORE):SetAsync(backupKey, blob, { player.UserId })
	end)
	if not saved then
		log:Error("character backup failed for %d: %s", player.UserId, tostring(err))
		return { ok = false, reason = "backup" }
	end
	-- Re-read after the yield: the profile may have changed meanwhile.
	data = PlayerDataService:GetData(player)
	if data == nil then
		return { ok = false, reason = "notLoaded" }
	end
	local ok, reason, needsRejoin = CharacterSlots.delete(data, slot)
	if not ok then
		return { ok = false, reason = reason }
	end
	AuditLogService:Audit({
		actorUserId = player.UserId,
		action = "CharacterDelete",
		target = tostring(slot),
		details = { job = blob.Job, level = blob.Level, backup = backupKey, last = data.Race == nil },
	})
	if needsRejoin then
		rejoin(player)
		return { ok = true, rejoin = true }
	end
	PlayerDataService:PushSnapshot(player)
	return list(data)
end

function CharacterService:Init()
	PlayerDataService:AddLoadHook(onLoad)
	NetService:Handle("CharacterSlots", onRequest)
	NetService:Handle("ConvertRace", onConvert)
end

function CharacterService:Start()
	Players.PlayerRemoving:Connect(function(player)
		leaving[player] = nil
	end)
end

return CharacterService
