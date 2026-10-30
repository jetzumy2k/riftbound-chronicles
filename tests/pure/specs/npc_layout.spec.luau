--[[
	D-132: the town NPCs stand in two signed rows (every NPC in exactly one
	row, on its side of the spawn), never on top of each other or of the
	quest giver.
]]
local load = require("../loader")
local NpcDefinitions = load("src/shared/Definitions/NpcDefinitions")
local QuestDefinitions = load("src/shared/Definitions/QuestDefinitions")

return function(t)
	t.describe("Town NPC layout (D-132)", function()
		t.it("every NPC is in exactly one row, on that row's side", function()
			local seen = {}
			for _, row in NpcDefinitions.ROWS do
				for _, id in row.ids do
					local npc = NpcDefinitions.get(id)
					t.ok(npc ~= nil, id)
					t.ok(seen[id] == nil, `{id} in two rows`)
					seen[id] = true
					t.eq(math.sign(npc.at[1]), math.sign(row.signX), `{id} side`)
				end
			end
			for _, npc in NpcDefinitions.List do
				t.ok(seen[npc.id], `{npc.id} has a row`)
			end
		end)

		t.it("nobody stands within 12 studs of another, the quest giver included", function()
			local spots = {}
			for _, npc in NpcDefinitions.List do
				table.insert(spots, { npc.id, npc.at })
			end
			table.insert(spots, { "QuestGiver", QuestDefinitions.Givers.Angel.at })
			for i = 1, #spots do
				for j = i + 1, #spots do
					local a, b = spots[i][2], spots[j][2]
					local d = math.sqrt((a[1] - b[1]) ^ 2 + (a[3] - b[3]) ^ 2)
					t.ok(d >= 12, `{spots[i][1]} and {spots[j][1]} are {d} studs apart`)
				end
			end
		end)
	end)
end
