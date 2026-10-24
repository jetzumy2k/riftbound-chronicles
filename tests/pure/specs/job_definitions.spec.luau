local load = require("../loader")
local Enums = load("src/shared/Enums")
local JobDefinitions = load("src/shared/Definitions/JobDefinitions")

local BANNED_WORDS = {
	"god",
	"gods",
	"satan",
	"heaven",
	"hell",
	"demon",
	"pray",
	"prayer",
	"worship",
	"holy",
	"sin",
	"bible",
	"church",
}

local function containsWord(text: string, word: string): boolean
	return string.find(string.lower(text), `%f[%a]{word}%f[%A]`) ~= nil
end

return function(t)
	t.it("defines exactly the enum jobs, in display order", function()
		t.eq(#JobDefinitions.Order, #Enums.Job)
		for _, job in Enums.Job do
			local def = JobDefinitions.get(job)
			t.ok(def ~= nil, job)
			t.eq(def.id, job)
			t.ok(table.find(JobDefinitions.Order, job) ~= nil, job)
		end
		t.eq(JobDefinitions.get("Bard"), nil)
	end)

	t.it("skill categories match CLAUDE.md §6 and are valid enum values", function()
		local expected = {
			Healer = { "Heal", "Shield", "Cleanse", "HolyAttack", "AreaSupport" },
			Warrior = { "Guard", "Shield", "DefenseBuff", "MeleeAttack", "AreaMelee", "Taunt" },
			Archer = { "RangedAttack", "Precision", "Mobility", "Mark", "RangedArea" },
			Mage = { "MagicAttack", "AreaMagic", "Control", "Barrier" },
		}
		for job, categories in expected do
			local def = JobDefinitions.get(job)
			t.eq(table.concat(def.allowedSkillCategories, ","), table.concat(categories, ","), job)
			for _, category in def.allowedSkillCategories do
				t.ok(Enums.has(Enums.SkillCategory, category), `{job}: {category}`)
			end
		end
	end)

	t.it("every skill category belongs to at least one job", function()
		for _, category in Enums.SkillCategory do
			local owners = 0
			for _, job in Enums.Job do
				if JobDefinitions.allowsSkillCategory(job, category) then
					owners += 1
				end
			end
			t.ok(owners >= 1, category)
		end
	end)

	t.it("healers never get archer precision; archers never get melee or healing (§6.1)", function()
		t.ok(not JobDefinitions.allowsSkillCategory("Healer", "Precision"))
		t.ok(not JobDefinitions.allowsSkillCategory("Healer", "Taunt"))
		t.ok(not JobDefinitions.allowsSkillCategory("Archer", "Heal"))
		t.ok(not JobDefinitions.allowsSkillCategory("Archer", "MeleeAttack"))
		t.ok(not JobDefinitions.allowsSkillCategory("Warrior", "RangedAttack"))
		-- Mage magic stays separate from Healer support and Archer precision.
		t.ok(not JobDefinitions.allowsSkillCategory("Mage", "Heal"))
		t.ok(not JobDefinitions.allowsSkillCategory("Mage", "Precision"))
		t.ok(not JobDefinitions.allowsSkillCategory("Healer", "AreaMagic"))
		-- Shield is the only shared category (support shield vs warrior shield).
		t.ok(JobDefinitions.allowsSkillCategory("Healer", "Shield"))
		t.ok(JobDefinitions.allowsSkillCategory("Warrior", "Shield"))
	end)

	t.it("rejects unknown jobs and categories", function()
		t.ok(not JobDefinitions.allowsSkillCategory("Bard", "Heal"))
		t.ok(not JobDefinitions.allowsSkillCategory("Healer", "Fireball"))
		t.ok(not JobDefinitions.allowsSkillCategory("Healer", nil))
	end)

	t.it("weapons come from the gear sheet and are race-aware", function()
		for _, job in Enums.Job do
			local def = JobDefinitions.get(job)
			for _, race in Enums.Race do
				local weapons = def.weaponsByRace[race]
				t.ok(weapons ~= nil and #weapons >= 1, `{job}/{race}`)
				for _, weapon in weapons do
					t.ok(Enums.has(Enums.WeaponType, weapon), `{job}/{race}: {weapon}`)
				end
			end
		end
		-- D-68: the creator's weapon rules, the same in both realms.
		local WeaponRules = load("src/shared/Definitions/WeaponRules")
		for _, family in { "Sword", "Mace", "Axe", "Greatsword", "WarHammer", "BattleAxe" } do
			t.ok(JobDefinitions.allowsWeapon("Warrior", "Angel", family), family)
			t.ok(JobDefinitions.allowsWeapon("Warrior", "Devil", family), family)
		end
		for _, job in { "Healer", "Mage" } do
			for _, family in { "Dagger", "Sword", "Staff" } do
				t.ok(JobDefinitions.allowsWeapon(job, "Angel", family), `{job} {family}`)
			end
		end
		t.ok(JobDefinitions.allowsWeapon("Healer", "Devil", "Orb"), "orb kept")
		t.ok(JobDefinitions.allowsWeapon("Mage", "Devil", "Tome"), "tome kept")
		t.ok(JobDefinitions.allowsWeapon("Archer", "Devil", "Crossbow"))
		t.ok(not JobDefinitions.allowsWeapon("Archer", "Human", "Bow"))
		t.ok(not JobDefinitions.allowsWeapon("Archer", "Angel", "Sword"))
		-- Every family a class can hold has a hand rule.
		for _, job in Enums.Job do
			for _, family in JobDefinitions.get(job).weaponsByRace.Angel do
				t.ok(WeaponRules.get(family) ~= nil, family)
			end
		end
	end)

	t.it("every category has a player-facing name", function()
		for _, category in Enums.SkillCategory do
			t.ok(type(JobDefinitions.CategoryNames[category]) == "string", category)
		end
	end)

	t.it("player-facing text avoids real-world religious terms", function()
		local texts = {}
		for _, job in Enums.Job do
			local def = JobDefinitions.get(job)
			table.insert(texts, def.displayName)
			table.insert(texts, def.description)
			for _, role in def.roleByRace do
				table.insert(texts, role)
			end
		end
		for _, name in JobDefinitions.CategoryNames do
			table.insert(texts, name)
		end
		for _, text in texts do
			for _, word in BANNED_WORDS do
				t.ok(not containsWord(text, word), `'{text}' contains '{word}'`)
			end
		end
	end)

	t.it("job glyphs use symbols Roblox fonts render (no exotic dingbats)", function()
		-- Colour emoji render in every font; text-style dingbats depend on the
		-- font and showed as boxes in the HUD fonts (D-75, glyphs.spec).
		local SAFE = {
			["🗡"] = true,
			["💖"] = true,
			["🏹"] = true,
			["🔮"] = true,
		}
		for _, job in Enums.Job do
			local def = JobDefinitions.get(job)
			t.ok(SAFE[def.glyph] == true, `{job} glyph '{def.glyph}' is not in the safe set`)
		end
	end)

	t.it("definitions are deeply frozen", function()
		local def = JobDefinitions.get("Warrior")
		t.ok(table.isfrozen(def))
		t.ok(table.isfrozen(def.allowedSkillCategories))
		t.ok(table.isfrozen(def.weaponsByRace.Angel))
	end)
end
