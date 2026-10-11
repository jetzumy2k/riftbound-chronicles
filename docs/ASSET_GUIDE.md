# ASSET_GUIDE.md — Adding free Creator Store art (beginner guide)

This guide shows you how to find free 3D models on the Roblox Creator Store, make them safe and wearable, and get them into the game. The first time takes about 15 minutes. After that, each item takes about 3 minutes.

You don't write any code. A helper script does the technical part.

---

## Part A: one-time setup

### A1. Install the Rojo plugin into Studio
Rojo syncs the `assets/` folder into Studio live, so you see new art without rebuilding.

1. Close Roblox Studio.
2. In a terminal opened in the project folder, run:
   ```
   rojo plugin install
   ```
3. Open Roblox Studio again. You'll now see a **Rojo** button in the **Plugins** tab.

### A2. Open the game with live sync
1. In the terminal, run:
   ```
   rojo serve
   ```
   Leave this window open while you work.
2. In Studio, open `build/RiftboundChronicles.rbxlx` (File → Open from File).
3. Go to **Plugins → Rojo → Connect**. The Rojo panel should say *Connected*.

From now on, anything saved into `assets/` appears in Studio automatically, under **ServerStorage → RC_Assets**.

### A3. Show the panels you need
In Studio's **View** tab, turn on:
- **Toolbox**: where you find free models
- **Explorer**: the list of everything in the game
- **Properties**
- **Output**: messages from scripts
- **Command Bar**: a one-line box at the bottom where you paste the helper script

---

## Part B: adding one item (repeat for each)

### B1. Find a model
1. In the **Toolbox**, open the **Creator Store** tab and choose the **Models** category.
2. Type a search term from the shopping list (Part C), for example `angel wings`.
3. Click a result to open its details. Pick it only if it passes **every** check:

| ✅ Check | Why |
|---|---|
| It is **free** | We only use free Creator Store assets |
| Good rating and many favourites | Quality signal; avoids broken uploads |
| From a creator with other well-rated items, ideally **verified** | Reduces the risk of hidden malicious scripts |
| Made of **MeshParts** (smooth shapes), not dozens of plain blocks | Looks far more realistic |
| Fewer than about 60 parts | Phones stay smooth |
| No real-world brands or characters (e.g. named anime or game heroes) | Copyright and Roblox rules |
| Modest and non-graphic: no blood, gore or revealing designs | Our 9+ audience (CLAUDE.md §2, ART_DIRECTION §7) |
| No real religious symbols (crosses, pentagrams) | Fictional factions only |

4. Click **Insert**. The model appears in the world and is listed in the **Explorer** under **Workspace**.

> 🛡 If Studio warns that the model **contains scripts**, that's OK. The helper script deletes them. Never move a free model's scripts into the game.

### B2. Run the helper script
1. In the **Explorer**, click the model you just inserted. Select only that one.
2. Open `tools/studio/PrepareAccessory.luau` in a text editor.
3. Change the two lines marked **EDIT ME**:
   - `SLOT`: what it is: `Wings`, `Halo`, `Horns`, `Tail`, `Cape`, `Body` or `Weapon` (held in the right hand)
   - `LOOK`: who wears it:
     - `_Angel` = every Angel look (easiest; recommended for wings and halos)
     - `_Devil` = every Devil look
     - or one look only: `Dawnlight`, `Moonsilver`, `Rosegleam`, `Skyward`, `Emberhorn`, `Obsidian`, `Crimson`, `Violet Flame`
4. Copy the **whole file**, click into the **Command Bar**, paste and press **Enter**.
5. The **Output** shows ✅ *Prepared "_Angel_Wings"…* and tells you exactly where to save it.

### B3. Save it into the project
1. In the **Explorer**, open **ServerStorage → RC_Import**. Your new item is selected.
2. Right-click it → **Save to File…**
3. Browse to `riftbound-chronicles/assets/Outfits/<LOOK>/` (e.g. `assets/Outfits/_Angel/`).
4. Name the file after the slot, e.g. `Wings.rbxm`, and click **Save**.
5. Delete the inserted copy from **Workspace** and the item in **RC_Import**. The saved file is now the real one.

### B4. Test it
1. Press **Play**. Pick the race. You should wear the new item in place of the built-in one.
2. If it is **in the wrong place, size or direction**, stop Play. Back in `PrepareAccessory.luau`, adjust the optional values and redo B1–B3:
   - `TURN = Vector3.new(0, 180, 0)` if it faces backwards
   - `OFFSET = Vector3.new(0, 0.5, 0.3)` to move it up 0.5 and back 0.3 studs
   - `SCALE = 0.8` to make it smaller
3. When it looks right, write a line in `assets/CREDITS.md`. Right-click the model in the Toolbox → **Copy Asset ID** to get the ID.

### B5. Commit
Tell me "commit the new assets" and I'll commit and push them. Or use git yourself.

---

## Part C: shopping list

Start with the race features. They make the biggest visual difference and are the easiest to find.

| Priority | Save to | SLOT | Search terms to try |
|---|---|---|---|
| ⭐ 1 | `_Angel/Wings.rbxm` | Wings | `angel wings`, `white feather wings`, `holy wings accessory` *(any wording is fine for searching)* |
| ⭐ 2 | `_Angel/Halo.rbxm` | Halo | `halo`, `golden halo`, `glowing halo` |
| ⭐ 3 | `_Devil/Wings.rbxm` | Wings | `bat wings`, `dragon wings`, `dark wings` |
| ⭐ 4 | `_Devil/Horns.rbxm` | Horns | `horns`, `demon horns`, `curved horns` |
| 5 | `_Devil/Tail.rbxm` | Tail | `devil tail`, `dragon tail` |
| 6 | `_Angel/Cape.rbxm`, `_Devil/Cape.rbxm` | Cape | `cape`, `knight cape`, `royal cape` |
| 7 | `<Look>/Body.rbxm` | Body | `fantasy armor`, `knight armor`, `paladin armor` (see note) |

**Note on armour (Body):** full armour sets from the Creator Store are usually whole character models, which don't convert well into one accessory. Our built-in armour stays in place until a proper set exists. The best route to concept-art-quality armour is an artist (Blender) or layered-clothing items. We'll revisit this in the art pass (Phase 15/16).

---

## Troubleshooting
| Problem | Fix |
|---|---|
| "Select exactly ONE model" | Click only the model in the Explorer, not several items |
| "This model has N parts" | Choose a lighter model (fewer parts) |
| The item doesn't appear when playing | Check that Rojo says *Connected*, and that the file is in `assets/Outfits/_Angel/` (or the right look folder) with a `.rbxm` extension |
| It floats far away | Set `OFFSET` closer to zero, or the model's own origin is odd; try another model |
| Built-in wings still show as well | The `SLOT` was wrong. Re-run with the correct SLOT |
