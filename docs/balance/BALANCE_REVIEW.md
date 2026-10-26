# Balance review (Phase 20, PLAN.md D-95)

Game Designer review, based on `docs/balance/SIMULATION.md` (regenerate it
with `lune run tools/balance/simulate > docs/balance/SIMULATION.md`). The
simulation uses the game's own formula modules, so it shows what the
server computes. It is a model: walking, dodging and skill choice add noise,
and real playtests must confirm it.

**Creator decisions 2026-10-25: applied** (see "Applied" at the end). The CLAUDE.md §5 stat rules (HP x1.20, Attack x1.10, Defense
x1.08 per level, crit and regen) are kept in every option.

## Summary

| # | Finding | Severity | Recommendation |
|---|---|---|---|
| 1 | Levelling is about **50x too fast**: level 30 in under an hour of play, against the planned 20-25 hours (D-18). One clear of floor 3 gives more EXP than the whole curve. | High | Scale creature and dungeon-bonus EXP to **x0.025** (~19 h) or **x0.05** (~9 h if a faster game suits the audience). Quests stay as they are. |
| 2 | **Mall Mythical sets give a 3.8x PvP edge** (4.8x with buffs) over a player in normal drop gear at level 30. | High (fairness) | Creator's decision (D-93). Options: keep; make Mall sets Legendary only; or sell sets at the player's level minus 5. |
| 3 | **Archer armour has no defensive stats** (its attribute pool is Attack / Crit / Skill Power). With fixed or high rolls Archers kill each other in **2-4 s** at any level. | Medium | Give Archer armour **Max HP and Defense** (weight 2 each) and lower Attack / Crit Chance from 3 to 2. |
| 4 | **Creatures barely threaten geared players**: a level-matched creature needs **20-115 hits** to defeat a player in a normal drop kit. | Medium | Raise regular creature damage **x2** (attackScale), elites x1.5: about 15-60 hits. |
| 5 | **Bosses are sized for players with no gear** (BossBalance). A normal drop kit makes them about 15% easier; endgame gear halves them (a duo uses 0.3 of the enrage instead of 0.95). | Low-Medium | Size boss HP for the drop kit (**x1.15**). Endgame being faster is fair reward. |
| 6 | Equal-level PvP without gear lasts **3-13 s** (D-01 Level Power Scale works). With gear it lasts **9-29 s**, and across classes **10-42 s**: Healers are the slowest killers (support role), Archers the most fragile. | OK | Keep D-01 (1.047^L), D-05 (K = 200 + 25 x level) and D-16 (min(own, theirs + 5)). |
| 7 | Enhancement: **12.5 stones per item** on average from +0 to +10 (D-08 rates), never destroyed. About 140 stones for a full set. | OK | Keep. With finding 1 fixed, play time grows and so do stone drops. |
| 8 | Drops (D-06): 12% regular, 35% elite, bosses always (Legendary 20%). | OK | Keep; re-check after finding 1 (longer play = more drops per level). |

## Details

### 1. EXP (D-18)
- The curve is fine: `XPToNext(L) = 100 x 1.18^L`, 79,095 EXP to level 30.
- Creature EXP is the problem. Each creature gives a fixed share of a level at its own level (`EnemyDefinitions.xpAt` scales EXP along the curve): about 25% of a level for a Rift Wolf, about 37% for an Abyssal Knight, around 4 kills per level.
- The tuning table in the simulation gives the hours to level 30 at different multipliers, assuming half the time is spent fighting:

| EXP multiplier | Hours to 30 |
|---|---|
| 1 (now) | 0.5 |
| 0.1 | 4.7 |
| 0.05 | 9.4 |
| 0.025 | about 19 |
| 0.02 | 23.5 |

- Events and buffs still stack on top: Double EXP, Scroll of Insight, the 3x cap.

### 2. Mall sets (D-93)
- A level-30 Warrior wearing the Mall Mythical set (+0) defeats one in a normal Rare +5 / +3 kit in 12 s, and takes 46 s to be defeated.
- That's the same edge as endgame Mythical +10 gear, which takes weeks of play to get.
- This is the pay-to-win trade-off flagged in D-93. The decision stays with the creator.

### 3. Archer armour
- Warrior armour rolls Max HP / Defense / Damage Reduction, Healer armour Max HP / Defense, and Mage armour Max HP / Defense.
- Archer armour rolls only damage stats. As rolls rise, Archers become glass cannons: with average drops they're balanced, with the best rolls they aren't.

### 4. Creature damage
- Regular creatures use `attackScale` about 0.9 and `attackCoefficient` 0.22-0.45 at the player formula's Attack.
- Gear adds Defense and HP far faster than creatures gain damage, so dungeons stop being dangerous once a player has a drop kit.

### 5. Boss HP
- `BossBalance.hpFor` models a player without gear (D-47 targets).
- Sizing it for the drop kit keeps the "solo impossible, duo super hard, party very hard" rule for normally geared players.

## What stays (re-checked)
- **D-01** Level Power Scale 1.047^L
- **D-05** Defense K
- **D-06** drop chances
- **D-08** enhancement rates
- **D-16** PvP level normalisation
- **CLAUDE.md §5** stat growth

## Applied (creator decisions 2026-10-25)

| # | Change | Where | Result in the simulation |
|---|---|---|---|
| 1 | Creature and dungeon-boss EXP x **0.2 x 0.905^creature level** (a level-dependent scale, not a flat x0.025: a flat cut made level 1 take 25 minutes) | `XPTable.creatureScale`, `EnemyDefinitions.xpAt`, DungeonService bonus | Level 30 in **~19 hours**. Level 1 takes ~3 min, level 10 ~10 min, level 20 ~50 min, the last level ~2.5 h. With Insight about 12.5 h, with Double EXP 9.4 h. Quests unchanged (about 16% of the curve). |
| 2 | The Mall sells the **Legendary set only** | `MallDefinitions` | Mall buyer's edge at level 30: **1.7x** (2.2x with buffs), down from 3.8x. |
| 3 | Archer armour rolls **Max HP and Defense** (Attack / Crit Chance weight 3 to 2) | `ItemRules.POOLS.Gear.Archer` | Top-rolled Archers no longer die in 2-4 s; existing items keep their attributes. |
| 4 | Regular creatures hit **x2**, elites **x1.5** (bosses unchanged) | `EnemyDefinitions` | A level-matched creature needs **14-58 hits** to defeat a player in a drop kit (was 20-115). |
| 5 | Bosses sized for a normally geared player (**x1.15**) | `BossBalance.GEAR_FACTOR` | Normally geared groups keep the solo-impossible / duo-super-hard / party-very-hard rule. |
