--!strict
--[[
	WeaponRules — the one place that says how each weapon family is held
	(equipment overhaul stage 1, PLAN.md D-68; the creator's weapon rules of
	2026-10-19). Everything else (server equip checks, the bag screen, the
	outfit builder, animations) reads this table.

	  family      hands  shield  dual  profile    classes
	  Sword        One    yes     yes   OneHand    Warrior (short sword);
	                                               Healer / Mage short sword
	  Mace         One    yes     -     OneHand    Warrior (small blunt)
	  Axe          One    yes     -     OneHand    Warrior (hand axe)
	  Greatsword   Two    no      -     TwoHand    Warrior (long sword)
	  WarHammer    Two    no      -     TwoHand    Warrior (large blunt)
	  BattleAxe    Two    no      -     TwoHand    Warrior (large axe)
	  Polearm      Two    no      -     TwoHand    Warrior (kept from D-35)
	  Dagger       One    no      -     Dagger     Healer, Mage
	  Staff        Two    no      -     Staff      Healer, Mage
	  Orb / Wand / Tome  One  no  -     Caster     extras kept (creator, 2026-10-19)
	  Bow          One*   no      -     Bow        Archer (*one-handed class,
	                                               but never with a shield)
	  Crossbow     Two    no      -     Crossbow   Archer

	`shield`: a shield may sit in the off-hand. Shields are Warrior gear, so
	other classes never hold one. `dual`: a second weapon of the same family
	may sit in the off-hand (Warrior dual swords: two separate items).

	Pure module.
]]

export type Hands = "One" | "Two"
export type Profile =
	"OneHand"
	| "Shield"
	| "TwoHand"
	| "Dual"
	| "Dagger"
	| "Staff"
	| "Caster"
	| "Bow"
	| "Crossbow"

export type Rule = {
	family: string,
	name: string, -- player-facing category
	hands: Hands,
	shield: boolean,
	dual: boolean,
	profile: Profile,
}

local function rule(
	family: string,
	name: string,
	hands: Hands,
	shield: boolean,
	dual: boolean,
	profile: Profile
): Rule
	return table.freeze({
		family = family,
		name = name,
		hands = hands,
		shield = shield,
		dual = dual,
		profile = profile,
	})
end

local WeaponRules = {}

WeaponRules.ByFamily = table.freeze({
	Sword = rule("Sword", "Short Sword", "One", true, true, "OneHand"),
	Mace = rule("Mace", "Mace", "One", true, false, "OneHand"),
	Axe = rule("Axe", "Hand Axe", "One", true, false, "OneHand"),
	Greatsword = rule("Greatsword", "Long Sword", "Two", false, false, "TwoHand"),
	WarHammer = rule("WarHammer", "War Hammer", "Two", false, false, "TwoHand"),
	BattleAxe = rule("BattleAxe", "Battle Axe", "Two", false, false, "TwoHand"),
	Polearm = rule("Polearm", "Polearm", "Two", false, false, "TwoHand"),
	Dagger = rule("Dagger", "Dagger", "One", false, false, "Dagger"),
	Staff = rule("Staff", "Staff", "Two", false, false, "Staff"),
	Orb = rule("Orb", "Orb", "One", false, false, "Caster"),
	Wand = rule("Wand", "Wand", "One", false, false, "Caster"),
	Tome = rule("Tome", "Tome", "One", false, false, "Caster"),
	Bow = rule("Bow", "Bow", "One", false, false, "Bow"),
	Crossbow = rule("Crossbow", "Crossbow", "Two", false, false, "Crossbow"),
}) :: { [string]: Rule }

function WeaponRules.get(family: string?): Rule?
	return if family then WeaponRules.ByFamily[family] else nil
end

-- "One-handed · shield allowed", "Two-handed · no shield", ...
function WeaponRules.describe(family: string?): string
	local r = WeaponRules.get(family)
	if r == nil then
		return ""
	end
	local hands = if r.hands == "Two" then "Two-handed" else "One-handed"
	local extra = if r.shield then "shield allowed" else "no shield"
	if r.dual then
		extra ..= " · can dual-wield"
	end
	return `{r.name} · {hands} · {extra}`
end

--[[
	The animation profile for what's in the hands (D-69): a main-hand
	family and what the off-hand holds ("Shield", "Weapon" or nil). Dual
	swords use "Dual"; a one-hander with a shield "Shield" (the shield arm
	held in guard).
]]
function WeaponRules.profileFor(mainFamily: string?, offHand: string?): Profile?
	local r = WeaponRules.get(mainFamily)
	if r == nil then
		return nil
	end
	if offHand == "Weapon" and r.dual then
		return "Dual"
	elseif offHand == "Shield" and r.shield then
		return "Shield"
	end
	return r.profile
end

-- The AnimationClips set each profile plays ("<Set>_Idle", "<Set>_Hold",
-- "<Set>_Attack1..3"). One-handers use the Warrior sword set, the orb /
-- wand / tome the Mage set, the bow the Archer set.
WeaponRules.CLIP_SET = table.freeze({
	OneHand = "Warrior",
	Shield = "Shield",
	TwoHand = "TwoHand",
	Dual = "Dual",
	Dagger = "Dagger",
	Staff = "Staff",
	Caster = "Mage",
	Bow = "Archer",
	Crossbow = "Crossbow",
}) :: { [string]: string }

return table.freeze(WeaponRules)
