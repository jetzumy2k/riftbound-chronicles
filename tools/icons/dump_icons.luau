--[[
	Dumps SkillIcons motifs (and which skills use them) as JSON (stdout) for
	tools/icons/render_icons.py. Run from the repository root:
	    lune run tools/icons/dump_icons > build/icons.json
]]
local serde = require("@lune/serde")
local load = require("../../tests/pure/loader")
local SkillIcons = load("src/shared/Definitions/SkillIcons")
local ok, SkillDefinitions = pcall(load, "src/shared/Definitions/SkillDefinitions")

local skills = {}
if ok then
	for _, skill in SkillDefinitions.All do
		table.insert(skills, { id = skill.id, icon = (skill :: any).icon, element = skill.fx.element, job = skill.job })
	end
end
print(serde.encode("json", { motifs = SkillIcons.Motifs, elements = SkillIcons.Elements, skills = skills }))
