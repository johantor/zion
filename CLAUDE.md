# Zion

A Claude Code plugin pack ("crew") of orchestrated agents, commands, hooks, and
skills for feature delivery. This repository **is the plugin** — there is no
application code to build or ship. Work here is editing agent/command/skill
definitions, hooks, and docs.

## Crew configuration

These values are read by the `morpheus` orchestrator and the frontend skills.
Keep them accurate; update them if this repo ever gains app code.

- **Frontend mode:** *unset* — optional here. Pin it (`headless` or `server-rendered`)
  only to force a choice; otherwise `morpheus` resolves it per project (its memory, or by
  asking you and then remembering). This repo is the plugin itself and has no frontend.
- **Backend test command:** none (no backend test project detected)
- **Frontend test command:** none (no frontend e2e suite detected)
- **Backend build command:** none (no build manifest detected) — e.g. `dotnet build`.
- **Frontend build command:** none (no build manifest detected) — e.g. the project's
  `build` / `typecheck` script (`tsc --noEmit`, `vite build`, etc.).
- **Backend lint command:** none (no backend project detected) — e.g. `dotnet format --verify-no-changes`,
  plus `dotnet csharpier check` when a `.csharpierrc` is present.
- **Frontend lint command:** none (no frontend project detected) — e.g. the project's
  `lint` script (`eslint`, `biome check`, `stylelint`, etc.) in report/verify mode.
- **Base branch:** *unset* — the branch `morpheus` branches off (e.g. `main` / `develop` /
  trunk). If unset, `morpheus` resolves it per project (its memory, or by asking you).
- **Branch naming:** *unset* — convention for crew feature branches (e.g. `feature/<ticket>-<slug>`).
- **Run/dev URL:** none configured
- **Notable conventions:** Repository currently contains Claude crew/plugin configuration only.

## Repository layout

This is a **monorepo marketplace**: `.claude-plugin/marketplace.json` lists the plugins,
each of which lives in its own directory under `plugins/<name>/` (its plugin root). Adding
a plugin is additive — create `plugins/<name>/` and add an entry to `marketplace.json`.

- `.claude-plugin/marketplace.json` — the marketplace; lists each plugin and its `source`.
- `plugins/crew/` — the `crew` plugin (its root; component paths below are relative to it):
  - `.claude-plugin/plugin.json` — plugin manifest (name `crew`).
  - `agents/` — `morpheus` (orchestrator) plus workers `tank`, `trinity`, `oracle`, `dozer`, `seraph`. Auto-discovered from this dir; not declared in the manifest.
  - `commands/` — `/feature`, `/review`, `/ship`, `/pr` (namespaced as `crew:feature` etc. once installed).
  - `skills/` — `engineering-principles`, `context-discipline`, `frontend-headless`, `frontend-server-rendered`.
  - `hooks/` — `bash-safety.sh`, `read-guard.sh`, `lane-guard.sh`, `format.sh`, wired via `hooks.json`.
  - `scripts/validate-plugin.sh` — validates every plugin's manifest/structure.
- `.claude/settings.json` — this repo's own dev-time hooks (point at `plugins/crew/hooks/` so the guards run while developing here).
- `.github/copilot-instructions.md` — guided review instructions for GitHub Copilot, aligned with the crew reviewer.
- `.github/workflows/validate.yml` — CI: shellcheck + plugin manifest validation.

## How the crew works

- `morpheus` plans and delegates; it writes no production code. Workers stay idle until delegated to.
- `morpheus` maintains a written plan at `.claude/plan-<feature>.md` with per-step acceptance criteria.
- `morpheus` is the sole owner of git: it branches off the resolved base branch and commits each
  verified step; workers never run git. The crew stops at the local ship gate by default —
  pushing and opening a PR is the separate `/crew:pr` command.
- Worker lanes: `tank` = backend (C#/.NET/Optimizely, Razor server-side), `trinity` = frontend (React/Redux/JS/HTML/SCSS, plus Razor markup in server-rendered mode),
  `oracle` = backend tests only, `dozer` = frontend e2e only, `seraph` = visual design conformance (read-only).
- All workers apply `context-discipline`: process bulk output with code, return only concise findings.

## How we look at code (the crew reviewer)

Reviews — whether by `/crew:review`, the crew, or GitHub Copilot — judge code against
the `engineering-principles` skill and classify every finding as **Blocking**,
**Warning**, or **Passed**. The same three pillars apply: code quality, security,
and design conformance. See `plugins/crew/skills/engineering-principles/SKILL.md` for the
full rules and `.github/copilot-instructions.md` for the review contract.

Core principles (defaults, not dogma — the repo's established patterns win on conflict):
YAGNI, KISS, pragmatic DRY (rule of three), small single-purpose units, intention-revealing
names, fail-fast error handling, and minimal-scope diffs.

## Validating changes

This repo has no app build. Before opening a PR, run what CI runs:

```bash
shellcheck plugins/*/hooks/*.sh plugins/*/scripts/*.sh
bash plugins/crew/scripts/validate-plugin.sh
```

## Releasing

Versions are per-plugin. To cut a release:

1. Bump `version` in `plugins/<name>/.claude-plugin/plugin.json` and add a `CHANGELOG.md`
   entry (a PR that changes plugin behavior must do this — see `copilot-instructions.md`).
2. Merge to `main`. `.github/workflows/auto-release.yml` runs on the push, sees the new
   version has no `<plugin>--v<version>` tag yet, and creates the tag and GitHub Release
   automatically, with notes pulled from that version's `CHANGELOG.md` section. No
   matching changelog entry → it skips with a warning. No manual tagging is needed
   (`claude plugin tag` exists for tagging by hand, but here the workflow owns it).

## Conventions

- Hooks are POSIX shell run via `bash`; keep them shellcheck-clean.
- Agent/command/skill definitions are Markdown with YAML frontmatter — match the field
  shape of existing files in the same directory.
- Local agent memory lives in `.claude/agent-memory-local/` and is gitignored. Don't commit it.
- Keep diffs minimal-scope; list unrelated improvements rather than bundling them.
- PR titles follow Conventional Commits: `type(scope): summary`, with a `(vX.Y.Z)` suffix
  when the PR bumps a plugin version. Use `feat`/`fix`/`chore`/`docs`/`ci`/`refactor`; scope
  the plugin when the change is plugin-specific (e.g. `feat(crew): … (v1.9.0)`).
