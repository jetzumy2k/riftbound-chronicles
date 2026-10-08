# DATA_MODEL.md — Riftbound Chronicles

- **Phase:** 0 (Repository Audit)
- **Date:** 2026-10-08
- **Status:** Proposed. Schema v1 gets implemented in Phase 2. Fields owned by later phases ship in v1 as empty defaults, so later phases fill them without a migration where possible.
- **Existing data model:** none (no code). This document is the source of truth until code exists. After that, the code plus this document must agree.

---

## 1. Storage Map

| Store | Engine API | Key scheme | Contents | Writer |
|---|---|---|---|---|
| `RC_Profiles_v1` | DataStore via **ProfileStore** (D-11) | `Player_<UserId>` | Player profile (§2) | PersistenceAdapter only |
| `RC_Config_v1` | DataStore | `override`, `history_<n>` | Config overrides plus the last 10 versions | ConfigurationService (through AdminService) |
| `RC_Audit_v1` | DataStore | `<YYYY-MM-DD>_<JobId>_<seq>` | Batched audit entries (≤ 3 MB per key) | AuditLogService |
| `RC_Security_v1` | DataStore | `<YYYY-MM-DD>_<JobId>_<seq>` | Throttled security rejections | AuditLogService |
| `RC_Reports_v1` | DataStore | `<YYYY-MM-DD>_<reportId>` | Player reports | ReportService |
| Bans | **Roblox Ban API** (`Players:BanAsync`) | Roblox-managed | Ban records | ModerationService |
| Roles | **Code config** (`server/Config/Roles.luau`), optional group-rank mapping | — | Owner/Admin/Moderator UserIds and grants | git (Owner) |
| Event state (optional) | MemoryStore | `events` | Manual event activations across servers | EventService |

The `_v1` suffix on store names means a hard reset is never needed: a fundamentally new layout would get a new store plus a one-time migration.

---

## 2. Player Profile — Schema v1

Luau-style types. All numbers are integers unless marked `number`.

```lua
type Profile = {
    SchemaVersion: number,           -- 1
    CreatedAt: number,               -- os.time() UTC
    LastLoginAt: number,

    -- Identity (Phase 3/4) -------------------------------------------------
    Race: RaceId?,                   -- nil until chosen; "Angel" | "Devil"
    FacePreset: number,              -- index into server allowlist, default 1
    Job: JobId?,                     -- nil until chosen; "Healer" | "Warrior" | "Archer"

    -- Progression (Phase 2) ------------------------------------------------
    Level: number,                   -- 0..30
    Experience: number,              -- 0 .. XPToNext(Level)-1 ; 0 at Level 30
    TotalExperience: number,         -- lifetime, for audits/analytics

    -- Skills (Phase 5) ------------------------------------------------------
    OwnedSkills: { [SkillId]: true },
    EquippedSkills: {                -- 3 regular + 1 special
        Regular: { SkillId? },       -- length ≤ 3, no duplicates
        Special: SkillId?,
    },

    -- Items (Phase 7/8) -----------------------------------------------------
    Inventory: { [ItemGuid]: ItemInstance },   -- gear only; cap 150 (D-09)
    Equipment: { [SlotId]: ItemGuid? },        -- Weapon, Helm, Chest, Legs, Boots, Accessory
    Stackables: { [StackableId]: number },     -- stones, fragments, consumables, quest items
    Wallet: { Gold: number, PvPMarks: number },

    -- Quests & story (Phase 11) ---------------------------------------------
    QuestState: { [QuestId]: QuestProgress },
    StoryFlags: { [StoryFlagId]: true },
    ClaimedRewardIds: { [RewardId]: number },  -- value = claimedAt; see §4

    -- Cosmetics (Phase 11/14) -----------------------------------------------
    Titles: { [TitleId]: true },
    EquippedTitle: TitleId?,
    Cosmetics: { [CosmeticId]: true },
    EquippedCosmetics: { [CosmeticSlot]: CosmeticId? },

    -- PvP (Phase 12/14) -----------------------------------------------------
    PvPStats: {
        Victories: number,           -- credited defeats (anti-farm rules applied)
        Defeats: number,
        Participations: number,
        RecentVictims: { [string]: number },  -- tostring(UserId) -> lastCreditAt; pruned >30 min
        DailyCredit: { Day: number, Count: number },
    },

    -- Events (Phase 18) -----------------------------------------------------
    EventProgress: { [EventInstanceId]: { Score: number, Claimed: boolean, ExpiresAt: number } },

    -- Moderation flags (Phase 17) -------------------------------------------
    Restrictions: { [RestrictionId]: number },  -- e.g. PvPBlocked -> untilUnix

    -- Settings (client-requested, server-validated) ------------------------
    Settings: {
        MusicVolume: number,         -- 0..100
        SfxVolume: number,           -- 0..100
        GraphicsTier: "Auto" | "Low" | "Medium" | "High",
        ShowDamageNumbers: boolean,
    },

    -- Lifetime counters (analytics/achievements) ----------------------------
    Counters: { [CounterId]: number },          -- whitelisted keys only
}
```

### 2.1 Item instance
```lua
type ItemInstance = {
    Guid: string,                    -- HttpService:GenerateGUID(false), server only
    DefId: ItemDefId,                -- must exist in ItemDefinitions
    Rarity: RarityId,                -- Standard|Uncommon|Rare|Legendary|Mythical
    ItemLevel: number,               -- 0..30
    Attributes: { { Stat: StatId, Value: number } }, -- rolled; count by rarity; pool by category/job
    Enhancement: number,             -- 0..10
    Locked: boolean,                 -- blocks salvage
    Source: SourceTag,               -- "Quest:Q1" | "Dungeon:<runId>" | "Boss:<runId>" | "PvPBoss:<id>" | "Admin:<auditId>" | "Event:<id>"
    CreatedAt: number,
}
```
Enhancement doesn't store derived stats. Effective stats are computed from `DefId + ItemLevel + Attributes + Enhancement` using the rules in config, so a balance change applies retroactively in a consistent way.

### 2.2 Quest progress
```lua
type QuestProgress = {
    Status: "Active" | "ReadyToTurnIn" | "Completed",
    Objectives: { [ObjectiveId]: number },   -- counters, clamped to target
    AcceptedAt: number,
    CompletedAt: number?,
}
```

### 2.3 Size estimate
150 gear instances at about 300 bytes each is about 45 KB. With everything else included, the total stays under 100 KB, far below the DataStore value limit (4 MB). `ClaimedRewardIds` is pruned (§4) to keep it bounded.

---

## 3. Validation and Repair (on every load)

`ProfileValidator.repair(profile) -> (profile, repairs: {string})`. Every repair gets logged to the security log with the UserId.

| Field | Rule | Repair |
|---|---|---|
| Missing field | Present in template | Fill from `ProfileTemplate` (deep, without overwriting existing values) |
| `SchemaVersion` | ≤ current | Run migrations in order. Greater than current means the profile came from a newer build: **kick** with "Game updated, please rejoin" and never downgrade |
| `Level` | int 0..30 | Clamp |
| `Experience` | 0 ≤ xp < XPToNext(Level); 0 at L30 | Clamp |
| `Race`/`Job` | nil or a valid enum | nil (forces re-selection) and log |
| `FacePreset` | in allowlist | 1 |
| `OwnedSkills` | Each id exists and matches the Job | Drop invalid |
| `EquippedSkills` | Owned, job-valid, correct type, no duplicates, ≤ 3 + 1 | Drop invalid entries |
| `Inventory` | Guid key equals `item.Guid`. DefId exists. Rarity valid. Enhancement 0..10. Attributes come from the allowed pool, within bounds | Drop the item if DefId is unknown (log the full item); otherwise clamp |
| Duplicate Guids | Impossible by key, but checked across Equipment | Unequip dangling references |
| `Equipment` | Slot valid, guid in Inventory, item fits the slot | nil |
| `Stackables`/`Wallet` | Non-negative int, known id, ≤ cap | Clamp, drop unknown |
| `QuestState` | Known QuestId, objective counts within target | Drop unknown, clamp |
| `Settings` | Ranges and enums | Defaults |
| `Counters` | Whitelisted keys | Drop others |

Unknown definition IDs might come from content that was *removed*. Those items get **logged in full** before being dropped, so support can restore them.

---

## 4. Integrity Patterns

### 4.1 Synchronous mutation rule
Every gameplay mutation follows **check → mutate → emit** in one synchronous block with **no yields** (no `task.wait`, no DataStore calls, no RemoteFunction invokes) between the check and the mutation. Luau's single-threaded execution makes that block atomic with respect to other server code.

### 4.2 Idempotent rewards
```lua
PlayerDataService:ClaimReward(player, rewardId, grantFn) -> boolean
-- if ClaimedRewardIds[rewardId] then return false
-- ClaimedRewardIds[rewardId] = now ; grantFn(profile) -- same synchronous block
```
| Source | RewardId format | Retention |
|---|---|---|
| Quest | `Q:<QuestId>` | Permanent |
| Dungeon clear | `D:<runId>` | 7 days |
| Boss loot | `B:<runId>:<bossId>` | 7 days |
| PvP boss | `PB:<spawnId>` | 7 days |
| Event reward | `E:<eventInstanceId>:<tier>` | Until event expiry + 7 days |
| Admin grant | `A:<auditId>` | 30 days |

`runId`/`spawnId` = `<JobId>:<counter>`, which is unique across servers.

### 4.3 Session locking
ProfileStore session locking means only one server holds a profile. All mutations happen in memory on the owning server, and auto-save persists them. When a session is stolen, the old server's profile object is invalidated and that player is kicked.

### 4.4 No trading (D-14)
Items never move between profiles. This removes the main duplication vector.

### 4.5 Admin edits
Admins never write raw profile JSON. They call typed operations (`GrantItem(defId, rarity)`, `SetLevel(n)`, `RemoveItem(guid)`), which go through the same validators and are audit-logged with before/after.

---

## 5. Migrations
- `server/Persistence/Migrations/vN_to_vN+1.luau` exports `migrate(profile) -> profile`. Each migration is pure and idempotent.
- The loader runs the migrations in order, then runs `repair`.
- Every migration has a Lune test that runs fixture profiles of the old version through migration and repair to a valid current-version profile.
- v1 is the initial schema, so it has no migrations.

---

## 6. Replicated View (what the client receives)

`ProfileSnapshot` for the **owning player only**: Race, FacePreset, Job, Level, Experience, XPToNext, OwnedSkills, EquippedSkills, Inventory (full item instances; the player owns them), Equipment, Stackables, Wallet, QuestState (only active and completed IDs, no hidden flags), visible StoryFlags, Titles, Cosmetics, PvPStats (Victories/Defeats/Participations only), Settings.

**Never replicated:** ClaimedRewardIds, RecentVictims, Restrictions details, Counters internals, CreatedAt, any data belonging to other players.

Attributes visible to everyone (`Player` attributes): `Level`, `Race`, `Job`, `Title`, `PvPProtected`.

---

## 7. Definition Schemas (shared, display-safe)

| Definition | Key fields |
|---|---|
| `ItemDefinition` | id, name, slot, category (Weapon/Armor/Accessory), jobRestriction?, levelReq, baseStats, attributePoolId, iconId, modelRef |
| `AttributePool` (server config) | id, entries {stat, min, max by rarity, weight}, rollsByRarity |
| `SkillDefinition` | id, name, job, type (Regular/Special), category, range, cooldown, focusCost, castTime, targetRule (Enemy/Ally/Self/Area/Direction), formula {base, atkCoeff}, effects, animationId, vfxId, sfxId, unlockRule |
| `JobDefinition` | id, allowedSkillCategories, basicAttack, weaponTypes |
| `EnemyDefinition` / `BossDefinition` | id, level, stats, aiProfile, abilities, xp, lootTableId, telegraphs, phases (boss) |
| `LootTable` (server config) | id, dropChance, rarityWeights, itemPool, stackableRewards |
| `QuestDefinition` | id, prerequisites, objectives {id, type, target, params}, dialogue, rewards {xp, items, stackables, titles, flags, unlocks} |
| `EventDefinition` | id, name, category, defaultDuration, eligibility, zones, multipliers, spawns, rewards, announcementKey, cooldown, stackGroup |

The server-only parts (loot weights, attribute pool bounds, AI internals) live in `server/Config`. Clients receive only what the UI displays, such as **displayed odds** for enhancement (D-08 transparency).
