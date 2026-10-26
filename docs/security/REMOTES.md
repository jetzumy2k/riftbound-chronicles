# Client -> server remotes (generated)

`lune run tools/security/remote_matrix > docs/security/REMOTES.md`. NetService checks, in order, before any handler: global rate budget, this remote's rate limit, argument count and schema (types, ranges, lengths, unknown fields rejected), player states, staff permission (from server Roles). Handler-level checks: docs/security/SECURITY_REVIEW.md.

| Remote | Kind | Arguments | Rate (burst / per s) | States | Staff permission |
|---|---|---|---|---|---|
| AdminAudit | Function | none | 4 / 0.5 | ProfileLoaded | audit.view |
| AdminBoss | Function | enum(1) | 2 / 0.1 | ProfileLoaded | bosses.manage |
| AdminConfigGet | Function | none | 4 / 0.5 | ProfileLoaded | config.view |
| AdminConfigSet | Function | int(0..-); array<=40 of {Bool, Number, Path, Reset, Text} | 3 / 0.2 | ProfileLoaded | config.view |
| AdminEvents | Function | enum(4); {Id, Minutes, Rewards, StartsAt} | 10 / 1 | ProfileLoaded | events.activate |
| AdminInspect | Function | int(1..9007199254740991) | 6 / 1 | ProfileLoaded | player.inspect |
| AdminPlayerAction | Function | int(1..9007199254740991); enum(9); {Currency, DefId, Guid, Number, Quest, Rarity, Reason, Stackable} | 6 / 1 | ProfileLoaded | panel.open |
| AdminPlayers | Function | string(<=20) | 6 / 1 | ProfileLoaded | player.inspect |
| BasicAttack | Event | instance? | 6 / 4 | ProfileLoaded, HasJob, Alive | - |
| BuyMallItem | Function | enum(14) | 4 / 1 | ProfileLoaded, HasJob | - |
| ClientReady | Event | none | 2 / 0.05 |  | - |
| CombineFragments | Event | int(1..100) | 4 / 1 | ProfileLoaded, HasJob | - |
| DungeonLeave | Event | none | 3 / 0.5 | ProfileLoaded | - |
| EnhanceItem | Event | string(<=36); boolean | 3 / 2 | ProfileLoaded, HasJob | - |
| EquipItem | Event | string(<=36); enum(3)? | 6 / 2 | ProfileLoaded, HasJob | - |
| EquipTitle | Event | enum(12)? | 4 / 0.5 | ProfileLoaded | - |
| LearnSkill | Event | enum(97) | 6 / 2 | ProfileLoaded, HasJob | - |
| LockItem | Event | string(<=36); boolean | 8 / 3 | ProfileLoaded, HasJob | - |
| PartyInvite | Event | instance | 4 / 0.5 | ProfileLoaded, HasJob | - |
| PartyKick | Event | instance | 4 / 0.5 | ProfileLoaded | - |
| PartyLeave | Event | none | 3 / 0.3 | ProfileLoaded | - |
| PartyRespond | Event | instance; boolean | 4 / 0.5 | ProfileLoaded, HasJob | - |
| QuestAccept | Event | enum(11) | 4 / 0.5 | ProfileLoaded, HasJob | - |
| QuestTurnIn | Event | enum(11) | 4 / 0.5 | ProfileLoaded, HasJob | - |
| ResetAttributes | Event | none | 2 / 0.2 | ProfileLoaded, HasJob | - |
| ResetSkills | Event | none | 2 / 0.1 | ProfileLoaded, HasJob | - |
| SalvageItems | Event | array<=25 of string(<=36) | 4 / 1 | ProfileLoaded, HasJob | - |
| SelectJob | Event | enum(4) | 3 / 0.2 | ProfileLoaded, HasRace | - |
| SelectRace | Event | enum(2); int(1..8) | 3 / 0.2 | ProfileLoaded | - |
| SetHeadStyle | Event | enum(2) | 2 / 0.2 | ProfileLoaded | - |
| SetHudLayout | Event | map<=9 | 3 / 0.1 | ProfileLoaded | - |
| SetLoadout | Event | array<=6 of enum(97); enum(97)? | 4 / 0.5 | ProfileLoaded, HasJob | - |
| SetMovementMode | Event | enum(3) | 8 / 4 | ProfileLoaded, Alive | - |
| SkillCast | Event | enum(97); instance? | 4 / 2.5 | ProfileLoaded, HasJob, Alive | - |
| SpendAttributes | Event | {AGI, INT, REC, STR, WIS} | 10 / 4 | ProfileLoaded, HasJob | - |
| StudioTestGear | Event | none | 2 / 0.2 | ProfileLoaded, HasJob | - |
| UnequipItem | Event | enum(12) | 6 / 2 | ProfileLoaded, HasJob | - |
| UnionInvite | Event | instance | 4 / 0.5 | ProfileLoaded, HasJob | - |
| UnionKick | Event | instance | 4 / 0.5 | ProfileLoaded | - |
| UnionLeave | Event | none | 3 / 0.3 | ProfileLoaded | - |
| UnionRespond | Event | instance; boolean | 4 / 0.5 | ProfileLoaded, HasJob | - |
| UseConsumable | Event | enum(9) | 4 / 1 | ProfileLoaded, HasJob, Alive | - |
