# Riftbound Chronicles — Claude Development Pack

This package contains the master development instructions for the Roblox RPG.

## Files

- `CLAUDE.md` — master engineering, game, safety and architecture instructions.
- `docs/PHASE_PROMPTS.md` — sequential prompts for Claude Code.
- `.claude/skills/architecture/SKILL.md`
- `.claude/skills/security/SKILL.md`
- `.claude/skills/game-design/SKILL.md`
- `.claude/skills/roblox-compliance/SKILL.md`
- `.claude/skills/art-animation/SKILL.md`
- `.claude/skills/qa-gamer/SKILL.md`
- `.claude/skills/data-integrity/SKILL.md`
- `.claude/skills/mobile-ui/SKILL.md`
- `.claude/skills/live-ops/SKILL.md`

## Recommended workflow

1. Put `CLAUDE.md` at the repository root.
2. Copy `.claude/skills/` into the repository.
3. Give Claude Code Phase 0 only.
4. Review its output.
5. Run the phase tests.
6. Proceed sequentially.
7. Do not ask Claude to implement all phases in one prompt.

## Important design corrections

The requested dungeon regular-mob table said 30% Rare and 70% Rare. This package interprets it as:
- 30% Rare
- 70% Standard/Uncommon

Also, enhancement's `+20 damage` is defined as weapon attack. Armor receives a separate defensive enhancement benefit so armor does not gain an inappropriate attack-only stat.

## Roblox compliance note

The package is designed around a 9+ audience and non-graphic fantasy combat. Roblox's current documentation says Minimal/Mild experiences can be eligible for Roblox Select (9–15), but creators must accurately complete the Maturity & Compliance Questionnaire and comply with current Community Standards. Re-check official Roblox requirements before publishing.
