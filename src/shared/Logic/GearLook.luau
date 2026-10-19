--!strict
--[[
	GearLook — what a character's equipped gear looks like (Phase 7 follow-
	up, PLAN.md D-65). Turns the profile's equipment into the facts the
	outfit builder draws from: per slot, the weapon family, the tier (1-3,
	more ornaments) and the rarity (its glow colour; Standard has none).

	Pure module.
]]

local ItemDefinitions = require(script.Parent.Parent.Definitions.ItemDefinitions)

export type SlotLook = {
	tier: number,
	rarity: string,
	family: string?, -- weapons only
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
		if def and def.slot == slot then
			look[slot] = {
				tier = def.tier,
				rarity = item.Rarity,
				family = def.family,
				enhancement = if type(item.Enhancement) == "number" then item.Enhancement else 0,
			}
		end
	end
	return look
end

return table.freeze(GearLook)
