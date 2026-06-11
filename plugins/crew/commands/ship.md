---
description: Run the diff-aware pre-PR ship gate and return a go/no-go summary
---

Run the pre-PR ship gate and return a single **GO** / **NO-GO** summary.

You own git, so **scope the gate to the diff**: determine which lanes the branch
actually changed, then run only the gates that change can affect. Don't run a full
e2e or backend suite for a lane nothing touched.

## 1. Determine changed lanes

Compute the files changed on this branch vs. the resolved base branch
(`git diff --name-only <base>...HEAD`, plus any staged/unstaged changes), then
classify each path — same split the lane guard uses:

- **Backend lane** — `*.cs`, `*.csproj` (and `*.cshtml`: it carries server-side logic).
- **Frontend lane** — `*.ts`, `*.tsx`, `*.jsx`, `*.js`, `*.mjs`, `*.scss`, `*.css`, `*.html`
  (and `*.cshtml` in server-rendered mode, where trinity owns the markup).
- **Neither** — docs, config, plugin files, etc.

A diff can touch both lanes; `.cshtml` counts toward both. If `$ARGUMENTS` is `full`,
skip classification and run every gate regardless of the diff.

## 2. Run only the affected gates

Lane-scoped and **independent** — a gate whose lane has no changes is **skipped**, not run:

1. **Backend tests** — *only if the backend lane changed*: delegate to `crew:oracle`; run the suite, surface failures with file:line.
2. **Build** — *only if the backend lane changed*: run the backend build command from `CLAUDE.md`; surface compiler errors.
3. **Backend lint** — *only if the backend lane changed*: run the backend lint command from `CLAUDE.md` (verify mode — e.g. `dotnet format --verify-no-changes`, plus `dotnet csharpier check` when a `.csharpierrc` is present); surface lint/format violations.
4. **Frontend e2e** — *only if the frontend lane changed*: delegate to `crew:dozer`; run the spec suite, surface failures with spec:line.
5. **Frontend lint** — *only if the frontend lane changed*: run the frontend lint command from `CLAUDE.md`; surface lint errors.
6. **Review** — **always**: run `/crew:review` and include its `## Blocking` section.

If a gate's command is unset / `none` in `CLAUDE.md`, skip it with that note (not a failure).

## 3. Output

Every gate appears in the summary with its status — **never skip silently**:

- ✅ passed · ❌ failed · ⏭️ skipped (with reason: *lane untouched* or *no command configured*).
- **GO** — all *run* gates passed.
- **NO-GO** — list each failing gate with ❌ and the blocking items that must be resolved before merging.
