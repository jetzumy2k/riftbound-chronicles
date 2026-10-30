--!strict
--[[
	LevelCap — the level 60 extension (creator request 2026-10-30, PLAN.md
	D-129). Pure.

	Levels 0..BASE (30) are exactly as before. The admin switch
	Progression.Level60 (Settings → 🆙 Level cap) raises the cap to MAX
	(60); off, EXP stops at 30 as it always did. Creator decision: levels
	31..60 grow gently, so a level 60 character is about 4x a level 30 one
	instead of 250x:
	  HP +5 %, Attack and Defense +3 % per level past 30 (GENTLE)
	  EXP to the next level +6 % per level past 30 (XP_GROWTH)
	  gear of item level 31..60 grows at 0.3x the old rate (gearLevel)
	The server mirrors the live cap for clients as the ReplicatedStorage
	attribute ATTRIBUTE (display only).
]]

local LevelCap = {}

LevelCap.BASE = 30
LevelCap.MAX = 60
LevelCap.ATTRIBUTE = "RC_LevelCap"
LevelCap.GENTLE = table.freeze({ HP = 1.05, Attack = 1.03, Defense = 1.03 })
LevelCap.XP_GROWTH = 1.06
LevelCap.GEAR_RATE = 0.3

-- The live cap for the switch.
function LevelCap.of(level60: boolean?): number
	return if level60 then LevelCap.MAX else LevelCap.BASE
end

-- The level used in gear growth (exponents): unchanged to 30, slower after.
function LevelCap.gearLevel(itemLevel: number): number
	if itemLevel <= LevelCap.BASE then
		return itemLevel
	end
	return LevelCap.BASE + (itemLevel - LevelCap.BASE) * LevelCap.GEAR_RATE
end

return table.freeze(LevelCap)
