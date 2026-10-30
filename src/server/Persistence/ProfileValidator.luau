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
local BuffRules = require(Shared.Logic.BuffRules)
local AttributeRules = require(Shared.Logic.AttributeRules)
local Complexion = require(Shared.Definitions.Complexion)
local FacePresets = require(Shared.Definitions.FacePresets)
local SkillDefinitions = require(Shared.Definitions.SkillDefinitions)
local PassiveDefinitions = require(Shared.Definitions.PassiveDefinitions)
local ItemDefinitions = require(Shared.Definitions.ItemDefinitions)
local ItemRules = require(Shared.Logic.ItemRules)
local QuestRules = require(Shared.Logic.QuestRules)
local HudSlots = require(Shared.Layout.HudSlots)
local PotionRules = require(Shared.Logic.PotionRules)
local ProfileTemplate = require(script.Parent.ProfileTemplate)

local MAX_NOTES = 25
local MAX_KEY_LENGTH = 64
local MAX_REWARD_ID_LENGTH = 128
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
	if not Enums.has(Enums.HeadStyle, data.HeadStyle) then
		note(`HeadStyle: invalid '{tostring(data.HeadStyle)}' -> Man`)
		data.HeadStyle = "Man"
	end
	local complexionFields: { [string]: string } = { SkinTone = "Skin", HairColor = "Hair" }
	for field, kind in complexionFields do
		if type(data[field]) ~= "string" or not Complexion.isValid(kind, data[field]) then
			if data[field] ~= nil then
				note(`{field}: invalid '{tostring(data[field])}' -> Default`)
			end
			data[field] = Complexion.DEFAULT
		end
	end
	fixInt(data, "CreatedAt", 0, math.huge, 0, "CreatedAt", note)
	fixInt(data, "LastLoginAt", 0, math.huge, 0, "LastLoginAt", note)
	-- D-128
	fixInt(data, "PuzzleDay", 0, math.huge, 0, "PuzzleDay", note)
	-- D-122: auction escrow entries (resolved by AuctionService on load).
	for key, entry in data.Escrow do
		if
			type(key) ~= "string"
			or type(entry) ~= "table"
			or (entry.Kind ~= "List" and entry.Kind ~= "Bid")
			or type(entry.ListingId) ~= "string"
		then
			note(`Escrow: dropped '{tostring(key)}'`)
			data.Escrow[key] = nil
		end
	end
	-- D-121: trade history (newest first, at most 20 entries).
	do
		local kept = {}
		for _, e in data.TradeHistory do
			if
				#kept < 20
				and type(e) == "table"
				and isShortString(e.Id, 40)
				and isFinite(e.At)
				and isFinite(e.With)
				and isShortString(e.WithName, 40)
				and isShortString(e.Gave, 600)
				and isShortString(e.Got, 600)
			then
				table.insert(
					kept,
					{ Id = e.Id, At = e.At, With = e.With, WithName = e.WithName, Gave = e.Gave, Got = e.Got }
				)
			end
		end
		if #kept ~= #data.TradeHistory then
			note("TradeHistory: dropped bad entries")
		end
		data.TradeHistory = kept
	end
	-- D-120: Fortune Wheel bonus points and free spins.
	local bonus = data.BonusAttributes
	dropUnknownKeys(
		bonus,
		{ REC = true, INT = true, WIS = true, STR = true, AGI = true },
		"BonusAttributes",
		note
	)
	for _, id in { "REC", "INT", "WIS", "STR", "AGI" } do
		fixInt(bonus, id, 0, 50, 0, `BonusAttributes.{id}`, note)
	end
	dropUnknownKeys(data.Roulette, { Day = true, Used = true }, "Roulette", note)
	fixInt(data.Roulette, "Day", 0, math.huge, 0, "Roulette.Day", note)
	fixInt(data.Roulette, "Used", 0, 1000, 0, "Roulette.Used", note)
	-- D-119: the Warden's chain.
	do
		local ChainRules = require(Shared.Logic.ChainRules) :: any
		local fixed, changed = ChainRules.repair(data.Chain)
		if changed and type(data.Chain) == "table" then
			note("Chain: repaired")
		end
		data.Chain = fixed
	end
	-- D-117: the Exchanger's daily counts.
	local exchange = data.ExchangeDay
	if type(exchange) == "table" then
		dropUnknownKeys(exchange, { Day = true, ToGold = true, ToMallPoints = true }, "ExchangeDay", note)
		fixInt(exchange, "Day", 0, math.huge, 0, "ExchangeDay.Day", note)
		fixInt(exchange, "ToGold", 0, math.huge, 0, "ExchangeDay.ToGold", note)
		fixInt(exchange, "ToMallPoints", 0, math.huge, 0, "ExchangeDay.ToMallPoints", note)
	end
	-- D-111: the last system reset this profile took.
	fixInt(data, "ResetVersion", 0, math.huge, 0, "ResetVersion", note)
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

-- D-90: whole points on the five attributes, never more than the level gives.
local function repairAttributes(data: Data, note: (string) -> ())
	-- D-131: Tower points (spent like level points) and best clear times.
	local TowerRules = require(Shared.Logic.TowerRules) :: any
	fixInt(data, "TowerPoints", 0, TowerRules.MAX_POINTS, 0, "TowerPoints", note)
	if type(data.TowerBest) ~= "table" then
		data.TowerBest = {}
		note("TowerBest: reset")
	end
	for id, tenths in data.TowerBest do
		if
			TowerRules.get(id) == nil
			or type(tenths) ~= "number"
			or tenths ~= tenths
			or tenths < 1
			or tenths % 1 ~= 0
		then
			data.TowerBest[id] = nil
			note(`TowerBest.{tostring(id)}: dropped`)
		end
	end
	local attributes, changed = AttributeRules.repair(data.Attributes, data.Level, data.TowerPoints)
	if changed then
		note("Attributes: repaired")
	end
	data.Attributes = attributes
	fixInt(data, "AttributeResetAt", 0, math.huge, 0, "AttributeResetAt", note)
end

local function repairSkills(data: Data, note: (string) -> ())
	-- Phase 5 (D-45): real skills of the character's own job, a whole rank
	-- within 1..maxRank, and the skill above it in the tree learned too.
	filterMap(data.OwnedSkills, "OwnedSkills", note, function(id, rank)
		-- Tree skills and class passives (D-104) share the map.
		local skill: any = SkillDefinitions.get(id) or PassiveDefinitions.get(id)
		return skill ~= nil
			and skill.job == data.Job
			and isFinite(rank)
			and rank % 1 == 0
			and rank >= 1
			and rank <= skill.maxRank
	end)
	for tier = 2, SkillDefinitions.TIERS do
		for id in data.OwnedSkills do
			local skill = SkillDefinitions.get(id)
			if
				skill
				and skill.tier == tier
				and skill.requires
				and data.OwnedSkills[skill.requires] == nil
			then
				note(`OwnedSkills: removed {id} (requires {skill.requires})`)
				data.OwnedSkills[id] = nil
			end
		end
	end

	local equipped = data.EquippedSkills
	dropUnknownKeys(equipped, { Regular = true, Special = true }, "EquippedSkills", note)
	if type(equipped.Regular) ~= "table" then
		note("EquippedSkills.Regular: reset")
		equipped.Regular = {}
	end
	-- Rebuild Regular as a clean, duplicate-free array of at most N skill ids.
	local clean, seen = {}, {}
	local function owns(id: any, slotType: string): boolean
		local skill = SkillDefinitions.get(id)
		-- Basic skills (Auto Attack) are known without being owned.
		return skill ~= nil
			and skill.type == slotType
			and (data.OwnedSkills[id] ~= nil or SkillDefinitions.isBasic(skill))
	end
	for index = 1, Constants.Loadout.RegularSlots do
		local id = equipped.Regular[index]
		if isShortString(id, MAX_KEY_LENGTH) and not seen[id] and owns(id, "Regular") then
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
	if equipped.Special ~= nil and not owns(equipped.Special, "Special") then
		note("EquippedSkills.Special: cleared invalid value")
		equipped.Special = nil
	end
end

-- An item about to be dropped, in full, so support can restore it (DATA_MODEL.md §3).
local function describeItem(item: any): string
	if type(item) ~= "table" then
		return tostring(item)
	end
	local attributes = {}
	if type(item.Attributes) == "table" then
		for _, attribute in item.Attributes do
			if type(attribute) == "table" then
				table.insert(attributes, `{tostring(attribute.Stat)}={tostring(attribute.Value)}`)
			end
		end
	end
	return `DefId={tostring(item.DefId)} Rarity={tostring(item.Rarity)} ItemLevel={tostring(item.ItemLevel)} +{tostring(
		item.Enhancement
	)} Source={tostring(item.Source)} [{table.concat(attributes, ",")}]`
end

local function repairItems(data: Data, note: (string) -> ())
	-- Phase 7 (D-64): every item checked against its definition and pool.
	for guid, item in data.Inventory do
		local keep, notes = ItemRules.repairItem(guid, item)
		if not keep then
			note(`Inventory: dropped {tostring(guid)} ({notes[1]}): {describeItem(item)}`)
			data.Inventory[guid] = nil
		elseif #notes > 0 then
			note(`Inventory: {guid}: {table.concat(notes, "; ")}`)
		end
	end
	-- Equipment: a real slot, an owned item that fits it, never two slots.
	local used = {}
	filterMap(data.Equipment, "Equipment", note, function(slot, guid)
		local item = type(guid) == "string" and data.Inventory[guid]
		local def = item and ItemDefinitions.get(item.DefId)
		if
			not Enums.has(Enums.ItemSlot, slot)
			or def == nil
			or not ItemRules.fitsSlot(def, slot)
			or used[guid]
		then
			return false
		end
		used[guid] = true
		return true
	end)
	-- D-68: the off-hand must go with the main hand (shield / second sword).
	local function defIn(slot: string): any
		local guid = data.Equipment[slot]
		local item = guid and data.Inventory[guid]
		return item and ItemDefinitions.get(item.DefId)
	end
	if not ItemRules.handsCompatible(defIn("Weapon"), defIn("OffHand")) then
		note("Equipment.OffHand: cleared (doesn't go with the main hand)")
		data.Equipment.OffHand = nil
	end
	filterMap(data.Stackables, "Stackables", note, function(id, count)
		local def = ItemDefinitions.stackable(id)
		return def ~= nil and isFinite(count) and count % 1 == 0 and count >= 0 and count <= def.maxStack
	end)

	local wallet = data.Wallet
	dropUnknownKeys(
		wallet,
		{ Gold = true, PvPMarks = true, MallPoints = true, PurchasedMallPoints = true },
		"Wallet",
		note
	)
	fixInt(wallet, "Gold", 0, MAX_CURRENCY, 0, "Wallet.Gold", note)
	fixInt(wallet, "PvPMarks", 0, MAX_CURRENCY, 0, "Wallet.PvPMarks", note)
	fixInt(wallet, "MallPoints", 0, MAX_CURRENCY, 0, "Wallet.MallPoints", note)
	fixInt(wallet, "PurchasedMallPoints", 0, math.huge, 0, "Wallet.PurchasedMallPoints", note)
	-- D-93: known buffs, still running.
	local buffs, buffsChanged = BuffRules.repair(data.Buffs, os.time())
	if buffsChanged then
		note("Buffs: repaired")
	end
	data.Buffs = buffs
end

local function repairQuestsAndCosmetics(data: Data, note: (string) -> ())
	filterMap(data.QuestState, "QuestState", note, function(id, state)
		return isShortString(id, MAX_KEY_LENGTH) and type(state) == "table"
	end)
	-- Phase 11 (D-73): known quests only, counts within each step's target.
	for _, message in QuestRules.repair(data.QuestState) do
		note(message)
	end
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

-- D-115: the stored characters. Each is checked like a whole profile (in
-- a scratch copy), so a bad stored character is repaired the same way.
local repairCharacters: (data: Data, note: (string) -> ()) -> ()

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
	if not PotionRules.isChoice(settings.QuickPotion) then
		if settings.QuickPotion ~= nil then
			note("Settings.QuickPotion: reset")
		end
		settings.QuickPotion = "Auto"
	end
	if type(settings.ShowDamageNumbers) ~= "boolean" then
		note("Settings.ShowDamageNumbers: reset")
		settings.ShowDamageNumbers = template.Settings.ShowDamageNumbers
	end
	-- D-74: known HUD pieces, centres within the screen (missing in older saves).
	local hud = HudSlots.sanitize(settings.HudLayout)
	local before, after = 0, 0
	if type(settings.HudLayout) == "table" then
		for _ in settings.HudLayout do
			before += 1
		end
	end
	for _ in hud do
		after += 1
	end
	if type(settings.HudLayout) ~= "table" or before ~= after then
		note("Settings.HudLayout: repaired")
	end
	settings.HudLayout = hud

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
	repairAttributes(data, note)
	repairSkills(data, note)
	repairItems(data, note)
	repairQuestsAndCosmetics(data, note)
	repairPvP(data, template, note)
	repairMisc(data, template, note)
	repairCharacters(data, note)

	return notes
end

function repairCharacters(data: Data, note: (string) -> ())
	local CharacterSlots = require(script.Parent.CharacterSlots) :: any
	if not CharacterSlots.validSlot(data.ActiveSlot) then
		note(`ActiveSlot: {tostring(data.ActiveSlot)} -> 1`)
		data.ActiveSlot = 1
	end
	if data.PendingSlot ~= nil and not CharacterSlots.validSlot(data.PendingSlot) then
		note("PendingSlot: cleared")
		data.PendingSlot = nil
	end
	if data.PendingRace ~= nil and (not Enums.has(Enums.Race, data.PendingRace) or data.Race == nil) then
		note("PendingRace: cleared")
		data.PendingRace = nil
	end
	local kept = {}
	for key, blob in data.Characters do
		local slot = tonumber(key)
		if type(key) ~= "string" or not CharacterSlots.validSlot(slot) or slot == data.ActiveSlot then
			note(`Characters: removed slot '{tostring(key)}'`)
		elseif type(blob) ~= "table" or blob.Job == nil then
			note(`Characters.{key}: not a character, removed`)
		elseif data.Race == nil then
			note(`Characters.{key}: no realm, removed`)
		else
			local scratch = ProfileTemplate.new()
			scratch.Race = data.Race
			CharacterSlots.install(scratch, blob)
			for _, line in ProfileValidator.repair(scratch) do
				note(`Characters.{key}: {line}`)
			end
			if scratch.Job == nil then
				note(`Characters.{key}: invalid class, removed`)
			else
				kept[key] = CharacterSlots.extract(scratch)
			end
		end
	end
	data.Characters = kept
end

return table.freeze(ProfileValidator)
