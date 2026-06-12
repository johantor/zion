---
name: debt-taxonomy
description: Catalog of suppression mechanisms, upgrade tiers, classification rubric, safe-removal recipes, and handoff-outline format for the keymaker crew. Load into keymaker (orchestrator) and twin (fixer).
---

# Debt taxonomy

## Suppression mechanisms

### .NET / C#
| Mechanism | Scope | Notes |
|---|---|---|
| `#pragma warning disable CS####` / `restore` | Block | Removal re-enables for that block only |
| `[SuppressMessage("category", "id")]` | Member/type | Check for `Justification` param — justified ones may be legitimate |
| `<NoWarn>CS####;CS####</NoWarn>` in `.csproj` | Project-wide | Single line, large blast radius — expand to diagnostic count before gating |
| `<NoWarn>` in `Directory.Build.props` | Solution-wide | Even larger; treat as tier 2 unless count is tiny |
| `.editorconfig` severity downgrade (`dotnet_diagnostic.CS####.severity = none/silent`) | Folder-scoped | Count diagnostics under the folder, not just this line |
| `GlobalSuppressions.cs` | Assembly-wide | File may have many entries — enumerate each as a separate finding |
| Skipped tests: `[Fact(Skip="…")]`, `[Theory(Skip="…")]` | Test | Classify as needs-investigation; never un-skip without confirmation |

### TypeScript / JavaScript / Frontend
| Mechanism | Scope | Notes |
|---|---|---|
| `// eslint-disable-next-line rule-name` | Next line | |
| `// eslint-disable rule-name` … `// eslint-enable` | Block | |
| `/* eslint-disable */` (no rule) | File | Broad; expand to diagnostic count |
| `// biome-ignore lint/category/rule: reason` | Next line | Reason present = possibly legitimate |
| `@ts-ignore` | Next line | Worst kind — suppresses *all* errors; removal may surface multiple issues |
| `@ts-expect-error` | Next line | **Cheap-win detector**: if the underlying issue was already fixed, removal compiles clean; if not, the error is now explicit — always safe to attempt |
| `it.skip` / `test.skip` / `xit` / `xdescribe` | Test | Classify as needs-investigation; never un-skip without confirmation |
| `tsconfig.json` `strict: false` or disabled checks | Project-wide | Tier 2; outline only |
| ESLint `rules: { "rule": "off" }` in config file | Project-wide | Treat like `<NoWarn>` in props — expand diagnostic count |

### Upgrade pointer shapes
| Pointer shape | Tier | Example |
|---|---|---|
| Single package, patch/minor | 1 — proceed | `lodash 4.17.19 → 4.17.21` |
| Single package, major | 1 — proceed (with migration notes via Context7) | `Newtonsoft.Json 12 → 13` |
| Multi-package coordinated bump | 1 if same lane, 2 if cross-lane | `react + react-dom + @types/react` |
| Framework/platform version (TFM, Node major, React major) | 2 — outline only | `.NET 6 → .NET 8`, `Node 18 → 22` |
| ORM / DB driver major | 1 if API-stable, 2 if breaking migrations required | `EF Core 7 → 8` (1), `EF Core 6 → 7` (2 if raw SQL changes) |
| Bundler / toolchain replacement | 2 — outline only | `webpack → vite`, `tsc → swc` |

## Classification rubric

Classify every suppression *before* gating. Applied in order:

1. **Legitimately suppressed** — has a meaningful justification comment/param AND the issue it suppresses is a known false-positive or intentional pattern. Action: add or verify justification comment; leave the suppression; remove from backlog.
2. **Trivially fixable** — suppression is stale (the diagnostic no longer fires at that location) OR the fix is a one-line code change (rename, null-check, cast). Action: remove suppression and/or apply fix; verify.
3. **Needs real work** — fix requires design judgment, non-trivial refactor, or understanding of business logic. Action: include in batch with explicit acceptance criteria; twin implements.
4. **Needs investigation** — skipped tests, `@ts-ignore` without context, any suppression with no commit rationale and an unclear rule. Action: `git log -1 --format="%s %ae %ar" -- <file>` to surface committer/date; flag in report; do not auto-fix.
5. **Environmental** — suppresses a tooling/build-environment quirk that is not fixable in application code (e.g. generated code, third-party vendored files, CI-only paths). Action: mark as legitimate; suggest adding a `Justification` param.

## Blast-radius gate

Before fixing anything, enumerate with scripts:

```bash
# Count occurrences — never stream file bodies
grep -rn --include="*.cs" "pragma warning disable CS8602" src/ | wc -l
grep -rn --include="*.ts" "@ts-expect-error" src/ | wc -l
```

Then apply the gate:
- **≤ 5 findings, single lane** → proceed immediately (one twin, one commit)
- **6–40 findings, single lane** → proceed in batches (fan twins by directory cluster)
- **6–40 findings, cross-lane** → one background twin per lane, parallel dispatch
- **> 40 findings for a single rule** → stop, present natural slices (by directory/project), ask user which to proceed with; remainder becomes an open item or handoff outline on request
- **Platform migration detected** → classify as tier 2; produce handoff outline on user request; stop

## Batch commit shape

One commit per rule/batch (bisectable). Message shape: `chore(debt): remove CS8602 suppression in src/Orders/ (4 sites)`. Always delete the suppression after the fix verifies — never leave both the fix and the suppression in place.

## Handoff outline format (tier-2 projects only)

Written to `.claude/plan-<slug>.md`. Morpheus-compatible so a slice can feed `/crew:feature` directly.

```markdown
# <Migration name> — handoff outline

## Scope
<What this migration is and why it was classified as a project.>

## Blast radius (evidence)
- Backend: <count> call sites across <N> files in <projects>
- Frontend: <count> issues across <N> files
- Cross-cutting: <list any shared contracts, config files, or build pipeline changes>

## Work packages

### WP1: <name> (independent)
Acceptance criteria:
- <verifiable gate, e.g. "project X compiles against v5 with no errors">
Files in scope: <directory clusters>
Lane: backend | frontend | both
Open questions: <list unknowns — do not guess>

### WP2: <name> (depends-on: WP1)
...

## Verification
Build command: <from CLAUDE.md crew configuration>
Test command: <from CLAUDE.md crew configuration>
Lint command: <from CLAUDE.md crew configuration>

## Known risks
<list; mark each UNKNOWN if unconfirmed>

## Open questions
<list; these must be resolved before any WP starts>
```

## Package-manager variance

- **NuGet**: check for `Directory.Packages.props` (Central Package Management) — version is declared there, not in individual `.csproj`; update in one place
- **npm**: update `package.json` + commit `package-lock.json`; warn if `peerDependencies` conflict
- **pnpm**: update `package.json` + commit `pnpm-lock.yaml`; check `pnpm-workspace.yaml` for monorepo version pins
- **yarn**: update `package.json` + commit `yarn.lock`
- Transitive/peer conflicts → report and stop; never silently pin or `--legacy-peer-deps`
