--[[
	D-111: the Owner's system reset clears what isn't kept; Robux Mall
	Points, receipts, identity and cosmetics always survive.
]]
local load = require("../loader")
local ResetRules = load("src/shared/Logic/ResetRules")
local ProfileTemplate = load("src/server/Persistence/ProfileTemplate")
local ProfileValidator = load("src/server/Persistence/ProfileValidator")
local AdminRules = load("src/shared/Logic/AdminRules")

local function played(): { [string]: any }
	local data = ProfileTemplate.new()
	data.Race, data.Job = "Angel", "Warrior"
	data.Level, data.Experience, data.TotalExperience = 20, 50, 99999
	data.Attributes.STR = 40
	data.OwnedSkills = { W_Slash = 3 }
	data.EquippedSkills = { Regular = { "W_Slash" } }
	data.Inventory = { g1 = { DefId = "x" } }
	data.Equipment = { Weapon = "g1" }
	data.Stackables = { HealingPotion = 5 }
	data.Buffs = { Might = 123 }
	data.Wallet = { Gold = 10, PvPMarks = 20, MallPoints = 900, PurchasedMallPoints = 300 }
	data.PvPStats.Victories = 77
	data.QuestState = { Q1 = { Status = "Completed" } }
	data.StoryFlags = { MetElder = true }
	data.EventProgress = { E1 = 4 }
	data.Titles = { Hero = true }
	data.ClaimedRewardIds = { ["Q:Q1"] = 1, ["G:StarterGear"] = 1, ["R:abc"] = 1, ["D:run1"] = 1 }
	return data
end

return function(t)
	t.describe("System reset (D-111)", function()
		t.it("clearing everything keeps identity, cosmetics and Robux points", function()
			local data = played()
			local cleared = ResetRules.apply(data, ResetRules.normalize({}), 2, ProfileTemplate.new())
			t.eq(#cleared, 6)
			t.eq(data.Level, 0)
			t.eq(data.Attributes.STR, 0)
			t.eq(next(data.OwnedSkills), nil)
			t.eq(next(data.Inventory), nil)
			t.eq(next(data.Equipment), nil)
			t.eq(next(data.Stackables), nil)
			t.eq(data.Wallet.Gold, 0)
			t.eq(data.Wallet.MallPoints, 300, "Robux-bought points stay")
			t.eq(data.PvPStats.Victories, 0)
			t.eq(next(data.QuestState), nil)
			t.eq(next(data.StoryFlags), nil)
			t.eq(data.Race, "Angel")
			t.eq(data.Job, "Warrior")
			t.ok(data.Titles.Hero, "titles stay")
			t.eq(data.ClaimedRewardIds["Q:Q1"], nil, "quest rewards can be earned again")
			t.eq(data.ClaimedRewardIds["G:StarterGear"], nil, "starter gear comes back with gear cleared")
			t.eq(data.ClaimedRewardIds["R:abc"], 1, "receipts are never forgotten")
			t.eq(data.ClaimedRewardIds["D:run1"], 1)
			t.eq(data.ResetVersion, 2)
			t.eq(#ProfileValidator.repair(data), 0, "the result is a valid profile")
		end)

		t.it("kept groups survive; quests always restart", function()
			local data = played()
			ResetRules.apply(
				data,
				ResetRules.normalize({
					Items = true,
					Gear = true,
					MallPoints = true,
					Levels = true,
					Rankings = true,
				}),
				1,
				ProfileTemplate.new()
			)
			t.eq(data.Level, 20)
			t.eq(data.OwnedSkills.W_Slash, 3)
			t.eq(data.Equipment.Weapon, "g1")
			t.eq(data.Stackables.HealingPotion, 5)
			t.eq(data.Wallet.MallPoints, 900)
			t.eq(data.PvPStats.Victories, 77)
			t.eq(next(data.QuestState), nil)
			t.eq(data.ClaimedRewardIds["G:StarterGear"], 1, "gear kept: no second starter set")
		end)

		t.it("a reset is due once per version; only the Owner may run it", function()
			t.ok(ResetRules.due(0, 1))
			t.ok(ResetRules.due(nil, 1))
			t.ok(not ResetRules.due(1, 1))
			t.ok(not ResetRules.due(2, 1))
			t.ok(not ResetRules.due(0, nil))
			t.eq(ResetRules.normalize({ Items = true, Bogus = true }).Bogus, nil)
			t.ok(AdminRules.has("Owner", "system.reset"))
			t.ok(not AdminRules.has("Admin", "system.reset"))
			t.ok(not AdminRules.has("Moderator", "system.reset", { "system.reset" }))
		end)
	end)
end
