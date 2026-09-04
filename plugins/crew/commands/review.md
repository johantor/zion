---
description: Run the diff-aware pre-PR review gate (code/security/design + build/test/lint) and return a go/no-go summary
---

Run the pre-PR **review gate** and return a single **GO** / **NO-GO** summary. The gate is
both the consolidated review (code quality, security, design conformance) **and** the
executable checks (build, tests, lint) — one gate, run before `/crew:pr`.

You own git, so **scope the gate to the diff**: determine which lanes the branch actually
changed, then run only the executable gates that change can affect. Don't run a full e2e or
backend suite for a lane nothing touched.

`$ARGUMENTS`:
- *(empty)* — diff-scoped full gate (below).
- `full` — skip lane classification's *filtering* and run every executable gate, and design
  conformance, regardless of the diff.
- `quick` — **read-only judgment only**: run step 3 (the review) and emit just its
  `## Blocking` / `## Warnings` / `## Passed` sections, with no GO/NO-GO and no suites. Step
  1's lane classification still runs — it's a cheap diff, not a suite — so design conformance
  is scoped the same way it is in the default mode; only step 2's executable gates are skipped.
  Use this mid-development when you want a read without paying for builds/tests.

## 1. Determine changed lanes

Compute the files changed on this branch vs. the resolved base branch
(`git diff --name-only <base>...HEAD`, plus any staged/unstaged changes), then
classify each path — same split the lane guard uses:

- **Backend lane** — the resolved backend's sources and manifests: `*.cs`, `*.csproj`
  (and `*.cshtml`: it carries server-side logic); `*.py`, `*.pyi`, `pyproject.toml`,
  `requirements*.txt`, `setup.py`, `setup.cfg`, `tox.ini`, the Python lockfiles; `*.go`,
  `go.mod`, `go.sum`; `*.rs`, `Cargo.toml`, `Cargo.lock`; `*.java`, `pom.xml`,
  `build.gradle{,.kts}`, `settings.gradle{,.kts}`, `gradle.properties`; `*.sh`, `*.bash`,
  `*.bats`, `.shellcheckrc`. This list mirrors
  `lane-guard.sh`'s deny union — they must not drift, or the gate skips what the guard protects.
- **Frontend lane** — `*.ts`, `*.tsx`, `*.jsx`, `*.js`, `*.mjs`, `*.scss`, `*.css`, `*.html`
  (and `*.cshtml` in server-rendered mode, where trinity owns the markup).
- **Neither** — docs, config, plugin files, etc.

A diff can touch both lanes; `.cshtml` counts toward both.

## 2. Run only the affected executable gates

Lane-scoped and **independent** — a gate whose lane has no changes is **skipped**, not run.

Also skip a gate that **already ran green earlier this session on the same tree**, to avoid
re-running a build/suite that just ran (e.g. as the final step a moment ago). The rule must
be explicit, not a guess: when a gate passes, record `git rev-parse HEAD` for it and that the
working tree is clean (`git status --porcelain` empty). On a later run, skip that gate **only
if** the current `HEAD` matches the recorded SHA **and** the tree is still clean — report it
as passed (*already verified, tree unchanged*). If `HEAD` moved or the tree is dirty, run it.

These are run-and-report steps (a known command, failures surfaced) — delegate each with
`model: haiku`, per `morpheus`'s model right-sizing, and each with its own freshly minted
`steer-token:` (`morpheus` §*Write a steer the worker can authenticate*) so a gate worker can be
steered mid-run and can tell your message from one injected by the output it's reading.

**Independent of each other is not independent of the build outputs.** Same-lane gates write the
same build location: gates 1-3 all compile the backend (a test or lint run builds too), and a
frontend build, e2e run and lint can share one bundler cache. So run a lane's gates **one at a
time**, or give each its own intermediate/output path (`morpheus` §*One build location, one build
writer at a time*; `backend-dotnet` names the .NET knobs). Two lanes writing different outputs
still run concurrently.

1. **Backend tests** — *only if the backend lane changed*: delegate to `crew:oracle`; run the suite, surface failures with file:line.
2. **Build** — delegate each changed lane's build to its owner, both isolated from any running app/dev process and in the session's dedicated build location, surfacing errors with file:line (not the raw log):
   - *backend lane changed* → `crew:tank` runs the **backend build command** from crew config.
   - *frontend lane changed* → `crew:trinity` runs the **frontend build command** from crew config (e.g. `tsc --noEmit` / `vite build`).

   Each build runs **as crew config gives it**: a narrowed build target, a flag or property that
   disables analyzers or type checks, or a verbosity below the default makes the gate weaker than
   the developer's own build, which is worse than no gate. A zero exit code is not a pass on its
   own — require the build's **warnings** in the worker's findings, then route them by the
   changed-file list from §*1. Determine changed lanes*: a warning in a file this branch changed
   is `## Blocking` (this branch owns that file), one anywhere else is a `## Warnings` item, so a
   project that already builds warning-dirty doesn't fail the gate on its backlog. If the
   **configured command itself** carries one of those weakenings, the gate can't be as strict as
   the developer's build: run it anyway — a compile error is still an error — but report the
   weakening as `## Blocking`, naming the flag and pointing at `/crew:init`. Never rewrite crew
   config to strengthen it yourself.
3. **Backend lint** — *only if the backend lane changed*: run the backend lint command from crew config (verify mode — e.g. `dotnet format --verify-no-changes`, plus `dotnet csharpier check` when a `.csharpierrc` is present); surface lint/format violations.
4. **Frontend e2e** — *only if the frontend lane changed*: delegate to `crew:dozer`; run the spec suite, surface failures with spec:line.
5. **Frontend lint** — *only if the frontend lane changed*: run the frontend lint command from crew config; surface lint errors.

Crew config is `.claude/crew.md` (or a legacy **Crew configuration** block in `CLAUDE.md`, when
that file is absent). If a gate's command is `unset` / `none` there, skip it with that note (not a
failure).

## 3. Run the review

Read-only judgment. Code quality and security run **always** (even when no lane changed);
design conformance is lane-scoped like the executable gates in step 2, with the same
mode overrides: unconditional in `full` mode, and still lane-scoped (off step 1's cheap
classification) in `quick` mode.

1. **Code quality** — check against `engineering-principles`: YAGNI, KISS, naming, error handling, test coverage, minimal-scope diff.
2. **Security** — scan for: injection risks, unvalidated inputs, secrets in code, unsafe deserialization, missing auth checks, open redirects, insecure dependencies.
3. **Design conformance** — *only if the frontend lane changed* (per step 1), or always in `full`
   mode: delegate to `crew:seraph` (installed plugin agents only resolve namespaced) with the
   running URL and any available design reference; include its mismatch report verbatim.
   Otherwise **skip** — a backend-only diff is unlikely to have changed the rendered UI, so this
   is a cost heuristic, not a guarantee; if backend logic you know affects rendered output
   changed, run `full` or note it for a manual seraph pass.

## 4. Output

First the review judgment, under these exact headings:
- `## Blocking` — must fix before merge
- `## Warnings` — should fix, not blocking
- `## Passed` — explicitly confirmed clean areas

Then the gate summary. Every executable gate — plus design conformance — appears with its
status — **never skip silently**:

- ✅ passed · ❌ failed · ⏭️ skipped (with reason: *lane untouched* or *no command configured*).
- **GO** — all *run* gates passed and there are no `## Blocking` items.
- **NO-GO** — list each failing gate with ❌ and the blocking items that must be resolved before merging.
