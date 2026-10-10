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
