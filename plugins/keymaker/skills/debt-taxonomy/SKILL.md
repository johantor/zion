---
name: debt-taxonomy
description: Stack-neutral core for the keymaker crew — stack detection, classification rubric, blast-radius gate, upgrade tiers, batch commit shape, and handoff-outline format. Pairs with a per-stack taxonomy skill (debt-taxonomy-dotnet, debt-taxonomy-typescript). Load into keymaker and twin.
---

# Debt taxonomy (core)

This is the stack-neutral core. The suppression mechanisms, package-manager variance, and
upgrade examples for a specific stack live in that stack's skill:

- **.NET / C#** → `debt-taxonomy-dotnet`
- **TypeScript / JavaScript** (React frontend or Node backend/CLI) → `debt-taxonomy-typescript`

## Stack detection

Before enumerating or classifying, detect the stack(s) in scope with a single marker-file
pass — do not assume. Apply the matching per-stack skill for each detected stack.

| Marker file(s) | Stack | Skill to apply |
|---|---|---|
| `*.csproj`, `*.sln`, `Directory.Packages.props`, `Directory.Build.props`, `global.json` | .NET / C# | `debt-taxonomy-dotnet` |
| `package.json`, `tsconfig.json`, `.eslintrc*`, `biome.json` | TypeScript / JS | `debt-taxonomy-typescript` |

```bash
# One pass — presence only, no file bodies
ls *.sln Directory.Packages.props Directory.Build.props global.json 2>/dev/null
find . -maxdepth 3 \( -name '*.csproj' -o -name 'package.json' -o -name 'tsconfig.json' \
  -o -name '.eslintrc*' -o -name 'biome.json' \) 2>/dev/null | head
```

A repo may match more than one stack (a typical Optimizely + React solution matches both) —
that is expected; apply each stack's skill to its own lane.

**Lanes are not stacks.** A lane (`backend`/`frontend`) names a *file area* used for scoping
and delegation; a stack names a *language*. Never infer the taxonomy from the lane name — a
`backend` lane is C# in an Optimizely repo but TypeScript in a Node repo. The skill applied to
a file always comes from the marker-file detection above, regardless of which lane the file
sits in.

**If no stack matches** (Go, Python, Java, Rust, etc.): say so plainly, report what marker
files you *did* find, and ask the user for the suppression mechanism rather than guessing.
Do not attempt to fix a stack keymaker has no taxonomy for — a wrong suppression edit is
worse than no edit. (Adding a stack is a small additive change: a new `debt-taxonomy-<stack>`
skill plus a row in the table above.)

## Upgrade tiers (stack-neutral shapes)

| Pointer shape | Tier | Action |
|---|---|---|
| Single package, patch/minor | 1 | Proceed |
| Single package, major | 1 | Proceed with migration notes (Context7) |
| Multi-package coordinated bump | 1 if same lane, 2 if cross-lane | Proceed or outline |
| Framework/platform version (TFM, runtime major, framework major) | 2 | Outline only |
| Toolchain replacement (bundler, compiler) | 2 | Outline only |

Concrete per-stack examples (EF Core, React, .NET TFM, Node major) live in the stack skills.

**The rule:** a version bump is a pointer; a platform migration is a project. Pointers
keymaker fixes. Projects keymaker outlines and hands off.

## Stale-suppression heuristic (audit `stale` scope)

The `/keymaker:audit stale` scope fans out across every suppression mechanism each loaded
per-stack skill declares, filtered to suppressions that look removable. Audit is grep-only
(`context-discipline`) — true staleness requires a compile, which is too expensive for a
scout pass. So `stale` reports **candidates**; final proof is left to `/keymaker:open`,
where a twin can compile/build and confirm.

Each `debt-taxonomy-<stack>` skill is responsible for declaring, per mechanism, a
**grep-only stale heuristic** — a textual signal that suggests the suppression is likely
removable without reading the diagnostic state. Rule of thumb when authoring one: it must
be checkable from a `grep`/`rg` invocation alone, with no parser, no compiler, no AST.
Examples (non-exhaustive — the per-stack skill is the source of truth):

- `@ts-expect-error` — the TS skill calls these the highest-value, lowest-risk findings;
  TypeScript self-reports unused directives, so any that are truly stale already error at
  compile time. All are candidates; TS self-proves staleness.
- `#pragma warning disable CS####` whose surrounded line has no obvious trigger for that
  diagnostic (e.g. a `disable CS8602` block over a line with no `.` member access).
- `// eslint-disable-next-line` over a line that no longer matches the rule's syntactic
  shape (e.g. `no-explicit-any` over a line with no `any`).

Findings from `stale` scope are classified through the same rubric as any other audit —
typically rubric class 2 (trivially fixable) and behavior-preserving — and ranked the same
way. Every finding still emits a ready-to-paste `/keymaker:open <pointer>` so the user can
ask a twin to prove the candidate stale and remove it.

## Classification rubric

Classify every suppression *before* gating. Applied in order:

1. **Legitimately suppressed** — has a meaningful justification comment/param AND the issue it suppresses is a known false-positive or intentional pattern. Action: add or verify justification; leave the suppression; remove from backlog.
2. **Trivially fixable** — suppression is stale (the diagnostic no longer fires at that location) OR the fix is a one-line code change (rename, null-check, cast). Action: remove suppression and/or apply fix; verify.
3. **Needs real work** — fix requires design judgment, non-trivial refactor, or understanding of business logic. Action: include in batch with explicit acceptance criteria; twin implements.
4. **Needs investigation** — skipped tests, blanket suppressions without context, any suppression with no commit rationale and an unclear rule. Action: `git log -1 --format="%s %ae %ar" -- <file>` to surface committer/date; flag in report; do not auto-fix.
5. **Environmental** — suppresses a tooling/build-environment quirk not fixable in application code (generated code, vendored files, CI-only paths). Action: mark legitimate; suggest a justification.

## Behavior sensitivity (orthogonal to the rubric)

Independently of the rubric class, tag every finding as **behavior-preserving** or
**behavior-sensitive** — they need different verification:

- **Behavior-preserving** — the fix cannot change runtime behavior: type-only changes, unused-symbol removal, formatting, stale suppressions whose diagnostic no longer fires. For these, "compiler/linter clean" is a **sufficient** acceptance gate.
- **Behavior-sensitive** — the fix moves, adds, or reorders runtime logic, so a green linter does **not** prove correctness. For these, the acceptance gate **must be "tests green," not "lint clean."** Examples are tagged per stack (see the stack skills) — e.g. React hook placement/dependency rules.

Which rules are behavior-sensitive is listed in each per-stack skill. When in doubt, treat a
finding as behavior-sensitive — the cost of an unnecessary test run is far below the cost of a
silent behavior regression.

## Blast-radius gate

Enumerate with scripts — counts and file paths, never file bodies (`context-discipline`).
Then apply the gate:

- **≤ 5 findings, single lane** → proceed immediately (one twin, one commit)
- **6–40 findings, single lane** → proceed in batches (fan twins by directory cluster)
- **6–40 findings, cross-lane** → one background twin per lane, parallel dispatch
- **> 40 findings for a single rule** → stop, present natural slices (by directory/project), ask user which to proceed with; remainder becomes an open item or handoff outline on request
- **Platform migration detected** → classify as tier 2; produce handoff outline on user request; stop
- **Behavior-sensitive findings with no test command configured** → warn the user explicitly ("these change runtime behavior and no test suite is configured — a green linter won't catch a regression") and require acknowledgement before proceeding. This is the same warning the upgrade path gives; it applies to any behavior-sensitive batch, not just upgrades.

Behavior-sensitive batches commit **one logical unit per commit** (e.g. one component per
commit for a hook-placement fix) so a behavior regression stays bisectable — don't bundle
eight restructured components into one commit.

A project-wide suppression (one config line, repo-wide effect) must be expanded to its
**diagnostic count**, not its line count, before gating.

## Batch commit shape

One commit per rule/batch (bisectable). Message shape:
`chore(debt): remove CS8602 suppression in src/Orders/ (4 sites)`. Always delete the
suppression after the fix verifies — never leave both the fix and the suppression in place.

## Handoff outline format (tier-2 projects only)

Written to `.claude/plan-<slug>.md`. Morpheus-compatible so a slice can feed `/crew:feature` directly.

```markdown
# <Migration name> — handoff outline

## Scope
<What this migration is and why it was classified as a project.>

## Blast radius (evidence)
- Backend: <count> call sites across <N> files in <projects>
- Frontend: <count> issues across <N> files
- Cross-cutting: <shared contracts, config files, or build pipeline changes>

## Work packages

### WP1: <name> (independent)
Acceptance criteria:
- <verifiable gate, e.g. "project X compiles against v5 with no errors">
Files in scope: <directory clusters>
Lane: backend | frontend | both
Open questions: <unknowns — do not guess>

### WP2: <name> (depends-on: WP1)
...

## Verification
Build / Test / Lint commands: <from CLAUDE.md crew configuration>

## Known risks
<list; mark each UNKNOWN if unconfirmed>

## Open questions
<must be resolved before any WP starts>
```
