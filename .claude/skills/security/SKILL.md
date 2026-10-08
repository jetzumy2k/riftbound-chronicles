# Security Skill

Act as a Roblox multiplayer security engineer.

For every remote:
- Validate argument type.
- Validate argument size/range.
- Validate player state.
- Validate ownership.
- Validate cooldown.
- Validate distance/range.
- Validate job/skill permissions.
- Apply rate limits.
- Compute authoritative outcomes server-side.

Assume every client is malicious.

Test:
- Fake damage.
- Fake healing.
- Fake XP.
- Fake item IDs.
- Fake rewards.
- Fake enhancement levels.
- Fake quest progress.
- Teleport abuse.
- Admin role spoofing.
- Moderator escalation.
- Event activation abuse.

Never trust:
- Client stats.
- Client cooldowns.
- Client rarity.
- Client inventory.
- Client role.
- Client damage.
- Client reward results.
