--[[
	Admin panel rules (Phase 17, D-77, SECURITY_MODEL §6, T-19 / T-20): the
	permission matrix, roles, which config values the panel may edit, and
	how a batch of changes becomes an override.
]]

local load = require("../loader")
local AdminRules = load("src/shared/Logic/AdminRules")
local Schema = load("src/shared/Logic/Schema")
local ConfigCore = load("src/server/Config/ConfigCore")
local Defaults = load("src/server/Config/Defaults")
local buildSchema = load("src/server/Config/ConfigSchema")
local Roles = load("src/server/Config/Roles")

local spec = buildSchema(Schema)
local _, effective = ConfigCore.resolve(Defaults, nil, spec, Schema)

return function(t)
	t.describe("AdminRules", function()
		t.it(
			"Moderators never get economy, drop rates, items, data edits or roles (CLAUDE.md §21)",
			function()
				for _, permission in
					{
						"config.view",
						"config.dropRates",
						"config.enhancement",
						"config.game",
						"items.grant",
						"items.remove",
						"player.edit",
						"player.inspectFull",
						"quests.manage",
						"bosses.manage",
						"roles.assign",
						"audit.viewAll",
					}
				do
					t.ok(not AdminRules.has("Moderator", permission, { permission }), permission)
				end
				for _, permission in { "panel.open", "player.inspect", "moderation.kick", "audit.view" } do
					t.ok(AdminRules.has("Moderator", permission), permission)
				end
			end
		)

		t.it("grant-only permissions need an explicit Moderator grant", function()
			t.ok(not AdminRules.has("Moderator", "moderation.ban"))
			t.ok(AdminRules.has("Moderator", "moderation.ban", { "moderation.ban" }))
			t.ok(not AdminRules.has("Moderator", "events.activate", { "moderation.ban" }))
		end)

		t.it(
			"Admins can do everything but assign roles or reset the game; Owners everything; others nothing",
			function()
				for _, permission in AdminRules.PERMISSIONS do
					t.eq(
						AdminRules.has("Admin", permission),
						permission ~= "roles.assign" and permission ~= "system.reset",
						permission
					)
					t.ok(AdminRules.has("Owner", permission), permission)
					t.ok(not AdminRules.has(nil, permission), permission)
					t.ok(not AdminRules.has("Player" :: any, permission), permission)
				end
				t.ok(not AdminRules.has("Owner", "made.up"))
				t.eq(#AdminRules.permissionsFor(nil), 0)
			end
		)

		t.it("every player action maps to a known permission", function()
			for _, action in AdminRules.ACTIONS do
				local permission = AdminRules.ACTION_PERMISSION[action]
				t.ok(permission and table.find(AdminRules.PERMISSIONS, permission) ~= nil, action)
			end
			for _, reason in AdminRules.REASONS do
				t.ok(AdminRules.REASON_TEXT[reason] ~= nil, reason)
			end
		end)

		t.it("roles come from the server's list and the place creator", function()
			local roles = { Owners = { 1 }, Admins = { 2 }, Moderators = { 3, 2 }, ModeratorGrants = {} }
			t.eq(AdminRules.roleFor(1, nil, roles), "Owner")
			t.eq(AdminRules.roleFor(2, nil, roles), "Admin", "the highest role wins")
			t.eq(AdminRules.roleFor(3, nil, roles), "Moderator")
			t.eq(AdminRules.roleFor(4, nil, roles), nil)
			t.eq(AdminRules.roleFor(4, 4, roles), "Owner", "creator of a user-owned place")
			t.eq(AdminRules.roleFor(0, 0, roles), nil, "no creator id (local file)")
			-- The shipped list: the creator is Owner; nobody else yet.
			t.eq(AdminRules.roleFor(11763195295, nil, Roles), "Owner")
			t.eq(#Roles.Admins + #Roles.Moderators, 0)
		end)

		t.it("only game sections are editable; network, logging and anti-cheat stay code-only", function()
			t.eq(AdminRules.permissionForPath("Loot.Tables.DungeonBoss.Rarity.Rare"), "config.dropRates")
			t.eq(AdminRules.permissionForPath("Enhancement.RatesPct.6"), "config.enhancement")
			t.eq(AdminRules.permissionForPath("PvP.MarksPerVictory"), "config.game")
			t.eq(AdminRules.permissionForPath("Flags.Maintenance"), "config.game")
			for _, path in
				{ "Net.GlobalCapacity", "Log.Level", "AntiExploit.Mode", "Admin.StudioPlayer1Owner" }
			do
				t.eq(AdminRules.permissionForPath(path), nil, path)
			end
			t.eq(AdminRules.permissionForPath("Flags.ConfigOverrides"), nil, "the override switch itself")
			t.eq(AdminRules.permissionForPath(42), nil)
		end)

		t.it("flatten lists every editable value with its default and limits", function()
			local entries = AdminRules.flatten(spec, effective, Defaults)
			local byPath = {}
			for _, entry in entries do
				byPath[entry.path] = entry
				t.ok(AdminRules.permissionForPath(entry.path) ~= nil, entry.path)
			end
			local rare = byPath["Loot.Tables.DungeonBoss.Rarity.Rare"]
			t.eq(rare.value, 80)
			t.eq(rare.default, 80)
			t.eq(rare.kind, "number")
			t.eq(rare.max, 100)
			-- Enum-keyed maps list keys the defaults leave out (to add them).
			t.ok(byPath["Loot.Tables.DungeonBoss.Rarity.Epic"] ~= nil)
			t.eq(byPath["Loot.Tables.DungeonBoss.Rarity.Epic"].value, nil)
			t.ok(byPath["Enhancement.RatesPct.10"] ~= nil)
			t.ok(byPath["PvP.MarksPerVictory"] ~= nil)
			t.ok(byPath["Flags.Maintenance"] ~= nil)
			t.eq(byPath["Flags.ConfigOverrides"], nil)
			t.eq(byPath["Net.GlobalCapacity"], nil)
		end)

		t.it("a batch of changes becomes a valid override; lists are written whole", function()
			local values, why = AdminRules.applyChanges(spec, {}, effective, {
				{ Path = "Loot.Tables.WarZoneBoss.Rarity.Rare", Number = 70 },
				{ Path = "Loot.Tables.WarZoneBoss.Rarity.Mythical", Number = 30 },
				{ Path = "Enhancement.RatesPct.10", Number = 40 },
				{ Path = "Flags.Maintenance", Bool = true },
			})
			t.ok(values ~= nil, why)
			t.eq(values.Loot.Tables.WarZoneBoss.Rarity.Mythical, 30)
			t.eq(#values.Enhancement.RatesPct, 10, "whole list")
			t.eq(values.Enhancement.RatesPct[10], 40)
			t.eq(values.Enhancement.RatesPct[1], Defaults.Enhancement.RatesPct[1])
			local ok, config = ConfigCore.resolve(Defaults, { version = 1, values = values }, spec, Schema)
			t.ok(ok, tostring(config))
			t.eq(config.Loot.Tables.WarZoneBoss.Rarity.Mythical, 30)
			t.eq(config.Loot.Tables.DungeonBoss.Rarity.Rare, 80, "untouched values keep the defaults")

			-- Reset removes the override (and empty parents).
			local reset = AdminRules.applyChanges(spec, values, effective, {
				{ Path = "Flags.Maintenance", Reset = true },
				{ Path = "Enhancement.RatesPct.3", Reset = true },
			})
			t.eq(reset.Flags, nil)
			t.eq(reset.Enhancement, nil, "a list resets whole")
			t.eq(reset.Loot.Tables.WarZoneBoss.Rarity.Rare, 70)
		end)

		t.it("refuses unknown paths, locked values and out-of-range or wrong-type values", function()
			local function why(change)
				local values, reason = AdminRules.applyChanges(spec, {}, effective, { change })
				t.eq(values, nil)
				return reason
			end
			t.eq(why({ Path = "Net.GlobalCapacity", Number = 9999 }), "path Net.GlobalCapacity")
			t.eq(why({ Path = "Flags.ConfigOverrides", Bool = false }), "path Flags.ConfigOverrides")
			t.eq(
				why({ Path = "Loot.Tables.Nope.DropChancePct", Number = 5 }),
				"path Loot.Tables.Nope.DropChancePct"
			)
			t.eq(why({ Path = "Loot.Tables.DungeonMob", Number = 5 }), "path Loot.Tables.DungeonMob")
			t.eq(why({ Path = "Enhancement.RatesPct.11", Number = 5 }), "path Enhancement.RatesPct.11")
			t.eq(
				why({ Path = "Loot.Tables.DungeonMob.DropChancePct", Number = 101 }),
				"value Loot.Tables.DungeonMob.DropChancePct"
			)
			t.eq(
				why({ Path = "Loot.Tables.DungeonMob.DropChancePct", Number = 0 / 0 }),
				"value Loot.Tables.DungeonMob.DropChancePct"
			)
			t.eq(
				why({ Path = "Loot.Tables.DungeonMob.DropChancePct", Bool = true }),
				"value Loot.Tables.DungeonMob.DropChancePct"
			)
			t.eq(why({ Path = "PvP.DailyCreditCap", Number = 2.5 }), "value PvP.DailyCreditCap")
			t.eq(why({ Path = "Flags.Maintenance", Number = 1 }), "value Flags.Maintenance")
		end)
	end)
end
