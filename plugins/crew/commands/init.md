---
description: Detect the project's crew configuration and write it to CLAUDE.md (idempotent — re-run to reconcile new settings)
---

Set up (or reconcile) the **crew configuration** the orchestrator reads. This command
detects the project's build/test/lint commands, base branch, and frontend mode, shows you
what it found, and writes the agreed values to the **Crew configuration** block in
`CLAUDE.md`. It is **idempotent**: the first run bootstraps the block; a re-run reconciles it,
adding any slots introduced by a newer plugin version **without overwriting values you've
already set**.

Do the detection read-only first, then confirm with the user before writing anything.

## 1. Canonical configuration slots

These are the slots the crew reads. This list is the source of truth for what "complete"
means — reconcile fills any of these that are missing:

- **Frontend mode** — `headless` or `server-rendered`. Optional/pin-only; leave unset to let
  `morpheus` resolve it per project.
- **Backend test command** — e.g. `dotnet test`.
- **Frontend test command** — the e2e suite (e.g. `npx playwright test`).
- **Backend build command** — e.g. `dotnet build`.
- **Frontend build command** — e.g. `tsc --noEmit` / `vite build`.
- **Backend lint command** — verify mode (e.g. `dotnet format --verify-no-changes`, plus
  `dotnet csharpier check` when a `.csharpierrc` is present).
- **Frontend lint command** — the project's lint script in report/verify mode (`eslint`,
  `biome check`, `stylelint`, …).
- **Base branch** — the branch `morpheus` branches off (`main` / `develop` / trunk).
- **Branch naming** — convention for feature branches (e.g. `feature/<ticket>-<slug>`).
- **Run/dev URL** — the local dev URL, if the project serves one.
- **Notable conventions** — short free-text notes for the crew.

## 2. Detect (read-only)

Inspect the repo and propose a value for each slot. Cite where each came from so the user can
trust or correct it; never invent a command you can't see configured.

- **Backend (.NET):** a `*.sln`/`*.csproj` implies build `dotnet build`, test `dotnet test`,
  lint `dotnet format --verify-no-changes` (add `dotnet csharpier check` if a `.csharpierrc`
  exists).
- **Frontend (Node):** read `package.json` `scripts` — map `build`/`typecheck` → frontend
  build, `test`/`e2e`/a Playwright config → frontend test, `lint` → frontend lint. Use the
  scripts that exist; don't assume an `npx` download.
- **Base branch:** the remote's default (`git symbolic-ref refs/remotes/origin/HEAD`), falling
  back to an existing `main`/`develop`. If ambiguous, ask.
- **Frontend mode:** infer from the stack — a React/Vite/Next SPA build → `headless`; Razor
  `.cshtml` views without an SPA bundle → `server-rendered`. If it's genuinely mixed or
  unclear, leave unset and note that `morpheus` will resolve it, or ask.
- **Run/dev URL, branch naming, notable conventions:** propose from dev scripts /
  `launchSettings.json` / existing branch names where visible; otherwise leave unset.

When detection comes up empty, pick the placeholder by slot type — never write a value that
makes the config unusable:

- **Tooling slots** (backend/frontend test, build, and lint commands; run/dev URL): if the
  project genuinely has no such tooling, use plain none.
- **Project-identity slots** (base branch, branch naming, frontend mode): never none — a base
  branch always exists, so none would be wrong. Leave these *unset* so `morpheus` resolves or
  asks (for base branch, prefer asking — see above).

Match the block's existing placeholder wording exactly — italic *unset* and plain none, never
backticked — so reconcile reliably recognizes them later. Don't guess to fill a blank.

## 3. Confirm with the user

Show the detected values as a table (slot · proposed value · source), and let the user
confirm or edit before anything is written. Then ask **where to write it**:

- **`CLAUDE.md` crew-configuration block** *(recommended)* — committed and shared with the
  repo, reviewable in PRs, and the source `morpheus` and the `crew:*` commands already read
  first. This command writes here.
- **Keep it local / uncommitted** — don't write the block; `morpheus` already resolves any
  unset slot per session (its memory → ask) and remembers your answer locally. Choose this to
  avoid committing crew config to the repo. Report the detected values for reference and stop.

## 4. Write / reconcile `CLAUDE.md`

When the user picks the committed destination:

- **No block yet** → add a `## Crew configuration` section containing every slot from §1 with
  the confirmed values.
- **Block exists (reconcile)** → for each slot in §1: add it if missing; fill it if present but
  still a placeholder (*unset* / none) and a value was detected and confirmed. **Never
  overwrite a slot the user has set to a real value** — show those as "kept" rather than
  changing them. Preserve the surrounding prose and slot wording.

Before writing, show the exact set of additions/changes (a short diff of slots) and apply only
after the user confirms. After writing, report what was added, filled, and kept unchanged, and
note that re-running reconciles again after future plugin updates.
