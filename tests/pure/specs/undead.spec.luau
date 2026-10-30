--[[
	D-133: the Abyssal Spire's undead (sculpted shapes, attack sets, the
	Death Lord) and the war zones' levels under the level 60 cap.
]]
local load = require("../loader")
local EnemyDefinitions = load("src/shared/Definitions/EnemyDefinitions")
local DungeonDefinitions = load("src/shared/Definitions/DungeonDefinitions")
local MobAttacks = load("src/shared/Logic/MobAttacks")
local ZoneLevels = load("src/shared/Logic/ZoneLevels")
local BossBalance = load("src/shared/Logic/BossBalance")
local StatFormulas = load("src/shared/Logic/StatFormulas")

local UNDEAD_SHAPES =
	{ Skeleton = true, Zombie = true, DeathKnight = true, Dullahan = true, DeathLord = true }

return function(t)
	t.describe("The Spire's undead (D-133)", function()
		t.it("every Spire creature is undead and gentle; the Death Lord guards floor 3", function()
			local spire = DungeonDefinitions.get("AbyssalSpire") :: any
			t.ok(spire ~= nil)
			local seen: { [string]: boolean } = {}
			local count = 0
			for index = 1, 3 do
				local floor = spire.floors[index]
				for _, room in floor.rooms do
					for _, camp in room.camps or {} do
						local enemy = EnemyDefinitions.get(camp.enemy)
						t.ok(enemy ~= nil, camp.enemy)
						if enemy and enemy.tier == nil and not seen[enemy.id] then
							seen[enemy.id] = true
							count += 1
							t.ok(enemy.undead == true and enemy.gentle == true, enemy.id)
							t.eq(enemy.body, "Guardian", enemy.id)
						end
					end
				end
			end
			t.eq(count, 9)
			local lair = spire.floors[3].rooms[spire.floors[3].bossRoom]
			t.eq(lair.boss, "DeathLord")
			local lord = EnemyDefinitions.get("DeathLord")
			t.ok(lord ~= nil and lord.undead == true and lord.tier == "Floor")
			t.eq(EnemyDefinitions.get("Jormungandr"), nil)
		end)

		t.it("armed undead fight with weapons, ghouls with claws", function()
			t.eq(MobAttacks.setFor("Guardian", "Skeleton"), "Undead")
			t.eq(MobAttacks.setFor("Guardian", "DeathKnight"), "Undead")
			t.eq(MobAttacks.setFor("Guardian", "Dullahan"), "Undead")
			t.eq(MobAttacks.setFor("Guardian", "Zombie"), "Ghoul")
		end)
	end)

	t.describe("War zones under the level 60 cap (D-133)", function()
		t.it("nothing changes with the cap at 30", function()
			local stalker = EnemyDefinitions.get("DuneStalker") :: any
			t.eq(ZoneLevels.spawnFor(stalker, 27, false), nil)
			t.eq(ZoneLevels.level(27, false), 27)
		end)

		t.it("camps move up 30 levels (55-60) and grow gently", function()
			local stalker = EnemyDefinitions.get("DuneStalker") :: any
			local s = ZoneLevels.spawnFor(stalker, 25, true) :: any
			t.eq(s.level, 55)
			t.ok(s.gentle)
			t.eq(s.hpScale, stalker.hpScale)
			t.eq((ZoneLevels.spawnFor(stalker, 30, true) :: any).level, 60)
			-- A level 55 field creature is as tough against a level 55 player
			-- as a level 25 one was against a level 25 player.
			local then25 = StatFormulas.forLevel(25).MaxHP * stalker.hpScale / StatFormulas.forLevel(25).MaxHP
			local now55 = StatFormulas.forLevel(55).MaxHP * s.hpScale / StatFormulas.forLevel(55).MaxHP
			t.ok(math.abs(then25 - now55) < 1e-9)
		end)

		t.it("bosses fight at 60; harder bosses stay harder", function()
			local easy, hard = EnemyDefinitions.get("Ammit") :: any, EnemyDefinitions.get("Leviathan") :: any
			local a = ZoneLevels.spawnFor(easy, easy.level, true) :: any
			local b = ZoneLevels.spawnFor(hard, hard.level, true) :: any
			t.eq(a.level, 60)
			t.eq(b.level, 60)
			if easy.level < hard.level then
				t.ok(b.hpScale > a.hpScale, "the higher boss keeps more health")
			end
			-- A duo still beats it inside the enrage timer.
			local enrage = EnemyDefinitions.ENRAGE_SECONDS[hard.tier]
			local hp = BossBalance.creatureBase(60, true).MaxHP * b.hpScale
			local defense = BossBalance.creatureBase(60, true).Defense * hard.defenseScale
			local dps = BossBalance.playerDps(BossBalance.referenceLevel(60, true), defense)
			t.ok(hp / (2 * dps) < enrage, "duo time-to-kill under the enrage timer")
		end)

		t.it("EXP follows the curve past 30 for shifted creatures; own levels unchanged", function()
			local stalker = EnemyDefinitions.get("DuneStalker") :: any
			local at30 = EnemyDefinitions.xpAt(stalker, 30)
			t.ok(EnemyDefinitions.xpAt(stalker, 55) > at30)
			t.ok(EnemyDefinitions.xpAt(stalker, 60) > EnemyDefinitions.xpAt(stalker, 55))
			local boss = EnemyDefinitions.get("Leviathan") :: any
			t.eq(EnemyDefinitions.xpAt(boss), EnemyDefinitions.xpAt(boss, boss.level))
		end)
	end)
end
