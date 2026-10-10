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
