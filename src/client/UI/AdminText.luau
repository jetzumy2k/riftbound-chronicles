--!strict
--[[
	AdminText — plain-language names and one-line explanations for the
	admin panel's Settings tab (creator review 2026-10-24: raw config paths
	such as "StoneTables.WarZoneMob.Stones.PerfectStone" were hard to read).

	The server sends dotted config paths (AdminRules.flatten); this module
	turns them into a section title, a group card title and a row name with
	help. A path with no entry here still shows, with its key split into
	words, so a new config value never disappears from the panel.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MallDefinitions = require(ReplicatedStorage.Shared.Definitions.MallDefinitions)

local AdminText = {}

export type Section = { title: string, help: string }
export type Leaf = { name: string, help: string?, unit: string? }

AdminText.SECTIONS = {
	Flags = { title = "🚦 Switches", help = "Turn whole features on or off." },
	Loot = {
		title = "🎁 Drop rates",
		help = "How often creatures drop gear or stones, and which rarity. The rarity numbers in each table are weights and must add up to 100.",
	},
	Enhancement = {
		title = "💎 Enhancement",
		help = "Chance (%) that an Enhancement Stone succeeds for each upgrade step. A Perfect Stone always succeeds. Players see these rates.",
	},
	PvP = {
		title = "🏆 War zones (PvP)",
		help = "Portal access, victory rules, PvP Marks and war-zone respawns.",
	},
	Quests = { title = "📜 Quests", help = "The story quest system." },
	Dungeon = {
		title = "🏰 Dungeons",
		help = "Dungeon creatures and bosses: respawn timers and shared EXP.",
	},
	Party = { title = "👥 Parties", help = "Party and union sizes." },
	Mobs = { title = "🐺 Creatures", help = "Creature AI and the Training Grounds." },
	Skills = { title = "🌟 Skills", help = "Cooldowns, crowd control and area skills." },
	Combat = { title = "💥 Combat", help = "Damage formula, regeneration, protection timers and Focus." },
	Appearance = { title = "👤 Appearance", help = "How player characters look." },
	Mall = { title = "🛒 Item Mall prices", help = "What each Item Mall entry costs in Mall Points." },
	Shop = {
		title = "🛍️ Merchant",
		help = "Gold prices of the capital Merchant: potions, gear it sells (Standard / Uncommon / Rare) and what it pays for gear.",
	},
	Exchange = {
		title = "💱 Exchanger",
		help = "Gold and Mall Points ratios and daily limits (0 = no limit), per account.",
	},
} :: { [string]: Section }

-- Card titles for grouped values (the path between the section and the leaf).
AdminText.GROUPS = {
	["Loot.Tables.DungeonMob"] = "Dungeon creature: gear",
	["Loot.Tables.DungeonElite"] = "Dungeon elite ⭐: gear",
	["Loot.Tables.DungeonMiniBoss"] = "Dungeon mini-boss: gear",
	["Loot.Tables.DungeonFloorBoss"] = "Dungeon floor boss: gear",
	["Loot.Tables.DungeonBoss"] = "Dungeon final boss: gear",
	["Loot.Tables.WarZoneBoss"] = "War-zone boss (PvP): gear",
	["Loot.StoneTables.WarZoneMob"] = "War-zone creature (PvP): stones",
	["Enhancement.RatesPct"] = "Success chance per step",
} :: { [string]: string }

-- Row names by full path, or by the last key for repeated keys.
local LEAVES: { [string]: Leaf } = {
	DropChancePct = {
		name = "Drop chance",
		help = "% chance that a defeat drops anything at all.",
		unit = "%",
	},
	PerfectStone = { name = "Perfect Stone", help = "Weight (out of 100) when a stone drops." },
	EnhancementStone = { name = "Enhancement Stone", help = "Weight (out of 100) when a stone drops." },

	["Flags.Maintenance"] = {
		name = "Maintenance mode",
		help = "ON kicks every player with a maintenance message. Owners and Admins stay so they can turn it off.",
	},

	["Flags.AutoAttack"] = {
		name = "Auto-attack switch",
		help = "ON lets players turn on hands-free Auto-attack (finds and fights nearby creatures). OFF hides the switch and stops it for everyone.",
	},

	["PvP.MinLevel"] = { name = "Entry level", help = "Lowest level allowed through the war-zone portals." },
	["PvP.StudioMinLevel"] = { name = "Studio: entry level", help = "Studio tests only." },
	["PvP.LevelGap"] = {
		name = "Level gap",
		help = "Damage is evened out against players more than this many levels lower.",
	},
	["PvP.PortalReach"] = {
		name = "Portal reach",
		help = "How close a player must stand to use a portal.",
		unit = "studs",
	},
	["PvP.RepeatVictimMinutes"] = {
		name = "Repeat-victim wait",
		help = "Defeating the same player again within this time gives no victory.",
		unit = "min",
	},
	["PvP.DailyCreditCap"] = {
		name = "Daily victory cap",
		help = "Most victories one player can earn per day.",
	},
	["PvP.FreshSpawnGraceSeconds"] = {
		name = "Spawn-camping guard",
		help = "No victory for defeating a player whose spawn protection ended less than this long ago.",
		unit = "s",
	},
	["PvP.MarksPerVictory"] = { name = "Marks per victory", help = "PvP Marks for each counted victory." },
	["PvP.MarksPerBoss"] = {
		name = "Marks per boss",
		help = "PvP Marks for helping defeat a war-zone boss (once per spawn).",
	},
	["PvP.CampRespawnSeconds"] = {
		name = "Creature camp respawn",
		help = "War-zone field creatures return after this.",
		unit = "s",
	},
	["PvP.BossRespawnMinutes"] = {
		name = "Boss respawn",
		help = "A fallen war-zone boss returns after this.",
		unit = "min",
	},
	["PvP.Guards"] = {
		name = "Camp guardians",
		help = "ON: guardians around each war-zone camp strike players of the other realm who come close.",
	},
	["PvP.GuardRadius"] = {
		name = "Guardian reach",
		help = "Distance from a camp's centre the guardians defend (the camp ring is 40).",
		unit = "studs",
	},
	["PvP.GuardHitPct"] = {
		name = "Guardian hit",
		help = "Each guardian strike takes this % of the intruder's max HP.",
		unit = "%",
	},
	["PvP.GuardHitSeconds"] = {
		name = "Guardian strike rate",
		help = "Seconds between guardian strikes on an intruder.",
		unit = "s",
	},
	["PvP.StudioBossRespawnSeconds"] = {
		name = "Studio: boss respawn",
		help = "Studio tests only.",
		unit = "s",
	},

	["Quests.Enabled"] = { name = "Quests", help = "Turns the story quest system on or off." },
	["Quests.GatesInStudio"] = {
		name = "Studio: quest locks",
		help = "Studio tests only. ON makes quest unlocks (dungeon, enhancement, war zones) apply in Studio too.",
	},
	["Quests.PollHz"] = {
		name = "Location checks",
		help = 'Times per second "go to" quest steps are checked.',
	},

	["Dungeon.Enabled"] = { name = "Dungeons", help = "Turns the dungeons on or off." },
	["Dungeon.MobRespawnSeconds"] = { name = "Creature respawn", unit = "s" },
	["Dungeon.MiniBossRespawnMinutes"] = { name = "Mini-boss respawn", unit = "min" },
	["Dungeon.FloorBossRespawnMinutes"] = { name = "Floor boss respawn", unit = "min" },
	["Dungeon.BossRespawnHours"] = { name = "Final boss respawn", unit = "h" },
	["Dungeon.StudioMiniBossRespawnSeconds"] = {
		name = "Studio: mini-boss respawn",
		help = "Studio tests only.",
		unit = "s",
	},
	["Dungeon.StudioFloorBossRespawnSeconds"] = {
		name = "Studio: floor boss respawn",
		help = "Studio tests only.",
		unit = "s",
	},
	["Dungeon.StudioBossRespawnSeconds"] = {
		name = "Studio: final boss respawn",
		help = "Studio tests only.",
		unit = "s",
	},
	["Dungeon.XpShareRadius"] = {
		name = "EXP share distance",
		help = "Party members this close share kill EXP.",
		unit = "studs",
	},
	["Dungeon.WipeResetSeconds"] = {
		name = "Boss reset after a wipe",
		help = "A boss in a fight resets when no player is alive in its room for this long.",
		unit = "s",
	},

	["Party.MaxMembers"] = { name = "Party size", help = "Most players in one party." },
	["Party.InviteSeconds"] = {
		name = "Invite expiry",
		help = "A party invite expires after this.",
		unit = "s",
	},
	["Party.UnionMaxParties"] = {
		name = "Parties per union",
		help = "Most parties a leader can join into a union.",
	},

	["Mobs.TickHz"] = {
		name = "AI updates",
		help = "Creature AI updates per second (higher costs more server time).",
	},
	["Mobs.SleepRadius"] = {
		name = "Wake distance",
		help = "Creatures sleep when no player is this close.",
		unit = "studs",
	},
	["Mobs.TrainingSprites"] = { name = "Training sprites", help = "Training Grounds sprites per capital." },
	["Mobs.TrainingRespawnSeconds"] = { name = "Training sprite respawn", unit = "s" },

	["Skills.GlobalCooldownSeconds"] = {
		name = "Global cooldown",
		help = "Wait between any two skill casts.",
		unit = "s",
	},
	["Skills.CooldownSlackSeconds"] = {
		name = "Cooldown slack",
		help = "Casts this early (network lag) still count as ready.",
		unit = "s",
	},
	["Skills.PvPControlScale"] = {
		name = "PvP control length",
		help = "Stuns and slows last this fraction as long player vs player (0.5 = half).",
	},
	["Skills.ControlImmunitySeconds"] = {
		name = "Control immunity",
		help = "After a stun or freeze ends, the target can't get another for this long.",
		unit = "s",
	},
	["Skills.MaxAreaTargets"] = { name = "Area targets", help = "Most targets an area skill hits per wave." },
	["Skills.ResetNeedsSafeZone"] = {
		name = "Skill reset only in safe zone",
		help = "ON: the free skill tree reset works only in a safe zone, out of combat.",
	},
	["Skills.FreeTreeReset"] = {
		name = "Free skill tree reset",
		help = "OFF: the skill tree's Reset button needs a Scroll of Relearning.",
	},
	["Skills.FreeAttributeReset"] = {
		name = "Free attribute reset",
		help = "OFF: the attributes' Reset button needs a Scroll of Rebirth (no free daily reset).",
	},
	["Skills.StudioUnlockAll"] = { name = "Studio: unlock all skills", help = "Studio tests only." },
	["Skills.StudioBonusPoints"] = { name = "Studio: bonus skill points", help = "Studio tests only." },

	["Combat.PowerScalePerLevel"] = {
		name = "Power per level",
		help = "Damage and healing are multiplied by this for each level.",
	},
	["Combat.DefenseKBase"] = {
		name = "Defense curve: base",
		help = "Damage = raw x K / (K + Defense), where K = base + per-level x attacker level.",
	},
	["Combat.DefenseKPerLevel"] = { name = "Defense curve: per level", help = 'See "Defense curve: base".' },
	["Combat.TagSeconds"] = {
		name = "In-combat time",
		help = "A player counts as in combat for this long after the last hostile action.",
		unit = "s",
	},
	["Combat.DefeatDelaySeconds"] = {
		name = "Defeat delay",
		help = "Wait before a defeated player returns to their safe zone.",
		unit = "s",
	},
	["Combat.SpawnProtectSeconds"] = {
		name = "Spawn protection",
		help = "No damage taken after spawning.",
		unit = "s",
	},
	["Combat.ExitBubbleSeconds"] = {
		name = "Safe-zone exit shield",
		help = "Protection right after leaving a safe zone, so nobody is ambushed at the edge.",
		unit = "s",
	},
	["Combat.RegenDelaySeconds"] = {
		name = "Regen delay",
		help = "HP regeneration starts this long after combat.",
		unit = "s",
	},
	["Combat.SafeZoneRegenPctPerSecond"] = {
		name = "Safe-zone regen",
		help = "% of max HP restored per second in a safe zone.",
		unit = "%/s",
	},
	["Combat.RestRegenPctPerSecond"] = {
		name = "Resting regen",
		help = "% of max HP restored per second out of combat with no creature nearby.",
		unit = "%/s",
	},
	["Combat.RestCreatureRadius"] = {
		name = "Resting: creature distance",
		help = "No creature may be this close for resting regen.",
		unit = "studs",
	},
	["Combat.FocusMax"] = { name = "Max Focus", help = "Focus is the resource skills and sprinting spend." },
	["Combat.FocusRegenPerSecond"] = { name = "Focus regen", unit = "/s" },
	["Combat.RangeToleranceStuds"] = {
		name = "Range tolerance",
		help = "Extra distance allowed when the server checks a skill's range.",
		unit = "studs",
	},
	["Combat.MaxPingCompensationSeconds"] = {
		name = "Lag compensation",
		help = "Most network delay forgiven when the server checks a hit.",
		unit = "s",
	},
	["Combat.ResetCooldownSeconds"] = {
		name = "Character reset cooldown",
		help = "Wait between character resets out of combat.",
		unit = "s",
	},
	["Combat.RelevanceRadius"] = {
		name = "Combat effects distance",
		help = "Players this close see another fight's hits and effects.",
		unit = "studs",
	},

	["Appearance.SmoothBody"] = {
		name = "Smooth body",
		help = "Every character uses the game's smooth body (keeps their head, face, hair and skin).",
	},
}

-- "DungeonFloorBoss" -> "Dungeon Floor Boss"
function AdminText.words(key: string): string
	local spaced = string.gsub(key, "(%l)(%u)", "%1 %2")
	return (string.gsub(spaced, "(%a)(%d)", "%1 %2"))
end

function AdminText.section(name: string): Section
	return AdminText.SECTIONS[name] or { title = name, help = "" }
end

--[[
	Splits a path into its card (group key + title) and its row (name, help,
	unit). Loot tables group by table, the enhancement list by step; other
	sections have one card.
]]
function AdminText.describe(path: string): (string, string, Leaf)
	local parts = string.split(path, ".")
	local sectionName = parts[1]
	local last = parts[#parts]
	if sectionName == "Loot" and #parts >= 4 then
		local group = `{parts[1]}.{parts[2]}.{parts[3]}`
		local title = AdminText.GROUPS[group] or AdminText.words(parts[3])
		local leaf = LEAVES[last]
		if parts[4] == "Rarity" then
			leaf = { name = last, help = "Weight (out of 100) when gear drops." }
		end
		return group, title, leaf or { name = AdminText.words(last) }
	end
	if sectionName == "Enhancement" and parts[2] == "RatesPct" then
		local group = "Enhancement.RatesPct"
		return group, AdminText.GROUPS[group], { name = `Upgrade to +{last}`, unit = "%" }
	end
	if sectionName == "Mall" and parts[2] == "Prices" then
		local entry = MallDefinitions.get(last)
		return "Mall.Prices",
			AdminText.section("Mall").title,
			{
				name = if entry then `{entry.icon} {entry.name}` else last,
				help = if entry then entry.short else nil,
				unit = "MP",
			}
	end
	local leaf = LEAVES[path] or { name = AdminText.words(last) }
	return sectionName, AdminText.section(sectionName).title, leaf
end

return AdminText
