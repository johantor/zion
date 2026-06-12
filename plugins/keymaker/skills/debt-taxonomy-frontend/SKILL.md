---
name: debt-taxonomy-frontend
description: TypeScript / JavaScript / frontend suppression mechanisms, safe-removal recipes, npm/pnpm/yarn package-manager variance, and upgrade-tier examples for the keymaker crew. Apply when stack detection (debt-taxonomy) finds a JS/TS project. Load into keymaker and twin.
---

# Debt taxonomy — TypeScript / JavaScript / frontend

Apply this skill when `debt-taxonomy` stack detection finds a JS/TS project (`package.json`,
`tsconfig.json`, `.eslintrc*`, `biome.json`). Classification rubric and blast-radius gate are
in the core `debt-taxonomy` skill.

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

## TypeScript notes

- `@ts-expect-error` removals are the highest-value, lowest-risk findings — always enumerate them first in an audit; many are stale.
- `any` introduced to silence `no-explicit-any`: usually rubric class 2–3 (replace with a real type or `unknown` + narrowing).
- After edits, run the project's **own** lint/typecheck on the touched files only — `tsc --noEmit` for the project, or the configured `lint` script scoped to the changed paths. Capture output to a file and grep (`context-discipline`).

## Package-manager variance

Detect by lockfile, then update `package.json` **and commit the matching lockfile**:

| Lockfile | Manager | Install command | Notes |
|---|---|---|---|
| `package-lock.json` | npm | `npm install` | |
| `pnpm-lock.yaml` | pnpm | `pnpm install` | Check `pnpm-workspace.yaml` for monorepo version pins |
| `yarn.lock` | yarn | `yarn install` | |

- `peerDependencies` conflicts → report and stop; never silently pass `--legacy-peer-deps` or `--force`.
- In a monorepo, a version may be pinned at the workspace root — update there, not in the leaf package.

## Upgrade-tier examples (frontend)

| Upgrade | Tier | Notes |
|---|---|---|
| `lodash 4.17.19 → 4.17.21` | 1 | Patch |
| `react + react-dom + @types/react` (minor) | 1 | Coordinated same-lane bump |
| `@types/*` bumps | 1 | Type-only |
| **React major** (`17 → 18`) | **2 — outline only** | Concurrent rendering, root API, effect timing changes |
| **Node major** (`18 → 22`) | 2 — outline only | Runtime-wide |
| CommonJS → ESM | 2 — outline only | Module-system migration |
| `webpack → vite`, `tsc → swc` | 2 — outline only | Toolchain replacement |
