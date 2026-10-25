# Mobile / multi-device checklist (Phase 19, PLAN.md D-94)

Every screen of the game, how its layout is checked, and what still needs a
look in Studio's device emulator. Automated checks run on the 20 device
sizes in `tests/pure/devices.luau` (phones portrait / landscape, tablets,
laptops, desktops up to 4K, a small window), as safe-area sizes (Roblox top
bar and insets removed). Rules everywhere: touch targets at least 44 px, nothing
essential outside the safe area, panels inside the screen, no overlaps.

| Screen | Layout module | Automated check | Studio check |
|---|---|---|---|
| HUD (level, HP / Focus, zone badge, Edit HUD) | HudSlots / HudLayout | hud_slots.spec: on screen, moved pieces kept on screen | text readable at the smallest scale |
| Combat buttons, skill slots, potion, Auto, run / crouch | CombatButtonsLayout (row / arc / column) | skills.spec: on screen, 44 px, no overlaps (circles), clear of the jump corner and HUD, phone landscape keeps the middle clear | thumb reach on a phone |
| SKILLS / BAG toggles | CombatButtonsLayout.toggles | skills.spec, quest_layout.spec | |
| Quest tracker and log | QuestLayout | quest_layout.spec: card or pill, never over buttons | |
| Event chip, buff chip, toasts | **OverlayLayout (new)** | **overlay_layout.spec**: clear of HUD, tracker, toggles, buttons and jump corner; toasts never over the chips; 44 px event chip; one toast at a time on short screens | chips readable in their short form |
| Skill tree and Attributes page | SkillTreeLayout | skills.spec (tree); Attributes buttons are 44 px | the Attributes page scrolls on a phone |
| Bag / equipment doll | InventoryLayout | inventory_layout.spec (20 sizes) | |
| Item Mall | **MallLayout (new)** | **mall_layout.spec**: panel on screen, 44 px rows, header / tabs / cards / footer never overlap, a full card row always fits; short screens put the tabs in the header row | buying on a phone |
| Event board (🎉 chip) | sized to the screen, scrolls | | fits and scrolls on a phone |
| Race / class choice | RaceSelectLayout, JobSelectLayout | race_select_layout.spec, job_select_layout.spec | |
| Admin panel (staff) | sized to the screen (max 960 x 660), scrolls | | usable on a tablet |
| Party panel | moved with the HUD (HudSlots) | hud_slots.spec | |

Console: a TV at 1080p uses the desktop 1080p size; controller navigation is
not part of this pass.
