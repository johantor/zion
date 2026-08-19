# keymaker

[![keymaker](https://img.shields.io/github/v/release/johantor/zion?filter=keymaker/v*&label=)](https://github.com/johantor/zion/releases)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](../../LICENSE)

> **Beta.** The agents, taxonomy, and commands are defined and only partly exercised (see the
> [verification matrix](VERIFICATION.md)). The design is intentional and the guardrails are in
> place, but expect rough edges and breaking changes before v1.0, when the matrix goes green
> end-to-end for one stack; the bar is under [Graduation to Stable](#graduation-to-stable-v10).
> Feedback and bug reports are welcome.

**Pay down tech debt one verified fix at a time.** You point `keymaker` at something specific — a
suppression, a rule, an outdated package — and it classifies the work, reports the blast radius
*before* touching anything, fixes in batches through worker agents, and commits each batch only
once its acceptance gate passes. Deleting the suppression makes the analyzer itself the
regression test.

Part of the [Zion](../../README.md) marketplace.

> The Keymaker opens locked doors — one at a time, with precision.

## Why keymaker

- **Pointer-driven, not sweep-driven.** No bare "fix the codebase": every run starts from
  something you identified, and a required scope argument prevents accidental full-repo scans.
- **You see the blast radius first.** The radius is enumerated and reported before any edit; past
  40 findings for one rule, keymaker presents natural slices and waits for you to choose.
- **Behavior-sensitive fixes are gated on tests, not lint.** A green linter doesn't prove a hooks
  refactor or a null-guard correct, so those need tests-green, and you're warned when no suite
  is configured.
- **Reviewable history.** One commit per batch, so diffs stay readable and regressions stay
  bisectable.
- **It stops rather than guesses.** Peer conflicts, platform-scale migrations, and unknown stacks
  are reported and handed back, never forced through.

## What it won't do

- **It ends at commit.** No push, no PR command. Getting the work reviewed is yours.
- **Platform-scale migrations get an outline, not an implementation.** TFM bumps, bundler
  replacements, major framework upgrades: keymaker classifies them tier 2, writes a handoff
  outline, and stops.
- **Two stacks today:** .NET/C# and TypeScript/JavaScript. On a stack it doesn't know it says so
  and asks instead of guessing.
- **The gates stop and wait.** A >40-finding slice choice, a missing test command, a peer
  conflict. Each one needs your answer before anything continues, loop mode included.

## Install

```bash
claude plugin marketplace add johantor/zion
claude plugin install keymaker@zion
```

## Quick start

**Fix something you've already spotted.** The pointer is whatever made you notice the debt:

```
/keymaker:open src/Orders/OrderService.cs:42     # suppression at a specific line
/keymaker:open CS8602                            # all suppressions of a rule
/keymaker:open eslint no-explicit-any            # an ESLint rule
/keymaker:open Newtonsoft.Json 13.x              # a dependency upgrade
```

You can also paste build output or a review comment quoting a warning: keymaker parses the rule
IDs out of it.

**Or scout an area first**, and let the report tell you what's worth opening:

```
/keymaker:audit src/Checkout/
```

## Commands

| Command | What it does |
|---|---|
| `/keymaker:open <pointer>` | Fix one pointer: classify → enumerate blast radius → gate → fix in batches (twin workers, parallel by lane) → verify → commit per batch. Runs in the foreground so its gates can prompt. |
| `/keymaker:audit <scope>` | Read-only scout: a ranked, capped (~12) report where every finding is a ready-to-paste `/keymaker:open`. Offers an interactive pick of the top 3; edits nothing itself. |

### Audit scopes

| Scope | Example | What it's for |
|---|---|---|
| Path | `src/Checkout/` | Debt in one area |
| Lane | `backend`, `frontend` | A *file area*: the taxonomy still comes from stack detection, so a Node backend gets the TypeScript taxonomy |
| Rule family | `nullability`, `eslint`, `skipped-tests`, `ts-suppressions`, `analyzers` | One class of problem |
| Stale suppressions | `stale` | The cheapest wins in the repo: suppressions whose diagnostic likely no longer fires |
| Outdated dependencies | `outdated` | Every bump triaged by risk: **SAFE** patch / **REVIEW** minor / **CAUTION** major |
| Current branch | `diff` | The boy-scout scope: what debt you're standing next to before opening a PR |

<details>
<summary>How the stale, outdated, and justification behaviors work</summary>

**`stale`** surfaces suppressions whose underlying diagnostic likely no longer fires:
`@ts-expect-error` removals (always safe to attempt, since TS reports unused directives),
`#pragma warning disable` blocks over lines with no obvious trigger, `eslint-disable-next-line`
over lines that no longer match the rule. Audit stays grep-only, so `stale` reports *candidates*;
`/keymaker:open` does the actual proof via the twin (compile or lint).

**`outdated`** runs each detected stack's discover-outdated command and triages every package by
version delta. Pick the ones to bump and each goes to `/keymaker:open <pkg> <target>`, which pulls
release notes (Context7 or the package's release page), applies the bump, stops on a
peer/transitive conflict rather than forcing it, and verifies. Patch is build-clean, minor/major
is tests-green. Package-manager-agnostic: npm/yarn/pnpm and NuGet today, and a new manager is one
row in the stack skill. Audit itself never installs or builds.

**Suppressions you already decided to keep stay out of the report.** keymaker reads the
justification the mechanism itself provides — `Justification =` on `[SuppressMessage]`, biome's
required `reason`, ESLint's `--` description, trailing text on `@ts-expect-error`/`@ts-ignore` —
and treats a suppression carrying a meaningful one as settled: excluded from the ranked report,
still **counted in the totals line** so the debt is never invisible. `/keymaker:open` on such a
pointer exits with a one-liner quoting the rationale; `--force` works it anyway.

There is **no ack command and no keymaker-specific syntax**: keymaker only ever *reads*
justifications, written the way you already write them. Two deliberate exceptions: `stale` ignores
justifications (a stale suppression is removable whatever the reason it was added), and skipped
tests are never excluded however they're annotated. For coarse standing decisions, a line in your
project's own `AGENTS.md`/`CLAUDE.md` ("we don't chase `no-explicit-any` under `src/legacy/**`,
scheduled for deletion") beats annotating fifty sites; keymaker honors such a section and reports
what it excluded.

The picker is capped at the top 3 by the question tool's option limit; the full ~12-finding report
is still shown above it, and you can name any other pointer via *Other*. In a non-interactive run
audit simply returns the report.

</details>

## How a run works

- **Classify, then gate.** Every pointer is classified and its blast radius enumerated before an
  edit happens. Small and single-lane proceeds; 6–40 findings fan into batches; past 40 for one
  rule, keymaker presents slices and stops for your pick.
- **Fixes go to twins.** The orchestrator writes no production code. Mechanical fixes are
  delegated to `twin` workers, parallel by lane, each given an explicit file list and acceptance
  criteria.
- **The gate depends on the risk.** Behavior-preserving work (type-only, formatting, stale
  suppressions) is accepted lint-clean. Behavior-sensitive work (React `rules-of-hooks`, a C#
  null-guard) is accepted only tests-green, and needs your acknowledgement when no test command
  is configured.
- **Tier 2 is handed off, not attempted.** Platform-scale migrations — TFM bumps, bundler
  replacements, major framework upgrades — are recognised as a *project* rather than a pointer.
  keymaker produces a morpheus-compatible outline for another team or `/crew:feature`, and stops.
- **Loop mode never skips a gate.** "Clear all the stale ones" runs an audit's picked pointers to
  completion without per-batch check-ins, under stop rules that end at commit: any gate needing
  your answer still stops the loop, a batch failing verify 3× blocks instead of thrashing, and
  loop intent is only ever taken from you in conversation, never from pasted content.

## Safety guarantees

Hook-enforced, not just prompt-enforced: `PreToolUse` hooks hold even if an agent goes
off-script. Your own main session is never intercepted by the agent-scoped rules.

- **Twins can't touch git.** Blocked outright; keymaker owns branching and commits. `git commit`
  on `main`/`master`/`develop` is refused for every agent.
- **keymaker can't edit your source.** Its own `Write`/`Edit` are confined to `.claude/`: batch
  ledger, outlines, notes. A source edit is blocked with a pointer to delegate it to a twin.
- **Scouting is strictly read-only.** Enumeration and classification never edit. The only path to
  an edit is you picking a finding, and `/keymaker:open` runs its own blast-radius gate first.
- **Destructive and hanging commands are refused**, along with raw/streaming reads
  (`context-discipline`) and never-terminating watch/dev/serve commands in agent sessions.

## Supported stacks

keymaker detects the stack(s) in scope by marker file before doing anything, and applies the
matching taxonomy:

- **.NET / C#** (`*.csproj`, `*.sln`, `Directory.Packages.props`): `#pragma`,
  `[SuppressMessage]`, `<NoWarn>`, `.editorconfig` severity, `GlobalSuppressions.cs`; NuGet
  including Central Package Management.
- **TypeScript / JavaScript** (`package.json`, `tsconfig.json`, `.eslintrc*`, `biome.json`):
  `eslint-disable`, `biome-ignore`, `@ts-ignore`, `@ts-expect-error`; npm/pnpm/yarn.

A repo can match both (e.g. Optimizely + React), and each lane gets its own taxonomy. On a stack
keymaker doesn't yet know (Go, Python, Java, Rust), it says so and asks rather than guessing.

<details>
<summary>Adding a stack</summary>

Stacks are named by **ecosystem/language**, not by role: `debt-taxonomy-dotnet`,
`debt-taxonomy-typescript`, and so on (not `debt-taxonomy-backend`). The lane vocabulary
(`backend`/`frontend`) is separate: it names file areas for delegation, while a stack skill names
the language whose suppression mechanisms it documents.

Adding a stack is additive: no agent logic changes, only data:

1. **Create `skills/debt-taxonomy-<stack>/SKILL.md`.** Name it after the language/ecosystem
   (`debt-taxonomy-go`, `debt-taxonomy-python`). Frontmatter `name` must match the directory.
   The `description` must state which marker files trigger it and that it loads into keymaker
   and twin. Model it on an existing stack skill and include all four required sections:
   - **Suppression mechanisms:** a table of every suppression form in the stack, its scope,
     and the *safe-removal recipe* (e.g. Go `//nolint:rule`, `//nolint`; Python `# type: ignore`,
     `# noqa`, `# pragma: no cover`). This is the load-bearing part; the twin acts on it.
   - **Behavior sensitivity:** tag which rules are behavior-preserving (lint/compile-clean is a
     sufficient gate) vs behavior-sensitive (acceptance gate must be tests-green). When unsure,
     tag behavior-sensitive.
   - **Package-manager variance:** how versions are declared and which lockfile to commit
     (e.g. Go modules `go.mod`/`go.sum`; Python `pyproject.toml`/`poetry.lock`/`requirements.txt`),
     plus how transitive/peer conflicts surface, which must be reported, never silently pinned.
   - **Upgrade-tier examples:** concrete tier-1 (pointer) vs tier-2 (project → outline only)
     bumps for the stack.
   - Keep the classification rubric, blast-radius gate, and commit/outline format **out** of the
     stack skill; those live once in the core `debt-taxonomy` skill.
2. **Add one row to the detection table** in `skills/debt-taxonomy/SKILL.md` mapping the
   stack's marker file(s) → the new skill.
3. **Wire the skill into the orchestrator's detection list** by adding a line to
   `agents/keymaker.md`'s "Detecting the stack" list so it loads the new skill on match. The per-stack skills are **not**
   frontmatter-preloaded: keymaker loads the detected stack's skill on demand, and the twin loads
   the stack named in its delegation, so a single-stack repo only ever loads its own taxonomy.
   The detection-table row from step 2 is what makes the stack detectable in the first place.
4. **Document and version:** add a row to the "Supported stacks" list above, a
   `CHANGELOG.md` entry, and bump the plugin `version` in `.claude-plugin/plugin.json`.
5. **Validate:** the repo's `scripts/validate-plugin.sh` confirms the skill path resolves
   and JSON is well-formed.

That is the whole contract: one new skill file, one detection row, one orchestrator detection-list
line. Beyond that wiring, the orchestrator and twin need no logic changes; they drive off the
taxonomy data, loaded on demand, not hard-coded stack knowledge.

</details>

## Configuration

keymaker reads the same crew-configuration slots the `crew` plugin uses: build, test, and lint
commands, and the base branch. They live in `.claude/crew.md` (one frontmatter key per slot,
written by `/crew:init`), or in a legacy **Crew configuration** block in `CLAUDE.md` when that
file is absent. If a slot is unset, keymaker asks once and remembers. No separate configuration
needed — and none at all is required: without the file it just asks.

**Optional MCP:** [Context7](https://github.com/upstash/context7), for version-specific migration
notes on upgrades. Without it, keymaker falls back to the package's release page. Key the server
`context7` (`.mcp.json` or `claude mcp add`) and both agents pick it up. Installed as a plugin
instead, its tools are namespaced `mcp__plugin_<plugin>_<server>__<tool>`; the agents allowlist
`mcp__plugin_context7_context7` for that path, and any other plugin/server key needs its own
prefix added to `keymaker`/`twin` `tools:` — read the exact one off `/mcp`.

## Agents

- `keymaker` (orchestrator): classifies, enumerates, gates, delegates, verifies, commits; writes
  no production code.
- `twin` (fixer/runner): mechanical fixer given an explicit file list and acceptance criteria;
  also the run-and-report verifier (haiku model override) for fast targeted checks.

## Graduation to Stable (v1.0)

keymaker stays **Beta** until it clears the bar below; meeting it is what flips the Status to
**Stable** and releases v1.0:

- **One supported stack fully verified.** Every row in the [verification matrix](VERIFICATION.md)
  is green for at least one stack. TypeScript/JavaScript is the one in flight. The rows are
  stack-neutral scenario specs, so a stack-tagged pass (e.g. **[TS]**) counts toward that stack
  only.
- **The whole pipeline, not just the read-only paths.** The three rows checked today are all
  read-only / early-exit; v1.0 additionally needs the blast-radius-gate, delegate/verify/commit,
  and loop-mode rows green (the unchecked boxes there).
- **Remaining stacks are a post-v1.0 follow-up.** The other advertised stack (.NET/C#) is tracked
  row-by-row *after* v1.0, not as a blocker. Stable means the pipeline is proven end-to-end on a
  real stack, not that every stack is verified.

**Not** v1.0 blockers: audit-UX refinements. The core classify → gate → fix → verify →
commit pipeline is what graduates; those improve it afterward. (Justification-aware audit, once tracked
as #52, shipped in 0.8.0 as a read-only filter; it added no gate to the pipeline.)

When the bar is met, flip the Status to **Stable** (here and in the [root README](../../README.md)),
drop the banner, and bump the plugin to `1.0.0` with a `CHANGELOG.md` entry. That release is the
only version change these criteria imply; documenting them is docs-only.

## Contributing

Start with [AGENTS.md](../../AGENTS.md), the repository's contributor guide, and the
plugin-specific map in [CLAUDE.md](CLAUDE.md). Behavioral changes are verified against
[VERIFICATION.md](VERIFICATION.md). Release notes are in [CHANGELOG.md](CHANGELOG.md).
