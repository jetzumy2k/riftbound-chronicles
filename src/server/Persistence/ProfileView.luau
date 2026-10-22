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
local XPTable = require(Shared.Logic.XPTable)
local SkillDefinitions = require(Shared.Definitions.SkillDefinitions)
local ItemDefinitions = require(Shared.Definitions.ItemDefinitions)

local ProfileView = {}

-- Learned skill id -> rank (unknown ids are never sent).
local function ownedSkills(data: { [string]: any }): { [string]: number }
	local out = {}
	local owned = if type(data.OwnedSkills) == "table" then data.OwnedSkills else {}
	for _, id in SkillDefinitions.IDS do
		local rank = owned[id]
		if type(rank) == "number" and rank >= 1 then
			out[id] = rank
		end
	end
	return out
end

local function equippedSkills(data: { [string]: any }): { [string]: any }
	local equipped = if type(data.EquippedSkills) == "table" then data.EquippedSkills else {}
	local regular = {}
	for _, id in if type(equipped.Regular) == "table" then equipped.Regular else {} do
		if SkillDefinitions.get(id) and #regular < 3 then
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
	return { Gold = wallet.Gold or 0, PvPMarks = wallet.PvPMarks or 0 }
end

function ProfileView.progression(data: { [string]: any }, levelsGained: number?): { [string]: any }
	return {
		Level = data.Level,
		Experience = data.Experience,
		XPToNext = XPTable.toNext(data.Level),
		LevelsGained = levelsGained or 0,
	}
end

function ProfileView.snapshot(data: { [string]: any }): { [string]: any }
	return {
		Race = data.Race,
		Job = data.Job,
		FacePreset = data.FacePreset,
		HeadStyle = data.HeadStyle,
		Level = data.Level,
		Experience = data.Experience,
		XPToNext = XPTable.toNext(data.Level),
		OwnedSkills = ownedSkills(data),
		EquippedSkills = equippedSkills(data),
		Inventory = ProfileView.inventory(data),
		Equipment = ProfileView.equipment(data),
		Stackables = ProfileView.stackables(data),
		Wallet = ProfileView.wallet(data),
	}
end

return table.freeze(ProfileView)
