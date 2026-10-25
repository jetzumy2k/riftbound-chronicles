--[[
	Pure test runner. From the repository root:

	    lune run tests/pure/run

	Exits non-zero if any test fails.
]]

local process = require("@lune/process")

local harness = require("./harness")

-- Static list: keeps requires literal so they resolve the same in every Lune version.
local specs = {
	{ "enums_constants", require("./specs/enums_constants.spec") },
	{ "glyphs", require("./specs/glyphs.spec") },
	{ "admin_rules", require("./specs/admin_rules.spec") },
	{ "face_expressions", require("./specs/face_expressions.spec") },
	{ "schema", require("./specs/schema.spec") },
	{ "rate_bucket", require("./specs/rate_bucket.spec") },
	{ "signal", require("./specs/signal.spec") },
	{ "log", require("./specs/log.spec") },
	{ "guard", require("./specs/guard.spec") },
	{ "config_core", require("./specs/config_core.spec") },
	{ "registry", require("./specs/registry.spec") },
	{ "xp_table", require("./specs/xp_table.spec") },
	{ "stat_formulas", require("./specs/stat_formulas.spec") },
	{ "profile_validator", require("./specs/profile_validator.spec") },
	{ "migrations", require("./specs/migrations.spec") },
	{ "reward_claims", require("./specs/reward_claims.spec") },
	{ "profile_view", require("./specs/profile_view.spec") },
	{ "race_definitions", require("./specs/race_definitions.spec") },
	{ "face_presets", require("./specs/face_presets.spec") },
	{ "world_layout", require("./specs/world_layout.spec") },
	{ "world_budget", require("./specs/world_budget.spec") },
	{ "capital_terrain", require("./specs/capital_terrain.spec") },
	{ "creature_language", require("./specs/creature_language.spec") },
	{ "events", require("./specs/events.spec") },
	{ "attributes", require("./specs/attributes.spec") },
	{ "event_challenges", require("./specs/event_challenges.spec") },
	{ "mall", require("./specs/mall.spec") },
	{ "overlay_layout", require("./specs/overlay_layout.spec") },
	{ "mall_layout", require("./specs/mall_layout.spec") },
	{ "race_select_layout", require("./specs/race_select_layout.spec") },
	{ "motion_math", require("./specs/motion_math.spec") },
	{ "job_definitions", require("./specs/job_definitions.spec") },
	{ "job_select_layout", require("./specs/job_select_layout.spec") },
	{ "combat_math", require("./specs/combat_math.spec") },
	{ "movement_check", require("./specs/movement_check.spec") },
	{ "animation_clips", require("./specs/animation_clips.spec") },
	{ "combo_math", require("./specs/combo_math.spec") },
	{ "dungeon", require("./specs/dungeon.spec") },
	{ "dungeon_floors", require("./specs/dungeon_floors.spec") },
	{ "creature_ik", require("./specs/creature_ik.spec") },
	{ "mob_tactics", require("./specs/mob_tactics.spec") },
	{ "mob_flight", require("./specs/mob_flight.spec") },
	{ "mob_attacks", require("./specs/mob_attacks.spec") },
	{ "creature_sounds", require("./specs/creature_sounds.spec") },
	{ "level_gap", require("./specs/level_gap.spec") },
	{ "item_rules", require("./specs/item_rules.spec") },
	{ "inventory_layout", require("./specs/inventory_layout.spec") },
	{ "enhance_rules", require("./specs/enhance_rules.spec") },
	{ "loot_rules", require("./specs/loot_rules.spec") },
	{ "pvp", require("./specs/pvp.spec") },
	{ "skills", require("./specs/skills.spec") },
	{ "structure", require("./specs/structure.spec") },
	{ "quest_rules", require("./specs/quest_rules.spec") },
	{ "quest_layout", require("./specs/quest_layout.spec") },
	{ "hud_slots", require("./specs/hud_slots.spec") },
}

for _, entry in specs do
	harness.t.describe(entry[1], function()
		entry[2](harness.t)
	end)
end

local state = harness.state
for _, failure in state.failures do
	print(`FAIL {failure}\n`)
end
print(`\n{state.passed} passed, {state.failed} failed`)

process.exit(if state.failed == 0 then 0 else 1)
