--[[
	D-103 stage A: class colours and branch roles for the skill tree screen.
]]
local load = require("../loader")
local ClassThemes = load("src/shared/Definitions/ClassThemes")
local SkillDefinitions = load("src/shared/Definitions/SkillDefinitions")

local JOBS = { "Warrior", "Healer", "Archer", "Mage" }

local function validColour(c): boolean
	if type(c) ~= "table" or #c ~= 3 then
		return false
	end
	for _, v in c do
		if type(v) ~= "number" or v < 0 or v > 255 or v % 1 ~= 0 then
			return false
		end
	end
	return true
end

-- Rough brightness (0-255) of a colour.
local function brightness(c): number
	return 0.299 * c[1] + 0.587 * c[2] + 0.114 * c[3]
end

return function(t)
	t.describe("ClassThemes", function()
		t.it("every class has a full set of valid colours", function()
			for _, job in JOBS do
				local theme = ClassThemes.forJob(job)
				t.ok(theme ~= ClassThemes.DEFAULT, `{job} has its own theme`)
				for _, key in { "primary", "secondary", "accent", "dark", "text" } do
					t.ok(validColour(theme[key]), `{job} {key}`)
				end
			end
			t.eq(ClassThemes.forJob(nil), ClassThemes.DEFAULT)
			t.eq(ClassThemes.forJob("Nope"), ClassThemes.DEFAULT)
		end)

		t.it("titles stay readable on the dark panel tint (CLAUDE.md §28)", function()
			for _, job in JOBS do
				local theme = ClassThemes.forJob(job)
				t.ok(brightness(theme.text) - brightness(theme.dark) >= 120, `{job} title contrast`)
				t.ok(brightness(theme.dark) <= 40, `{job} panel stays dark`)
			end
		end)

		t.it("every branch shows a role, and the Warrior has an attack and a defense build", function()
			for _, job in JOBS do
				for _, branch in SkillDefinitions.Branches[job] do
					local role = ClassThemes.role(branch.id)
					t.ok(role ~= nil and #role > 0 and #role <= 18, `{job} {branch.id} role`)
				end
			end
			t.eq(ClassThemes.role("Blademaster"), "ATTACK BUILD")
			t.eq(ClassThemes.role("Ironclad"), "DEFENSE BUILD")
		end)
	end)
end
