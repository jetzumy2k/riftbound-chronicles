# ART_DIRECTION.md — Riftbound Chronicles

Reference concept sheets (creator-provided, 2026-10-11):
- `docs/characters and gears/Angel vs Devil Fantasy Game Showcase.png`
- `docs/characters and gears/Angel and Devil Gear Showcase.png`

They define the **target look**: stylised-realistic anime fantasy (comparable to Lost Ark / Genshin key art). This document turns them into buildable requirements.

## 1. Factions
| | Angels | Devils |
|---|---|---|
| Motto | Light, Order, and Hope | Power, Freedom, and Ambition |
| Palette | White, ivory, gold, sky blue | Black, crimson, ember red |
| Materials | Polished gold filigree, white cloth, feathers, blue gems | Blackened steel, red lacquer, leather, glowing red veins |
| Race features | Feathered wings, halos | Horns, bat wings |
| Capital | Floating white-gold cathedral city above the clouds | Volcanic crimson gothic city with lava |

## 2. Jobs (per race)
| Job | Role text on the sheet | Weapons |
|---|---|---|
| Warrior | High Defense · Melee DPS | Swords, Greatswords, Polearms, Maces (Angel) / Axes (Devil) |
| Healer | Healing · Support · Buff (Angel) / Debuff (Devil) | Staffs, Orbs |
| Archer | Long Range · High DPS | Bows, Crossbows |
| Mage *(added 2026-10-11, D-30; not on the sheet yet)* | Arcane Burst (Angel) / Hex Burst (Devil) · Area DPS | Staffs, Wands, Tomes |

Each job has a full gear set per race: helm, chest, gloves, legs, boots, cape. These map to the D-25 equipment slots.

## 3. Customization (both races)
Faces (6 shown), hair styles, eye colours, horns (Devil), halos (Angel), wings (both). This expands the Phase 3 "look preset" into **separate slots**: face, hair, eyes, race feature and wings. Each slot is still chosen from a server-side allowlist (SECURITY_MODEL T-30).

## 4. Motion
Idle, walking, running, jumping, normal attack, skill attack, defending, casting. The motion feel (easing, lean, head look, landing) is implemented in `CharacterMotionController`. Authored animations for each state are still needed (§6).

## 5. Areas
Angel starting area, Devil starting area, dungeon (gothic hall with a stone colossus boss), desert PvP oasis, jungle PvP waterfall. These match CLAUDE.md §13/§20.

## 6. What it takes to reach this look in Roblox
The concept sheets are painted 2D key art. In Roblox that quality comes from **authored 3D assets**; code alone can't produce it.

| Need | How it gets into the game | Status |
|---|---|---|
| Realistic bodies/faces | Rigged R15 MeshPart characters with SurfaceAppearance (PBR) textures, from an artist (Blender) or vetted Creator Store models | Needed |
| Gear sets | Layered-clothing / rigid Accessories per job × race, saved to `assets/Outfits/...` | Pipeline ready (Wardrobe); art needed |
| Wings, halos, horns | Accessories (MeshParts + SurfaceAppearance) | Procedural placeholder in place; art needed |
| Weapons | Tool / Accessory MeshParts with grip attachments | Phase 5/7 system; art needed |
| Animations | Authored or motion-captured R15 KeyframeSequences per state (idle/walk/run/jump/attack/skill/defend/cast), uploaded as Animation assets | Motion layer done; animations needed |
| Terrain/areas | Roblox Terrain + modular building kits (MeshParts) | Phase 16 |

Until the art exists, the game runs on the procedural outfit (`Appearance/OutfitBuilder`) and the default animations with the motion layer on top.

## 7. Required adjustments (compliance and spec)
1. **Modest outfits (approved by the creator 2026-10-11; 9+ audience, CLAUDE.md §2):** several female designs on the sheets (healer and archer) have deep necklines and high slits. Final game outfits must cover the chest and hips and keep skirts and slits non-revealing, so the Mild maturity target holds. Same silhouettes and colours, more coverage.
2. **Rarity tiers: resolved 2026-10-11.** Epic was added (6 tiers: Standard/Common, Uncommon, Rare, Epic, Legendary, Mythical). See PLAN D-22.
3. **No real-world religious symbols** on gear (PLAN PC-1). The sheet's emblems are abstract wings and spikes, which is fine. Keep crosses and pentagrams out.
