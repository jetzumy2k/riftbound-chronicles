--!strict
--[[
	CharacterSlots — up to Constants.Characters.MaxSlots characters per
	account (creator request 2026-10-27, PLAN.md D-115).

	The profile keeps its shape: its top-level fields ARE the character being
	played (every service keeps reading them as before). The other
	characters are stored whole in `Characters["<slot>"]`, and `ActiveSlot`
	says which slot the top level belongs to.

	  Account-wide (stay at the top level for every character): the realm
	  (Race), Mall Points and the Robux total, settings, moderation flags,
	  reset version, timestamps, and the account reward claims (Robux
	  receipts R:, staff pay S:).
	  Per character (CHARACTER_FIELDS, moved in and out): class, looks,
	  level, attributes, skills, bag and gear, Gold and PvP Marks, buffs,
	  quests, story, titles, cosmetics, PvP stats, event progress and the
	  other reward claims.

	Switching never touches a live profile: the server records PendingSlot
	and the player rejoins; the swap happens on the next load
	(applyPending), before any service sees the data.

	Pure module.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Constants = require(Shared.Constants)
local FacePresets = require(Shared.Definitions.FacePresets)
local ProfileTemplate = require(script.Parent.ProfileTemplate)

local CharacterSlots = {}

CharacterSlots.MAX = Constants.Characters.MaxSlots

CharacterSlots.CHARACTER_FIELDS = table.freeze({
	"Job",
	"FacePreset",
	"HeadStyle",
	"SkinTone",
	"HairColor",
	"Level",
	"Experience",
	"TotalExperience",
	"Attributes",
	"AttributeResetAt",
	"OwnedSkills",
	"EquippedSkills",
	"Inventory",
	"Equipment",
	"Stackables",
	"Buffs",
	"QuestState",
	"StoryFlags",
	"Titles",
	"Cosmetics",
	"EquippedCosmetics",
	"EquippedTitle",
	"PvPStats",
	"EventProgress",
	"Chain",
	"BonusAttributes",
	"Roulette",
	"TradeHistory",
	"Escrow",
	"PuzzleDay",
})
-- Per-character wallet keys (Mall Points stay with the account).
CharacterSlots.WALLET_FIELDS = table.freeze({ "Gold", "PvPMarks" })
-- Reward-claim prefixes that belong to the account.
CharacterSlots.ACCOUNT_CLAIMS = table.freeze({ R = true, S = true })

type Data = { [string]: any }

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in value do
		out[k] = deepCopy(v)
	end
	return out
end

local function isAccountClaim(id: any): boolean
	local prefix = if type(id) == "string" then string.match(id, "^(%u+):") else nil
	return prefix ~= nil and CharacterSlots.ACCOUNT_CLAIMS[prefix] == true
end

-- True if the top level holds a created character (its class is chosen).
function CharacterSlots.activeExists(data: Data): boolean
	return data.Job ~= nil
end

-- The character at the top level, as a stored blob (copies; the profile
-- is left as it was).
function CharacterSlots.extract(data: Data): Data
	local blob: Data = {}
	for _, field in CharacterSlots.CHARACTER_FIELDS do
		blob[field] = deepCopy(data[field])
	end
	local wallet = {}
	for _, field in CharacterSlots.WALLET_FIELDS do
		wallet[field] = if type(data.Wallet) == "table" then data.Wallet[field] else nil
	end
	blob.Wallet = wallet
	local claims = {}
	for id, at in (if type(data.ClaimedRewardIds) == "table" then data.ClaimedRewardIds else {}) :: Data do
		if not isAccountClaim(id) then
			claims[id] = at
		end
	end
	blob.Claims = claims
	return blob
end

--[[
	Puts `blob` (nil: a brand-new character of the account's realm) at the
	top level, replacing the character there. Account fields are kept.
]]
function CharacterSlots.install(data: Data, blob: Data?)
	local fresh = ProfileTemplate.new()
	local source: Data = blob or fresh
	for _, field in CharacterSlots.CHARACTER_FIELDS do
		local value = source[field]
		if value == nil and blob ~= nil and field ~= "Job" and field ~= "EquippedTitle" then
			value = fresh[field]
		end
		data[field] = deepCopy(value)
	end
	if blob == nil then
		data.Job = nil
		data.EquippedTitle = nil
		if data.Race then
			data.FacePreset = FacePresets.defaultFor(data.Race)
		end
	end
	if type(data.Wallet) ~= "table" then
		data.Wallet = fresh.Wallet
	end
	local wallet = if blob and type(blob.Wallet) == "table" then blob.Wallet else {}
	for _, field in CharacterSlots.WALLET_FIELDS do
		data.Wallet[field] = if type(wallet[field]) == "number" then wallet[field] else 0
	end
	local claims = {}
	for id, at in (if type(data.ClaimedRewardIds) == "table" then data.ClaimedRewardIds else {}) :: Data do
		if isAccountClaim(id) then
			claims[id] = at
		end
	end
	if blob and type(blob.Claims) == "table" then
		for id, at in blob.Claims do
			if not isAccountClaim(id) then
				claims[id] = at
			end
		end
	end
	data.ClaimedRewardIds = claims
end

local function validSlot(slot: any): boolean
	return type(slot) == "number" and slot % 1 == 0 and slot >= 1 and slot <= CharacterSlots.MAX
end
CharacterSlots.validSlot = validSlot

-- How many characters the account has (the played one included).
function CharacterSlots.count(data: Data): number
	local n = if CharacterSlots.activeExists(data) then 1 else 0
	for key in (data.Characters or {}) :: Data do
		if tonumber(key) ~= data.ActiveSlot then
			n += 1
		end
	end
	return n
end

export type Summary = { Slot: number, Empty: boolean, Active: boolean, Job: string?, Level: number? }

-- Every slot, in order, for the character screen.
function CharacterSlots.summary(data: Data): { Summary }
	local out = {}
	for slot = 1, CharacterSlots.MAX do
		if slot == data.ActiveSlot then
			local exists = CharacterSlots.activeExists(data)
			table.insert(out, {
				Slot = slot,
				Empty = not exists,
				Active = true,
				Job = data.Job,
				Level = if exists then data.Level else nil,
			})
		else
			local blob = (data.Characters or {})[tostring(slot)]
			table.insert(out, {
				Slot = slot,
				Empty = blob == nil,
				Active = false,
				Job = if blob then blob.Job else nil,
				Level = if blob then blob.Level else nil,
			})
		end
	end
	return out
end

--[[
	Applies a switch recorded by the server (PendingSlot): stores the played
	character in its slot and installs the chosen one (an empty slot starts
	a new character). Returns true if anything changed.
]]
function CharacterSlots.applyPending(data: Data): boolean
	local pending = data.PendingSlot
	data.PendingSlot = nil
	if not validSlot(pending) or pending == data.ActiveSlot then
		return false
	end
	data.Characters = if type(data.Characters) == "table" then data.Characters else {}
	if CharacterSlots.activeExists(data) then
		data.Characters[tostring(data.ActiveSlot)] = CharacterSlots.extract(data)
	end
	local key = tostring(pending)
	CharacterSlots.install(data, data.Characters[key])
	data.Characters[key] = nil
	data.ActiveSlot = pending
	return true
end

--[[
	D-116: converts the account to `race` (Race Conversion Rune): the realm
	changes and every character's face preset becomes the new realm's
	default (presets belong to a realm). Gear, weapons and items are
	realm-free ids (ItemDefinitions), so they carry over unchanged and draw
	in the new realm's look. Returns true if anything changed.
]]
function CharacterSlots.convertRace(data: Data, race: string): boolean
	if data.Race == nil or data.Race == race then
		return false
	end
	data.Race = race
	local face = FacePresets.defaultFor(race)
	data.FacePreset = face
	for _, blob in (if type(data.Characters) == "table" then data.Characters else {}) :: Data do
		blob.FacePreset = face
	end
	return true
end

--[[
	Deletes the character in `slot`. Returns (ok, reason, rejoin):
	  - another slot: removed at once (no rejoin);
	  - the played one: cleared, and the player rejoins on another character
	    (the lowest slot), or, if it was the last, with no realm so race
	    selection opens again (D-116 option 1).
]]
function CharacterSlots.delete(data: Data, slot: number): (boolean, string?, boolean)
	if not validSlot(slot) then
		return false, "slot", false
	end
	data.Characters = if type(data.Characters) == "table" then data.Characters else {}
	if slot ~= data.ActiveSlot then
		if data.Characters[tostring(slot)] == nil then
			return false, "empty", false
		end
		data.Characters[tostring(slot)] = nil
		return true, nil, false
	end
	if not CharacterSlots.activeExists(data) then
		return false, "empty", false
	end
	CharacterSlots.install(data, nil)
	local nextSlot: number? = nil
	for other = 1, CharacterSlots.MAX do
		if data.Characters[tostring(other)] ~= nil then
			nextSlot = other
			break
		end
	end
	if nextSlot then
		data.PendingSlot = nextSlot
	else
		-- The last character: the realm is free to choose again.
		data.Race = nil
		data.FacePreset = 1
	end
	return true, nil, true
end

return table.freeze(CharacterSlots)
