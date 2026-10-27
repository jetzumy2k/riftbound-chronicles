--!strict
--[[
	ResetRules — what a system reset clears (creator decisions 2026-10-27,
	PLAN.md D-111). The Owner picks what to KEEP; everything else goes back
	to a new character's value.

	  Items      consumables / stones / scrolls, running Mall buffs, Gold
	             and PvP Marks
	  Gear       every weapon, armor piece and accessory (bag + equipped)
	  MallPoints all Mall Points. Points bought with Robux are ALWAYS kept
	             (Wallet.PurchasedMallPoints caps what a reset can take)
	  Levels     level, EXP, attribute points and the skill tree (points
	             come from levels, so they go together)
	  Rankings   PvP victories / defeats / participations

	Always cleared: quests, story flags and event progress (and the quest /
	starter-gift claims, so those rewards can be earned again; the starter
	gift only when gear is cleared). Always kept: realm, class, looks,
	titles and cosmetics, settings, moderation flags, Robux receipts and
	the other reward claims (they stop duplicate payouts).

	Pure module.
]]

local ResetRules = {}

ResetRules.KEEP_KEYS = table.freeze({ "Items", "Gear", "MallPoints", "Levels", "Rankings" })
ResetRules.CONFIRM_TEXT = "RESET"

export type Keep = { [string]: boolean }

-- A copy of `keep` with only known keys (missing = clear it).
function ResetRules.normalize(keep: any): Keep
	local out: Keep = {}
	for _, key in ResetRules.KEEP_KEYS do
		out[key] = type(keep) == "table" and keep[key] == true
	end
	return out
end

-- True if a profile last reset at `profileVersion` must take reset `version`.
function ResetRules.due(profileVersion: any, version: any): boolean
	return type(version) == "number"
		and version > 0
		and (type(profileVersion) ~= "number" or profileVersion < version)
end

local function claimPrefix(id: string): string?
	return string.match(id, "^(%u+):")
end

--[[
	Applies reset `version` to `data` in place. `fresh` is a new profile
	(ProfileTemplate.new()) to copy cleared fields from. Returns a short
	list of what was cleared (for the audit log).
]]
function ResetRules.apply(
	data: { [string]: any },
	keep: Keep,
	version: number,
	fresh: { [string]: any }
): { string }
	local cleared = {}
	local function reset(field: string)
		data[field] = fresh[field]
	end
	local wallet = data.Wallet
	if not keep.Items then
		reset("Stackables")
		reset("Buffs")
		wallet.Gold = 0
		wallet.PvPMarks = 0
		table.insert(cleared, "Items")
	end
	if not keep.Gear then
		reset("Inventory")
		reset("Equipment")
		table.insert(cleared, "Gear")
	end
	if not keep.MallPoints then
		local bought = math.max(0, tonumber(wallet.PurchasedMallPoints) or 0)
		wallet.MallPoints = math.min(wallet.MallPoints or 0, bought)
		table.insert(cleared, "MallPoints")
	end
	if not keep.Levels then
		for _, field in { "Level", "Experience", "TotalExperience", "Attributes", "AttributeResetAt" } do
			reset(field)
		end
		reset("OwnedSkills")
		reset("EquippedSkills")
		table.insert(cleared, "Levels")
	end
	if not keep.Rankings then
		reset("PvPStats")
		table.insert(cleared, "Rankings")
	end
	reset("QuestState")
	reset("StoryFlags")
	reset("EventProgress")
	local claims = data.ClaimedRewardIds
	if type(claims) == "table" then
		for id in claims do
			local prefix = claimPrefix(id)
			if prefix == "Q" or (prefix == "G" and not keep.Gear) then
				claims[id] = nil
			end
		end
	end
	table.insert(cleared, "Quests")
	data.ResetVersion = version
	return cleared
end

return table.freeze(ResetRules)
