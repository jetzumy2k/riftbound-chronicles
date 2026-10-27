--!strict
--[[
	RouletteRules — the Fortune Wheel (creator request 2026-10-27, PLAN.md
	D-120; numbers in config Roulette). Pure: the server passes the random
	rolls in.

	Spins: FreeSpinsPerDay free a day per character, then GoldPerSpin Gold
	each (creator decision: never Robux or Mall Points, so it is not a paid
	random item). The odds are shown on the wheel.

	Prizes, most to least likely (default weights, out of 100):
	  ThankYou    40  "Thank you for playing!"
	  Standard    25  a Standard piece of your class at your level
	  Rare        17  a Rare piece
	  Consumable  10  potions, Enhancement Stones or a buff draught
	  Attribute    4  +1 to a random attribute, permanently (a bonus point
	                  that no reset takes away)
	  Level        2  +1 level (at level 30: a consumable instead)
	  Legendary    2  a Legendary piece
]]

local RouletteRules = {}

RouletteRules.PRIZES =
	table.freeze({ "ThankYou", "Standard", "Rare", "Consumable", "Attribute", "Level", "Legendary" })

RouletteRules.INFO = table.freeze({
	ThankYou = table.freeze({ icon = "🙏", name = "Thank you!" }),
	Standard = table.freeze({ icon = "🔘", name = "Standard gear" }),
	Rare = table.freeze({ icon = "🔷", name = "Rare gear" }),
	Consumable = table.freeze({ icon = "🧪", name = "Consumable" }),
	Attribute = table.freeze({ icon = "📊", name = "+1 attribute" }),
	Level = table.freeze({ icon = "🆙", name = "+1 level" }),
	Legendary = table.freeze({ icon = "🔶", name = "Legendary gear" }),
})

-- Consumable prizes; id "Buff" = a random buff draught.
RouletteRules.CONSUMABLES = table.freeze({
	table.freeze({ id = "HealingPotion", count = 5 }),
	table.freeze({ id = "GreaterHealingPotion", count = 2 }),
	table.freeze({ id = "EnhancementStone", count = 2 }),
	table.freeze({ id = "Buff", count = 1 }),
})

RouletteRules.MAX_BONUS = 50

export type Config = {
	Enabled: boolean,
	FreeSpinsPerDay: number,
	GoldPerSpin: number,
	Weights: { [string]: number },
}

-- (ok, reason): every prize has a whole weight 0..100 and they sum to 100.
function RouletteRules.validate(weights: any): (boolean, string?)
	if type(weights) ~= "table" then
		return false, "missing"
	end
	local total = 0
	for _, prize in RouletteRules.PRIZES do
		local w = weights[prize]
		if type(w) ~= "number" or w < 0 or w > 100 or w % 1 ~= 0 then
			return false, `weight {prize}`
		end
		total += w
	end
	if total ~= 100 then
		return false, `weights add up to {total}, not 100`
	end
	return true, nil
end

-- The prize for `roll` (0..1) on `weights` (valid ones).
function RouletteRules.pick(weights: { [string]: number }, roll: number): string
	local at = roll * 100
	local sum = 0
	for _, prize in RouletteRules.PRIZES do
		sum += weights[prize]
		if at < sum then
			return prize
		end
	end
	return RouletteRules.PRIZES[1]
end

-- Free spins left today for a stored { Day, Used }.
function RouletteRules.freeLeft(state: any, config: Config, day: number): number
	local used = if type(state) == "table" and state.Day == day then state.Used or 0 else 0
	return math.max(0, config.FreeSpinsPerDay - used)
end

return table.freeze(RouletteRules)
