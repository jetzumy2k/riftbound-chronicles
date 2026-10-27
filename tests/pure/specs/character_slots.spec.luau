--[[
	D-115: up to 4 characters per account; account fields stay, character
	fields move with the character; switching happens on load.
]]
local load = require("../loader")
local CharacterSlots = load("src/server/Persistence/CharacterSlots")
local ProfileTemplate = load("src/server/Persistence/ProfileTemplate")
local ProfileValidator = load("src/server/Persistence/ProfileValidator")
local Migrations = load("src/server/Persistence/Migrations")

local function account(): { [string]: any }
	local data = ProfileTemplate.new()
	data.Race, data.Job, data.Level = "Angel", "Warrior", 12
	data.Stackables = { HealingPotion = 5 }
	data.Wallet = { Gold = 500, PvPMarks = 7, MallPoints = 900, PurchasedMallPoints = 100 }
	data.ClaimedRewardIds = { ["Q:Q1"] = 1, ["R:buy1"] = 2, ["S:M2026-10"] = 3, ["G:StarterGear"] = 4 }
	data.Settings.MusicVolume = 33
	ProfileValidator.repair(data) -- consistent EXP totals etc.
	return data
end

return function(t)
	t.describe("Character slots (D-115)", function()
		t.it("v3 profiles become slot 1 with no other characters", function()
			local old = account()
			old.SchemaVersion = 3
			old.Characters, old.ActiveSlot = nil, nil
			local status, result = Migrations.migrate(old)
			t.eq(status, "ok")
			t.eq(result.SchemaVersion, 4)
			t.eq(result.ActiveSlot, 1)
			t.eq(next(result.Characters), nil)
			t.eq(result.Level, 12, "the character is untouched")
		end)

		t.it(
			"a new character starts fresh; account things stay; switching back restores everything",
			function()
				local data = account()
				data.PendingSlot = 2
				t.ok(CharacterSlots.applyPending(data))
				t.eq(data.ActiveSlot, 2)
				t.eq(data.Job, nil, "new character: the class screen opens")
				t.eq(data.Level, 0)
				t.eq(next(data.Stackables), nil)
				t.eq(data.Wallet.Gold, 0, "Gold is per character")
				t.eq(data.Wallet.MallPoints, 900, "Mall Points are the account's")
				t.eq(data.Race, "Angel", "same realm")
				t.eq(data.Settings.MusicVolume, 33)
				t.eq(data.ClaimedRewardIds["R:buy1"], 2, "receipts stay with the account")
				t.eq(data.ClaimedRewardIds["S:M2026-10"], 3)
				t.eq(data.ClaimedRewardIds["Q:Q1"], nil, "quests are the character's")
				t.eq(data.ClaimedRewardIds["G:StarterGear"], nil, "a new character gets starter gear")
				t.eq(data.Characters["1"].Job, "Warrior")
				data.Job = "Mage"
				data.PendingSlot = 1
				t.ok(CharacterSlots.applyPending(data))
				t.eq(data.Job, "Warrior")
				t.eq(data.Level, 12)
				t.eq(data.Stackables.HealingPotion, 5)
				t.eq(data.Wallet.Gold, 500)
				t.eq(data.ClaimedRewardIds["Q:Q1"], 1)
				t.eq(data.Characters["2"].Job, "Mage", "the other character is kept")
				t.eq(data.Characters["1"], nil, "the played one is not stored twice")
				t.eq(CharacterSlots.count(data), 2)
				local notes = ProfileValidator.repair(data)
			t.eq(#notes, 0, table.concat(notes, " / "))
			end
		)

		t.it("an abandoned new slot (no class chosen) is not kept", function()
			local data = account()
			data.PendingSlot = 3
			CharacterSlots.applyPending(data)
			data.PendingSlot = 1
			CharacterSlots.applyPending(data)
			t.eq(data.Characters["3"], nil)
			t.eq(CharacterSlots.count(data), 1)
		end)

		t.it("summary lists every slot; bad pending slots do nothing", function()
			local data = account()
			data.Characters["3"] = CharacterSlots.extract(account())
			local s = CharacterSlots.summary(data)
			t.eq(#s, CharacterSlots.MAX)
			t.ok(s[1].Active and not s[1].Empty)
			t.ok(s[2].Empty)
			t.eq(s[3].Job, "Warrior")
			data.PendingSlot = 9
			t.ok(not CharacterSlots.applyPending(data))
			t.eq(data.PendingSlot, nil)
		end)

		t.it("delete: another slot at once; the played one moves on; the last frees the realm", function()
			local data = account()
			data.Characters["2"] = CharacterSlots.extract(account())
			data.Characters["4"] = CharacterSlots.extract(account())
			local ok, _, rejoin = CharacterSlots.delete(data, 4)
			t.ok(ok and not rejoin)
			t.eq(data.Characters["4"], nil)
			local ok2, _, rejoin2 = CharacterSlots.delete(data, 1)
			t.ok(ok2 and rejoin2)
			t.eq(data.PendingSlot, 2, "goes on with the next character")
			t.eq(data.Race, "Angel")
			CharacterSlots.applyPending(data)
			t.eq(data.ActiveSlot, 2)
			local ok3, _, rejoin3 = CharacterSlots.delete(data, 2)
			t.ok(ok3 and rejoin3)
			t.eq(data.Race, nil, "the last character: choose a realm again")
			t.eq(data.Wallet.MallPoints, 900, "Mall Points survive")
			local ok4, why = CharacterSlots.delete(data, 3)
			t.ok(not ok4)
			t.eq(why, "empty")
		end)

		t.it("stored characters are validated like profiles", function()
			local data = account()
			local bad = CharacterSlots.extract(account())
			bad.Level = 999
			data.Characters["2"] = bad
			data.Characters["1"] = CharacterSlots.extract(account())
			data.Characters["7"] = CharacterSlots.extract(account())
			data.Characters["3"] = { Job = "Pirate" }
			local notes = ProfileValidator.repair(data)
			t.ok(#notes >= 3)
			t.ok(data.Characters["2"].Level <= 30, "level clamped")
			t.eq(data.Characters["1"], nil, "never the played slot twice")
			t.eq(data.Characters["7"], nil, "no slot 7")
			t.eq(data.Characters["3"], nil, "unknown class dropped")
		end)
	end)
end
