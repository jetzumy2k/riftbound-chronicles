# CLAUDE.md — ANGELS VS DEVILS: RIFTBOUND CHRONICLES

## 1. Project Mission

Build a production-quality Roblox fantasy RPG tentatively titled:

**Riftbound Chronicles: Angels vs Devils**

The experience combines:
- Player leveling from Level 0 to Level 30.
- Story-driven progression and quests.
- Dungeon PvE.
- Race-vs-race PvP.
- Three job types: Healer, Warrior, Archer/Long-Range.
- 3 regular skills + 1 special skill equipped at a time.
- Randomized gear attributes.
- Enhancement Stones and +10 equipment enhancement.
- Secure Admin/Moderator panel.
- Scheduled/manual live events.
- Mobile-first UI.
- Human-like character movement, combat animations, facial expressions and weapon handling.
- Realistic-looking but Roblox-appropriate terrain and creature design.
- Non-graphic defeat: defeated players are returned to their race's safe zone.

### Critical scope rule

Do NOT build the whole game in one pass.

Use `docs/PHASE_PROMPTS.md` and execute exactly one phase at a time. Every phase must compile/run, be reviewed, and pass its acceptance criteria before starting the next phase.

---

# 2. Platform/Safety Target

The design target is **players age 9+**, so content should be designed to fit Roblox's Minimal/Mild direction whenever possible.

Important current Roblox requirements:
- Public experiences must have an accurately completed Maturity & Compliance Questionnaire.
- Roblox uses maturity/content descriptors to determine audience access.
- Minimal/Mild experiences are eligible for Roblox Select (ages 9–15).
- Violence must be disclosed in the questionnaire if present.
- Realistic/excessive violence or blood can change the applicable maturity classification.
- Roblox Community Standards and Terms of Use apply to games, assets, avatars and other uploaded content.
- Use Roblox's official safety/moderation systems.
- Use TextChatService/filtering for player-generated text.
- If AI-generated content is ever exposed to players, review Roblox's current AI and disclosure requirements.

Sources to re-check before release:
- Roblox Creator safety documentation.
- Content Maturity & Compliance documentation.
- Roblox Community Standards.
- Roblox Kids and Select requirements.
- Creator Dashboard publishing/configuration requirements.

Do not claim that this project is "legally certified." The project is designed for platform compliance; final compliance remains the creator's responsibility.

---

# 3. Game Concept

## 3.1 Fictional World

The world is split between two fictional fantasy races:

### Angels
A celestial fantasy race with:
- Customizable fantasy faces.
- Bright/ethereal architecture.
- Aerial/celestial visual language.
- Unique starting area and safe zone.

### Devils
A dark fantasy race with:
- Customizable fantasy faces.
- Volcanic/obsidian architecture.
- Infernal/fantasy visual language.
- Unique starting area and safe zone.

These are fictional game factions. Do not turn the game into real-world religious instruction, worship, demonology, political propaganda, or attacks against real-world religions/groups.

---

# 4. Player Progression

Starting level: **0**

Maximum level: **30**

Primary leveling activity: **Dungeons**

Secondary progression:
- Story quests.
- Gear.
- Enhancement.
- PvP.
- Titles/cosmetics.
- PVP kill counts
- PVP title based from kill counts
- Events.

EXP, level calculations, rewards and progression are always server-authoritative.

---

# 5. Character Base Stats

At Level 0:

| Stat | Value |
|---|---:|
| HP | 200 |
| Base Defense | 50 |
| Base Damage/Attack | 100 |
| Base Crit Damage | 0.05% |
| HP Regeneration | 0.02% |

Per level:

| Stat | Increase |
|---|---:|
| HP | +20% |
| Base Damage/Attack | +10% |
| Base Defense | +8% |
| Base Crit Damage | +0.05 percentage points |
| HP Regeneration | +0.02 percentage points |

## Required formula decision

Unless balancing review approves another approach:
- HP: multiplicative growth.
- Attack: multiplicative growth.
- Defense: multiplicative growth.
- Crit Damage: additive percentage-point increase.
- HP Regeneration: additive percentage-point increase.

Example conceptual formulas:

`HP(level) = 200 * (1.20 ^ level)`

`Attack(level) = 100 * (1.10 ^ level)`

`Defense(level) = 50 * (1.08 ^ level)`

`CritDamage(level) = 0.05% + (0.05% * level)`

`HPRegen(level) = 0.02% + (0.02% * level)`

Claude must document and test the exact implementation. Do not silently change these rules.

---

# 6. Jobs

Each player chooses one job per character.

## 6.1 Healer

Identity:
- Healing.
- Protection.
- Support.
- Controlled attack.

Allowed skill categories:
- Heal.
- Shield.
- Cleanse/support.
- Holy/arcane-style attack.
- Area support.

Not allowed:
- Pure warrior-only defense mechanics unless designed as support.
- Archer-only precision systems.

## 6.2 Warrior

Identity:
- Melee damage.
- Defense.
- Damage mitigation.
- Frontline control.

Allowed skill categories:
- Guard.
- Shield.
- Defense buff.
- Melee attack.
- Area melee attack.
- Taunt/control.

## 6.3 Archer / Long-Range

Identity:
- Ranged damage.
- Precision.
- Mobility.
- Tactical control.

Allowed skill categories:
- Ranged attack.
- Precision/crit.
- Mobility.
- Mark/debuff.
- Ranged area attack.

Every equipped skill must be validated against the player's job on the server.

---

# 7. Skill Loadout

Maximum equipped skills:
- 3 regular skills.
- 1 special skill.

The player may own more skills, but only the allowed loadout can be active.

Each skill should have:
- Unique ID.
- Name.
- Job restriction.
- Type.
- Range.
- Cooldown.
- Resource cost if applicable.
- Damage/heal formula.
- Status/effect.
- Animation.
- VFX.
- SFX.
- Server validation rules.

No client can set its own:
- Damage.
- Cooldown completion.
- Target validity.
- Range.
- Resource cost.
- Skill ownership.

---

# 8. Gear and Weapons

Equipment uses randomized additional attributes appropriate to its intended role.

Example attribute pools:

### Weapons
- Attack.
- Crit Damage.
- Crit Chance.
- Skill Power.
- Job-specific modifiers.

### Warrior Gear
- HP.
- Defense.
- Damage mitigation.
- Melee Attack.
- HP Regen.

### Healer Gear
- HP.
- Defense.
- Healing Power.
- Support Power.
- Resource efficiency.
- Cooldown reduction where balanced.

### Archer Gear
- Attack.
- Crit Chance.
- Crit Damage.
- Ranged Skill Power.
- Mobility/precision modifiers.

Random attributes must:
- Be rolled by the server.
- Come from an allowed pool.
- Respect item level/rarity.
- Never create impossible combinations unless intentionally defined.
- Be saved with the item instance.

---

# 9. Rarity

Suggested rarity hierarchy:

1. Common/Standard
2. Uncommon
3. Rare
4. Legendary
5. Mythical

The exact names can be finalized during Phase 3.

---

# 10. Enhancement System

Enhancement Stones upgrade weapons and gear.

Maximum enhancement:
**+10**

Each successful enhancement:
- Weapon Attack: +20.
- Crit Damage: +2.5%.

For defensive gear, the project must define a corresponding class-appropriate defensive benefit instead of incorrectly applying attack-only stats to armor.

Recommended defensive enhancement:
- Armor Defense +8 per successful enhancement.
- Optional secondary defensive scaling can be configured later.

Enhancement:
- Must be server-authoritative.
- Cannot exceed +10.
- Must atomically consume stones.
- Must be safe against disconnects.
- Must not duplicate equipment or stones.
- Must not be designed as a gambling mechanic.

If paid randomized items are ever introduced, stop and review Roblox's current policy requirements before implementation.

---

# 11. Dungeon System

Dungeons are the primary leveling environment.

Each dungeon should support:
- Entry requirement.
- Party/session.
- Spawn points.
- Mob groups.
- Boss.
- Objective.
- Completion state.
- Reward state.
- Reset.
- Player defeat/rejoin handling.

Dungeons should have:
- Normal enemies.
- Elite enemies where appropriate.
- Boss encounters.
- Environmental storytelling.
- Job-relevant mechanics.

---

# 12. Dungeon Drop Rates

## Boss

Default:
- 20% Legendary weapon/gear.
- 80% Rare weapon/gear.

## Regular Mob

The original request contained:
"30% rare / 70% rare."

This is interpreted as:

- 30% Rare weapon/gear.
- 70% Standard/Uncommon weapon/gear.

This interpretation must be documented in the configuration.

All drop rates:
- Are server-side.
- Must total 100% where applicable.
- Can be changed by authorized Admins.
- Must be validated.
- Must be audit logged.

---

# 13. PvP Zones

There are two PvP portals available from each race's appropriate area.

## Portal 1 — Desert Rift

Environment:
- Large desert.
- Rock formations.
- Dunes.
- Oasis in the center.
- Water, vegetation and structures around oasis.

Central oasis:
- PvP Safe Zone.
- No player damage.
- Return portal to the player's leveling map.
- Anti-spawn-camping protection.

## Portal 2 — Jungle Rift

Environment:
- Dense tropical jungle.
- Large waterfall.
- River.
- Bridges/rock formations.
- Central waterfall/river safe zone.

Central safe zone:
- No player damage.
- Return portal to leveling map.
- Anti-spawn-camping protection.

---

# 14. PvP Rules

PvP is non-graphic.

When a player reaches 0 HP:
1. Server determines defeat.
2. No blood.
3. No dismemberment.
4. No realistic injury.
5. Use a clean stylized defeat animation/VFX.
6. Teleport defeated player to their own race's safe zone.
7. Restore combat state appropriately.
8. Prevent immediate re-engagement until the safe-zone protection ends.

Default:
- No item loss.
- No gear destruction.
- No XP loss.

PvP must not permit:
- Safe-zone damage.
- Spawn camping.
- Teleport abuse.
- Arbitrary client damage.
- Fake death packets.

---

# 15. PvP Drop Rates

## PvP Boss

Default:
- 20% Mythical weapon/gear.
- 80% Rare weapon/gear.

## PvP Regular Mobs

Default:
- 30% Perfect Enhancement Stone.
- 70% Enhancement Stone.

All are configurable by authorized Admins.

---

# 16. Story

Working title:

**Riftbound Chronicles: The War of the Twin Realms**

## Premise

A mysterious dimensional rupture known as the Rift appears between two fictional realms.

Angels and Devils each believe the other faction caused it.

The player begins at Level 0 as a new recruit.

As the player completes dungeons and quests, they discover that both sides have been manipulated by an ancient force known as the **Nullborn**.

The story should evolve from faction rivalry into a larger mystery:
- The Rift is unstable.
- Dungeon creatures are being corrupted.
- Someone is feeding false information to both races.
- PvP conflict is being exploited.
- The Nullborn seeks to merge both realms into a lifeless dimension.

The player eventually discovers that neither race is the true enemy.

---

# 17. Initial Quest Arc

## Quest 1 — First Spark
Objectives:
- Complete training.
- Defeat 5 training creatures.

Rewards:
- EXP.
- Starter weapon.
- Basic healing consumables.
- Dungeon access.

## Quest 2 — Into the Rift
Objectives:
- Clear first dungeon.
- Defeat dungeon guardian.

Rewards:
- EXP.
- Rare gear chance.
- Enhancement Stone.
- Enhancement system unlock.

## Quest 3 — Echoes of the Other Realm
Objectives:
- Discover 3 Rift fragments.

Rewards:
- EXP.
- Class-specific accessory.
- Story unlock.

## Quest 4 — The Broken Gate
Objectives:
- Defeat dungeon boss.
- Recover Gate Core.

Rewards:
- EXP.
- Rare weapon/gear.
- Portal access.

## Quest 5 — Two Paths, One Rift
Objectives:
- Visit faction capital.
- Inspect both PvP portals.

Rewards:
- EXP.
- PvP consumable.
- Cosmetic title.

## Quest 6 — Trial of the Desert
Objectives:
- Enter Desert Rift.
- Defeat PvE creatures.
- Return safely.

Rewards:
- EXP.
- Enhancement Stones.
- Desert cosmetic.

## Quest 7 — Trial of the Jungle
Objectives:
- Enter Jungle Rift.
- Defeat PvE creatures.
- Return safely.

Rewards:
- EXP.
- Enhancement Stones.
- Jungle cosmetic.

## Quest 8 — Rival Encounter
Objectives:
- Participate in a PvP encounter/event.
- No kill requirement.

Rewards:
- EXP.
- PvP currency.
- Job cosmetic.

## Quest 9 — The False War
Objectives:
- Investigate clues proving both factions are being manipulated.

Rewards:
- EXP.
- Rare accessory.
- Story title.

## Quest 10 — Guardian of the Rift
Objectives:
- Defeat major guardian.

Rewards:
- EXP.
- Legendary reward chance.
- Special-skill unlock token.

## Level 30 — The Nullborn Gate
Objectives:
- Complete final dungeon.
- Defeat final guardian.
- Complete final faction story.

Rewards:
- Endgame Legendary/Mythical reward according to configured table.
- Final title.
- Cosmetic aura.
- Repeatable endgame access.

---

# 18. Creature Design

Mobs and bosses should be visually impressive and creature-like, while remaining suitable for the target audience.

Use:
- High-quality humanoid/fantasy animation.
- Natural creature locomotion.
- Distinct silhouettes.
- Facial/emotional expressions where appropriate.
- Readable attack telegraphs.
- Stylized impact effects.

Avoid:
- Gore.
- Exposed organs.
- Dismemberment.
- Graphic wounds.
- Torture imagery.
- Excessively realistic death.

"Real-like creature" means believable fantasy creature design, not graphic realism.

Suggested dungeon creatures:
- Rift Wolf.
- Crystal Beetle.
- Stoneback Guardian.
- Thorncrawler.
- Ember Hound.
- Mist Serpent.
- Rift Knight.
- Ancient Guardian.

Suggested bosses:
- The Shattered Warden.
- Oasis Colossus.
- Jungle Hydra.
- Riftbound Knight.
- Nullborn Herald.

---

# 19. Human-Like Character Design

Characters should have:
- Standard Roblox-compatible humanoid movement.
- Natural walking.
- Running.
- Jumping.
- Dodging where appropriate.
- Weapon holding.
- Attack animations.
- Hit reactions.
- Defeat animation.
- Facial expression states.
- Idle animations.

Animation quality requirements:
- Avoid robotic snapping.
- Blend locomotion smoothly.
- Prevent attack animation from overriding essential movement incorrectly.
- Keep controls responsive.
- Support R15 where practical.
- Test animations on mobile and desktop.

---

# 20. Terrain / World Art Direction

Terrain should be believable and detailed:
- Natural slopes.
- Rivers.
- Waterfalls.
- Sand dunes.
- Rock formations.
- Vegetation.
- Lighting.
- Weather/atmosphere.
- Faction architecture.

However, maintain Roblox performance:
- Avoid excessive high-poly assets.
- Use streaming appropriately.
- Reuse meshes/materials intelligently.
- Limit particle counts.
- Test on low-end/mobile devices.

---

# 21. Admin / Moderator System

Roles:
- Owner.
- Admin.
- Moderator.

## Owner
Full control.

## Admin
Can manage:
- Items.
- Gear.
- Weapons.
- Bosses.
- Mobs.
- Quests.
- Drop rates.
- Enhancement configuration.
- Events.
- Player moderation.
- Game configuration.

## Moderator
Can manage:
- Player reports.
- Kick/temporary moderation actions where permitted.
- Player support tools.
- Event activation only if explicitly granted.
- View selected operational information.

Moderator must NOT automatically receive:
- Economy controls.
- Drop-rate controls.
- Item creation.
- Admin-role assignment.
- Data editing.

Every action:
- Server-side permission check.
- Argument validation.
- Audit log.

Use Roblox's official moderation capabilities where applicable.

---

# 22. Moderator Compensation

If compensation is implemented:
- Prefer cosmetic/title/store rewards.
- Do not make moderator status pay-to-win.
- Do not hide compensation logic in client code.
- Keep the system configurable and auditable.
- Follow Roblox monetization/platform requirements.

---

# 23. Admin Event System

Admins/authorized moderators can trigger configured events.

The panel must include at least these 25 event templates:

1. Double EXP Weekend
2. Double Dungeon Drop Rate
3. Rare Gear Rush
4. Legendary Hunt
5. Mythical Boss Invasion
6. Enhancement Stone Rush
7. Perfect Stone Hunt
8. Desert Storm
9. Jungle Flood
10. Rift Beast Invasion
11. Boss Frenzy
12. Elite Mob Swarm
13. Treasure Hunt
14. Hidden Chest Hunt
15. Race Challenge
16. Angel Defense Event
17. Devil Defense Event
18. Cross-Race Tournament
19. PvP Arena Rush
20. No-Cooldown Training Event
21. Healing Festival
22. Archer Precision Challenge
23. Warrior Survival Challenge
24. Class Mastery Event
25. Nullborn World Boss

Additional possible events:
26. Triple Quest EXP
27. Dungeon Marathon
28. Rare Attribute Weekend
29. Cosmetic Parade
30. Rift Eclipse

Every event definition should support, where relevant:
- Start time.
- End time/duration.
- Eligible players.
- Map/zone.
- Multipliers.
- Spawn configuration.
- Reward configuration.
- Announcement.
- Cooldown.
- Audit logging.

Events must be server authoritative.

---

# 24. Recommended Architecture

## Server Services

- PlayerDataService
- ProfileServiceAdapter / persistence abstraction
- StatsService
- LevelService
- RaceService
- JobService
- SkillService
- CombatService
- InventoryService
- EquipmentService
- ItemService
- LootService
- EnhancementService
- QuestService
- DungeonService
- MobService
- BossService
- PvPService
- SafeZoneService
- TeleportService
- EventService
- AdminService
- ModerationService
- AuditLogService
- RateLimitService
- ConfigurationService
- AntiExploitService

## Client Controllers

- UIController
- InputController
- CombatController
- SkillBarController
- InventoryController
- EquipmentController
- QuestController
- CharacterController
- CustomizationController
- TeleportController
- NotificationController
- EventController

## Shared

- Types
- Constants
- Enums
- ItemDefinitions
- SkillDefinitions
- JobDefinitions
- QuestDefinitions
- EnemyDefinitions
- BossDefinitions
- EventDefinitions
- ConfigurationSchema
- ValidationHelpers

---

# 25. Security Requirements

The server is authoritative for:
- XP.
- Level.
- Stats.
- Damage.
- Healing.
- Critical hits.
- Loot.
- Item creation.
- Enhancement.
- Inventory.
- Equipment.
- Quest progress.
- Quest rewards.
- PvP.
- Teleports.
- Events.
- Admin permissions.

Clients may request actions, but cannot dictate outcomes.

Every RemoteEvent/RemoteFunction:
- Has schema validation.
- Has rate limiting.
- Has player-state validation.
- Has permission checks where relevant.
- Rejects unexpected arguments.
- Logs security-relevant failures.

---

# 26. Data Integrity

Use a versioned player profile.

Recommended profile:
```text
Profile
├── SchemaVersion
├── Race
├── Job
├── Level
├── Experience
├── BaseProgression
├── EquippedSkills
├── Inventory
├── Equipment
├── Enhancement
├── QuestState
├── StoryFlags
├── Cosmetics
├── Titles
├── PvPStats
├── EventProgress
└── Settings
```

Requirements:
- Validate on load.
- Repair missing fields.
- Migrate old schema versions.
- Prevent duplication.
- Handle server shutdown.
- Handle reconnect.
- Avoid excessive DataStore writes.
- Never store arbitrary client payloads.

---

# 27. Performance

Target:
- Mobile first.
- Stable multiplayer.
- Streaming-enabled world where appropriate.
- Controlled NPC AI.
- Efficient raycasts.
- Controlled particles.
- Limited remote frequency.
- Batched/non-critical operations where possible.

Never sacrifice server authority merely to gain performance.

---

# 28. UI/UX

Mobile is a first-class platform.

Requirements:
- Responsive layouts.
- Safe-area awareness.
- Readable text.
- Compact panels.
- Touch-friendly controls.
- No overlapping buttons.
- No text clipping.
- Skill bar accessible during combat.
- Inventory easy to browse.
- Quest objectives easy to understand.
- Admin UI hidden from unauthorized players.
- Color should not be the only indication of state.

---

# 29. Testing

Each phase must test:
- Studio Play.
- Multiplayer test.
- Client/server separation.
- Mobile emulation.
- Reconnect.
- Death/defeat.
- Teleports.
- Save/load.
- Invalid remote calls.
- Reward duplication.
- Admin permissions.

Critical defects block the next phase.

---

# 30. Definition of Done

A feature is done only when:
- It works in multiplayer.
- It is server authoritative where required.
- It has validation.
- It has error handling.
- It has reasonable performance.
- It is mobile usable.
- It does not create obvious exploit paths.
- It does not duplicate rewards/items.
- It survives reconnects where applicable.
- It is documented.
- It passes the relevant review persona.

---

# 31. Required Review Personas

At every major milestone, review from:

### Senior Developer
Check:
- Architecture.
- Maintainability.
- Luau quality.
- Performance.
- Security.
- Data integrity.

### Platform/Community Compliance Reviewer
Check:
- Community Standards.
- Content Maturity.
- Safety.
- Moderation.
- User-generated content.
- Monetization.
- Age appropriateness.

### Game Designer
Check:
- Progression.
- Class balance.
- Dungeon pacing.
- PvP fairness.
- Loot economy.
- Retention.

### Gamer
Check:
- Fun.
- Clarity.
- Responsiveness.
- First-time experience.
- Mobile experience.
- Friction.
- Repetition.
- Excitement.

Never claim legal certification. Identify anything requiring human/platform/legal review.

---

# 32. Required Agent Behavior

When asked to implement a phase:
1. Inspect current repository state.
2. Read relevant skills.
3. Read relevant architecture documents.
4. State the implementation goal.
5. List files to create/change.
6. Implement only the current phase.
7. Test.
8. Review security.
9. Review mobile UX where applicable.
10. Report:
   - Changed files.
   - Tests.
   - Results.
   - Known issues.
   - Security concerns.
   - Next phase.

Do not silently implement future phases.

