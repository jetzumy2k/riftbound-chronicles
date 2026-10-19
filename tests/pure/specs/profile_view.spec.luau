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

	t.it("items, equipment, stackables and wallet match the schemas (D-64)", function()
		local ItemDefinitions = load("src/shared/Definitions/ItemDefinitions")
		local ItemRules = load("src/shared/Logic/ItemRules")
		local data = ProfileTemplate.new()
		data.Race = "Devil"
		data.Job = "Warrior"
		data.Level = 30
		local seed = 3
		local function random()
			seed = (seed * 1103515245 + 12345) % 2147483648
			return seed / 2147483648
		end
		local n = 0
		for _, id in ItemDefinitions.IDS do
			local def = ItemDefinitions.All[id]
			n += 1
			local guid = string.format("%08X-0000-0000-0000-%012X", n, n)
			data.Inventory[guid] = {
				Guid = guid,
				DefId = id,
				Rarity = "Mythical",
				ItemLevel = def.maxItemLevel,
				Attributes = ItemRules.roll(def, "Mythical", def.maxItemLevel, random),
				Enhancement = 10,
				Locked = n % 2 == 0,
				Source = "Test",
				CreatedAt = 1700000000,
			}
			local slot = if def.slot == "Ring"
				then "Ring1"
				elseif def.slot == "Shield" then "OffHand"
				else def.slot
			if def.job == "Warrior" and def.tier == 3 then
				data.Equipment[slot] = guid
			end
		end
		data.Stackables = { HealingPotion = 3, StoneFragment = 12 }
		data.Wallet = { Gold = 10, PvPMarks = 2 }
		local view = ProfileView.snapshot(data)
		t.ok(Schema.validateArgs(Registry.ProfileSnapshot.args, 1, { view }))
		t.eq(view.Inventory[next(data.Inventory)].Source, nil, "Source is never sent")
		local update = {
			Changed = view.Inventory,
			Removed = { "00000001-0000-0000-0000-000000000001" },
			Equipment = view.Equipment,
			Stackables = view.Stackables,
			Wallet = view.Wallet,
			ReadyIn = { HealingPotion = 12 },
		}
		t.ok(Schema.validateArgs(Registry.InventoryUpdate.args, 1, { update }))
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
