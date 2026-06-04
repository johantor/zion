# Matrix Team Claude Plugin

This repository is a Claude Code plugin pack. It provides a ready-to-use `.claude/` setup with agents, commands, hooks, and skills.

## Install

### Option A: Use this repository directly
1. Clone this repository.
2. Open it in Claude Code.
3. Run:
   - `claude --agent morpheus`

### Option B: Install into another repository
1. Copy the `.claude/` folder from this repository into your target repository root.
2. Copy `CLAUDE.md` into the target repository root.
3. Ensure hook scripts are executable in the target repository:
   - `chmod +x .claude/hooks/*.sh`
4. Open the target repository in Claude Code.
5. Run:
   - `claude --agent morpheus`

## Usage

1. Start orchestrator: `claude --agent morpheus`
2. Run `/feature <ticket-or-task>` to plan and execute feature work.
3. Run `/review` for consolidated code + security + design review.
4. Run `/ship` for pre-PR go/no-go checks.

## What is included

- `agents/`: `morpheus`, `tank`, `trinity`, `oracle`, `dozer`, `seraph`
- `skills/`: `engineering-principles`, `context-discipline`, `frontend-headless`, `frontend-server-rendered`
- `hooks/`: path guard, read guard, bash safety, formatter entrypoint
- `commands/`: `/feature`, `/review`, `/ship`
- `settings.json`: hook wiring
- `CLAUDE.md`: crew configuration

## Verify installation

After install, confirm these paths exist in your repository:
- `.claude/settings.json`
- `.claude/agents/morpheus.md`
- `.claude/commands/feature.md`
- `.claude/hooks/bash-safety.sh`

If they exist and `claude --agent morpheus` starts, installation is complete.

## Notes

- Worker agents stay idle until `morpheus` delegates.
- Local memory is ignored via `.gitignore` (`.claude/agent-memory-local/`).
