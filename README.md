# Matrix Team Claude Plugin

This repository now contains a complete Claude multi-agent plugin setup under `.claude/`.

## What is included

- `agents/`: six project-scoped agents
  - `morpheus` (orchestrator)
  - `tank` (backend implementer)
  - `trinity` (frontend implementer)
  - `oracle` (backend tests)
  - `dozer` (frontend e2e tests)
  - `seraph` (design conformance)
- `skills/`: reusable skill packs
  - `engineering-principles`
  - `context-discipline`
  - `frontend-headless`
  - `frontend-server-rendered`
- `hooks/`: guardrails and safety checks
  - lane/path guard
  - large-read guard
  - bash safety guard
  - formatting entrypoint
- `commands/`: reusable orchestrator commands
  - `/feature`
  - `/review`
  - `/ship`
- `settings.json`: global hook wiring
- `CLAUDE.md`: repo crew configuration

## Quick start

1. Open this repo in Claude Code.
2. Start orchestrated workflow with:
   - `claude --agent morpheus`
3. Run `/feature <ticket>` for implementation workflow.
4. Run `/review` for consolidated quality + design review.
5. Run `/ship` before opening PRs.

## Notes

- Worker agents are intentionally dormant unless explicitly delegated by `morpheus`.
- Local agent memory is ignored via `.gitignore`.
- Hook scripts are executable and enforce lane/safety constraints.
