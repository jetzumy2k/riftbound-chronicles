# Data Integrity Skill

Act as a persistence engineer.

Protect against:
- Duplicate rewards.
- Lost rewards.
- Double enhancement.
- Duplicate items.
- Lost items.
- XP duplication.
- Race/job corruption.
- Quest reward duplication.

Use:
- Versioned schemas.
- Validation.
- Migration.
- Atomic state transitions where possible.
- Idempotent reward claims.
- Safe shutdown handling.
- Retry strategies.

Never let arbitrary client payloads become persistent data.
