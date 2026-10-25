--!strict
--[[
	EventChallenges — the hunts and challenges (Phase 18 stage 3, PLAN.md
	D-92). Pure: where chests go, their clues, what everything pays and how
	the contests are ranked. EventChallengeService runs them.

	  TreasureHunt       5 treasure chests in the war zones, each with a clue
	                     (zone, whose camp's half, how far from the oasis,
	                     the nearest boss's post); all 5 earn the title
	                     Treasure Seeker
	  HiddenChestHunt    12 small chests hidden across both war zones, no
	                     clues; 8 earn the title Keen Eye
	  RaceChallenge      credited PvP victories per realm; the realm with
	                     more wins
	  CrossRaceTournament credited PvP victories per player; the top 3 win
	  AngelDefense /     waves of Rift creatures attack that realm's training
	  DevilDefense       yard; every defender who defeats one is paid
	  CosmeticParade     5 minutes in a capital during the parade
	  ArenaRush          PvP Marks x2 (Marks category, PvPService)

	Every reward is claimed once per event run (claim ids "E:<event>:<start
	time>:<what>", RewardClaims). Scores live on the server running the
	event: a player is paid when it ends if they are still online there.
]]

local WorldLayout = require(script.Parent.Parent.Definitions.WorldLayout)

local EventChallenges = {}

export type Chest = { zone: string, x: number, z: number, treasure: boolean, clue: string? }
export type Reward = { gold: number, stones: number, title: string? }

-- Chest spots relative to a war zone's centre: clear of the camps (bases),
-- the boss posts and the oasis.
local TREASURE: { { any } } = {
	{ "DesertRift", 300, -300 },
	{ "DesertRift", -290, 300 },
	{ "JungleRift", 290, 290 },
	{ "JungleRift", -300, -280 },
	{ "DesertRift", 240, 180 },
}
local HIDDEN: { { any } } = {
	{ "DesertRift", 120, -40 },
	{ "DesertRift", -120, -60 },
	{ "DesertRift", 400, 120 },
	{ "DesertRift", -420, 100 },
	{ "DesertRift", 220, -150 },
	{ "DesertRift", -60, -200 },
	{ "JungleRift", 130, 60 },
	{ "JungleRift", -140, -40 },
	{ "JungleRift", 420, -200 },
	{ "JungleRift", -420, 60 },
	{ "JungleRift", 200, 160 },
	{ "JungleRift", -170, -200 },
}

EventChallenges.TREASURE_TITLE = "TreasureSeeker"
EventChallenges.HIDDEN_TITLE = "KeenEye"
EventChallenges.HIDDEN_TITLE_COUNT = 8
EventChallenges.DEFENDER_TITLE = "RealmDefender"
EventChallenges.DEFENDER_TITLE_KILLS = 10
EventChallenges.TOURNAMENT_TITLE = "TournamentVictor"
EventChallenges.PARADE_TITLE = "ParadeStar"
EventChallenges.PARADE_SECONDS = 5 * 60
-- Studs from a chest within which it can be opened.
EventChallenges.OPEN_REACH = 12

local REWARDS: { [string]: Reward } = {
	TreasureChest = table.freeze({ gold = 500, stones = 2 }),
	HiddenChest = table.freeze({ gold = 150, stones = 1 }),
	RaceWinner = table.freeze({ gold = 1000, stones = 2 }),
	RaceTaking = table.freeze({ gold = 300, stones = 0 }),
	Tournament1 = table.freeze({ gold = 3000, stones = 3, title = "TournamentVictor" }),
	Tournament2 = table.freeze({ gold = 2000, stones = 2 }),
	Tournament3 = table.freeze({ gold = 1000, stones = 1 }),
	Defender = table.freeze({ gold = 500, stones = 1 }),
	Parade = table.freeze({ gold = 200, stones = 0, title = "ParadeStar" }),
}
EventChallenges.REWARDS = table.freeze(REWARDS)

-- Defense waves: how many, how often, how many creatures each.
EventChallenges.WAVES = 5
EventChallenges.WAVE_SECONDS = 60
EventChallenges.WAVE_SIZE = 6
EventChallenges.WAVE_CREATURES =
	table.freeze({ "RiftWolf", "CrystalBeetle", "RiftWolf", "Thorncrawler", "RiftGuardian" })

local ZONE_NAMES = { DesertRift = "the Desert Rift", JungleRift = "the Jungle Rift" }

local function zone(zoneId: string): any
	return (WorldLayout.WarZones :: any)[zoneId]
end

--[[
	A clue for a spot (x, z) relative to the zone centre, from what players
	can see: whose camp's half of the zone it is in (the Angel camp lies at
	-z, the Devil camp at +z), how far from the oasis, and the nearest
	boss's post (its name floats over it).
]]
function EventChallenges.clue(zoneId: string, x: number, z: number): string
	local z_ = zone(zoneId)
	local side = "between the two camps"
	for race, base in z_.bases do
		if base.z * z > 0 and math.abs(z) > 60 then
			side = `on the {race} camp's half`
		end
	end
	local distance = math.sqrt(x * x + z * z)
	local far = if distance > 330
		then "far from the oasis"
		elseif distance < 180 then "close to the oasis"
		else "a fair walk from the oasis"
	local nearest, best = nil, math.huge
	for _, post in z_.bosses do
		local d = math.sqrt((post.x - x) ^ 2 + (post.z - z) ^ 2)
		if d < best then
			nearest, best = post.enemy, d
		end
	end
	return `In {ZONE_NAMES[zoneId]}, {side}, {far}, nearer to {nearest}'s lair than to any other.`
end

-- The chests event `eventId` hides (empty for other events).
function EventChallenges.chests(eventId: string): { Chest }
	local out: { Chest } = {}
	if eventId == "TreasureHunt" then
		for _, spot in TREASURE do
			table.insert(out, {
				zone = spot[1],
				x = spot[2],
				z = spot[3],
				treasure = true,
				clue = EventChallenges.clue(spot[1], spot[2], spot[3]),
			})
		end
	elseif eventId == "HiddenChestHunt" then
		for _, spot in HIDDEN do
			table.insert(out, { zone = spot[1], x = spot[2], z = spot[3], treasure = false })
		end
	end
	return out
end

-- The winning realm from victories per realm (nil on a tie or no wins).
function EventChallenges.raceWinner(scores: { [string]: number }): string?
	local angel, devil = scores.Angel or 0, scores.Devil or 0
	if angel == devil then
		return nil
	end
	return if angel > devil then "Angel" else "Devil"
end

--[[
	Players ranked by score (highest first; ties by who reached it first,
	`order` = when each player last scored, lower is earlier). Players
	with 0 are left out.
]]
function EventChallenges.rank(scores: { [any]: number }, order: { [any]: number }): { any }
	local list = {}
	for who, score in scores do
		if score > 0 then
			table.insert(list, who)
		end
	end
	table.sort(list, function(a, b)
		if scores[a] ~= scores[b] then
			return scores[a] > scores[b]
		end
		return (order[a] or 0) < (order[b] or 0)
	end)
	return list
end

-- The creature level for a defense wave from the defenders' levels.
function EventChallenges.waveLevel(levels: { number }): number
	if #levels == 0 then
		return 5
	end
	local total = 0
	for _, level in levels do
		total += level
	end
	return math.clamp(math.floor(total / #levels + 0.5), 1, 30)
end

-- Where a defense wave comes in: the far end of the realm's training yard
-- (world {x, y, z} points, `count` of them, spread across it).
function EventChallenges.wavePoints(race: string, count: number): { { number } }
	local realm = (WorldLayout.Realms :: any)[race]
	local center, size = WorldLayout.trainingYard(realm)
	local dir = WorldLayout.yardDirection(realm)
	local top = center[2] + size[2] / 2
	local z = center[3] + dir * (size[3] / 2 - 18)
	local out = {}
	for i = 1, count do
		local x = center[1] + (i - (count + 1) / 2) * (size[1] - 40) / math.max(count, 1)
		table.insert(out, { x, top, z })
	end
	return out
end

-- A claim id for event `eventId` run starting `startsAt`.
function EventChallenges.claimId(eventId: string, startsAt: number, what: string): string
	return `E:{eventId}:{startsAt}:{what}`
end

return EventChallenges
