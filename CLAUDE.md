# Zion Link

A Claude Code plugin pack ("crew") of orchestrated agents, commands, hooks, and
skills for feature delivery. This repository **is the plugin** — there is no
application code to build or ship. Work here is editing agent/command/skill
definitions, hooks, and docs.

## Crew configuration

These values are read by the `morpheus` orchestrator and the frontend skills.
Keep them accurate; update them if this repo ever gains app code.

- **Frontend mode:** headless
- **Backend test command:** none (no backend test project detected)
- **Frontend test command:** none (no frontend e2e suite detected)
- **Build command:** none (no build manifest detected)
- **Run/dev URL:** none configured
- **Notable conventions:** Repository currently contains Claude crew/plugin configuration only.

## Repository layout

- `.claude-plugin/` — `plugin.json` (plugin manifest, name `crew`) and `marketplace.json`.
- `.claude/agents/` — `morpheus` (orchestrator) plus workers `tank`, `trinity`, `oracle`, `dozer`, `seraph`.
- `.claude/commands/` — `/zion-feature`, `/zion-review`, `/zion-ship`.
- `.claude/skills/` — `engineering-principles`, `context-discipline`, `frontend-headless`, `frontend-server-rendered`.
- `.claude/hooks/` — `bash-safety.sh`, `read-guard.sh`, `lane-guard.sh`, `format.sh`, wired via `hooks.json`.
- `.claude/scripts/validate-plugin.sh` — manifest validation.
- `.github/copilot-instructions.md` — guided review instructions for GitHub Copilot, aligned with the crew reviewer.
- `.github/workflows/validate.yml` — CI: shellcheck + plugin manifest validation.

## How the crew works

- `morpheus` plans and delegates; it writes no production code. Workers stay idle until delegated to.
- `morpheus` maintains a written plan at `.claude/plan-<feature>.md` with per-step acceptance criteria.
- Worker lanes: `tank` = backend (C#/.NET/Optimizely/Razor), `trinity` = frontend (React/Redux/SCSS),
  `oracle` = backend tests only, `dozer` = frontend e2e only, `seraph` = visual design conformance (read-only).
- All workers apply `context-discipline`: process bulk output with code, return only concise findings.

## How we look at code (the crew reviewer)

Reviews — whether by `/zion-review`, the crew, or GitHub Copilot — judge code against
the `engineering-principles` skill and classify every finding as **Blocking**,
**Warning**, or **Passed**. The same three pillars apply: code quality, security,
and design conformance. See `.claude/skills/engineering-principles/SKILL.md` for the
full rules and `.github/copilot-instructions.md` for the review contract.

Core principles (defaults, not dogma — the repo's established patterns win on conflict):
YAGNI, KISS, pragmatic DRY (rule of three), small single-purpose units, intention-revealing
names, fail-fast error handling, and minimal-scope diffs.

## Validating changes

This repo has no app build. Before opening a PR, run what CI runs:

```bash
shellcheck .claude/hooks/*.sh .claude/scripts/*.sh
bash .claude/scripts/validate-plugin.sh
```

## Conventions

- Hooks are POSIX shell run via `bash`; keep them shellcheck-clean.
- Agent/command/skill definitions are Markdown with YAML frontmatter — match the field
  shape of existing files in the same directory.
- Local agent memory lives in `.claude/agent-memory-local/` and is gitignored. Don't commit it.
- Keep diffs minimal-scope; list unrelated improvements rather than bundling them.
