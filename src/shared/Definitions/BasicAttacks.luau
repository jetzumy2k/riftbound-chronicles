--!strict
--[[
	BasicAttacks — one always-available attack per job (Phase 6 test attack;
	Phase 5 adds the equipped skill loadout on top).

	`range` is in studs, `cooldown` in seconds, `coefficient` multiplies the
	attacker's Attack (CombatMath.damage). The server owns all of these; the
	client only shows the cooldown.

	Display-safe data only. Pure module.
]]

export type BasicAttack = {
	job: string,
	name: string,
	range: number,
	cooldown: number,
	coefficient: number,
	-- Melee attacks may auto-target within a forward cone; ranged need line of sight.
	style: "Melee" | "Ranged" | "Magic",
}

local BasicAttacks = {}

BasicAttacks.ByJob = table.freeze({
	Warrior = table.freeze({
		job = "Warrior",
		name = "Blade Strike",
		range = 8,
		cooldown = 0.8,
		coefficient = 1.0,
		style = "Melee",
	} :: BasicAttack),
	Healer = table.freeze({
		job = "Healer",
		name = "Radiant Bolt",
		range = 32,
		cooldown = 1.0,
		coefficient = 0.7,
		style = "Magic",
	} :: BasicAttack),
	Mage = table.freeze({
		job = "Mage",
		name = "Arcane Missile",
		range = 40,
		cooldown = 1.1,
		coefficient = 1.05,
		style = "Magic",
	} :: BasicAttack),
	Archer = table.freeze({
		job = "Archer",
		name = "Quick Shot",
		range = 48,
		cooldown = 0.9,
		coefficient = 0.85,
		style = "Ranged",
	} :: BasicAttack),
})

function BasicAttacks.forJob(job: any): BasicAttack?
	if type(job) ~= "string" then
		return nil
	end
	return (BasicAttacks.ByJob :: any)[job]
end

return table.freeze(BasicAttacks)
