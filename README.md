# Zion Link

A Claude Code plugin **marketplace** — a monorepo of plugins for feature delivery.

## Add the marketplace

```bash
claude plugin marketplace add johantor/zion-link
```

Then install any plugin below with `claude plugin install <plugin>@zion-link`, or
browse them in Claude Code under `/plugin > Discover`.

## Plugins

| Plugin | Install | Description |
| ------ | ------- | ----------- |
| [`crew`](plugins/crew/README.md) | `claude plugin install crew@zion-link` | Orchestrated agents, commands, hooks, and skills for feature delivery. |

Each plugin lives in `plugins/<name>/` and documents itself in its own README.

## Repository layout

- `.claude-plugin/marketplace.json` — the marketplace; lists each plugin and its `source`.
- `plugins/<name>/` — one plugin per directory (its plugin root): `.claude-plugin/plugin.json` plus `agents/`, `commands/`, `skills/`, `hooks/`.
- `.claude/settings.json` — this repo's own dev-time hooks (the crew guards, so they run while developing here).
- `.github/copilot-instructions.md` — guided review instructions aligned with the crew reviewer.
- `.github/workflows/validate.yml` — CI: shellcheck + plugin manifest validation.

See [`CLAUDE.md`](CLAUDE.md) for contributor conventions.

## Adding a plugin

Adding a plugin is additive — it never touches existing ones:

1. Create `plugins/<name>/` with `.claude-plugin/plugin.json` and your component dirs
   (`agents/`, `commands/`, `skills/`, `hooks/`).
2. Add an entry to `.claude-plugin/marketplace.json` with `"source": "./plugins/<name>"`.
3. Add a `plugins/<name>/README.md` and a row to the table above.

## Validating

```bash
shellcheck plugins/*/hooks/*.sh plugins/*/scripts/*.sh
bash plugins/crew/scripts/validate-plugin.sh   # validates every plugin under plugins/*
```
