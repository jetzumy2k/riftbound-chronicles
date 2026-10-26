# Security review (Phase 21, PLAN.md D-97)

Review by a Roblox multiplayer security engineer, following
`.claude/skills/security` ("assume every client is malicious"). It covers
all 42 client → server remotes (`docs/security/REMOTES.md`, generated) and
the systems added since the last review: events, attribute points, the
Item Mall, buffs and Robux purchases. Threats are numbered as in
`docs/SECURITY_MODEL.md` (T-01 … T-41).

## Pipeline (every remote)
`NetService` runs these checks, in this order, before any handler:
1. a global per-player budget;
2. the remote's own rate limit;
3. the argument count;
4. the schema: types, ranges, lengths and allowed values; unknown fields are rejected, and NaN and infinity never pass;
5. player state (profile loaded, has a race / class, alive);
6. for staff remotes, a permission read from server-side Roles.

Handler errors are caught, and the client never sees the error text. Every rejection is logged and counted as a strike. **Automated:** `security.spec` and `structure.spec` (the allowlist and staff-permission rules).

## The skill's checks, per threat

| Check | Result | How |
|---|---|---|
| Fake damage / healing (T-02) | Blocked | Attack and cast remotes carry intent only (target hint, skill id); the server computes amounts from its own stats, range and line of sight. No player remote has an amount field (`security.spec`). |
| Fake XP (T-01) | Blocked | No remote grants EXP; `LevelService.GrantXP` is server-internal; creature EXP is scaled server-side (D-95). |
| Fake item ids (T-09, T-10) | Blocked | Guids are looked up in the caller's own profile; items are created only by `InventoryService.GrantItem` (no remote reaches it with client rarity); the Mall takes a catalog id only (T-35). |
| Fake rewards (T-12, T-34, T-38) | Blocked | Every reward is a claim (`RewardClaims`): quests, bosses, dungeons, events, chests, Robux receipts (`R:<PurchaseId>`, kept forever). |
| Fake enhancement levels (T-11) | Blocked | The server reads the level and stones from the profile; +10 cap; stones are taken atomically. |
| Fake quest progress (T-13) | Blocked | No progress remote; accept / turn-in check the giver's distance and the quest's state. |
| Fake attribute points / buffs (T-36, T-37) | Blocked | Totals checked against the level; buffs start only by consuming a bag item on the server. |
| Teleport abuse (T-06, T-15, T-40) | **Fixed: was logging only** | Movement validation was in Shadow mode (log only) since Phase 6. Now **Enforce**: speed, teleport and fly cheats are rubber-banded. Every legitimate server move grants grace or an allowance first: travel, war-zone camp push-out, dashes, lunges, run / crouch changes. There are no knockbacks in the game. |
| Admin role spoofing (T-19) | Blocked | Roles come from server config; every staff remote names a permission that NetService checks on each call; the role is never read from the client. |
| Moderator escalation (T-20, T-39) | Blocked, **gap closed** | Permission matrix with explicit grants. New: event bonus rewards need `items.grant`, so a Moderator with the event grant can start events but cannot pay out Mall Points, stones or sets. |
| Event activation abuse (T-22) | Blocked | Templates only; per-template longest run, cooldown, overlap and stage checks; windows stored in validated config; multipliers capped; audited. |
| Remote probing / flooding (T-23, T-41) | **New** | Rate limits as before. Now, requests only a modified client can send (bad arguments, staff remotes, unknown remotes) kick after 20 within a minute. Rate limits, state checks and server errors never count. |

## Never trust the client: verified
- **Stats:** server-side, from the profile (StatsService, attributes and buffs included).
- **Cooldowns:** server timestamps per skill and per consumable.
- **Rarity:** rolled or fixed by the server; never an argument of a player remote.
- **Inventory:** the server profile; Guid look-ups are owner-scoped.
- **Role:** server Roles config.
- **Damage:** server CombatMath.
- **Reward results:** server tables and claims; purchases come from server catalogs.

## Fixes in this phase
1. `AntiExploit.Mode` changed from Shadow to **Enforce** (`Defaults`).
2. **Tamper kick:** `Logic/StrikeRules` and `AntiExploitService`, with new config values `AntiExploit.TamperKickCount` (20) and `TamperWindowSeconds` (60). Logged as `TamperKick`; no ban.
3. **Regression tests:** `tests/pure/specs/security.spec.luau`:
   - no player remote accepts an outcome field;
   - rate, state and string limits on every player remote;
   - purchases by catalog id only;
   - bounded attribute and reward payloads;
   - Enforce mode;
   - the tamper-kick rules.
4. **Generated remote list:** `docs/security/REMOTES.md` (`tools/security/remote_matrix`).
5. **SECURITY_MODEL:** new threats T-34 … T-41, new test-plan rows and residual risks.

## Needs a person (not automated)
- **Rubber-banding:** watch for it with real players and lag. If legitimate players get pulled back, retune `SpeedFactor` / `SpeedToleranceStuds` or fall back to Shadow.
- **Robux purchases:** a live test with real Developer Products before launch. They're on hold by the creator.
- **Ban API:** needs `Players.BanningEnabled`, public rules and an appeal path (SECURITY_MODEL §9).
- **Exploit testing in a test place:** someone should run an exploit-tool test against a private test place (never against live players), to confirm the rubber-band and the tamper kick behave as designed.
