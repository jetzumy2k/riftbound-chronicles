local load = require("../loader")
local ProfileTemplate = load("src/server/Persistence/ProfileTemplate")
local ProfileValidator = load("src/server/Persistence/ProfileValidator")
local ItemRules = load("src/shared/Logic/ItemRules")

local function fresh()
	return ProfileTemplate.new()
end

local function joined(notes)
	return table.concat(notes, " | ")
end

return function(t)
	t.it("a fresh profile needs no repairs", function()
		local data = fresh()
		local notes = ProfileValidator.repair(data)
		t.eq(#notes, 0, joined(notes))
	end)

	t.it("a valid mid-game profile needs no repairs", function()
		local data = fresh()
		data.Race = "Devil"
		data.FacePreset = 7
		data.Job = "Archer"
		data.Level = 12
		data.Experience = 50
		data.TotalExperience = 99999
		data.Titles = { RiftChampion = true }
		data.EquippedTitle = "RiftChampion"
		data.ClaimedRewardIds = { ["Q:FirstSpark"] = 1700000000 }
		local notes = ProfileValidator.repair(data)
		t.eq(#notes, 0, joined(notes))
	end)

	t.describe("progression", function()
		t.it("clamps level above 30", function()
			local data = fresh()
			data.Level = 99
			ProfileValidator.repair(data)
			t.eq(data.Level, 30)
			t.eq(data.Experience, 0)
		end)

		t.it("clamps negative and fractional levels", function()
			local data = fresh()
			data.Level = -3
			ProfileValidator.repair(data)
			t.eq(data.Level, 0)
			local data2 = fresh()
			data2.Level = 7.9
			ProfileValidator.repair(data2)
			t.eq(data2.Level, 7)
		end)

		t.it("repairs NaN / infinite / string numbers", function()
			local data = fresh()
			data.Level = 0 / 0
			data.Experience = math.huge
			ProfileValidator.repair(data)
			t.eq(data.Level, 0)
			t.eq(data.Experience, 0)
			local data2 = fresh()
			data2.Level = "30"
			ProfileValidator.repair(data2)
			t.eq(data2.Level, 0)
		end)

		t.it("clamps experience to the current level's range", function()
			local data = fresh()
			data.Level = 0
			data.Experience = 5000
			ProfileValidator.repair(data)
			t.eq(data.Experience, 99)
		end)

		t.it("experience at level 30 is always 0", function()
			local data = fresh()
			data.Level = 30
			data.Experience = 10
			ProfileValidator.repair(data)
			t.eq(data.Experience, 0)
		end)

		t.it("raises TotalExperience to at least what the level implies", function()
			local data = fresh()
			data.Level = 30
			data.TotalExperience = 5
			ProfileValidator.repair(data)
			t.eq(data.TotalExperience, 79095)
		end)
	end)

	t.describe("identity", function()
		t.it("clears invalid race and job (forces re-selection)", function()
			local data = fresh()
			data.Race = "Human"
			data.Job = 3
			local notes = ProfileValidator.repair(data)
			t.eq(data.Race, nil)
			t.eq(data.Job, nil)
			t.ok(#notes >= 2)
		end)

		t.it("repairs unknown face presets", function()
			local data = fresh()
			data.FacePreset = 9999
			ProfileValidator.repair(data)
			t.eq(data.FacePreset, 1)
		end)

		t.it("a face preset must belong to the chosen race", function()
			local data = fresh()
			data.Race = "Devil"
			data.FacePreset = 2 -- an Angel preset
			ProfileValidator.repair(data)
			t.eq(data.FacePreset, 5) -- first Devil preset
			local ok = fresh()
			ok.Race = "Angel"
			ok.FacePreset = 3
			t.eq(#ProfileValidator.repair(ok), 0)
		end)
	end)

	t.describe("structure", function()
		t.it("fills missing fields from the template", function()
			local data = fresh()
			data.Wallet = nil
			data.Settings = nil
			ProfileValidator.repair(data)
			t.eq(data.Wallet.Gold, 0)
			t.eq(data.Settings.GraphicsTier, "Auto")
		end)

		t.it("replaces fields of the wrong type", function()
			local data = fresh()
			data.Inventory = "hacked"
			data.PvPStats = 5
			ProfileValidator.repair(data)
			t.eq(type(data.Inventory), "table")
			t.eq(data.PvPStats.Victories, 0)
		end)

		t.it("removes unknown top-level and nested fields", function()
			local data = fresh()
			data.IsAdmin = true
			data.Wallet.Robux = 1e9
			data.Settings.Godmode = true
			ProfileValidator.repair(data)
			t.eq(data.IsAdmin, nil)
			t.eq(data.Wallet.Robux, nil)
			t.eq(data.Settings.Godmode, nil)
		end)

		t.it("sets SchemaVersion to current", function()
			local data = fresh()
			data.SchemaVersion = nil
			ProfileValidator.repair(data)
			t.eq(data.SchemaVersion, ProfileTemplate.SCHEMA_VERSION)
		end)
	end)

	t.describe("collections", function()
		t.it("filters invalid set entries", function()
			local data = fresh()
			data.Job = "Warrior"
			data.OwnedSkills =
				{ ShieldBash = 2, Whirlwind = "yes", [5] = 1, CleavingStrike = 9, Hamstring = 1.5 }
			data.StoryFlags = { Met = true, [""] = true }
			ProfileValidator.repair(data)
			t.eq(data.OwnedSkills.ShieldBash, 2)
			t.eq(data.OwnedSkills.Whirlwind, nil)
			t.eq(data.OwnedSkills[5], nil)
			t.eq(data.OwnedSkills.CleavingStrike, nil, "rank above max")
			t.eq(data.OwnedSkills.Hamstring, nil, "fractional rank")
			t.eq(data.StoryFlags[""], nil)
		end)

		t.it("cleans the skill loadout: max 3 regular, no duplicates", function()
			local data = fresh()
			data.Job = "Warrior"
			data.OwnedSkills = { ShieldBash = 1, CleavingStrike = 1, Whirlwind = 1, IronSkin = 1 }
			data.EquippedSkills = {
				Regular = { "ShieldBash", "ShieldBash", "Whirlwind", "IronSkin", "CleavingStrike" },
				Special = 5,
				Extra = true,
			}
			ProfileValidator.repair(data)
			t.eq(table.concat(data.EquippedSkills.Regular, ","), "ShieldBash,Whirlwind")
			t.eq(data.EquippedSkills.Special, nil)
			t.eq(data.EquippedSkills.Extra, nil)
		end)

		t.it("keeps Auto Attack on the bar though it costs no point (never owned)", function()
			local data = fresh()
			data.Job = "Archer"
			data.OwnedSkills = {}
			data.EquippedSkills = { Regular = { "AutoAttack" }, Special = "AutoAttack" }
			ProfileValidator.repair(data)
			t.eq(table.concat(data.EquippedSkills.Regular, ","), "AutoAttack")
			t.eq(data.EquippedSkills.Special, nil, "not a special")
		end)

		t.it("keeps only real skills of the character's own job, with their prerequisites (D-45)", function()
			local data = fresh()
			data.Job = "Healer"
			data.OwnedSkills = {
				MendingLight = 1,
				Renewal = 1,
				Lifewell = 1,
				RadiantBurst = 1,
				FlashHeal = 1,
				DivineGrace = 1,
				Smite = 1,
				ShieldBash = 1, -- Warrior skill
				Nope = 1, -- no such skill
				WrathOfHeaven = 1, -- requires Halo of Silence (not learned)
			}
			data.EquippedSkills =
				{ Regular = { "ShieldBash", "MendingLight", "DivineGrace" }, Special = "MendingLight" }
			ProfileValidator.repair(data)
			t.eq(data.OwnedSkills.MendingLight, 1)
			t.eq(data.OwnedSkills.DivineGrace, 1)
			t.eq(data.OwnedSkills.ShieldBash, nil)
			t.eq(data.OwnedSkills.Nope, nil)
			t.eq(data.OwnedSkills.WrathOfHeaven, nil, "missing prerequisite")
			-- Wrong job, and a special in a regular slot, are dropped; a regular
			-- skill can't sit in the special slot.
			t.eq(table.concat(data.EquippedSkills.Regular, ","), "MendingLight")
			t.eq(data.EquippedSkills.Special, nil)
		end)

		t.it("a character without a job owns no skills", function()
			local data = fresh()
			data.OwnedSkills = { ShieldBash = 1 }
			data.EquippedSkills = { Regular = { "ShieldBash" } }
			ProfileValidator.repair(data)
			t.eq(next(data.OwnedSkills), nil)
			t.eq(#data.EquippedSkills.Regular, 0)
		end)

		t.it("drops negative/fractional stacks and clamps currency", function()
			local data = fresh()
			data.Stackables = { EnhancementStone = 5, PerfectStone = -1, Fragment = 1.5 }
			data.Wallet = { Gold = -50, PvPMarks = 1e20 }
			ProfileValidator.repair(data)
			t.eq(data.Stackables.EnhancementStone, 5)
			t.eq(data.Stackables.PerfectStone, nil)
			t.eq(data.Stackables.Fragment, nil)
			t.eq(data.Wallet.Gold, 0)
			t.eq(data.Wallet.PvPMarks, 1000000000000)
		end)

		t.it("drops inventory entries whose key does not match the item Guid", function()
			local data = fresh()
			local good = "11111111-2222-3333-4444-555555555555"
			local function item(guid: string): any
				return {
					Guid = guid,
					DefId = "W_Warrior_Sword_T1",
					Rarity = "Rare",
					ItemLevel = 3,
					Attributes = { { Stat = "Attack", Value = 3 } },
					Enhancement = 0,
					Locked = false,
					Source = "Test",
					CreatedAt = 1,
				}
			end
			data.Inventory = {
				[good] = item(good),
				spoof = item("other"),
				junk = 5,
			}
			data.Equipment = { Weapon = good, Chest = "missing", Wings = good }
			ProfileValidator.repair(data)
			t.ok(data.Inventory[good] ~= nil)
			t.eq(data.Inventory.spoof, nil)
			t.eq(data.Inventory.junk, nil)
			t.eq(data.Equipment.Weapon, good)
			t.eq(data.Equipment.Chest, nil)
			t.eq(data.Equipment.Wings, nil)
		end)

		t.it("checks items against their definition, pool and bounds (D-64)", function()
			local data = fresh()
			local a = "AAAAAAAA-0000-0000-0000-000000000001"
			local b = "AAAAAAAA-0000-0000-0000-000000000002"
			local c = "AAAAAAAA-0000-0000-0000-000000000003"
			data.Inventory = {
				[a] = {
					Guid = a,
					DefId = "A_Mage_Chest_T1",
					Rarity = "Rare",
					ItemLevel = 25, -- tier 1 is 0-9
					Attributes = {
						{ Stat = "SkillPower", Value = 999 }, -- clamped
						{ Stat = "SkillPower", Value = 3 }, -- repeat: dropped
						{ Stat = "Mitigation", Value = 2 }, -- not a mage pool stat
					},
					Enhancement = 14,
					Locked = "yes",
					Source = "Test",
					CreatedAt = 1,
					Hacked = true,
				},
				[b] = { Guid = b, DefId = "W_Warrior_Laser_T1", Rarity = "Rare" },
				[c] = { Guid = c, DefId = "W_Mage_Wand_T1", Rarity = "Godly" },
			}
			-- A chest in the weapon slot is not allowed.
			data.Equipment = { Weapon = a, Chest = a }
			ProfileValidator.repair(data)
			local item = data.Inventory[a]
			t.eq(item.ItemLevel, 9)
			t.eq(item.Enhancement, 10)
			t.eq(item.Locked, false)
			t.eq(item.Hacked, nil)
			t.eq(#item.Attributes, 1)
			local _, hi = ItemRules.bounds("SkillPower", "Rare", 9)
			t.eq(item.Attributes[1].Value, hi)
			t.eq(data.Inventory[b], nil, "unknown def dropped")
			t.eq(data.Inventory[c], nil, "unknown rarity dropped")
			t.eq(data.Equipment.Weapon, nil)
			t.eq(data.Equipment.Chest, a)
		end)

		t.it("clears titles and cosmetics the player does not own", function()
			local data = fresh()
			data.EquippedTitle = "Owner"
			data.EquippedCosmetics = { Aura = "GoldAura" }
			ProfileValidator.repair(data)
			t.eq(data.EquippedTitle, nil)
			t.eq(data.EquippedCosmetics.Aura, nil)
		end)

		t.it("drops claimed reward ids with bad timestamps", function()
			local data = fresh()
			data.ClaimedRewardIds = { ["Q:A"] = 100, ["Q:B"] = "yesterday", ["Q:C"] = -5 }
			ProfileValidator.repair(data)
			t.eq(data.ClaimedRewardIds["Q:A"], 100)
			t.eq(data.ClaimedRewardIds["Q:B"], nil)
			t.eq(data.ClaimedRewardIds["Q:C"], nil)
		end)

		t.it("drops non-whitelisted counters", function()
			local data = fresh()
			data.Counters = { Anything = 5 }
			ProfileValidator.repair(data)
			t.eq(data.Counters.Anything, nil)
		end)

		t.it("repairs settings ranges and enums", function()
			local data = fresh()
			data.Settings =
				{ MusicVolume = 500, SfxVolume = -1, GraphicsTier = "Ultra", ShowDamageNumbers = "no" }
			ProfileValidator.repair(data)
			t.eq(data.Settings.MusicVolume, 100)
			t.eq(data.Settings.SfxVolume, 0)
			t.eq(data.Settings.GraphicsTier, "Auto")
			t.eq(data.Settings.ShowDamageNumbers, true)
		end)
	end)

	t.it("caps the number of repair notes", function()
		local data = fresh()
		for i = 1, 100 do
			data[`Junk{i}`] = i
		end
		local notes = ProfileValidator.repair(data)
		t.eq(#notes, 25)
		t.ok(string.find(notes[25], "more", 1, true) ~= nil)
	end)

	t.it("repair is idempotent", function()
		local data = fresh()
		data.Level = 99
		data.Race = "Elf"
		data.Junk = true
		ProfileValidator.repair(data)
		local second = ProfileValidator.repair(data)
		t.eq(#second, 0, joined(second))
	end)
end
