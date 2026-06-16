---
name: debt-taxonomy-typescript
description: TypeScript / JavaScript suppression mechanisms, safe-removal recipes, npm/pnpm/yarn package-manager variance, and upgrade-tier examples for the keymaker crew. Covers any JS/TS project — React frontend or Node backend/CLI. Apply when stack detection (debt-taxonomy) finds a JS/TS project. Load into keymaker and twin.
---

# Debt taxonomy — TypeScript / JavaScript

Apply this skill when `debt-taxonomy` stack detection finds a JS/TS project (`package.json`,
`tsconfig.json`, `.eslintrc*`, `biome.json`) — this covers any JavaScript/TypeScript code,
whether a React frontend or a Node backend/CLI. The React-specific rows below apply only when
React is present. Classification rubric and blast-radius gate are in the core `debt-taxonomy`
skill.

## Suppression mechanisms

| Mechanism | Scope | Safe-removal notes |
|---|---|---|
| `// eslint-disable-next-line rule-name` | Next line | Delete the comment; re-lint the file to confirm the rule passes. |
| `// eslint-disable rule-name` … `// eslint-enable` | Block | Delete both markers. |
| `/* eslint-disable */` (no rule) | File | Broad — expand to **diagnostic count** before gating. Prefer replacing with targeted per-line disables only where genuinely needed, then remove the rest. |
| `// biome-ignore lint/category/rule: reason` | Next line | A meaningful `reason` may be legitimate (rubric class 1). |
| `@ts-ignore` | Next line | Worst kind — suppresses **all** errors on the next line. Removal may surface multiple distinct errors; enumerate them before fixing. Prefer replacing with `@ts-expect-error` if one specific error remains. |
| `@ts-expect-error` | Next line | **Cheap-win detector**: if the underlying issue was already fixed, removal compiles clean (TS reports the directive as unused → just delete it). If not, the error is now explicit. **Always safe to attempt.** |
| `it.skip` / `test.skip` / `xit` / `xdescribe` | Test | Rubric class 4 (needs-investigation). Never un-skip without confirmation. |
| `tsconfig.json` `"strict": false` or disabled checks (`noImplicitAny`, `strictNullChecks`) | Project-wide | Tier 2 — outline only. Flipping these surfaces a flood of errors. |
| ESLint `rules: { "rule": "off" }` in config | Project-wide | Like a blanket disable — expand to **diagnostic count** before gating. |

## Behavior sensitivity (which rules need tests, not just lint)

Tag every JS/TS finding before delegating (see core `debt-taxonomy`):

**Behavior-sensitive** — fixing these moves/reorders/adds runtime logic; acceptance gate
**must be tests-green**, and with no test suite configured the orchestrator warns and requires
acknowledgement:
- `react-hooks/rules-of-hooks` — moving a hook out of a conditional/loop changes *when and how often it runs*. This is a structural refactor (lift state, split component, map a loop to child components), not a comment deletion — rubric class 3, behavior-sensitive.
- `react-hooks/exhaustive-deps` — adding a missing dependency can change effect timing or cause re-render loops. Never just append the dep to silence it; understand why it was omitted.
- Any suppression whose removal forces a logic change (not a type change).

**Behavior-preserving** — type-only or cosmetic; "tsc/eslint clean" is a sufficient gate:
- `@typescript-eslint/no-explicit-any`, `no-unused-vars`, unused `@ts-expect-error`, import ordering, formatting rules.

## TypeScript notes

- `@ts-expect-error` removals are the highest-value, lowest-risk findings — always enumerate them first in an audit; many are stale.
- `any` introduced to silence `no-explicit-any`: usually rubric class 2–3 (replace with a real type or `unknown` + narrowing).
- After edits, run the project's **own** lint/typecheck on the touched files only — `tsc --noEmit` for the project, or the configured `lint` script scoped to the changed paths. Capture output to a file and grep (`context-discipline`).

## Stale heuristics (grep-only, for audit `stale` scope)

Per the core skill: audit must not compile. These are grep-only signals that a suppression
is a *candidate* for removal; `/keymaker:open` proves it via the twin.

| Mechanism | Grep-only stale heuristic |
|---|---|
| `@ts-expect-error` | **Always a candidate** — TS reports unused directives as errors, so removal is always safe to attempt. Highest-value, lowest-risk. Rank these first. |
| `@ts-ignore` | Candidate when the next line has no obvious type-error shape (no member access, no call, no JSX). Riskier than `@ts-expect-error` because removal does not self-report when stale; `/keymaker:open` must verify via `tsc --noEmit`. |
| `// eslint-disable-next-line <rule>` | Candidate when the next line no longer contains the rule's syntactic trigger — e.g. `no-explicit-any` over a line with no `any`, `no-unused-vars` over a line whose identifier is referenced elsewhere in the file. |
| `// eslint-disable <rule>` … `// eslint-enable` | Candidate when the surrounded block has no occurrence of the rule's syntactic trigger. |
| `/* eslint-disable */` (no rule, file scope) | Not a stale candidate from grep alone — covers every rule; defer to a real lint pass via `/keymaker:open`. |
| `// biome-ignore lint/category/rule: reason` | Candidate when the next line no longer contains the rule's syntactic trigger. A meaningful `reason` may still be legitimate (rubric class 1) — flag, do not assume. |
| `it.skip` / `test.skip` / `xit` / `xdescribe` | Never a stale candidate — skipped tests are rubric class 4 (needs-investigation), not removable without confirmation. |

## Package-manager variance

Detect by lockfile, then update `package.json` **and commit the matching lockfile**:

| Lockfile | Manager | Install command | Notes |
|---|---|---|---|
| `package-lock.json` | npm | `npm install` | |
| `pnpm-lock.yaml` | pnpm | `pnpm install` | Check `pnpm-workspace.yaml` for monorepo version pins |
| `yarn.lock` | yarn | `yarn install` | |

- `peerDependencies` conflicts → report and stop; never silently pass `--legacy-peer-deps` or `--force`.
- In a monorepo, a version may be pinned at the workspace root — update there, not in the leaf package.

## Upgrade-tier examples (JS/TS)

| Upgrade | Tier | Notes |
|---|---|---|
| `lodash 4.17.19 → 4.17.21` | 1 | Patch |
| `react + react-dom + @types/react` (minor) | 1 | Coordinated same-lane bump |
| `@types/*` bumps | 1 | Type-only |
| **React major** (`17 → 18`) | **2 — outline only** | Concurrent rendering, root API, effect timing changes |
| **Node major** (`18 → 22`) | 2 — outline only | Runtime-wide |
| CommonJS → ESM | 2 — outline only | Module-system migration |
| `webpack → vite`, `tsc → swc` | 2 — outline only | Toolchain replacement |
