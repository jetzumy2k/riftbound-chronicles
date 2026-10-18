# DEVELOPMENT.md — Working on Riftbound Chronicles

## Toolchain
All tools are pinned in `rokit.toml`. Install them with:

```bash
rokit install
```

| Tool | Use |
|---|---|
| Rojo 7.7.1 | Sync `src/` into Studio (`rojo serve`) or build a place file (`rojo build`) |
| Wally 0.3.2 | Packages (ProfileStore arrives in Phase 2): `wally install` |
| StyLua 2.5.2 | Formatter: `stylua src tests` |
| Selene 0.32.0 | Linter: `selene src` |
| luau-lsp 1.70.1 | Strict type check (below) |
| Lune 0.10.5 | Pure-logic test runner |
| run-in-roblox 0.3.0 | Headless-ish Studio boot probe (below) |

## First-time setup

```bash
rokit install
wally install        # required before rojo build/serve (ServerPackages/ProfileStore)
```

## Daily loop

```bash
rojo serve                      # then connect from the Rojo plugin in Studio and press Play
```

## Checks (run all before committing a phase)

```bash
stylua --check src tests
selene src
lune run tests/pure/run

# Strict type check (downloads Roblox API definitions once into .tooling/)
curl -sSfL -o .tooling/globalTypes.d.luau https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze --definitions=.tooling/globalTypes.d.luau --sourcemap=sourcemap.json src

rojo build -o build/RiftboundChronicles.rbxlx
```

## Studio boot probe

```bash
rojo build -o build/RiftboundChronicles.rbxlx
run-in-roblox --place build/RiftboundChronicles.rbxlx --script tests/studio/boot_probe.luau
```

This opens Studio briefly, runs the place in server mode and prints `PROBE PASS/FAIL` lines.

**Known issue (Windows):** run-in-roblox 0.3.0 always listens on port **50312**. If Hyper-V or WSL has reserved a port range that contains it, it fails with `os error 10013`. Check with:

```bash
netsh int ipv4 show excludedportrange protocol=tcp
```

To free the dynamic reservations, run this in an **elevated** terminal: `net stop winnat` then `net start winnat`. This briefly interrupts container and WSL networking.

## Manual multiplayer test (each phase)
In Studio: **Test → Clients and Servers → Local Server + 2 players**. Then check:
- Server Output: `[RC][Info][Loader] booted N services`, `[RC][Info][NetService] published N remotes`
- Each client Output: `[RC][Info][Notification] Welcome: system.welcome`
- No `[RC][Error]` lines and no red errors on server or clients

## Phase 2 manual tests (player data)
Saves only persist in Studio when the place is **published** and **Game Settings → Security → Enable Studio Access to API Services** is on. Otherwise ProfileStore uses an in-memory mock and data resets every session (the server log prints `DataStore state: NoAccess`).

Grant XP from the **server** command bar during Play. There is deliberately no client path:

```lua
local LS = require(game.ServerScriptService.Server.Services.LevelService)
local p = game.Players:GetPlayers()[1]
print(LS:GrantXP(p, 500, "Dev"))       --> true  3   (L0 -> L3)
print(LS:GrantXP(p, 1000000, "Dev"))   --> true 27   (capped at L30)
print(LS:GrantXP(p, -5, "Dev"))        --> false 0   (rejected)
```

Check:
- The HUD (top left) shows `Lv N` and `x / y XP` and updates immediately. At the cap it shows `MAX LEVEL`.
- Stop, then Play again (with API access): level and XP are restored.
- From a **client** command bar, firing any remote with XP-like arguments changes nothing. The only client-to-server remote is `ClientReady`.

## Phase 3 manual tests (race system)
Run **Test → Clients and Servers → Local Server + 2 players** (or Play solo for the basics).

1. **First join:** the "✦ CHOOSE YOUR REALM ✦" screen appears with two glass cards (Angels / Devils) and a 3D preview panel in the middle. There is no character yet.
2. **Tap a card:** it glows, gets a "✓ SELECTED" ribbon and the other card dims. The preview shows **your own avatar** in that race's outfit, slowly turning; drag it to rotate. Tap the look medallions: the preview recolours and the title shows `LOOK · <NAME>`. The gold button reads "ENTER THE SKYREACH" / "ENTER THE EMBERDEEP".
3. **Enter:** the screen closes and the character spawns on that race's capital wearing the fantasy outfit (tunic, armour, cape, gloves, boots; Angels: wings + ring of light; Devils: horns, bat wings, tail). Casual avatar clothing and hats are removed; face, hair and skin stay. The HUD shows the level medallion, XP bar and **🛡 SAFE ZONE**.
4. **Two players** (Local Server): pick different races. Each spawns only at their own capital. Note that Studio test players ("Player1", "Player2") have a default avatar, so the face and body underneath look generic; that's Studio, not the game.
5. **Leave the safe zone** (walk past the glowing ring): the SAFE ZONE badge disappears.
6. **Reset (Esc → Reset):** you respawn at your own capital after ~3 s, re-dressed.
7. **Rejoin** (needs a published place with API access): no race screen, and you spawn straight at home.
8. **Tamper test** (client command bar):
   ```lua
   local r = game.ReplicatedStorage.Remotes.SelectRace
   r:FireServer("Devil", 1)      -- Angel preset with Devil race → rejected (InvalidFacePreset)
   r:FireServer("Human", 1)      -- not an enum value → rejected (BadArgs)
   r:FireServer("Angel", 1, "x") -- extra argument → rejected (BadArity)
   r:FireServer("Devil", 5)      -- after a race is chosen → rejected (RaceAlreadyChosen)
   ```
   The server Output shows `[RC][Warn][Security] … code=…` lines, and nothing changes in game.

## Phase 4 manual tests (job system)
1. **New player:** after "Enter the Skyreach/Emberdeep", the **"✦ CHOOSE YOUR PATH ✦"** screen appears over a view of your capital. There is still no character.
2. Three cards (Warrior / Healer / Archer) show the role line for your race (Angel Healer = *Buff*, Devil Healer = *Debuff*) and the weapons that job can use for your race (Angel Warrior: Sword · Greatsword · Polearm · Mace; Devil Warrior: … Axe …).
3. Tap a card: "✓ SELECTED", the others dim, and the button reads "BEGIN AS WARRIOR". Press it: the character spawns at your capital.
4. **Device check:** Test → Device → phone (portrait and landscape), tablet and desktop. Cards stack or sit side by side; nothing is cut off.
5. **Tamper test** (client command bar):
   ```lua
   local r = game.ReplicatedStorage.Remotes.SelectJob
   r:FireServer("Mage")      -- not a job → rejected (BadArgs)
   r:FireServer("Healer")    -- after a job is chosen → rejected (JobAlreadyChosen)
   ```
6. **Server rule check** (server command bar, after choosing Warrior):
   ```lua
   local JS = require(game.ServerScriptService.Server.Services.JobService)
   local p = game.Players:GetPlayers()[1]
   print(JS:CanUseSkillCategory(p, "Taunt"), JS:CanUseSkillCategory(p, "Heal")) --> true false
   print(JS:CanUseWeapon(p, "Greatsword"), JS:CanUseWeapon(p, "Bow"))          --> true false
   ```

## Phase 6 manual tests (combat foundation)
Each capital has a **Training Grounds** yard in front of the spawn, outside the safe zone. Floor stripes mark 10–50 studs from the 3 training dummies at the far end, so you can check each job's range (Warrior 8, Healer 32, Mage 40, Archer 48). If an attack is blocked, a toast says why (safe zone, too far, no line of sight, no target).

1. **HUD:** under the level panel are the HP bar (`HP 200 / 200` at L0) and a blue Focus bar. **✦ PROTECTED** shows for 10 s after spawning.
2. **Attack:** walk past the ring to a dummy. Then:
   - Desktop: **click the dummy**, or press **F** facing it.
   - Gamepad: **R2**.
   - Phone: the big gold button.
   White numbers float up; crits (~5%) show **gold ✦ numbers**; the dummy flashes white. Warrior must stand close (8 studs); Healer (32) and Archer (48) can hit from range but need line of sight.
3. **Safe zone:** standing inside the ring, attacks do nothing (blocked in both directions). Walking out gives a 3 s **PROTECTED** bubble.
4. **Defeat (non-graphic):** keep hitting a dummy to 0 (2,500 HP). It bursts into light and fades, then returns after 3 s.
5. **Player defeat / reset:** Esc → Reset. Outside combat you respawn at home after ~1 s. Within 10 s of fighting, a reset counts as a defeat (light burst, respawn after 2.5 s, protected again).
6. **Movement checks (shadow mode):** in the server command bar,
   ```lua
   game.Players:GetPlayers()[1].Character.Humanoid.WalkSpeed = 100
   ```
   then walk: the server log shows `[Security] … MovementSuspect (shadow) speed …`, and nothing is corrected yet (Enforce comes before PvP).
7. **Tamper test** (client command bar): `game.ReplicatedStorage.Remotes.BasicAttack:FireServer(workspace)`. It's rejected (BadArgs, not a Model); there is no remote that can set damage or HP.

## Phase 5 manual tests (skill trees, D-45)
Studio now uses the real level gates (1 skill point per level). To try the whole tree, set `Skills.StudioUnlockAll = true` and `StudioBonusPoints = 60` in `src/server/Config/Defaults.luau` (Studio only, never live). Server Output: `96 skills in 16 branches ready`. Old test characters are migrated to schema v2 with an empty tree (all points back); skills or ranks above the character's level are removed on join.
1. **Skill tree:** press **K** or tap **✦ SKILLS (n)** on the right edge. Each class has 4 branch columns x 6 tiers, 24 skills (Warrior: Blademaster / Ironclad / Warlord / Vanguard; Healer: Light / Sanctity / Judgment / Seraph; Archer: Marksman / Venom / Ranger / Windrunner; Mage: Pyromancy / Cryomancy / Arcanist / Stormcaller). Every node and branch has a **drawn icon** (no empty boxes), a rank badge `n/5` (specials, round icons: `n/3`), a padlock + "Lv N" while locked, and **LEARN / +RANK** when a point can be spent. Lines join each skill to the one it needs. The tree scrolls and keeps its scroll position when you learn.
1b. **Level gates:** at level 0 only the four tier-1 skills can be learned; new skills open at levels 3-6, 8-11, 14-17, 20-23 and 27-30 (one column per level), with a toast naming the new skill on level-up. A skill's rank 2 opens at level 6, rank 3 at 12, rank 4 at 18, rank 5 at 24 (**"Rank n opens at level X"** on the button and as a toast); a toast says when a new rank opens.
2. **Skill information:** tap a node: the right / lower pane shows type, category, branch, rank, Focus, cooldown, range / radius, target type, every effect with numbers and durations, the **COMBO** rule and what the next rank adds. Hover a skill-bar button (desktop) or press-and-hold it (phone) for the same card.
3. **Learn and choose your set:** **Learn (1 pt)** / **Rank n (1 pt)** spends a point; **Put in slot 1/2/3** or **Put in Special** builds the bar from *any* learned skills (swaps if already on the bar); **Remove from bar** empties a slot. The bar row at the top of the tree shows the result. **Reset** works only in a safe zone (toast otherwise) and refunds every point. Rejoin: tree, ranks and bar are saved.
4. **Targeting:** click / tap a creature or player (near misses snap to the closest one); a red dashed ring (enemy) or green ring with gaps (ally) stays under it and a plate over its head shows name, level, HP and statuses with ✕ to clear. **Tab** / DPad-right cycles enemies. Attacks and skills always go to the selected target; with none, the nearest enemy in front becomes selected. Out of range, your character **walks to it and then attacks / casts** (moving yourself cancels).
5. **Effects to check** (training dummies, then creatures): stun stars, **freeze** ice block, root shards, slow mist, **poison** green bubbles + ☠ numbers each second, **burn** flames + 🔥 numbers, **hardening** stone outline, empower red sparks, haste wind, regen sparkles + green numbers, shield bubble + blue 🛡 numbers when it soaks, mark reticle, silence ∅, taunt "!". Every status also shows as a word chip.
6. **Skill visuals:** casts show weapon glints / glowing hands / rune circles; projectiles (fireball, frost lance, holy bolt, arrows, homing missiles) fly with trails and light; impacts burst on whoever is hit (explosions, ice shatter, venom splash, light pillars, quake rocks); areas: whirl, nova, quake, arrow / poison rain, blizzard, meteor (red warning circle first), healing dome.
7. **Combos:** freeze a target (Glacial Prison / Frost Arrow), then Frost Bolt or Shield Bash: big shatter + **"COMBO · SHATTER!"**. Also: Combustion on burning, Toxic Bloom (Entangling Arrow) on poisoned, Judgment / Deadeye on marked, Earthshaker on slowed, Crushing Blow on stunned, Execute below 35% / 30% HP. The skill-bar button glows with **COMBO!** when its combo is ready on your target.
8. **New skill animations:** Warrior spin (Whirlwind / Blade Storm), leap-slam (Ground Slam / Earthsplitter), brace (Iron Skin / Bulwark), roar; Healer raise and staff-plant; Archer sky volley and dodge roll; Mage channel and push.
8b. **Rest regen:** after a fight, stop attacking and move 40+ studs from any creature (dungeon, forest, desert, jungle): after 5 s the HP bar shows **"· resting"** and HP fills in about 50 s. Getting hit, attacking or a creature walking close stops it; training dummies don't block it.
9. **Fair play:** a stunned / frozen player can't attack, cast or walk; silenced can't cast; after a stun / freeze ends a player can't be stunned again for 3 s; crowd control lasts half as long player-vs-player; bosses ignore stun / freeze / root / slow / silence (taunt works).
10. **Tamper tests** (client command bar), each does nothing:
   ```lua
   local R = game.ReplicatedStorage.Remotes
   R.LearnSkill:FireServer("Fireball")          -- another class's skill (security log: LearnNotAllowed)
   R.SkillCast:FireServer("Execution")          -- not learned / not on the bar (SkillNotAllowed)
   R.SetLoadout:FireServer({"CleavingStrike","Whirlwind","Execution","IronSkin"})  -- 4 regular (BadArgs)
   R.SetLoadout:FireServer({"BladeStorm"})      -- special in a regular slot (InvalidLoadout)
   for i = 1, 20 do R.LearnSkill:FireServer("CleavingStrike") end  -- one rank per free point, max 5
   ```

## Dungeon floors, unions and war-zone bosses (D-47, D-48, D-49)
Studio boss timers are short (`Dungeon.StudioMiniBossRespawnSeconds` 60, `StudioFloorBossRespawnSeconds` 120, `StudioBossRespawnSeconds` 180; `PvP.StudioBossRespawnSeconds` 120). Server Output: `dungeons ready (Rift Hollow: 4 floors, 37 bosses per realm)`.
1. **Floor 1:** enter through the capital's Rift Dungeons gate. The tracker shows `Floor 1/4 · The Shattered Crypts (Lv 1-10)` and the room. Walk the landing, 7 rooms and Cerberus's Gate: creatures rise from level 1 to 9 (head plates), a Stoneback Guardian mini boss guards room 4.
2. **Open, guarded way down (D-50):** rooms hold 4-5 creature packs; Cerberus's Gate has guard packs on the flanks and two elites by the portal. The "Down to Floor 2" portal at the back of the lair works **with Cerberus alive** (any level): its label reads `Floor 2: The Ember Depths (Lv 11-20)`. "Up to Floor 1" there brings you back in front of the lair.
3. **Floors 2-3:** ember basalt with lava seams (levels 11-20, Chimera at 20), then ice-stone with icicles (21-30, Basilisk at 30).
4. **Floor 4:** the Hall of Thirty: 15 chambers on each side, one mini boss each (levels 31-40, a billboard over each shows awake / countdown; the tracker counts "Mini bosses awake: n / 30"). Typhon's Sanctum is a separate room at the end of the hall.
5. **Enrage:** stay in a boss fight past its timer (Mini 3 min, Floor 4 min, Boss 5 min): toast "<name> is ENRAGED!", the tracker's HP bar adds ENRAGED, and its hits become deadly. Leave its room for 6 s: it resets to full HP, calm again.
6. **Killability check (solo):** a level-30 test character alone can't finish Typhon before the enrage.
7. **Unions:** with 4 test players (Studio: Test > Clients and Servers), form two parties; leader A taps **+ Union** and picks leader B: B gets "A invites your party to a union" with Accept / Decline. Both panels list "Union · 2/4 parties · n players" with each party; A (union leader, ★) can remove B's party (×); B can **Leave union**. Kill EXP goes to every union member within 150 studs.
8. **War zones:** Desert and Jungle creatures are level 25-30 (head plates) with many more camps; five bosses per zone stand in the middle band with "awake" billboards (Desert: Ammit 30, Anzu 35, Sphinx 40, Apophis 45, Oasis Colossus 50; Jungle: Camazotz 30, Ahuizotl 35, Mapinguari 40, Jungle Hydra 45, Leviathan 50). Their phase / enrage warnings reach players within 160 studs. A level-10 character can still enter.
9. **Creature-like bosses (D-50):** Cerberus has three heads that look around on their own and all turn to watch you as you approach; jaws open when it snarls and bites; now and then it sniffs, howls or shakes; it prowls its lair when idle and turns to face you rather than snapping round. Chimera: mane, horns, wings that fold at rest and spread / beat when alert, a snake-headed tail. Basilisk slithers (a wave runs down its body), rears its neck back in the wind-up and strikes down. Ability wind-ups differ: ground circle = roar, cone = sweep, ring = rear-up and slam.
10. **Tamper tests** (client command bar), each does nothing:
   ```lua
   local R = game.ReplicatedStorage.Remotes
   R.UnionInvite:FireServer("Player2")                       -- a name, not a Player (BadArgs)
   R.UnionKick:FireServer(game.Players.LocalPlayer)          -- not the union leader / own party
   R.UnionRespond:FireServer(game.Players:GetPlayers()[2], true)  -- no pending invite
   ```

## Auto Attack (D-53)
1. A new character's skill bar has **Auto Attack** in slot 1. In the skill tree (K) the BASIC tile (left of the bar row) shows it: "Free · known", no Learn button, Put in slot 1 / 2 / 3; skill points are unchanged.
2. Press its key (or tap its button) near creatures: the nearest one (even behind you) is targeted, you walk into reach and attack with your normal combo until it falls. The button reads **AUTO · ON** while it runs.
3. It stops when the target falls, when you steer, press it again, press ✕ on the target frame, or select a friend; clicking another enemy switches to it.
4. Nothing nearby: "No creature nearby to attack." In a war zone with no creature near, it goes for the nearest enemy player.
5. Rejoin: Auto Attack is still on the bar.

## Walking and slithering (D-54)
1. Let a wolf / hound chase you: its legs step with the ground (feet planted while the body passes over them, no skating), and at full speed it lowers into a long gallop of about 3 strides a second, not a rapid patter.
2. Beetles, golems and guardians: legs step at the speed they move; standing still, feet settle.
3. A serpent (Bakunawa, Ladon, Echidna, Basilisk, Leviathan, Apophis; the Jungle Hydra's body): moving, the body bends in an S and every part follows the path the chest took (no part slides sideways); the head stays steady; over bumps the belly stays on the ground. When it stops it lies in the curve it stopped in.
4. A creature that respawns or is teleported does not snap its body across the map (its trail is laid fresh).

## Creature flight (D-60)
Fliers: Fafnir, Wyvern, Typhon, Griffin, Anzu, Peryton, Camazotz, Harpy Queen, the Sphinx and the Chimera (war zones / dungeons where they spawn). Pure rules: `lune run tests/pure/run` (mob_flight).
1. Get a flier to chase you in the open: after a few seconds it **takes off** (wings beating, legs tucked), climbs, and **wheels round you** overhead.
2. It stops, hovers and a **red circle** marks the ground where you stand; about a second later it **dives** onto it nose-first, wings swept back. Step out of the circle in time: no damage. Stay in: a heavy hit.
3. It lands and fights on foot for 7-11 s (melee can hit it), then may fly again.
4. Stun it while it flies (Warrior / Mage control): it comes down. Run away past its leash: it lands and walks home. Defeat it in the air: it falls.
5. Indoors with a low ceiling it never takes off.
6. Bosses that fly (Fafnir, Typhon...) only use their ground abilities while on the ground.
7. Multiplayer: a second player sees the same flight, smoothly (server-owned physics), and the dive circle.

## Creature meshes and behaviour (D-52)
**Importing the sculpted creatures** (once per shape; `python tools/creatures/build.py` regenerates them):
1. Studio: **File > Import 3D** (or Avatar tab > Import 3D), pick `build/creatures/Hound.gltf`.
2. Keep the importer's defaults (rig and skinning on); if it asks for the file's units, choose **studs**. The hound should come in about 5 studs long and 3.5 tall (Cerberus a bit bigger, the serpent about 13 long, the hydra about 8).
3. **Import**. The model lands in the **Workspace** (expand it in the Explorer); rename it exactly `Hound` if needed.
4. Right-click it > **Save to File...** > `src/server/CreatureModels/Hound.rbxm`, then delete it from the Workspace. (Rojo only syncs files into Studio, so the model must be saved to the folder on disk.)
5. Repeat for `Cerberus`, `Serpent`, `Hydra` (batch A), `Beetle`, `Spider`, `Golem`, `Knight`, `Lion`, `Chimera` (batch B, D-57) and `Dragon`, `Griffin`, `Steed`, `Bat`, `Harpy`, `Gorgon`, `Sprite` (batch C, D-58), then sync / rebuild the place. Batch B's `Lion` must be re-imported if it was imported before D-58 (it gained Nian's horns and split wings).
A creature with no imported model keeps its old procedural body, so this can be done one shape at a time. Previews of every shape: `build/creatures/<Name>.png`.

**Batch B checks (D-57)**
1. **Spider** (Arachne, Scylla, Charybdis): eight legs arched high, stepping in two alternating sets of four; fangs spread in the wind-up and snap on the strike; the abdomen sways as it walks.
2. **Beetle** (Crystal Beetle, Sand / Cinder Scarab, Thorncrawler, Abyss Crawler, and the beetle-bodied bosses): a glossy domed shell with glowing spots, a horn, six legs in alternating tripods; the front pair waves when it rears.
3. **Golem** (all golems, Oasis Colossus): craggy stone slabs, a glowing core, huge fists; arms swing against the legs, feet planted; the jaw drops to roar. Grendel, Mapinguari and the Oasis Colossus wear glassy crystal spikes; the others none.
4. **Knight** (Abyssal Knight, Rift Guardian, Minotaur): plate armour, cloak, sword and shield; the sword arm rises overhead and slams down. Only the Minotaur has horns on its helm.
5. **Lion** (Nemean Lion, Sphinx, Manticore): a maned lion. The Sphinx has feathered wings that fold along its back at rest and spread when it runs or strikes; the Manticore has a segmented sting instead of a tail tuft; the Nemean Lion has neither.
6. **Chimera**: lion with a goat's head rising from its back (both look at you), bat wings, and a serpent tail whose head looks round and snaps with the strike.

**Batch C checks (D-58)** -- every enemy now has a sculpted body.
1. **Dragon** (Fafnir, Wyvern, Typhon): horned head on a long neck (Wyvern without horns), bat wings folded at rest and spreading at a run or strike, a spined tail ending in a blade that sways.
2. **Griffin** (Griffin, Anzu, Cockatrice): eagle's head with a hooked beak (opens on the strike), feather ruff and crest, lion's body and tufted tail; Griffin and Anzu have feathered wings, the Cockatrice none.
3. **Steed** (Kelpie, Peryton): a horse with an arched neck, flowing mane and tail, hooves; the Peryton has antlers and feathered wings, the Kelpie neither. Long-legged walk and gallop, hooves planted.
4. **Bat** (Camazotz): wolf-bat with great ears, fangs, leathery wings and glassy spines.
5. **Harpy** (Harpy Queen): armoured bird-woman, wings of long feathers along her arms that swing as she strides and rise overhead for the strike; taloned bird feet.
6. **Gorgon**: armoured torso rising from a serpent body that slithers like the serpents; snakes for hair; arms spread and rise in the wind-up and sweep forward on the strike.
7. **Sprite** (Rift Sprite): glowing heart in a shell of glassy crystal shards, petal wings beating fast, wisps trailing below; it hovers and bobs.
8. **Lion** now also covers **Nian** (with curved horns) and **Taotie**; **Ahuizotl** uses the hound.

**Checks**
1. Rift Hollow floor 1 (Rift Wolves) and Cerberus's Gate; floor 3 Basilisk; Jungle Rift Hydra (level 45) and Desert Apophis: the new bodies, one smooth skin, coloured per creature.
2. Wolves: paws planted, spine flexes at a gallop; when you come near they **circle you, then pounce**.
3. Serpents: the body slithers in a wave; they **stop coiled just out of reach, then lunge** (neck rears back, head strikes, jaw opens).
4. Hydra: four sprawling legs trot; three necks sway and strike a beat apart.
5. Golems / knights **charge** if you keep your distance; beetles **zig-zag** in.
6. **Portals:** walk into any portal surface (capital gates, dungeon Leave / Up / Down, Desert / Jungle gates and Return Home): you travel at once, no prompt. Arriving next to a portal never sends you on again until you step out.

**Streaming (D-56):** walk 200+ studs away from a group of creatures and come back, several times: every creature still steps with its legs (none glides with still legs).

## Creature overhaul, stage 1: skeletons and walking (D-51)
Offline first: `lune run tools/world/check_gait all` (every legged creature at a walk and a run: planted feet must not slide; 0 failed). One creature with a pose strip: `lune run tools/world/check_gait RiftWolf 16 build/gait/wolf.json` then `python tools/world/render_gait.py build/gait/wolf.json build/gait/wolf.png`.
1. **Training Grounds / Rift Hollow floor 1:** watch a Rift Wolf wander, then chase you. Its paws stay put on the ground while the body passes over them (no skating), knees and hocks bend, it walks in a 4-beat sequence and gallops when chasing.
2. **Beetles:** six legs step in alternating tripods, reaching out sideways; when one rears (idle) its front legs wave in the air.
3. **Golems / knights:** feet planted, knees bend, hips sway, arms swing against the legs with bent elbows.
4. **Giant bosses** (Cerberus, Chimera, Typhon): long slow strides, the body drops a little on every footfall; turning on the spot makes them step round instead of spinning.
5. **Slopes and steps:** walk a creature over uneven ground (war-zone dunes, dungeon stairs): feet land on the surface, the body tips with the slope.
6. **Attacks and defeat:** wolves rear and claw the air before a slam, reach out with the forepaws on a lunge; a defeated creature folds its legs as it rolls over.
7. **Mobile:** with 15+ creatures on screen the frame rate holds (ground raycasts only within 70 studs).

## Animation and movement checks
Character animation is authored keyframe clips (`src/shared/Definitions/AnimationClips.luau`, PLAN.md D-36) played through each character's Animator by `AnimationController`. Until the clips are published (docs/ASSET_GUIDE.md Part D) they are registered for play-testing in Studio; Output then shows `[Animation] registered … for play-testing`. A warning `animation … is not published and could not be registered` means you are outside Studio and must publish first.

**Controls**

| | Desktop | Gamepad | Phone |
|---|---|---|---|
| Attack (tap or hold) | click target / hold mouse / F | R2 | gold job button (3 combo pips) |
| Sprint | hold Shift | L3 | » RUN button |
| Crouch | C or Ctrl (toggle) | B | ⌄ CROUCH button |

1. **Idle / walking:** standing still plays the job's combat idle (breathing, weapon ready); walking keeps the weapon held while the legs walk.
2. **Sprint:** speed 16 → 25, running stride with arm pump; Focus drains while moving.
3. **Crouch:** lowered stance; crouch-walk cycle while moving.
4. **Combos (press repeatedly or hold):** each job chains 3 steps, the 3rd is a heavy finisher, then a short pause.
   - Warrior: horizontal slash → rising backhand → overhead cleave with a lunge and ground shockwave.
   - Healer: staff thrust (radiant bolt) → staff point (bolt) → two-handed staff slam (ring of light + pillar on the target).
   - Mage: wand flick (missile) → palm blast (missile from the left hand) → gather and two-handed arcane burst (large orb).
   - Archer: side-on draw and release → quicker second shot → wide-stance power shot (charging glow, bright arrow, burst).
5. **Hit feel:** damage numbers appear when the swing/projectile lands; both fighters freeze for a few frames (hit-stop); your camera shakes slightly; targets flinch, finishers stagger them.
6. **Attack while walking:** the legs keep walking (upper-body version of the attack).
7. **Defeat:** non-graphic kneel with head bowed, then light burst and fade.
8. **Two players:** each sees the other's loops, combos and effects exactly once.

**Authoring tools** (`tools/anim`, not shipped): `lune run tools/anim/dump_clips > build/clips.json`, then `python tools/anim/generate_arms.py build/clips.json` (solves weapon arms into `AnimationArms.luau`) and `python tools/anim/render_clips.py build/clips.json build/clips` (stick-figure contact sheets for review). Needs Python with numpy, scipy, matplotlib.

## War zone checks (Phase 12: Desert Rift)
Server Output: `Desert Rift built (… parts, terrain in … s)` and `war zones open (min level 1, Studio)`. Live servers need level 10.
1. **Gate:** the "Desert Rift" gate on the left side of each capital is open. Holding its prompt takes you to **your realm's camp** (Angels at the north edge, Devils at the south). It refuses you while in combat or inside a dungeon run.
2. **Camps:** a paved plateau with tents and banners in your realm's colours, lamps and a "Return Home" portal; the HUD shows SAFE ZONE. A shimmering ring marks each camp. You walk in and out of your own camp freely; if the other realm steps inside, the server moves them straight back out with a message (no spawn camping). "Return Home" is blocked while in combat.
3. **The desert and the oasis:** dunes, mesas and rim cliffs; the HUD shows "⚔ WAR ZONE · PvP" and the lighting turns warm desert. The oasis in the middle (pool, palms, arches, market tents) is **open PvP ground** guarded by Sand Scarabs and Dune Stalkers.
4. **PvP (Angel vs Devil, Test → 2 players):** fight anywhere outside the camps. Leaving your camp gives a short protection bubble. A higher-level attacker hits a lower-level player as if at most 5 levels above them.
5. **Defeat:** non-graphic; you return to your own capital with no item or EXP loss. The winner sees "Victory over …" (not again for the same victim within 30 minutes).
6. **Creatures:** packs at camps across the dunes and around the oasis; they respawn 30 s after falling.
7. **Animations across players:** each player sees the other realm's attacks, idle and sprint animate even when they met far from where they spawned.

## War zone checks (Phase 13: Jungle Rift, D-43)
Server Output: `Jungle Rift built (… parts, in … s)`. Everything from the Desert checks applies here too (camps, PvP, defeat, credit rules).
1. **Gate:** the "Jungle Rift" gate on the right side of each capital is open and takes you to **your realm's camp** (Angels north edge, Devils south): stilt huts with thatched roofs, banners, lamps, "Return Home" portal; HUD shows SAFE ZONE.
2. **The jungle:** humid green lighting and haze; rolling ground with dense rainforest trees, palms, ferns and bushes; mossy rock outcrops; rock cliffs at the edges (invisible walls stop you on them).
3. **The waterfall:** in the middle, the river pours over a tall cliff into a deep pool: translucent layered water, white streaks, falling spray and mist, foam and boulders; vines hang down the cliff. The plaza around the pool (flagstone walk, ruined columns and arches, braziers, a glowing crystal islet, lily pads) is **open PvP ground** with Thorncrawlers and Jungle Prowlers.
4. **River and bridges:** the river leaves the pool eastward (stone bridge beside the plaza, two rope bridges further east). Up on the highland west of the falls (climb the gentle north or south slopes) the upper river has a stone and a rope bridge, and starts at a small spring cascade by the west rim. You can also swim.
5. **Creatures:** Jungle Prowlers, Thorncrawlers and Mossback Golems (elite) at overgrown shrines; they respawn 30 s after falling.
6. **Performance:** walk the whole zone on a low graphics level / mobile emulation; report any hitching near the waterfall or in the forest.

## Dungeon checks (Phase 9, D-42)
Server Output: `mob AI ready (8 Hz)` and `dungeons ready (Rift Hollow, one per realm)`; boss kills log `… defeated in the … dungeon; returns in …`.
1. **Training Grounds:** 5 Rift Sprites in each yard; 20 EXP each; five take a new character to level 1.
2. **Party:** "+ Party" (left, under the HP bar) invites players of your realm; Accept/Decline popup; ★ marks the leader, who can remove members (×).
3. **Gate:** the Rift Dungeons gate (back of the capital) takes you to **your realm's** Rift Hollow (level 1+). Everyone of your realm shares it, so you may meet other players inside.
4. **Map:** a large open ruin: Shattered Entry Hall → Crystal Gallery → Guardian's Sanctum, wide corridors, no doors. The tracker (top right) shows where you are, the mini boss and boss status, your party, and the boss's health while fighting it. Leave from the tracker or the exit portal at the entrance.
5. **Respawns:** regular creatures come back about 45 s after falling. The **Stoneback Guardian** (mini boss, end of the Crystal Gallery) returns after 20 min and the **Rift Guardian** after 3 h; **in Studio** after 1 min and 3 min. Altars above their posts show "awake" or the countdown.
6. **Creatures:** they amble around their posts when idle and look around, walk / gallop with matching leg motion, bank into turns, crouch before attacking and lunge, recoil when hit and collapse when defeated.
7. **Boss:** red ground warnings (Slam circle, Sweep cone, Shockwave ring with a safe centre), wolves at 60%; if nobody is alive in its room for a few seconds it resets.
8. **Rewards:** kill EXP shared with your party nearby; each mini-boss / boss kill also gives everyone who hit it a one-time bonus ("… defeated! +… bonus EXP").
9. **Defeat:** you come back beside your party leader (or another party member) inside; if none is alive in there, outside the gate.

## Capital checks
Server Output: `Skyreach Citadel built (… parts)` and `Emberdeep Bastion built (… parts)` (budget ≤ 1,000 each).
1. **Skyreach Citadel (Angels):** bright sky and golden bloom; white-gold cathedral with twin bell towers, rose window and a floating gold ring behind the spawn; spired corner towers; colonnades with blue banners; gold lamps; the city floats on a rock island over clouds, with floating islets.
2. **Emberdeep Bastion (Devils):** ember-red dusk; black keep with a glowing portcullis, lava moat and spiked towers; braziers with fire; the city stands on pillars over a lava sea with lava falls, jagged spires, drifting embers and a volcano beyond the training yard.
3. **Gates:** Desert Rift (left), Jungle Rift (right), Rift Dungeons (back, beside the landmark). They are sealed (force-field barrier, "Opens with the … update").
4. **Lighting** changes smoothly between the two capitals and the selection view.
5. **Mobile:** walk the plaza on a phone emulator; frame rate should stay smooth.

**Preview tools** (`tools/world`, not shipped): `lune run tools/world/dump_capitals > build/capitals.json` runs the real builder offline, then `python tools/world/render_capitals.py build/capitals.json build/capitals` draws top and side views.

## Adding approved outfit art (Creator Store)
Follow **`docs/ASSET_GUIDE.md`** (beginner-friendly). In short: insert a free Creator Store model, run `tools/studio/PrepareAccessory.luau` in the Command Bar (removes scripts and makes it a slot-tagged Accessory), then Save to File into `assets/Outfits/<_Angel|_Devil|LookName>/<Slot>.rbxm`. Each approved slot (Body, Cape, Wings, Halo, Horns, Tail) replaces only the matching built-in piece. Record credits in `assets/CREDITS.md`.

## How pure tests load game modules
Game modules use normal Roblox requires (`require(script.Parent.X)`, `game:GetService("ReplicatedStorage").Shared...`) so luau-lsp type-checks them. `tests/pure/loader.luau` emulates just enough of the DataModel (ReplicatedStorage.Shared → `src/shared`, ServerScriptService.Server → `src/server`) to run them under Lune. Any other service is unavailable, so a module that needs the engine fails to load. That's how the "pure module" rule is enforced. In specs: `local load = require("../loader")` then `load("src/shared/Logic/XPTable")`.

## Layout
See `docs/ARCHITECTURE.md` §4. In short:
- `src/server` → ServerScriptService.Server (bootstrap, Loader, Services, Config)
- `src/shared` → ReplicatedStorage.Shared (display-safe only)
- `src/client` → StarterPlayerScripts.Client
- `tests/pure` → Lune tests for modules with no Roblox APIs
- `tests/studio` → scripts that need the engine

## Adding a remote
1. Declare it in `src/shared/Net/Registry.luau` with an argument schema and a rate limit (and `states` and `permission` where needed).
2. In the owning service's `Init`, call `NetService:Handle(name, fn)`. The handler receives already-validated arguments.
3. Add negative tests (wrong types, extra arguments, flooding) per `docs/SECURITY_MODEL.md` §8.

## Adding a service
1. Create `src/server/Services/<Name>.luau` with `Init` (wiring only, no yields) and/or `Start`.
2. Add it to `src/server/Services/Manifest.luau` with its layer (`ARCHITECTURE.md` §5.1).
3. `lune run tests/pure/run` checks the layering rules.
