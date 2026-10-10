# DESIGN_REFERENCE_SHAIYA.md — Shaiya as the reference game

The creator's reference (2026-10-11): **Shaiya**, a classic fantasy MMORPG built around faction-vs-faction PvP and leveling. The goal is a Roblox game with the same core loop, but a **modern fantasy** look instead of Shaiya's classic one.

> **IP rule:** Shaiya is a *reference for gameplay feel*. We never copy its names, maps, art, icons, sounds or text. Everything in Riftbound Chronicles stays original. Before release, a human should check that nothing is substantially similar.

> The Shaiya details below come from general knowledge of the game and may vary by version or server. They're meant as design inspiration, not a spec.

## 1. How Shaiya maps to Riftbound Chronicles

| Shaiya system | Riftbound Chronicles today | Status |
|---|---|---|
| Two warring factions (Light vs Fury), each with its own home cities | Angels vs Devils, separate capitals and safe zones | ✅ Built (Phase 3) |
| Faction PvP map where both sides fight over territory | Desert Rift + Jungle Rift PvP zones, race-vs-race PvP | 📋 Planned (Phases 12–14) |
| Kill-count **PvP rank** with titles/stars | CLAUDE.md §4: PvP kill counts and titles | 📋 Planned (Phase 14) |
| Six classes per faction (melee DPS, tank, stealth melee, archer, mage, healer) | Warrior, Healer, Archer, **Mage** | ✅ 4 jobs (Mage added, D-30) |
| Party grinding in dungeons as the main leveling path | Dungeons are the primary leveling activity | 📋 Planned (Phases 9–10) |
| Item enchanting with stones (+ levels) | Enhancement Stones, +0..+10, no gambling-style loss | 📋 Planned (Phase 8) |
| Rarity tiers and boss drops | 6 rarities incl. Epic; boss/mob drop tables | 📋 Planned (Phases 7, 10, 14) |
| Story quests | 11-quest arc, Nullborn story | 📋 Planned (Phase 11) |

## 2. Shaiya ideas *not* in the plan yet (candidates)

| Idea | What it adds | Fit / risks | Recommendation |
|---|---|---|---|
| **Gem sockets** (Shaiya "lapis") | Gear gets sockets; gems add stats. A big gear chase | Fits the gear loop well. Needs economy design (Phase 7/20). Must not become paid-random | 👍 Add as a later phase after enhancement |
| **Stat point allocation** (STR/DEX/INT…) | Players build their character each level | **Conflicts with CLAUDE.md §5** (fixed per-level stat growth). Would need a spec change and rebalance | 🤔 Creator decision; maybe a small bonus-point layer on top of §5 |
| **Difficulty modes** (easy/normal/hard/hardcore) | Replayability, bragging rights | Hardcore death penalties conflict with "no XP/item loss" (§14) and the 9+ audience | 👎 Not recommended |
| **Tank class** (Shaiya Defender/Guardian) | Dedicated tank role | Warrior already covers tanking (Guard, Taunt). A 5th class costs a lot of content and balancing | ⏸ Revisit after launch |
| **Stealth melee class** (Shaiya Ranger/Assassin) | Burst and stealth gameplay | Stealth in PvP is hard to keep fair and readable on mobile | ⏸ Revisit after launch |
| **Mounts** | Faster travel on big maps | Fun and cosmetic-friendly; needs anti-exploit speed allowances | 👍 Good post-launch feature |
| **Guilds + guild war** | Long-term social retention | Large scope (UI, moderation of names and chat via TextService filtering) | 👍 Post-launch (Phase 26+) |
| **Party EXP sharing** | Encourages grouping | Small, fits the dungeon phase | 👍 Fold into Phase 9 |

## 3. "Modern fantasy" vs Shaiya's "classic fantasy"
- **UI:** dark glass + gold, clean typography, responsive on phones (D-28), versus Shaiya's ornate classic PC windows.
- **Characters:** stylised-realistic modern armour and silhouettes from the concept sheets (ART_DIRECTION.md), versus Shaiya's classic medieval look.
- **Controls:** touch-first combat (big buttons, soft targeting), plus mouse and gamepad.
- **Pacing:** shorter sessions (~10–20 min loops: one dungeon run, one PvP round) suited to Roblox players.

## 4. Decisions needed from the creator
1. Add **gem sockets** as a future phase? (recommended)
2. **Stat points:** keep CLAUDE.md §5 fixed growth (current), or add a small allocatable bonus layer?
3. **Party EXP sharing** in the dungeon phase? (recommended)
4. Mounts and guilds as post-launch features?
