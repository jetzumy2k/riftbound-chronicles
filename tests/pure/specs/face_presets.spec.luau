local load = require("../loader")
local Enums = load("src/shared/Enums")
local FacePresets = load("src/shared/Definitions/FacePresets")

return function(t)
	t.it("ids are unique, positive integers starting at 1", function()
		local seen = {}
		for _, preset in FacePresets.List do
			t.ok(preset.id % 1 == 0 and preset.id >= 1, tostring(preset.id))
			t.ok(not seen[preset.id], `duplicate id {preset.id}`)
			seen[preset.id] = true
		end
		t.ok(seen[1], "id 1 must exist (profile default)")
		t.eq(FacePresets.maxId(), #FacePresets.List)
	end)

	t.it("every race has presets and each preset belongs to a valid race", function()
		for _, race in Enums.Race do
			t.ok(#FacePresets.forRace(race) >= 1, race)
		end
		for _, preset in FacePresets.List do
			t.ok(Enums.has(Enums.Race, preset.race), preset.name)
		end
	end)

	t.it("isValidFor enforces the race pairing", function()
		t.ok(FacePresets.isValidFor(1, "Angel"))
		t.ok(not FacePresets.isValidFor(1, "Devil"))
		t.ok(FacePresets.isValidFor(5, "Devil"))
		t.ok(not FacePresets.isValidFor(99, "Angel"))
		t.ok(not FacePresets.isValidFor("1", "Angel"))
		t.ok(not FacePresets.isValidFor(1.5, "Angel"))
	end)

	t.it("defaultFor returns that race's first preset", function()
		t.eq(FacePresets.defaultFor("Angel"), 1)
		t.eq(FacePresets.defaultFor("Devil"), 5)
	end)

	t.it("face textures, when set, are engine asset ids only (no arbitrary URLs)", function()
		for _, preset in FacePresets.List do
			local texture = preset.faceTexture
			if texture ~= nil then
				t.ok(
					string.match(texture, "^rbxassetid://%d+$") ~= nil
						or string.match(texture, "^rbxasset://") ~= nil,
					`{preset.name}: {texture}`
				)
			end
		end
	end)

	t.it("every preset has a full palette and every role resolves to a colour", function()
		for _, preset in FacePresets.List do
			for _, role in { "cloth", "metal", "glow", "leather", "wing", "horn", "blade", "wood", "unknown" } do
				local color = FacePresets.roleColor(preset, role)
				t.eq(#color, 3, `{preset.name}.{role}`)
				for _, channel in color do
					t.ok(channel >= 0 and channel <= 255, `{preset.name}.{role}`)
				end
			end
			t.eq(preset.accent, preset.palette.glow)
		end
	end)

	t.it("preset table is frozen", function()
		t.ok(table.isfrozen(FacePresets.List))
		t.ok(table.isfrozen(FacePresets.List[1]))
	end)
end
