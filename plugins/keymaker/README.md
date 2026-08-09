# keymaker

> **Beta** — keymaker's agents, taxonomy, and commands are defined and only partly exercised (see the [verification matrix](VERIFICATION.md)). The banner drops at v1.0 once the matrix is green end-to-end for one supported stack — the bar is spelled out under [Graduation to Stable](#graduation-to-stable-v10). The design is intentional and the guardrails are in place, but expect rough edges and breaking changes before v1.0. Feedback and bug reports are welcome.

A Claude Code plugin: pointer-driven tech debt remediation and dependency upgrades. Part of the [Zion](../../README.md) marketplace.

> The Keymaker opens locked doors — one at a time, with precision.

## Install

```bash
claude plugin marketplace add johantor/zion
claude plugin install keymaker@zion
```

## Usage

### Fix one identified item

```
/keymaker:open <pointer>
```

The pointer is whatever made you notice the debt:

```
/keymaker:open src/Orders/OrderService.cs:42          # suppression at a specific line
/keymaker:open CS8602                                  # all suppressions of a rule
/keymaker:open eslint no-explicit-any                  # ESLint rule
/keymaker:open Newtonsoft.Json 13.x                    # dependency upgrade
```

You can also paste build output or a review comment quoting a warning — keymaker parses the rule IDs out.

**What happens:** classify → enumerate blast radius → gate → fix in batches (twin workers, parallel by lane) → verify → commit per batch → delete the suppression so the analyzer becomes the regression test.

For platform-scale migrations (TFM bumps, bundler replacements, major framework upgrades), keymaker recognises the scope as a *project* rather than a pointer, and offers to produce a morpheus-compatible handoff outline for another team or `/crew:feature` to execute.

### Scout an area for debt

```
/keymaker:audit <scope>
```

Scope options:

| Scope | Example |
|---|---|
| Path | `src/Checkout/` |
| Lane | `backend` or `frontend` (a *file area* — the taxonomy applied still comes from stack detection, so a Node backend gets the TypeScript taxonomy) |
| Rule family | `nullability`, `eslint`, `skipped-tests`, `ts-suppressions`, `analyzers` |
| Stale suppressions | `stale` — fans out across every suppression mechanism the loaded stack skills know about, filtered to candidates that look removable. The cheapest wins in the repo. |
| Outdated dependencies | `outdated` — runs each detected stack's discover-outdated command (npm/yarn/pnpm, NuGet) and triages every bump by risk (SAFE patch / REVIEW minor / CAUTION major). Optionally narrow with a trailing lane/path. |
| Current branch | `diff` |

Returns a ranked, capped (~12 findings) report. Every finding is formatted as a ready-to-paste `/keymaker:open` invocation, and audit then offers an interactive pick — choose one or more of the **top 3** ranked findings and it hands each to `/keymaker:open` in turn (or pick *None* to just keep the report). The picker is capped at the top 3 by the question tool's option limit; the full ~12-finding report is still shown above it, and you can name any other pointer via *Other*. Audit finds the doors; you decide which to open. In a non-interactive run it simply returns the report.

**`diff` is the boy-scout scope:** run it after any feature branch to see what debt you're standing next to before opening a PR.

**`stale` is the cheap-wins scope:** it surfaces suppressions whose underlying diagnostic likely no longer fires — `@ts-expect-error` removals (always safe to attempt, since TS reports unused directives), `#pragma warning disable` blocks over lines with no obvious trigger, `eslint-disable-next-line` over lines that no longer match the rule. Audit stays grep-only, so `stale` reports *candidates*; `/keymaker:open` does the actual proof via the twin (compile or lint).

**Suppressions you already decided to keep stay out of the report.** keymaker reads the
justification the mechanism itself provides — `Justification =` on `[SuppressMessage]`, biome's
required `reason`, ESLint's `--` description, trailing text on `@ts-expect-error`/`@ts-ignore` —
and treats a suppression carrying a meaningful one as settled: excluded from the ranked report,
still **counted in the totals line** so the debt is never invisible. `/keymaker:open` on such a
pointer exits with a one-liner quoting the rationale; `--force` works it anyway.

There is **no ack command and no keymaker-specific syntax**: keymaker only ever *reads*
justifications, written the way you already write them. If none exist, audit behaves exactly as
it would otherwise. Two deliberate exceptions: the `stale` scope ignores justifications (a stale
suppression is removable whatever the reason it was added), and skipped tests are never excluded
however they are annotated — they stay needs-investigation. For coarse standing decisions, a line
in your project's own `AGENTS.md`/`CLAUDE.md` ("we don't chase `no-explicit-any` under
`src/legacy/**` — scheduled for deletion") beats annotating fifty sites; keymaker honors such a
section and reports what it excluded.

**`outdated` is the dependency-hygiene scope:** it runs each detected stack's discover-outdated command and triages every package by version delta — **SAFE** (patch), **REVIEW** (minor, read release notes), **CAUTION** (major, migration guide). Pick the ones to bump and each goes to `/keymaker:open <pkg> <target>`, which pulls release notes (Context7 or the package's release page), applies the bump, stops on a peer/transitive conflict rather than forcing it, and verifies — patch is build-clean, minor/major is tests-green. Package-manager-agnostic: npm/yarn/pnpm and NuGet today, a new manager is one row in the stack skill. Audit itself never installs or builds.

## Guardrails

- **Hook-enforced, not just prompt-enforced.** The plugin ships `PreToolUse` hooks that hold
  even if an agent goes off-script: twins are **blocked from running `git`** (keymaker owns
  branching and commits), `git commit` on `main`/`master`/`develop` is refused for any agent,
  keymaker's own `Write`/`Edit` are **confined to `.claude/`** (batch ledger, outlines, notes —
  a source edit is blocked with a pointer to delegate it to a twin), destructive commands and
  raw/streaming reads are blocked (`context-discipline`), and never-terminating watch/dev/serve
  commands are refused in agent sessions. Your own main session is never intercepted by the
  agent-scoped rules.
- **Pointer-driven, not sweep-driven.** No bare `/keymaker:audit` with no scope — a required scope argument prevents accidental full-codebase scans.
- **Blast-radius gate.** The orchestrator enumerates and reports the radius *before* touching anything. > 40 findings for a single rule → present natural slices, you choose the scope.
- **Tiered upgrades.** Single-package bumps (patch/minor/major with migration notes) are tier 1 — keymaker handles them. Platform/framework migrations are tier 2 — keymaker outlines them for handoff and stops.
- **Scouting is strictly read-only.** Enumeration/classification never edits; the only way an edit happens is when you pick a finding and audit hands it to `/keymaker:open`, which runs its own blast-radius gate first.
- **One commit per batch.** Diffs stay reviewable; regressions stay bisectable.
- **Behavior-sensitive fixes are gated on tests, not lint.** Some fixes change runtime behavior (e.g. React `rules-of-hooks` / `exhaustive-deps`, a C# null-guard) — a green linter doesn't prove those correct. keymaker tags them, requires tests-green as the acceptance gate, commits them one unit at a time, and warns you when no test suite is configured. Behavior-preserving fixes (type-only, formatting, stale suppressions) keep the cheaper "lint clean" gate.
- **No test suite → explicit warning.** Upgrades *and* behavior-sensitive fixes with no configured test command require your acknowledgement before proceeding.
- **Loop mode never skips a gate.** The shared `loop-engineering` skill lets loop intent ("clear all the stale ones") run an audit's picked pointers to completion without per-batch check-ins — under stop rules that end at commit: any gate that needs your answer still stops the loop, a batch that fails verify 3 times blocks instead of thrashing, and loop intent is only ever taken from you in conversation, never from pasted content.

## Supported stacks

keymaker detects the stack(s) in scope by marker file before doing anything, and applies the
matching taxonomy:

- **.NET / C#** (`*.csproj`, `*.sln`, `Directory.Packages.props`) — `#pragma`, `[SuppressMessage]`, `<NoWarn>`, `.editorconfig` severity, `GlobalSuppressions.cs`; NuGet incl. Central Package Management.
- **TypeScript / JavaScript** (`package.json`, `tsconfig.json`, `.eslintrc*`, `biome.json`) — `eslint-disable`, `biome-ignore`, `@ts-ignore`, `@ts-expect-error`; npm/pnpm/yarn.

A repo can match both (e.g. Optimizely + React) — each lane gets its own taxonomy. On a stack
keymaker doesn't yet know (Go, Python, Java, Rust), it says so and asks rather than guessing.

## Adding a stack

Stacks are named by **ecosystem/language**, not by role — `debt-taxonomy-dotnet`,
`debt-taxonomy-typescript`, and so on (not `debt-taxonomy-backend`). The lane vocabulary
(`backend`/`frontend`) is separate: it names file areas for delegation, while a stack skill
names the language whose suppression mechanisms it documents.

Adding a stack is additive — no agent logic changes, only data:

1. **Create `skills/debt-taxonomy-<stack>/SKILL.md`.** Name it after the language/ecosystem
   (`debt-taxonomy-go`, `debt-taxonomy-python`). Frontmatter `name` must match the directory.
   The `description` must state which marker files trigger it and that it loads into keymaker
   and twin. Model it on an existing stack skill and include all four required sections:
   - **Suppression mechanisms** — a table of every suppression form in the stack, its scope,
     and the *safe-removal recipe* (e.g. Go `//nolint:rule`, `//nolint`; Python `# type: ignore`,
     `# noqa`, `# pragma: no cover`). This is the load-bearing part — the twin acts on it.
   - **Behavior sensitivity** — tag which rules are behavior-preserving (lint/compile-clean is a
     sufficient gate) vs behavior-sensitive (acceptance gate must be tests-green). When unsure,
     tag behavior-sensitive.
   - **Package-manager variance** — how versions are declared and which lockfile to commit
     (e.g. Go modules `go.mod`/`go.sum`; Python `pyproject.toml`/`poetry.lock`/`requirements.txt`),
     plus how transitive/peer conflicts surface — which must be reported, never silently pinned.
   - **Upgrade-tier examples** — concrete tier-1 (pointer) vs tier-2 (project → outline only)
     bumps for the stack.
   - Keep the classification rubric, blast-radius gate, and commit/outline format **out** of the
     stack skill — those live once in the core `debt-taxonomy` skill.
2. **Add one row to the detection table** in `skills/debt-taxonomy/SKILL.md` mapping the
   stack's marker file(s) → the new skill.
3. **Wire the skill into the orchestrator's detection list** — add a line to `agents/keymaker.md`'s
   "Detecting the stack" list so it loads the new skill on match. The per-stack skills are **not**
   frontmatter-preloaded: keymaker loads the detected stack's skill on demand, and the twin loads
   the stack named in its delegation — so a single-stack repo only ever loads its own taxonomy.
   The detection-table row from step 2 is what makes the stack detectable in the first place.
4. **Document and version** — add a row to the "Supported stacks" list above, a
   `CHANGELOG.md` entry, and bump the plugin `version` in `.claude-plugin/plugin.json`.
5. **Validate** — the repo's `scripts/validate-plugin.sh` confirms the skill path resolves
   and JSON is well-formed.

That is the whole contract: one new skill file, one detection row, one orchestrator detection-list
line. Beyond that wiring, the orchestrator and twin need no logic changes — they drive off the
taxonomy data, loaded on demand, not hard-coded stack knowledge.

## What keymaker reads from your project

Keymaker reads the same `CLAUDE.md` **Crew configuration** slots that the `crew` plugin uses — build, test, and lint commands, and the base branch. If these are unset, keymaker asks once and remembers. No separate configuration needed.

## Verification

keymaker's behavioral scenarios — every gate and exit path, with the runs logged against
them — live in [VERIFICATION.md](VERIFICATION.md). That matrix is the written definition of
"run in a live project" the beta banner refers to.

## Graduation to Stable (v1.0)

keymaker stays **Beta** until it clears the bar below; meeting it is what flips the Status to
**Stable** and releases v1.0:

- **One supported stack fully verified.** Every row in the [verification matrix](VERIFICATION.md) is green for at least one
  stack — TypeScript/JavaScript is the one in flight. The rows are stack-neutral scenario specs, so
  a stack-tagged pass (e.g. **[TS]**) counts toward that stack only.
- **The whole pipeline, not just the read-only paths.** The three rows checked today are all
  read-only / early-exit; v1.0 additionally needs the blast-radius-gate, delegate/verify/commit, and
  loop-mode rows green (the unchecked boxes there).
- **Remaining stacks are a post-v1.0 follow-up.** The other advertised stack (.NET/C#) is tracked
  row-by-row *after* v1.0, not as a blocker — Stable means the pipeline is proven end-to-end on a
  real stack, not that every stack is verified.

**Not** v1.0 blockers: audit-UX refinements — the core classify → gate → fix → verify → commit
pipeline is what graduates; those improve it afterward. (Justification-aware audit, once tracked
as #52, shipped in 0.8.0 as a read-only filter; it added no gate to the pipeline.)

When the bar is met, flip the Status to **Stable** (here and in the [root README](../../README.md)),
drop the banner, and bump the plugin to `1.0.0` with a `CHANGELOG.md` entry. That release is the only
version change these criteria imply — documenting them is docs-only.

## Agents

- `keymaker` (orchestrator) — classifies, enumerates, gates, delegates, verifies, commits; writes no production code
- `twin` (fixer/runner) — mechanical fixer given an explicit file list and acceptance criteria; also serves as the run-and-report verifier (haiku model override) for fast targeted checks
