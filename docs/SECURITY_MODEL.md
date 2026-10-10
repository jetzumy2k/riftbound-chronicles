# SECURITY_MODEL.md — Riftbound Chronicles

- **Phase:** 0 (Repository Audit)
- **Date:** 2026-10-08
- **Status:** Phase 6 implemented T-02, T-05, T-06 (shadow mode), T-07, T-08, T-16, T-17, T-33 in CombatService / AntiExploitService / SafeZoneService. Proposed threat model for the rest. Mitigations get implemented in the phases listed. Phase 21 audits them. The top risks (fake defeat, untrusted position) have binding designs in §5A.
- **Baseline assumption:** **every client is malicious.** It can call any remote with any arguments at any rate, read anything replicated to it, and move its own character arbitrarily, because the client owns its character's physics.

---

## 1. Assets to Protect
| Asset | Why it matters |
|---|---|
| Player profiles (level, items, wallet, quests) | Progress loss or duplication destroys trust and the economy |
| Item and stone economy | Duplication or forged rarity breaks progression |
| PvP outcomes and titles | Fairness, leaderboard integrity |
| Admin/moderator powers | Full game control if escalated |
| Live config (drop rates, events) | Economy-wide corruption from one bad write |
| Other players' safety | Harassment, unfiltered text, spawn camping |
| Platform standing | Policy violations risk moderation of the experience |

## 2. Threat Actors
1. **Exploiter**: executes arbitrary client Luau. Calls remotes, edits the local DataModel, teleports or speeds up their character.
2. **Griefer**: no exploits. Abuses game rules (spawn camping, report spam, win-trading).
3. **Rogue or compromised staff**: a Moderator trying Admin actions, or an Admin making harmful config changes.
4. **Infrastructure faults**: DataStore outages, server crashes, disconnects at the worst moment.

## 3. Trust Boundaries
```text
 Client (untrusted) ──RemoteEvent/Function──▶ NetService dispatcher ──▶ Service handlers
   │                                              (validate everything)      │
   └─ character physics (untrusted position) ─▶ AntiExploitService ◀─────────┘
                                                                              ▼
                                             Server state ──▶ ProfileStore / DataStores
```
Inputs that cross the boundary: remote arguments, character CFrame/velocity, `ProximityPrompt` triggers, Touched events involving the client's character, and chat (handled by TextChatService).

---

## 4. Remote Validation Pipeline (NetService, Phase 1)

Each step runs in order, and any failure means **reject, reason code, strike, throttled security log**:

1. **Rate limit**: token bucket per (player, remote), with defaults in the table below. A global per-player budget of 30 msgs/s across all remotes.
2. **Arity**: the argument count equals the schema count. Extra arguments are rejected.
3. **Schema**: exact types (`typeof`), and no `Instance` arguments unless the schema says so (then: class check, still in the DataModel, ancestry check). Strings get a max length and charset. Numbers must be finite (reject NaN and ±inf), within range, and integers where required. Enums must be in the allowlist. Tables: max keys, no metatables, no nested depth > 2, keys of the expected type.
4. **Player state**: profile loaded, alive or not as required, not transitioning, in the required zone, restriction flags clear.
5. **Ownership**: referenced Guids, skills and titles belong to *this* player. Target refs resolve server-side.
6. **Permission**: admin/mod remotes only (§6).
7. **Handler**: wrapped in `xpcall`. Errors are logged with the remote name and never sent to the client verbatim.

Suggested rate defaults (tuned per remote in its phase):

| Remote class | Capacity / refill per s |
|---|---|
| Combat intents (`BasicAttack`, `SkillCast`) | 6 / 4 |
| UI actions (equip, lock, select) | 5 / 2 |
| Economy actions (`EnhanceItem`, `SalvageItems`) | 3 / 1 |
| Social (`PartyInvite`, `SubmitReport`) | 3 / 0.1 |
| Admin actions | 10 / 2 (still audited) |

**Strikes:** `AntiExploitService` accumulates weighted strikes over a decaying window. Thresholds lead to **log**, then **kick**, then **flag for moderator review**. It never auto-bans; Roblox ban decisions stay with humans.

---

## 5. Threat Catalog

Severity: **C**ritical / **H**igh / **M**edium / **L**ow. "Phase" = where the mitigation is implemented.

| ID | Threat (STRIDE) | Attack | Mitigation | Sev | Phase |
|---|---|---|---|---|---|
| T-01 | Tampering | Fake XP / level via remote | No remote accepts XP or level. `LevelService.GrantXP` is server-internal and called only by quest, mob or dungeon handlers. | C | 2 |
| T-02 | Tampering | Fake damage or healing amount | Intent-only remotes. The server computes the amount from server stats, the skill definition and the target. | C | 6/5 |
| T-03 | Tampering | Skill cooldown bypass / spam | Server-side cooldown timestamps per (player, skill), plus rate limits. Client cooldown UI is cosmetic only. | H | 5 |
| T-04 | Elevation | Casting a wrong-job or unowned skill, or a 5th slot | Loadout validated on equip **and** on cast (ownership, job, slot type). | H | 5 |
| T-05 | Tampering | Out-of-range or wall-penetrating attacks | Server range check uses the server-observed positions plus a latency tolerance (≤ 4 studs + speed × RTT, capped). A server raycast checks line of sight. | H | 6 |
| T-06 | Tampering | Speed hack, teleport, noclip, fly | Movement validator with a leaky-bucket violation budget, noclip raycasts, airtime checks and server-granted movement allowances. Rubber-band first, strike second, never kick on the first offense. **Full design: §5A.2.** | H | 6 |
| T-07 | Spoofing | Fake death / self-kill to escape PvP or skip penalties | Defeat is decided **only** by CombatService HP. Server-controlled respawn (`CharacterAutoLoads = false`). Any other death is "unsanctioned" and resolved by state: a reset while combat-tagged counts as a defeat. **Full design: §5A.1.** | H | 6 |
| T-33 | Tampering | Flinging other players or mobs through client-owned physics | Player-to-player collisions off (collision groups). Mobs and bosses get `SetNetworkOwner(nil)` (server-owned). World props anchored. **§5A.4.** | M | 6/9 |
| T-08 | Tampering | Client sets own `Humanoid.Health` / WalkSpeed / JumpPower | Health is display-only (T-07). Movement stats are server-set, and AntiExploit checks observed speed, not properties. | M | 6 |
| T-09 | Tampering | Forged item Guid, equipping or salvaging someone else's item | Guids are looked up in **the caller's** profile only. Unknown means rejected. | H | 7 |
| T-10 | Tampering | Forged rarity, attributes or item creation | `ItemService` is the only item factory. It rolls from server pools. No client field enters an item. | C | 7 |
| T-11 | Tampering | Enhancement level forging, exceeding +10, duplicating stones | The server reads the level from the profile. Check, consume, roll and apply happen synchronously. A per-player in-flight lock. A concurrency test fires 20 requests at once. | C | 8 |
| T-12 | Repudiation/Tampering | Duplicate dungeon, boss, quest or event rewards | `ClaimReward(rewardId)` idempotency (`DATA_MODEL` §4.2). Rewards granted at completion only. | C | 9–11, 18 |
| T-13 | Tampering | Fake quest progress / objective completion | No progress remote. Objectives advance from server events (kills, zone entry, interactions validated by distance). | H | 11 |
| T-14 | Tampering | Remote `Interact` from across the map (fragments, inspect points) | Server distance check (≤ prompt range + tolerance). Each interactable is one-shot per player per quest. | M | 11 |
| T-15 | Elevation | Portal/teleport bypass (entering PvP or dungeons without requirements, teleporting into safe zones mid-combat) | `UsePortal(portalId)` checks the player is within range of *that* portal, plus level/quest requirements, plus no combat tag. Destinations come from server data. Never from client coordinates. | H | 12 |
| T-16 | Tampering | Damage into or out of a safe zone | `SafeZoneService` decides membership from server-side positions (region/OverlapParams) every tick. CombatService rejects when either party is in a safe zone or protected. | H | 12 |
| T-17 | Abuse | Spawn camping | Spawn protection (ends early when the protected player attacks), a bubble when leaving the safe zone, no damage across safe-zone edges, spawn points out of line-of-sight from PvP areas. | M | 12 |
| T-18 | Abuse | Win-trading / alt farming for PvP titles | Credit rules: no credit for the same victim within 30 min, for victims who are protected or > 5 levels below, and a daily cap. Titles come from credited victories only. | M | 14 |
| T-19 | Elevation | Calling admin remotes as a normal player | Admin remotes check the role **server-side** from Roles config on every call. Unauthorized calls get a strike and are always logged (not throttled). The admin UI is never replicated to unauthorized players. | C | 17 |
| T-20 | Elevation | Moderator escalation (economy, drop rates, roles) | Permission matrix (§6) with explicit grants. Role assignment is Owner-only and lives in code config. | C | 17 |
| T-21 | Tampering | Harmful config values (drop rate 1000%, negative stones, +50 enhancement) | Same schema validation as defaults. Sums/ranges enforced. Diff preview. Versioned rollback. Audit before/after. | H | 17 |
| T-22 | Tampering | Event abuse (stacking multipliers, permanent events, unauthorized activation) | Templates only (no free-form events). Duration cap. Stacking caps with renormalized rarity weights. A `events.activate` grant is required. Ending an event never mutates stored data. | H | 18 |
| T-23 | DoS | Remote flooding / huge payloads | Rate limits, global per-player budget, payload size limits, strikes then kick. | M | 1 |
| T-24 | DoS | Expensive server work triggered by the client (pathfinding, raycasts) | Per-cast raycast caps. AI pathfinding is server-scheduled and never triggered directly by a client. | M | 6/9 |
| T-25 | Info disclosure | Reading server config, loot weights, admin lists | Server-only modules live in ServerScriptService/ServerStorage. ReplicatedStorage holds display-safe data only. | M | 1 |
| T-26 | Info disclosure | Seeing other players' private data | Profile views are sent only to the owner. Public attributes are limited (`DATA_MODEL` §6). | M | 2 |
| T-27 | Safety | Unfiltered user text (reports, any custom text) | TextChatService for chat. `TextService:FilterStringAsync` for any user text shown to others (reports). No custom names or titles. | H | 17 |
| T-28 | Safety | Report spam / weaponized reports | Report rate limit, one report per target per 10 min, reports only trigger review (never automatic punishment). | L | 17 |
| T-29 | Integrity | Data loss on shutdown, disconnect or DataStore outage | ProfileStore session lock and auto-save, `BindToClose` release, never play on a blank profile, synchronous mutations. | C | 2 |
| T-30 | Integrity | Asset injection via customization (arbitrary face/accessory IDs) | The client sends preset indices only. The server maps them to asset IDs from an allowlist. | H | 3 |
| T-31 | Tampering | Party/dungeon session hijack (joining others' runs, kicking members) | Party membership is server-side. Invites are UserId-targeted and expire. Only members of a run receive its rewards. | M | 9 |
| T-32 | Tampering | Touched-event abuse (client moving its character into hitboxes, kill bricks, reward triggers) | No rewards or damage from client-owned `Touched` alone. The server re-checks positions and state. | M | 6/9 |

---

## 5A. Detailed Designs for the Top Risks

The two highest-impact risks found in Phase 0 come from Roblox's replication model, which can't be changed. The game must be built to withstand them.

1. **The owning client can kill its own character, and the server sees that death.**
2. **The owning client controls its own character's position.**

The designs below are binding for Phases 6, 9 and 12. Every threshold is a config value (`AntiExploit.*`, `Combat.*`) so it can be tuned without code changes.

### 5A.1 Authoritative defeat and respawn (T-07)

**Principle:** `Humanoid.Health` and `Humanoid.Died` are *display and signal only*. A defeat exists only when **CombatService** says so.

**Setup (server, Phase 6):**
| Setting | Value | Why |
|---|---|---|
| `Players.CharacterAutoLoads` | `false` | Only the server decides when and where a character spawns |
| Character `Humanoid.BreakJointsOnDeath` | `false` | Non-graphic: no falling apart (also a compliance requirement) |
| `StarterCharacterScripts/Health` | Empty placeholder script with that name | Disables Roblox's default regen. CombatService owns regen (D-04) |
| `Humanoid.MaxHealth` / `Health` | Written by the server from CombatService | Mirror for the default health bar and nameplates |
| `StarterGui:SetCore("ResetButtonCallback", false)` | Client, cosmetic | Removes the casual reset path. **Not a security control:** exploiters bypass it |
| `Workspace.FallenPartsDestroyHeight` | Below the lowest map region | Void falls are handled explicitly (below) |

**State machine (per player, server):**
```text
Spawning → Active ⇄ (CombatTagged) → Defeated → Respawning → Protected → Active
```
- **CombatTagged:** set whenever the player deals or takes damage from a hostile source. Clears 10 s after the last hostile event (`Combat.TagSeconds`).
- **Defeated:** entered only when CombatService HP ≤ 0. Effects: immune, all intents rejected, `PvPService.RecordDefeat(victim, creditTo)`, a stylized defeat VFX broadcast. After `Combat.DefeatDelay` (2.5 s): Respawning.
- **Respawning:** the server calls `player:LoadCharacter()` and places the character at the **race safe-zone spawn** (PvP or overworld) or at the **dungeon checkpoint** (D-20, while rejoin charges remain).
- **Protected:** `Combat.SpawnProtectSeconds` (10 s) of immunity. It ends early if the player casts a hostile skill or leaves the safe zone (and then a 3 s exit bubble applies, §5A.3).

**Unsanctioned deaths.** These are `Humanoid.Died` (or a character being removed) while CombatService state ≠ Defeated:
| Situation at that moment | Resolution |
|---|---|
| Not combat-tagged, overworld/safe zone | Treated as a normal reset: respawn at the race safe zone. No penalty. Rate-limited to 1 per 15 s (more is a strike). |
| **Combat-tagged in PvP** | Resolved **as a PvP defeat**. Credit goes to the last hostile damager under the normal anti-farm rules (T-18). The player can't escape a losing fight this way. |
| Combat-tagged in a dungeon | Counts as a dungeon defeat (uses a rejoin charge, D-20). |
| Void fall (Y below the zone floor) | Environment defeat: same rules as the row for the zone they were in. |
| Mid-travel (TravelService grace active) | Ignored: TravelService re-spawns the character at the destination. |

A character that **stays alive locally** while server HP ≤ 0 (a client blocking its own death) doesn't matter: the server is already in the Defeated state, rejects every intent, and forcibly respawns the character with `LoadCharacter` after the delay.

**Leaving the game while combat-tagged** ("combat logging"): the profile releases normally, so there's no data loss. `PvPService` records the leave as a defeat for PvP stats (credit under the same anti-farm rules). The player rejoins in their race safe zone.

**Tests (Phase 6, plus Phase 12 for the PvP rows):** client sets `Humanoid.Health = 0` out of combat (respawns at the safe zone, no penalty); the same while combat-tagged in PvP (defeat recorded, attacker credited once); a client that never dies locally at 0 server HP (forced respawn); spamming resets (rate-limited and a strike); leaving while combat-tagged; a void fall in a dungeon; intents during Defeated and Respawning (all rejected).

### 5A.2 Untrusted position: movement validation (T-05, T-06)

**Principle:** the server never trusts where a client *says* it is. It also can't stop the client moving itself, so it validates what it *observes* and **corrects** instead of punishing first.

**Network ownership:** player characters stay client-owned (needed for responsive movement). Everything else that moves (mobs, bosses, projectiles, platforms) is **server-owned** (`SetNetworkOwner(nil)` or anchored).

**Sampler:** `AntiExploitService` samples each character's `HumanoidRootPart` on the server at **10 Hz** into a ring buffer of 2 s. Players are checked round-robin across frames, so the cost spreads out.

**Checks, per sample pair (Δt):**
| Check | Rule | Exemptions |
|---|---|---|
| **Horizontal speed** | `dist_xz ≤ (maxSpeed × 1.25 + 4) × Δt`, where `maxSpeed` is the server-granted WalkSpeed (or the larger skill allowance) | Movement allowance active |
| **Vertical rise** | Rising faster than the jump arc allows (from the server's JumpPower) plus tolerance | Allowance, launch pads |
| **Noclip** | If displacement > 4 studs, a server raycast from the previous to the current position against the `WorldSolid` collision group. A hit means the player passed through geometry | Travel grace |
| **Airtime (fly)** | Not grounded (downward raycast > 6 studs) for > `AntiExploit.MaxAirSeconds` (3 s) with vertical speed near 0 | Allowance, known drop zones |
| **Zone bounds** | Position inside the region the server believes the player is in (dungeon slot, PvP zone, overworld). Leaving the bounds is impossible without TravelService | Travel grace |

**Violation budget (lag tolerance):** each failed check adds points to a per-player **leaky bucket** that drains at 1 point/s. Budgets:
- **≥ 3 points:** **rubber-band**. The server moves the character back to its last valid sample (`PivotTo`) and logs it.
- **≥ 10 points within 60 s:** a **strike** (counts toward the kick threshold in §4) and moderator flag.
- **One very large teleport** (> 150 studs outside travel grace): immediate rubber-band plus a strike. No legitimate lag produces that distance.

**Movement allowances (prevent false positives):** server systems that move players legitimately *grant* an allowance before acting:
- TravelService teleport: `grantTravelGrace(player, 2 s)` and resets the sample history.
- Dash or leap skills: `grantAllowance(player, {speed = x, seconds = y})`.
- Knockback from the server: an allowance sized to the impulse.
- Respawn: resets the history.

**Rollout modes:** each check has `Off | Shadow | Enforce` (config). Phase 6 ships in **Shadow** mode (log only). Thresholds get tuned with real playtests on mobile and high-ping connections, and switch to **Enforce** before Phase 12 (PvP). Phase 23 re-tunes them.

### 5A.3 Untrusted position: combat range, line of sight and safe zones (T-05, T-15, T-16)

All checks use **server-observed** positions computed *at the time of the request*, never client-sent coordinates:
- **Range:** `distance(attackerHRP, targetHRP) ≤ skill.range + 4 + min(ping, 0.3 s) × targetSpeed`. Ping comes from `player:GetNetworkPing()`. The cap keeps high ping from becoming a range hack.
- **Line of sight:** a server raycast from the attacker's head to the target's torso, against `WorldSolid` only (characters excluded). Skills with `ignoreLOS = true` (e.g. self-heals) skip it.
- **Aimed/directional skills:** the client sends a **unit direction** only. The server builds the shot from the server-observed origin, so a client can't choose where a projectile comes from.
- **Safe zones (`SafeZoneService`):** zones are simple volumes (boxes and cylinders) checked with pure math, which is cheaper than physics queries. Membership is **recomputed inside every combat check** for both parties, not read from a cached flag. Rule: if **either** attacker or target is in a safe zone, or the target is Protected, there's no hostile effect. This blocks attacks into and out of safe zones and prevents edge abuse.
- **Exit bubble:** leaving a safe zone grants 3 s of protection that ends early if the player attacks. This stops campers at the exit.
- **Portals (T-15):** `UsePortal(portalId)` requires the player within 12 studs of *that* portal (server position), not combat-tagged, and meeting the level and quest requirements. The destination comes from server data, with travel grace granted.
- **Interactables (T-14):** the same distance rule as portals (prompt range + 3 studs).

### 5A.4 Physics abuse (T-33)
- Collision group `Players` doesn't collide with `Players`. Exploiters can't fling each other by ramming with their client-owned character.
- Mobs and bosses are server-owned and use their own collision group. Players can block them, but can't push them through walls (the server owns their physics).
- Unanchored loose props are avoided in combat areas. Where physics props exist, they are server-owned or cosmetic-only (client-side clones).

### 5A.5 Acceptance tests added to Phases 6, 9 and 12
| Test | Expected |
|---|---|
| Client sets its WalkSpeed to 100 | Rubber-band within ≤ 1 s; strike after a sustained attempt |
| Client teleports its character 500 studs | Immediate rubber-band plus a strike |
| Client noclips through a dungeon wall | Rubber-band; can't reach the boss room early |
| Client flies (hovering 10 studs up for 5 s) | Airtime violation, rubber-band |
| Attack from 2× skill range, with spoofed high ping | Rejected (ping cap) |
| Attack through a wall | Rejected (LOS) |
| Attack from inside the oasis to outside, and outside to inside | Both rejected |
| Hit a player 1 s after they leave the safe zone | Rejected (exit bubble) |
| `UsePortal` from 200 studs away | Rejected |
| High-ping legitimate player (300 ms, mobile) moving normally for 10 min | **Zero** rubber-bands (false-positive gate) |

---

## 6. Admin Permission Matrix (implemented in Phase 17)

| Permission | Owner | Admin | Moderator |
|---|:-:|:-:|:-:|
| `roles.assign` | ✅ | ❌ | ❌ |
| `config.dropRates` / `config.enhancement` / `config.game` | ✅ | ✅ | ❌ |
| `items.create/grant/remove` | ✅ | ✅ | ❌ |
| `bosses.manage` / `mobs.manage` / `quests.manage` | ✅ | ✅ | ❌ |
| `player.edit` (level, wallet, typed ops only) | ✅ | ✅ | ❌ |
| `events.activate` / `events.schedule` | ✅ | ✅ | grant-only |
| `moderation.kick` | ✅ | ✅ | ✅ |
| `moderation.tempRestrict` (PvP block, event exclusion) | ✅ | ✅ | ✅ |
| `moderation.ban` (Roblox Ban API) | ✅ | ✅ | grant-only |
| `reports.view/resolve` | ✅ | ✅ | ✅ |
| `player.inspect` (read-only) | ✅ | ✅ | ✅ (limited view) |
| `audit.view` | ✅ | ✅ | own actions only |

Roles come from `server/Config/Roles.luau` (UserIds) and optionally group ranks. The Owner is `game.CreatorId` or the group owner. Roles are resolved on join and re-checked on **every** admin call. Any client-supplied role value is ignored.

---

## 7. Logging
| Log | Content | Throttle |
|---|---|---|
| Audit | Every admin/mod action, config change, admin grant: actor, role, action, target, args digest, before/after, JobId, time | None |
| Security | Remote rejections, strikes, repairs on load, anti-exploit corrections | Per player per reason, ≤ 1 entry per 10 s (with a count) |
| Error | Handler and service errors with stack traces | Deduped per message per minute |

Logs never contain chat text. They contain report text only after filtering, and never secrets.

---

## 8. Security Test Plan (cumulative; each phase adds its rows)
For **every** remote:
- Wrong types (string where number, table where string, Instance injection)
- Extra or missing arguments
- NaN, ±inf, negative, huge numbers, 10 KB strings, deeply nested tables
- Another player's Guid, UserId or run id
- Flooding at 100 calls/s
- Valid call in the wrong state (dead, transitioning, wrong zone)

Scenario tests (from `.claude/skills/security`): fake XP, fake damage, fake healing, fake item, fake enhancement, duplicate rewards, fake quest completion, teleport bypass, safe-zone damage, admin remote abuse, moderator escalation, event config abuse. Each is a written test case, automated where the logic is pure and run manually in multiplayer Studio otherwise, before the phase that introduces the feature is accepted.

---

## 9. Residual Risks / Human Review Required
- Movement anti-exploit tolerances trade false positives (lag) against detection. They need tuning with real-device play in Phase 23.
- Roblox platform APIs and policies were checked on 2026-10-08 (`PLAN.md` §10). Ban API: requires `Players.BanningEnabled`; `DisplayReason` is filtered and ≤ 400 chars; Roblox expects public rules and an appeal path. **Re-verify** before Phases 17, 22 and 25.
- No system can fully prevent client-side visual exploits (ESP, auto-aim). Server checks bound their impact. They don't eliminate it.
