# Contributing to Zion

Zion is a Claude Code plugin pack ("crew") of orchestrated agents, commands, hooks, and
skills for feature delivery. **This repository *is* the plugin** — there is no application
code to build or ship. Work here means editing agent/command/skill definitions, hooks, and
docs.

This is the contributor guide for anyone — human or agent — changing this repo, and it is
tool-neutral. Claude Code reads `CLAUDE.md`, which points here and adds only its own runtime
configuration (the values the `crew` orchestrator reads).

## Repository layout

This is a **monorepo marketplace**: `.claude-plugin/marketplace.json` lists the plugins,
each of which lives in its own directory under `plugins/<name>/` (its plugin root). Adding
a plugin is additive — create `plugins/<name>/` and add an entry to `marketplace.json`.

- `.claude-plugin/marketplace.json` — the marketplace; lists each plugin and its `source`.
- `plugins/crew/` — the `crew` plugin (its root; component paths below are relative to it):
  - `.claude-plugin/plugin.json` — plugin manifest (name `crew`).
  - `agents/` — `morpheus` (orchestrator) plus workers `tank`, `trinity`, `oracle`, `dozer`, `seraph`. Auto-discovered from this dir; not declared in the manifest.
  - `commands/` — `/init`, `/feature`, `/review`, `/pr` (namespaced as `crew:feature` etc. once installed). `/init` detects and writes the crew configuration block in `CLAUDE.md` (idempotent reconcile). `/review` is the pre-PR GO/NO-GO gate (consolidated review + build/test/lint).
  - `skills/` — shared: `engineering-principles`, `context-discipline`; frontend mode:
    `frontend-headless`, `frontend-server-rendered`; per-stack (loaded dynamically once
    `morpheus` resolves the project's stack): `backend-dotnet`, `backend-node`,
    `cms-optimizely`, `frontend-react`, `frontend-nextjs`, `tests-xunit`, `tests-node`;
    per-e2e-tool (loaded by `dozer` once `morpheus` resolves the e2e tool): `tests-cypress`,
    `tests-playwright`.
  - `hooks/` — `bash-safety.sh`, `read-guard.sh`, `lane-guard.sh`, `format.sh`, wired via `hooks/hooks.json`.
  - `scripts/validate-plugin.sh` — validates every plugin's manifest/structure.
- `plugins/engineering-principles/` — standalone plugin that ships only the `engineering-principles` skill:
  - `.claude-plugin/plugin.json` — plugin manifest (name `engineering-principles`).
  - `skills/engineering-principles/SKILL.md` — standalone shipped copy; must remain byte-for-byte synced with the canonical crew copy.
  - `CHANGELOG.md` — release notes for this plugin's versions.
- `.claude/settings.json` — this repo's own dev-time hooks (point at `plugins/crew/hooks/` so the guards run while developing here).
- `.github/copilot-instructions.md` — guided review instructions for GitHub Copilot, aligned with the crew reviewer.
- `.github/workflows/validate.yml` — CI: shellcheck + plugin manifest validation.

## How the crew works

- `morpheus` plans and delegates; it writes no production code. Workers stay idle until delegated to.
- `morpheus` maintains a written plan at `<plan-dir>/plan-<feature>.md` — `<plan-dir>` is the `Plan directory` crew-config slot, or `.claude/` when unset — with per-step acceptance criteria, and presents it for the user's go-ahead before creating the branch or delegating (the plan checkpoint — one gate, honoring a standing "just build it").
- `morpheus` is the sole owner of git: it branches off the resolved base branch and commits each
  verified step; workers never run git. The crew stops at the local review gate by default —
  pushing and opening a PR is the separate `/crew:pr` command.
- Worker lanes are stack-agnostic: `tank` = backend implementer for the resolved backend
  stack, `trinity` = frontend implementer for the resolved frontend stack (plus a shared
  server template's markup in server-rendered mode), `oracle` = backend tests only, `dozer`
  = frontend e2e only (for the resolved e2e tool), `seraph` = visual design conformance
  (read-only). Stack knowledge lives in per-stack skills, loaded once `morpheus` resolves the
  project's stack (`CLAUDE.md`'s **Backend stack**/**Frontend stack** slots). E2e tool
  knowledge lives in per-tool skills, loaded once `morpheus` resolves the e2e tool
  (`CLAUDE.md`'s **Frontend e2e tool** slot). `lane-guard.sh` enforces the write lane by file
  extension for disjoint-language stacks (e.g. dotnet+react), or by configured directory paths
  (**Backend/Frontend lane path(s)**) when both stacks are the same language (e.g. node+nextjs).
- All workers apply `context-discipline`: process bulk output with code, return only concise findings.

The crew's runtime configuration (test/build/lint commands, base branch, frontend mode) lives
in `CLAUDE.md` under **Crew configuration** — that is what `morpheus` and the `crew:*` commands
read. For this repo those slots are mostly `unset`/`none`, because the repo is the plugin itself
and has no app code to build or test.

## How we review code (the crew reviewer)

Reviews — whether by `/crew:review`, the crew, or GitHub Copilot — judge code against
the `engineering-principles` skill and classify every finding as **Blocking**,
**Warning**, or **Passed**. The same three pillars apply: code quality, security,
and design conformance. See `plugins/crew/skills/engineering-principles/SKILL.md` for the
full rules and `.github/copilot-instructions.md` for the review contract.

Core principles (defaults, not dogma — the repo's established patterns win on conflict):
YAGNI, KISS, pragmatic DRY (rule of three), small single-purpose units, intention-revealing
names, fail-fast error handling, and minimal-scope diffs.

The standalone `engineering-principles` plugin ships a copy of this skill;
`plugins/crew/skills/engineering-principles/SKILL.md` is the canonical source and every
shipped copy must stay byte-for-byte in sync. Drift is enforced automatically by
`plugins/crew/scripts/validate-plugin.sh` (CI fails on mismatch); reviewers should
still flag any drift that slips through as at least a **Warning**, and **Blocking**
when it would change reviewer behavior.

## Validating changes

This repo has no app build. Before opening a PR, run what CI runs:

```bash
shellcheck plugins/*/hooks/*.sh plugins/*/scripts/*.sh
bash plugins/crew/scripts/validate-plugin.sh
```

`validate-plugin.sh` parses each `plugins/*/agents/*.md` YAML frontmatter and verifies every
entry in its `skills:` list resolves to some `plugins/*/skills/<name>/SKILL.md` in the repo
(skills are referenced unqualified, per existing convention). A typo here would otherwise fail
silently at runtime — the skill just doesn't load and the agent guesses.

## Releasing

Versions are per-plugin. To cut a release:

1. Bump `version` in `plugins/<name>/.claude-plugin/plugin.json` and add a `CHANGELOG.md`
   entry (a PR that changes plugin behavior must do this — see `.github/copilot-instructions.md`).
2. Merge to `main`. `.github/workflows/auto-release.yml` runs on the push, sees the new
   version has no `<plugin>--v<version>` tag yet, and creates the tag and GitHub Release
   automatically, with notes pulled from that version's `CHANGELOG.md` section. No
   matching changelog entry → it skips with a warning. No manual tagging is needed
   (`claude plugin tag` exists for tagging by hand, but here the workflow owns it).

## Conventions

- Hooks are Bash scripts (`#!/usr/bin/env bash`); keep them shellcheck-clean.
- Agent/command/skill definitions are Markdown with YAML frontmatter — match the field
  shape of existing files in the same directory.
- Local agent memory lives in `.claude/agent-memory-local/` and is gitignored. Don't commit it.
- Keep diffs minimal-scope; list unrelated improvements rather than bundling them.
- PR titles follow Conventional Commits: `type(scope): summary`, with a `(vX.Y.Z)` suffix
  when the PR bumps a plugin version. Use `feat`/`fix`/`chore`/`docs`/`ci`/`refactor`; scope
  the plugin when the change is plugin-specific (e.g. `feat(crew): … (v1.9.0)`).
- When a PR resolves an issue, link it with a GitHub closing keyword in the body —
  `Closes #N` / `Fixes #N` / `Resolves #N` — so the issue auto-closes on merge. Plain
  references like `Implements #N` only cross-link; they do not close the issue.
