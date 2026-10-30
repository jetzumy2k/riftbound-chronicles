--[[
	Creature attack sets (PLAN.md D-61): which moves each kind has, how one
	is picked, and the front-arc test on hits (Logic/MobAttacks).
]]

local load = require("../loader")
local MobAttacks = load("src/shared/Logic/MobAttacks")

return function(t)
	t.describe("MobAttacks", function()
		t.it("every kind of creature has its own set", function()
			t.eq(MobAttacks.setFor("Wolf", "Lion"), "Predator")
			t.eq(MobAttacks.setFor("Wolf", "Dragon"), "Beast")
			t.eq(MobAttacks.setFor("Guardian", "Harpy"), "Brute")
			t.eq(MobAttacks.setFor("Beetle", "Spider"), "Crawler")
			t.eq(MobAttacks.setFor("Serpent", "Gorgon"), "Serpent")
			t.eq(MobAttacks.setFor("Golem", nil), "Brute", "no mesh: by body")
			t.eq(MobAttacks.setFor("Sprite", nil), "Sprite")
			-- D-133: the undead.
			t.eq(MobAttacks.setFor("Guardian", "Skeleton"), "Undead")
			t.eq(MobAttacks.setFor("Guardian", "DeathLord"), "Undead")
			t.eq(MobAttacks.setFor("Guardian", "Zombie"), "Ghoul")
			for name, moves in MobAttacks.Sets do
				t.ok(#moves >= 1, name)
				for _, move in moves do
					t.ok(move.windup > 0 and move.damage > 0 and move.reach > 0, `{name}.{move.id}`)
					t.ok(move.arc > 0 and move.arc <= 360, `{name}.{move.id} arc`)
				end
			end
		end)

		t.it("only picks moves that reach, weighted by how common they are", function()
			-- Close in: anything goes; the common bite most often.
			local seen: { [string]: number } = {}
			for i = 0, 99 do
				local move = MobAttacks.choose("Predator", 4, 6, i / 100, nil)
				seen[move.id] = (seen[move.id] or 0) + 1
			end
			t.ok(seen.Bite > seen.Claw and seen.Claw > seen.Pounce, "bite > claw > pounce")
			-- At the edge of its reach only the long pounce lands.
			for i = 0, 9 do
				t.eq(MobAttacks.choose("Predator", 9, 6, i / 10, nil).id, "Pounce")
			end
			-- Nothing reaches: the basic move.
			t.eq(MobAttacks.choose("Brute", 40, 6, 0.5, nil).id, "Smash")
		end)

		t.it("is less likely to repeat a special move straight away", function()
			local function count(last: string?): number
				local n = 0
				for i = 0, 199 do
					if MobAttacks.choose("Brute", 3, 6, i / 200, last).id == "Stomp" then
						n += 1
					end
				end
				return n
			end
			t.ok(count("Stomp") < count(nil), "fewer stomps after a stomp")
		end)

		t.it("hits only what is in front, within the move's arc", function()
			local forward = { 0, -1 }
			t.ok(MobAttacks.inArc(forward, { 0, -5 }, 80), "dead ahead")
			t.ok(MobAttacks.inArc(forward, { 2, -5 }, 80), "a little to the side")
			t.ok(not MobAttacks.inArc(forward, { 5, 0 }, 80), "beside it")
			t.ok(not MobAttacks.inArc(forward, { 0, 5 }, 170), "behind it")
			t.ok(MobAttacks.inArc(forward, { 0, 5 }, 360), "a sweep all round")
			t.ok(MobAttacks.inArc(forward, { 0.3, 0.3 }, 60), "right on top of it")
		end)
	end)
end
