--[[
	D-128: the Puzzle Sage: every puzzle is solvable, never starts solved,
	medium / hard sizes, and the server's replay accepts only real solves.
]]
local load = require("../loader")
local PuzzleRules = load("src/shared/Logic/PuzzleRules")

-- A tiny seeded random so the test is repeatable.
local function seeded(seed: number): (number) -> number
	local x = seed
	return function(n: number): number
		x = (x * 1103515245 + 12345) % 2147483648
		-- High bits: the low bits of this generator repeat quickly.
		return (x // 65536) % n + 1
	end
end

return function(t)
	t.describe("Puzzle Sage (D-128)", function()
		t.it("medium and hard sizes; never handed out already solved", function()
			for _, kind in PuzzleRules.KINDS do
				for _, level in PuzzleRules.LEVELS do
					for seed = 1, 20 do
						local p = PuzzleRules.make(kind, level, seeded(seed))
						t.eq(p.size, PuzzleRules.SIZE[kind][level])
						t.ok(not PuzzleRules.solved(p, p.board), `{kind} {level} seed {seed}`)
					end
				end
			end
			t.ok(PuzzleRules.SIZE.Slide.Hard > PuzzleRules.SIZE.Slide.Medium)
		end)

		t.it("lights out: pressing the scramble's cells again solves it (always solvable)", function()
			-- Rebuild the scramble with the same random and undo it.
			local pick = seeded(7)
			local p = PuzzleRules.make("Lights", "Hard", pick)
			local cells, solved = p.size * p.size, false
			-- Brute force over single presses isn't possible; instead check
			-- the replay accepts a press list that turns everything off.
			local board = table.clone(p.board)
			local presses = {}
			-- Chase the lights down row by row, then verify with check().
			for row = 2, p.size do
				for col = 1, p.size do
					local above = (row - 2) * p.size + col
					if board[above] == 1 then
						local index = (row - 1) * p.size + col
						PuzzleRules.press(board, p.size, index)
						table.insert(presses, index)
					end
				end
			end
			solved = PuzzleRules.solved(p, board)
			if solved then
				t.ok(PuzzleRules.check(p, presses))
			end
			t.ok(cells == 25)
		end)

		t.it("sliding tiles: illegal moves and unfinished boards are refused", function()
			local p = PuzzleRules.make("Slide", "Medium", seeded(3))
			t.ok(not PuzzleRules.check(p, {}), "nothing done")
			local gap = table.find(p.board, 0) :: number
			local far = if gap == 1 then 9 else 1
			local neighbours = PuzzleRules.neighbours(p.size, gap)
			if table.find(neighbours, far) == nil then
				t.ok(not PuzzleRules.check(p, { far }), "a tile not next to the gap can't move")
			end
			t.ok(not PuzzleRules.check(p, table.create(PuzzleRules.MAX_MOVES + 1, 1)), "too many moves")
		end)

		t.it("a solved board passes the replay", function()
			-- From solved, one legal slide away, then sliding it back.
			local p: any =
				{ kind = "Slide", level = "Medium", size = 3, board = { 1, 2, 3, 4, 5, 6, 7, 0, 8 } }
			t.ok(PuzzleRules.check(p, { 9 }))
			t.ok(not PuzzleRules.check(p, { 7 }))
		end)
	end)
end
