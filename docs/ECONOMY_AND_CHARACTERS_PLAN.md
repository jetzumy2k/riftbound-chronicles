# Characters, race change, NPC economy, trading and auction (PLAN.md D-115..D-123)

Creator request 2026-10-27. Built one stage at a time; each stage gets a Studio test and a commit before the next starts. Existing features must keep working: every stage ships with a profile migration (no data loss) and its own tests.

## Creator decisions (2026-10-27)

| Topic | Decision |
|---|---|
| Roulette cost | 1 free spin a day, extra spins for Gold. No Robux or Mall Points, so it isn't a paid random item. Odds are shown on the NPC. |
| What can trade / auction | Gold, consumables, gear and weapons from play. Mall-bought gear (item `Source` = `Mall:*`), Mall-only consumables (scrolls, buff draughts, Greater/Major/Supreme potions) and Mall Points never change hands. |
| Durability at 0 | The item's stats stop counting until the Blacksmith repairs it for Gold. It is never destroyed (keeps the CLAUDE.md §14 no-item-loss rule). |
| NPC shop rarities | Standard, Uncommon and Rare. Rare is priced high so drops still matter. |

## Stages (recommended order: each builds on the one before)

1. **D-115 Character slots.** Up to 4 characters per account, all of the account's race.
   - A character screen on join: pick, create or delete (typed confirmation). One character is played at a time; switching saves, then rejoins.
   - **Account-wide:** realm, Mall Points (and Robux receipts), settings, moderation flags, staff role.
   - **Per character:** class, level, gear, bag, Gold, quests, skills, PvP stats.
   - Profile schema v4 migration: today's character becomes slot 1.
2. **D-116 Race change.**
   - **Option 1:** delete every character, then race selection reopens (the same as a new player).
   - **Option 2:** the Race Conversion Rune (Item Mall, MP price set by the admin).
     - Using it asks for the new realm and confirms, then asks the player to rejoin. On rejoin every character is the new race.
     - Gear keeps its rarity, level, rolls and enhancement. Weapons change to the same class's weapon for the new realm (the existing `weaponsByRace` map); armor follows the realm's look.
     - Audited. A backup is saved first (as in D-111).
3. **D-117 Merchant and exchange NPCs.**
   - **Merchant:** sells healing potions and Standard/Uncommon/Rare gear, weapons and accessories for Gold. Buys back unused (unequipped, unlocked) gear for Gold.
   - **Exchanger:** Gold to Mall Points and Mall Points to Gold, at ratios set in Admin → Settings, with an optional daily cap.
   - Server prices, audited.
4. **D-118 Durability and the Blacksmith.**
   - Gear, weapons and accessories have durability (100 by default, admin tunable). They wear a little per fight and on defeat.
   - At 0 the item's stats stop counting. The Blacksmith repairs one item or everything for Gold.
   - Shown on item cards and tooltips. Old items start full.
5. **D-119 Chain quest NPC.**
   - A repeatable chain of 7 to 10 steps: collect N drops from named dungeon or war-zone creatures, defeat targets, and so on.
   - Finishing the chain gives a Legendary gear piece or weapon, or a 1-day random buff.
   - Uses the existing quest and claim system, so a reward can't be paid twice.
6. **D-120 Roulette NPC.**
   - 1 free spin a day, then Gold per spin.
   - **Rewards from most to least likely:** "Thank you", Standard gear, Rare gear, then a consumable, +1 attribute point, +1 level, and Legendary gear (least likely).
   - The odds are admin-tunable, validated to total 100%, and listed on the NPC. Audited.
7. **D-121 Player trading.**
   - Invite, then both players fill offer windows (Gold, consumables, gear).
   - **Scam protections:**
     - Any change to an offer clears both players' "Ready".
     - Both must lock, then confirm on a final summary screen showing what each side gives and gets.
     - A 3-second countdown follows, which either player can cancel.
     - The swap is atomic on the server, checked again at that moment.
     - Equipped and Mall items are blocked, and both players need bag space.
   - **Risk warning:** both players must accept a warning that trades are at their own risk before each trade.
   - **Trade history:** in each player's menu, kept in the audit log as evidence. The Report button attaches the trade ID for admins, Game Masters and Moderators.
   - Trading requires level 5 and being in a safe zone, and is rate-limited.
8. **D-122 Auction market.**
   - **Listing:** list an item with a starting bid and an optional Buy Now price. Lengths are 12, 24 or 48 h, and there is a small Gold listing fee.
   - **Browsing:** search and filter by kind, rarity and class.
   - **Bids:** a bid holds the bidder's Gold in escrow. Being outbid refunds it.
   - **Ending:** Buy Now or the end time completes the sale, minus a fee.
   - **Cross-server:** listings live in a shared DataStore and MemoryStore with server-side escrow. Items and Gold are delivered through a mailbox the next time the player is online, so nothing is lost if they're offline.
   - Audited, with a per-player listing cap.
9. **D-123 Review pass.**
   - **Economy check:** Gold sources versus sinks, trade and auction abuse, MP/Gold exchange loops.
   - **Compliance check:** trading, randomness and age 9+ for the Roblox questionnaire.

## Security rules for every stage

- Server-authoritative: prices, odds, ratios and durability live on the server or in config. Clients only ask.
- Every remote has a schema, a rate limit and state checks, and is listed in `structure.spec`.
- **Item moves are atomic.** NPC sales, trades, auctions and repairs check again and change the profile synchronously, with no yield between check and write (DATA_MODEL §4.1). A cross-server move goes through a claim ID so it can never happen twice.
- Every Gold, Mall Point and item movement is audit logged with both parties.
- Mall Points never move between players.

## Needs a human or platform review before release

- **Trading and the auction:** check Roblox's current rules on in-experience trading and real-money trading before going live. Disclose trading in the Maturity & Compliance questionnaire.
- **Roulette:** it is free or bought with Gold only, and its odds are shown. Re-check the rules if spins are ever sold for Robux or Mall Points.
- **Gold to Mall Points:** this lets players earn the Robux currency by playing. That is allowed, but it is a revenue decision for the creator, and the admin ratio controls it.
