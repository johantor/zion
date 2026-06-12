---
name: debt-taxonomy
description: Stack-neutral core for the keymaker crew — stack detection, classification rubric, blast-radius gate, upgrade tiers, batch commit shape, and handoff-outline format. Pairs with a per-stack taxonomy skill (debt-taxonomy-dotnet, debt-taxonomy-frontend). Load into keymaker and twin.
---

# Debt taxonomy (core)

This is the stack-neutral core. The suppression mechanisms, package-manager variance, and
upgrade examples for a specific stack live in that stack's skill:

- **.NET / C#** → `debt-taxonomy-dotnet`
- **TypeScript / JavaScript / frontend** → `debt-taxonomy-frontend`

## Stack detection

Before enumerating or classifying, detect the stack(s) in scope with a single marker-file
pass — do not assume. Apply the matching per-stack skill for each detected stack.

| Marker file(s) | Stack | Skill to apply |
|---|---|---|
| `*.csproj`, `*.sln`, `Directory.Packages.props`, `Directory.Build.props`, `global.json` | .NET / C# | `debt-taxonomy-dotnet` |
| `package.json`, `tsconfig.json`, `.eslintrc*`, `biome.json` | TypeScript / JS | `debt-taxonomy-frontend` |

```bash
# One pass — presence only, no file bodies
ls *.sln Directory.Packages.props global.json 2>/dev/null
find . -maxdepth 3 -name '*.csproj' -o -name 'package.json' -o -name 'tsconfig.json' 2>/dev/null | head
```

A repo may match more than one stack (a typical Optimizely + React solution matches both) —
that is expected; apply each stack's skill to its own lane.

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

## Classification rubric

Classify every suppression *before* gating. Applied in order:

1. **Legitimately suppressed** — has a meaningful justification comment/param AND the issue it suppresses is a known false-positive or intentional pattern. Action: add or verify justification; leave the suppression; remove from backlog.
2. **Trivially fixable** — suppression is stale (the diagnostic no longer fires at that location) OR the fix is a one-line code change (rename, null-check, cast). Action: remove suppression and/or apply fix; verify.
3. **Needs real work** — fix requires design judgment, non-trivial refactor, or understanding of business logic. Action: include in batch with explicit acceptance criteria; twin implements.
4. **Needs investigation** — skipped tests, blanket suppressions without context, any suppression with no commit rationale and an unclear rule. Action: `git log -1 --format="%s %ae %ar" -- <file>` to surface committer/date; flag in report; do not auto-fix.
5. **Environmental** — suppresses a tooling/build-environment quirk not fixable in application code (generated code, vendored files, CI-only paths). Action: mark legitimate; suggest a justification.

## Blast-radius gate

Enumerate with scripts — counts and file paths, never file bodies (`context-discipline`).
Then apply the gate:

- **≤ 5 findings, single lane** → proceed immediately (one twin, one commit)
- **6–40 findings, single lane** → proceed in batches (fan twins by directory cluster)
- **6–40 findings, cross-lane** → one background twin per lane, parallel dispatch
- **> 40 findings for a single rule** → stop, present natural slices (by directory/project), ask user which to proceed with; remainder becomes an open item or handoff outline on request
- **Platform migration detected** → classify as tier 2; produce handoff outline on user request; stop

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
