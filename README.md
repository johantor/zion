# Zion Link

A Claude Code plugin pack with orchestrated agents, commands, hooks, and skills for feature delivery.

## Install

Add this marketplace repository first:

```bash
claude plugin marketplace add johantor/zion-link
```

Then install from the marketplace (`<plugin-name>@<marketplace-name>`). Use the marketplace name returned by `claude plugin marketplace add` (or confirm with `claude plugin marketplace list`) after `@`:

```bash
claude plugin install crew@zion-link
```

Here, `crew` is the plugin name from `.claude-plugin/plugin.json`, and `zion-link` is the marketplace name.

Or browse in Claude Code under `/plugin > Discover` after adding the marketplace.

## Usage

1. Start orchestrator: `claude --agent morpheus`
2. Run `/zion-feature <ticket-or-task>` to plan and execute feature work.
3. Run `/zion-review` for consolidated code + security + design review.
4. Run `/zion-ship` for pre-PR go/no-go checks.

## What is included

- `agents/`: `morpheus`, `tank`, `trinity`, `oracle`, `dozer`, `seraph`
- `skills/`: `engineering-principles`, `context-discipline`, `frontend-headless`, `frontend-server-rendered`
- `hooks/`: lane guard, read guard, bash safety, formatter entrypoint
- `commands/`: `/zion-feature`, `/zion-review`, `/zion-ship`

## Notes

- Worker agents stay idle until `morpheus` delegates.
- Local memory is ignored via `.gitignore` (`.claude/agent-memory-local/`).
