# Performance and multiplayer review (Phase 23, PLAN.md D-102)

Scope from `docs/PHASE_PROMPTS.md` Phase 23: NPC AI, remote frequency,
memory, instance count, particles, terrain, streaming, DataStore usage,
concurrent dungeons, PvP concurrency, mobile performance.

## 1. Targets (one server)

| Item | Target | Where it is checked |
|---|---|---|
| Players | 30 | `PerfBudget.TARGET_PLAYERS` |
| Server frame time | average ≤ 18 ms, 95th percentile ≤ 25 ms (60 Hz = 16.7 ms) | PerfService report |
| Server memory | ≤ 2,500 MB | PerfService report |
| Remote events sent | ≤ 30 per player per second | PerfService report (NetService counters) |
| Remote events received | ≤ 15 per player per second | PerfService report; every remote is also rate-limited (REMOTES.md) |
| Parts per character outfit | ≤ 320 (anime characters are about 250-300) | PerfService report |
| World parts / lights / emitters | per zone, D-82 budgets | `World/BudgetAudit` at startup |

**The report.** Every `Perf.ReportSeconds` (60 s, admin-configurable) the
server logs one line, for example:

```
perf: players=8 frame avg 16.8 ms p95 19.2 ms, memory 1310 MB, remotes/player/s out 6.2 in 3.1, creatures 212 live 37 awake, largest outfit 288 parts
```

Any value over its limit adds a warning line: `perf over budget: <field> <value> > <limit>`.

## 2. Audit

| Area | Finding | Result |
|---|---|---|
| **NPC AI** | One scheduler (MobService) at 8 Hz (`Mobs.TickHz`, max 10); idle creatures sleep with no player within 150 studs; server-owned physics; one `pcall` per awake creature so one bad creature can't stop the rest. Bosses tick at 5 Hz. | OK. The report now shows live / awake creatures. |
| **Server loops** | Every service loop is a timed `task.wait` (0.25-30 s) or the AI tick; only AntiExploitService and PerfService use Heartbeat. No busy loops. | OK |
| **Remote frequency** | Combat events and telegraphs go only to players within `Combat.RelevanceRadius`; profile / inventory / quest updates go to the owner only; one `FireAllClients` wrapper, used for nothing per frame. Every client→server remote has a token bucket plus a global budget per player; 20 rejects in 60 s kick (D-97). | OK. Traffic is now counted both ways. |
| **Memory / leaks** | Per-player tables are cleared on `PlayerRemoving` in every service except one: PvPService's spawn-camp notice times, **fixed**. Client controllers that track characters drop them when they leave (ExpressionController, MobLevelController, the new detail controller uses a weak table). | Fixed 1 small leak |
| **Instance count** | The world stays inside the D-82 budgets (capitals ~860 / 750 parts, war zones ≤ 7,000, dungeons ~5,400). New: anime characters are **about 250-300 parts each** (D-100), so 30 players add roughly 8,000 parts. All are massless, non-colliding, non-queryable welded parts (no physics cost beyond the weld), but each one is drawn. | **Detail by distance added** (section 3) |
| **Particles / lights** | Zones: within the D-82 emitter budgets. Characters: one aura emitter (5 per second), a sword sparkle on Legendary+ weapons, two small lights (halo, sword). | They switch off on characters past 55 studs |
| **Terrain** | Decoration on (animated grass), terrain strata and voxel fills written once at startup (D-83 to D-85); no runtime terrain writes. | OK |
| **Streaming** | `StreamingEnabled`, target radius 1,024 studs (draw distance); Roblox lowers it on low-memory devices. | OK; lower to 512 if the phone test shows memory pressure |
| **DataStore** | ProfileStore: one load per join, its own periodic autosave and a save on leave / shutdown; `SaveNow` only after a Mall purchase receipt. No per-action writes. | OK |
| **Concurrent dungeons** | One persistent copy of the dungeon per realm (D-42), shared by every party; creatures respawn on timers. Load is bounded by players, not by the number of runs. | OK |
| **PvP concurrency** | Two war zones, each one map for everyone; spawn protection, safe zones and victory credit checks run in a 0.25 s sweep. | OK |
| **Mobile** | Every screen has a tested layout (MOBILE_CHECKLIST.md); character detail drops by distance; particles small. A real-phone frame-rate check needs a published place (section 4). | Code done; device test open |

## 3. Changes in this phase

- **`Logic/DetailRules`** (tested): a part's detail class from its size
  (under 0.35 studs: fine; under 0.8: medium), and the level for a camera
  distance with an 8-stud margin so characters don't flicker at the borders.
- **Builders tag parts** (`Kit.part` sets `RC_Lod`); the eyes, brows and
  mouth always show, only their shines and lash flicks drop.
- **`CharacterDetailController`** (client): twice a second, for every other
  player and the commanders: past 55 studs the fine parts are hidden and
  the outfit's particles and lights switch off; past 120 studs the medium
  parts are hidden too. Your own character always keeps full detail.
  Local only, nothing is sent to the server.
- **`PerfService`** + **`Logic/PerfBudget`** (tested): the report above.
  `NetService:TakeTraffic` (event counters), `MobService:Counts` (live /
  awake creatures), config `Perf.ReportSeconds`.
- **Leak fix:** PvPService forgets a leaver's spawn-camp notice time.

## 4. Test plan

### In Studio (no publishing)
1. **Test** tab → *Clients and Servers* → 4 to 8 players → Start.
2. In the Server window's Output, read the `perf:` line each minute.
   Expect frame average ~16.7 ms, no `over budget` warnings.
3. Walk one player away from the others: past ~55 studs their gems,
   trims, eye shines and sparkles disappear; past ~120 studs the small
   plates and feathers too; walking back restores everything with no
   flicker at the border.
4. Press **Ctrl+F6** (MicroProfiler) on a client and on the server during
   a fight with several creatures: no single frame label stands out.
5. **F9** → Memory / Network: client memory steady while walking between
   zones; network receive in the low KB/s.
6. **Leaks:** have a test player join and leave 10 times; the server's
   memory in the `perf:` line returns to about the same value.

### Needs a private published test place
7. **Phone:** join from a phone; check frame rate in the capital, in a
   dungeon fight and in a war zone (Roblox's settings → Performance stats).
8. **Real lag:** play with a friend far away; watch for rubber-banding
   (Phase 21 movement checks).
9. **Load:** as many testers as possible at once; read the `perf:` lines.
10. **Soak:** leave a server running 2 hours with players; memory in the
    `perf:` lines should level off, not climb steadily.

## 5. Open items (owner: creator)

- Steps 7-10 need a **private** published test place (not public).
- If phones struggle: lower `StreamingTargetRadius` to 512, or lower
  `DetailRules.NEAR` / `FAR`.
- A part-count cut for the anime outfits (merging trims) is possible if
  the 30-player test shows rendering cost.
