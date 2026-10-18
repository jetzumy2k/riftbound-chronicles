# Creature Audit (creator review 2026-10-17)

Audit before the mob / boss / creature overhaul. Findings come from the code
as it stands (`EnemyDefinitions`, `World/CreatureBuilder`,
`Controllers/MobVisualController`, `Logic/MobBrain`, `Services/MobService`,
`Services/BossService`, `Services/CombatService`, `Effects/*`).

## 1. How creatures are made today

| Area | Today |
|---|---|
| Models | 100% procedural: every creature is built at runtime from rounded `Part`s (ellipsoid `SpecialMesh`) welded to a few limbs. No MeshParts, no textures, no authored assets. |
| Rig | `Humanoid` + invisible `HumanoidRootPart`; limbs on `Motor6D`s. **One joint per limb**: shin / paw / forearm / tibia are welded to the thigh / arm, so legs cannot bend at the knee. |
| Animation | No `Animator` / AnimationTracks. The client (`MobVisualController`) sets `Motor6D.Transform` each frame from sine-based gaits per body plan, within 160 studs. |
| Movement | `Humanoid:MoveTo` in a straight line (no pathfinding); every creature walks, including winged ones. |
| AI | `MobBrain`: 4 states (Idle, Chase, Windup, Return). One basic attack per creature; bosses add 3 generated abilities by archetype (circle, cone, ring) plus summons. |
| Hit detection | Basic strike: distance check when the wind-up ends (no facing / arc check). Boss abilities: telegraphed shapes (circle / cone / ring), fair and readable. |
| VFX | Ground telegraphs, damage numbers, skill impacts, status VFX. **No creature-specific effects** (no dust, claw trails, landing shockwaves, breath). |
| SFX | **No audio anywhere in the game** (no sound asset ids). |
| Network / perf | Server-owned physics, AI at 8 Hz with a 150-stud sleep radius, streaming on. About 325 creatures per realm dungeon; 40–100 parts each. |

## 2. Inventory by anatomy and movement type

61 enemies on **6 body plans**. The 30 floor-4 mini bosses and most war bosses are recoloured, rescaled copies of these plans with a few traits.

| Movement type | Body plan | Creatures |
|---|---|---|
| Quadruped, agile predator | Wolf | RiftWolf, EmberHound, RimeStalker, DuneStalker, JungleProwler, Fenrir, Garmr, Orthrus, Cadejo, BlackShuck |
| Quadruped, big cat / beast (on the wolf plan) | Wolf | NemeanLion, Manticore, Sphinx, Ammit, Chimera, Cerberus, Ahuizotl |
| Quadruped, heavy charger (on the wolf plan) | Wolf | ErymanthianBoar |
| Flyer (on the wolf plan; it walks) | Wolf + Wings | Camazotz |
| Crawler, 6 legs | Beetle | CrystalBeetle, CinderScarab, AbyssCrawler, Thorncrawler, SandScarab |
| Crawler / sea monster (on the beetle plan) | Beetle | Arachne, Scylla, Charybdis, Cockatrice, Taotie, Kelpie |
| Heavy biped | Golem | StonebackGuardian, MagmaGolem, SandstoneGolem, MossbackGolem, Tarasque, Bunyip, Catoblepas, OasisColossus |
| Ape / brute (on the golem plan) | Golem | Yeti, Grendel, Mapinguari |
| Armoured biped | Guardian | RiftGuardian, AbyssalKnight, Minotaur, Nian, Typhon, Gorgon |
| Flyers (on the biped plan; they walk) | Guardian + Wings | HarpyQueen, Griffin, Wyvern, Fafnir, Peryton, Anzu |
| Serpent | Serpent | Basilisk, Bakunawa, Ladon, Echidna, Apophis, JungleHydra, Leviathan |
| Hovering wisp | Sprite | RiftSprite |

## 3. Problems by category (worst first)

### 3.1 Model and anatomy (critical)
- **Wrong anatomy for 24 of 61 creatures.** Griffin, Harpy Queen, Anzu and Peryton are birds built as stone knights. Wyvern and Fafnir are dragons built as knights. Arachne is a spider built as a 6-legged beetle. Kelpie is a water horse built as a beetle. Scylla and Charybdis are sea monsters built as beetles. Cockatrice is a bird. Yeti, Grendel and Mapinguari are apes built as stone golems. Nemean Lion and Sphinx are lions built as wolves, and the Erymanthian Boar is a wolf.
- **Reuse:** apart from colour, size and a few traits, the 30 mini bosses look like 4 creatures.
- **Visible seams:** ellipsoids overlap or gap at every bend, because there are no continuous meshes.
- **Ceiling:** procedural parts can be made much better, but they cannot reach authored-mesh quality (skinned, textured).

### 3.2 Rigging and joints (critical; the main cause of stiff motion)
- **One joint per limb**, so there are no knees, hocks, ankles or elbows. Legs swing like stilts.
- No spine joints: the body is one rigid piece. Quadrupeds can't flex shoulders and hips separately.
- Necks are welded on wolves (only the head turns).

### 3.3 Locomotion and animation (high)
- Feet are not planted on the ground (no IK). Body height ignores slopes, so feet float or sink on terrain.
- Gaits are sine curves without contact or passing poses, so they read as "mechanical".
- No gait per species: a lion, a boar and a wolf share one gait.
- No jump, land, stumble or stagger. Turning is a server-side snap in the wind-up.

### 3.4 AI and movement logic (high)
- **No flight.** All winged creatures walk. A 3D flight controller and an aerial state machine would be new systems.
- Only 4 states: no Alert, Recovery, Stagger, Enrage display, Retreat or Circle.
- Straight-line `MoveTo` with no pathfinding, so creatures stick on war-zone rocks.
- One attack per creature, with no attack sets per species (bite, claw, pounce, charge, tail sweep, dive).

### 3.5 Attack choreography and hit detection (high)
- One generic wind-up → strike → recover curve per body plan. Boss moves depend only on the ability shape.
- The basic strike hits anyone in range when the wind-up ends, even someone behind the creature (no arc check).

### 3.6 VFX and sound (high)
- No creature attack effects (dust, claw trails, impacts, breath) and no landing or charge effects.
- **No sound at all.** Roars, footsteps, wing beats and impacts all need audio assets.

### 3.7 Performance and networking (medium)
- The current budget is fine. Adding knee joints and IK raycasts raises client cost per creature, so it needs an LOD: full IK near the camera, simple gait far away.
- Flight must stay server-authoritative (server-owned AlignPosition / AlignOrientation) to avoid exploits and jitter.

## 4. What needs your assets or decisions

| Need | Why | Options |
|---|---|---|
| Creature meshes | Professional anatomy needs skinned, textured meshes. | (a) Improve procedural parts only. (b) I generate skinned mesh files (FBX) and you import them with Studio's 3D Importer under your account. (c) You buy or commission meshes. |
| Sound effects | There is no audio in the game. | You choose sounds from the Creator Store (licensed for your experience) and give me the asset ids; I wire them to animation events. |
| Phase order | This is the Phase 16 creature art pass plus combat AI work, ahead of Phases 7–14. | Run it now, or after Phase 14 as Phase 16. |

## 5. Stages (each one tested in Studio before the next)

Decisions (2026-10-17): run now, before Phase 7; code-built models; Claude picks sound ids.

Status: stage 1 built (D-51). The creator then rejected the code-built looks (2026-10-17): creatures become **sculpted skinned meshes** the creator imports (D-52), with behaviour brought forward. Batch A (Hound, Cerberus, Serpent, Hydra) built, waiting for import and test; next batches: big cat, boar, beetle, spider, golem, knight / minotaur, ape, bird / griffin, dragon, bat.

1. **Rigs and locomotion:** multi-joint legs (hip–knee–ankle), spine and neck chains, foot IK with ground raycasts (near-camera LOD), gaits per species (agile predator, heavy beast, armoured, 6- and 8-leg crawler, serpent, heavy biped).
2. **Correct anatomy:** new body plans for Avian (Griffin, Harpy, Anzu, Peryton, Cockatrice), Drake (Wyvern, Fafnir), Bat (Camazotz), Arachnid (Arachne), Feline (Nemean Lion, Sphinx, Manticore, Ammit, Chimera), Boar, Ape (Yeti, Grendel, Mapinguari), Aquatic (Kelpie, Scylla, Charybdis); a distinct silhouette for every boss.
3. **Flight:** a server-owned flight controller and aerial states (take off, hover, circle, dive, land), aerial attacks with ground telegraphs, and grounded / airborne switching for flying bosses.
4. **AI and attacks:** states Alert / Recovery / Stagger / Enrage, gradual facing with an arc check on hits, attack sets per species (bite, claw, pounce, charge, tail sweep, dive), and signature combos per boss.
5. **VFX and SFX:** dust, claw trails, shockwaves, breath, wing gusts and defeat effects, mobile-budgeted; sounds once you provide asset ids.
6. **Optional:** authored meshes, depending on the choice in section 4.
