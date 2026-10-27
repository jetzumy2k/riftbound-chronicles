--[[
	Phase 5 skill system (D-45): skill trees, points and ranks, the skill
	bar and cast rules, statuses, combos, damage / support math, player text,
	remote schemas and the touch / tree layouts.
]]

local load = require("../loader")
local Schema = load("src/shared/Logic/Schema")
local Registry = load("src/shared/Net/Registry")(Schema)
local SkillDefinitions = load("src/shared/Definitions/SkillDefinitions")
local Constants = load("src/shared/Constants")
local SkillIcons = load("src/shared/Definitions/SkillIcons")
local SkillRules = load("src/shared/Logic/SkillRules")
local JobDefinitions = load("src/shared/Definitions/JobDefinitions")
local BasicAttacks = load("src/shared/Definitions/BasicAttacks")
local AnimationClips = load("src/shared/Definitions/AnimationClips")
local CombatButtonsLayout = load("src/shared/Layout/CombatButtonsLayout")
local SkillTreeLayout = load("src/shared/Layout/SkillTreeLayout")
local Defaults = load("src/server/Config/Defaults")

local DEVICES = require("../devices")

local JOBS = { "Warrior", "Healer", "Archer", "Mage" }
local EFFECTS = {
	Damage = true,
	Heal = true,
	Shield = true,
	Poison = true,
	Burn = true,
	Regen = true,
	Stun = true,
	Freeze = true,
	Root = true,
	Slow = true,
	Silence = true,
	Mark = true,
	Weaken = true,
	Guard = true,
	Harden = true,
	Empower = true,
	Haste = true,
	Taunt = true,
	Cleanse = true,
	Dash = true,
	Reflect = true,
	Immune = true,
	Extend = true,
}
local CASTS = { Weapon = true, Hands = true, Raise = true, Circle = true }
local TRAVELS = { None = true, Bolt = true, Orb = true, Arrow = true, Lance = true, Missiles = true }
local IMPACTS = {
	Slash = true,
	Burst = true,
	Explosion = true,
	Shatter = true,
	Pillar = true,
	Ward = true,
	Heal = true,
	Sigil = true,
	Venom = true,
	Quake = true,
}
local AREAS =
	{ Nova = true, Whirl = true, Quake = true, Rain = true, Meteor = true, Blizzard = true, Circle = true }
local STATUSES = {
	Stun = true,
	Freeze = true,
	Root = true,
	Slow = true,
	Silence = true,
	Mark = true,
	Weaken = true,
	Poison = true,
	Burn = true,
}

-- Every skill of `job` at `rank` (max rank if nil).
local function learnAll(job: string, rank: number?): { [string]: number }
	local owned = {}
	for _, skill in SkillDefinitions.forJob(job) do
		owned[skill.id] = rank or skill.maxRank
	end
	return owned
end

local function castFacts(overrides: { [string]: any }?): { [string]: any }
	local facts = {
		job = "Warrior",
		owned = { CleavingStrike = 1, Whirlwind = 1, ShieldBash = 2, BladeStorm = 1 },
		loadout = { Regular = { "CleavingStrike", "Whirlwind", "ShieldBash" }, Special = "BladeStorm" },
		now = 100,
		readyAt = nil,
		globalReadyAt = 0,
		focus = 100,
		stunned = false,
		silenced = false,
		slack = 0.15,
	}
	for key, value in overrides or {} do
		facts[key] = value
	end
	return facts
end

-- Damage per second of one skill at a rank (direct + over time; no combos).
local function dps(skill, rank: number): number
	local total = 0
	for _, raw in skill.effects do
		local e = SkillRules.effectAtRank(raw, rank)
		if e.kind == "Damage" then
			total += (e.coefficient or 0) * (skill.waves or 1)
		elseif e.kind == "Poison" or e.kind == "Burn" then
			total += (e.coefficient or 0) * (e.seconds or 0) * (skill.waves or 1)
		end
	end
	return total / skill.cooldown
end

local function overlaps(a, b): boolean
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

-- Touch combat buttons are round (corner radius = half their size).
local function circlesOverlap(a, b): boolean
	local ax, ay, bx, by = a.x + a.w / 2, a.y + a.h / 2, b.x + b.w / 2, b.y + b.h / 2
	return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) < (a.w + b.w) / 2
end

return function(t)
	t.describe("skill trees", function()
		t.it(
			"every class has 4 branches x 6 tiers: 20 regular skills and 1 ultimate per branch (D-103)",
			function()
				for _, job in JOBS do
					local branches = SkillDefinitions.Branches[job]
					t.eq(#branches, 4, `{job} branches`)
					local regular, special = 0, 0
					for _, branch in branches do
						t.ok(SkillIcons.get(branch.icon) ~= nil, `{job} {branch.id} icon`)
						for tier = 1, SkillDefinitions.TIERS do
							local skill = SkillDefinitions.at(job, branch.id, tier)
							t.ok(skill ~= nil, `{job} {branch.id} tier {tier}`)
							if skill then
								t.eq(
									skill.type,
									if SkillDefinitions.SPECIAL_TIERS[tier] then "Special" else "Regular",
									skill.id
								)
								if skill.type == "Regular" then
									regular += 1
								else
									special += 1
								end
							end
						end
					end
					t.eq(regular, 20, `{job} regular`)
					t.eq(special, 4, `{job} ultimates, one per branch`)
					t.eq(#SkillDefinitions.forJob(job), 24, job)
				end
				t.eq(#SkillDefinitions.All, 96)
			end
		)

		t.it("ids are unique and every category is allowed for its job (CLAUDE.md §6)", function()
			local seen = {}
			for _, skill in SkillDefinitions.All do
				t.ok(not seen[skill.id], `duplicate {skill.id}`)
				seen[skill.id] = true
				t.eq(SkillDefinitions.get(skill.id), skill)
				t.ok(
					JobDefinitions.allowsSkillCategory(skill.job, skill.category),
					`{skill.id}: {skill.category} not allowed for {skill.job}`
				)
			end
		end)

		t.it("skills open level by level up to 30: tier 1 at 0, then tier level + column", function()
			for _, job in JOBS do
				local levels = {}
				for column, branch in SkillDefinitions.Branches[job] do
					local previous = -1
					for tier = 1, SkillDefinitions.TIERS do
						local skill = SkillDefinitions.at(job, branch.id, tier) :: any
						t.eq(skill.unlockLevel, SkillDefinitions.unlockLevelFor(tier, column), skill.id)
						t.ok(skill.unlockLevel > previous, `{skill.id} opens after the skill above it`)
						previous = skill.unlockLevel
						levels[skill.unlockLevel] = true
					end
				end
				t.ok(levels[0] and levels[30], `{job}: something opens at level 0 and at level 30`)
				local count = 0
				for _ in levels do
					count += 1
				end
				t.ok(count >= 20, `{job}: skills open on {count} different levels`)
			end
		end)

		t.it("each tier requires the skill above it", function()
			for _, skill in SkillDefinitions.All do
				t.eq(
					skill.maxRank,
					if skill.type == "Special"
						then SkillDefinitions.SPECIAL_MAX_RANK
						else SkillDefinitions.REGULAR_MAX_RANK,
					skill.id
				)
				if skill.tier == 1 then
					t.eq(skill.requires, nil, skill.id)
				else
					local above = SkillDefinitions.get(skill.requires)
					t.ok(
						above ~= nil and above.branch == skill.branch and above.tier == skill.tier - 1,
						`{skill.id} requires the tier above`
					)
				end
			end
		end)

		t.it("only Healers heal others; Mages never heal (CLAUDE.md §6.4)", function()
			for _, skill in SkillDefinitions.All do
				for _, effect in skill.effects do
					if effect.kind == "Heal" or effect.kind == "Regen" then
						t.ok(
							skill.job == "Healer" or (skill.job == "Warrior" and skill.target == "Self"),
							skill.id
						)
					end
				end
				if skill.job == "Mage" then
					t.eq(SkillDefinitions.effect(skill, "Heal"), nil, skill.id)
					t.eq(SkillDefinitions.effect(skill, "Regen"), nil, skill.id)
				end
			end
		end)

		t.it(
			"the trees cover the standard effects: slow, freeze, stun, area, heal, poison, hardening...",
			function()
				local seen = {}
				for _, skill in SkillDefinitions.All do
					for _, effect in skill.effects do
						seen[effect.kind] = true
					end
					if skill.target == "SelfArea" or skill.target == "EnemyArea" then
						seen.Area = true
					end
					if skill.combo then
						seen.Combo = true
					end
				end
				for kind in EFFECTS do
					t.ok(seen[kind], `no skill uses {kind}`)
				end
				t.ok(seen.Area and seen.Combo)
			end
		)

		t.it("every field is sane and every effect is complete", function()
			for _, skill in SkillDefinitions.All do
				local id = skill.id
				t.ok(#skill.name > 0 and #skill.description > 0, id)
				t.ok(SkillIcons.get(skill.icon) ~= nil, `{id} icon '{tostring(skill.icon)}'`)
				t.ok(SkillIcons.Elements[skill.fx.element] ~= nil, `{id} element colours`)
				-- D-103: the capstone ultimates may wait up to 2 minutes.
				local maxCooldown = if skill.tier == 6 then 120 else 60
				t.ok(skill.cooldown >= 3 and skill.cooldown <= maxCooldown, `{id} cooldown`)
				t.ok(skill.focusCost > 0 and skill.focusCost <= Defaults.Combat.FocusMax, `{id} focus`)
				t.ok(
					skill.clip ~= nil and AnimationClips.get(skill.clip) ~= nil,
					`{id} clip {tostring(skill.clip)}`
				)
				local fx = skill.fx
				t.ok(fx ~= nil and CASTS[fx.cast] and TRAVELS[fx.travel] and IMPACTS[fx.impact], `{id} fx`)
				t.ok(fx.area == nil or AREAS[fx.area], `{id} area fx`)
				if skill.target == "Enemy" or skill.target == "Ally" or skill.target == "EnemyArea" then
					t.ok(skill.range > 0 and skill.range <= 60, `{id} range`)
				end
				if skill.target == "SelfArea" or skill.target == "EnemyArea" then
					t.ok(skill.radius ~= nil and skill.radius > 0 and skill.radius <= 24, `{id} radius`)
					t.ok(
						skill.maxTargets ~= nil and skill.maxTargets <= Defaults.Skills.MaxAreaTargets,
						`{id} targets`
					)
				end
				t.ok(#skill.effects > 0, `{id} effects`)
				for _, effect in skill.effects do
					local kind = effect.kind
					t.ok(EFFECTS[kind], `{id} effect {kind}`)
					if kind == "Damage" or kind == "Heal" or kind == "Shield" then
						t.ok(
							effect.coefficient and effect.coefficient > 0 and effect.coefficient <= 3.2,
							`{id} coefficient`
						)
					end
					if kind == "Poison" or kind == "Burn" or kind == "Regen" then
						t.ok(effect.coefficient and effect.coefficient <= 0.3, `{id} {kind} per second`)
					end
					if
						kind ~= "Damage"
						and kind ~= "Heal"
						and kind ~= "Cleanse"
						and kind ~= "Dash"
						and kind ~= "Extend"
					then
						t.ok(
							effect.seconds and effect.seconds > 0 and effect.seconds <= 10,
							`{id} {kind} seconds`
						)
					end
					if kind == "Guard" or kind == "Slow" or kind == "Mark" or kind == "Weaken" then
						t.ok(effect.pct and effect.pct > 0 and effect.pct <= 50, `{id} {kind} pct`)
					end
					if kind == "Harden" or kind == "Empower" or kind == "Haste" then
						t.ok(effect.pct and effect.pct > 0 and effect.pct <= 40, `{id} {kind} pct`)
					end
					if kind == "Stun" or kind == "Freeze" then
						t.ok((effect.seconds or 0) <= 1.5, `{id} stuns stay short`)
					end
					-- D-103 limits (creator decisions 2026-10-26).
					if kind == "Reflect" then
						t.ok(effect.pct and effect.pct <= 100 and (effect.seconds or 0) <= 5, `{id} reflect`)
					elseif kind == "Immune" then
						t.ok((effect.seconds or 0) <= 8 and skill.cooldown >= 90, `{id} immunity stays short`)
					elseif kind == "Extend" then
						t.ok(effect.pct and effect.pct <= 50, `{id} extend pct`)
						t.ok((effect.pulses or 1) >= 1 and (effect.pulses or 1) <= 3, `{id} extend pulses`)
						t.ok((effect.coefficient or 1) <= 1.5, `{id} extend power`)
					end
					if effect.perPointPct then
						t.ok(effect.attribute ~= nil and effect.perPointPct <= 0.5, `{id} attribute scaling`)
					end
					if effect.hpPct then
						t.ok(effect.hpPct <= 10, `{id} HP scaling`)
					end
				end
				if skill.combo then
					local combo = skill.combo
					t.ok((combo.status and STATUSES[combo.status]) or combo.lowHpPct, `{id} combo condition`)
					t.ok(combo.bonusPct > 0 and combo.bonusPct <= 100 and #combo.name > 0, `{id} combo`)
					t.ok(SkillDefinitions.effect(skill, "Damage") ~= nil, `{id} combo needs damage`)
				end
			end
		end)

		t.it("every combo status can be applied by some skill (teamwork across classes)", function()
			local applied = {}
			for _, skill in SkillDefinitions.All do
				for _, effect in skill.effects do
					applied[effect.kind] = true
				end
			end
			for _, skill in SkillDefinitions.All do
				if skill.combo and skill.combo.status then
					t.ok(applied[skill.combo.status], `{skill.id}: nothing applies {skill.combo.status}`)
				end
			end
		end)

		t.it("a full bar at max rank adds burst without more than doubling basic-attack damage", function()
			for _, job in JOBS do
				local regular, special = {}, 0
				for _, skill in SkillDefinitions.forJob(job) do
					local d = dps(skill, skill.maxRank)
					if skill.type == "Regular" then
						table.insert(regular, d)
					else
						special = math.max(special, d)
					end
				end
				table.sort(regular, function(a, b)
					return a > b
				end)
				local best = regular[1] + regular[2] + regular[3] + special
				local chain = BasicAttacks.chainDps(BasicAttacks.ByJob[job])
				t.ok(best <= chain * 1.15, `{job}: best bar {best} vs basic chain {chain}`)
			end
		end)

		t.it("Focus regen sustains any 3 regular skills on cooldown", function()
			for _, job in JOBS do
				local costs = {}
				for _, skill in SkillDefinitions.forJob(job) do
					if skill.type == "Regular" then
						table.insert(costs, skill.focusCost / skill.cooldown)
					end
				end
				table.sort(costs, function(a, b)
					return a > b
				end)
				local perSecond = costs[1] + costs[2] + costs[3]
				t.ok(perSecond <= Defaults.Combat.FocusRegenPerSecond, `{job} spends {perSecond}/s`)
			end
		end)
	end)

	t.describe("points and learning", function()
		t.it("1 point at level 0 plus 3 per level; the Studio bonus only adds", function()
			t.eq(SkillRules.pointsFor(0), 1)
			t.eq(SkillRules.pointsFor(30), 91)
			t.eq(SkillRules.pointsFor(5, 10), 26)
			t.eq(SkillRules.available({ CleavingStrike = 3, Whirlwind = 2 }, 10), 26)
			-- A fully ranked tree costs more than a level-30 character has: choices matter.
			t.ok(SkillRules.spent(learnAll("Warrior")) > SkillRules.pointsFor(30))
		end)

		t.it("learns tier 1 at level 0, then needs the skill above and the tier level", function()
			t.ok(SkillRules.canLearn("Warrior", {}, 0, 0, false, "CleavingStrike"))
			local function reason(owned, level, id, bonus, unlockAll)
				local ok, why =
					SkillRules.canLearn("Warrior", owned, level, bonus or 0, unlockAll == true, id)
				t.ok(not ok)
				return why
			end
			t.eq(reason({}, 30, "Whirlwind", 5), "requires")
			t.eq(reason({ CleavingStrike = 1 }, 2, "Whirlwind", 5), "locked")
			t.ok(SkillRules.canLearn("Warrior", { CleavingStrike = 1 }, 3, 0, false, "Whirlwind"))
			-- Later columns open a level later: Ironclad tier 2 at 4.
			t.eq(reason({ ShieldBash = 1 }, 3, "IronSkin", 5), "locked")
			t.ok(SkillRules.canLearn("Warrior", { ShieldBash = 1 }, 4, 0, false, "IronSkin"))
			t.eq(reason({ CleavingStrike = 1 }, 0, "ShieldBash"), "noPoints")
			t.eq(reason({ CleavingStrike = 5 }, 30, "CleavingStrike"), "maxRank")
			-- Higher ranks open with level (rank 2 at level 6).
			t.eq(reason({ CleavingStrike = 1 }, 5, "CleavingStrike", 5), "rankLocked")
			t.ok(SkillRules.canLearn("Warrior", { CleavingStrike = 1 }, 6, 0, false, "CleavingStrike"))
			t.eq(reason({}, 30, "Fireball"), "wrongJob")
			t.eq(reason({}, 30, "Nope"), "wrongJob")
			t.eq(select(2, SkillRules.canLearn(nil, {}, 30, 0, false, "CleavingStrike")), "noJob")
			-- Studio unlock-all lifts only the level gate.
			t.ok(SkillRules.canLearn("Warrior", { CleavingStrike = 1 }, 0, 5, true, "Whirlwind"))
			t.eq(reason({}, 0, "Whirlwind", 5, true), "requires")
		end)

		t.it("rank caps rise with level until every rank is open", function()
			local strike = SkillDefinitions.get("CleavingStrike") :: any
			local storm = SkillDefinitions.get("BladeStorm") :: any
			t.eq(SkillRules.rankCap(strike, 0), 1)
			t.eq(SkillRules.rankCap(strike, 5), 1)
			t.eq(SkillRules.rankCap(strike, 6), 2)
			t.eq(SkillRules.rankCap(strike, 23), 4)
			t.eq(SkillRules.rankCap(strike, 24), 5)
			t.eq(SkillRules.rankCap(strike, 30), 5)
			t.eq(SkillRules.rankCap(storm, 30), 3, "specials stop at 3")
			t.eq(SkillRules.rankCap(strike, 0, true), 5, "Studio unlock-all")
			t.eq(SkillRules.rankLevel(1), 0)
			t.eq(SkillRules.rankLevel(5), 24)
		end)

		t.it("fitToLevel drops skills and ranks the level doesn't open", function()
			local fitted, changed = SkillRules.fitToLevel(
				{ CleavingStrike = 4, Whirlwind = 2, BladeFlurry = 1, BladeStorm = 3, Nope = 1 },
				6
			)
			t.ok(changed)
			t.eq(fitted.CleavingStrike, 2)
			t.eq(fitted.Whirlwind, 2)
			t.eq(fitted.BladeFlurry, nil, "opens at 8")
			t.eq(fitted.BladeStorm, nil)
			t.eq(fitted.Nope, nil)
			local same, unchanged = SkillRules.fitToLevel({ CleavingStrike = 1 }, 0)
			t.ok(not unchanged)
			t.eq(same.CleavingStrike, 1)
			local studio, kept = SkillRules.fitToLevel({ BladeStorm = 3 }, 0, true)
			t.ok(not kept)
			t.eq(studio.BladeStorm, 3)
		end)

		t.it("level-up notices list the skills that just opened", function()
			local names = {}
			for _, skill in SkillRules.unlockedBetween("Warrior", 2, 3) do
				table.insert(names, skill.id)
			end
			t.eq(table.concat(names, ","), "Whirlwind")
			t.eq(#SkillRules.unlockedBetween("Warrior", 29, 30), 1)
			t.eq(#SkillRules.unlockedBetween("Warrior", 0, 30), 20)
			t.eq(#SkillRules.unlockedBetween(nil, 0, 30), 0)
		end)

		t.it("ranks scale numbers; control and percentages stay capped", function()
			local strike = SkillDefinitions.effect(SkillDefinitions.get("CleavingStrike"), "Damage")
			t.ok(math.abs(SkillRules.effectAtRank(strike, 1).coefficient - strike.coefficient) < 1e-9)
			t.ok(math.abs(SkillRules.effectAtRank(strike, 5).coefficient - strike.coefficient * 1.48) < 1e-9)
			for _, skill in SkillDefinitions.All do
				for _, effect in skill.effects do
					local top = SkillRules.effectAtRank(effect, skill.maxRank)
					if top.kind == "Stun" then
						t.ok(top.seconds <= SkillRules.CAPS.Stun, skill.id)
					elseif top.kind == "Freeze" then
						t.ok(top.seconds <= SkillRules.CAPS.Freeze, skill.id)
					end
					if top.pct then
						local cap = if top.kind == "Reflect"
							then SkillRules.CAPS.ReflectPct
							else SkillRules.CAPS.Pct
						t.ok(top.pct <= cap, skill.id)
					end
					if top.kind == "Extend" then
						t.eq(top.coefficient, effect.coefficient, `{skill.id}: ranks only widen an Extender`)
					end
				end
			end
		end)
	end)

	t.describe("skill bar (T-04)", function()
		local owned = learnAll("Warrior", 1)

		t.it("accepts any 3 learned regular skills plus 1 learned special", function()
			t.ok(
				SkillRules.validateLoadout(
					"Warrior",
					owned,
					{ "Execution", "IronSkin", "Hamstring" },
					"Earthsplitter"
				)
			)
			t.ok(SkillRules.validateLoadout("Warrior", owned, {}, nil), "empty is fine")
		end)

		t.it("rejects unlearned, wrong-job, wrong-slot, duplicate and extra skills", function()
			local function reason(regular, special, o)
				local ok, why = SkillRules.validateLoadout("Warrior", o or owned, regular, special)
				t.ok(not ok)
				return why
			end
			t.eq(reason({ "Fireball" }, nil), "notLearned")
			t.eq(reason({ "Whirlwind" }, nil, { CleavingStrike = 1 }), "notLearned")
			t.eq(reason({ "BladeStorm" }, nil), "wrongSlot")
			t.eq(reason({}, "Whirlwind"), "wrongSlot")
			t.eq(reason({ "Whirlwind", "Whirlwind" }, nil), "duplicate")
			local seven = {}
			for _, skill in SkillDefinitions.forJob("Warrior") do
				if skill.type == "Regular" and #seven < SkillRules.REGULAR_SLOTS + 1 then
					table.insert(seven, skill.id)
				end
			end
			t.eq(#seven, 7)
			t.eq(reason(seven, nil), "tooMany")
			table.remove(seven)
			t.ok(SkillRules.validateLoadout("Warrior", owned, seven, nil), "six regular skills fit")
			t.eq(SkillRules.REGULAR_SLOTS, Constants.Loadout.RegularSlots)
			t.eq(select(2, SkillRules.validateLoadout(nil, owned, {}, nil)), "noJob")
		end)

		t.it("auto-fill adds learned skills to empty slots and never moves the player's choices", function()
			local first = SkillRules.autoFill("Warrior", { ShieldBash = 1 }, { Regular = {}, Special = nil })
			-- Auto Attack first (a new character's slot 1), then learned skills.
			t.eq(table.concat(first.Regular, ","), "AutoAttack,ShieldBash")
			local custom = SkillRules.autoFill("Warrior", owned, { Regular = { "Hamstring" }, Special = nil })
			t.eq(custom.Regular[1], "Hamstring")
			t.eq(#custom.Regular, 6)
			t.ok(custom.Special ~= nil)
			t.ok(SkillRules.validateLoadout("Warrior", owned, custom.Regular, custom.Special))
		end)

		t.it(
			"Auto Attack: every class knows it free, slots in a regular slot, never learned or cast",
			function()
				local id = SkillDefinitions.AUTO_ATTACK
				local skill = SkillDefinitions.get(id)
				t.ok(skill ~= nil and SkillDefinitions.isBasic(skill), "defined and basic")
				t.eq((skill :: any).type, "Regular")
				t.ok(table.find(SkillDefinitions.IDS, id) ~= nil, "remotes accept it")
				t.ok(table.find(SkillDefinitions.All, skill) == nil, "not in any class tree")
				for _, job in { "Warrior", "Healer", "Archer", "Mage" } do
					t.eq(SkillRules.rankOf({}, id), 1)
					t.ok(SkillRules.validateLoadout(job, {}, { id }, nil), `{job} can slot it with no points`)
					local ok, reason = SkillRules.canLearn(job, {}, 30, 0, false, id)
					t.eq(ok, false)
					t.eq(reason, "basic")
				end
				-- Free: it never uses a skill point.
				t.eq(SkillRules.available({}, 0), SkillRules.pointsFor(0))
				local ok, reason = SkillRules.canCast(
					id,
					{
						job = "Warrior",
						owned = {},
						loadout = { Regular = { id }, Special = nil },
						stunned = false,
						silenced = false,
						now = 10,
						globalReadyAt = 0,
						readyAt = nil,
						slack = 0,
						focus = 100,
					} :: any
				)
				t.eq(ok, false)
				t.eq(reason, "basic")
				-- A full bar keeps the player's choices (no forced slot).
				local full = SkillRules.autoFill("Warrior", owned, {
					Regular = {
						"Hamstring",
						"ShieldBash",
						"Whirlwind",
						"IronSkin",
						"Execution",
						"CleavingStrike",
					},
				})
				t.ok(table.find(full.Regular, id) == nil, "not forced onto a full bar")
				-- Pruning keeps it.
				t.eq(SkillRules.prune("Warrior", {}, { Regular = { id }, Special = nil }).Regular[1], id)
			end
		)

		t.it("a reset prunes skills that are no longer learned", function()
			local pruned = SkillRules.prune(
				"Warrior",
				{ Hamstring = 1 },
				{ Regular = { "Whirlwind", "Hamstring" }, Special = "BladeStorm" }
			)
			t.eq(table.concat(pruned.Regular, ","), "Hamstring")
			t.eq(pruned.Special, nil)
		end)
	end)

	t.describe("casting (T-03 / T-04)", function()
		t.it("an equipped, learned, ready skill with Focus can be cast", function()
			t.ok(SkillRules.canCast("CleavingStrike", castFacts()))
		end)

		t.it("rejects unequipped, unlearned, stunned, silenced, cooldown, busy and no-Focus casts", function()
			local function reason(id, overrides)
				local ok, why = SkillRules.canCast(id, castFacts(overrides))
				t.ok(not ok)
				return why
			end
			t.eq(reason("CleavingStrike", { loadout = { Regular = { "Whirlwind" } } }), "notEquipped")
			t.eq(reason("Execution", nil), "notLearned")
			t.eq(reason("Fireball", nil), "notLearned")
			t.eq(reason("CleavingStrike", { stunned = true }), "stunned")
			t.eq(reason("CleavingStrike", { silenced = true }), "silenced")
			t.eq(reason("CleavingStrike", { readyAt = 101 }), "cooldown")
			t.eq(reason("CleavingStrike", { globalReadyAt = 100.5 }), "busy")
			t.eq(reason("Whirlwind", { focus = 21 }), "noFocus")
		end)

		t.it("forgives only a tiny network slack on cooldowns", function()
			t.ok(SkillRules.canCast("CleavingStrike", castFacts({ readyAt = 100.1 })), "within slack")
			t.ok(not SkillRules.canCast("CleavingStrike", castFacts({ readyAt = 100.3 })), "beyond slack")
		end)
	end)

	t.describe("statuses, combos and support", function()
		t.it("incoming damage: mark adds, guard subtracts, shield absorbs first", function()
			local hp, absorbed, left = SkillRules.incoming(100, 0, 0, 0)
			t.eq(hp, 100)
			t.eq(absorbed, 0)
			t.eq(left, 0)
			t.eq((SkillRules.incoming(100, 15, 0, 0)), 115)
			t.eq((SkillRules.incoming(100, 0, 40, 0)), 60)
			hp, absorbed, left = SkillRules.incoming(100, 0, 0, 30)
			t.eq(hp, 70)
			t.eq(absorbed, 30)
			t.eq(left, 0)
			hp, absorbed, left = SkillRules.incoming(100, 0, 0, 500)
			t.eq(hp, 0)
			t.eq(absorbed, 100)
			t.eq(left, 400)
			-- Guard never makes anyone invulnerable.
			t.eq((SkillRules.incoming(100, 0, 100, 0)), 10)
		end)

		t.it("empower and weaken scale attack, never below 10%", function()
			t.eq(SkillRules.attackScale(0, 0), 1)
			t.ok(math.abs(SkillRules.attackScale(20, 0) - 1.2) < 1e-9)
			t.ok(math.abs(SkillRules.attackScale(0, 20) - 0.8) < 1e-9)
			t.eq(SkillRules.attackScale(0, 100), 0.1)
		end)

		t.it("combos trigger on their status or low HP only", function()
			local shatter = SkillDefinitions.get("FrostBolt").combo
			local function has(list)
				return function(kind)
					return table.find(list, kind) ~= nil
				end
			end
			t.ok(SkillRules.comboApplies(shatter, has({ "Freeze" }), 1))
			t.ok(not SkillRules.comboApplies(shatter, has({ "Slow" }), 1))
			local execute = SkillDefinitions.get("Execution").combo
			t.ok(SkillRules.comboApplies(execute, has({}), 0.2))
			t.ok(not SkillRules.comboApplies(execute, has({}), 0.5))
			t.ok(not SkillRules.comboApplies(nil, has({ "Freeze" }), 0.1))
		end)

		t.it("heals and buffs only reach players of your own realm (D-24)", function()
			local facts = {
				helperIsPlayer = true,
				targetIsPlayer = true,
				helperRace = "Angel",
				targetRace = "Angel",
				helperDefeated = false,
				targetDefeated = false,
				helperInSafeZone = false,
				targetInSafeZone = false,
				targetInCombat = true,
			}
			t.ok(SkillRules.canHelp(facts))
			local function with(key, value)
				local copy = table.clone(facts)
				copy[key] = value
				return select(2, SkillRules.canHelp(copy))
			end
			t.eq(with("targetRace", "Devil"), "notAlly")
			t.eq(with("targetIsPlayer", false), "notAlly")
			t.eq(with("targetDefeated", true), "targetDefeated")
			t.eq(with("helperInSafeZone", true), "safeZone")
			local resting = table.clone(facts)
			resting.helperInSafeZone = true
			resting.targetInCombat = false
			t.ok(SkillRules.canHelp(resting))
		end)

		t.it(
			"control: bosses ignore it but can be taunted; PvP control is shorter; buffs aren't control",
			function()
				local scale = Defaults.Skills.PvPControlScale
				t.ok(scale > 0 and scale < 1)
				for _, kind in { "Stun", "Freeze", "Root", "Slow", "Silence" } do
					t.eq(SkillRules.controlSeconds(kind, 1, true, false, scale), 0, kind)
					t.eq(SkillRules.controlSeconds(kind, 1, false, true, scale), scale, kind)
					t.eq(SkillRules.controlSeconds(kind, 1, false, false, scale), 1, kind)
				end
				t.eq(SkillRules.controlSeconds("Taunt", 5, true, false, scale), 5)
				t.eq(SkillRules.controlSeconds("Taunt", 5, false, true, scale), 0)
				t.eq(SkillRules.controlSeconds("Haste", 3, true, true, scale), 3)
				t.ok(Defaults.Skills.ControlImmunitySeconds >= 1, "no chain-stunning players")
			end
		)
	end)

	t.describe("D-103 ultimates, Extender and execute", function()
		t.it("reflect returns the hit, capped per hit and halved in PvP", function()
			t.eq(SkillRules.reflected(400, 100, 1000, 1), 400)
			t.eq(SkillRules.reflected(400, 100, 250, 1), 250, "cap")
			t.eq(SkillRules.reflected(400, 100, 1000, 0.5), 200, "PvP")
			t.eq(SkillRules.reflected(400, 300, 1000, 1), 400, "never more than the hit")
			t.eq(SkillRules.reflected(-5, 100, 1000, 1), 0)
		end)

		t.it("ultimates scale with attribute points (capped) and max HP", function()
			local e = { kind = "Damage", coefficient = 2, attribute = "STR", perPointPct = 0.5, hpPct = 5 }
			-- 100 STR = +50%; 5% of 4,000 HP against 1,000 Attack = +0.2.
			t.ok(math.abs(SkillRules.boostedCoefficient(2, e :: any, 100, 4000, 1000, 100) - 3.2) < 1e-9)
			-- 300 STR would be +150%, capped at +100%.
			t.ok(math.abs(SkillRules.boostedCoefficient(2, e :: any, 300, 0, 1000, 100) - 4) < 1e-9)
			t.eq(SkillRules.boostedCoefficient(2, { kind = "Damage" } :: any, 100, 4000, 1000, 100), 2)
		end)

		t.it("an Extender widens the area up to a cap", function()
			t.eq(SkillRules.extendedRadius(10, 40, 30), 14)
			t.eq(SkillRules.extendedRadius(24, 50, 30), 30)
		end)

		t.it("each class has an Extender and the execute / reflect / immune ultimates", function()
			local extenders, executes = {}, {}
			for _, skill in SkillDefinitions.All do
				if SkillDefinitions.effect(skill, "Extend") then
					extenders[skill.job] = true
				end
				if skill.combo and skill.combo.execute then
					executes[skill.id] = true
					t.ok(
						skill.combo.lowHpPct ~= nil and skill.combo.lowHpPct <= 35,
						`{skill.id} execute threshold`
					)
				end
			end
			for _, job in JOBS do
				t.ok(extenders[job], `{job} has an Extender`)
			end
			t.ok(executes.Execution and executes.BladeStorm and executes.Heartseeker)
			t.ok(SkillDefinitions.effect(SkillDefinitions.get("Unbreakable"), "Reflect") ~= nil)
			t.ok(SkillDefinitions.effect(SkillDefinitions.get("AegisOfDawn"), "Immune") ~= nil)
			t.ok(
				SkillDefinitions.effect(SkillDefinitions.get("SweepingBlow"), "Mark") ~= nil,
				"corrupting area"
			)
			local charge = SkillDefinitions.effect(SkillDefinitions.get("CleavingStrike"), "Dash")
			t.ok(charge ~= nil and charge.toward == true, "Warrior charge")
			-- Mage ultimates use INT (D-90 magic damage), not WIS.
			local meteor = SkillDefinitions.effect(SkillDefinitions.get("Meteor"), "Damage")
			t.eq(meteor.attribute, "INT")
		end)

		t.it("new numbers have config defaults inside their schema", function()
			local skills = Defaults.Skills
			t.ok(skills.ReflectCapPctOfMaxHp > 0 and skills.ReflectCapPctOfMaxHp <= 100)
			t.ok(skills.PvPReflectScale > 0 and skills.PvPReflectScale <= 1)
			t.ok(skills.ImmunePvPCutPct > 0 and skills.ImmunePvPCutPct < 100, "no full immunity in PvP")
			t.ok(skills.ExtendWindowSeconds > 0 and skills.ExtendMaxRadius >= 24)
			t.eq(skills.ExecuteCreatures, true)
		end)

		t.it("tooltips describe the new effects", function()
			local reflect = SkillRules.describe(SkillDefinitions.get("Unbreakable"), 1)
			t.ok(string.find(table.concat(reflect.effects, "|"), "Reflects 100%", 1, true) ~= nil)
			local storm = SkillRules.describe(SkillDefinitions.get("BladeStorm"), 1)
			t.ok(string.find(table.concat(storm.effects, "|"), "max HP", 1, true) ~= nil)
			t.ok(string.find(storm.combo or "", "creatures fall at once", 1, true) ~= nil)
			local sunder = SkillRules.describe(SkillDefinitions.get("Sunder"), 1)
			t.ok(string.find(table.concat(sunder.effects, "|"), "EXTENDER", 1, true) ~= nil)
		end)
	end)

	t.describe("skill information text", function()
		t.it("every skill describes every effect, its combo and the next rank", function()
			for _, skill in SkillDefinitions.All do
				local info = SkillRules.describe(skill, 1)
				t.ok(#info.header > 0 and #info.stats > 0 and #info.target > 0, skill.id)
				t.ok(#info.effects >= #skill.effects, `{skill.id} effects described`)
				for _, line in info.effects do
					t.ok(#line > 0 and not string.find(line, "nil", 1, true), `{skill.id}: {line}`)
				end
				t.eq(info.combo ~= nil, skill.combo ~= nil, `{skill.id} combo text`)
				t.ok(info.nextRank ~= nil, `{skill.id} next rank`)
				t.eq(SkillRules.describe(skill, skill.maxRank).nextRank, nil, `{skill.id} at max rank`)
			end
			local text = SkillRules.describe(SkillDefinitions.get("CleavingStrike"), 1)
			t.eq(text.effects[1], "Charges 11 studs at the target")
			t.eq(text.effects[2], "Deals 135% Attack damage")
			t.ok(string.find(text.combo or "", "Crushing Blow", 1, true) ~= nil)
		end)
	end)

	t.describe("remotes", function()
		local function valid(name, args)
			return (Schema.validateArgs(Registry[name].args, #args, args))
		end

		t.it("SetLoadout takes at most 6 regular skills plus 1 special", function()
			local six = { "CleavingStrike", "Whirlwind", "Execution", "IronSkin", "Hamstring", "ShieldBash" }
			t.ok(valid("SetLoadout", { six, "BladeStorm" }))
			t.ok(valid("SetLoadout", { {} }))
			local seven = table.clone(six)
			table.insert(seven, "AutoAttack")
			t.ok(not valid("SetLoadout", { seven }), "7th slot")
			t.ok(not valid("SetLoadout", { { "Nope" } }), "unknown id")
			t.ok(not valid("SetLoadout", { { "CleavingStrike" }, 7 }), "special type")
		end)

		t.it("SkillCast takes a skill id and an optional target only", function()
			t.ok(valid("SkillCast", { "CleavingStrike" }))
			t.ok(not valid("SkillCast", { "Nope" }), "unknown id")
			t.ok(not valid("SkillCast", { 5 }), "number id")
			t.ok(not valid("SkillCast", { "CleavingStrike", "damage" }), "string target")
			t.ok(not valid("SkillCast", { "CleavingStrike", nil, 9999 }), "extra argument")
			t.eq(Registry.SkillCast.rate.capacity, 4)
		end)

		t.it("LearnSkill takes one known skill id; ResetSkills takes nothing", function()
			t.ok(valid("LearnSkill", { "Fireball" }))
			t.ok(not valid("LearnSkill", { "Nope" }))
			t.ok(not valid("LearnSkill", { "Fireball", 3 }), "no rank argument")
			t.ok(valid("ResetSkills", {}))
			t.ok(not valid("ResetSkills", { true }))
		end)

		t.it("the client learns cooldowns, never sends outcomes", function()
			t.eq(Registry.SkillCooldown.direction, "ServerToClient")
			t.ok(table.find(Registry.SkillCast.states, "Alive") ~= nil)
			t.eq(Registry.CombatEvent.direction, "ServerToClient")
		end)
	end)

	t.describe("touch buttons (CLAUDE.md §28)", function()
		for _, device in DEVICES do
			local name, width, height = device[1], device[2], device[3]
			t.it(`{name}: on screen, ≥ 44 px, no overlaps, clear of the jump button and HUD`, function()
				local layout = CombatButtonsLayout.compute(width, height)
				local keys = CombatButtonsLayout.shownKeys(layout)
				local rects = {}
				for _, key in keys do
					local slot = (layout :: any)[key]
					t.ok(slot.size >= CombatButtonsLayout.MIN_TOUCH_PX, `{key} size`)
					local r = CombatButtonsLayout.rect(slot, width, height)
					t.ok(r.x >= 0 and r.y >= 0, `{key} off screen`)
					t.ok(
						slot.right >= CombatButtonsLayout.JUMP_ZONE
							or slot.bottom >= CombatButtonsLayout.JUMP_ZONE,
						`{key} jump`
					)
					rects[key] = r
				end
				-- HudController: panels in the top-left 260 x 160 px, scaled by
				-- clamp(height / 720, 0.85, 1.35).
				local scale = math.clamp(height / 720, 0.85, 1.35)
				local hud = { x = 0, y = 0, w = 260 * scale, h = 160 * scale }
				-- The SKILLS / BAG toggles are part of the same corner (D-86).
				local toggles = CombatButtonsLayout.toggles(width, height)
				for _, id in { "skills", "bag" } do
					local r = CombatButtonsLayout.toggleRect(toggles[id], width, height)
					t.ok(r.x >= 0 and r.y >= 0, `{id} toggle off screen`)
					t.ok(
						r.w >= CombatButtonsLayout.MIN_TOUCH_PX and r.h >= CombatButtonsLayout.MIN_TOUCH_PX,
						`{id} toggle size`
					)
					t.ok(
						toggles[id].right >= CombatButtonsLayout.JUMP_ZONE
							or toggles[id].bottom >= CombatButtonsLayout.JUMP_ZONE,
						`{id} toggle jump`
					)
					rects[id] = r
					table.insert(keys, id)
				end
				t.ok(not overlaps(rects.skills, rects.bag), "toggles overlap")
				table.remove(keys)
				table.remove(keys)
				-- Phone landscape: the cluster stays out of the middle of the
				-- screen, where the character stands.
				if layout.mode == "arc" then
					for _, key in keys do
						t.ok(rects[key].x > width * 0.4, `{key} reaches the middle ({rects[key].x})`)
					end
				end
				for _, id in { "skills", "bag" } do
					t.ok(not overlaps(rects[id], hud), `{id} toggle overlaps the HUD`)
					for _, key in keys do
						t.ok(not overlaps(rects[id], rects[key]), `{id} toggle overlaps {key}`)
					end
				end
				for i = 1, #keys do
					t.ok(not overlaps(rects[keys[i]], hud), `{keys[i]} overlaps the HUD`)
					for j = i + 1, #keys do
						t.ok(
							not circlesOverlap(rects[keys[i]], rects[keys[j]]),
							`{keys[i]} overlaps {keys[j]}`
						)
					end
				end
			end)
		end
	end)

	t.describe("skill tree screen", function()
		for _, device in DEVICES do
			local name, width, height = device[1], device[2], device[3]
			t.it(`{name}: panel fits, nodes ≥ 44 px and never overlap`, function()
				local layout = SkillTreeLayout.compute(width, height)
				local p = layout.panel
				t.ok(p.x >= 0 and p.y >= 0 and p.x + p.w <= width and p.y + p.h <= height, "panel on screen")
				t.ok(layout.node >= SkillTreeLayout.MIN_TOUCH_PX, "node size")
				-- The bar scrolls sideways when the 7 slots don't fit (D-75).
				t.ok(layout.barSlot >= SkillTreeLayout.MIN_TOUCH_PX, "bar slot size")
				local rects = {}
				-- A node is its tile, the rank badge (4 px out) and its label
				-- (column width - 4) underneath.
				local cell = math.max(layout.columnWidth - 4, layout.node + 8)
				for key, center in layout.nodes do
					local r = {
						x = center.x - cell / 2,
						y = center.y - layout.node / 2 - 7,
						w = cell,
						h = layout.node + 9 + SkillTreeLayout.LABEL_HEIGHT,
					}
					t.ok(r.x >= -0.5 and r.x + r.w <= layout.tree.w + 0.5, `{key} inside the tree`)
					t.ok(r.y >= 0 and r.y + r.h <= layout.tree.h + 0.5, `{key} inside the tree (vertical)`)
					table.insert(rects, r)
				end
				t.eq(#rects, SkillTreeLayout.BRANCHES * SkillTreeLayout.TIERS)
				t.eq(SkillTreeLayout.BRANCHES, SkillDefinitions.BRANCHES)
				t.eq(SkillTreeLayout.TIERS, SkillDefinitions.TIERS)
				for i = 1, #rects do
					for j = i + 1, #rects do
						t.ok(not overlaps(rects[i], rects[j]), "nodes overlap")
					end
				end
				if layout.mode == "wide" then
					t.ok(layout.detail.w >= 200, "detail pane wide enough")
				end
			end)
		end
	end)
end
