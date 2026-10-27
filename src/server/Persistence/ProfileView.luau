--!strict
--[[
	ProfileView — builds the replicated view of a profile for its owner
	(docs/DATA_MODEL.md §6). Only whitelisted fields are copied; internal
	fields (ClaimedRewardIds, RecentVictims, Restrictions, Counters, timestamps)
	are never sent.

	The output must match the `ProfileSnapshot` / `ProgressionUpdate` schemas in
	shared/Net/Registry. Later phases extend the view together with the schema.

	Pure module: no engine APIs beyond requires (tests load it via tests/pure/loader).
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Constants = require(Shared.Constants)
local XPTable = require(Shared.Logic.XPTable)
local SkillDefinitions = require(Shared.Definitions.SkillDefinitions)
local PassiveDefinitions = require(Shared.Definitions.PassiveDefinitions)
local ItemDefinitions = require(Shared.Definitions.ItemDefinitions)
local QuestDefinitions = require(Shared.Definitions.QuestDefinitions)

local ProfileView = {}

-- Learned skill id -> rank (unknown ids are never sent).
local function ownedSkills(data: { [string]: any }): { [string]: number }
	local out = {}
	local owned = if type(data.OwnedSkills) == "table" then data.OwnedSkills else {}
	for _, ids in { SkillDefinitions.IDS, PassiveDefinitions.IDS } do
		for _, id in ids do
			local rank = owned[id]
			if type(rank) == "number" and rank >= 1 then
				out[id] = rank
			end
		end
	end
	return out
end

local function equippedSkills(data: { [string]: any }): { [string]: any }
	local equipped = if type(data.EquippedSkills) == "table" then data.EquippedSkills else {}
	local regular = {}
	for _, id in if type(equipped.Regular) == "table" then equipped.Regular else {} do
		if SkillDefinitions.get(id) and #regular < Constants.Loadout.RegularSlots then
			table.insert(regular, id)
		end
	end
	return {
		Regular = regular,
		Special = if SkillDefinitions.get(equipped.Special) then equipped.Special else nil,
	}
end

-- Phase 7 (D-64): an item as its owner sees it (no Source).
function ProfileView.item(item: { [string]: any }): { [string]: any }
	local attributes = {}
	for _, attribute in item.Attributes do
		table.insert(attributes, { Stat = attribute.Stat, Value = attribute.Value })
	end
	return {
		Guid = item.Guid,
		DefId = item.DefId,
		Rarity = item.Rarity,
		ItemLevel = item.ItemLevel,
		Attributes = attributes,
		Enhancement = item.Enhancement,
		Locked = item.Locked,
		CreatedAt = item.CreatedAt,
		Durability = item.Durability,
	}
end

-- Items whose definition still exists (validated on load), at most `cap`.
function ProfileView.inventory(data: { [string]: any }, cap: number?): { [string]: any }
	local out = {}
	local count = 0
	for guid, item in if type(data.Inventory) == "table" then data.Inventory else {} do
		if count >= (cap or 200) then
			break
		end
		if ItemDefinitions.get(item.DefId) then
			out[guid] = ProfileView.item(item)
			count += 1
		end
	end
	return out
end

function ProfileView.equipment(data: { [string]: any }): { [string]: string }
	return table.clone(if type(data.Equipment) == "table" then data.Equipment else {})
end

function ProfileView.stackables(data: { [string]: any }): { [string]: number }
	local out = {}
	for id, count in if type(data.Stackables) == "table" then data.Stackables else {} do
		if ItemDefinitions.stackable(id) and count > 0 then
			out[id] = count
		end
	end
	return out
end

function ProfileView.wallet(data: { [string]: any }): { Gold: number, PvPMarks: number }
	local wallet = if type(data.Wallet) == "table" then data.Wallet else {}
	return { Gold = wallet.Gold or 0, PvPMarks = wallet.PvPMarks or 0, MallPoints = wallet.MallPoints or 0 }
end

-- D-93: running buffs, id -> seconds left.
function ProfileView.buffs(data: { [string]: any }): { [string]: number }
	local out = {}
	local now = os.time()
	for id, expires in data.Buffs or {} do
		if type(expires) == "number" and expires > now then
			out[id] = math.min(expires - now, 6 * 3600)
		end
	end
	return out
end

-- D-90: the attribute points spent and seconds until the next free reset.
function ProfileView.attributes(data: { [string]: any }): { [string]: any }
	local a = data.Attributes or {}
	return {
		Attributes = {
			REC = a.REC or 0,
			INT = a.INT or 0,
			WIS = a.WIS or 0,
			STR = a.STR or 0,
			AGI = a.AGI or 0,
		},
		ResetIn = math.max(0, (data.AttributeResetAt or 0) + 24 * 3600 - os.time()),
		-- D-120: permanent bonus points (Fortune Wheel).
		Bonus = {
			REC = (data.BonusAttributes or {}).REC or 0,
			INT = (data.BonusAttributes or {}).INT or 0,
			WIS = (data.BonusAttributes or {}).WIS or 0,
			STR = (data.BonusAttributes or {}).STR or 0,
			AGI = (data.BonusAttributes or {}).AGI or 0,
		},
	}
end

function ProfileView.progression(data: { [string]: any }, levelsGained: number?): { [string]: any }
	return {
		Level = data.Level,
		Experience = data.Experience,
		XPToNext = XPTable.toNext(data.Level),
		LevelsGained = levelsGained or 0,
	}
end

--[[
	Phase 11 (D-73): the owner's quests (status, step counts, interactables
	found), story flags, titles, equipped title and cosmetics. Unknown ids
	are never sent.
]]
function ProfileView.quests(data: { [string]: any }): { [string]: any }
	local quests = {}
	local state = if type(data.QuestState) == "table" then data.QuestState else {}
	for _, id in QuestDefinitions.IDS do
		local progress = state[id]
		if type(progress) == "table" then
			local found = {}
			for target in progress.Found or {} do
				if QuestDefinitions.Interactables[target] then
					table.insert(found, target)
				end
			end
			table.sort(found)
			quests[id] =
				{ Status = progress.Status, Objectives = table.clone(progress.Objectives), Found = found }
		end
	end
	local function set(source: any, known: { [string]: any }): { string }
		local out = {}
		if type(source) == "table" then
			for id, value in source do
				if value == true and known[id] ~= nil then
					table.insert(out, id)
				end
			end
		end
		table.sort(out)
		return out
	end
	local flags = {}
	for _, flag in QuestDefinitions.FLAGS do
		flags[flag] = true
	end
	local title = data.EquippedTitle
	return {
		Quests = quests,
		Flags = set(data.StoryFlags, flags),
		Titles = set(data.Titles, QuestDefinitions.Titles),
		EquippedTitle = if type(title) == "string" and QuestDefinitions.Titles[title] then title else nil,
		Cosmetics = set(data.Cosmetics, QuestDefinitions.Cosmetics),
	}
end

function ProfileView.snapshot(data: { [string]: any }): { [string]: any }
	return {
		Race = data.Race,
		Job = data.Job,
		FacePreset = data.FacePreset,
		HeadStyle = data.HeadStyle,
		SkinTone = data.SkinTone,
		HairColor = data.HairColor,
		Level = data.Level,
		Experience = data.Experience,
		XPToNext = XPTable.toNext(data.Level),
		OwnedSkills = ownedSkills(data),
		EquippedSkills = equippedSkills(data),
		Inventory = ProfileView.inventory(data),
		Equipment = ProfileView.equipment(data),
		Stackables = ProfileView.stackables(data),
		Wallet = ProfileView.wallet(data),
		-- D-76: PvP record (victory titles progress in the quest log).
		PvP = {
			Victories = if type(data.PvPStats) == "table" then data.PvPStats.Victories or 0 else 0,
			Defeats = if type(data.PvPStats) == "table" then data.PvPStats.Defeats or 0 else 0,
		},
		Quests = ProfileView.quests(data),
		-- D-90.
		Attributes = ProfileView.attributes(data),
		-- D-93.
		Buffs = ProfileView.buffs(data),
		-- D-74: where the player moved their HUD pieces.
		HudLayout = if type(data.Settings) == "table" and type(data.Settings.HudLayout) == "table"
			then table.clone(data.Settings.HudLayout)
			else {},
	}
end

return table.freeze(ProfileView)
