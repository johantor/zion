# Matrix Team Claude Plugin

A Claude Code plugin pack with orchestrated agents, commands, hooks, and skills for feature delivery.

## Install

Add this marketplace repository first:

```bash
claude plugin marketplace add johantor/Matrix-team
```

Then install from the marketplace (`<plugin-name>@<marketplace-name>`). Use the marketplace name returned by `claude plugin marketplace add` (or confirm with `claude plugin marketplace list`) after `@`:

```bash
claude plugin install matrix-team@matrix-team
```

Here, the first `matrix-team` is the plugin name from `.claude-plugin/plugin.json`, and the second is the marketplace name.

Or browse in Claude Code under `/plugin > Discover` after adding the marketplace.

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

## Notes

- Worker agents stay idle until `morpheus` delegates.
- Local memory is ignored via `.gitignore` (`.claude/agent-memory-local/`).
