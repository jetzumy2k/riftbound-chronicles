--!strict
--[[
	GearLook — what a character's equipped gear looks like (Phase 7 follow-
	up, PLAN.md D-65). Turns the profile's equipment into the facts the
	outfit builder draws from: per slot, the weapon family, the tier (1-3,
	more ornaments) and the rarity (its glow colour; Standard has none).

	Pure module.
]]

local ItemDefinitions = require(script.Parent.Parent.Definitions.ItemDefinitions)
local ItemRules = require(script.Parent.ItemRules)

export type SlotLook = {
	tier: number,
	rarity: string,
	family: string?, -- weapons only
	kind: string, -- ItemDef.slot: "Weapon", "Shield", "Ring", ...
	enhancement: number,
}

export type Look = { [string]: SlotLook } -- slot -> look; missing = nothing worn

local GearLook = {}

-- Glow colour per rarity (RGB). Standard gear doesn't glow.
GearLook.RARITY_GLOW = table.freeze({
	Uncommon = table.freeze({ 110, 225, 120 }),
	Rare = table.freeze({ 90, 160, 255 }),
	Epic = table.freeze({ 190, 110, 255 }),
	Legendary = table.freeze({ 255, 165, 50 }),
	Mythical = table.freeze({ 255, 80, 110 }),
})

-- Rarities whose weapon sheds a few sparkles; any weapon at +7 or more
-- sparkles too (D-66).
GearLook.SPARKLE = table.freeze({ Legendary = true, Mythical = true })
GearLook.SPARKLE_ENHANCEMENT = 7

function GearLook.sparkles(worn: SlotLook): boolean
	return GearLook.SPARKLE[worn.rarity] == true or worn.enhancement >= GearLook.SPARKLE_ENHANCEMENT
end

-- Enhancement aura (creator request 2026-10-27, PLAN.md D-110): stages
-- by enhancement. The weapon's own level sets its glow; the body aura
-- stacks with the AVERAGE enhancement of the six armor slots (an empty
-- slot counts 0), so every piece raised adds to it.
GearLook.AURA_STEPS = table.freeze({ 4, 7, 10 })
GearLook.ARMOR_SLOTS = table.freeze({ "Helm", "Shoulders", "Chest", "Hands", "Legs", "Boots" })
-- Aura colour of Standard gear (no rarity glow): soft gold.
GearLook.AURA_PLAIN = table.freeze({ 255, 220, 150 })
local RARITY_RANK = { Standard = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5, Mythical = 6 }

-- 0 (none) .. 3 for an enhancement level (or an average of levels).
function GearLook.auraStage(level: number): number
	local stage = 0
	for index, step in GearLook.AURA_STEPS do
		if level >= step then
			stage = index
		end
	end
	return stage
end

export type Aura = {
	weapon: number, -- weapon enhancement (0..10)
	weaponStage: number,
	weaponColor: { number },
	armor: number, -- average armor enhancement (0..10)
	armorStage: number,
	armorColor: { number }, -- best rarity among the enhanced armor
}

function GearLook.aura(look: Look): Aura
	local weapon = look.Weapon
	local weaponLevel = if weapon then weapon.enhancement else 0
	local sum, bestRank, bestColor = 0, 0, GearLook.AURA_PLAIN
	for _, slot in GearLook.ARMOR_SLOTS do
		local worn = look[slot]
		if worn and worn.enhancement > 0 then
			sum += worn.enhancement
			local rank = RARITY_RANK[worn.rarity] or 0
			if rank > bestRank then
				bestRank = rank
				bestColor = GearLook.RARITY_GLOW[worn.rarity] or GearLook.AURA_PLAIN
			end
		end
	end
	local armor = sum / #GearLook.ARMOR_SLOTS
	return {
		weapon = weaponLevel,
		weaponStage = GearLook.auraStage(weaponLevel),
		weaponColor = if weapon
			then GearLook.RARITY_GLOW[weapon.rarity] or GearLook.AURA_PLAIN
			else GearLook.AURA_PLAIN,
		armor = armor,
		armorStage = GearLook.auraStage(armor),
		armorColor = bestColor,
	}
end

--[[
	The look of what's equipped. `equipment` maps slot -> guid, `inventory`
	guid -> item; unknown, missing or wrong-slot entries draw nothing.
]]
function GearLook.fromEquipment(equipment: { [string]: any }?, inventory: { [string]: any }?): Look
	local look: Look = {}
	if type(equipment) ~= "table" or type(inventory) ~= "table" then
		return look
	end
	for slot, guid in equipment do
		local item = inventory[guid]
		local def = if type(item) == "table" then ItemDefinitions.get(item.DefId) else nil
		if def and ItemRules.fitsSlot(def, slot) then
			look[slot] = {
				tier = def.tier,
				rarity = item.Rarity,
				family = def.family,
				kind = def.slot,
				enhancement = if type(item.Enhancement) == "number" then item.Enhancement else 0,
			}
		end
	end
	return look
end

return table.freeze(GearLook)
