# keymaker

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
| Lane | `backend` or `frontend` |
| Rule family | `nullability`, `eslint`, `skipped-tests`, `ts-suppressions`, `analyzers` |
| Current branch | `diff` |

Returns a ranked, capped (~12 findings) read-only report. Every finding is formatted as a ready-to-paste `/keymaker:open` invocation — audit finds the doors, you decide which to open.

**`diff` is the boy-scout scope:** run it after any feature branch to see what debt you're standing next to before opening a PR.

## Guardrails

- **Pointer-driven, not sweep-driven.** No bare `/keymaker:audit` with no scope — a required scope argument prevents accidental full-codebase scans.
- **Blast-radius gate.** The orchestrator enumerates and reports the radius *before* touching anything. > 40 findings for a single rule → present natural slices, you choose the scope.
- **Tiered upgrades.** Single-package bumps (patch/minor/major with migration notes) are tier 1 — keymaker handles them. Platform/framework migrations are tier 2 — keymaker outlines them for handoff and stops.
- **Audit is strictly read-only.** No edit ever happens from an audit run.
- **One commit per batch.** Diffs stay reviewable; regressions stay bisectable.
- **Behavior-sensitive fixes are gated on tests, not lint.** Some fixes change runtime behavior (e.g. React `rules-of-hooks` / `exhaustive-deps`, a C# null-guard) — a green linter doesn't prove those correct. keymaker tags them, requires tests-green as the acceptance gate, commits them one unit at a time, and warns you when no test suite is configured. Behavior-preserving fixes (type-only, formatting, stale suppressions) keep the cheaper "lint clean" gate.
- **No test suite → explicit warning.** Upgrades *and* behavior-sensitive fixes with no configured test command require your acknowledgement before proceeding.

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
3. **Wire the skill into both agents** — add `debt-taxonomy-<stack>` to the `skills:` list in
   `agents/keymaker.md` and `agents/twin.md`, and add a line to the orchestrator's
   "Detecting the stack" list so it knows to apply it.
4. **Document and version** — add a row to the "Supported stacks" list above, a
   `CHANGELOG.md` entry, and bump the plugin `version` in `.claude-plugin/plugin.json`.
5. **Validate** — `plugins/crew/scripts/validate-plugin.sh` confirms the skill path resolves
   and JSON is well-formed.

That is the whole contract: one new skill file, one detection row, two agent wirings. The
orchestrator and twin need no behavioral changes because they drive off the taxonomy data,
not hard-coded stack knowledge.

## What keymaker reads from your project

Keymaker reads the same `CLAUDE.md` **Crew configuration** slots that the `crew` plugin uses — build, test, and lint commands, and the base branch. If these are unset, keymaker asks once and remembers. No separate configuration needed.

## Agents

- `keymaker` (orchestrator) — classifies, enumerates, gates, delegates, verifies, commits; writes no production code
- `twin` (fixer/runner) — mechanical fixer given an explicit file list and acceptance criteria; also serves as the run-and-report verifier (haiku model override) for fast targeted checks
