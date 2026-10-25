local load = require("../loader")
local CreatureLanguage = load("src/shared/Definitions/CreatureLanguage")
local EnemyDefinitions = load("src/shared/Definitions/EnemyDefinitions")

return function(t)
	t.describe("CreatureLanguage", function()
		t.it("the seven elements are told apart by hue", function()
			local names = {}
			for name in CreatureLanguage.ELEMENTS do
				table.insert(names, name)
			end
			t.eq(#names, 7)
			for i = 1, #names do
				for j = i + 1, #names do
					local a = CreatureLanguage.hue(CreatureLanguage.ELEMENTS[names[i]].glow)
					local b = CreatureLanguage.hue(CreatureLanguage.ELEMENTS[names[j]].glow)
					t.ok(
						CreatureLanguage.hueGap(a, b) >= 20,
						`{names[i]} and {names[j]} {math.floor(a)} / {math.floor(b)}`
					)
				end
			end
		end)

		t.it("ranks: elites get a star, bosses a crown and a sigil", function()
			t.eq(CreatureLanguage.rankOf({ elite = false }), "Normal")
			t.eq(CreatureLanguage.rankOf({ elite = true }), "Elite")
			t.eq(CreatureLanguage.rankOf({ elite = true, tier = "Mini" }), "Mini")
			t.eq(CreatureLanguage.displayName("Rift Wolf", "Normal"), "Rift Wolf")
			t.eq(CreatureLanguage.displayName("Magma Golem", "Elite"), "Magma Golem ⭐")
			t.eq(CreatureLanguage.displayName("Typhon", "Boss"), "Typhon 👑")
			t.ok(
				CreatureLanguage.sigil("Normal") == nil and CreatureLanguage.sigil("Elite") == nil,
				"no sigil"
			)
			local mini = CreatureLanguage.sigil("Mini") :: any
			local floor = CreatureLanguage.sigil("Floor") :: any
			local boss = CreatureLanguage.sigil("Boss") :: any
			t.ok(mini.rings == 1 and mini.crown == 0, "a mini boss: one ring, no crown")
			t.ok(
				floor.rings == 2 and floor.crown > 0 and boss.crown >= floor.crown,
				"big bosses: two rings, a crown"
			)
		end)

		t.it("every boss has an element its glow shows", function()
			local count = 0
			for id, enemy in EnemyDefinitions.ById do
				if enemy.tier then
					count += 1
					local element = enemy.element
					t.ok(element ~= nil, `{id} has no element`)
					if element then
						local gap = CreatureLanguage.hueGap(
							CreatureLanguage.hue(enemy.glow),
							CreatureLanguage.hue(CreatureLanguage.ELEMENTS[element].glow)
						)
						t.ok(
							gap <= CreatureLanguage.HUE_TOLERANCE,
							`{id}: glow {math.floor(gap)} degrees off {element}`
						)
					end
				else
					t.ok(enemy.element == nil, `{id} is not a boss`)
				end
			end
			t.eq(count, 45)
		end)

		t.it("no two bosses share body, anatomy, element and weight", function()
			local seen = {}
			for id, enemy in EnemyDefinitions.ById do
				if enemy.tier then
					local traits = table.clone(enemy.traits or {})
					table.sort(traits)
					local key = `{enemy.body}|{table.concat(traits, "+")}|{enemy.element}|{enemy.scale}`
					t.ok(seen[key] == nil, `{id} looks like {seen[key]} ({key})`)
					seen[key] = id
				end
			end
		end)

		t.it("mini bosses come in three weights and use every element", function()
			local weights, elements = {}, {}
			for _, spec in EnemyDefinitions.MINI_BOSSES do
				local enemy = EnemyDefinitions.get(spec[1]) :: any
				weights[enemy.scale] = true
				elements[enemy.element] = true
				local palette = CreatureLanguage.ELEMENTS[enemy.element]
				t.ok(
					enemy.glow[1] == palette.glow[1] and enemy.color[2] == palette.body[2],
					`{spec[1]} palette`
				)
			end
			for _, scale in EnemyDefinitions.MINI_SCALE do
				t.ok(weights[scale], `weight {scale} used`)
			end
			for name in CreatureLanguage.ELEMENTS do
				t.ok(elements[name], `{name} used`)
			end
		end)
	end)
end
