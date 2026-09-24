---
description: Run the diff-aware pre-PR review gate (code/security/design + build/test/lint) and return a go/no-go summary
---

Run the pre-PR **review gate** and return a single **GO** / **NO-GO** summary. The gate is
both the consolidated review (code quality, security, design conformance) **and** the
executable checks (build, tests, lint) — one gate, run before `/crew:pr`. Load the
`review-gate` skill with the Skill tool first: its rules govern every executable gate below,
whether `morpheus` or this command dispatches it.

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

- **Frontend lane** — its sources (`*.ts`, `*.tsx`, `*.jsx`, `*.js`, `*.mjs`, `*.scss`, `*.css`,
  `*.html`, and `*.cshtml` in server-rendered mode, where trinity owns the markup) and its
  manifests and tool configuration: `package.json` and its lockfile, `tsconfig*.json`, the
  bundler, e2e, unit-test, lint and style configs (`vite.config.*`, `next.config.*`,
  `playwright.config.*`, `cypress.config.*`, `.eslintrc*`, `biome.json`, `postcss.config.*`,
  `tailwind.config.*`, …), since a gate's own configuration decides what the build and lint do.
- **Backend lane** — every other changed file that is not documentation (`*.md` outside
  `.claude/`, `docs/**`, `.github/**`, `LICENSE`): sources, manifests, lockfiles and gate
  configuration alike. `*.cshtml` carries server-side logic, so it counts here too. When in
  doubt, backend: an extra build costs minutes, a skipped gate costs a bad merge. No list to keep
  in step with `lane-guard.sh` — the guard decides who may *edit* a file, this step only decides
  which gates *run*.
- **Both lanes** — `.claude/crew.md`: a changed gate command changes what both lanes' gates do.
- **Node is the exception.** The whole JS/TS set — `.ts`, `.tsx`, `.js`, `.jsx`, `.mjs`, `.cjs`,
  `.mts`, `.cts` — **and the manifests, lockfiles and tool configs above** belong to whichever
  lane the **Backend/Frontend lane path(s)** put them in (the same split `lane-guard.sh` falls
  back to), so `apps/api/package.json` is backend under a backend lane path; and to the backend
  alone when **Frontend stack** is `none`. Classifying by extension would skip the backend gates
  on a backend-only Node repo.
- **No view layer, no frontend gates.** When **Frontend stack** is `none` there is no frontend
  lane in any mode: the frontend build/test/lint gates never run, and `seraph` is never dispatched
  for design conformance. That holds in `full` mode too — a project with no view has nothing for
  those gates to check.
- **Neither** — the documentation set above.

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

Each handoff carries this **wait recipe** verbatim, so a command of any length ends inside the
worker's turn — a worker that ends its turn on its own background work can report late, and that
report can miss you. Start the command detached, with its exit code written to a file (the
literal `/tmp/` prefix keeps the redirects inside `bash-safety.sh`'s exempt sinks; the braces
capture every part of a compound command; `set -m` gives it its own process group, whose id goes to
`pid`):

```sh
set -m; mkdir -m 700 /tmp/gate.$$ && { ( { <command>; } >/tmp/gate.$$/log 2>&1; echo $? >/tmp/gate.$$/exit ) >/dev/null 2>&1 & echo $! >/tmp/gate.$$/pid; } && echo /tmp/gate.$$
```

Then repeat this call, with the printed path as `d` and Bash `timeout: 600000`, until it prints an
exit code instead of `running`; grep `$d/log` for the findings (a bare `cat` is refused). Never
`run_in_background`.

```sh
d=<path>; for i in $(seq 110); do [ -f "$d/exit" ] && break; sleep 5; done; head -c 8 "$d/exit" 2>/dev/null || echo running
```

Give the handoff a wall-clock budget. Still `running` past it is a **gate timeout**: stop the whole
group and confirm it is gone before you report, so nothing keeps writing build outputs.

```sh
d=<path>; p=$(head -c 16 "$d/pid"); kill -TERM -- -"$p"; for i in $(seq 60); do kill -0 -- -"$p" 2>/dev/null || break; sleep 1; done; kill -0 -- -"$p" 2>/dev/null && echo still-running || echo stopped
```

Report it with the gate's name and `$d`, never as a code failure; `still-running` goes to the user
as is. A build timeout follows `review-gate` rule 4; a hung test, e2e or lint run goes to the
user as its own timeout, not rerun as contention.

**Independent of each other is not independent of the build outputs.** Same-lane gates write the
same build location, so they run as `review-gate` rule 1 says: one at a time, or together only
under the stack skill's **Parallel gates** recipe with its conditions checked and recorded. Two
lanes writing different outputs still run concurrently.

1. **Backend tests** — *only if the backend lane changed*: delegate to `crew:oracle`; run the suite, surface failures with file:line.
2. **Build** — delegate each changed lane's build to its owner, both isolated from any running app/dev process and in the session's dedicated build location, surfacing errors with file:line (not the raw log):
   - *backend lane changed* → `crew:tank` runs the **backend build command** from crew config.
   - *frontend lane changed* → `crew:trinity` runs the **frontend build command** from crew config (e.g. `tsc --noEmit` / `vite build`).

   Each build runs as `review-gate` rules 2–4 say: one-shot and bounded, as configured with its
   warnings in the findings, contention told from a code failure. Rule 3's routing lands in the
   output as: a warning in a file this branch changed is `## Blocking`, one anywhere else a
   `## Warnings` item, so a project that already builds warning-dirty doesn't fail the gate on
   its backlog; a weakening in the **configured command itself** is `## Blocking`, naming the
   flag and pointing at `/crew:init` — run the build anyway, a compile error is still an error.
3. **Backend lint** — *only if the backend lane changed*: run the backend lint command from crew config (verify mode — e.g. `dotnet format --verify-no-changes`, plus `dotnet csharpier check` when a `.csharpierrc` is present); surface lint/format violations.
4. **Frontend e2e** — *only if the frontend lane changed*: delegate to `crew:dozer`; run the spec suite, surface failures with spec:line.
5. **Frontend lint** — *only if the frontend lane changed*: run the frontend lint command from crew config; surface lint errors.

A formatter or linter that reports **zero files checked** did not run: report that gate as ❌
failed (*zero files checked*), never as clean (a worktree under `.claude/worktrees/` can hide
the whole tree from it).

Crew config is `.claude/crew.md`; when that file is absent, `crew.md` in
`git rev-parse --git-common-dir` (the local file), then a legacy **Crew configuration** block in
`CLAUDE.md`. If a gate's command is `unset` / `none` there, skip it with that note (not a
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
