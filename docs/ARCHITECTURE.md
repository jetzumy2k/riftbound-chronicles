# ARCHITECTURE.md — Riftbound Chronicles

- **Phase:** 0 (Repository Audit)
- **Date:** 2026-10-08
- **Status:** Proposed. D-01, D-10 and D-18 approved 2026-10-08. Other decisions use the recommended defaults from `PLAN.md` §4.
- **Companion docs:** `docs/DATA_MODEL.md`, `docs/SECURITY_MODEL.md`, `PLAN.md`

---

## 1. Audit of the Current Repository

### 1.1 Contents
```text
riftbound-chronicles/
├── .claude/skills/        9 review-persona skills (architecture, security, data-integrity,
│                          game-design, roblox-compliance, art-animation, qa-gamer,
│                          mobile-ui, live-ops)
├── docs/
│   ├── PHASE_PROMPTS.md   Phases 0–26
│   └── README.md          Pack overview + two documented design corrections
├── CLAUDE.md              Master spec
├── PLAN.md                Review, decision log, amended phase order
└── LICENSE                MIT (from GitHub initial commit)
```
Git: `main` tracks `origin` = `github.com/jetzumy2k/riftbound-chronicles`.

### 1.2 Findings
| Area | Current state |
|---|---|
| Existing architecture | **None.** No Luau source, no `.rbxl/.rbxlx` place file, no Rojo project. |
| Existing systems | None implemented. All systems are specified only in `CLAUDE.md`. |
| Folder structure | Documentation only (above). |
| Dependencies | None. No `wally.toml`, `rokit.toml`/`aftman.toml`, `selene.toml` or `stylua.toml`. |
| Server/client/shared boundaries | Not yet in code. Defined in this document (§3). |
| Remotes | None exist. The planned map is in §6. |
| Data model | Outlined in `CLAUDE.md` §26. Fully specified in `docs/DATA_MODEL.md`. |
| Tests | None. Strategy in §10. |
| Line endings | Files are LF in git, and Windows checkout warns LF→CRLF. Phase 1 adds `.gitattributes` (`* text=auto eol=lf`). |

### 1.3 Technical debt in the specification
Since there is no code yet, the only debt is inconsistencies in the specification. Each one is resolved here or in `PLAN.md`:

| # | Issue | Resolution |
|---|---|---|
| TD-1 | `CLAUDE.md` §24 names a service `TeleportService`, which shadows the Roblox engine service. | Renamed **`TravelService`** in this architecture. |
| TD-2 | `ProfileServiceAdapter` names a superseded library. | Renamed **`PersistenceAdapter`** (wraps ProfileStore, D-11). |
| TD-3 | `CLAUDE.md` §9 says to finalize rarity names "in Phase 3," but Phase 3 is the Race phase. | Rarity enum is finalized in Phase 1 (D-22). |
| TD-4 | Phase 5 (Skills) needs Phase 6 (Combat resolver). | Execution order 4 → 6 → 5 (`PLAN.md` §6). |
| TD-5 | Around 10 systems required by the spec have no phase (currency, titles, parties, etc.). | Assigned in `PLAN.md` §5. |
| TD-6 | Stat units are ambiguous (crit, regen, defense). | D-02 to D-05. Formulas live in `Shared/Logic/StatFormulas`. |

---

## 2. Runtime Topology (D-10 approved 2026-10-08)

**Approved: one Roblox place for v1.** Everything below runs in a single server instance:

```text
Server (one place, StreamingEnabled)
├── Angel Capital + Angel Safe Zone ─┐
├── Devil Capital + Devil Safe Zone ─┤ static world (Workspace)
├── Training Grounds ────────────────┤
├── Desert Rift (PvP) + Oasis Safe ──┤
├── Jungle Rift (PvP) + Falls Safe ──┘
└── Dungeon Instances  (cloned per session from ServerStorage templates into
                        reserved, spatially isolated slots far from the main world;
                        destroyed when the session ends)
```

Reasons:
- One profile session per player, so no cross-server profile handoff while there is no matchmaking layer yet.
- One codebase and place, which is simpler to test locally (Studio multi-client).
- All zone transitions go through **`TravelService`**. A later move of dungeons or PvP to `TeleportService:ReserveServer` is a change inside TravelService (plus a profile-release/handoff step) and doesn't spread through gameplay code.

Proposed limits (tuned in Phase 23): `MaxPlayers` around 24, concurrent dungeon slots ≤ 6, each slot in its own region with a ≥ 2,000-stud gap.

---

## 3. Authority Boundaries

| Owner | Owns | Never owns |
|---|---|---|
| **Server** | All persistent data. XP, level, stats, HP and Focus (authoritative values), damage, healing, crits, cooldowns, targets, loot, item creation, enhancement, inventory, equipment, quests, PvP results, zone membership, travel, events, roles and permissions, config. | Input feel, camera, local VFX. |
| **Client** | Input, camera, UI, animation playback, cosmetic VFX/SFX, prediction of *visuals only* (e.g. playing the cast animation right away). | Any outcome. The client sends **intents** and the server replies with **results**. |
| **Shared** (ReplicatedStorage) | Display-safe definitions, enums, types, constants, pure formulas (used by the client only to *display* previews; the server recomputes). | Secrets, server config overrides, role lists, drop-table internals beyond what the UI shows, AI logic. |

Rules:
1. Code under `ServerScriptService`/`ServerStorage` is never `require`d by the client. Shared code never `require`s server code.
2. The server is the only one that creates remotes (§6).
3. Physics network ownership of a player's own character belongs to that client, so **positions are untrusted**. The server checks movement, range and zone membership (`docs/SECURITY_MODEL.md` §5A.2–5A.3).
4. Authoritative HP lives in `CombatService`. `Humanoid.Health` is a **server-written mirror** for display. Character death that doesn't come from CombatService is resolved by the unsanctioned-death rules (`docs/SECURITY_MODEL.md` §5A.1).

---

## 4. Source Layout (Rojo)

Created in Phase 1. Rojo maps `src/` like this:

```text
src/
├── server/                         → ServerScriptService.Server
│   ├── init.server.luau            Bootstrap: Loader.start(Services)
│   ├── Loader.luau                 Ordered Init()/Start() with xpcall boundaries
│   ├── Services/                   One ModuleScript per service (§5)
│   ├── Persistence/
│   │   ├── PersistenceAdapter.luau ProfileStore wrapper (D-11)
│   │   ├── ProfileTemplate.luau
│   │   ├── Migrations/             v1_to_v2.luau, …
│   │   └── ProfileValidator.luau   validate + repair
│   └── Config/                     Server-only defaults: Roles, LootTables, EnhancementRates,
│                                   EventSchedule, Limits (never replicated)
├── serverstorage/                  → ServerStorage
│   ├── DungeonTemplates/  Mobs/  Bosses/  Props/
├── shared/                         → ReplicatedStorage.Shared
│   ├── Types.luau  Enums.luau  Constants.luau
│   ├── Definitions/                Item/Skill/Job/Quest/Enemy/Boss/Event (display-safe)
│   ├── Logic/                      Pure modules: StatFormulas, XPTable, Validation, Schema,
│   │                               RateBucket, LootMath, AttributeMath, EventMath
│   ├── Net/                        Registry.luau (remote specs), Client.luau, Server.luau
│   └── Util/                       Signal, Trove, Promise-lite, Log
├── client/                         → StarterPlayer.StarterPlayerScripts.Client
│   ├── init.client.luau
│   ├── Controllers/                (§5.3)
│   └── UI/                         Components/, Screens/, Theme.luau, SafeArea.luau
└── starterchar/ (optional)         → StarterPlayer.StarterCharacterScripts (animation overrides)
tests/
├── pure/                           Lune-run specs for shared/Logic and server pure modules
└── studio/                         Jest-Lua/TestEZ specs needing Roblox APIs
```

Toolchain (Phase 1): Rokit, Rojo 7, Wally (ProfileStore, test framework), StyLua, Selene, luau-lsp, Lune.

---

## 5. Services and Controllers

### 5.1 Server service layers
A service may `require` services in **its own or lower layers only**. To notify a higher layer, it fires a Signal that the higher layer subscribes to. This prevents circular dependencies.

| Layer | Services | Responsibility |
|---|---|---|
| **L0 Core** | `Logger`, `ConfigurationService`, `RateLimitService`, `AuditLogService`, `NetService` (dispatcher) | Config (defaults + DataStore overrides + MessagingService invalidation), token buckets, audit and security logs, remote validation pipeline |
| **L1 Data** | `PersistenceAdapter`, `PlayerDataService` | Profile session lifecycle, load/validate/repair/migrate, typed mutators, the `ClaimReward(rewardId, fn)` idempotency helper |
| **L2 Identity & Progression** | `StatsService`, `LevelService`, `RaceService`, `JobService` | Pure stat formulas plus gear aggregation, XP grants (server-internal API), race/job selection and validation |
| **L3 Items & Economy** | `ItemService`, `InventoryService`, `EquipmentService`, `EnhancementService`, `LootService`, `WalletService` | Item factory (only creator of item instances), inventory cap and salvage, equip rules, enhancement state machine, loot rolls |
| **L4 Combat** | `CombatService`, `SkillService`, `SafeZoneService`, `AntiExploitService` | HP/Focus/defense/crit/regen, target validation, defeat, skills/loadout/cooldowns, server-side zone membership, movement sanity |
| **L5 World** | `TravelService`, `MobService`, `BossService`, `DungeonService`, `PartyService`, `PvPService` | Zone travel and portals, NPC AI, boss phases, dungeon sessions, parties, PvP rules and normalization |
| **L6 Meta** | `QuestService`, `TitleService`, `EventService`, `AnalyticsService` (wrapper) | Quests and story flags, titles and cosmetics, live events and multipliers, funnel telemetry |
| **L7 Operations** | `AdminService`, `ModerationService`, `ReportService` | Permission matrix, admin actions, ban/kick, reports |

**Lifecycle:** the Loader calls each service's `Init()` (synchronous: wiring only, no yields) in layer order, then `Start()` (may spawn loops). Any failure is logged with the service name. A failure in an **L0–L1** service stops the boot and sets the server to "maintenance": players get kicked with a friendly message rather than playing without saves.

**Player lifecycle:** `PlayerDataService` loads the profile, then fires `ProfileLoaded(player)`. Services set up per-player state on that signal, *never* on `PlayerAdded` directly. When a player leaves, services clean up, then the profile is released. `BindToClose` releases all profiles and flushes audit logs.

### 5.2 Engine services used (wrapped, never called ad hoc in gameplay code)
| Engine service | Wrapped by |
|---|---|
| DataStoreService | PersistenceAdapter (ProfileStore), ConfigurationService, AuditLogService |
| MessagingService | ConfigurationService, EventService (config/event invalidation) |
| MemoryStoreService | optional: cross-server event state / rate data (Phase 18+) |
| TeleportService | TravelService only (future multi-place) |
| TextService / TextChatService | ReportService (filtering), chat defaults |
| Players:BanAsync | ModerationService |
| AnalyticsService | AnalyticsService wrapper |
| HttpService | GUIDs; optional audit sink behind a feature flag |

### 5.3 Client controllers
`UIController` (screen stack, safe area, input mode), `InputController` (keyboard/gamepad/touch to intents), `CombatController` (soft-lock target, basic attack intent, hit/defeat visuals), `SkillBarController`, `InventoryController`, `EquipmentController`, `QuestController`, `CharacterController` (animation state, facial expressions), `CustomizationController` (race/face preset selection), `TravelController` (portal prompts, loading transitions), `NotificationController`, `EventController`, `AdminController` (**only loaded if the server parents the admin UI to this player**).

Controllers only call `Net.Client` and read replicated state. They never require server modules.

---

## 6. Networking

### 6.1 Remote creation
`Shared/Net/Registry.luau` declares every remote as data:
```lua
-- illustrative shape, implemented in Phase 1
SkillCast = {
    kind = "Event",             -- client→server intent
    schema = { "SkillId", "TargetRef?" },
    rate = { capacity = 6, refillPerSec = 4 },
    state = { "Alive", "NotTransitioning" },
    permission = nil,
}
```
At boot the server creates one `Folder ReplicatedStorage.Remotes` with the declared instances. The client waits for the folder. **Nothing else** creates RemoteEvents or RemoteFunctions. Server→client traffic uses RemoteEvents (no server-invoked RemoteFunctions). Client→server requests that need a reply use a RemoteFunction or a request-ID plus reply event (decided per remote in Phase 1. RemoteFunctions are allowed client→server only, with a bounded server handler).

Validation pipeline (`NetService`): **rate limit → arity check (no extra args) → schema → player state → permission → handler (xpcall) → result**. Every rejection gets a reason code, increments a per-player strike counter (`AntiExploitService`), and goes to the security log with throttling. Details are in `docs/SECURITY_MODEL.md` §4.

### 6.2 Planned remote map
C→S means an intent from client to server. S→C means a push from server to client. The phase is when the remote is introduced.

| Remote | Dir | Args (schema) | Phase |
|---|---|---|---|
| `ClientReady` | C→S | — | 1 |
| `Notify` | S→C | {kind, textKey, params} | 1 |
| `ProfileSnapshot` | S→C | replicated profile view (`DATA_MODEL` §6) | 2 |
| `ProgressionUpdate` | S→C | {Level, Experience, XPToNext, LevelsGained} (typed per-domain updates replace a generic path/value delta, so every payload stays schema-validated) | 2 |
| `SelectRace` | C→S | Race enum, FacePresetId (int, must belong to the race). One-shot; `ProfileLoaded` state | 3 |
| `SelectJob` | C→S | Job enum. One-shot; `ProfileLoaded` + `HasRace` states | 4 |
| `BasicAttack` | C→S | optional target Model; server auto-targets otherwise. States: ProfileLoaded, HasJob, Alive | 6 |
| `UseConsumable` | C→S | ItemDefId (stackable allowlist) | 6/7 |
| `CombatEvent` | S→C | {kind: Damage/Heal/Defeat/Revive, target Model, amount?, crit?} to players within `Combat.RelevanceRadius` | 6 |
| `EquipSkill` | C→S | SkillId, SlotIndex (1–4) | 5 |
| `SkillCast` | C→S | SkillId, TargetRef? / AimDirection (unit vector) | 5 |
| `EquipItem` / `UnequipItem` | C→S | ItemGuid / SlotEnum | 7 |
| `LockItem` / `SalvageItems` | C→S | ItemGuid / {ItemGuid ≤ 20} | 7 |
| `EnhanceItem` | C→S | ItemGuid, StoneType enum | 8 |
| `PartyInvite` / `PartyRespond` / `PartyLeave` | C→S | UserId / bool / — | 9 |
| `DungeonEnter` / `DungeonLeave` | C→S | DungeonId / — | 9 |
| `DungeonState` | S→C | {runId, objective, progress} | 9 |
| `LootGranted` | S→C | {itemSummaries} | 10 |
| `QuestAccept` / `QuestTurnIn` | C→S | QuestId | 11 |
| `DialogueChoice` | C→S | DialogueNodeId, ChoiceIndex | 11 |
| `Interact` | C→S | InteractableRef (fragments, NPCs, inspect points) | 11 |
| `EquipTitle` / `EquipCosmetic` | C→S | TitleId / CosmeticId (owned) | 11 |
| `UsePortal` | C→S | PortalId | 12 |
| `ZoneState` | S→C | {zone, safe, protectedUntil} | 12 |
| `EventState` | S→C | active events (display) | 18 |
| `SubmitReport` | C→S | TargetUserId, ReasonEnum, Text? (≤ 200, filtered) | 17 |
| `Admin_*` | C→S | one remote per admin action, each with schema + permission | 17–18 |

There is **no remote** that accepts damage, healing, XP, level, stats, loot, rarity, enhancement result, quest progress, cooldown state, role, or position/teleport destination.

### 6.3 Replication strategy
- **Small per-player public state** (Level, Race, Job, equipped Title, PvP-protected flag) goes in **attributes** on the `Player` (server-written). This is cheap and readable by all clients for nameplates.
- **HP/Focus**: the server writes attributes on the character (`HP`, `MaxHP`, `Focus`) plus the mirrored `Humanoid.Health`.
- **Private state** (inventory, quests, wallet): the `ProfileSnapshot` on load, then typed per-domain update events (`ProgressionUpdate` in Phase 2; later phases add their own). These are never placed in instances other clients could read.
- **Combat feedback**: `CombatEvent`, batched and sent only to players within the relevance radius.

---

## 7. Configuration and Live Ops
- **Defaults** live in code (`server/Config/*`), are versioned in git, and are validated at boot. An invalid default stops the boot during development.
- **Overrides** live in the DataStore `RC_Config_v1` with key `override`, as `{version, changedBy, changedAt, values}`. They are validated with the same schema as defaults. An invalid override gets rejected, and the server keeps the last good version.
- **Propagation** happens through a MessagingService topic `config` carrying `{version}`. Servers reload if the incoming version is newer. A poll every 5 minutes is the fallback.
- **Feature flags** (`Flags.*`) are part of config. Every system checks its flag at its entry point.
- **Rollback**: the previous N=10 override versions are kept, and the Owner/Admin can revert to one (with an audit log entry).
- **Scheduled events** use UTC windows in config, so every server computes "active" the same way without sending messages (D-12).

---

## 8. Performance Risks and Budgets

| Risk | Mitigation | Budget (initial, revisited in Phase 23) |
|---|---|---|
| NPC AI heartbeat cost | One central AI scheduler (not a script per mob). Tick ≤ 10 Hz, idle mobs sleep when no player is within 150 studs. Pathfinding computed only on demand and cached. | ≤ 2 ms/frame server AI at 60 active mobs |
| Remote spam | Token buckets per remote. Combat events batched per frame and filtered by relevance. | ≤ 20 C→S msgs/s per player sustained |
| Raycast cost for hit validation | Server raycasts only for confirmed casts, with filtered RaycastParams and a per-cast count limit. | ≤ 8 raycasts per cast |
| Dungeon instance churn | Clone from templates and destroy on end. Pool slots. Check the instance count after cleanup. | Instance count returns to ±1% of baseline |
| Particles/VFX on mobile | Client-side VFX quality tiers. Emitters capped per effect. | ≤ 200 live particles per effect on low tier |
| Terrain/world memory | StreamingEnabled with `StreamingMinRadius`/`TargetRadius` tuned. Persistent models only for portals and safe zones. | Client memory ≤ 1.2 GB on a low-end phone (measure in Phase 23) |
| DataStore budget | ProfileStore auto-save. Audit logs batched every 30 s. Config read on version change only. | Within DataStore per-server limits with ≥ 50% headroom |
| Server memory leaks | Trove/cleanup per player, per run and per event. A soak test in Phase 23. | No growth over a 2-hour soak |

---

## 9. Failure Cases (designed, not yet implemented)
| Failure | Behavior |
|---|---|
| DataStore outage at join | ProfileStore retries. On final failure, kick with "Couldn't load your save. Please rejoin," and **never** play on a blank profile. |
| Profile session locked elsewhere | ProfileStore steals the session after its timeout. The player sees a waiting message. |
| Server shutdown mid-dungeon | `BindToClose` releases profiles. In-progress run rewards are not granted (they are granted only at completion), so nothing duplicates. |
| Disconnect mid-enhancement | The mutation is synchronous with no yield, so it either happened fully before the leave or didn't happen. |
| Config override invalid | Rejected and logged, and the last good version stays active. |
| Service init error | L0–L1 failure: maintenance mode. L2+ failure: that feature's flag is forced off and an error is logged. |

---

## 10. Testing Strategy
- **Pure (Lune, every phase):** everything in `shared/Logic` and pure server modules, such as stat table, XP table, schema validator, token bucket, loot distribution (statistical), attribute roller (fuzz), enhancement state machine, permission matrix, and event math.
- **Studio (Jest-Lua/TestEZ):** service integration with mocked DataStores (ProfileStore mock mode).
- **Manual multiplayer:** Studio "Local Server, 2–4 players", the Device Emulator (phone/tablet), reconnect, and defeat/teleport flows, following the phase checklists in `PLAN.md` §7.
- **Adversarial:** for every remote, a negative test that sends wrong types, extra arguments, out-of-range values, other players' GUIDs and rate floods (`docs/SECURITY_MODEL.md` §8).

---

## 11. Open Decisions Affecting This Document
| ID | Topic | Default used in this doc |
|---|---|---|
| D-10 ✅ | Single vs multi-place | **Approved:** single place (§2) |
| D-11 | Persistence library | ProfileStore |
| D-12 | Cross-server config | DataStore + MessagingService (§7) |
| D-13 | Audit-log storage | DataStore by day, 90 days |
| D-21 | Characters per account | One |
| D-22 ✅ | Rarity names | Standard, Uncommon, Rare, Epic, Legendary, Mythical |
