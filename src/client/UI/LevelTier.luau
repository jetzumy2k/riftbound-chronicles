--!strict
--[[
	LevelTier — how a creature's level reads to this player (PLAN.md D-63):
	a colour, a mark and a word per Logic/LevelGap tier, so the danger and
	the EXP never rest on colour alone (CLAUDE.md §28).

	  Deadly   grey    ☠  far too strong, no EXP
	  Higher   red     ▲▲
	  High     orange  ▲
	  Medium   yellow  △
	  Normal   green
	  Minimal  blue    ▽  little EXP
	  Trivial  white   ·  too weak, no EXP
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LevelGap = require(ReplicatedStorage.Shared.Logic.LevelGap)

export type Style = { tier: LevelGap.Tier, color: Color3, mark: string, word: string }

local STYLES: { [string]: { color: Color3, mark: string, word: string } } = {
	Deadly = { color = Color3.fromRGB(150, 150, 156), mark = "☠", word = "Deadly · no EXP" },
	Higher = { color = Color3.fromRGB(255, 82, 70), mark = "▲▲", word = "Very hard" },
	High = { color = Color3.fromRGB(255, 152, 60), mark = "▲", word = "Hard" },
	Medium = { color = Color3.fromRGB(255, 226, 90), mark = "△", word = "Tough" },
	Normal = { color = Color3.fromRGB(124, 232, 124), mark = "", word = "" },
	Minimal = { color = Color3.fromRGB(140, 200, 255), mark = "▽", word = "Easy · little EXP" },
	Trivial = { color = Color3.fromRGB(245, 245, 245), mark = "·", word = "Too weak · no EXP" },
}

local LevelTier = {}

function LevelTier.playerLevel(): number
	local player = Players.LocalPlayer
	local level = player and player:GetAttribute("Level")
	return if type(level) == "number" then level else 0
end

function LevelTier.styleFor(creatureLevel: number): Style
	local tier = LevelGap.tierFor(creatureLevel, LevelTier.playerLevel())
	local style = STYLES[tier.id]
	return { tier = tier, color = style.color, mark = style.mark, word = style.word }
end

return LevelTier
