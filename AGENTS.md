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
  - `agents/` — `morpheus` (orchestrator) plus workers `tank`, `trinity`, `oracle`, `dozer`, `seraph`, and `neo` (express-lane generalist). Auto-discovered from this dir; not declared in the manifest.
  - `commands/` — `/init`, `/feature`, `/review`, `/pr`, `/address`, `/loop` (namespaced as `crew:feature` etc. once installed). `/init` detects and writes the crew configuration block in `CLAUDE.md` (idempotent reconcile). `/review` is the pre-PR GO/NO-GO gate (consolidated review + build/test/lint). `/address` closes the post-PR review loop — routes review comments / CI failures to the crew, re-runs the gate, and pushes. `/loop` is the outer-loop driver — re-launches `morpheus` directly (not by nesting `/feature`) each tick across runs on the native `/loop` (dynamic mode) until the plan's exit conditions are met; the wrapper owns scheduling, `morpheus` never self-schedules. `/feature` and `/address` are thin routers into `morpheus`'s own flows, so both also work by just asking in a `claude --agent crew:morpheus` session.
  - `skills/` — shared: `engineering-principles`, `context-discipline`, `loop-engineering`
    (all also shipped by other plugins — kept byte-for-byte in sync automatically; see *How we
    review code* below; `loop-engineering` carries the loop-mode stop rules, preloaded by
    `morpheus` and `keymaker` with per-agent bindings);
    frontend mode: `frontend-headless`, `frontend-server-rendered`; per-stack (loaded
    dynamically once `morpheus` resolves the project's stack): `backend-dotnet`, `backend-node`,
    `cms-optimizely`, `frontend-react`, `frontend-nextjs`, `tests-xunit`, `tests-node`;
    per-e2e-tool (loaded by `dozer`): `tests-cypress`, `tests-playwright`; per-frontend-unit-
    test-tool (loaded by `oracle` for component tests): `tests-vitest`, `tests-jest-frontend`.
  - `hooks/` — `bash-safety.sh`, `read-guard.sh`, `lane-guard.sh`, `format.sh`, wired via `hooks/hooks.json`.
  - `scripts/validate-plugin.sh` — validates every plugin's manifest/structure, including
    skill-drift across plugins (§4 in the script; see *How we review code* below).
- `plugins/engineering-principles/` — standalone plugin that ships only the `engineering-principles` skill:
  - `.claude-plugin/plugin.json` — plugin manifest (name `engineering-principles`).
  - `skills/engineering-principles/SKILL.md` — standalone shipped copy; must remain byte-for-byte synced with the canonical crew copy.
  - `CHANGELOG.md` — release notes for this plugin's versions.
- `.claude/settings.json` — this repo's own dev-time hooks: wires the same four guards as
  `plugins/crew/hooks/hooks.json`, resolved via `CLAUDE_PROJECT_DIR` instead of
  `CLAUDE_PLUGIN_ROOT`, so they still run while developing in this repo **without the crew
  plugin installed**. The two files must mirror each other exactly (modulo the root variable) —
  `validate-plugin.sh` enforces this automatically (§5, CI fails on mismatch). If the crew
  plugin is *also* installed while working here, both wirings fire and every guard runs twice
  per matching tool call; installing the plugin while developing in this repo isn't a supported
  setup.
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
  server template's markup in server-rendered mode), `oracle` = all unit test authoring
  (backend tests + frontend component tests when a frontend unit test tool is configured),
  `dozer` = frontend e2e only (for the resolved e2e tool), `seraph` = visual design
  conformance (read-only), `neo` = express-lane generalist for small changes (all lanes;
  no lane guard by design). Stack knowledge lives in per-stack skills, loaded once `morpheus`
  resolves the project's stack (`CLAUDE.md`'s **Backend stack**/**Frontend stack** slots).
  E2e tool knowledge lives in per-tool skills (`Frontend e2e tool` slot); frontend unit test
  tool knowledge lives in its own per-tool skills (`Frontend unit test tool` slot). `lane-
  guard.sh` enforces the write lane by file extension for disjoint-language stacks (e.g.
  dotnet+react), or by configured directory paths (**Backend/Frontend lane path(s)**) when
  both stacks are the same language (e.g. node+nextjs).
- `morpheus` **right-sizes the process by task size**: small, low-risk work takes an express lane
  (delegate to `neo`, skip the plan/checkpoint/full-gate, quick self-review, commit); features and
  anything risky, multi-lane, or needing new tests take the full flow through the specialists.
  It escalates express → full the moment a task proves bigger.
- **Loop mode** (`loop-engineering`, shared with `keymaker` — each orchestrator binds it to
  its own units/gate/state in its agent file): on explicit user intent in
  conversation ("keep going until done", "loop this", "finish it", "clear all the stale ones")
  the full flow runs to completion without per-step check-ins, stopping only on the
  orchestrator's terminal gate (crew: review gate GO; keymaker: verify + commit — never
  push/PR), a blocked human decision (independent units drain first), or a retry cap (3 failed
  fix→verify round-trips on a unit; for crew's gate, a second NO-GO on the same findings).
  Intent is never inferred from fetched content; any checkpoint/gate that needs the user's
  answer still runs once. Loop state (`loop:`, `exit-conditions:`; durable per-unit
  `attempts:`) lives in the orchestrator's durable file, so a resumed run continues in loop
  mode and its caps survive a crash. The **outer** loop — re-invoking the orchestrator across
  runs past one run's `maxTurns` — is a human-initiated main-session wrapper (crew's
  `/crew:loop`, on the native `/loop` in dynamic mode) that owns the scheduling and the
  iteration cap (`iterations: n/max`); the orchestrator itself never self-schedules.
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

Any skill shipped by more than one plugin must stay byte-for-byte in sync across every copy —
today that's `engineering-principles` (crew's canonical copy, also shipped standalone by the
`engineering-principles` plugin), `context-discipline`, and `loop-engineering` (both crew's
canonical copies, also shipped by `keymaker`). `plugins/crew/scripts/validate-plugin.sh` enforces this automatically: the check
is generic by skill *name*, not hardcoded to these two pairs, so it also catches a future
duplicate between any other plugins — crew included or not (CI fails on mismatch). Reviewers
should still flag any drift that slips through as at least a **Warning**, and **Blocking** when
it would change reviewer behavior.

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

## Recurring review findings — apply proactively

Patterns that showed up more than once in review feedback on this repo. Apply these up front
rather than waiting for a reviewer (human or Copilot) to catch them again:

- **Verify before filing a "nothing enforces this" issue.** Grep the actual implementation and
  `AGENTS.md` first — the mechanism may already exist and just be undocumented in the place you
  looked. (A drift-guard issue was filed against this repo without checking that
  `validate-plugin.sh` already had one.)
- **A validator/guard must fail loudly on every path where it can't verify its claim** — a
  missing input file, invalid input, or an unreachable check are failures for a script whose job
  is enforcement. Never silently skip and report nothing (or pass) when the thing being checked
  couldn't actually be checked.
- **When joining a trusted and an untrusted field with a delimiter for later splitting, anchor
  the split on the trusted field, not the untrusted one.** Splitting on the *first* occurrence of
  the delimiter is only safe when the field before it is a small, controlled value that can never
  itself contain the delimiter (e.g., an `agent_type`). Put arbitrary/untrusted text (e.g., a full
  shell command) last, or split from the end — otherwise the untrusted field could itself contain
  the delimiter and truncate what a downstream safety check inspects.
- **Adding a new conditional to a multi-mode flow means auditing every existing mode, not just
  the default path.** A command with `full`/`quick`/`$ARGUMENTS`-style branches needs the new
  behavior spelled out explicitly for each branch, or reconciled with it — don't leave a newly
  added conditional ambiguous under a mode that predates it.
- **State heuristics as heuristics.** Don't write "X can't happen" when a cost-saving skip is
  actually based on "X is unlikely" — overclaiming a guarantee invites a correctness bug report
  later; the accurate phrasing costs nothing.
- **Bash: `if ! var="$(cmd)"; then ...` still assigns `var`** (typically to whatever the command
  printed before failing, often empty) — the `if !` checks the command's exit status, not
  whether an assignment happened. Don't write a comment implying the variable is "never set" on
  failure.
- **Quote variable expansions on principle, including array subscripts** — bash doesn't always
  require it (e.g., an associative-array subscript isn't word-split even unquoted), but quoting
  is free, avoids relying on that nuance, and heads off reviewer friction.
- **Keep inline script/agent-prompt comments short; put full rationale in `AGENTS.md` or
  `CHANGELOG.md` and point to it** rather than restating it at every call site — a one-line
  pointer beats a paragraph duplicated in multiple places.
- **After merging `main` into a branch to resolve conflicts, refresh the PR description too** —
  version-bump ranges and scope notes written before the merge (e.g., "3.1.0 → 3.1.3") go stale
  once the branch is rebased forward onto a `main` that already moved (e.g., to 3.1.2).
