--!strict
--[[
	PotionRules — the healing potions (D-106, creator request 2026-10-27).

	Four sizes (30 / 50 / 75 / 90% of max HP) that share one cooldown: using
	any of them starts the wait for all (InventoryService). The quick potion
	button drinks the smallest potion that heals what is missing, else the
	biggest one owned, so a scratch never burns a Supreme potion.

	Pure.
]]

local ItemDefinitions = require(script.Parent.Parent.Definitions.ItemDefinitions)

local PotionRules = {}

-- Weakest first.
PotionRules.IDS = table.freeze({
	"HealingPotion",
	"GreaterHealingPotion",
	"MajorHealingPotion",
	"SupremeHealingPotion",
})

-- % of max HP the potion restores (0 for anything else).
function PotionRules.pctOf(id: string): number
	local def = ItemDefinitions.Stackables[id]
	local use = def and def.use
	return if use and use.kind == "HealPct" then use.pct or 0 else 0
end

-- Whether `id` is a healing potion (they share one cooldown).
function PotionRules.isPotion(id: string): boolean
	return PotionRules.pctOf(id) > 0
end

-- Total potions of every size in `have` (stackable counts by id).
function PotionRules.count(have: { [string]: number }): number
	local total = 0
	for _, id in PotionRules.IDS do
		total += have[id] or 0
	end
	return total
end

--[[
	The potion the quick button drinks for `missingPct` (0..100) of max HP
	missing: the smallest owned one that covers it, else the biggest owned.
	nil if none is owned.
]]
function PotionRules.pick(have: { [string]: number }, missingPct: number): string?
	local biggest: string? = nil
	for _, id in PotionRules.IDS do
		if (have[id] or 0) > 0 then
			if PotionRules.pctOf(id) >= missingPct then
				return id
			end
			biggest = id
		end
	end
	return biggest
end

-- D-126: the quick button's setting: "Auto" (pick above) or one potion.
PotionRules.CHOICES = table.freeze({
	"Auto",
	"HealingPotion",
	"GreaterHealingPotion",
	"MajorHealingPotion",
	"SupremeHealingPotion",
})

function PotionRules.isChoice(value: any): boolean
	return type(value) == "string" and table.find(PotionRules.CHOICES, value) ~= nil
end

--[[
	The potion the quick button drinks with the player's `choice`: that
	potion while any are left, else the automatic pick.
]]
function PotionRules.choose(have: { [string]: number }, missingPct: number, choice: string?): string?
	if choice and choice ~= "Auto" and (have[choice] or 0) > 0 then
		return choice
	end
	return PotionRules.pick(have, missingPct)
end

return table.freeze(PotionRules)
