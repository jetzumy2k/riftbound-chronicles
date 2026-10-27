local load = require("../loader")
local MallDefinitions = load("src/shared/Definitions/MallDefinitions")
local ItemDefinitions = load("src/shared/Definitions/ItemDefinitions")
local BuffRules = load("src/shared/Logic/BuffRules")
local EventRules = load("src/shared/Logic/EventRules")
local ItemRules = load("src/shared/Logic/ItemRules")
local StatFormulas = load("src/shared/Logic/StatFormulas")
local LootRules = load("src/shared/Logic/LootRules")
local RewardClaims = load("src/server/Persistence/RewardClaims")
local ProfileTemplate = load("src/server/Persistence/ProfileTemplate")
local ProfileValidator = load("src/server/Persistence/ProfileValidator")
local EventRewards = load("src/shared/Logic/EventRewards")
local Schema = load("src/shared/Logic/Schema")
local ConfigSchema = load("src/server/Config/ConfigSchema")
local Defaults = load("src/server/Config/Defaults")
local ConfigCore = load("src/server/Config/ConfigCore")

local NOW = 1800000000

return function(t)
	t.describe("Item Mall", function()
		t.it("admin price list covers every entry at its catalog price (D-109)", function()
			local prices = Defaults.Mall.Prices
			for _, entry in MallDefinitions.CATALOG do
				t.eq(prices[entry.id], entry.price, entry.id)
			end
			for id in prices do
				t.ok(MallDefinitions.get(id) ~= nil, `unknown Mall id {id}`)
			end
		end)

		t.it("every catalog entry gives something real for a fixed price", function()
			t.ok(#MallDefinitions.CATALOG >= 10, "catalog size")
			for _, entry in MallDefinitions.CATALOG do
				t.ok(entry.price > 0 and entry.price % 1 == 0, `{entry.id} price`)
				t.ok(table.find(MallDefinitions.TABS, entry.tab) ~= nil, `{entry.id} tab`)
				if entry.grant.kind == "Stackable" then
					local def = ItemDefinitions.stackable(entry.grant.id)
					t.ok(def ~= nil, `{entry.id}: unknown stackable {entry.grant.id}`)
					t.ok(
						entry.grant.count >= 1 and def and entry.grant.count <= def.maxStack,
						`{entry.id} count`
					)
				else
					t.ok(
						entry.grant.rarity == "Legendary" or entry.grant.rarity == "Mythical",
						`{entry.id} rarity`
					)
				end
			end
			for _, id in BuffRules.IDS do
				local def = ItemDefinitions.stackable(`Buff_{id}`)
				t.ok(
					def and def.use and def.use.kind == "Buff" and def.use.buff == id,
					`Buff_{id} starts {id}`
				)
				t.ok(MallDefinitions.get(id) ~= nil, `{id} is sold`)
			end
		end)

		t.it("every buff, bag item and Mall entry explains itself in a few words", function()
			for _, id in BuffRules.IDS do
				local buff = BuffRules.get(id)
				t.ok(#buff.tag >= 2 and #buff.tag <= 5, `{id} badge label {buff.tag}`)
				t.ok(buff.short ~= "" and #buff.short <= 24, `{id} short effect`)
				t.eq(ItemDefinitions.stackable(`Buff_{id}`).glyph, buff.icon, `{id} same icon in the bag`)
				t.eq(MallDefinitions.get(id).icon, buff.icon, `{id} same icon in the Mall`)
			end
			for id, def in ItemDefinitions.Stackables do
				t.ok(type(def.short) == "string" and def.short ~= "" and #def.short <= 32, `{id} short`)
				t.ok(
					string.find(def.name, "_", 1, true) == nil and def.name ~= id,
					`{id} has a readable name`
				)
			end
			for _, entry in MallDefinitions.CATALOG do
				t.ok(
					type(entry.short) == "string" and entry.short ~= "" and #entry.short <= 32,
					`{entry.id} short`
				)
			end
		end)

		t.it("Mall Point packs: 100 / 550 / 1200 / 2600 for 80 / 400 / 800 / 1600 Robux", function()
			local want = { { 100, 80 }, { 550, 400 }, { 1200, 800 }, { 2600, 1600 } }
			for i, pack in MallDefinitions.PACKS do
				t.eq(MallDefinitions.pointsOf(pack), want[i][1])
				t.eq(pack.robux, want[i][2])
			end
			t.eq(MallDefinitions.packForProduct(0), nil, "unset products never pay")
			t.eq(MallDefinitions.packForProduct(123456), nil)
		end)

		t.it("buffs: stacking time, capped at 6 hours", function()
			local buffs = {}
			t.eq(BuffRules.extend(buffs, "Insight", NOW), NOW + 3600)
			t.eq(BuffRules.extend(buffs, "Insight", NOW + 600), NOW + 7200, "adds 60 minutes")
			for _ = 1, 10 do
				BuffRules.extend(buffs, "Insight", NOW)
			end
			t.eq(buffs.Insight, NOW + BuffRules.STACK_SECONDS)
			-- D-119: a reward runs a day; using one more never shortens it.
			t.eq(BuffRules.grantFor(buffs, "Might", 86400, NOW), NOW + 86400)
			t.eq(BuffRules.extend(buffs, "Might", NOW), NOW + 86400)
			t.eq(BuffRules.extend(buffs, "Nope", NOW), nil)
			t.eq(#BuffRules.active({ Might = NOW - 1, Iron = NOW + 5 }, NOW), 1)
		end)

		t.it("reward buffs join the event caps; stat buffs add to stats", function()
			local running = EventRules.active(
				{ { Id = "DoubleExp", StartsAt = NOW - 10, EndsAt = NOW + 100, By = 1 } },
				NOW
			)
			local extra = BuffRules.rewardBonus({ Insight = NOW + 60 }, "XP", NOW)
			t.near(extra, 0.5, 1e-9)
			t.near(EventRules.factor("XP", running, {}, extra), 2.5, 1e-9)
			t.near(EventRules.factor("XP", {}, {}, extra), 1.5, 1e-9, "a buff alone")
			t.eq(EventRules.factor("XP", running, {}, 5), 3, "still capped")
			local mob = { DropChancePct = 12, Rarity = { Standard = 45, Uncommon = 25, Rare = 30 } }
			local boosted = EventRules.lootTable(
				mob,
				{ { Id = "Buff:Fortune", StartsAt = 0, EndsAt = math.huge, By = 0 } },
				{}
			)
			t.near(boosted.DropChancePct, 18, 1e-9)
			t.ok(LootRules.validate(boosted), "valid table")
			local base = ItemRules.withGear(StatFormulas.forLevel(10), ItemRules.gearTotals({}, {}))
			local stats = BuffRules.applyTo(
				base,
				{ Might = NOW + 60, Iron = NOW + 60, Vigor = NOW + 60, Clarity = NOW + 60 },
				NOW
			)
			t.near(stats.MaxHP, base.MaxHP * 1.1, 1e-6)
			t.near(stats.Defense, base.Defense * 1.1, 1e-6)
			t.eq(stats.DamagePct, 10)
			t.eq(stats.FocusBonus, 30)
			t.ok(BuffRules.applyTo(base, {}, NOW) == base, "no buffs: the same table")
		end)

		t.it("set pieces have fixed attributes: same every time, inside the ranges", function()
			local def = ItemDefinitions.defFor("Warrior", "Weapon", "Sword", 20)
			t.ok(def ~= nil, "a warrior sword")
			for _, rarity in { "Legendary", "Mythical" } do
				local a = ItemRules.fixedRoll(def, rarity, 20)
				local b = ItemRules.fixedRoll(def, rarity, 20)
				t.eq(#a, ItemRules.ROLLS[rarity])
				for i, attribute in a do
					t.eq(attribute.Stat, b[i].Stat)
					t.eq(attribute.Value, b[i].Value)
					local lo, hi = ItemRules.bounds(attribute.Stat, rarity, 20)
					t.ok(
						attribute.Value >= lo and attribute.Value <= hi,
						`{attribute.Stat} {attribute.Value} in {lo}..{hi}`
					)
				end
			end
		end)

		t.it("event rewards: checked kinds, items and amounts", function()
			local ALL = { "MallPoints", "Stones", "Buffs", "Sets" }
			local function why(list, allowed: any?)
				local ok, reason =
					EventRewards.validate(list, if allowed == false then nil else allowed or ALL)
				return if ok then "ok" else reason
			end
			t.eq(why(nil), "ok")
			t.eq(
				why({
					{ Kind = "MallPoints", Count = 500 },
					{ Kind = "Item", Id = "PerfectStone", Count = 2 },
				}),
				"ok"
			)
			t.eq(why({ { Kind = "Set", Id = "Mythical", Count = 1 } }), "ok")
			t.eq(why({ { Kind = "MallPoints", Count = 10001 } }), "count")
			t.eq(why({ { Kind = "Item", Id = "StoneFragment", Count = 1 } }), "item")
			t.eq(why({ { Kind = "Item", Id = "Buff_Might", Count = 100 } }), "count")
			t.eq(why({ { Kind = "Set", Id = "Rare", Count = 1 } }), "set")
			t.eq(why({ { Kind = "Set", Id = "Legendary", Count = 2 } }), "count")
			t.eq(why({ { Kind = "Gold", Count = 5 } }), "kind")
			t.eq(why({ { Kind = "MallPoints", Count = 0 } }), "count")
			local five = {}
			for _ = 1, 5 do
				table.insert(five, { Kind = "MallPoints", Count = 1 })
			end
			t.eq(why(five), "many")
			t.eq(why({ { Kind = "MallPoints", Count = 5 } }, false), "none", "boost events take none")
			t.eq(why({}, false), "ok", "an empty list is always fine")
			t.eq(why({ { Kind = "Set", Id = "Legendary", Count = 1 } }, { "MallPoints", "Buffs" }), "group")
			t.eq(
				why({ { Kind = "Item", Id = "PerfectStone", Count = 1 } }, { "MallPoints", "Buffs" }),
				"group"
			)
			t.eq(why({ { Kind = "Item", Id = "Buff_Might", Count = 1 } }, { "MallPoints", "Buffs" }), "ok")
			for _, id in EventRewards.ITEMS do
				t.ok(ItemDefinitions.stackable(id) ~= nil, id)
			end
			t.eq(
				EventRewards.describe({
					{ Kind = "MallPoints", Count = 500 },
					{ Kind = "Item", Id = "PerfectStone", Count = 2 },
					{ Kind = "Set", Id = "Legendary", Count = 1 },
				}),
				"500 Mall Points, 2 x Perfect Enhancement Stone, Legendary Set"
			)
			t.eq(
				EventRewards.slotsNeeded(
					{ { Kind = "Set", Id = "Legendary", Count = 1 }, { Kind = "MallPoints", Count = 5 } },
					11
				),
				11
			)
		end)

		t.it("which events take rewards, and who gets them", function()
			local EventDefinitions = load("src/shared/Definitions/EventDefinitions")
			for _, e in EventDefinitions.List do
				if e.kind == "Modifier" then
					t.eq(e.rewards, nil, `{e.id}: a boost takes no rewards`)
				end
				if e.rewards then
					t.ok(EventRewards.RECIPIENTS[e.rewardTo or ""] ~= nil, `{e.id} says who gets them`)
					for _, group in e.rewards do
						t.ok(table.find(EventRewards.GROUP_ORDER, group) ~= nil, `{e.id}: {group}`)
					end
				end
			end
			for _, id in
				{ "DoubleExp", "RareGearRush", "LegendaryHunt", "DesertStorm", "BossFrenzy", "ArenaRush" }
			do
				t.eq(EventDefinitions.get(id).rewards, nil, `{id} takes no rewards`)
			end
			t.ok(EventDefinitions.get("NullbornWorldBoss").rewards ~= nil, "the world boss takes rewards")
		end)

		t.it("a window with rewards passes the config schema", function()
			local values = {
				Events = {
					Windows = {
						{
							Id = "DoubleExp",
							StartsAt = 1,
							EndsAt = 100,
							By = 1,
							Rewards = { { Kind = "MallPoints", Count = 500 } },
						},
					},
				},
			}
			local ok, result =
				ConfigCore.resolve(Defaults, { version = 1, values = values }, ConfigSchema(Schema), Schema)
			t.ok(ok, tostring(result))
		end)

		t.it("profiles: Mall Points and buffs are repaired; receipts are kept forever", function()
			local data = ProfileTemplate.new()
			data.Wallet.MallPoints = -5
			data.Buffs = { Insight = os.time() + 600, Fake = os.time() + 600, Might = os.time() - 5 }
			ProfileValidator.repair(data)
			t.eq(data.Wallet.MallPoints, 0)
			t.ok(
				data.Buffs.Insight ~= nil and data.Buffs.Fake == nil and data.Buffs.Might == nil,
				"known, running only"
			)
			t.ok(RewardClaims.isValidId("R:5f2c1a9e-8b3d-4c1e-9a7f-1234567890ab"), "receipt claim id")
			t.eq(RewardClaims.RETENTION_SECONDS.R, false)
			local fresh = ProfileTemplate.new()
			local notes = ProfileValidator.repair(fresh)
			t.eq(#notes, 0, table.concat(notes, " | "))
		end)
	end)
end
