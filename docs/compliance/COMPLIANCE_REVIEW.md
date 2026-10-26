# Compliance review (Phase 22, PLAN.md D-99)

Prepared by a Roblox platform and community compliance reviewer, following
`.claude/skills/roblox-compliance`. The design target is **players aged 9+**,
with a **Minimal / Mild-compatible** design (CLAUDE.md §2).

> **This is not legal approval** and does not guarantee any moderation or
> rating outcome. Before publishing, the creator must:
> 1. re-read Roblox's **current** official documentation: Community Standards, Content Maturity & Compliance, the Maturity & Compliance Questionnaire, monetization and paid-random-item rules, and the Roblox Select / Kids requirements;
> 2. **personally and accurately** complete the questionnaire on the Creator Dashboard.
>
> Questionnaire wording changes over time. Treat the sheet below as a guide to what the game contains, not as copy-paste answers.

## 1. Questionnaire answer sheet (what the game contains)

| Area the questionnaire asks about | What the game has | Suggested answer (verify the current options) | Evidence |
|---|---|---|---|
| **Violence** | Fantasy combat: swords, bows, magic, against fantasy creatures and (in war zones only) players of the other realm. Defeat is a kneel, a burst of light and a fade. Players return to their own realm's safe zone. No realistic weapons, no blood, no injury detail. | Disclose **fantasy / unrealistic violence, repeated**. Expect a **Mild** label; Roblox decides. | CombatFeedbackController, CombatVfx, SkillVfx ("stylised light, no blood"); defeat flow (SECURITY_MODEL T-07, CLAUDE.md §14). |
| **Blood / gore** | None. Hits show light, ice, fire and earth effects; creatures show rift-crystal glow, never wounds; defeated creatures sink and fade in about 2.6 s. | **None.** | CreatureBuilder ("no gore"), MobService corpse fade, D-81 "lights out" faces. |
| **Fear / scary content** | Dark dungeon floors (crypts, ember depths, frozen abyss, void), large monsters (Cerberus, Typhon, the Nullborn Herald), a violet "Rift Eclipse" sky, boss roars and camera shake. No jump scares, horror imagery or realistic threat. | Likely **mild fear** (fantasy monsters, dark places). Disclose if asked. | DungeonBuilder (D-87), boss sigils (D-88), world events (D-91). |
| **Crude humour, strong language** | None in game text. Players' chat uses Roblox's own chat and filter. | **None** (from the game). | All texts are written by the developer: NotificationController, QuestDefinitions. |
| **Romance / sexual content** | None. Avatars are athletic fantasy bodies; outfits are armour and robes. | **None.** | OutfitBuilder, BodyStyle (D-70 / D-72). |
| **Alcohol, drugs, tobacco** | "Potions" and "draughts" are fantasy healing and buff items (heal 30%, +10% damage). No intoxication, no real substances. | **None.** The wording ("Draught of Might") is fantasy; review the names if a reviewer reads them as alcohol. | ItemDefinitions, BuffRules. |
| **Gambling** | No real-money gambling, no casino games, no loot boxes. Gear drops are random **from playing** (never bought). Enhancement can fail from +6 (rates shown before every attempt; a Perfect Stone always succeeds; failure never destroys gear). | **No gambling.** But see paid random items. | LootRules, EnhanceRules (D-08). |
| **Paid random items** | **None.** Mall sets have fixed attributes shown before purchase (D-93). The Mall sells only **Perfect Stones**, which always succeed (creator decision 2026-10-26); plain Enhancement Stones, whose upgrade can fail, come only from play. | **None** (re-check against Roblox's current definition). | MallDefinitions (D-99). |
| **Social features** | Default Roblox chat; parties and unions (invites by player, expire); PvP between realms in war zones; player names, levels and titles (from a fixed list) are visible. No voice features added by the game, no free-form text from players shown to others, no player-made content. | Disclose **chat / social interaction** as Roblox's defaults. **No free-form user creation.** | PartyController, QuestDefinitions.Titles, no custom text remote (SECURITY_MODEL T-27). |
| **Religious / real-world references** | Angels and Devils are **fictional fantasy realms** (CLAUDE.md §3): no real religions, scriptures, worship, prayer or real-world groups; the story's villain is the fictional Nullborn. | Not real-world religious content. If the questionnaire asks about religious themes, answer accurately; reviewers may note the names. | RaceDefinitions header note, QuestDefinitions story. |
| **Monetization** | Mall Points through Developer Products (4 packs, **on hold**), spent on buffs, potions, stones and a fixed Legendary set. No subscriptions, no ads, no off-platform payments. | Declare in-experience purchases once the products exist. | MallService (receipts), MallDefinitions. |
| **Data / privacy** | Only Roblox user ids and game progress are stored (DataStore). No contact details, no location, no off-platform links. | **No personal data collection** beyond Roblox's own. | DATA_MODEL.md. |
| **AI features** | None shown to players. Creature meshes were generated offline by developer tools, not at run time. | **None.** Re-check Roblox's AI disclosure rules if that changes. | tools/creatures (offline). |

## 2. Risk table

| # | Risk | Likelihood | Impact | Mitigation in the game | Remaining action (owner: creator) |
|---|---|---|---|---|---|
| R1 | The questionnaire is answered from memory, not from the current form, so the rating is wrong. | M | H | This sheet lists what the game contains. | Fill the questionnaire yourself, on the current form, before publishing. |
| R2 | Robux purchases feeding a chance-based upgrade (indirect paid random item). | L | H | **Resolved 2026-10-26:** the Mall sells only Perfect Stones (always succeed); plain Enhancement Stones come only from play. | Re-check the paid-random-item policy before publishing. |
| R3 | Pay-to-win in PvP (Mall Legendary set 1.7x edge, PvP buffs) harms fairness and reviews for a young audience. | H | M | Mythical set removed from the Mall (D-95); buffs capped. **Creator decision 2026-10-26: buffs keep working in PvE and PvP.** | Watch player feedback after launch. |
| R4 | Young players spend Robux without understanding. | M | H | Two-tap confirm in the Mall; Roblox's purchase window. | Rely on Roblox parental controls and spending limits; no custom bypasses. |
| R5 | "Angels vs Devils" names read as religious content by a reviewer or parent. | L-M | M | Fictional factions, no worship or real-world references (CLAUDE.md §3). | Keep the story and store text clearly fantasy; answer the questionnaire accurately. |
| R6 | Fear content (dark dungeons, big monsters, eclipse) rated above Mild. | L-M | M | Stylised visuals, no jump scares, no gore. | Disclose fear accurately if asked. |
| R7 | Harassment between players in PvP / chat. | M | M | Roblox chat filter; same-realm players can't hurt each other; safe zones; spawn protection; staff kick / ban tools. | Publish community rules and a reporting / appeal path (Ban API needs it). |
| R8 | Player-written text shown unfiltered. | L | H | No remote accepts player text that others see; staff fields aren't shown to players. | If a feature adds player text (names, notes), filter it with TextService. |
| R9 | Moderation decisions without an appeal path. | M | M | Preset ban reasons, audited actions, temporary bans. | Write the rules and the appeal contact before using the Ban API on live players. |
| R10 | The movement anti-cheat pulls back legitimate laggy players (Phase 21). | M | L | Grace / allowances for every server move; no auto-ban. | Watch for reports after launch; tune or switch to Shadow. |

## 3. Before publishing (checklist for the creator)
- [ ] Re-read the current Community Standards, Content Maturity & Compliance, the questionnaire and the monetization / paid-random-item rules.
- [ ] Complete the Maturity & Compliance Questionnaire yourself, using section 1 as a guide.
- [x] R2 decided: Perfect Stones only in the Mall. R3 decided: buffs work in PvE and PvP.
- [ ] Create the Developer Products (on hold) and test a real purchase in a private test place.
- [ ] Publish community rules and a reporting / appeal path; enable `Players.BanningEnabled` only after that.
- [ ] Check the experience description, icon and thumbnails show fantasy combat and no blood, and match the answers you gave.
- [ ] Keep this file updated when content changes (new monetization, AI, user content, voice).
