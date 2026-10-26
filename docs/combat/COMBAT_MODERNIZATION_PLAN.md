# Combat modernization: skills, skill tree, combos, animation, VFX (PLAN.md D-103)

Creator request 2026-10-26: upgrade the existing skill tree, skills,
combos, animations and effects to a modern fantasy anime MMORPG feel.
**Upgrade what exists. Don't build a second system.**

## 1. Inspection: what exists today

| System | Where | What it does now |
|---|---|---|
| **Skill tree data** | `Definitions/SkillDefinitions` (2,650 lines) | 4 jobs × 4 branches × 6 tiers = **96 skills**, plus Auto Attack. Tiers 1, 2, 4, 5 are Regular (rank 1-5); tier 3 and tier 6 are Special (rank 1-3). The **tier-6 capstone of each branch is the ultimate**. Fields: category, target, range / radius, cooldown, focusCost, clip, projectileSpeed, waves, delay, effects, combo, fx. |
| **Tree rules** | `Logic/SkillRules` | Skill points (1 + 1 per level), unlock level per tier and column, rank caps by level, prerequisite = the skill above, 6 + 1 loadout validation, canCast (cooldown, global cooldown, Focus, stun / silence), effect numbers per rank, combo checks, PvP control scaling. |
| **Server casting** | `SkillService` (692) + `CombatService` (1,589) | Validates and runs every cast: ownership, job, range, target, Focus, cooldowns; damage = coefficient × Attack (CombatMath); 20 effect kinds (Damage, Heal, Shield, Poison, Burn, Regen, Stun, Freeze, Root, Slow, Silence, Mark, Weaken, Guard, Harden, Empower, Haste, Taunt, Cleanse, Dash). |
| **Classes** | `JobDefinitions` | Warrior: Blademaster, Ironclad, Warlord, Vanguard. Healer: Light, Sanctity, Judgment, Seraph. Archer: Marksman, Venom, Ranger, Windrunner. Mage: Pyromancy, Cryomancy, Arcanist, Stormcaller. Allowed categories enforced on the server. |
| **Stats** | `StatFormulas`, `AttributeRules` (D-90), `StatsService` | CLAUDE.md §5 level growth; 5 attributes REC / INT / WIS / STR / AGI. **STR = physical damage** (Warrior, Archer), **INT = magic damage** (Mage, Healer), WIS = Focus, magic resistance, Healing Power, AGI = dodge. **Focus is the game's mana.** |
| **Buffs** | `BuffRules` / `BuffService` | Mall consumable buffs only (saved, timed). Combat buffs (Empower, Guard, Harden, Haste) live in CombatService status tables and expire there. |
| **Combo** | `BasicAttacks` + `Logic/ComboMath` | A 3-step basic-attack chain per job (recovery, window, finisher cooldown, lunge, heavy finisher). Skill **combos**: bonus damage when the target has a status or is below an HP %, optional consume, "COMBO · NAME" title. |
| **Animation** | `AnimationClips` (2,614) + `AnimationController` | Keyframe clips authored as data (no external assets), registered at runtime; Hit markers time the damage; upper-body variants while moving; hit-stop. |
| **VFX** | `Effects/SkillVfx` (931), `CombatVfx` (518), `TelegraphVfx`, `CameraShake`, `StatusVfxController` | Recipe per skill: element palette (10), cast (4), travel (6), impact (10), area (7). Parts + particles, Debris cleanup, client only. |
| **Skill tree UI** | `SkillTreeController` (877) + `Layout/SkillTreeLayout`, `UI/SkillIcon`, `UI/SkillInfo` | 4 columns × 6 rows of nodes with drawn icons, rank badge, padlock / level, gold prerequisite lines, detail pane, loadout row, Stats page. |

### Not in the project (the request assumed them)
- **EOA / Extender EOA**: no skill, field or code uses these names. Read here as
  **Area of Effect** (the area skills) and an **Extender** that builds on an
  area the caster already placed (decision Q1).
- **Passive skills**: no passive type exists (decision Q4).
- **Warrior Dash**: Warriors have no dash; only Archers (Evasive Roll, Skyward Leap).
- **Mana**: the game calls it **Focus**. The plan keeps Focus.
- **Mage damage stat**: in D-90, magic damage comes from INT, not WIS (decision Q3).

## 2. Mapping the requested roles to existing skills (no duplicates)

| Request | Warrior Attack (Blademaster + Warlord) | Warrior Defense (Ironclad + Vanguard) | Archer | Mage | Healer |
|---|---|---|---|---|---|
| Spam (low cooldown) | Cleaving Strike, Hamstring | Rallying Strike, Shield Bash | Piercing Shot, Gust Shot, Venom Arrow | Fireball, Frost Bolt, Spark Bolt, Arcane Missiles | Smite, Radiant Strike, Mending Light |
| Stun / Slow / Poison | Hamstring, Crippling Blow | Shield Bash, Challenger's Roar (taunt) | Crippling Shot, Entangling Arrow, Venom Arrow, Serpent Sting | Frost Bind, Glacial Prison, Hex, Living Bomb (burn) | Halo of Silence, Holy Brand, Lightbinder |
| Dash | **new:** Cleaving Strike gains a short charge-in | — | Evasive Roll, Skyward Leap | — | — |
| EOA (area) | Whirlwind, Ground Slam | Sweeping Blow, **Bulwark → "corrupting" area** (targets take +% damage) | Multi Shot, Toxic Cloud, Ricochet | Flame Wave, Static Field, Chain Lightning | Radiant Burst, Consecrate, Lifewell (area heal), Aura of Resolve (area defence) |
| Extender EOA | Sunder | Steadfast | Plague Volley follow-up via Ricochet | Combustion | Penance |
| Ultimate | Blade Storm / Earthsplitter (STR + HP scaling, execute) | Unbreakable / Avatar of War (party reflect) | Heartseeker / Arrow Rain / Tempest Volley (AGI scaling) | Meteor / Blizzard / Thunderstorm / Arcane Nova (Q3 stat) | Divine Grace / Aegis of Dawn (party protection) |

Existing ids, names, remotes and attributes keep their names. Changes are to
numbers, effects, fx recipes and clips, so saved skill ranks stay valid.

## 3. Plan in stages (one stage per Studio test and commit)

**Stage A — Skill tree UI** (`SkillTreeController`, `SkillTreeLayout`, `SkillIcon`, `SkillInfo`, `Theme`)
- Class themes: Warrior crimson / black / gold / steel; Archer emerald / teal / silver; Mage violet / blue / cyan; Healer white / gold / celestial blue.
- Node frames by kind: regular (round), special (hexagon), **ultimate** (large, animated glow), passive (diamond, if Q4).
- Branch headers with a role label (for example "Attack build", "Defense build"), prerequisite lines that light up and pulse when learnable.
- Chips on every node: cooldown, Focus cost, damage / heal type; hover and selection tweens; learn / rank-up burst and sound.
- Fix the stale "3 + 1" header text (the bar is 6 + 1, D-75).

**Stage B — VFX framework** (`Effects/SkillVfx`, `CombatVfx`, new `Effects/VfxKit`)
- Shared kit: pooled parts, Beams, Trails, Attachments, one budget per character, effects off past `DetailRules.NEAR` on other players (D-102).
- Weapon trails on every attack, new travel (piercing arrow, chain bolt), impacts (crit starburst, rune shatter), areas (arcane circle, holy dome, poison cloud), **ultimate cinematic**: under 1 s wind-up, screen flash, camera push, ground sigil.
- Death / defeat stays non-graphic (light, no blood, CLAUDE.md §14).

**Stage C — Combo system** (`ComboMath`, `BasicAttacks`, `CombatController`, `CombatFeedbackController`)
- Skill chaining: a skill pressed during a basic-attack recovery cancels it (the server checks the same window).
- Combo counter on the HUD (hits within 2.5 s), combo-window cue, crit effects, a hit-stop and shake profile per class (Warrior heavy, Archer quick, Mage burst, Healer soft).

**Stage D — Skill rework per class** (`SkillDefinitions`, `SkillRules`, `CombatService`, `CombatMath`)
- New effect kinds: `Vulnerable` (area weakening), `Reflect`, `Extend` (enlarges / re-pulses the caster's own active area), `Execute` (threshold), optional attribute scaling `scaling = { STR = x, MaxHP = y }` for ultimates.
- Every new number in Config with a schema and admin audit (CLAUDE.md §12, §21); balance re-run with the Phase 20 simulation tool.

**Stage E — Passives** (if Q4), **then animation polish** (new clips per class in `AnimationClips`, all data-authored, no external assets).

## 4. Safety and security rules kept
- The server still decides every cast, target, range, cooldown, Focus cost, damage, buff and debuff. New effects run in CombatService; the client only draws.
- Buffs never write to base stats; they are timed status entries, cleared on death, respawn and leave, and never stack past a cap.
- No permanent invulnerability, no unconditional instant kill on bosses or players.
- New effects are client-side, pooled and capped for phones.

## 5. Decisions (creator, 2026-10-26)
- **Q1 EOA:** EOA = the area skills. **Extender** = a follow-up skill: if the
  caster's own area is still active, it grows, lasts longer and pulses again.
- **Q2 Ultimates, safe limits:** Healer party ultimate = 8 s full immunity in
  PvE, 60% damage cut in PvP, 120 s cooldown, no recast while active. Warrior
  defense ultimate = reflects 100% of incoming damage for 5 s, capped per hit
  (a share of the Warrior's max HP), 50% in PvP. Execute = instant only on
  normal creatures; bosses and players take bonus damage instead. All numbers
  in Config.
- **Q3 Mage ultimate:** scales with **INT** (D-90 magic damage).
- **Q4 Passives:** a new Passive skill type in the tree, **2 passive slots**;
  the 6 + 1 skill bar is unchanged. Passives grant timed, capped buffs (for
  example "on a crit: +15% STR for 6 s, 20 s internal cooldown").

## 6. Progress

**Stage D (class skills), first pass, done 2026-10-26** (creator asked for
classes first):
- New effects: `Reflect`, `Immune`, `Extend`; Dash `toward` (charge);
  Damage `hpPct` and `attribute` / `perPointPct`; combo `execute`.
  Server: `CombatService` (Immune / Reflect in `applyDamage`, `Execute`),
  `SkillService` (Extender registry, attribute and HP scaling, charge hit).
  Pure rules in `SkillRules.reflected / boostedCoefficient / extendedRadius`
  (tested). Config `Skills.*` (schema-checked, admin-editable).
- Warrior attack: Cleaving Strike charges in; Execution and Blade Storm
  finish creatures; Blade Storm / Earthsplitter scale with STR and max HP;
  Sunder is the Extender.
- Warrior defense: Sweeping Blow corrupts (+25% damage taken); Steadfast is
  the Extender; Unbreakable reflects 100% for 5 s (capped, half in PvP).
- Archer: Ricochet is the Extender; Heartseeker (execute), Tempest Volley,
  Arrow Rain scale with AGI.
- Mage: Combustion is the Extender; Meteor, Blizzard, Thunderstorm, Arcane
  Nova scale with INT.
- Healer: Penance is the Extender (re-pulses heals too); Aegis of Dawn gives
  8 s immunity (60% cut in PvP), 120 s cooldown, can't be chained.
- Client: charge toward the target, "EXTENDED" pulse, IMMUNE / REFLECT
  chips, glow and numbers.
- **Fixes from the creator's test (2026-10-26):** putting a skill on the bar
  sent only the first 3 regular slots (a leftover from the old 3 + 1 bar), so
  slots 4-6 were lost and refilled in tree order; it now sends all 6. **One
  ultimate per branch:** only the tier-6 capstone is a Special (shown as
  ULTIMATE); the tier-3 skills (Blade Flurry, ...) are regular skills now
  (rank 5, any of the 6 slots). Saved bars with a tier-3 skill in the
  ultimate slot are repaired on load.

**Stage A (skill tree screen), done 2026-10-26, awaiting test:**
`Definitions/ClassThemes` (tested: colours, contrast, a role per branch) and
`UI/ClassTheme` tint the panel, branch cards, links, bar and detail pane in
the class colours; branch role labels (Warrior "ATTACK BUILD" / "DEFENSE
BUILD", ...; the column header grew to 34 px); the ultimate node has a round
frame, a spinning gold / class glow and a ⭐ badge; learnable nodes and the
link to them pulse; nodes grow on hover / selection; learning bursts with a
chime; the panel springs open; the detail pane has chips (ULTIMATE /
REGULAR, Physical / Magic / Healing / Protection / Support, cooldown,
Focus, range, EXTENDER).

**Faces + stages B/C first pass, 2026-10-26, awaiting test** (creator: "facial
expression animation is lacking, and the animation effect of the skills and
combo"):
- **Anime faces move:** `FaceExpressions.animePose` (tested) turns the
  existing expression weights (Pain, Effort, Happy, Focused, Defeated,
  blinking) into a pose of the Part-built face; `ExpressionController`
  squashes the eye meshes, drops the lash lines, lifts / tilts the brows and
  opens / widens the mouth through the parts' weld offsets and sizes, on
  each client only; far faces go back to neutral.
- **Weapon trails** (`Effects/WeaponTrail`): a glow streak on the weapon
  hand for melee swings and weapon skills (none for bows).
- **Ultimate cinematic** (`Effects/UltimateFx`): rune circle, light pillar
  and flash for everyone; for the caster a name banner in the class colour,
  edge flash, camera zoom-punch and shake (under 1.3 s).
- **Combo counter** (`UI/ComboCounter`, `Logic/HitStreak` tested):
  "12 HITS · GREAT" with a pop per hit, tiers COMBO / GREAT / AMAZING /
  LEGENDARY, fades 2.5 s after the last hit.
- **Class hit feel:** hit-stop and shake scale per class (Warrior 1.35,
  Mage 1.1, Healer 0.85, Archer 0.7); golden starburst on crits.
