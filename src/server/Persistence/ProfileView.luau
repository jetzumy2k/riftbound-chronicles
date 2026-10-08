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

local XPTable = require(game:GetService("ReplicatedStorage").Shared.Logic.XPTable)

local ProfileView = {}

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
	}
end

return table.freeze(ProfileView)
