--!strict
--[[
	ProfileValidator — validate and repair a loaded profile in place
	(docs/DATA_MODEL.md §3). Runs on every load, after migrations.

	    local repairs = ProfileValidator.repair(data)

	Returns a list of human-readable repair notes (empty = profile was valid).
	The caller logs non-empty results to the security log.

	Phase 2 scope: structure, progression and every field whose rules are
	known now. Definition-dependent checks (item DefIds, skill/job match, quest
	ids) are added by the phases that introduce those definitions.

	Pure module: no engine APIs beyond requires (tests load it via tests/pure/loader).
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Constants = require(Shared.Constants)
local Enums = require(Shared.Enums)
local XPTable = require(Shared.Logic.XPTable)
local FacePresets = require(Shared.Definitions.FacePresets)
local ProfileTemplate = require(script.Parent.ProfileTemplate)

local MAX_NOTES = 25
local MAX_KEY_LENGTH = 64
local MAX_REWARD_ID_LENGTH = 128
local MAX_STACK = 1000000000
local MAX_CURRENCY = 1000000000000

local ProfileValidator = {}

type Data = { [string]: any }

local function isFinite(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value do
		copy[k] = deepCopy(v)
	end
	return copy
end

local function isShortString(value: any, maxLength: number): boolean
	return type(value) == "string" and #value > 0 and #value <= maxLength
end

-- Builds a repair context that collects bounded notes.
local function newNotes(): ({ string }, (string) -> ())
	local notes: { string } = {}
	local overflow = 0
	local function note(message: string)
		if #notes < MAX_NOTES then
			table.insert(notes, message)
		else
			overflow += 1
			notes[MAX_NOTES] = `... and {overflow} more`
		end
	end
	return notes, note
end

-- Coerces t[key] to an integer in [min, max]; non-numbers become `default`.
local function fixInt(
	t: Data,
	key: string,
	min: number,
	max: number,
	default: number,
	path: string,
	note: (string) -> ()
)
	local value = t[key]
	local fixed
	if not isFinite(value) then
		fixed = default
	else
		fixed = math.clamp(math.floor(value), min, max)
	end
	if fixed ~= value then
		note(`{path}: {tostring(value)} -> {fixed}`)
		t[key] = fixed
	end
end

-- Keeps only keys of a struct that exist in `allowed` (name -> true).
local function dropUnknownKeys(t: Data, allowed: { [string]: any }, path: string, note: (string) -> ())
	for key in t do
		if type(key) ~= "string" or allowed[key] == nil then
			note(`{path}: removed unknown key '{tostring(key)}'`)
			t[key] = nil
		end
	end
end

-- Filters a map in place, keeping entries for which keep(key, value) is true.
local function filterMap(t: Data, path: string, note: (string) -> (), keep: (any, any) -> boolean)
	local removed = 0
	for key, value in t do
		if not keep(key, value) then
			t[key] = nil
			removed += 1
		end
	end
	if removed > 0 then
		note(`{path}: removed {removed} invalid entr{if removed == 1 then "y" else "ies"}`)
	end
end

local function isSetEntry(key: any, value: any): boolean
	return isShortString(key, MAX_KEY_LENGTH) and value == true
end

--------------------------------------------------------------------------------
-- Section repairs
--------------------------------------------------------------------------------

local function repairTopLevel(data: Data, template: Data, note: (string) -> ())
	local optional = ProfileTemplate.OPTIONAL_KEYS
	for key in data do
		if type(key) ~= "string" or (template[key] == nil and optional[key] == nil) then
			note(`removed unknown field '{tostring(key)}'`)
			data[key] = nil
		end
	end
	for key, default in template do
		local value = data[key]
		if value == nil then
			note(`filled missing field '{key}'`)
			data[key] = deepCopy(default)
		elseif type(value) ~= type(default) then
			note(`replaced '{key}' of wrong type {type(value)}`)
			data[key] = deepCopy(default)
		end
	end
end

local function repairIdentity(data: Data, note: (string) -> ())
	if data.Race ~= nil and not Enums.has(Enums.Race, data.Race) then
		note(`Race: invalid '{tostring(data.Race)}' cleared`)
		data.Race = nil
	end
	if data.Job ~= nil and not Enums.has(Enums.Job, data.Job) then
		note(`Job: invalid '{tostring(data.Job)}' cleared`)
		data.Job = nil
	end
	-- Face preset must exist and, once a race is chosen, belong to that race.
	local preset = data.FacePreset
	local validPreset = if data.Race ~= nil
		then FacePresets.isValidFor(preset, data.Race)
		else FacePresets.get(preset) ~= nil
	if not validPreset then
		local fallback = if data.Race ~= nil then FacePresets.defaultFor(data.Race) else 1
		note(`FacePreset: {tostring(preset)} -> {fallback}`)
		data.FacePreset = fallback
	end
	fixInt(data, "CreatedAt", 0, math.huge, 0, "CreatedAt", note)
	fixInt(data, "LastLoginAt", 0, math.huge, 0, "LastLoginAt", note)
end

local function repairProgression(data: Data, note: (string) -> ())
	fixInt(data, "Level", Constants.Level.Min, Constants.Level.Max, 0, "Level", note)

	local toNext = XPTable.toNext(data.Level)
	local maxExperience = if toNext > 0 then toNext - 1 else 0
	fixInt(data, "Experience", 0, maxExperience, 0, "Experience", note)

	-- Lifetime total can never be below what the current level/XP implies.
	local minimumTotal = XPTable.totalToReach(data.Level) + data.Experience
	fixInt(data, "TotalExperience", minimumTotal, math.huge, minimumTotal, "TotalExperience", note)
end

local function repairSkills(data: Data, note: (string) -> ())
	filterMap(data.OwnedSkills, "OwnedSkills", note, isSetEntry)

	local equipped = data.EquippedSkills
	dropUnknownKeys(equipped, { Regular = true, Special = true }, "EquippedSkills", note)
	if type(equipped.Regular) ~= "table" then
		note("EquippedSkills.Regular: reset")
		equipped.Regular = {}
	end
	-- Rebuild Regular as a clean, duplicate-free array of at most N skill ids.
	local clean, seen = {}, {}
	for index = 1, Constants.Loadout.RegularSlots do
		local id = equipped.Regular[index]
		if isShortString(id, MAX_KEY_LENGTH) and not seen[id] then
			seen[id] = true
			table.insert(clean, id)
		end
	end
	local originalCount = 0
	for _ in equipped.Regular do
		originalCount += 1
	end
	if #clean ~= originalCount then
		note(`EquippedSkills.Regular: kept {#clean} of {originalCount}`)
	end
	equipped.Regular = clean
	if equipped.Special ~= nil and not isShortString(equipped.Special, MAX_KEY_LENGTH) then
		note("EquippedSkills.Special: cleared invalid value")
		equipped.Special = nil
	end
end

local function repairItems(data: Data, note: (string) -> ())
	-- Deep item validation (DefIds, rarity, attributes, enhancement) arrives in Phase 7.
	filterMap(data.Inventory, "Inventory", note, function(guid, item)
		return isShortString(guid, MAX_KEY_LENGTH) and type(item) == "table" and item.Guid == guid
	end)
	filterMap(data.Equipment, "Equipment", note, function(slot, guid)
		return Enums.has(Enums.ItemSlot, slot) and type(guid) == "string" and data.Inventory[guid] ~= nil
	end)
	filterMap(data.Stackables, "Stackables", note, function(id, count)
		return isShortString(id, MAX_KEY_LENGTH)
			and isFinite(count)
			and count % 1 == 0
			and count >= 0
			and count <= MAX_STACK
	end)

	local wallet = data.Wallet
	dropUnknownKeys(wallet, { Gold = true, PvPMarks = true }, "Wallet", note)
	fixInt(wallet, "Gold", 0, MAX_CURRENCY, 0, "Wallet.Gold", note)
	fixInt(wallet, "PvPMarks", 0, MAX_CURRENCY, 0, "Wallet.PvPMarks", note)
end

local function repairQuestsAndCosmetics(data: Data, note: (string) -> ())
	filterMap(data.QuestState, "QuestState", note, function(id, state)
		return isShortString(id, MAX_KEY_LENGTH) and type(state) == "table"
	end)
	filterMap(data.StoryFlags, "StoryFlags", note, isSetEntry)
	filterMap(data.ClaimedRewardIds, "ClaimedRewardIds", note, function(id, claimedAt)
		return isShortString(id, MAX_REWARD_ID_LENGTH) and isFinite(claimedAt) and claimedAt >= 0
	end)
	filterMap(data.Titles, "Titles", note, isSetEntry)
	filterMap(data.Cosmetics, "Cosmetics", note, isSetEntry)
	filterMap(data.EquippedCosmetics, "EquippedCosmetics", note, function(slot, id)
		return isShortString(slot, MAX_KEY_LENGTH)
			and isShortString(id, MAX_KEY_LENGTH)
			and data.Cosmetics[id] == true
	end)

	local title = data.EquippedTitle
	if title ~= nil and not (isShortString(title, MAX_KEY_LENGTH) and data.Titles[title] == true) then
		note("EquippedTitle: cleared (not owned)")
		data.EquippedTitle = nil
	end
end

local function repairPvP(data: Data, template: Data, note: (string) -> ())
	local stats = data.PvPStats
	dropUnknownKeys(stats, template.PvPStats, "PvPStats", note)
	fixInt(stats, "Victories", 0, math.huge, 0, "PvPStats.Victories", note)
	fixInt(stats, "Defeats", 0, math.huge, 0, "PvPStats.Defeats", note)
	fixInt(stats, "Participations", 0, math.huge, 0, "PvPStats.Participations", note)
	if type(stats.RecentVictims) ~= "table" then
		note("PvPStats.RecentVictims: reset")
		stats.RecentVictims = {}
	end
	filterMap(stats.RecentVictims, "PvPStats.RecentVictims", note, function(userId, at)
		return isShortString(userId, 20) and isFinite(at) and at >= 0
	end)
	if type(stats.DailyCredit) ~= "table" then
		note("PvPStats.DailyCredit: reset")
		stats.DailyCredit = { Day = 0, Count = 0 }
	end
	dropUnknownKeys(stats.DailyCredit, { Day = true, Count = true }, "PvPStats.DailyCredit", note)
	fixInt(stats.DailyCredit, "Day", 0, math.huge, 0, "PvPStats.DailyCredit.Day", note)
	fixInt(stats.DailyCredit, "Count", 0, math.huge, 0, "PvPStats.DailyCredit.Count", note)
end

local function repairMisc(data: Data, template: Data, note: (string) -> ())
	filterMap(data.EventProgress, "EventProgress", note, function(id, progress)
		return isShortString(id, MAX_REWARD_ID_LENGTH) and type(progress) == "table"
	end)
	filterMap(data.Restrictions, "Restrictions", note, function(id, untilTime)
		return isShortString(id, MAX_KEY_LENGTH) and isFinite(untilTime) and untilTime >= 0
	end)

	local settings = data.Settings
	dropUnknownKeys(settings, template.Settings, "Settings", note)
	fixInt(settings, "MusicVolume", 0, 100, template.Settings.MusicVolume, "Settings.MusicVolume", note)
	fixInt(settings, "SfxVolume", 0, 100, template.Settings.SfxVolume, "Settings.SfxVolume", note)
	if not Enums.has({ "Auto", "Low", "Medium", "High" }, settings.GraphicsTier) then
		note("Settings.GraphicsTier: reset")
		settings.GraphicsTier = template.Settings.GraphicsTier
	end
	if type(settings.ShowDamageNumbers) ~= "boolean" then
		note("Settings.ShowDamageNumbers: reset")
		settings.ShowDamageNumbers = template.Settings.ShowDamageNumbers
	end

	filterMap(data.Counters, "Counters", note, function(key, value)
		return ProfileTemplate.COUNTER_KEYS[key] == true and isFinite(value) and value >= 0
	end)
end

--------------------------------------------------------------------------------

--[[
	Repairs `data` in place and returns repair notes. `data` must already be at
	the current schema version (run Migrations first).
]]
function ProfileValidator.repair(data: Data): { string }
	local notes, note = newNotes()
	local template = ProfileTemplate.new()

	repairTopLevel(data, template, note)
	data.SchemaVersion = ProfileTemplate.SCHEMA_VERSION
	repairIdentity(data, note)
	repairProgression(data, note)
	repairSkills(data, note)
	repairItems(data, note)
	repairQuestsAndCosmetics(data, note)
	repairPvP(data, template, note)
	repairMisc(data, template, note)

	return notes
end

return table.freeze(ProfileValidator)
