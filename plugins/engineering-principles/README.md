# engineering-principles

Standalone Zion plugin documentation for teams that want only the engineering principles
skill without the full `crew` orchestration stack.

## Purpose

- Provide the `engineering-principles` review rubric as a focused plugin surface.
- Keep adoption simple for users who do not need worker agents, hooks, or crew commands.

## Source of truth and drift policy

- Canonical source: `plugins/crew/skills/engineering-principles/SKILL.md`
- If this plugin carries a duplicated skill file, it must remain byte-for-byte in sync with
  the canonical source.
- Any drift should be flagged in review as at least a **Warning**, and **Blocking** when the
  drift changes reviewer behavior.

This policy is also documented in `../../AGENTS.md`.
