# PLAN.md — Riftbound Chronicles: Angels vs Devils

Master build plan, written from a review of `CLAUDE.md`, `docs/PHASE_PROMPTS.md`, `docs/README.md` and every skill under `.claude/skills/`.

- **Date:** 2026-10-08
- **Repository state at review:** design documents only. No Luau source, no Rojo project, no place file, no tests. The directory is **not a git repository** yet.
- **How to use this file:** `CLAUDE.md` is the spec. `docs/PHASE_PROMPTS.md` holds the per-phase prompts. This file adds what those two leave open: the decisions that need an owner, fixes to the phase order, the systems no phase covers, a toolchain, and the test and exit gates for every phase. Run **one phase per task**, as before.

---

## 1. Executive Summary

The design is strong on security, safety and server authority. It has the right service split, and running one phase at a time is the right discipline. Before Phase 2 locks in numbers, these problems need fixing:

1. **Balance math in §5 breaks down at high levels.** HP grows 1.20× per level and Attack only 1.10×, so at Level 30 the HP-to-Attack ratio is **13.6× worse** than at Level 0. Fights at the level cap (PvP especially) would last about 50 or more hits. Base Crit Damage of 0.05% does almost nothing. HP Regen has no time unit. There is no Crit Chance stat and no defense-mitigation formula (see §4, D-01 to D-05, and Appendix A).
2. **Some phases depend on later phases.** Skills (Phase 5) need the Combat resolver from Phase 6. Quest 1 needs the training mobs from Phase 9. Quests 6 to 8 need the PvP zones from Phases 12 and 13 (see §6).
3. **About ten required systems have no phase:** currency, consumables, cosmetics, titles, PvP kill titles, parties, skill acquisition, inventory cap and salvage, the player report pipeline, and cross-server config propagation (see §5).
4. **The economy and enhancement rules have gaps.** The spec doesn't say whether a mob drop is guaranteed or only possible. It gives no enhancement success rate, doesn't define what a Perfect Stone does, and has no gear sink (see D-06 to D-09).
5. **Some architecture decisions are missing.** One place or several places? Which persistence library? Where do audit logs live? How do admin changes reach other live servers? `TeleportService` in §24 has the same name as a Roblox engine service (see §3 and D-10 to D-13).

None of this blocks Phase 0. Phase 0 should record the answers to the **Decision Log (§4)**. Decisions marked **[Blocker for Phase N]** must be settled before that phase starts.

---

## 2. Review Findings by Persona (CLAUDE.md §31)

### 2.1 Senior Developer
| # | Finding | Severity | Resolution |
|---|---|---|---|
| SD-1 | Service named `TeleportService` (§24) shadows the engine's `TeleportService`. | Medium | Rename to `TravelService` (zone and place travel). Use the engine's TeleportService only inside it. |
| SD-2 | No single-place vs multi-place decision. It affects persistence (session locks), dungeon instancing, PvP population and testing. | High | D-10 |
| SD-3 | No persistence library chosen. "ProfileServiceAdapter" implies ProfileService, which has been superseded by **ProfileStore** (same author, session locking). | High | D-11 |
| SD-4 | Admin config, drop rates and events must reach **every live server**. Nothing describes how. | High | D-12: DataStore holds the source of truth, MessagingService carries invalidation, and each config change bumps a version number. |
| SD-5 | No audit-log storage or retention design. | Medium | D-13 |
| SD-6 | No toolchain or test runner. Without one, "Each phase must test" can't be enforced. | High | §3.1 |
| SD-7 | Phase 5 needs Phase 6 (combat resolution). | High | §6: run Phase 6 before Phase 5. |
| SD-8 | No trading system is specified. That is good: it removes the biggest duplication vector. | — | Record "no player trading in v1" as an explicit decision (D-14). |

### 2.2 Platform / Community Compliance Reviewer
| # | Finding | Severity | Resolution |
|---|---|---|---|
| PC-1 | The Angels/Devils theme carries religious connotations. | Medium | Art bible rule: no crosses, pentagrams, scripture, real deities, worship or ritual imagery. Use the in-world terms "Celestials/Infernals" in lore text where it helps. Recheck in Phase 22. |
| PC-2 | Player reports with free-text descriptions are user-generated text shown to other users (moderators). | Medium | Use preset report categories. Optional free text goes through `TextService:FilterStringAsync` before display. Also link Roblox's own Report Abuse flow. |
| PC-3 | Paid randomized items and enhancement-with-failure are close to gambling mechanics. | High if monetized | v1 has **no Robux sale** of Enhancement Stones, gear or anything else with a random outcome (D-15). Any future paid random item needs a fresh policy review (odds disclosure, regional restrictions). |
| PC-4 | Moderator compensation in Robux has platform and labor implications. | Medium | Cosmetic and title rewards only (§22). Robux payouts are out of scope for code. |
| PC-5 | Custom character names or titles would be UGC text. | Medium | No custom names. Use Roblox DisplayName. Titles come from a preset list only. |
| PC-6 | "Kill count" language and kill-based titles in a 9+ game. | Low | Player-facing wording uses "Victories" or "Defeats," never "kills." Titles: "Duelist," "Rift Champion" and similar. |
| PC-7 | Violence must be disclosed in the questionnaire. Target is Mild (fantasy, non-graphic). | Info | Phase 22 produces the questionnaire answer sheet for a human to submit. Never claim certification. |

### 2.3 Game Designer
| # | Finding | Severity | Resolution |
|---|---|---|---|
| GD-1 | HP outgrows Attack: L30 time-to-kill is about 13.6× L0's before defense (Appendix A). | High | D-01 [Blocker for Phase 2] |
| GD-2 | Flat +20 Attack per enhancement triples weapon Attack at L0 but adds only about 11% at L30. | Medium | D-08: keep +20 as specified, but flag for Phase 20 (possibly scale with item level). |
| GD-3 | The spec doesn't say whether every regular mob kill drops gear at 30% Rare / 70% Standard. If it does, inventory floods and Rare loses value. | High | D-06 |
| GD-4 | Mythical gear drops **only** from PvP bosses, which forces PvE players into PvP. | Medium | Accept for v1 (it gives PvP a reason). Revisit in Phase 20. Final dungeon reward tables (§17 L30) may also include Mythical. |
| GD-5 | Level disparity in race PvP: L30 (47k HP) against L5 (498 HP). | High | D-16: PvP zone minimum level plus optional level brackets or normalization. |
| GD-6 | Race population imbalance per server. | Medium | D-17: server-side race-balance soft cap and matchmaking hints. |
| GD-7 | No XP curve or mob XP values. | High | D-18 [Blocker for Phase 2] |
| GD-8 | Skill acquisition and the special-skill unlock are undefined (only Quest 10's "token" is mentioned). | Medium | D-19 |
| GD-9 | No gear sink, so gear inflation goes unchecked. | Medium | D-09: salvage gear into Enhancement Stone fragments, plus an inventory cap. |
| GD-10 | Kill-count titles invite win-trading and alt farming. | Medium | No credit for repeat defeats of the same victim within N minutes, for victims under spawn protection, or for victims far below your level. Daily cap. |

### 2.4 Gamer
| # | Finding | Severity | Resolution |
|---|---|---|---|
| GM-1 | The animation pass (Phase 15) and mobile pass (Phase 19) come late. Combat will feel bad through Phases 5 to 14. | Medium | Each combat phase ships placeholder R15 animations and a usable mobile layout (Definition of Done). Phases 15 and 19 become *polish* passes. |
| GM-2 | No onboarding or tutorial flow is defined beyond Quest 1. | Medium | Phase 11 adds a guided first-5-minutes path: choose race, choose job, training, first dungeon. |
| GM-3 | Mobile targeting for skills is undefined. | Medium | Soft-lock auto-target nearest valid enemy (or ally for heals), tap to retarget. The server re-validates. |
| GM-4 | Dungeon defeat behavior is unclear: return to the race safe zone, or rejoin? | Medium | D-20 |

---

## 3. Technical Foundation (decided in Phases 0–1)

### 3.1 Toolchain (recommended)
| Tool | Purpose |
|---|---|
| **git** | Version control. Run `git init` before Phase 0 and commit after each accepted phase. |
| **Rojo 7** | Filesystem ↔ Studio sync (`default.project.json`). |
| **Rokit** (or Aftman) | Pins toolchain versions. |
| **Wally** | Package manager (ProfileStore, plus a test framework). |
| **StyLua** | Formatter. |
| **Selene** | Linter (with the Roblox std). |
| **luau-lsp** | Type checking. Use `--!strict` in shared and server modules where practical. |
| **Jest-Lua** (or TestEZ) | Unit and integration tests run in Studio. |
| **Lune** | Runs **pure** logic tests (formulas, loot tables, validators, enhancement state machine) outside Studio, CI-friendly. |
| Roblox Open Cloud Luau Execution *(optional, verify current availability)* | Headless in-place test runs for CI. |

Rule: keep **pure logic** (stat formulas, XP table, loot roller, attribute roller, validators, permission matrix, event-multiplier math) in modules with **no Roblox API calls**, so Lune can test them. Services wrap that logic with Roblox APIs.

### 3.2 Proposed source layout
```text
src/
  ServerScriptService/Server/
    init.server.luau          -- single bootstrap: loads services in dependency order
    Services/                 -- one ModuleScript per service (§24), TravelService not TeleportService
    Persistence/              -- ProfileStore adapter, migrations, validators
    Config/                   -- server-only config (roles, drop tables, secrets-free)
  ServerStorage/              -- mob/boss models, dungeon templates, loot assets (never replicated)
  ReplicatedStorage/Shared/
    Types, Constants, Enums
    Definitions/              -- Item, Skill, Job, Quest, Enemy, Boss, Event (display-safe data only)
    Logic/                    -- pure, testable formulas shared for *display* (server is still authoritative)
    Net/                      -- remote registry + schema definitions
    Util/                     -- ValidationHelpers, Signal, Maid/Trove
  StarterPlayerScripts/Client/
    init.client.luau
    Controllers/              -- §24 client controllers
    UI/                       -- mobile-first components
tests/
  pure/                       -- Lune
  studio/                     -- Jest-Lua/TestEZ
docs/
```

### 3.3 Networking contract (Phase 1)
- All remotes are created by the **server** from one registry (`Shared/Net`). The client never creates remotes.
- Each remote declares: name, direction, an argument **schema** (types, sizes, enums, max string length, max table size), a **rate limit** (token bucket per player per remote), required **player state** (alive, in zone X, not in transition), and a **permission** (for admin remotes).
- One server-side dispatcher validates **before** any handler runs. It rejects extra arguments and logs failures (with throttled logging) to the security log.
- Clients send **intents** only ("cast skill S at target T", "enhance item I"). They never send results.
- Prefer RemoteEvents plus a server reply event over RemoteFunctions (server→client RemoteFunctions are never used).

### 3.4 Persistence (Phase 2)
- **ProfileStore** with session locking. One profile per player (D-21: one character per account in v1).
- Profile follows CLAUDE.md §26, plus `Wallet`, `Consumables`, `ClaimedRewardIds`, `Stats` (lifetime counters) and `Flags`.
- `SchemaVersion` gets an ordered **migration chain** (`migrations/v1_to_v2.luau`, …).
- **Validate and repair on load:** clamp the level to 0–30, drop items with unknown definition IDs (and log them), clamp enhancement to 0–10, dedupe item GUIDs.
- **Idempotency:** every reward source (quest completion, dungeon run, boss kill, event reward) has a deterministic `rewardId`. A reward is granted only if `rewardId ∉ ClaimedRewardIds`, and the add happens in the **same synchronous mutation** as the grant. Old IDs get pruned by type (keep per-quest IDs permanently, prune run IDs after 7 days).
- Item instances get a server-generated GUID (`HttpService:GenerateGUID(false)`).
- Writes rely on ProfileStore auto-save and release on leave. Never call `SetAsync` per action.
- `BindToClose` releases all profiles.

### 3.5 Configuration and Live Ops (Phases 1, 17, 18, 26)
- `ConfigurationService` holds **defaults in code**, plus **overrides in a DataStore** (versioned, schema-validated), plus **invalidation over MessagingService** (servers reload the new version). Every override is audit-logged with before and after values.
- Drop tables are validated: weights are non-negative, they sum to 100% (or get normalized under a documented rule), and every rarity and item ID exists.
- Feature flags (`Flags.PvPEnabled`, `Flags.EnhancementEnabled`, …) let any system be disabled live.

### 3.6 Audit logging (D-13)
- `AuditLogService` writes structured entries: actor, role, action, target, args digest, before/after, timestamp, server JobId.
- Storage: a DataStore partitioned by UTC day, with batched appends every N seconds and on close. Optionally, an HttpService sink to an external log endpoint (behind a flag; Discord webhooks need a proxy and are discouraged).
- Security-relevant rejections (invalid remote calls) go to a separate, rate-limited **security log**.

### 3.7 Moderation primitives
- Roles: Owner is `game.CreatorId` (or the group owner). Admins and Moderators come from a **server-only** UserId list (or a group rank mapping). Roles are never read from the client.
- Use `Players:BanAsync` / `UnbanAsync` (Roblox Ban API) for bans and `Player:Kick` for kicks. Temporary in-game restrictions (PvP mute, event exclusion) are profile flags.
- All chat goes through **TextChatService** (default filtering). Any custom text shown to others is filtered.

---

## 4. Decision Log

Each decision needs an owner (the creator). The **recommended default** is what Claude implements if the creator approves it. Nothing in CLAUDE.md changes silently: an approved deviation gets recorded here and in the relevant doc.

| ID | Decision | Recommended default | Needed by |
|---|---|---|---|
| **D-01** ✅ | HP vs Attack growth mismatch (Appendix A) | **APPROVED 2026-10-08: keep the spec and compensate.** §5 stats are implemented exactly. Outgoing damage and healing get a separate **Level Power Scale** `PowerScale(L) = 1.047^L` (config `Combat.PowerScalePerLevel`), which keeps equal-level fights at about 2–7 basic hits from L0 to L30 (Appendix B). PvP normalization (D-16) applies on top. Revisit in Phase 20. | Phase 2 (stats), Phase 6 (scale) |
| **D-02** | Meaning of "Base Crit Damage 0.05%" | Treat it as a *bonus* on top of a base crit multiplier of **1.5×**: `critMult = 1.5 + CritDamageBonus`. Gear and enhancement (+2.5% per level) add to the bonus. Otherwise crits do nothing. | Phase 2 |
| **D-03** | Crit Chance (no base stat exists) | Base **5%** crit chance, increased only by gear and skills. Server rolls with a seeded per-server RNG. | Phase 2 |
| **D-04** | HP Regen unit | % of Max HP **per second, out of combat only** (in combat after 5 s without damage, or 0). Exact behavior is configurable. | Phase 2 |
| **D-05** | Defense mitigation formula | `damage = raw × K / (K + Defense)`, with `K` configurable and level-aware (`K = 200 + 25 × attackerLevel` as a starting point). Minimum damage is 1. | Phase 6 |
| **D-06** | Is a mob drop guaranteed? | Separate a **drop chance** (configurable: boss 100%, regular mob ~12%, elite ~35%) from the **rarity distribution** given a drop (the spec's 20/80 and 30/70). Both are documented in config. | Phase 10 |
| **D-07** | Split of "Standard/Uncommon" within the 70% | 45% Standard, 25% Uncommon. | Phase 10 |
| **D-08** | Enhancement success and failure | +1 to +5 at 100%. From +6 on, rates decline (90/80/70/60/50, configurable). **Failure never downgrades or destroys** the item. A **Perfect Stone guarantees success**. Rates are shown to the player in the UI. No paid stones (D-15). Armor gains +8 Defense per level (CLAUDE.md §10). | Phase 8 |
| **D-09** | Gear sink | Inventory cap of 150 gear instances. Salvage gear into Stone Fragments (10 fragments make 1 Enhancement Stone). Equipped and locked items can't be salvaged. | Phase 7 |
| **D-10** ✅ | Single place vs multi-place | **APPROVED 2026-10-08. One place in v1**: capitals, dungeon instances (cloned per session from ServerStorage into isolated regions) and PvP zones are all in one server, with StreamingEnabled. `TravelService` hides the boundary so a later move to reserved servers is localized. | **Blocker for Phase 1** |
| **D-11** | Persistence library | ProfileStore (via Wally), wrapped by `ProfileServiceAdapter` → rename to `PersistenceAdapter`. | Phase 2 |
| **D-12** | Cross-server config and events | DataStore holds the source of truth plus MessagingService invalidation. Scheduled events use UTC `os.time()` windows from config, so every server agrees without messages. | Phase 1 (skeleton), Phase 17 |
| **D-13** | Audit-log storage and retention | DataStore partitioned by day, kept 90 days. A cleanup job runs on the owner's command. | Phase 17 |
| **D-14** | Player trading | **None in v1.** | Phase 7 |
| **D-15** | Monetization | None in v1. If added later: cosmetic game passes only. A policy review is mandatory before any paid random item. | Phase 22 |
| **D-16** | PvP level disparity | Portal access needs Quest 4 **and** Level ≥ 10. PvP damage is normalized: each combatant fights at `min(ownLevel, opponentLevel + 5)` stats when attacking a lower-level player. Configurable. | Phase 12 |
| **D-17** | Race balance per server | Soft cap: if one race is ≥ 65% of a server, join-time server hints prefer other servers. Not a hard block. | Phase 12 |
| **D-18** ✅ | XP curve | **APPROVED 2026-10-08.** `XPToNext(L) = round(100 × 1.18^L)`, giving a target of ~20–25 active hours to L30 (79,095 total XP after per-level rounding, so an average of ~3,500 XP/hour; the last level needs 12,150). Mob XP scales with mob level, and dungeon clear bonuses provide ~60% of leveling XP. Tuned in Phase 20. | **Blocker for Phase 2** |
| **D-19** *(superseded by D-45)* | Skill acquisition | All 3 regular skills of the chosen job are owned at job selection, with the first unlocked at L0 and the others at L3 and L6. The special skill is unlocked by the Quest 10 token, with an early "lite" special at L12 so the slot isn't empty for most of the game. Extra skills come later as content. | Phase 5 |
| **D-20** *(superseded by D-39)* | Defeat inside a dungeon | Respawn at the dungeon checkpoint while the session is alive and the player has rejoin charges left (default 3). Otherwise return to the race safe zone. Defeat in PvP always returns the player to the race safe zone (§14). | Phase 9 |
| **D-21** | Characters per account | One character (race and job) per account in v1. Job change only through an admin action (audited). | Phase 2 |
| **D-22** ✅ | Rarity names | **Updated 2026-10-11:** Standard, Uncommon, Rare, **Epic**, Legendary, Mythical (6 tiers; Epic added by the creator to match the gear concept sheet). The default drop tables in CLAUDE.md §12/§15 don't use Epic, so Phase 10/14 must decide whether events or tables include it. (CLAUDE.md §9 says "finalize in Phase 3," but rarity is used from Phase 7. Finalize in Phase 1 enums.) | Phase 1 |
| **D-23** | Resource system | One resource, **Focus** (100 max, regenerates ~10/s). Skills cost Focus. Healer heals cost more. | Phase 5/6 |
| **D-24** | Same-race combat | Friendly fire off. Heals and buffs only target the same race and your party. | Phase 6 |
| **D-25** | Equipment slots | Weapon, Helm, Chest, Legs, Boots, Accessory (Quest 3 reward). | Phase 7 |
| **D-26** ✅ | Character look | **APPROVED 2026-10-11: game outfits over the avatar.** Keep each player's face, hair, body shape and skin. The server removes casual clothing and accessories and dresses every character in race + look gear (`Appearance/Wardrobe`). | Phase 3 (pulled forward from 15/16) |
| **D-27** ✅ | Art source | **APPROVED 2026-10-11: Roblox Creator Store assets, approved by the creator.** Approved accessories are saved as `.rbxm` under `assets/Outfits/<LookName>/` (Rojo → `ServerStorage.RC_Assets`). Until then a procedural fantasy outfit (`Appearance/OutfitBuilder`) is used. No unverified catalog IDs. | Phase 3, art pass 15/16 |
| **D-28** ✅ | UI style | **APPROVED 2026-10-11: dark glass + gold fantasy.** All screens use `client/UI/Theme` + `client/UI/Kit`. | Phase 3 onward, polish in 19 |
| **D-29** ✅ | Safe-zone healing | **APPROVED 2026-10-11.** CLAUDE.md §5 regen is very slow (0.02%/s of max HP at L0 is about 0.04 HP/s), so a defeated or hurt player would wait minutes. Proposal: inside a race safe zone, HP restores at 20% of max HP per second (`Combat.SafeZoneRegenPctPerSecond`, admin-tunable). Outside safe zones the §5 regen applies unchanged after 5 s out of combat (D-04). | Phase 6 |
| **D-30** ✅ | Fourth job: Mage | **APPROVED 2026-10-11 by the creator** (reference game: Shaiya). Skill categories MagicAttack, AreaMagic, Control, Barrier; weapons Staff, Wand, Tome; basic attack *Arcane Missile* (40 studs). CLAUDE.md §1/§6.4 updated. Phase 5 needs 3 regular + 1 special Mage skills. | Phase 4 (retro), Phase 5 |
| **D-31** ✅ | Gem sockets (Shaiya-inspired) | **APPROVED 2026-10-11 in principle.** Gear gets sockets and gems add stats. Designed as its own phase after Enhancement (Phase 8); never paid-random. | Future phase (after 8) |
| **D-32** ✅ | Party EXP sharing | **APPROVED 2026-10-11.** Fold into the dungeon phase (Phase 9). | Phase 9 |
| **D-33** ✅ | Allocatable stat points | **APPROVED 2026-10-11 in principle:** a *small bonus layer* of points per level on top of the unchanged CLAUDE.md §5 growth (§5 itself is not changed). Exact numbers and stats are designed in the Phase 20 balance review and need sign-off. | Phase 20 design |
| **D-34** ✅ | Mounts and guilds | **APPROVED 2026-10-11 as post-launch features** (Phase 26+). | Post-launch |
| **D-35** ✅ | Character art direction | **APPROVED 2026-10-11:** follow the concept sheets in `docs/characters and gears/` at least ~80% (silhouette, palette, layering, glow) with job-specific outfits, race features and held weapons. Missing pieces are designed by Claude to match the concept and approved by the creator. | Pulled forward from Phases 15/16 |
| **D-36** ✅ | Character animation & combat feel | **APPROVED 2026-10-11 (creator chose "I author them"):** procedural joint posing is replaced by authored keyframe clips (`AnimationClips`, weapon arms solved by `tools/anim`) played through the Animator by priority (idle/hold, sprint/crouch, attacks, reactions, defeat). Basic attacks become 3-step combos per job with a heavy finisher (`BasicAttacks`, `ComboMath`), input buffering, hold-to-attack, melee lunge, hit-stop, camera shake and per-step VFX. Server decides the step and lands damage on the clip's Hit frame + projectile travel, re-validating at impact; chain DPS equals the Phase 6 values. Clips play in Studio via registration; **before release the creator publishes each clip once** (`docs/ASSET_GUIDE.md` Part D) and fills `AnimationAssets`. | Pulled forward from Phases 5/6 polish |
| **D-37** ✅ | Capitals, war zones, dungeons: order | **Creator request 2026-10-11:** build the capitals, war zones and dungeons. Done one phase at a time in dependency order: (1) **capital art** (Phase 16 subset, pulled forward): Skyreach Citadel and Emberdeep Bastion built by `World/CapitalBuilder` + `World/Architecture` from `WorldLayout.City`, per-capital lighting (`ZoneAtmosphere`, `AtmosphereController`), sealed portal gates for Desert Rift, Jungle Rift and Rift Dungeons; (2) **Phase 9** dungeon framework behind the Dungeons gate (EXP rewards; item loot waits for Phases 7/10); (3) **Phases 12–13** war zones behind the Rift gates. Capitals grew to 300 studs, safe zones to radius 110. Budget: ≤ 1,000 parts per capital. | Phase 16 (capitals), 9, 12, 13 |
| **D-38** ✅ | Phase 9 dungeon framework: design choices | **Implemented 2026-10-16:** party formation is a **quick-join rally** at each capital's Rift Dungeons gate (ProximityPrompt, no entry remote; same race, ≤ maxParty, `Dungeon.RallySeconds`); invites can come later. Runs clone a server-built template (`World/DungeonBuilder`) into one of ≤ `Dungeon.MaxSlots` slots far from the world (`WorldLayout.DungeonSlots`). Rooms activate in order; enemy HP × (1 + 0.6 per extra member). Kill EXP shared per D-32 (+15% per extra member, split evenly, members within 150 studs); clear EXP via `D:<runId>` claim. D-20 checkpoint charges (3), 120 s disconnect grace, boss reset after 4 s with no living member in the boss room. First dungeon **Rift Hollow** (Lv 1+): Rift Wolves → Crystal Gallery (beetles, elite Stoneback) → **Rift Guardian** (3 phases; Slam circle, Sweep cone, wolf summons, Shockwave ring). Training Grounds Rift Sprites (20 EXP; 5 = Lv 1) serve Quest 1. Item loot is Phase 10. | Phase 9 |
| **D-39** ✅ | Parties and dungeon defeat (supersedes D-20 and the D-38 rally) | **Creator decision 2026-10-16:** real parties. The player who sends the first invite creates the party and is its leader; only the leader invites (same realm, ≤ 4, invites expire after 45 s, accept/decline) and removes members; leadership passes to the longest-standing member. The leader opens the dungeon at the gate; members near the gate come along and others can enter later (arriving next to the leader). **Dungeon defeat:** respawn next to the party leader, or another living member if the leader is down; when the whole party is down the run ends and everyone respawns in front of the gate, party intact. Revive charges and the disconnect grace are removed (disconnecting leaves the party and the run). | Phase 9 |
| **D-40** ✅ | Free visual upgrades for creatures and characters | **Creator decision 2026-10-16: Option A now** — creatures rebuilt from rounded procedural forms (ellipsoid bodies and jointed limbs via built-in SpecialMesh shapes; no assets, no cost). **Noted for later:** **B.** free Creator Store rigged creature / armour models, inserted by the creator and swapped in through a pipeline like the outfit Wardrobe (keeps server AI, stats and rig joints); **C.** Roblox Studio's free AI mesh generator for creature parts, armour and props, wired in the same way. Player outfits stay on the current pipeline until B/C. | Phase 16 (art pass) |
| **D-41** ✅ | Phase 12 Desert Rift: implementation choices | **Implemented 2026-10-16:** the zone is real Roblox Terrain generated from a pure heightmap (`Logic/DesertTerrain`: dunes, sandstone mesas, rim cliffs, oasis pool) at (-3200, 24, 0), 1,000 studs square, with invisible boundary walls. **Creator change 2026-10-16:** each realm has its **own camp** at opposite edges (Angels north, Devils south): arrival point, "Return Home" portal (blocked while combat-tagged) and a race-owned safe zone, ringed by a shimmering marker; the **server moves anyone of the other realm back out** of a camp 4×/s (T-17 anti-spawn-camping; a physical barrier was dropped because it could trap players in their own camp). The **oasis in the middle is open PvP ground** with creature packs (and the Phase 14 PvP boss). Capital gate: level ≥ `PvP.MinLevel` 10 on live servers; **`PvP.StudioMinLevel` 1 in Studio only** for testing; the Quest 4 requirement is added with the quest system (Phase 11). D-16 normalization in CombatService; PvP records with T-18 credit rules (30 min repeat victim, > 5 levels below, daily cap 50); leaving while combat-tagged by a player counts as a defeat. Field camps (Dune Stalkers, Sand Scarabs, Sandstone Golems) respawn after 30 s. The PvP boss and PvP loot are Phase 14. | Phase 12 |
| **D-42** ✅ | Persistent dungeons with respawn timers (supersedes the instanced runs of D-38) | **Creator decision 2026-10-16: shared per realm.** One persistent Rift Hollow per realm (slot 1 Angels, slot 2 Devils) that every player of that realm shares; no PvP inside; open map, rooms about twice as big (140×150, 170×200, 190×190), wide corridors, no doors. Respawns: regular mobs `Dungeon.MobRespawnSeconds` 45 s, mini boss (Stoneback Guardian) `MiniBossRespawnMinutes` 20, big boss (Rift Guardian) `BossRespawnHours` 3; Studio uses 60 s / 180 s for testing. Altars and the tracker show "awake" / countdowns (timers restart with the server). Kill EXP shared with the killer's nearby party (D-32); each mini-boss / boss spawn gives contributors a one-time bonus (`B:<spawnId>:<enemy>`). Defeat inside: beside your party leader / a party member in the same dungeon, else outside the gate (D-39). Creature motion reworked (distance-driven gaits, banking, idle look-around and wandering, hit and defeat reactions). | Phase 9 |
| **D-43** ✅ | Phase 13 Jungle Rift: implementation choices | **Implemented 2026-10-17:** same rules as the Desert Rift (D-41): each realm has its own camp at opposite edges (Angels north, Devils south) with arrival, "Return Home" portal and a race-owned safe zone (`JungleAngelCamp` / `JungleDevilCamp`); everything between is open PvP ground. CLAUDE.md §13 asks for a central waterfall/river safe zone; following the creator's D-41 change for the Desert, the waterfall pool is **contested ground** and the safe zones are the camps. Terrain from a pure heightmap (`Logic/JungleTerrain`) at (3200, 24, 0), 1,000 studs square: a highland shelf in the west whose upper river pours over a ~44-stud cliff as **the waterfall** into a plunge pool in the middle, then meanders east as the lower river; five bridges (2 stone, 3 rope) on both stretches, mossy outcrops, rim cliffs. Art: layered translucent water sheets, two particle emitters (spray, mist), ruins, braziers and lily pads around the pool, a seeded forest of rainforest trees, palms, ferns and bushes kept off water, paths, camps and steep ground, stilt huts in the camps. Field creatures Jungle Prowler (L11), Thorncrawler (L12), Mossback Golem (L13 elite), respawn as in the Desert. **Framework gaps closed** (PLAN Phase 13 says new code means the Phase 12 framework was incomplete): terrain sampling is now per zone (`WarZone.terrain`, `Logic/WarZoneTerrain`), the voxel writer (`World/TerrainWriter`) and the camp / bounds builders (`World/WarZoneKit`) are shared, plants live in `World/Flora`. PvPService needed no rule changes. Quests 6–8 integration waits for the quest system (Phase 11). | Phase 13 |
| **D-44** *(superseded by D-45)* | Phase 5 skill system: first version | **Implemented 2026-10-17, replaced the same day after creator review:** 16 skills (3 regular + 1 special per job, categories checked against JobDefinitions) in `Definitions/SkillDefinitions`; rules in `Logic/SkillRules`; server `SkillService`. **D-19 as built:** all 4 job skills are owned from job selection; regular skills unlock at L0 / L3 / L6 and the special at **L12** (this is the "lite" special; the Quest 10 token will unlock an upgraded special in Phase 11). Empty slots auto-fill as skills unlock; the player's own choices never move. Studio unlocks everything (`Skills.StudioUnlockAll`, never live). **Loadout** is one intent (`SetLoadout(regular ≤ 3, special?)`, replacing the planned per-slot `EquipSkill`), validated for ownership, job, slot type, level and duplicates. **Casting** (`SkillCast(id, target?)`): equipped / owned / job / unlocked / stun / server cooldown + 0.6 s global cooldown / Focus, then server targeting (hostility, D-24 ally rules, range with lag cap, line of sight); effects land at the clip Hit frame + projectile travel and re-check harm/help rules. **Statuses** on CombatService entities: Stun, Root, Slow, Mark, Guard, Shield, Taunt; every hit goes Mark → Guard (≤ 90%) → Shield. **Fairness:** stun/root/slow last half as long player-vs-player (`Skills.PvPControlScale`), taunt never affects players, bosses ignore stun/root/slow; stuns ≤ 1.5 s; a healer inside a safe zone can't support someone fighting outside it. Evasive Roll is moved by the client after the server confirms, inside a speed allowance. **Balance (first pass, Phase 20 tunes):** skills add at most 60% of a job's basic-attack DPS; regular-skill Focus use stays under Focus regen. **UI:** desktop bar (1/2/3/Q), gamepad X/Y/L1/R1, touch buttons from the shared `Layout/CombatButtonsLayout` (attack, run, crouch, skills; device-tested for overlaps, ≥ 44 px, HUD and jump clearance); Skills panel (K) for the loadout; status chips over heads (icon + word) and a shield bubble. **Animations:** skills reuse the authored attack clips; self-buffs are effect-only until the Phase 15 animation pass adds dedicated skill clips. | Phase 5 |
| **D-45** ✅ | Skill trees, combos, targeting and skill visuals (supersedes D-19 and D-44) | **Creator review 2026-10-17** asked for real class skill trees, a free choice of skill set, standard effects (slow, freeze, stun, area, heal, poison, hardening...), combo effects, skill information, hit effects, better skill visuals and reliable targeting. **Trees (revised after the second creator review the same day: more skills, real icons, level-based unlocks):** each class has **4 branches x 6 tiers = 24 skills** (16 regular in tiers 1, 2, 4, 5; 8 specials in tier 3 and the tier-6 capstone; **96 total**, `Definitions/SkillDefinitions`): Warrior Blademaster / Ironclad / Warlord / **Vanguard**, Healer Light / Sanctity / Judgment / **Seraph**, Archer Marksman / Venom / Ranger / **Windrunner**, Mage Pyromancy / Cryomancy / Arcanist / **Stormcaller** (new Storm element). **Unlocks follow the level up to 30:** tier 1 of every branch at level 0, then tiers at 3 / 8 / 14 / 20 / 27 plus one level per column (`SkillDefinitions.unlockLevelFor`), so new skills open on 21 different levels and the last capstone at 30; **ranks open with level too** (rank 2 at 6, 3 at 12, 4 at 18, 5 at 24, `SkillRules.rankCap`); level-up toasts name the skill that just opened. Each skill needs the one above it (`requires`, `maxRank` and `unlockLevel` are derived from branch / tier / type). **Icons:** font glyphs such as ⛨ ⚚ ♜ ☣ didn't render in Roblox fonts, so every skill and branch has a drawn icon: `Definitions/SkillIcons` motifs (bars, dots, rings, half rings on a 100 x 100 box) built from UI frames by `UI/SkillIcon` on an element-coloured tile; `tools/icons/render_icons.py` previews them. Studio test allowances (`Skills.StudioUnlockAll` / `StudioBonusPoints`) are now **off by default** so Studio shows the real level gates. **Skill points:** 1 at level 0 + 1 per level (31 at L30); 1 point per rank; regular skills rank 1-5, specials 1-3 (+12% numbers per rank; control +8% duration and buffs +10%, capped: stun ≤ 2 s, freeze ≤ 2.5 s, percentages ≤ 60%). A full tree costs more than 31 points, so builds are a choice. Free reset in a safe zone, out of combat. Profile schema v2 (OwnedSkills = id -> rank) with a v1 -> v2 migration that refunds the old free grants. **Skill bar:** any 3 learned regular + 1 learned special. **Effects:** Damage, Heal, Shield, Poison / Burn (damage every second, credited to the caster), Regen, Stun, Freeze, Root, Slow, Silence, Mark, Weaken, Guard, Harden (+Defense), Empower (+Attack), Haste, Taunt, Cleanse, Dash; area waves; self effects. **Combos** (bonus damage when the target already has a status or is low on HP, some consume it): Shatter (frozen), Combustion (burning), Toxic Bloom (poisoned), Judgment / Deadeye (marked), Earthshaker (slowed), Crushing Blow (stunned), Execute (low HP); cross-class teamwork (a Mage freeze sets up a Warrior Shatter). **Fairness:** after a stun / freeze ends a player is immune to another for 3 s; PvP crowd control lasts half as long; bosses ignore crowd control (taunt works). **Balance (Phase 20 tunes):** the best 3 + 1 bar at max rank adds at most ~1.15x the class's basic-attack damage (still true with 24 skills per class); any 3 regular skills stay within Focus regen. **Targeting:** one persistent selected target (click / tap with near-miss snapping, Tab / DPad cycle, ring + head plate with HP and statuses); attacks and skills always use it; with none, the nearest enemy in front becomes selected; out of range the character walks into range and then acts. **Visuals:** `Effects/SkillVfx` element palettes with cast (weapon glint, hand orbs, rune circles), projectiles with trails / light / particles, impacts on every server-confirmed hit (explosion, shatter, venom, pillar, quake...), area effects (whirl, nova, quake, arrow / poison rain, blizzard, meteor, healing dome), status auras (ice block, stun stars, flames, poison bubbles, hardening outline...), "COMBO · NAME" titles, coloured damage-over-time numbers. **Animations:** 10 new authored skill clips (Warrior spin / slam / brace / roar, Healer raise / plant, Archer sky volley / roll, Mage channel / push) with solved weapon arms. **Info:** every skill has a generated description (`SkillRules.describe`) in the tree and in skill-bar tooltips. | Phase 5 |
| **D-46** ✅ | Rest regen out of combat (creator review 2026-10-17) | Players who haven't attacked or been hit for `Combat.RegenDelaySeconds` (5 s) and have no live creature (mob / boss; training dummies don't count) within `Combat.RestCreatureRadius` (40 studs) recover an extra `Combat.RestRegenPctPerSecond` (2% of max HP per second, about 50 s from empty) on top of the CLAUDE.md §5 HP-regen stat, everywhere outside safe zones: dungeons, forest, desert and jungle. Safe zones keep their faster regen (D-29). Server-side in CombatService's tick (checked twice a second); the HUD shows "· resting" next to HP. The §5 stat itself is unchanged. | Phase 5 |
| **D-47** ✅ | Rift Hollow becomes a 4-floor dungeon; boss killability (creator review 2026-10-17) | **Floors** (`Definitions/DungeonDefinitions`, built by `World/DungeonBuilder` side by side in each realm's slot, 500 studs apart, each with its own theme): **1 The Shattered Crypts** (crystal), **2 The Ember Depths** (basalt and lava seams), **3 The Frozen Abyss** (ice-stone and icicles): each a landing, **7 rooms** and the floor boss's lair; creature levels **1-10 / 11-20 / 21-30** (rising room by room, an elite mini boss in room 4), floor bosses named after myth's worst beasts: **Cerberus (10), Chimera (20), Basilisk (30)**. **4 The Nullborn Depths**: the **Hall of Thirty** with **30 separate chambers**, one mini boss each (Minotaur, Gorgon, Fenrir, Scylla, Fafnir, Nemean Lion... levels **31-40**, three per level), then **Typhon's Sanctum**, its own room, for the **level-40 Dungeon Boss Typhon, Father of Monsters**. **Access (creator decision, revised by D-50):** every floor is open to every level; each landing has Leave (and Up on 2-4) portals; the Down portal at the back of each lair **always works** (no seal), guarded by creatures and the floor boss. Creatures above level 30 use `StatFormulas.forCreatureLevel` (same formula, up to 60); camps can set a level (EXP scaled along the EXP curve, `EnemyDefinitions.xpAt`). **Killability** (`Logic/BossBalance`): boss HP comes from a model of a reference player's damage (level min(boss, 30), basic chain + skills, 70% uptime, real Defense / K formula) and an **enrage timer** (Boss 300 s, Floor 240 s, Mini 180 s: then 4x damage, abilities twice as often). Time to kill as a share of the enrage: **Dungeon Boss: 1 player impossible (1.9), duo super hard (0.95), party very hard (0.48), union hard (0.24 with 8, 0.12 with 16)**; floor bosses one notch easier (solo impossible, duo very hard, party hard); mini bosses a duo's fight. Boss hits are sized to ~30% (Boss) / 22% (Floor) / 18% (Mini) of a reference player's HP. Gear (Phases 7/10) will shift this; Phase 20 re-tunes. Every boss gets generated abilities by body plan (targeted circle, frontal cone, ring; floor and dungeon bosses also summon adds) and phases. Bosses reuse the D-40 procedural bodies with their own size and colours until the Phase 16 art pass. | Phase 9 |
| **D-48** ✅ | Unions (creator review 2026-10-17) | A **union joins up to 4 parties (16 players)**. Only party leaders act: the first party's leader invites other party leaders of the same realm (`UnionInvite` / `UnionRespond`, invites expire like party invites) and removes parties (`UnionKick`); any party leader can take their party out (`UnionLeave`). A party that dissolves leaves its union; a union of one party dissolves. Kill EXP is shared across the whole union nearby (D-32 rules, `PartyService:GetGroupMembers`), in dungeons and war zones. Party panel: union summary, + Union picker (party leaders of your realm) and Leave union. Dungeon respawns stay with your own party (D-39). | Phase 9 |
| **D-49** ✅ | War-zone creatures 25-30 and five bosses per zone (creator review 2026-10-17) | Desert / Jungle field creatures are **levels 25-30** (camps set each spot's level) and there are **many more camps** (21-22 per zone). **Five bosses per zone, levels 30-50**, in the contested middle band, with BossService abilities and enrage: Desert **Ammit (30), Anzu (35), Sphinx (40), Apophis (45), Oasis Colossus (50)**; Jungle **Camazotz (30), Ahuizotl (35), Mapinguari (40), Jungle Hydra (45), Leviathan (50)**. They get harder with level (`BossBalance.fieldDuoFraction`: level 30 like a floor boss, level 50 like the Dungeon Boss). Respawn `PvP.BossRespawnMinutes` 45 (Studio 120 s); a billboard over each post shows awake / countdown. **The zones still open at level 10 (creator decision)**, so lower-level players can enter but every creature there outclasses them. Boss loot stays Phase 14. | Phase 12-13 |
| **D-50** ✅ | Open, guarded floors; creature-like bosses (creator review 2026-10-17) | **No floor is locked:** the floor-boss seal on the Down portals is gone (any level can go down without killing the floor boss); the label shows the next floor and its levels. Floors are **guarded instead**: rooms hold 4-5 creature packs (about 84 creatures per floor, double before) and each lair has **6 guard camps** (14 creatures at the floor's top level: flank packs and two elites by the portal) besides the floor boss. **Bosses read as creatures, not statues:** new **Serpent** body plan (chest, raised two-joint neck, opening jaw, 7 trailing segments that slither) and **traits** for a myth's anatomy (`EnemyDefinitions.Trait`: ThreeHeads, Mane, Horns, Wings, SerpentTail, Spikes, Crest): **Cerberus** three heads, fiery mane, spines; **Chimera** lion mane, goat horns, bat wings, serpent tail; **Basilisk** a crowned serpent; **Typhon** wings, horns, serpent tail; Hydra / Ladon three-headed serpents; war and mini bosses get theirs too. Elites get fangs and claws; every jaw opens. **Animation** (`MobVisualController`): offsets scale with the creature's size (`RC_Scale`); heads track the nearest player; idle actions (sniff / howl / shake, roar / stretch, rise / hiss / coil, rear); wings fold, spread and beat; tails sway in a wave; attack moves by ability shape (`MobAttack.move`: Strike lunge, Slam rear-up and crash, Roar head-back jaws wide, Sweep). Server: elites and bosses **prowl** their post when idle (7 studs) and **turn toward** a target gradually (22-35° per tick) instead of snapping. Procedural forms remain until the Phase 16 art pass. | Phase 9 |

---

## 5. Missing Systems → Assigned Phases

| System | Required by (CLAUDE.md) | Assigned to |
|---|---|---|
| Currency / Wallet (Gold, PvP Marks) | Quest 8 "PvP currency" | Phase 7 |
| Consumables (healing potions, PvP consumable) | Quests 1 and 5 | Phase 7 (items), Phase 6 (use effect) |
| Quest items (Rift Fragments, Gate Core) | Quests 3 and 4 | Phase 11 |
| Titles, cosmetics, aura, equip UI | §4, Quests 5–10, L30 | Phase 11 (framework), Phase 14 (PvP titles) |
| PvP stats, victory counts, victory titles with anti-farming | §4 | Phase 12 (stats), Phase 14 (titles) |
| Party / dungeon group formation | §11 "Party/session" | Phase 9 |
| Training area and training creatures | Quest 1 | Phase 9 |
| Skill acquisition and special unlock token | Quest 10 | Phase 5 (rules), Phase 11 (token reward) |
| Inventory cap, salvage, item locking | Economy health | Phase 7 |
| Player reports pipeline | §21 | Phase 17 |
| Cross-server config propagation | §12, §23 "changeable by admins" | Phase 1 skeleton, Phase 17 |
| Onboarding flow | §31 Gamer | Phase 11 |
| Analytics funnel (Roblox AnalyticsService) | Retention review | Phase 11 (core funnel), Phase 26 |
| PvE mobs and PvP boss inside PvP zones | Quests 6–7, §15 | Phases 12–13 (spawns), Phase 14 (loot) |
| Event stacking rules | §23 multipliers | Phase 18: multipliers combine additively per category, capped (e.g. XP ≤ 3×). Rarity weights get adjusted and then **re-normalized to 100%**. |

---

## 6. Phase Sequence (amended)

The `PHASE_PROMPTS.md` numbering stays the same so prompts still match. **Execution order changes in two places:**

1. **Run Phase 6 (Combat Foundation) before Phase 5 (Skill System).** Skills need a resolver. Phase 6 ships one basic attack per job to test with.
2. Phase 11 (Quests) builds **all 11 quest definitions** and their objective types. Quests 6–8 are completable only once Phases 12–14 exist, and Phase 13 runs an integration check on them.

The order of everything else is sound.

### Milestones
| Milestone | Phases | Outcome |
|---|---|---|
| **M0 Foundation** | 0, 1, 2 | Boots cleanly. Profiles save. Levels 0–30 are server-authoritative. |
| **M1 Identity** | 3, 4 | Race and job chosen and persisted. Race spawn and safe zone work. |
| **M2 Combat Core** | 6, 5, 7, 8 | Fight, use skills, loot instances, enhance. All server-side. |
| **M3 PvE Loop (vertical slice)** | 9, 10, 11 | New player → training → first dungeon → loot → enhancement → story. **Playtest gate.** |
| **M4 PvP** | 12, 13, 14 | Two PvP zones, safe zones, non-graphic defeat, PvP loot and titles. |
| **M5 Presentation** | 15, 16 | Animation and art passes. |
| **M6 Operations** | 17, 18 | Admin/Mod panel, 30 events. |
| **M7 Hardening & Release** | 19–25 | Mobile, balance, security, compliance, performance, gamer review, release candidate. |
| **M8 Live** | 26 | Live-ops readiness. |

### Per-phase plan

Every phase follows CLAUDE.md §32: inspect, read skills, state the goal, list files, implement, test, review security and mobile, report. **Every phase also meets these standing exit criteria:** no errors in Studio Play; a 2-player local server test; the remotes it added are listed in `docs/ARCHITECTURE.md`; new remotes have schema, rate-limit and state checks; new data fields have migration and repair rules; new UI works at phone size in the Device Emulator; docs are updated; the phase is committed to git.

#### Phase 0 — Repository Audit
- **Skills:** architecture, security, data-integrity.
- **Do:** create `docs/ARCHITECTURE.md`, `docs/DATA_MODEL.md` and `docs/SECURITY_MODEL.md` from §3 of this plan, and record decisions D-10, D-11, D-12, D-21 and D-22. Write the remote map (planned), the threat model (STRIDE-style per remote category) and the performance risk list.
- **Exit:** no gameplay code. The creator has signed off on the Blocker decisions D-01, D-10 and D-18 (or they are explicitly deferred).

#### Phase 1 — Foundation
- **Do:** git, the Rojo, Wally, StyLua and Selene toolchain, the folder layout (§3.2), Enums (Race, Job, Rarity, SkillType, ItemSlot, Zone, Role), Types, Constants, `ConfigurationService` (defaults plus a DataStore override stub plus MessagingService invalidation stub), `RateLimitService` (token bucket), the Net registry and dispatcher (§3.3), Logger (levels, throttling), error boundaries (`xpcall` around service init and handlers), and a service loader with explicit init/start order.
- **Tests:** pure tests for the token bucket, schema validator and config validator. Studio: server and client boot, and remotes exist only from the server registry.
- **Exit:** clean boot; no server-only module in ReplicatedStorage; an invalid remote payload is rejected and logged.

#### Phase 2 — Player Data and Level 0–30
- **Do:** `PersistenceAdapter` (ProfileStore), profile schema v1, migration framework, validator and repair, `LevelService` (XP grant API is **server-internal only**), `StatsService` (pure formulas from §5 plus D-02 to D-04), XP table (D-18), and a replicated read-only stat snapshot for the HUD.
- **Tests (pure):** the stat table in Appendix A to 0.01 precision; XP overflow across several levels; cap at 30 with excess XP discarded or banked (document which); repairing a corrupt profile (negative level, level 99, missing fields, unknown item IDs).
- **Tests (Studio):** rejoin preserves level; two servers can't hold the same profile (session lock); fire every remote with XP-like payloads, none changes XP.
- **Exit:** CLAUDE.md Phase 2 acceptance criteria.

#### Phase 3 — Race System
- **Do:** first-time race selection UI (mobile-first), `RaceService` (set once; changes only through admin), race spawn points and safe zones (graybox), face presets as **server-owned preset IDs** (the client sends an index into an allowlist, never an asset ID), race accessories applied by the server.
- **Tests:** a forged race value or asset ID is rejected; trying to change race after selection is rejected; spawn is deterministic.
- **Compliance:** art follows the PC-1 rules.

#### Phase 4 — Job System
- **Do:** `JobDefinitions` (allowed skill categories per CLAUDE.md §6), job selection (once), `JobService.validateSkill(job, skill)`.
- **Tests:** every cross-job skill category is rejected; job persists.

#### Phase 6 — Combat Foundation *(runs before Phase 5)*
- **Do:** `CombatService` owns HP, Focus (D-23), defense (D-05), crit (D-02/D-03), regen (D-04), friendly-fire rules (D-24), and combat states (Idle, InCombat, Defeated, Protected). It also does target validation (exists, alive, hostile or allied as required, in range, line of sight on a server raycast) and hit reactions (replicated as cosmetic events). Non-graphic defeat means a stylized dissolve/light VFX, then return to the race safe zone, then spawn protection. Each job gets one basic attack for testing. Placeholder R15 animations.
- **Tests:** forged damage remote (there isn't one, so assert that); out-of-range target; dead target; same-race target; defeat → teleport home → protection timer; client can't set Humanoid.Health. (Health is server-owned; detect client-side humanoid tampering by comparing against the server's HP value.)

#### Phase 5 — Skill System
- **Do:** 12 skills (3 regular plus 1 special per job), the loadout (3+1) with server validation, server-tracked cooldowns, Focus costs, range, cast/channel rules, the skill acquisition rules (D-19), a mobile skill bar with soft-lock targeting (GM-3), and stylized VFX.
- **Tests:** equipping a wrong-job skill, an unowned skill, or a 5th slot fails; casting during cooldown fails; spamming casts gets rate-limited; mobile buttons are ≥ 44 px, sit in the safe area, and are usable while moving.

#### Phase 7 — Inventory and Gear
- **Do:** item definitions, item instances (GUID, defId, rarity, rolled attributes, enhancement, lock flag, source, createdAt), attribute pools per item category and job (CLAUDE.md §8), a rarity-scaled number of attribute rolls, equipment slots (D-25), equip and unequip with job/level checks, Wallet, consumables (stackable), inventory cap and salvage (D-09), and no trading (D-14).
- **Tests (pure):** the attribute roller never leaves its pool and respects rarity bounds (fuzz 100k rolls).
- **Tests (Studio):** a forged item GUID, equipping someone else's item, equipping a wrong-slot item, salvaging an equipped item, rejoin persistence.

#### Phase 8 — Enhancement
- **Do:** `EnhancementService` per D-08. It runs as one synchronous mutation: check ownership and level < 10, check stone count, consume the stone, roll, apply, log. A per-player lock prevents overlapping requests. The UI shows success rates and the result.
- **Tests:** concurrent requests (fire the same request 20 times in one frame) consume exactly the right number of stones; an item can't exceed +10; disconnect mid-request leaves state consistent (profile release); armor gets Defense, never Attack.

#### Phase 9 — Dungeon Framework
- **Do:** `DungeonService` (definitions, entry requirements, party formation by invite or quick-join, a session object with a run ID, an instanced map cloned from ServerStorage), `MobService` (lightweight server AI state machine on a throttled heartbeat at ≤ 10 Hz with sleeping when no players are near), `BossService` (phases, telegraphs, reset on wipe or leave), objectives, completion, rewards keyed by `runId:userId`, rejoin and defeat handling (D-20), cleanup on empty, the training area and creatures (Quest 1), and 1 starter dungeon with the "Dungeon Guardian".
- **Tests:** 2–4 players in one run plus 2 concurrent runs; leaving and rejoining mid-run; boss resets correctly after a wipe; reward claimed once per run per player; instance count returns to baseline after cleanup.

#### Phase 10 — Dungeon Loot
- **Do:** a `LootService` table schema (drop chance plus rarity weights, D-06/D-07), validation (weights sum to 100), a server roll, a grant that goes through the Phase 7 item factory, audit logs, and an "interpretation" note for the 30/70 table in config.
- **Tests (pure):** 1M-roll distribution within ±0.5%; an invalid table is rejected at load.

#### Phase 11 — Story and Quest System *(M3 playtest gate)*
- **Do:** `QuestService` with objective types (Kill, ClearDungeon, DefeatBoss, Collect, Visit, Inspect, EnterZone, ReturnSafely, ParticipatePvP, Investigate). Also prerequisites, a server-side dialogue graph, story flags, idempotent rewards (`quest:<id>` reward IDs), all 11 quest definitions, quest items, the titles and cosmetics framework, the onboarding path (GM-2), a compact mobile quest tracker, and analytics funnel events.
- **Tests:** a forged progress remote (there isn't one, so assert it); claiming twice; skipping a prerequisite; rejoin mid-quest.
- **Playtest gate:** a full new-player run from L0 through Quest 4 on desktop and mobile emulation. Fix all P0 and P1 issues before M4.

#### Phase 12 — Desert PvP Zone
- **Do:** desert terrain (graybox plus key landmarks), the oasis safe zone (server-side region check, not just a client trigger), return portal, boundary, race PvP rules, level gate and normalization (D-16), race-balance hints (D-17), spawn protection (on spawn and on entering, ends early if the player attacks), anti-camping (no damage into or out of the safe zone, a protection bubble on exit), PvP stats, and PvE mob spawns.
- **Tests:** damage across the safe-zone boundary in both directions; teleporting into the safe zone mid-combat (combat-tag blocks the portal); defeat returns the player to their own race's zone with no item or XP loss.

#### Phase 13 — Jungle PvP Zone
- **Do:** reuse the Phase 12 zone framework with the jungle content (waterfall, river, bridges). It should be data and art only. Any new code is a sign the Phase 12 framework was incomplete.
- **Integration:** Quests 6–8 become completable end to end.

#### Phase 14 — PvP Loot
- **Do:** the PvP boss (20% Mythical / 80% Rare) and PvP mob stone tables (30% Perfect / 70% Standard), victory titles with anti-farming (GD-10), and PvP Marks currency.
- **Tests:** distribution, single grant, and farming protections (repeat-victim and protected-victim cases give no credit).

#### Phase 15 — Human-like Animation Pass
- R15 locomotion blending, weapon grips per job, attack and skill animations with correct priorities (Action over Movement, with upper-body masking where practical), hit reactions, stylized defeat, and facial expression states (via FaceControls or dynamic heads where supported, decal fallback). Test on mobile.

#### Phase 16 — Terrain and Creature Art Pass
- Capitals, dungeons, desert, oasis, jungle, waterfall, and creature and boss silhouettes per CLAUDE.md §18. Set a **performance budget per zone** (part count, triangle count, particle emitters ≤ N, draw distance) and check it with the MicroProfiler on the lowest target device.

#### Phase 17 — Admin/Moderator Panel
- Permission matrix (Owner, Admin, Moderator, with explicit grants such as `events.activate`), panel UI that is **never cloned to unauthorized players** (the server parents it to the PlayerGui of authorized users only), player search and inspection, item, boss, quest, drop-rate and enhancement config editing through ConfigurationService with validation and diffs, Ban API, kick, the reports pipeline (PC-2), and an audit-log viewer.
- **Tests:** every admin remote called as a normal player, as a Moderator for Admin actions, with a spoofed role argument, and with out-of-range config values; every action is audit-logged.

#### Phase 18 — 25+ Event System
- 30 event templates as data (§23 fields), a scheduler (UTC windows, D-12), manual start and stop, stacking rules and caps (§5), announcements, cooldowns, safe disable, and a guarantee that ending an event never mutates stored player data retroactively.
- **Tests:** overlapping events stay within caps; rarity weights renormalize to 100; a server joining mid-event sees it active; a Moderator without the grant can't activate events.

#### Phases 19–26
Follow `PHASE_PROMPTS.md`, with these additions:
- **19 Mobile:** a checklist across phone, tablet, desktop and console aspect ratios; touch targets ≥ 44 px; no essential UI under the top-bar or safe-area insets.
- **20 Balance:** revisit D-01, D-05, D-06, D-08, D-16 and D-18 with playtest data. Build a simulation script in Lune for TTK and time-to-level.
- **21 Security:** run every test from the security skill and add regression tests for each fix.
- **22 Compliance:** produce a questionnaire answer sheet and a risk table. A human submits it.
- **23 Performance:** concurrency targets (e.g. 30 players, 4 dungeon runs, 2 PvP zones active), server heartbeat budget, remote traffic per player per second, memory over a 2-hour soak.
- **24 Gamer review:** P0–P3 triage.
- **25 RC:** release docs. **No automatic publishing.**
- **26 Live ops:** flags, event rotation, content hooks.

---

## 7. Cross-Cutting Checklists

### 7.1 Remote checklist (every remote, every phase)
- [ ] Declared in the Net registry with a schema
- [ ] Types, sizes and enum membership validated, extra arguments rejected
- [ ] Rate limit set
- [ ] Player state validated (alive, zone, not transitioning, owns the referenced object)
- [ ] Permission check (admin and mod remotes)
- [ ] Outcome computed on the server only
- [ ] Failures logged to the security log (throttled)
- [ ] Negative test written

### 7.2 Data-integrity checklist
- [ ] New field has a default, a validator and a repair rule
- [ ] Schema version bumped with a migration if the shape changed
- [ ] Rewards keyed by an idempotent reward ID
- [ ] Mutations are synchronous (no yields between check and write)
- [ ] Behavior on leave and server close verified

### 7.3 Safety checklist
- [ ] No blood, gore, dismemberment or realistic injury
- [ ] No real-world religious or political symbols
- [ ] No free-text UGC shown unfiltered
- [ ] No paid random outcome

### 7.4 Mobile checklist
- [ ] Works in the Device Emulator on a phone and a tablet
- [ ] Touch targets ≥ 44 px, nothing overlapping or clipped
- [ ] State shown with icons or text as well as color

---

## 8. Risk Register

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Scope is very large for the team size | High | High | M3 vertical-slice gate. Cut events 26–30 and the second PvP zone's art polish first if needed. |
| Balance curve breaks the late game (D-01) | High | High | Decide before Phase 2. Lune simulations in Phase 20. |
| Item or reward duplication | Medium | Critical | ProfileStore session locks, no trading, idempotent reward IDs, synchronous mutations, concurrency tests. |
| Admin config corrupts the economy | Medium | High | Validation, versioned config with rollback to the previous version, audit diffs. |
| Maturity rating rises above Mild | Low–Medium | High | Art bible rules, non-graphic defeat, Phase 22 review. |
| Religious-theme backlash | Low–Medium | Medium | PC-1 art rules, fictional lore framing. |
| Single-server instancing limits concurrency | Medium | Medium | `TravelService` abstraction so dungeons and PvP can move to reserved servers later. |
| Mobile performance in dense terrain | High | Medium | StreamingEnabled, per-zone budgets, low-end device tests from Phase 12. |
| Roblox API or policy changes | Medium | Medium | Recheck docs at Phases 17, 22 and 25. Mark every "verify" item. |

---

## Appendix A — Stat Table Under §5 As Written

`HP = 200·1.20^L`, `ATK = 100·1.10^L`, `DEF = 50·1.08^L`, `CritDmg = 0.05%·(L+1)`, `Regen = 0.02%·(L+1)`

| Level | HP | Attack | Defense | Crit Dmg | HP Regen | HP ÷ ATK |
|---:|---:|---:|---:|---:|---:|---:|
| 0 | 200.0 | 100.0 | 50.0 | 0.05% | 0.02% | 2.0 |
| 5 | 497.7 | 161.1 | 73.5 | 0.30% | 0.12% | 3.1 |
| 10 | 1,238.3 | 259.4 | 107.9 | 0.55% | 0.22% | 4.8 |
| 15 | 3,081.4 | 417.7 | 158.6 | 0.80% | 0.32% | 7.4 |
| 20 | 7,667.5 | 672.7 | 233.0 | 1.05% | 0.42% | 11.4 |
| 25 | 19,079.2 | 1,083.5 | 342.4 | 1.30% | 0.52% | 17.6 |
| 30 | 47,475.3 | 1,744.9 | 503.1 | 1.55% | 0.62% | 27.2 |

**Observations (for D-01, D-02 and D-08):**
- Before defense, hits to defeat an equal-level opponent rise from **2 at L0 to about 27 at L30**. That is 13.6× slower fights.
- A +10 weapon (+200 Attack) **triples** L0 Attack but adds only **11.5%** at L30.
- Crit Damage from levels (1.55% at L30) is small next to enhancement's +25% at +10. Base crit gets its meaning from D-02.
- Phase 2 implements these formulas **exactly**, with unit tests that check this table. Any change needs an approved Decision Log entry.

---

## Appendix B — Level Power Scale (D-01 compensation)

`PowerScale(L) = 1.047^L`, applied to outgoing skill and basic-attack damage and to healing. The attacker's (or healer's) level is used. The §5 stat values stay unchanged.

| Level | HP ÷ ATK (raw hits) | PowerScale | Hits with scale (before defense) |
|---:|---:|---:|---:|
| 0 | 2.00 | 1.000 | 2.0 |
| 5 | 3.09 | 1.258 | 2.5 |
| 10 | 4.77 | 1.583 | 3.0 |
| 15 | 7.38 | 1.992 | 3.7 |
| 20 | 11.40 | 2.506 | 4.5 |
| 25 | 17.61 | 3.153 | 5.6 |
| 30 | 27.21 | 3.967 | 6.9 |

Notes:
- Defense (D-05, `K = 200 + 25 × attackerLevel`) adds about 20% mitigation at L0 and about 35% at L30. Skill coefficients greater than 1.0 shorten fights again. Final time-to-kill targets come from the Phase 20 simulation.
- Mob HP and damage tables (Phase 9) get authored against these same scaled numbers.
- Phase 2 unit tests check the raw §5 table (Appendix A). Phase 6 tests check this table.

---

## 9. Immediate Next Steps

1. ~~Creator approves D-01, D-10, D-18~~: **done 2026-10-08**. D-02 to D-04, D-21 and D-22 still use the recommended defaults, and the creator can override them before Phase 2.
2. ~~git init + first commit~~: done (`24c2b64`).
3. ~~Phase 0~~: docs written (`docs/ARCHITECTURE.md`, `docs/DATA_MODEL.md`, `docs/SECURITY_MODEL.md`), with the top security risks designed in detail (`SECURITY_MODEL.md` §5A).
4. Next: **Phase 1**, then follow the amended order (… 4 → **6 → 5** → 7 …).

## 10. Platform Verification Log

Checked against current sources on 2026-10-08. Recheck before Phases 17, 22 and 25.

| Item | Finding | Impact on plan |
|---|---|---|
| **ProfileStore** | It exists. It is loleris's successor to ProfileService, and it uses session locking to prevent duplication across servers. Sources disagree on how long a dead session holds the lock before it's stolen (~80 s vs 5 min). | Use it (D-11). Phase 2 reads the official wiki/source for the steal timeout and adds a test. |
| **Players:BanAsync** | Live engine API. It needs `Players.BanningEnabled` to be on. The config takes `UserIds`, `Duration`, `DisplayReason` (≤ 400 chars, filtered), `PrivateReason`, `ExcludeAltAccounts` and `ApplyToUniverse`. `GetBanHistoryAsync` is also available. Roblox asks creators to post rules and provide an **appeal path**. | Phase 17 uses BanAsync, enables BanningEnabled, adds an appeals process (in `PLAYER_SUPPORT.md`) and a public rules page. |
| **Open Cloud Luau Execution** | It exists. It runs Luau headlessly in a place with full DataModel access, for CI testing. Tasks run up to 5 min, with 10 concurrent per place. There is a reference repo `Roblox/place-ci-cd-demo`. | Optional CI path for Studio-level tests (Phase 1 sets up Lune first; Luau Execution can be added later). |
| **Maturity labels** | Four labels: Minimal, Mild, Moderate, Restricted. **Minimal/Mild** experiences are eligible for **Roblox Kids (5–8)** and **Roblox Select (9–15)**. Moderate covers Select and 16+, and Restricted is 18+ age-verified. Kids/Select also have **additional publishing requirements**. Realistic or excessive violence can be moderated whatever the label. | Supports the 9+ / Mild target. Phase 22 must check the extra Kids/Select publishing requirements. |
