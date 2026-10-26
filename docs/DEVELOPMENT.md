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
1. **Skill tree:** press **K** or tap **🌟 SKILLS (n)** on the right edge. Each class has 4 branch columns x 6 tiers, 24 skills (Warrior: Blademaster / Ironclad / Warlord / Vanguard; Healer: Light / Sanctity / Judgment / Seraph; Archer: Marksman / Venom / Ranger / Windrunner; Mage: Pyromancy / Cryomancy / Arcanist / Stormcaller). Every node and branch has a **drawn icon** (no empty boxes), a rank badge `n/5` (specials, round icons: `n/3`), a padlock + "Lv N" while locked, and **LEARN / +RANK** when a point can be spent. Lines join each skill to the one it needs. The tree scrolls and keeps its scroll position when you learn.
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

## HUD reorganised (D-98)

1. Desktop: level + EXP, HP + Focus and the zone badge sit in Roblox's top bar, right of Roblox's buttons; the 🎉 chip (during an event), 📐 and (staff) 🛠 at the right end of that row. The left side of the view is empty unless a buff runs (badges top-left) or you are in a party (panel under them). Hover each top-bar piece: it explains itself.
2. Desktop: SKILLS, BAG and the 🧪 potion stand in the bottom-right corner; the skill bar stays at the bottom centre; the quest card top-right.
3. Phone emulator (iPhone XR landscape): the same top-bar row (shorter bars, zone as an icon); the left side free; the combat cluster on the right as before. Switch the emulator to touch input: Roblox's thumbstick (bottom-left) and jump button (bottom-right corner) appear in the spaces kept free for them.
4. Open a panel: the top bar hides with the rest of the HUD and comes back on close. Toasts appear in the free top gap (one at a time on phones).
5. 📐 Edit HUD: party, SKILLS, BAG, potion and quest can still be moved; the top bar can't.

## Phase 21: security (D-97)

Details: docs/security/SECURITY_REVIEW.md.

1. Play normally for a while: run, sprint, dash skills (e.g. a Warrior lunge), portals, the war-zone camps, dungeon floors. You are never pulled back ("rubber-band"). If you are, send the Output lines with "AntiExploit".
2. Output on start: "movement validation mode: Enforce".
3. Spam buttons (skills, potion, bag) as fast as you can: requests may be refused (rate limit) but you are never kicked.
4. (Optional, private test place only) An exploit tool that fires remotes with wrong arguments is kicked after 20 within a minute ("TamperKick" in the Log tab); a speed / teleport hack is pulled back.

## Icons, labels and tooltips (D-96)

1. Use two Mall buffs (e.g. Scroll of Insight and Draught of Might): badges appear under the 🎉 chip, "✨ EXP / 60m" (green ring) and "💪 ATK / 30m" (orange ring). Hover one (mouse) or tap it (touch): a card with its name, effect, minutes left and that another one adds time.
2. Use more buffs than fit on a phone: the last badge reads "+2"; its tooltip lists the rest.
3. Item Mall: every card shows its effect line ("+50% EXP · 60 min"); hover a card for the full description, price and how many you own.
4. Bag: only owned materials plus potions and stones are listed; each row has an effect line; hover / tap a row for its description.
5. Hover the 🧪 potion, 🎒 Bag, 🌟 Skills, 📐, 🛠 (staff), Auto and 🎉 buttons: each explains itself and its key. On touch, hold one half a second for its tooltip; a normal tap still does the action.
6. (Review fix) In a capital: the 🛡 SAFE ZONE badge and the +Party panel no longer overlap (also on a tall window). Admin panel > Players > Items: "Give stones, potions and buffs" shows names ("🔷 Draught of Clarity") with the effect under it; tapping cycles through all items. Hover 🛠 and open the panel: the tooltip closes.

## Phase 20: balance changes (D-95)

Numbers and reasons: docs/balance/BALANCE_REVIEW.md (regenerate the simulation with `lune run tools/balance/simulate > docs/balance/SIMULATION.md`).

1. A new character: killing Rift Wolves gives a few EXP each (about 5 at level 1); level 1 takes a few minutes, not seconds. Quest EXP is unchanged.
2. Floor 3 creatures give about 1-2% of a level each (they gave about a third).
3. Creatures hit noticeably harder: a level-matched creature takes about half the hits it did to defeat you.
4. Item Mall > Gear sets: only the Legendary set is for sale.
5. New Archer armour drops can roll Max HP and Defense.
6. Floor and field bosses have about 15% more HP.

## Phase 19: mobile / multi-device pass (D-94)

Studio > Test > Device emulator. Start an event (e.g. Double EXP) and use a buff (Mall) so both chips show; have a quest active.

1. iPhone SE / iPhone 8 / iPhone 14 in landscape: the 🎉 chip (short form "🎉1 59m") and the buff chip (icons) sit in a free spot: never over the HP / Focus bars, the quest card, SKILLS / BAG or the combat buttons. Tap the 🎉 chip: the board opens.
2. Same phones: trigger toasts (open a chest, buy in the Mall): one toast at a time, not over the quest card or buttons, not over the chips.
3. Portrait phones and tablets / desktop: chips at the top between the HUD and the quest card (full text on tablets and desktops); toasts in a free strip.
4. Item Mall on a landscape phone: the tabs sit in the header row (← Bag, tabs, MP, Close), a row of cards fits fully; tap a card: details with ← Back to list. On a tablet: cards and details side by side.
5. Rotate / resize the window: chips, toasts and the Mall re-place themselves.
6. Walk through docs/MOBILE_CHECKLIST.md's "Studio check" column.
7. (Review fix 2026-10-26) Open the bag, the skills, the quest log, the Mall or the event board: the HUD, skill bar, combat buttons, SKILLS / BAG / quest / party pills and chips disappear; closing the panel brings them back. In the Mall the cards' borders (and the selected card's ring) are whole on every side, the title sits next to ← Bag.

## Item Mall stage 1 (D-93)

1. Admin panel > Players > you > Progress: Add Mall Points 10000 (Robux packs need the creator's Developer Product ids first).
2. Open the bag: the header shows Mall Points; press 🛒 Mall (or key N). Tabs Buffs / Stones / Sets / Points; the title shows your MP.
3. Buy a Scroll of Insight: first tap shows "Confirm 60 MP?", second buys; MP go down, the scroll is in the bag. Use it: "Scroll of Insight is active", a 📜 60m chip appears under the event chip; creature EXP is 1.5x (2.5x with Double EXP running, never above 3x).
4. Draught of Might / Iron / Vigor / Clarity: damage, Defense, Max HP (HP bar), max Focus rise for 30 minutes and go back when they run out (chip disappears).
5. Scroll of Rebirth with attribute points spent: all points come back at once (even right after a free reset).
6. Stones tab: buy Perfect Stones (the only stones sold since D-99); they appear in the bag.
7. Sets tab: each set lists every piece with its fixed attributes; buy one with a nearly full bag: refused ("not enough room"); with room: every piece arrives with exactly the listed attributes.
8. Points tab: packs show "Not on sale yet" until product ids are set. After the creator sets them: a Studio test purchase adds the points once (re-test a purchase: no double points).
9. Not enough MP: Buy is refused with "Not enough Mall Points".

Mall layout (reworked): ← Bag returns to the bag; Get MP opens the 💠 tab; tabs show cards under headings; tapping a card shows its details and Buy (narrow screen: details replace the cards, ← Back to list returns).

Event rewards (stage 2, reworked), 🛠 > 🎉 Events:

10. The tab lists events under ⚡ Boosts, 🌍 World events, 🗺️ Hunts, 🏆 Challenges. Tap Double EXP: its page shows About, 1. How long, 2. Bonus rewards ("This event's boost is the reward, so it takes no bonus rewards."), 3. When. ← All events goes back.
11. Open Nullborn World Boss: 2. Bonus rewards says who gets them ("everyone who helps defeat one of the event's creatures or bosses") and offers only 💠 Mall Points, 💎 Stones, 🔶 Gear sets. Add 500 Mall Points (quick button 500, + Add) and a Legendary set; ▶ Start now. The list's "Live now" card shows "🎁 500 Mall Points, Legendary Set"; the players' 🎉 board says who gets them.
12. Help defeat the Herald (its summoned Abyssal Knights don't count): toast "Event reward: ..."; paid once per run. Treasure Hunt with a reward: paid on opening the first chest.
13. As a Moderator with the event grant: 2. Bonus rewards says only an Owner or Admin can add them.

## Phase 18 stage 3: hunts and challenges (D-92)

Studio Play as Player1 (Owner), 🛠 > 🎉 Events (every event now has Start / Schedule).

1. Treasure Hunt: tap the 🎉 chip: the board lists 5 clues. Go to the Desert / Jungle Rift and follow one: a chest with a glowing lid stands there; hold "Open": "+500 Gold, 2 stones" and "Chest opened: 1 of 5". Opening it again says you already did. All 5: title Treasure Seeker.
2. Hidden Chest Hunt: 12 plain chests across both war zones; 8 give the title Keen Eye. Stop the event: the chests vanish.
3. Angel Defense (as an Angel): every minute a wave of 6 Rift creatures comes into your capital's training yard ("Wave 1 of 5"); the board counts defeats. Stop the event: remaining creatures vanish and every defender gets 500 Gold + 1 stone (10+ defeats: Realm Defender).
4. Race Challenge / Cross-Race Tournament (local server, 2 players of different realms, level 10+ or Studio min level): win fights in a war zone; the board shows the realm score and the top 5. When the event ends, fighters are paid (winners more; tournament top 3).
5. PvP Arena Rush: a credited victory gives 10 PvP Marks instead of 5.
6. Cosmetic Parade: stand in a capital for 5 minutes: 200 Gold and the title Parade Star (only once per parade).
7. The board refreshes while open; Close or another panel closes it. Phone emulator: the board fits and scrolls.

## Phase 18 stage 2: world events (D-91)

Studio Play as Player1 (Owner), 🛠 > 🎉 Events; travel to a war zone (Studio min level 1).

1. Rift Beast Invasion: six packs of Rift Wolves with a Rift Guardian appear round the oasis in both war zones (level 32-33). Defeating them gives EXP and sometimes stones. Stop the event: the remaining ones vanish.
2. Elite Mob Swarm: a ⭐ golem stands beside every other creature camp.
3. Mythical Boss Invasion: a warning toast; in the Desert Rift two Jungle bosses (Camazotz, Mapinguari), in the Jungle Rift two Desert bosses (Ammit, Sphinx), with their sigils, abilities and boss loot.
4. Nullborn World Boss: a warning to everyone; the Nullborn Herald (violet, horned, 👑, two-ring sigil and shard crown) stands east of each oasis and summons Abyssal Knights. Defeat it or stop the event (it leaves).
5. Boss Frenzy: a war-zone boss you defeat returns in a quarter of the time (its post's billboard shows the shorter wait).
6. Desert Storm in the Desert Rift: thick sandy haze, dim light, sand blowing across. Jungle Flood in the Jungle Rift: rain and a grey gloom. Rift Eclipse anywhere outside the dungeons: violet dusk. Each eases back when stopped. Weather stays in its zone (no sandstorm in the jungle).
7. Frame rate on the phone emulator in the storm, the flood and an invasion.

## Attribute points (D-90)

0. Attack a creature: damage numbers appear and it loses HP (the first build broke combat setup).
1. On joining (and on each level-up) a toast says "N attribute points to spend: open 🌟 Skills, then 📊 Stats". Open the skill screen (🌟 or K): with no skill points left it opens straight on Attributes; otherwise the green "📊 Stats (N)" button switches to it. "Points to spend" shows 5 x your level (a level-12 character: 60). The 🌟 toggle counts skill + attribute points.
2. Press +1 / +5 on each attribute: the value rises, the effect line updates (e.g. "+6% Max HP · +6% Defense"), points go down; buttons grey out at 0 points.
3. REC: the HP bar's maximum rises. WIS: the Focus bar fills higher (it regenerates up to the new max). STR on a Warrior / Archer, INT on a Mage / Healer: hits do more damage. The "wrong" damage attribute says it does nothing for your class.
4. AGI: put points in, let a creature hit you: sometimes "💨 DODGE" shows and no damage is taken (at 60 points about 3.6% of hits).
5. Reset: all points come back; a second Reset says how many hours until the next free one.
6. Leave and rejoin: the points are still spent. Admin panel: set your level lower than your spent points allow: all points come back.
7. Phone emulator: the Attributes page fits, buttons are easy to tap, the 📊 / 🌟 switch works.

## Phase 18 stage 1: event engine and reward events (D-89)

Studio Play (Player1 is Owner); open 🛠 > 🎉 Events.

1. Pick 30 min, press "Start now" on Double EXP Weekend: a toast "Event started: ✨ Double EXP Weekend..." and a 🎉 ✨ chip at the top centre with the time left; tap the chip to list it. The Events tab shows it running with a Stop button.
2. Defeat a creature: the EXP gained is doubled (compare before / after). Start Class Mastery too: EXP is 2.25x; the chip shows both icons.
3. Stop Double EXP: "Event ended" toast, EXP back to normal. Starting it again right away is refused ("ran too recently").
4. No-Cooldown Training: in a capital's training yard skills recharge almost at once; outside the yard, normal cooldowns.
5. Healing Festival (as a Healer): heals and shields are 50% bigger.
6. Rare Attribute Weekend: new drops roll noticeably better attribute values. Legendary Hunt / Double Drops: more and rarer drops in the dungeon.
7. Schedule (fixed 2026-10-25): pick Today, type a time 2 minutes from now (your local time, e.g. 14:32): the preview line turns green ("Schedule starts ... (in 2m)"); press Schedule on Triple Quest EXP: it appears under Running and scheduled as "starts ... your time", then starts by itself (toast and chip). A past time shows in red and is refused; Cancel removes a scheduled one. Pick Tomorrow / another day for later dates.
8. Greyed events (e.g. Nullborn World Boss) say "Arrives in Phase 18 stage 2" and have no buttons.
9. Local server test, 2 players: Player2 (not staff) has no 🛠 button but sees the chip and the toasts.
10. Output: no errors; the Log tab shows EventStart / EventStop entries.

## Phase 16 stage 6: creature language and boss silhouettes (D-88)

1. Elites (e.g. Stoneback Guardian) show ⭐ after the name; every boss shows 👑.
2. Floor 4, Hall of Thirty: each mini boss stands on a single glowing ring in its element's colour (Yeti and Fenrir pale blue, Nemean Lion gold, Echidna violet, Grendel crimson...), bodies tinted to match. Harpy Queen / Cockatrice / Arachne are visibly smaller, Yeti / Tarasque / Minotaur bigger; the Tarasque has spikes, the Taotie horns.
3. Floor bosses (Cerberus, Chimera, Basilisk) and the field / sanctum Bosses: two rings with diamond rune marks, and rift shards circling over the head (over the middle of Cerberus's three heads).
4. Let a boss enrage (or wait out its timer): the sigil turns red and spins fast. A flying boss (Chimera, Typhon) keeps its sigil on the ground below it.
5. Defeat a boss: the sigil and crown fade out with it. Walk far away and back: no marks left floating.
6. Frame rate on the phone emulator in the Hall of Thirty.

## Phase 16 stage 5: dungeon floors (D-87)

1. Play, check the Output: both `RiftHollow_* [Dungeon]` lines about 6,100 parts, 160 lights, no warning.
2. Enter the Rift Dungeons on each floor: every room has a stone ceiling with rib beams (no sky), corridors as before. Crypt rooms have crystals hanging from the ceiling, Ember rooms chains with glowing cages, Frost rooms icicles, the Nullborn floor shards floating in the air. The middle of each room stays clear.
3. The rooms are darker but readable: candles and crystals light them. If anything is too dark, send a screenshot.
4. Flying creatures (e.g. the Chimera in its den, Typhon) still take off and circle below the ceiling, never through it.
5. The landing's portal gates and their name plates are fully visible under the ceiling. Dust motes drift in the air.
6. Check the frame rate inside a dungeon on the device emulator (phone).

## Phone landscape controls (D-86)

Use the device emulator (iPhone XR / iPhone 14 / iPhone SE, landscape):

1. The skills ring the attack button in two arcs in the bottom-right corner; the middle of the screen (your character) stays clear. The potion and the Auto switch sit at the ends of the outer arc.
2. RUN and CROUCH sit side by side just above the jump button; above them 🌟 (skill points shown as 🌟3) and 🎒 icon buttons open the skill tree and the bag.
3. The quest card sits at the top right, left of the icon column; nothing overlaps.
4. Empty skill slots show just "+". Long-press a skill still explains it.
5. Rotate to portrait: the paged column layout is unchanged. On a tablet / desktop the row layout and labelled SKILLS / BAG pills are unchanged.
6. If you had moved SKILLS or BAG with 📐 Edit HUD, they stay where you put them; Reset puts them in the new spots.

## Phase 16 stage 4: capital landforms (D-85)

1. Play, check the Output: both capitals' `[WorldBudget]` lines (Skyreach about 857 parts, Emberdeep about 753, 2 emitters each) and no warning. Note the boot time on the `[Loader] booted` line.
2. Skyreach Citadel: walk to the platform edge and look down. The island under it is one craggy rock tapering to a point with hanging spires and glowing crystals at their tips; three waterfalls spill off its sides into the clouds with mist. The floating islets sit on rocks. Nothing sticks up through the plaza.
3. Emberdeep Bastion: from the spawn, look past the training yard. The volcano is a smooth ridged cone with a crater, a glowing lava lake inside, six winding lava streams down the flanks and smoke rising from the top.
4. Check the frame rate in both capitals on the device emulator (phone).

## Phase 16 stage 3: Jungle Rift art (D-84)

1. Play, check the Output: `[WorldBudget] Jungle Rift [WarZone]` should be under 7,000 parts (expected about 6,300) with no warning. Send the line.
2. Grass terrain should show animated grass blades swaying in the wind (both war zones). If it doesn't, select Workspace > Terrain in Studio and tick **Decoration** (Rojo live sync may not apply Terrain properties).
3. In the Jungle Rift: the waterfall cliff and the rock outcrops show grey / slate / earthy rock layers; stones break the river surface and boulders sit on the banks, never on a bridge.
4. The forest is denser; a few giant trees rise well above the canopy; mossy logs lie on the floor.
5. Under the canopy, faint light motes drift past the camera, the water looks emerald, and sun rays show when looking toward the sun. Back in the desert the sand drifts and the water turns turquoise; in the capitals both stop.
6. Check the frame rate in the jungle on the device emulator (phone).

## Phase 16 stage 2: Desert Rift art (D-83)

1. Play, check the Output: the `[WorldBudget] Desert Rift [WarZone]` line should show about 1,800 parts, still 31 lights, and no warning. Note the build time on the `Desert Rift built` line (was 0.2 s).
2. Enter the Desert Rift. Look at the buttes: a sheer top cliff, stepped ledges below, and coloured rock layers across the faces. Check the hoodoo spires have a darker cap stone and the three stone arches stand (you can walk under them).
3. Walk the dunes: cacti, dry shrubs and small boulders; nothing stands in a creature camp, on a boss, or inside either realm's camp. The ruins sites have a fallen obelisk and broken columns.
4. At the oasis: reeds at the water's edge, lily pads, an outer ring of palms, and a wooden pier on the east side.
5. Thin sand should drift past the camera in the desert only; it stops when you leave. Check the frame rate in the desert on the device emulator (phone).

## Phase 16 stage 1: zone budgets (D-82)

1. Play in Studio and open the Output. For each capital, war zone and dungeon copy there is one `[WorldBudget]` line, like `Skyreach Citadel [Capital]: parts 812/1400 (58%), ...`.
2. Any zone over its budget prints a warning naming the fields that are over. Send the lines (copy or screenshot) so the budgets can be set from real numbers.
3. Optional: on a phone (or the device emulator), press Ctrl+F6 for the MicroProfiler in each zone and note the frame time.

## Creature faces (D-81)
Every creature's eyes were rebuilt: larger, brought forward out of the skin, each with a glowing iris, a dark pupil (slit for serpents, dragons, cats, griffins and gorgons; round for the rest) and a white highlight. Only the meshes changed, so each shape must be **re-imported**:
1. Studio: **File > Import 3D**, pick `build/creatures/<Name>.gltf` (defaults, rig and skinning on, units **studs**).
2. Right-click the imported model > **Save to File...** > `src/server/CreatureModels/<Name>.rbxm` (**replace** the old file), then delete it from the Workspace.
3. Do this for the 16 shapes in that folder: Hound, Cerberus, Serpent, Hydra, Beetle, Spider, Golem, Knight, Lion, Chimera, Dragon, Griffin, Steed, Bat, Harpy, Gorgon. Knight, Harpy and Gorgon have visor / slit eyes and are unchanged, so they can be skipped.
A shape not re-imported yet just keeps its old eyes.

**Checks**
1. Close up, each creature's eyes show a coloured iris, a dark pupil and a small white highlight, and they move with the head (looking round, biting, flying).
2. An enraged creature (low health, or an impatient boss): the eyes flare brighter along with the embers.
3. Defeat: the eyes go dark and the highlight disappears as it falls (no gore, CLAUDE.md §18).
4. Nothing glows white by mistake: hit sparks and embers keep the creature's own colour.

## Phase 15: facial expressions (D-79)
Use a local server with 2 players so you can watch the other character's face up close (zoom in; the face only moves within 70 studs).

**Checks:**
1. Standing still: the face is relaxed and blinks every few seconds (both eyes, quick).
2. Attack a creature: brows lower and the jaw sets during each swing (Effort); between swings the brows stay a little down (Focused) and relax about 8 s after the fight.
3. Take a hit: a short squint and wince, then back.
4. Get defeated: the eyes close softly (no blinking) until the respawn; after it the face is normal.
5. Level up (admin panel Set level, or kill creatures): a smile for about 3 s.
6. The other player's face does the same on your screen.
7. Mobile emulation: no slowdown with several players nearby.

## Phase 17: admin / moderator panel (D-77)
Use a **local server test with 2 players** (Test → Clients and Servers): Player1 is Owner, Player2 a normal player. In Play Solo you are Owner because you created the place. Settings changes in Studio apply to that test server only (never saved).

**Checks:**
1. Player1 sees a 🛠 button under 📐 (and F2 opens the panel); Player2 has no button and F2 does nothing.
2. Players tab: the left list shows both players at once (Search / Enter filters); tap Player2: the right side shows their name and pages Profile (overview, kick / ban), Progress, Items (give gear / stones, bag) and Quests.
3. Set Player2's level to 15, add 500 Gold, add 50 PvP Marks, set victories to 10: Player2's HUD / bag / quest log update at once; at 10 victories Player2 gets the "Skirmisher" title. Taking more Gold than they have stops at 0.
4. Give gear: search "sword", pick one, choose Legendary and item level 20, Give: it appears in Player2's bag with rolled stats. Give 5 Perfect Stones. Remove an unequipped item; an equipped one has no Remove button.
5. Reset a quest Player2 started: the log shows it can be taken again; finishing it again pays no second reward.
6. Kick Player2 with a reason: they leave with "Removed by a moderator: ...". (Ban uses Roblox's Ban API; in Studio it may refuse: the panel says "banFailed".) You can't kick yourself or another Owner.
7. Settings → 🎁 Drop rates, card "War-zone boss (PvP): gear": type Rare 70, then tap straight into Mythical and type 30 (the panel must stay open; each edited row turns gold "(unsaved)", the card shows "Weights total 100", the section button shows "(2)"), Save: "Saved 2 change(s)" and the version goes up. Set only Mythical to 30: the card shows "Weights total 110" in red and Save is refused with "Loot.Tables.WarZoneBoss: sum". "Reset" puts a value back to its default; "Discard" drops unsaved edits. Typing 150 in a 0-100 box shows a red outline and a hint, nothing is recorded. Tapping the dim area outside the panel does not close it.
8. Settings → Flags → Maintenance ON, Save: Player2 is kicked with the maintenance message, Player1 stays; turn it OFF again.
9. World → "Respawn every fallen boss now" after defeating a war-zone boss: it comes back at once.
10. Log tab: every action above is listed with your id; (with the command bar) Player2 calling an admin remote is refused and shows as "AdminDenied".
11. Mobile emulation: the panel fits and scrolls; buttons and boxes are touch size.

## Phase 14: PvP loot, victory titles, PvP Marks (D-76)
Studio: bosses return after 120 s; use two players (different realms) for the victory checks.

**Checks:**
1. Equip 4 to 6 regular skills, rejoin: the bar keeps all of them and the HUD / skill tree update normally (the D-75 snapshot fix).
2. Defeat war-zone field creatures: about 1 in 4 gives "💎 Loot: an Enhancement Stone" (now and then "a Perfect Enhancement Stone!"); the bag's stone counts go up. A party member who helped rolls separately.
3. Defeat a war-zone boss with a friend: each of you gets a Rare or (1 in 5) Mythical piece of your own class at item level 30 or below, plus "+10 PvP Marks". When it returns and falls again, you're paid again; one defeat never pays twice.
4. A level 10 alt in the party, standing by at a level 50 boss: no loot for it (level gap); level 20+ helpers get loot.
5. Defeat a player of the other realm: "Victory over <name>!", "+5 PvP Marks"; the quest log (J) shows "🗡 PvP: 1 victories · … next title « Skirmisher » at 10". Defeat the same player again within 30 min: no victory, no Marks.
6. Defeat them within 15 s of their respawn protection ending (without them attacking): no credit. If they attack you first, it counts.
7. With 10 credited victories (or set PvPStats.Victories to 10 in a test profile and rejoin): "New title: « Skirmisher »"; wear it from the log; it floats over your head.
9. Every notification shows exactly one icon at the front that fits it (❗ for warnings, 📜 quests, 🎁 loot, 💎 stones, 🏆 PvP, 👥 party ...), never two.
8. Config: set `Loot.StoneTables.WarZoneMob` weights to 30 / 60: the server logs "stone table WarZoneMob rejected (sum)" and uses 30 / 70.

## Icons and six skill slots (D-75)
1. No empty boxes anywhere: 🌟 SKILLS, the notification icons (🔔 / ❗), 📐 (HUD layout), ⭐ over a commander with a quest to hand in, ✅ on equipped items and chosen slots, status chips over heads (💫 STUNNED, 🧊 FROZEN, 🔇 SILENCED, 💚 REGEN ...), the race / job emblems on the start screens, and every bag tile (helm 👑, shoulders 🧥, axes 🔨, staff 🌟, wand 🎇).
2. Learn five or more regular skills: they fill the new slots by themselves (Auto Attack stays in slot 1). Desktop: a bar of seven at the bottom; keys 1-6 cast, Q casts the special.
3. Skill tree: the bar at the top shows slots 1-6 + SPECIAL (it scrolls sideways on a phone); a learned skill offers "Put in slot 1" to "Put in slot 6"; swapping and "Remove from bar" still work. Rejoin: the bar is kept.
4. Phone landscape (emulate iPhone SE 568 × 284 and a bigger phone): seven skill buttons in two rows left of the attack button; none overlaps the HUD, run / crouch, the potion, SKILLS / BAG or the jump button; each is easy to tap.
5. Phone portrait: three regular buttons plus the special; the small "4-6" button switches to slots 4-6 (it then reads "1-3"). A gold dot on it means a skill on the hidden page is ready. Keys and casting otherwise unchanged.
6. Security: sending SetLoadout with 7 regular skills is refused by the schema; 6 is accepted only if all are learned, regular and of your job.

## Phase 11 review fixes: panels, NPCs, movable HUD (D-74)
1. Talk to the commander: the dialogue text is bright and easy to read; the rest of the screen dims behind it; the "Talk" prompt and skill buttons no longer show on top.
2. Open the bag, then press K or the quest tracker: the bag closes and the other opens (never two at once). Tap the dim area outside a panel: it closes.
3. The commanders have skin and hair, an uncovered adult face, shining plate and a gentle idle (breathing / looking around), in both capitals.
4. Press 📐 (right of the HUD panels): gold boxes appear on Level & EXP, HP & Focus, the zone badge, Party, SKILLS, BAG, the potion button, the quest tracker and 📐. Drag a few (mouse and touch), press Save; rejoin: they stay. Reset puts everything back; Cancel drops changes. A box dragged to an edge never leaves the screen; the layout fits a different screen size (phone emulation).

## Phase 11: story and quests (D-73)
Studio skips the quest unlocks (dungeon gate, enhancement, war-zone gates) so testing isn't blocked; set config `Quests.GatesInStudio = true` to test them as live servers do.

**Checks** (a new character; "J" opens the quest log):
1. Right after choosing a job, "📜 New quest: First Spark" appears and the tracker (top right) says "▶ Go to the Training Grounds". A ◆ marker with the distance points at the yard.
2. Enter the yard: the step changes to "Defeat Rift Sprites 0/5"; kills count up; at 5, "⭐ First Spark: done!" and the tracker says "⭐ Return to <commander>". A gold ⭐ floats over the commander in front of the spawn.
3. Talk to the commander (prompt "Talk"): the dialogue shows the quest's closing words, the rewards and "Complete". Press it: EXP, an Uncommon weapon, 5 Healing Potions, "✅ Quest complete". Talk again: "Into the Rift" is offered with "Accept".
4. Quests 2-4 (the playtest gate: a new player from level 0 to Quest 4): enter the dungeons, clear 8 wolves / beetles, defeat a Stoneback Guardian; collect the three glowing Rift fragments in the Candlelit Nave, Sunken Cloister and Broken Chapel (they only show while the quest needs them); defeat Cerberus, then collect the Gate Core behind it. Each hand-in gives its rewards once.
5. Rejoin mid-quest: the tracker shows the same step and counts.
6. Steps are in order: Rift Sprites killed before reaching the yard don't count; a fragment collected twice counts once.
7. Quest 5 at level 10: stand before the great hall, then inspect the Desert and Jungle gates (glowing markers in front of them). Reward: the title "Riftwalker"; wear it from the log; it floats over your head for everyone.
8. Quests 6-8 at level 20: enter a war zone, defeat 6 of its creatures, walk out through your camp's Return portal (being defeated doesn't count); Rival Encounter completes on any hit given or taken against the other realm in a war zone.
9. Quests 9-11: three clues (oasis, waterfall, Ash Gallery on floor 2), the Basilisk (floor 3; +1 skill point shown in the skill tree), floor 4 and Typhon (final rewards, title "Nullbane").
10. With `Quests.GatesInStudio = true`: the dungeon gate says to finish First Spark, enhancing says to finish Into the Rift, the war-zone gates say to finish The Broken Gate.
11. Mobile (portrait and landscape): the tracker never covers the HUD, the SKILLS / BAG / potion buttons or skills (on phones in portrait it is a "📜 2/5" pill under the potion button); the log and dialogue fit and scroll; buttons are full size.
12. A second player of the other realm sees their own commander and quests; titles show over heads for both.

## Equipment overhaul, stage 6: bag / equipment screen (D-72)
**Checks** (open the bag with B or the BAG button; "Studio: add test gear" fills it):
1. The equipment block shows your character in 3D between the slots: armor on the left, Main hand / Off-hand / Necklace / Earrings / Ring 1 / Ring 2 on the right. It wears exactly what you wear (weapon, shield, armor meshes, jewellery).
2. Drag the character sideways (mouse or finger): it turns, and eases back when you let go. Dragging never moves the camera behind the screen.
3. Equip or unequip something: within about half a second the 3D copy updates. Respawn with the bag open: it shows the new character.
4. Select a bag piece you aren't wearing: the detail shows "If you wear it (slot):" with one ▲ (gain) or ▼ (loss) line per stat and "Takes off ..." naming what goes back to the bag; the target slot glows gold with a ▼ on the doll. Try a two-hander while wearing a sword and shield: both are named, and the shield's Defense shows as a loss.
5. Tap an empty slot: the bag shows only pieces that fit it, with a gold "<Slot> ×" chip that shows everything again.
6. "Your stats" lists HP, Attack, Defense and crit with the gear's share in brackets; it changes when you equip.
8. The preview is bright: armor colours read clearly against a lighter purple backdrop, and the character fills the frame head to toe (wings may be cut at the sides).
9. Every bag tile has an icon (earrings 💠, staff 🌟, wand 🎇; no empty boxes) for all four classes.
10. Quick potion: a round 🧪 button with the count sits above the run toggle (landscape) or under BAG (portrait); tap it or press H while hurt: you heal, it shows the cooldown seconds and dims; at 0 potions it stays dim. It never covers a skill, run / crouch or the jump button.
11. Faces: on the realm screen, Man / Woman (top right of the preview) rebuild the preview with that adult head within a few seconds. In the bag, Man / Woman on the 3D preview change your real character's head (the outfit is rebuilt on top) and the copy follows. The choice is kept after rejoining. Bodies look broader and more muscular than before.
12. Phones (portrait and landscape) and a tablet: the slots are full-size touch targets, nothing overlaps, the side column scrolls if the screen is short. Close the bag and play: no frame-rate cost remains (the copy stops updating when closed).

## Equipment overhaul, stage 3: armor and jewellery meshes (D-71)
**Importing** (once; `python tools/gear/build_armor.py` rebuilds them; previews in `build/armor/<Name>.png`):
1. Studio: **File > Import 3D**, select all 27 files in `build/armor/`: `Warrior_`, `Healer_`, `Archer_`, `Mage_` x `Helm`, `Shoulders`, `Chest`, `Hands`, `Legs`, `Boots`, plus `Necklace`, `Earrings`, `Ring`. Units: **studs**, defaults.
2. Each lands in the Workspace: right-click > **Save to File...** > `src/server/GearModels/<Name>.rbxm` (the same folder as the weapons; exact names), then delete it from the Workspace.
3. A slot without its model keeps the part-built piece, so this can be done in batches.

**Checks** ("Studio: add test gear" gives every piece of your class):
1. Each worn piece is a smooth sculpted shell that follows its body part: Warrior plate (open-faced helm with cheek and nape guards, layered pauldrons, cuirass with a ridge and crest gem plus abdomen plates, gauntlets with elbow cops, tassets / thigh plates / greaves with knee cops, sabatons); Healer robes (circlet, mantle caps, robe top with mantle collar and gem strip, cuffs and gloves, a long panelled robe skirt, soft boots); Archer leather (hood, one pauldron, jerkin with straps and a quiver, bracers, breeches with shin guards and a pouch, tall boots); Mage coat (wide-brimmed pointed hat, spaulders, coat with lapels and gem, wraps, an open robe skirt, tall boots).
2. Pieces stay on their part while walking, running, jumping and attacking (each is welded to its own part); nothing floats, the body shows where nothing is worn.
3. Tier 2 adds trims, crests, collars and capes; tier 3 the realm ornaments (Angel feathers, Devil horns, only your realm's). Glow trims take the rarity colour (Standard: plain metal).
4. Jewellery: the necklace sits at the neck with a pendant on the chest; earrings at both ears; Ring 1 on the right hand, Ring 2 on the left.
5. Mobile: a full set is about 80k triangles (about 12k a model); with 10+ armored players in view the frame rate holds.
6. A second player sees the same armor.

## Equipment overhaul, stage 4: smooth body (D-70)
Config switch: `Appearance.SmoothBody` (on). Body and head: Roblox's free "Base Body - Jordan" (bundle 994), adult proportions, athletic build (Humanoid width 1.3, depth 1.25).
1. Spawn: your character is an adult with an athletic build (broad shoulders, muscular arms and legs, full height, a head in proportion) and the matching animated face with eyebrows and eyelashes; your own hair and skin tone are kept. No "SetAccessories" / "IsLayered" warnings in the Output. Check from the front, side and back, standing and walking.
2. All players and test players get the same body proportions (no giant / tiny avatars), so armor and weapons sit the same on everyone.
3. Outfits, the shield, two-handed grips and both hands on the crossbow / staff still line up with the new limbs; nothing floats.
4. Combat, movement, jumping, sprint / crouch and respawning behave as before (the hit box is the root part, unchanged).
5. The realm-selection previews show the same body with the head on the shoulders (no long neck).
6. Output: no "smooth body not applied" warnings (if there are, the avatar keeps its own body and the reason is logged).
7. A second player sees your new body.

## Equipment overhaul, stages 2 and 5: weapon meshes and weapon animations (D-69)
**Importing the sculpted weapons** (once; `python tools/gear/build_weapons.py` rebuilds them; previews in `build/gear/<Family>.png`):
1. Studio: **File > Import 3D**, select all 15 files in `build/gear/` (Sword, Greatsword, Dagger, Mace, Axe, WarHammer, BattleAxe, Polearm, Staff, Orb, Wand, Tome, Bow, Crossbow, Shield). Units: **studs**. Keep the defaults (no rig).
2. Each lands in the **Workspace** as a model named after the weapon. For each: right-click > **Save to File...** > `src/server/GearModels/<Family>.rbxm` (exact name), then delete it from the Workspace.
3. Rojo syncs them; a weapon family without a file keeps its part-built look, so this can be done a few at a time.

**Checks** (after importing; "Studio: add test gear" gives every weapon of your class):
1. **Look:** every weapon is a sculpted model: broad bevelled blades with a glowing rune line, swept guards, wrapped grips, gem pommels; flanged mace, crescent axes, block war hammer, leaf-bladed polearm, staff with a crystal orb in a crescent cradle, wand with a crystal tip, recurve bow, crossbow with a loaded bolt, kite shield with a boss and rim. Tier 2 adds finials / collars / second axe bit / spikes; tier 3 the realm ornaments (Angel feathers, Devil horns, only your realm's). The rune lines / gems glow in the **rarity colour** (Standard: plain metal); Legendary / Mythical and +7 weapons sparkle. The shield sits on the outside of the left forearm, face out; no weapon floats or sits sideways in the hand.
2. **Two-handed** (long sword, war hammer, battle axe, polearm): both hands on the grip in the guard; attacks: a diagonal cleave from over the right shoulder, a wide chest-high sweep, an overhead slam into a lunge.
3. **Dual swords:** one sword in each hand on guard; attack 1 right-hand slash, attack 2 a mirrored left-hand slash, attack 3 both blades raised and crossed down.
4. **Short sword / mace / hand axe + shield:** the shield arm stays raised across the body in guard, the shield facing forward, through idle, walking and every attack.
5. **Staff** (Healer / Mage): held upright in both hands; attacks: a two-handed thrust, a sweeping swing, raised overhead in both hands then slammed down.
6. **Dagger:** quick forward stab, backhand slash, lunging double stab.
7. **Crossbow:** held across the body in both hands; attacks: shoulder it, aim down the stock, fire with a small recoil; the finisher holds the aim longer, kicks harder, then tips down while the left hand cranks the string.
8. One-handed swords / maces / axes without a shield keep the Warrior sword set; the bow the Archer set; orb / wand / tome the Mage set.
9. Hits still land on the animation's strike frame (damage timing unchanged); a second player sees the same animations.

## Equipment overhaul, stage 1: slots and hand rules (D-68)
Pure rules: `lune run tests/pure/run` (item_rules: hand rules, dual swords, rings, off-hand Attack; migrations v2 -> v3; loot kinds; job weapons). In Studio, "Studio: add test gear" now gives **every weapon of your class** (Warriors: two short swords), a shield (Warriors), shoulders, gloves, necklace, earrings and two rings. Pieces are still drawn with the part-built style; meshes come in stages 2-3, weapon-specific animations in stage 5.
1. **Slots:** the bag shows 12 equipment slots: main hand, off-hand, helm, shoulders, chest, hands, legs, boots, necklace, earrings, two rings. An old "Accessory" you had equipped now sits in the necklace slot.
2. **Warrior one-handers + shield:** equip a short sword, then the shield (off-hand): both stay; the shield sits on the left forearm. Same with the mace and the hand axe.
3. **Two-handers:** with a shield on, equip the long sword / war hammer / battle axe: the shield goes back to the bag and a toast says so. With a two-hander on, equip the shield: the two-hander goes back to the bag (the newest item always wins; nothing is deleted).
4. **Dual swords:** short sword in the main hand, then the second short sword's "Off-hand (dual)": one sword in each hand. Equip a mace in the main hand: the second sword returns to the bag. Trying to put the same sword in both hands is refused.
5. **Healer / Mage:** dagger, short sword and staff (plus the orb / wand / tome); no shield exists for them. **Archer:** bow (one-handed class) and crossbow (two-handed); no shield.
6. The item detail shows how a weapon is held ("Long Sword · Two-handed · no shield", "Short Sword · One-handed · shield allowed · can dual-wield").
7. **Jewellery:** necklace (pendant on the chest), earrings (both ears), rings ("Ring 1" right hand, "Ring 2" left hand). Each shows on the character; replacing one swaps it (no duplicates).
8. **Shoulders / hands:** equip and unequip them: pauldrons / gauntlets appear and disappear; the chest piece no longer includes them.
9. **Loot:** dungeon drops now include shoulders, gloves, shields (Warriors), necklaces, earrings and rings.
10. Rejoin: everything is where you left it; a second player sees the same.

## Phase 10 manual tests: dungeon loot (D-67)
Pure rules: `lune run tests/pure/run` (loot_rules: default tables valid and matching CLAUDE.md §12, invalid tables rejected, 1M-roll drop chance and rarity split within ±0.5%, drops are your own class and realm). Server log: every drop is an `Audit ... action=LootDrop` line.
1. Enter your realm's dungeon and defeat regular creatures (at a level that still gives EXP): about 1 in 8 drops an item (elites ★ about 1 in 3); a toast "Loot: <name> (<rarity>, item level N)". Drops are Standard, Uncommon or Rare (roughly 45 / 25 / 30).
2. Defeat a mini boss / floor boss / the Dungeon Boss: always a drop, Rare (about 4 in 5) or Legendary.
3. Every drop is gear of **your** class, a weapon family your realm uses, item level = the creature's level (30 at most); it appears in the bag and can be worn / enhanced.
4. **Party:** two players kill a boss together: each gets their own roll (and the boss pays each player once per spawn).
5. **Level gap:** a creature 10+ levels below you (white plate) or 20+ above (grey) drops nothing, like its EXP.
6. **Bag full** (150): the toast says the drop was lost; nothing in the bag changes.
7. **Config:** an override whose rarity weights don't add up to 100 is rejected (server log error) and the built-in table is used.

## Phase 8 manual tests: enhancement (D-66)
Pure rules: `lune run tests/pure/run` (enhance_rules: rates, the +10 cap, 20 requests on 5 stones use exactly 5, no downgrade, Perfect Stones, +20 Attack / +2.5% Crit Damage per weapon level, +8 Defense per armor level and never Attack). In Studio, "Studio: add test gear" now also gives 10 Enhancement Stones and 2 Perfect Stones (and 25 fragments = 2 more stones via Combine).
1. Open the bag (B), tap an item: the Enhance box shows "+N → +N+1", the chance (100% up to +5, then 90 / 80 / 70 / 60 / 50%), what each +1 adds, and the two buttons with your stone counts.
2. **Enhance** an equipped weapon: on success the tile shows +N, the detail "✓ Success! Now +N", a toast, and your hits get stronger (gear bonus: +20 Attack per level). Armor: +8 Defense per level, never Attack.
3. Keep going past +5: some attempts fail: "✗ Failed: still +N", one stone gone, the item unchanged (never lower, never destroyed).
4. **Perfect** always succeeds and uses only a Perfect Stone.
5. At +10 the box says "maximum reached" and no button shows; a forged request is refused (toast "already +10"), nothing is consumed.
6. Without stones the button is grey; a forged request is refused ("You don't have that stone"), nothing changes.
7. Spam the button (or fire `EnhanceItem` 20 times from the command bar with 5 stones): exactly 5 attempts happen, stones never go negative.
8. A weapon at +7 or more sparkles on the character.
9. Leave right after enhancing and rejoin: the level and stone count are what the last result said.

## Phase 7 manual tests: inventory and gear (D-64)
Pure rules: `lune run tests/pure/run` (item_rules with a 100k-roll fuzz, inventory_layout, profile_validator, profile_view). In Studio the bag's **"Studio: add test gear"** button (Studio only) gives one random piece for each slot of your class, 5 potions and 25 fragments.
1. **Open:** "🎒 BAG" (right edge, under SKILLS) or **B**. Phone portrait / landscape (Device emulator): equipment, materials and the bag scroll in one column, and tapping an item opens a sheet at the bottom with ✕. Tablet / desktop: three columns. Nothing overlaps the combat buttons.
2. **Tiles:** icon, rarity border **and** letter (S/U/R/E/L/M), item level, +N, 🔒 / ✓. Strongest first; filters All / Weapons / Armor / Accessories.
3. **Detail:** name in its rarity colour plus the rarity word, slot, family, class, item level, the piece's stats and its ◆ rolled attributes (1 for Standard / Uncommon, 2 Rare / Epic, 3 Legendary, 4 Mythical).
4. **Equip / unequip:** equip a weapon: the gear bonus updates and your hits grow (training dummy). Equipping or unequipping never changes your health fraction. In combat it is refused. An item above your level has no Equip button ("Reach level N"). Angel warriors can't wear Axes; Devil warriors can't wear Maces.
5. **Lock / salvage:** a locked item has no Salvage button and bulk salvage skips it. Salvage (tap twice): the item goes and Stone Fragments grow by its rarity (1/2/4/6/10/15). "Salvage S + U" (tap twice) clears unlocked, unequipped Standard / Uncommon pieces, 25 at a time. Equipped items can't be salvaged.
6. **Fragments and potions:** "Combine" turns 10 fragments into 1 Enhancement Stone. "Use" a Healing Potion when hurt: +30% HP, then a 15 s countdown; at full health it is refused.
7. **Persistence:** leave and rejoin: the same items (same rolls), equipment, locks, potions and fragments; equipped gear still counts after a respawn.
8. **Invalid calls** (from a client): `EquipItem` with a made-up guid, another player's guid or a chest in the weapon slot, `SalvageItems` with an equipped item, `StudioTestGear` on a live server: all refused (security log `ItemNotOwned` / `StudioOnlyRemote`), nothing changes.
9. **Bag full:** at 150 items new gear is refused with a toast; nothing in the bag is lost.
10. **Gear on the character (D-65):** a new character (or one made before gear existed) starts wearing a plain Standard set: its class weapon (Warrior sword, Healer staff, Archer bow, Mage wand), chest, legs, boots. Unequip the chest: the armour turns into a plain tunic; legs: plain trousers; boots: bare feet; weapon: empty hands. Equip a helm: Warrior open-faced helm, Healer circlet, Archer hood, Mage wizard hat (the face stays visible). Equip the accessory: a pendant and glowing wrist bands. Each weapon family has its own model (sword, greatsword, polearm, mace, axe, staff, orb, bow, crossbow, wand, tome). Tier 1 pieces are plain, tier 2 adds gems / trims / capes, tier 3 the realm ornaments (feathers or horns); trims glow in the rarity colour (Standard: plain metal) and Legendary / Mythical weapons sparkle. A second player sees the same.

## Level gap: EXP and danger colours (D-63)
Pure rules: `lune run tests/pure/run` (level_gap). Use the admin/test tools or creatures of different levels (dungeon floors span Lv 1-40; war zones Lv 9-13).
1. **Plates:** every creature shows its name and `Lv N` over its head (within 60 studs; hidden once defeated). The level's colour and mark follow the gap to **your** level: grey ☠ "Deadly · no EXP" (20+ above), red ▲▲ "Very hard" (10-19 above), orange ▲ "Hard" (5-9), yellow △ "Tough" (2-4), green (1 above to 4 below), blue ▽ "Easy · little EXP" (5-9 below), white · "Too weak · no EXP" (10+ below). The target plate shows the same colour and mark.
2. Level up: the colours update at once.
3. **EXP:** defeat a creature of each kind and watch the EXP bar: 20+ above or 10+ below gives none; 10-19 above ×1.5, 5-9 above ×1.3, 2-4 above ×1.15, about equal ×1, 5-9 below ×0.25. Dungeon boss bonus EXP follows the same rule (no "boss defeated +EXP" toast when it is 0).
4. **Party:** two players of different levels kill the same creature: each gets EXP for their own gap.

## Creature effects and sound (D-62)
Sound ids are checked with `python tools/creatures/check_sounds.py` (needs internet). Turn the game volume up.
1. **Voices:** walk up to a wolf (a howl, D-63), a lion / chimera (roar), a griffin / Anzu the Storm Bird / harpy (hawk screech, D-63), a bat (shrill screech), a dragon (deep rumbling roar, an ember breath from its jaws), a serpent (hiss), a spider (hiss), a beetle / scarab (giant-bug chitter, D-63), a golem (grinding stone, D-63), a knight. Bigger ones sound deeper. Each alert shows a ripple of air from the head.
2. **Attacks:** bites and swings whoosh; sweeps leave glowing claw streaks (one wide streak for golems / knights); slams and stomps thud with a shockwave ring and dust, and the camera shakes a little if you are close; golems crack like stone, knights clank.
3. **Footsteps:** big creatures (Cerberus, golems, dragons...) thud and kick up dust with each footfall when near.
4. **Flight:** wing beats on take-off and while circling, a rushing whoosh into the dive, an impact ring where it lands.
5. **Stagger / enrage / defeat:** a snort and dust when staggered; embers drift round an enraged creature (gone when it is defeated); a last, deeper cry in the creature's own voice (D-63), then a thud and dust as the body settles.
6. **Budget (mobile):** with 15+ creatures fighting, sounds don't pile up (at most 10 at once, nothing beyond 150 studs) and the frame rate holds.

## Creature AI and attacks (D-61)
1. **Alert:** walk up to an idle creature: it turns to you and roars briefly before it charges.
2. **Attack variety:** fight a wolf (bites, wide claw rakes, a long pounce from further out), a golem / knight (overhead smash, wide swing, a stomp that hits everyone close), a serpent (bite, tail sweep that hits behind it too), a beetle / spider (pincers, a ram from range), a dragon (bite, trample, tail sweep). Heavier moves have longer wind-ups.
3. **Dodging by moving:** circle quickly behind a creature during its wind-up: a bite or smash misses you (it turns, but not instantly). Sweeps and stomps still hit all round.
4. **Openings:** after each strike it pauses for a moment: a window to hit back.
5. **Stagger:** land a critical or very heavy hit: the creature recoils hard and its wind-up is cancelled (not more than once every 4 s; bosses never stagger).
6. **Enrage:** bring a creature below 30% health: it becomes visibly agitated, faster, and attacks more often. A boss that enrages on its timer shows the same posture.
7. **Unstuck:** lure a creature round a war-zone rock: if it snags, it hops and side-steps instead of running in place.
8. **Boss combos:** in a boss's second phase its frontal attack (cone) is followed at once by its follow-up (e.g. Cerberus: Maul then Pounce; golem bosses: Sweep then Quake).

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
