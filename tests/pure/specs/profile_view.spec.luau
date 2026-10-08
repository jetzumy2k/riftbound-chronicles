local load = require("../loader")
local Schema = load("src/shared/Logic/Schema")
local Registry = load("src/shared/Net/Registry")(Schema)
local ProfileTemplate = load("src/server/Persistence/ProfileTemplate")
local ProfileView = load("src/server/Persistence/ProfileView")

return function(t)
	t.it("snapshot of a fresh profile matches the ProfileSnapshot schema", function()
		local view = ProfileView.snapshot(ProfileTemplate.new())
		t.ok(Schema.validateArgs(Registry.ProfileSnapshot.args, 1, { view }))
	end)

	t.it("snapshot of a chosen, max-level profile matches the schema", function()
		local data = ProfileTemplate.new()
		data.Race = "Angel"
		data.Job = "Healer"
		data.Level = 30
		local view = ProfileView.snapshot(data)
		t.ok(Schema.validateArgs(Registry.ProfileSnapshot.args, 1, { view }))
		t.eq(view.XPToNext, 0)
	end)

	t.it("progression update matches the ProgressionUpdate schema", function()
		local data = ProfileTemplate.new()
		data.Level = 4
		data.Experience = 12
		local view = ProfileView.progression(data, 2)
		t.ok(Schema.validateArgs(Registry.ProgressionUpdate.args, 1, { view }))
		t.eq(view.LevelsGained, 2)
	end)

	t.it("never exposes internal fields", function()
		local data = ProfileTemplate.new()
		data.ClaimedRewardIds = { ["Q:A"] = 1 }
		local view = ProfileView.snapshot(data)
		for _, hidden in
			{
				"ClaimedRewardIds",
				"Restrictions",
				"Counters",
				"CreatedAt",
				"LastLoginAt",
				"PvPStats",
				"TotalExperience",
			}
		do
			t.eq(view[hidden], nil, hidden)
		end
	end)
end
