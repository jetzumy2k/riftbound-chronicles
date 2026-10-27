--!strict
--[[
	ShopRules — the Merchant and the Exchanger (creator request 2026-10-27,
	PLAN.md D-117). Pure; every number comes from the admin config (Shop /
	Exchange sections, passed in).

	Merchant
	  sells   Healing Potions, and every piece of the player's class
	          (weapons of their realm's families, armor, accessories) at
	          Standard, Uncommon or Rare, made at the player's level with
	          FIXED attributes (ItemRules.fixedRoll): nothing bought is a
	          random roll.
	  price   base[rarity] x (1 + level x LevelStepPct / 100)
	  buys    unused gear (not equipped, not locked): its rarity's base at
	          its level, x SellPct %, + EnhanceBonusPct % per +1.

	Exchanger (Mall Points are the account's, Gold the character's)
	  Mall Points -> Gold   1 MP gives GoldPerMallPoint Gold
	  Gold -> Mall Points   1 MP costs GoldForMallPoint Gold
	  Each direction has an optional daily limit in Mall Points (0 = none),
	  counted per account per UTC day.
]]

local ShopRules = {}

ShopRules.GEAR_RARITIES = table.freeze({ "Standard", "Uncommon", "Rare" })
ShopRules.POTION = "HealingPotion"
ShopRules.MAX_BUY = 99
ShopRules.MAX_EXCHANGE = 100000

export type ShopConfig = {
	Enabled: boolean,
	PotionPrice: number,
	GearBase: { [string]: number },
	SellBase: { [string]: number },
	LevelStepPct: number,
	SellPct: number,
	EnhanceBonusPct: number,
}

export type ExchangeConfig = {
	Enabled: boolean,
	GoldPerMallPoint: number,
	GoldForMallPoint: number,
	DailyMallPointsToGold: number,
	DailyGoldToMallPoints: number,
}

local function levelFactor(config: ShopConfig, level: number): number
	return 1 + math.max(0, level) * config.LevelStepPct / 100
end

-- Gold for one gear piece of `rarity` at `level`, or nil if not sold.
function ShopRules.gearPrice(config: ShopConfig, rarity: string, level: number): number?
	if table.find(ShopRules.GEAR_RARITIES, rarity) == nil then
		return nil
	end
	local base = config.GearBase[rarity]
	if type(base) ~= "number" then
		return nil
	end
	return math.max(1, math.floor(base * levelFactor(config, level)))
end

-- Gold the Merchant pays for an item (rarity, level, enhancement).
function ShopRules.sellPrice(config: ShopConfig, rarity: string, level: number, enhancement: number): number
	local base = config.SellBase[rarity] or 0
	local value = base * levelFactor(config, level) * config.SellPct / 100
	value *= 1 + math.max(0, enhancement) * config.EnhanceBonusPct / 100
	return math.max(0, math.floor(value))
end

function ShopRules.potionPrice(config: ShopConfig, count: number): number
	return config.PotionPrice * count
end

-- The exchange of `amount` Mall Points in `direction`: (gold, ok, reason).
-- "ToGold": spends `amount` MP for gold; "ToMallPoints": buys `amount` MP
-- for gold. `usedToday` is the MP already moved that way today.
function ShopRules.exchange(
	config: ExchangeConfig,
	direction: string,
	amount: number,
	usedToday: number
): (number, boolean, string?)
	if not config.Enabled then
		return 0, false, "closed"
	end
	if amount % 1 ~= 0 or amount < 1 or amount > ShopRules.MAX_EXCHANGE then
		return 0, false, "amount"
	end
	local cap = if direction == "ToGold" then config.DailyMallPointsToGold else config.DailyGoldToMallPoints
	if cap > 0 and usedToday + amount > cap then
		return 0, false, "daily"
	end
	if direction == "ToGold" then
		return amount * config.GoldPerMallPoint, true, nil
	elseif direction == "ToMallPoints" then
		return amount * config.GoldForMallPoint, true, nil
	end
	return 0, false, "direction"
end

-- The UTC day number (for the daily limits).
function ShopRules.day(t: number): number
	return t // 86400
end

-- Gold a creature drops: GoldPctOfXp % of its EXP, split between the
-- players who earned it (at least 1 each).
function ShopRules.killGold(xp: number, pct: number, recipients: number): number
	if recipients < 1 or pct <= 0 then
		return 0
	end
	return math.max(1, math.floor(xp * pct / 100 / recipients))
end

return table.freeze(ShopRules)
