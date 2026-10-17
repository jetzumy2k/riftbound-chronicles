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
		Level = data.Level,
		Experience = data.Experience,
		XPToNext = XPTable.toNext(data.Level),
		OwnedSkills = ownedSkills(data),
		EquippedSkills = equippedSkills(data),
	}
end

return table.freeze(ProfileView)
