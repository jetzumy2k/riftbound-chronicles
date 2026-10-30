--!strict
--[[
	ZoneLevels — the war zones' creature levels under the level 60 cap
	(creator request 2026-10-31, PLAN.md D-133). Pure.

	With the cap at 30 nothing changes: camps 25-30, bosses 30-50.
	With the level 60 switch on, the war zones follow the new top end:
	  - field creatures (camps, invasions, boss summons) move up by SHIFT
	    (30): a level 25 camp spawns at 55, a level 30 one at 60;
	  - war-zone bosses fight at the cap (60); a boss that was harder at
	    30 (level 50) stays harder: its health keeps its old fraction of a
	    duo's damage (BossBalance.fieldDuoFraction of its own level).
	Shifted creatures grow like players past 30 (gentle, D-130), as the
	level 31-60 dungeon does, so a level 60 player meets fair numbers.
	The switch applies when a creature (re)spawns.
]]

local BossBalance = require(script.Parent.BossBalance)
local LevelCap = require(script.Parent.LevelCap)
local EnemyDefinitions = require(script.Parent.Parent.Definitions.EnemyDefinitions)

local ZoneLevels = {}

ZoneLevels.SHIFT = LevelCap.MAX - LevelCap.BASE

export type Spawn = {
	level: number,
	gentle: boolean,
	-- Multipliers on the level's base health / attack.
	hpScale: number,
	attackScale: number,
}

-- A war-zone field level (camp, invasion, summon) for the cap switch.
function ZoneLevels.level(level: number, level60: boolean): number
	if not level60 then
		return level
	end
	return math.min(level + ZoneLevels.SHIFT, LevelCap.MAX)
end

--[[
	How a war-zone creature spawns with the level 60 switch on: nil when
	nothing changes (switch off, or a creature already grown gently).
	`level` is the level it would have had at cap 30.
]]
function ZoneLevels.spawnFor(enemy: EnemyDefinitions.Enemy, level: number, level60: boolean): Spawn?
	if not level60 or enemy.gentle then
		return nil
	end
	local tier = enemy.tier
	if tier == nil then
		return {
			level = ZoneLevels.level(level, true),
			gentle = true,
			hpScale = enemy.hpScale,
			attackScale = enemy.attackScale,
		}
	end
	local at = LevelCap.MAX
	local fraction = BossBalance.fieldDuoFraction(enemy.level)
	return {
		level = at,
		gentle = true,
		hpScale = BossBalance.hpFor(
			at,
			enemy.defenseScale,
			fraction,
			EnemyDefinitions.ENRAGE_SECONDS[tier],
			true
		) / BossBalance.creatureBase(at, true).MaxHP,
		attackScale = BossBalance.attackScaleFor(
			at,
			enemy.attackCoefficient,
			EnemyDefinitions.HIT_SHARE[tier],
			true
		),
	}
end

return table.freeze(ZoneLevels)
