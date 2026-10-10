--!strict
--[[
	CombatMath — every combat number, computed only on the server
	(CombatService). Shared so the client can *display* previews, never decide.

	  PowerScale(L) = PowerScalePerLevel ^ L                        (D-01)
	  raw           = Attack * coefficient * PowerScale(attackerLevel)
	  K             = DefenseKBase + DefenseKPerLevel * attackerLevel  (D-05)
	  damage        = raw * K / (K + Defense), x CritMultiplier on crit, >= 1
	  crit          = roll < CritChancePct / 100                     (D-02/D-03)
	  heal          = Attack * coefficient * PowerScale(healerLevel), x crit
	  regen/second  = MaxHP * HPRegenPct / 100                        (D-04)

	Random rolls are passed in (0 <= roll < 1) so results are deterministic and
	testable. Pure module.
]]

export type Config = {
	PowerScalePerLevel: number,
	DefenseKBase: number,
	DefenseKPerLevel: number,
	RangeToleranceStuds: number,
	MaxPingCompensationSeconds: number,
}

export type HitInput = {
	attack: number,
	attackerLevel: number,
	coefficient: number,
	critChancePct: number,
	critMultiplier: number,
	roll: number,
	defense: number?, -- damage only
}

export type HarmFacts = {
	sameEntity: boolean,
	attackerIsPlayer: boolean,
	targetIsPlayer: boolean,
	attackerRace: string?,
	targetRace: string?,
	attackerInSafeZone: boolean,
	targetInSafeZone: boolean,
	attackerDefeated: boolean,
	targetDefeated: boolean,
	targetProtected: boolean,
}

local CombatMath = {}

function CombatMath.powerScale(level: number, config: Config): number
	return config.PowerScalePerLevel ^ level
end

function CombatMath.defenseK(attackerLevel: number, config: Config): number
	return config.DefenseKBase + config.DefenseKPerLevel * attackerLevel
end

function CombatMath.mitigate(raw: number, defense: number, k: number): number
	return raw * k / (k + math.max(defense, 0))
end

function CombatMath.isCrit(critChancePct: number, roll: number): boolean
	return roll < math.clamp(critChancePct, 0, 100) / 100
end

--[[
	Returns (damage, crit). Damage is a whole number >= 1.
]]
function CombatMath.damage(input: HitInput, config: Config): (number, boolean)
	local raw = input.attack * input.coefficient * CombatMath.powerScale(input.attackerLevel, config)
	local mitigated =
		CombatMath.mitigate(raw, input.defense or 0, CombatMath.defenseK(input.attackerLevel, config))
	local crit = CombatMath.isCrit(input.critChancePct, input.roll)
	if crit then
		mitigated *= input.critMultiplier
	end
	return math.max(1, math.floor(mitigated + 0.5)), crit
end

--[[
	Returns (heal, crit). Heal is a whole number >= 0 (Phase 5 healing skills).
]]
function CombatMath.heal(input: HitInput, config: Config): (number, boolean)
	local amount = input.attack * input.coefficient * CombatMath.powerScale(input.attackerLevel, config)
	local crit = CombatMath.isCrit(input.critChancePct, input.roll)
	if crit then
		amount *= input.critMultiplier
	end
	return math.max(0, math.floor(amount + 0.5)), crit
end

-- HP regenerated over `dt` seconds at `regenPct` percent of max HP per second.
function CombatMath.regen(maxHP: number, regenPct: number, dt: number): number
	return maxHP * regenPct / 100 * math.max(dt, 0)
end

--[[
	Server range check with bounded lag compensation (SECURITY_MODEL §5A.3):
	distance <= range + tolerance + min(ping, cap) * targetSpeed
]]
function CombatMath.withinRange(
	distance: number,
	range: number,
	pingSeconds: number,
	targetSpeed: number,
	config: Config
): boolean
	local compensation = math.min(math.max(pingSeconds, 0), config.MaxPingCompensationSeconds)
		* math.max(targetSpeed, 0)
	return distance <= range + config.RangeToleranceStuds + compensation
end

--[[
	May the attacker harm the target? Returns (allowed, reason).
	Safe zones block both directions; spawn protection blocks being hit;
	same-race players never harm each other (D-24).
]]
function CombatMath.canHarm(facts: HarmFacts): (boolean, string?)
	if facts.sameEntity then
		return false, "self"
	elseif facts.attackerDefeated then
		return false, "attackerDefeated"
	elseif facts.targetDefeated then
		return false, "targetDefeated"
	elseif facts.attackerInSafeZone or facts.targetInSafeZone then
		return false, "safeZone"
	elseif facts.targetProtected then
		return false, "protected"
	elseif facts.attackerIsPlayer and facts.targetIsPlayer and facts.attackerRace == facts.targetRace then
		return false, "sameRace"
	end
	return true, nil
end

return table.freeze(CombatMath)
