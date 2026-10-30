--!strict
--[[
	PuzzleRules — the Puzzle Sage's puzzles (creator request 2026-10-30,
	PLAN.md D-128). Pure: the server passes the random numbers in, makes
	the puzzle, and checks the player's moves by replaying them; the client
	only shows the board and sends the moves.

	Kinds and levels (always solvable: made by scrambling a solved board):
	  Slide   sliding tiles: put 1..N in order, the gap last.
	          medium 3x3 (60 scramble moves), hard 4x4 (120)
	  Lights  lights out: pressing a light flips it and its 4 neighbours;
	          turn every light off.
	          medium 4x4 (6 presses), hard 5x5 (10)
	A board is a flat array, row by row (index 1 = top left).
]]

local PuzzleRules = {}

PuzzleRules.KINDS = table.freeze({ "Slide", "Lights" })
PuzzleRules.LEVELS = table.freeze({ "Medium", "Hard" })
PuzzleRules.SIZE = table.freeze({
	Slide = table.freeze({ Medium = 3, Hard = 4 }),
	Lights = table.freeze({ Medium = 4, Hard = 5 }),
})
PuzzleRules.SCRAMBLE = table.freeze({
	Slide = table.freeze({ Medium = 60, Hard = 120 }),
	Lights = table.freeze({ Medium = 6, Hard = 10 }),
})
PuzzleRules.SECONDS = table.freeze({ Medium = 300, Hard = 420 })
PuzzleRules.MAX_MOVES = 1500

export type Puzzle = { kind: string, level: string, size: number, board: { number } }

local function neighbours(size: number, index: number): { number }
	local row, col = (index - 1) // size, (index - 1) % size
	local out = {}
	if row > 0 then
		table.insert(out, index - size)
	end
	if row < size - 1 then
		table.insert(out, index + size)
	end
	if col > 0 then
		table.insert(out, index - 1)
	end
	if col < size - 1 then
		table.insert(out, index + 1)
	end
	return out
end
PuzzleRules.neighbours = neighbours

-- Slide: move the tile at `index` into the gap (0) next to it. False if not next to it.
function PuzzleRules.slide(board: { number }, size: number, index: number): boolean
	if board[index] == nil or board[index] == 0 then
		return false
	end
	for _, n in neighbours(size, index) do
		if board[n] == 0 then
			board[n], board[index] = board[index], 0
			return true
		end
	end
	return false
end

-- Lights: press `index` (it and its neighbours flip).
function PuzzleRules.press(board: { number }, size: number, index: number): boolean
	if board[index] == nil then
		return false
	end
	board[index] = 1 - board[index]
	for _, n in neighbours(size, index) do
		board[n] = 1 - board[n]
	end
	return true
end

function PuzzleRules.solved(puzzle: Puzzle, board: { number }): boolean
	local cells = puzzle.size * puzzle.size
	for i = 1, cells do
		if puzzle.kind == "Slide" then
			local want = if i == cells then 0 else i
			if board[i] ~= want then
				return false
			end
		elseif board[i] ~= 0 then
			return false
		end
	end
	return true
end

--[[
	Makes a puzzle. `pick(n)` returns a whole number 1..n (the server's
	random). The board is never already solved.
]]
function PuzzleRules.make(kind: string, level: string, pick: (number) -> number): Puzzle
	local size = PuzzleRules.SIZE[kind][level]
	local cells = size * size
	local board = {}
	for i = 1, cells do
		board[i] = if kind == "Slide" then (if i == cells then 0 else i) else 0
	end
	local puzzle: Puzzle = { kind = kind, level = level, size = size, board = board }
	repeat
		if kind == "Slide" then
			local gap = table.find(board, 0) :: number
			local last = -1
			for _ = 1, PuzzleRules.SCRAMBLE.Slide[level] do
				local options = {}
				for _, n in neighbours(size, gap) do
					if n ~= last then
						table.insert(options, n)
					end
				end
				local tile = options[pick(#options)]
				PuzzleRules.slide(board, size, tile)
				last, gap = gap, tile
			end
		else
			-- Distinct cells, so presses never cancel out.
			local used = {}
			local presses = 0
			while presses < PuzzleRules.SCRAMBLE.Lights[level] do
				local cell = pick(cells)
				if not used[cell] then
					used[cell] = true
					presses += 1
					PuzzleRules.press(board, size, cell)
				end
			end
		end
	until not PuzzleRules.solved(puzzle, board)
	return puzzle
end

--[[
	Replays the player's `moves` (cell indexes) on a copy of the puzzle and
	says whether it ends solved. Any illegal move fails the check.
]]
function PuzzleRules.check(puzzle: Puzzle, moves: { number }): boolean
	if #moves > PuzzleRules.MAX_MOVES then
		return false
	end
	local board = table.clone(puzzle.board)
	for _, index in moves do
		if type(index) ~= "number" or index % 1 ~= 0 then
			return false
		end
		local ok = if puzzle.kind == "Slide"
			then PuzzleRules.slide(board, puzzle.size, index)
			else PuzzleRules.press(board, puzzle.size, index)
		if not ok then
			return false
		end
	end
	return PuzzleRules.solved(puzzle, board)
end

return table.freeze(PuzzleRules)
