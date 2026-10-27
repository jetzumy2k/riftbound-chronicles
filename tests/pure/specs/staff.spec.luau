--[[
	D-112: panel-assigned Moderators / Game Masters: feature ceilings, who
	may change what, and pay periods.
]]
local load = require("../loader")
local StaffRules = load("src/shared/Logic/StaffRules")
local AdminRules = load("src/shared/Logic/AdminRules")
local RewardClaims = load("src/server/Persistence/RewardClaims")

local NEVER = {
	"config.dropRates",
	"config.enhancement",
	"config.game",
	"config.view",
	"player.edit",
	"items.remove",
	"roles.assign",
	"system.reset",
	"staff.manage",
	"audit.viewAll",
}

return function(t)
	t.describe("Staff (D-112)", function()
		t.it("no panel role can ever reach economy, data or role powers", function()
			for _, role in StaffRules.ROLES do
				for _, p in StaffRules.CEILING[role] do
					t.ok(table.find(AdminRules.PERMISSIONS, p) ~= nil, `{role}: {p} is a real permission`)
					t.ok(table.find(NEVER, p) == nil, `{role} must not get {p}`)
					t.ok(StaffRules.FEATURE_NAMES[p] ~= nil, `{p} has a name`)
				end
				local all = StaffRules.clampPerms(role, NEVER)
				t.eq(#all, 1, "only panel.open survives clamping")
				t.eq(all[1], "panel.open")
			end
			t.ok(table.find(StaffRules.CEILING.GameMaster, "items.grant") ~= nil)
			t.ok(table.find(StaffRules.CEILING.Moderator, "items.grant") == nil)
		end)

		t.it("features are on only while active, and only within the ceiling", function()
			local record: any =
				{ role = "Moderator", perms = { "moderation.kick", "items.grant" }, status = "Active" }
			t.ok(StaffRules.allows(record, "moderation.kick"))
			t.ok(StaffRules.allows(record, "panel.open"), "panel.open is always on")
			t.ok(not StaffRules.allows(record, "items.grant"), "past the Moderator ceiling")
			record.status = "Pending"
			t.ok(not StaffRules.allows(record, "moderation.kick"), "waiting for approval: no powers")
			t.ok(not StaffRules.allows(nil, "panel.open"))
		end)

		t.it("an Admin's assignments wait for the Owner; removals and pay don't", function()
			t.eq(StaffRules.decide("Owner", "Assign"), "now")
			t.eq(StaffRules.decide("Admin", "Assign"), "approval")
			t.eq(StaffRules.decide("Admin", "SetPerms"), "approval")
			t.eq(StaffRules.decide("Admin", "Remove"), "now")
			t.eq(StaffRules.decide("Admin", "SetSalary"), "now")
			t.eq(StaffRules.decide("Moderator", "List"), nil)
			t.eq(StaffRules.decide(nil, "Assign"), nil)
			t.ok(AdminRules.has("Admin", "staff.manage"))
			t.ok(not AdminRules.has("Moderator", "staff.manage", { "staff.manage" }))
		end)

		t.it("pay is cleaned, keyed once per week or month, and pauses after 30 days away", function()
			local salary = StaffRules.cleanSalary({
				enabled = true,
				period = "Fortnightly",
				mallPoints = 999999,
				items = { { id = "HealingPotion", count = 500 }, { id = "Nope", count = 1 } },
				setRarity = "Mythical",
			}, function(id)
				return id == "HealingPotion"
			end)
			t.eq(salary.period, "Monthly")
			t.eq(salary.mallPoints, StaffRules.MAX_SALARY_POINTS)
			t.eq(#salary.items, 1)
			t.eq(salary.items[1].count, StaffRules.MAX_ITEM_COUNT)
			t.eq(salary.setRarity, nil, "no Mythical sets as pay")
			-- 2026-10-26 (Mon) and 2026-11-01 (Sun) share a week; 11-02 starts the next.
			local mon, sun, nextMon = 1792972800, 1793491200, 1793577600
			t.eq(StaffRules.periodKey("Weekly", mon), StaffRules.periodKey("Weekly", sun))
			t.ok(StaffRules.periodKey("Weekly", sun) ~= StaffRules.periodKey("Weekly", nextMon))
			t.eq(StaffRules.periodKey("Monthly", mon), "M2026-10")
			t.eq(StaffRules.periodKey("Monthly", sun), "M2026-11")
			t.ok(RewardClaims.isValidId(StaffRules.claimId("Weekly", mon)))
			t.ok(RewardClaims.isValidId(StaffRules.claimId("Monthly", mon)))
			t.ok(StaffRules.inactive(mon - 31 * 86400, mon))
			t.ok(not StaffRules.inactive(mon - 5 * 86400, mon))
			t.ok(not StaffRules.inactive(0, mon), "never seen yet is not inactive")
		end)
	end)
end
