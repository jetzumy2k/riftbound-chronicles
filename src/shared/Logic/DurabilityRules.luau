--!strict
--[[
	DurabilityRules — gear wear and repair (creator request 2026-10-27,
	PLAN.md D-118; numbers in config Durability). Pure.

	Every weapon, armor piece and accessory has Durability 0..MAX (an old
	item without one counts as new). Equipped gear wears a little each time
	its owner earns a creature's EXP (weapons faster than armor) and on
	defeat. At 0 the item is BROKEN: its stats stop counting
	(ItemRules.gearTotals) until the Blacksmith repairs it. It is never
	destroyed (CLAUDE.md §14: no item loss).

	Repair cost = missing points x RepairGoldPerPoint[rarity] x (1 + item
	level x RepairLevelStepPct / 100), rounded up.
]]

local Constants = require(script.Parent.Parent.Constants)

local DurabilityRules = {}

DurabilityRules.MAX = Constants.Durability.Max
-- At or under this share of MAX the owner is told it is wearing out.
DurabilityRules.LOW_PCT = 20

export type Config = {
	Enabled: boolean,
	WeaponWearPerKill: number,
	ArmorWearPerKill: number,
	DefeatWearPct: number,
	PvPDefeatWear: boolean,
	RepairGoldPerPoint: { [string]: number },
	RepairLevelStepPct: number,
}

-- An item's durability (missing = new).
function DurabilityRules.of(item: any): number
	local value = if type(item) == "table" then item.Durability else nil
	return if type(value) == "number" then math.clamp(value, 0, DurabilityRules.MAX) else DurabilityRules.MAX
end

function DurabilityRules.isBroken(item: any): boolean
	return DurabilityRules.of(item) <= 0
end

-- The wear for one creature for an item worn in `slot`.
function DurabilityRules.killWear(config: Config, slot: string, isWeapon: boolean): number
	if not config.Enabled then
		return 0
	end
	return if isWeapon or slot == "Weapon" then config.WeaponWearPerKill else config.ArmorWearPerKill
end

-- The wear on defeat (by a player: only if PvPDefeatWear).
function DurabilityRules.defeatWear(config: Config, byPlayer: boolean): number
	if not config.Enabled or (byPlayer and not config.PvPDefeatWear) then
		return 0
	end
	return DurabilityRules.MAX * config.DefeatWearPct / 100
end

--[[
	Wears `item` by `amount`. Returns (new value, crossed): crossed is
	"broken" when it reached 0 now, "low" when it fell to LOW_PCT now.
]]
function DurabilityRules.wear(item: any, amount: number): (number, string?)
	local before = DurabilityRules.of(item)
	if amount <= 0 or before <= 0 then
		return before, nil
	end
	local after = math.max(0, math.floor((before - amount) * 100 + 0.5) / 100)
	local low = DurabilityRules.MAX * DurabilityRules.LOW_PCT / 100
	local crossed: string? = if after <= 0
		then "broken"
		elseif before > low and after <= low then "low"
		else nil
	return after, crossed
end

-- Gold to repair `item` to full (0 when it is full).
function DurabilityRules.repairCost(config: Config, item: any): number
	local missing = DurabilityRules.MAX - DurabilityRules.of(item)
	if missing <= 0 then
		return 0
	end
	local per = config.RepairGoldPerPoint[item.Rarity] or 1
	local level = if type(item.ItemLevel) == "number" then item.ItemLevel else 0
	return math.max(1, math.ceil(missing * per * (1 + level * config.RepairLevelStepPct / 100)))
end

return table.freeze(DurabilityRules)
