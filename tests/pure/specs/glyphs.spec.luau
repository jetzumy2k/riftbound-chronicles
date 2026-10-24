--[[
	Symbols Roblox's fonts can't draw (D-75): dingbats and "text style"
	symbols such as U+2726 (four-pointed star) or U+2623 (biohazard) show as
	empty boxes in game. Code may use ASCII, Latin-1, general punctuation,
	arrows, maths, geometric shapes (U+25A0..25FF) and colour emoji, but in
	the risky blocks below only the emoji that always draw in colour.
]]

local fs = require("@lune/fs")

-- Misc Technical, Misc Symbols, Dingbats, Misc Symbols and Arrows.
-- Plus Symbols and Pictographs Extended-A: emoji from 2019 on (the wand
-- U+1FA84 showed as a box, D-72); older emoji render.
local RISKY = { { 0x2300, 0x23FF }, { 0x2600, 0x27BF }, { 0x2B00, 0x2BFF }, { 0x1FA70, 0x1FAFF } }
-- Emoji-presentation characters in those blocks that we use (always colour).
local ALLOWED = {
	[0x2705] = true, -- white heavy check mark
	[0x274C] = true, -- cross mark
	[0x2728] = true, -- sparkles
	[0x2B50] = true, -- star
	[0x2757] = true, -- exclamation mark
	[0x26A1] = true, -- high voltage
	[0x2693] = true, -- anchor
	[0x2795] = true, -- heavy plus
	[0x231B] = true, -- hourglass
	[0x23F3] = true, -- hourglass flowing
}
-- Explains the boxes in a comment; never shown in game.
local SKIP = { ["src/shared/Definitions/SkillIcons.luau"] = true }

local function listFiles(dir: string, out: { string })
	for _, name in fs.readDir(dir) do
		local path = `{dir}/{name}`
		if fs.isDir(path) then
			listFiles(path, out)
		elseif string.match(name, "%.luau$") then
			table.insert(out, path)
		end
	end
end

local function risky(code: number): boolean
	if ALLOWED[code] then
		return false
	end
	for _, range in RISKY do
		if code >= range[1] and code <= range[2] then
			return true
		end
	end
	return false
end

return function(t)
	t.describe("glyphs", function()
		t.it("code never uses symbols that render as empty boxes", function()
			local files = {}
			listFiles("src", files)
			for _, path in files do
				if SKIP[path] then
					continue
				end
				local source = fs.readFile(path)
				local lineNumber = 0
				for line in string.gmatch(source .. "\n", "([^\n]*)\n") do
					lineNumber += 1
					for _, code in utf8.codes(line) do
						if risky(code) then
							t.ok(false, `{path}:{lineNumber} uses U+{string.format("%04X", code)}`)
							break
						end
					end
				end
			end
		end)
	end)
end
