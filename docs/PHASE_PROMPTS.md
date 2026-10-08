# PHASE_PROMPTS.md

## Operating rule

Run exactly one phase per Claude Code task.

At the end of every phase:
- Run tests.
- Fix critical defects.
- Review security.
- Review Roblox safety.
- Report changed files.
- Stop.

Do not skip phases because a later feature looks easier.

---

# Phase 0 — Repository Audit

Prompt:

Act as the Lead Senior Roblox/Luau Architect.

Inspect the complete repository.

Do not implement gameplay.

Produce:
- Existing architecture map.
- Existing systems.
- Folder structure.
- Dependencies.
- Server/client/shared boundaries.
- Remote map.
- Data model.
- Security threat model.
- Performance risks.
- Technical debt.
- Recommended architecture.

Create/update:
- docs/ARCHITECTURE.md
- docs/DATA_MODEL.md
- docs/SECURITY_MODEL.md

Acceptance:
- No gameplay implementation.
- Clear architecture.
- Clear authoritative server boundaries.

---

# Phase 1 — Foundation

Implement only:
- Folder/module architecture.
- Shared constants.
- Enums.
- Typed definitions.
- ConfigurationService.
- RateLimitService skeleton.
- Logging.
- Error handling.
- Remote folder structure.

Do not implement combat, quests, inventory or PvP.

Acceptance:
- Game starts without errors.
- Server/client initialization works.
- No secrets replicated.

---

# Phase 2 — Player Data and Level 0–30

Implement:
- Versioned player profile.
- Load/save.
- Migration.
- Data validation.
- XP.
- Level 0–30.
- Base stats.
- Level calculations.

Use:
HP 200
Defense 50
Attack 100
Crit Damage 0.05%
HP Regen 0.02%

Per level:
HP +20% multiplicative.
Attack +10% multiplicative.
Defense +8% multiplicative.
Crit Damage +0.05 percentage points.
HP Regen +0.02 percentage points.

Acceptance:
- Client cannot grant XP.
- Level cannot exceed 30.
- Reconnect preserves progress.
- Invalid data is safely repaired.

---

# Phase 3 — Race System

Implement:
- Angel.
- Devil.
- First-time race selection.
- Race persistence.
- Race spawn.
- Race safe zone.
- Face customization using controlled presets.

Keep races fictional fantasy factions.

Acceptance:
- Race is server authoritative.
- No arbitrary client asset injection.
- Spawn is deterministic.

---

# Phase 4 — Job System

Implement:
- Healer.
- Warrior.
- Archer/Long-range.

Create job definitions and server validation.

Acceptance:
- One active job.
- Compatible skill categories enforced.
- Job persists.

---

# Phase 5 — Skill System

Implement:
- 3 regular slots.
- 1 special slot.
- Skill definitions.
- Job restrictions.
- Cooldowns.
- Range.
- Resource cost.
- Server combat requests.
- Rate limits.

Create initial skills:
Healer: 3 regular + 1 special.
Warrior: 3 regular + 1 special.
Archer: 3 regular + 1 special.

Use stylized, non-graphic effects.

Acceptance:
- Client cannot control damage/cooldowns.
- Wrong-job skills rejected.
- Mobile combat works.

---

# Phase 6 — Combat Foundation

Implement:
- Damage.
- Healing.
- Defense.
- Crit.
- HP.
- Regeneration.
- Target validation.
- Combat states.
- Hit reactions.
- Non-graphic defeat state.

Acceptance:
- Server computes all outcomes.
- No arbitrary damage remote.
- No client-created death.

---

# Phase 7 — Inventory and Gear

Implement:
- Item instances.
- Inventory.
- Equipment slots.
- Equip/unequip.
- Rarity.
- Random bonus attributes.
- Job-appropriate attribute pools.

Acceptance:
- Server rolls item attributes.
- Items persist.
- Invalid items rejected.

---

# Phase 8 — Enhancement

Implement:
- Enhancement Stones.
- Perfect Enhancement Stones.
- +0 to +10.
- Weapon +20 Attack per successful enhancement.
- +2.5% Crit Damage per successful enhancement.
- Armor defensive enhancement rule.
- Atomic stone consumption.
- Disconnect-safe processing.

Acceptance:
- Cannot exceed +10.
- No item/stone duplication.
- All results server authoritative.

---

# Phase 9 — Dungeon Framework

Implement:
- Dungeon entry.
- Sessions.
- Mobs.
- Bosses.
- Objectives.
- Completion.
- Reset.
- Reward state.

Do not finalize all story content yet.

Acceptance:
- Multiple players supported.
- No reward duplication.
- Bosses reset correctly.

---

# Phase 10 — Dungeon Loot

Boss:
20% Legendary / 80% Rare.

Regular:
30% Rare / 70% Standard-Uncommon.

Implement configurable loot tables.

Acceptance:
- Rates validated.
- Server rolls.
- Rewards granted once.
- Audit logs exist.

---

# Phase 11 — Story and Quest System

Implement:
- Quest definitions.
- Objectives.
- Progress.
- Prerequisites.
- Dialogue.
- Story flags.
- EXP rewards.
- Item rewards.
- Idempotent completion.

Implement:
1. First Spark.
2. Into the Rift.
3. Echoes of the Other Realm.
4. The Broken Gate.
5. Two Paths, One Rift.
6. Trial of the Desert.
7. Trial of the Jungle.
8. Rival Encounter.
9. The False War.
10. Guardian of the Rift.
11. The Nullborn Gate.

Acceptance:
- Client cannot forge progress.
- Rewards cannot be claimed twice.
- Mobile quest UI is readable.

---

# Phase 12 — Desert PvP Zone

Implement:
- Desert.
- Central oasis.
- Safe zone.
- Return portal.
- PvP boundary.
- Race PvP.
- Non-graphic defeat.
- Return to own race safe zone.
- Spawn protection.

Acceptance:
- Safe zone cannot be damaged.
- Defeated player reliably returns home.
- No item loss.
- No spawn camping.

---

# Phase 13 — Jungle PvP Zone

Implement:
- Jungle.
- Waterfall/river.
- Safe zone.
- Return portal.
- Same PvP rules as Desert.

Acceptance:
- Same security and defeat guarantees.

---

# Phase 14 — PvP Loot

PvP Boss:
20% Mythical / 80% Rare.

PvP regular mobs:
30% Perfect Enhancement Stone / 70% Enhancement Stone.

Implement server-authoritative configurable loot.

Acceptance:
- No client-controlled drops.
- Rates validated.
- Reward duplication impossible.

---

# Phase 15 — Human-like Animation Pass

Implement:
- Smooth R15 locomotion.
- Walking.
- Running.
- Jumping.
- Weapon holding.
- Attack animations.
- Hit reactions.
- Defeat animation.
- Facial expression states.
- Skill animation blending.

Avoid:
- Graphic injuries.
- Blood.
- Dismemberment.

Acceptance:
- Animations are responsive.
- No major snapping.
- Mobile and desktop tested.

---

# Phase 16 — Terrain and Creature Art Pass

Create/organize:
- Angel capital.
- Devil capital.
- Dungeon environments.
- Desert.
- Oasis.
- Jungle.
- Waterfall.
- Creature visual language.
- Boss silhouettes.

"Realistic" means believable fantasy visuals while maintaining Roblox performance and age appropriateness.

Acceptance:
- Terrain is visually strong.
- Streaming/performance considered.
- No graphic content.

---

# Phase 17 — Admin/Moderator Panel

Implement:
- Owner.
- Admin.
- Moderator.
- UserId-based roles.
- Permission matrix.
- Player search.
- Player inspection.
- Item management.
- Boss management.
- Quest management.
- Drop-rate configuration.
- Enhancement configuration.
- Event management.
- Audit logs.

Acceptance:
- Unauthorized players cannot invoke admin actions.
- Moderator cannot perform restricted admin operations.
- Every sensitive action is logged.

---

# Phase 18 — 25+ Event System

Implement event definitions for at least:
1 Double EXP Weekend
2 Double Dungeon Drop Rate
3 Rare Gear Rush
4 Legendary Hunt
5 Mythical Boss Invasion
6 Enhancement Stone Rush
7 Perfect Stone Hunt
8 Desert Storm
9 Jungle Flood
10 Rift Beast Invasion
11 Boss Frenzy
12 Elite Mob Swarm
13 Treasure Hunt
14 Hidden Chest Hunt
15 Race Challenge
16 Angel Defense
17 Devil Defense
18 Cross-Race Tournament
19 PvP Arena Rush
20 No-Cooldown Training
21 Healing Festival
22 Archer Precision Challenge
23 Warrior Survival Challenge
24 Class Mastery
25 Nullborn World Boss
26 Triple Quest EXP
27 Dungeon Marathon
28 Rare Attribute Weekend
29 Cosmetic Parade
30 Rift Eclipse

Each event should support configurable:
- Duration.
- Eligibility.
- Map.
- Multipliers.
- Spawns.
- Rewards.
- Announcements.
- Cooldown.
- Audit logging.

---

# Phase 19 — Mobile UI/UX

Perform a complete mobile-first pass.

Fix:
- Oversized text.
- Overlapping panels.
- Clipped labels.
- Tiny buttons.
- Skill bar placement.
- Inventory layout.
- Quest layout.
- Notifications.
- Safe areas.

Acceptance:
- Core gameplay works on mobile.
- No essential control is hidden/off-screen.

---

# Phase 20 — Balance Review

Act as Game Designer.

Review:
- Level 0–30 curve.
- Class power.
- Skill cooldowns.
- Dungeon difficulty.
- Boss difficulty.
- Gear scaling.
- Enhancement.
- PvP fairness.
- Drop economy.
- Event rewards.

First produce a balance report.
Then implement only approved changes.

---

# Phase 21 — Security and Exploit Audit

Act as Roblox security engineer.

Attack the design conceptually and through test cases.

Try:
- Fake XP.
- Fake damage.
- Fake healing.
- Fake item.
- Fake enhancement.
- Duplicate rewards.
- Fake quest completion.
- Teleport bypass.
- Safe-zone damage.
- Admin remote abuse.
- Moderator privilege escalation.
- Event configuration abuse.

Fix critical/high issues.

---

# Phase 22 — Roblox Safety / Compliance Review

Review:
- Content maturity.
- Violence descriptors.
- Blood/gore.
- Religious/political implications.
- Avatar customization.
- Player-generated content.
- Chat filtering.
- Moderation.
- Monetization.
- Age appropriateness.

Goal:
Design for Minimal/Mild where reasonably possible.

Do not claim certification.

Produce:
- Risk.
- Relevant Roblox policy area.
- Current state.
- Required change.
- Severity.

Fix actionable issues.

---

# Phase 23 — Performance / Multiplayer QA

Review:
- NPC AI.
- Remote frequency.
- Memory.
- Instance count.
- Particles.
- Terrain.
- Streaming.
- DataStore usage.
- Concurrent dungeons.
- PvP concurrency.
- Mobile performance.

Acceptance:
- Stable multiplayer.
- No obvious server loops/leaks.
- No excessive remote traffic.

---

# Phase 24 — Gamer Review

Act as a veteran Roblox gamer.

Experience:
- New Level 0 onboarding.
- Race choice.
- Job choice.
- First skill.
- First dungeon.
- First loot.
- First enhancement.
- First story reveal.
- First PvP.
- First defeat.
- Return to safe zone.
- Event participation.

Rank issues:
P0 Broken
P1 Serious
P2 Important improvement
P3 Polish

Fix P0/P1 before release.

---

# Phase 25 — Release Candidate

Verify:
- Persistence.
- Progression.
- Dungeons.
- Loot.
- Skills.
- Gear.
- Enhancement.
- PvP.
- Safe zones.
- Teleports.
- Admin.
- Events.
- Mobile UI.
- Performance.
- Safety.

Create:
- docs/RELEASE_CHECKLIST.md
- docs/KNOWN_ISSUES.md
- docs/PLAYER_SUPPORT.md

Do not publish automatically.

---

# Phase 26 — Live Operations

Prepare:
- Feature flags.
- Safe balance configuration.
- Event rotation.
- Audit logs.
- Error monitoring.
- Content update structure.
- New dungeon hooks.
- New boss hooks.
- New race/job hooks.

Avoid unnecessary architecture complexity.
