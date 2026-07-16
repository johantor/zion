# Changelog

All notable changes to the `crew` plugin are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [3.5.1] - 2026-07-16

### Changed
- **The validator moved out of the plugin: `plugins/crew/scripts/validate-plugin.sh` →
  repo-root `scripts/validate-plugin.sh`.** It is repo tooling, not plugin behavior — it
  validates every plugin, the marketplace, and this repo's dev-time hook mirror, requires the
  marketplace monorepo layout, and never runs in an installed plugin (nothing in any agent,
  command, or hook invokes it). Installed crew trees no longer carry the inert script, and
  future validator-only changes stop being crew releases. CI and all doc references updated;
  the script itself is unchanged.

## [3.5.0] - 2026-07-16

### Added
- **Cross-plugin hook-script sync check (validate-plugin.sh §5).** A hook script filename
  shipped by more than one plugin must now stay in sync across every copy, mirroring §4's rule
  for skills (crew's copy is the reference when crew ships the file). Files with no markers
  must be byte-identical (`read-guard.sh`); files that delimit shared regions with
  `# --- BEGIN/END shared guard: <label> ---` markers (`bash-safety.sh`) may diverge outside
  the marked regions — per-plugin git policy differs — but every marked region must match
  byte-for-byte. Both `bash-safety.sh` copies now carry those markers around the
  destructive-ops, watch-command, and raw-read blocks; the mirror was previously documented
  but unenforced, so a regex fix in one copy could silently drift the other.
- **Hook wiring cross-check (validate-plugin.sh §6).** Every `command` in a plugin's
  `hooks/hooks.json` must resolve through the `"${CLAUDE_PLUGIN_ROOT}"/` prefix to a file that
  exists in that plugin, and every `hooks/*.sh` on disk must be wired by some command — an
  unwired guard script silently never runs, the same failure class §2g catches for agent
  `skills:` references. The former §5 (dev-time settings mirror) is now §7.
- **Marketplace description sync (validate-plugin.sh §2f).** A marketplace entry's
  `description` must equal its plugin manifest's (`plugin.json` is canonical); the two had
  quietly drifted for crew and keymaker.

### Changed
- **`read-guard.sh` allows bounded reads.** A `Read` carrying an explicit `limit` of at most
  2000 lines now passes regardless of file size — a bounded slice is exactly the targeted
  access `context-discipline` asks for, and the guard previously forced grep even for a
  disciplined 100-line read of a large file. Reads with no `limit`, a limit over 2000, or a
  non-numeric limit still hit the 64 KiB size block. keymaker ships the same guard
  byte-for-byte; its copy moves in lockstep (keymaker v0.7.0).
- **CI runs once per PR commit.** `validate.yml`'s `push` trigger is scoped to `main` (PR
  branches are covered by `pull_request` events, so the bare trigger ran everything twice) and
  a concurrency group cancels superseded runs. `auto-release.yml` fetches tags instead of full
  history, and the `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24` opt-in is gone — Node 24 has been the
  default Actions runtime since 2026-06-16.

## [3.4.0] - 2026-07-08

### Added
- **`/crew:loop <goal>` — the outer-loop driver (#102).** A thin main-session wrapper on the
  harness's native `/loop` in dynamic (self-paced) mode: each tick re-launches `morpheus`
  directly (the same agent `/crew:feature` runs, told a loop is driving it) so a feature that
  outlives one run's `maxTurns` finishes without the user re-asking each time. The durable `plan-<feature>.md` is the only cross-tick state — each tick
  reads it and ends the loop on the `loop-engineering` contract: success (all steps `done` +
  gate GO — never auto-push/PR), a step `blocked` on a human decision, or the iteration cap
  (`iterations: n/max`, model-enforced). An outer-loop tick runs `morpheus`'s workers in the
  **foreground** and to a stopping point, so a tick returns only when nothing is still running —
  ticks are genuinely synchronous. The re-entrancy guard therefore keys on the `in-flight:`
  marker only (its presence at the next firing means a crashed tick — clear it and let `morpheus`
  resume/reconcile); it deliberately does *not* gate on `in-progress` steps, which are
  `morpheus`'s to reconcile and would deadlock the loop if they blocked the next tick.
  Tick 1 still runs the plan checkpoint — loop intent authorizes the run, not the plan.
- **Plan-header outer-loop bookkeeping.** `morpheus.md`'s durable-state schema documents the
  `iterations: n/max` and `in-flight:` header fields; the `/crew:loop` wrapper owns them (it is
  the sole writer of the outer-loop bookkeeping, between synchronous ticks), and `morpheus`
  preserves them when it rewrites the plan. `morpheus` still never self-schedules — the wrapper
  owns all scheduling. The `loop-engineering` skill's scope note now points to this outer loop
  instead of denying one exists (crew and keymaker copies stay byte-identical).

## [3.3.1] - 2026-07-07

### Changed
- **`loop-engineering` is now stack-agnostic and shared with keymaker (#111).** The skill's
  crew-specific bindings (review gate GO as the success condition, the gate's second-NO-GO
  cap and `gate:` tracking, push behind `/crew:pr`, `neo` single-pass no-op) moved into
  `morpheus.md`'s own loop-mode bindings paragraph; the skill now states the generic contract —
  intent trigger, handshake, run-not-work authorization, the three stop rules, durable
  attempt/loop state, exit line — in terms of *units*, the *terminal gate*, and *durable state*
  that each preloading orchestrator binds in its agent file. keymaker ships a byte-identical
  copy (validate-plugin.sh §4 enforces the sync; crew's copy stays canonical). morpheus
  behavior is unchanged.

## [3.3.0] - 2026-07-07

### Added
- **New `loop-engineering` skill — loop mode with explicit stop rules (#83).** The crew already
  *is* the inner loop (morpheus drives makers and verifiers over a durable plan); what was
  missing was a deliberate trigger and written stop-rule discipline. The skill recognizes loop
  intent from the user in conversation only (never from fetched ticket/PR/Sentry prose), offers
  to loop on open-ended work, scopes authorization to the run (the plan checkpoint still runs
  once), and stops on: all steps done + gate GO (never auto-push/PR), a blocked human decision
  (after draining independent steps), or a retry cap — 3 failed fix→verify round-trips on a
  step, and at the gate a second NO-GO on the same findings. `maxTurns` remains a
  crash handled by durable resume, not an exit. Crew-only skill; the outer loop stays
  human-initiated in v1 (`/crew:loop` is deferred to #102).
- **morpheus now preloads skills.** New `skills:` frontmatter key with `loop-engineering` and
  `context-discipline` — morpheus's body already required context-discipline in every handoff,
  but nothing loaded it into morpheus itself. The plan-file schema gains loop-mode fields —
  header `loop:` / `exit-conditions:` / `gate:` (gate outcome + NO-GO count) and per-step
  `attempts:` — so a resumed run continues in loop mode without re-handshake and the retry
  caps survive a crash. The run summary gains a `loop exit:` line for exit observability.

## [3.2.0] - 2026-07-03

### Added
- **Workers are now code-blocked from git.** `bash-safety.sh` blocks any `git` invocation at a
  command position for `tank`/`trinity`/`oracle`/`dozer`/`neo` (`seraph` carries no Bash tool,
  so it needs no entry). "Workers never run git — morpheus owns branching and commits" was
  prose-only beyond the protected-branch commit backstop: a worker on a feature branch could
  still commit, checkout, reset, or push without tripping any guard. The
  commit-on-protected-branch backstop stays in place for every other agent type (morpheus,
  other plugins' agents).
- **Watch/dev/serve commands are blocked in agent sessions.** `dotnet watch`,
  `npm|pnpm|yarn|bun [run] dev|start|serve|watch`, bare `vite` (`vite build` stays allowed),
  `next`/`nuxt dev`, `ng serve`, `nodemon`, `webpack serve`, and the bare `--watch` flag
  (`--watch=false` stays allowed) never terminate — an agent turn that launches one hangs until
  its maxTurns/timeout. This enforces morpheus's "One-shot build, bounded" rule in code. Scoped
  via `agent_type`, so the user's own session can still run a dev server.

## [3.1.7] - 2026-07-02

### Changed
- **`validate-plugin.sh` now enforces that `.claude/settings.json` mirrors
  `plugins/crew/hooks/hooks.json`.** This repo wires its four crew guards
  twice — once for the installed plugin (`hooks/hooks.json`, resolved via
  `CLAUDE_PLUGIN_ROOT`) and once for developing in this repo without the
  plugin installed (`.claude/settings.json`, resolved via
  `CLAUDE_PROJECT_DIR`). The two had to be kept in sync by hand with nothing
  catching drift; a new check (§5) compares each hook's event, matcher,
  script, and timeout across both files (normalizing away the root-variable
  difference) and fails CI on any mismatch. `AGENTS.md` now also explains why
  both wirings exist and that installing the plugin while developing in this
  repo isn't a supported setup (every guard would run twice).

## [3.1.6] - 2026-07-02

### Changed
- **`validate-plugin.sh`'s skill-drift check is now generic by skill name, not hardcoded to
  crew.** It used to only iterate `plugins/crew/skills/*/` and compare each against same-named
  skills elsewhere — so it would never catch a duplicate skill shared between two *non-crew*
  plugins. It now groups every `SKILL.md` across all plugins by its directory basename and
  compares every plugin shipping that name, so any future duplication is caught regardless of
  whether crew is a party to it. When crew does ship the skill, its copy remains the reference
  (crew is the documented canonical source), matching the existing behavior for today's two
  pairs (`engineering-principles`, `context-discipline`) exactly. `AGENTS.md` documents the
  convention generically and calls out both pairs explicitly (previously only
  `engineering-principles` was documented in prose; `context-discipline`'s sync requirement was
  enforced but unmentioned).

## [3.1.5] - 2026-07-02

### Changed
- **`morpheus.md` trimmed from ~27 KB to ~22 KB (~19%), by consolidating repeated content.**
  The resolution ladder ("`CLAUDE.md` pin → local memory → detect/ask, then remember, then
  pass in the delegation") was restated nearly verbatim across five separate sections —
  frontend mode, backend/frontend stack, frontend e2e tool, frontend unit test tool, and base
  branch/branch-naming. It's now stated once in a new **Resolving crew configuration** section,
  with a compact table (slot · values · detection markers · consuming worker/skill) replacing
  the five prose sections. No slot's values, detection markers, confirm-vs-assume rules, or
  "pass the resolved value in every delegation" requirement were dropped — the anti-drift
  rule's plan-schema restatement was also trimmed to a pointer at *The plan file is durable
  state*, and several other verbose sections were tightened without losing distinct rules.
  This is loaded as `morpheus`'s system prompt on every orchestration session (up to
  `maxTurns: 80`), so the savings apply per session, not once.

## [3.1.4] - 2026-07-02

### Changed
- **`/crew:review`'s design-conformance check is now scoped to the frontend
  lane**, same as the executable build/test/lint gates in step 2. It used to
  delegate to `crew:seraph` unconditionally, spawning a design-conformance
  review (and its browser/Figma MCP traffic) even for a backend-only diff,
  where it's unlikely there's a rendered-UI change to compare — a cost
  heuristic, not a guarantee (`full` mode still runs it unconditionally).
  Skipped runs are reported in the gate summary with reason *lane untouched*,
  consistent with the other gates.

## [3.1.3] - 2026-07-02

### Changed
- **`format.sh`'s per-edit dotnet formatting is lighter weight.** It used to run
  full `dotnet format --include "$path"` (whitespace + style + **analyzer**
  fixes) on every edited `.cs` file — evaluating analyzers against the
  containing project, which can take 10-60s on real solutions. That full check
  already runs once, at the review gate (`dotnet format --verify-no-changes`),
  so paying it again per edit added little. Per edit now: CSharpier when the
  solution configures it (`.csharpierrc`) — it formats a single file directly
  without evaluating the project — otherwise `dotnet format whitespace`, which
  skips analyzer evaluation.
- **`eslint --fix` runs with `--cache`** in the web formatting lane, so repeated
  edits in the same area reuse ESLint's cache instead of re-linting cold.

## [3.1.2] - 2026-07-02

### Changed
- **`lane-guard.sh` and `bash-safety.sh` parse their hook payload in one `jq`
  call instead of three.** Both hooks separately parsed for payload validity,
  `agent_type`, and the relevant field (`path` / `command`) — three process
  spawns on every matching tool call. Each field is now extracted in a single
  `jq` call (whose own exit status doubles as the validity check), joined with
  a record-separator byte and split in the shell.
- **`lane-guard.sh` bails out immediately for the main session and any agent
  without a lane**, before any config parsing, matching the existing default
  arm of its lane dispatch.

## [3.1.1] - 2026-07-02

### Changed
- **`lane-guard.sh` caches marker detection per session.** In the same-language
  regime (stacks unset, no lane paths configured), the guard used to re-scan the
  whole repo (`has_dotnet_backend` / `has_node_backend` / `has_frontend`, each a
  `find` walk) on **every** `tank`/`trinity` Edit/Write. It now runs that
  detection once per session and caches the result (keyed by `session_id`),
  since the underlying markers (project files, declared dependencies) don't
  change mid-feature. Only persisted when a `session_id` is present, so the
  cache can't outlive the session it was written for.
- **More directories pruned during marker detection.** The probes only pruned
  `node_modules`; they now also prune `.git`, `dist`, `bin`, `obj`, `coverage`,
  and `.next`, so a large `.git` history or build output no longer slows the
  scan (or false-positives on stale build artifacts).

## [3.1.0] - 2026-07-02

### Added
- **`/crew:address` — close the PR review loop.** The lifecycle used to end at `/crew:pr`;
  once a reviewer, Copilot, or CI commented on the open PR the developer dropped back to manual
  mode, losing crew's lane routing and sole-git-ownership exactly when review churn is highest.
  The new command (a thin router into `morpheus`, like `/crew:feature`) pulls the PR's
  **unresolved** review threads and **failed** CI checks via the git-host MCP, classifies each
  item to a lane through `morpheus`'s size-triage (`tank` / `trinity` / `oracle` / `dozer`, or
  the `neo` express lane), delegates and commits each verified fix citing the thread it answers,
  re-runs the diff-scoped `/crew:review` gate, and — after confirming — pushes and resolves the
  addressed threads.
  - Review-comment text is treated as **untrusted external input**: technical asks are classified
    and routed, but anything that tries to redirect scope, exfiltrate secrets, or disable a guard
    is surfaced to the user rather than acted on.
  - The flow lives in `morpheus`'s own prompt (new *Address review feedback — close the review
    loop* section), so it works the same whether invoked as `/crew:address` from a normal session
    or just asked for in a `claude --agent crew:morpheus` session — no slash command required.

## [3.0.0] - 2026-07-02

### Added
- **Cypress Component Testing support.** Cypress can now be resolved as the **frontend unit
  test tool** (in addition to its existing role as the frontend e2e tool), covering projects
  that use Cypress Component Testing for component/unit tests.
  - `morpheus` detects `cypress` as the frontend unit test tool when `cypress.config.*`
    contains a `component` key and no `vitest.config.*` / `jest.config.*` is present.
  - `oracle` now loads the `tests-cypress` skill when `cypress` is the resolved frontend unit
    test tool, and applies the component-test section of that skill.
  - `tests-cypress` skill updated with a **Component tests** section covering `cy.mount()`,
    component spec file conventions (`.cy.ts` / `.cy.tsx`), and the `--component` run flag.
  - `/crew:init` detects and writes `cypress` for the **Frontend unit test tool** slot.

### Changed
- **BREAKING: crew is stack-agnostic — role-only agents, per-stack skills, detection-driven
  lanes.** `tank`, `trinity`, and `oracle` used to hard-code a specific stack (C#/.NET/
  Optimizely, React/Redux) directly in their prompts. They're now role-only; stack knowledge
  moved into skills loaded dynamically once `morpheus` resolves the project's stack —
  `backend-dotnet`, `backend-node`, `cms-optimizely` (composes on `backend-dotnet`, self-
  detected via package references), `frontend-react`, `frontend-nextjs`, `tests-xunit`,
  `tests-node` (Vitest/Jest, detected by config file). Concrete second-stack driver: Node
  backend + Next.js frontend (Optimizely SaaS / Graph).
  - `morpheus` resolves **Backend stack** / **Frontend stack** the same way it already
    resolves frontend mode (`CLAUDE.md` pin → memory → detect-and-ask), names the resolved
    stack in every implementation and test delegation, and never delegates without one
    resolved. `/crew:init` detects and writes both new slots.
  - `lane-guard.sh` gets a second lane regime: directory-based paths (**Backend lane
    path(s)** / **Frontend lane path(s)**, new `CLAUDE.md` slots) for same-language stack
    pairs (e.g. Node+Next.js) where a bare file extension can't tell `tank`'s and
    `trinity`'s files apart. Falls back to the existing extension-based globs otherwise. A
    Node backend with no lane paths configured fails closed rather than guessing. A Next.js
    route handler is exempted from `tank`'s deny / added to `trinity`'s deny, since — unlike
    Razor's genuinely bidirectional markup/logic split — route-handler ownership is
    single-owner (tank's, by concern) even though the file lives in the frontend tree.
  - `format.sh` now routes by the edited file's **extension** (restricted to a known set of
    web extensions) instead of a fixed `agent_type → lane` table, so a Node-backend file
    `tank` edits still gets Biome/Prettier/ESLint, a `.cs`/`.csproj` file gets dotnet/
    CSharpier regardless of which agent produced it, and an unrelated extension (e.g.
    `.cshtml`) is skipped cleanly instead of triggering a mismatched formatter.
  - `frontend-server-rendered` reframed from Razor-only to a shared-principles section plus
    per-template-language subsections (Razor, Blade) — Next.js/RSC is deliberately not one
    of them, since Next.js is categorically `headless` in crew's mode vocabulary even though
    it server-renders; RSC conventions live in `frontend-nextjs` instead.
  - `tank`, `trinity`, and `oracle` gain explicit `Skill` tool access (a pre-existing gap:
    trinity's frontend-mode skill loading used "via the Skill tool" without it since #19).
  - Why a major bump: agent descriptions and `lane-guard.sh`'s enforcement semantics change
    — a project relying on the old fixed `tank`=.NET/`trinity`=React assumption should
    re-check its `CLAUDE.md` crew configuration after upgrading (`/crew:init` reconciles it).
  - `dozer` is now also role-only and e2e-tool-agnostic: tool knowledge moved to per-tool
    skills `tests-cypress` (Cypress conventions, extracted from `dozer`'s implicit knowledge)
    and `tests-playwright` (new, Playwright conventions). `morpheus` resolves the **Frontend
    e2e tool** (`cypress` or `playwright`) the same way it resolves the backend/frontend stack,
    names it in every `dozer` delegation, and `/crew:init` detects and writes the new slot.
  - `oracle` is extended from backend-only to all unit test authoring: when `morpheus` also
    resolves a **Frontend unit test tool** (`vitest` or `jest`), it passes it in the `oracle`
    delegation so oracle additionally loads the matching skill (`tests-vitest`) and covers
    frontend component tests. A project can therefore use multiple test tools simultaneously
    (e.g. Playwright e2e + Vitest component tests) — `dozer` handles e2e, `oracle` handles
    unit/component. `/crew:init` detects and writes the new slot. `lane-guard.sh` broadens
    oracle's allowlist to include co-located component test file patterns (`**/*.test.*`,
    `**/*.spec.*`, `**/__tests__/**`). (Closes #82.)
  - `seraph` is unchanged (already tool-neutral via whichever browser-automation MCP is
    configured). keymaker is unaffected (already stack-agnostic by its own design). (Closes
    #46.)

## [2.10.0] - 2026-07-02

### Added
- **`morpheus` right-sizes the process by task size, with a new `neo` express-lane generalist.**
  Small tasks (a typo, a rename, an obvious one-liner, a small localized bug) used to pay the same
  heavyweight process as a full feature — a plan file, the plan checkpoint, lane specialists, and
  the full review gate — which made a one-line fix slow. `morpheus` now triages by size: small,
  low-risk work takes an **express lane** — it delegates to the new `neo` agent (an all-lane
  generalist), skips the plan/checkpoint/full-gate, runs a quick read-only self-review
  (`/crew:review quick`) plus any single directly-relevant test, and commits. Features and anything
  risky, multi-lane, or needing new tests still take the full flow through the specialists, and
  `morpheus` escalates express → full the moment a task proves bigger. `morpheus` stays the sole
  git owner and never writes production code itself — `neo` makes the change, `morpheus` reviews it,
  preserving the maker↔verifier split. `neo` holds the same `engineering-principles` bar as the
  specialists (the express lane is faster, not sloppier), never runs git, and reports back to
  escalate rather than plowing ahead when a task exceeds the express lane. The `lane-guard` hook
  grants `neo` all lanes by design; `format` picks .NET or web formatting by the edited file's
  extension.

## [2.9.0] - 2026-07-02

### Added
- **Fix-verify loops rerun only the affected tests, not the full suite.** Previously, once
  `oracle`/`dozer` reported failures and `morpheus` routed a fix back to the implementer,
  re-confirming the fix meant rerunning the *entire* backend/e2e suite again — even though the
  full suite is already established as the final review gate's job, run once when the work
  queue is drained. `oracle` and `dozer` now re-run only the specific test(s)/spec(s) that were
  previously failing when asked to confirm a fix, and `morpheus` names those failing test(s) in
  the re-delegation so the worker has something to target instead of defaulting to a full run.

## [2.8.1] - 2026-07-02

### Changed
- **Trim `/crew:feature` and the review gate for token cost, behavior-neutral.**
  `commands/feature.md` restated `morpheus`'s own durable-resume protocol, plan schema,
  checkpoint, and run-summary behavior in full on every invocation — all of it already lives
  unconditionally in `agents/morpheus.md`'s system prompt, so the restatement was pure token
  cost paid per call. It now points back to `morpheus`'s own standard flow instead. Also added
  `model: haiku` to the review gate's run-and-report delegations (`crew:oracle` tests,
  `crew:tank`/`crew:trinity` build, `crew:dozer` e2e) — `morpheus`'s own "Right-size the model
  per delegation" guidance already named these as haiku-eligible, but `commands/review.md`
  never applied it.

## [2.8.0] - 2026-06-16

### Added
- **Build gate handles contention with a running app/dev process.** When a dev server, watcher, or
  running app holds locks on build outputs, a delegated build could fail (`MSB3027`/`MSB3026`,
  "being used by another process", `EBUSY`/locked `bin`/`obj`/`dist`) or hang forever (a worker
  accidentally running a watch/dev command). The build gate now requires a **one-shot** build
  command (never `dotnet watch` / `npm run dev` / `vite` / `tsc --watch`) with a wall-clock timeout,
  and `morpheus` treats a lock/in-use error or timeout as **environmental, not a code failure** —
  it reports that a running process is likely locking the outputs and asks the user to stop the
  dev server/app and retry,
  instead of wastefully routing the "failure" back to the implementer. `tank` and `trinity` carry
  the same one-shot rule and lock-error recognition in their build instructions.

## [2.7.1] - 2026-06-16

### Fixed
- **Anti-drift rule 1's schema list now includes `worker`.** The 2.7.0 run-summary change added
  `worker` to the per-step plan schema but left rule 1's referenced field list at
  `id`/`status`/`depends-on`/`acceptance`/`evidence`, making `morpheus`'s own prompt internally
  inconsistent about which keys to maintain. Added `worker` to the list. Also tightened a changelog
  sentence so `/recap` reads as the command, not a bare noun.

## [2.7.0] - 2026-06-16

### Added
- **`morpheus` emits a run summary — observability for a completed feature.** `morpheus` now
  records `worker` per step in the plan file and emits a concise per-step table — **Step · Worker ·
  Outcome · Evidence** (commit SHA) — at the end of a feature and on request, plus a one-line
  done/blocked tally. Sourced from the plan file's parseable status (not a log dump), it survives a
  resume (when the live agent panel for earlier steps is gone) and deliberately doesn't restate the
  commit list or prose retrospective that Claude Code's `/recap` already covers — it's the
  per-worker delegation view that `/recap` can't see. (Closes #64.)

## [2.6.1] - 2026-06-16

### Changed
- **`morpheus.md` trimmed for token cost (behavior-neutral).** `morpheus.md` is the always-loaded
  system prompt in a `claude --agent crew:morpheus` session, so its size is a per-turn cost. The
  "Standard flow" no longer restates the dedicated sections that follow it (it now names each phase
  and points to them), `<plan-dir>` is defined once instead of in three places, and the build-gate
  wording is tightened — ~4% fewer words with no rule added, removed, or changed.

## [2.6.0] - 2026-06-16

### Added
- **Crew runs are resumable from the plan file.** A crashed or context-reset session used to
  mean re-explaining the feature, even though `<plan-dir>/plan-<feature>.md` already recorded the
  steps. The plan file is now durable state with a parseable schema — a header (`feature:`,
  `base-branch:`, `feature-branch:`) plus per-step `id:` / `status:` (`pending` | `in-progress` |
  `done` | `blocked`) / `depends-on:` / `acceptance:` / `evidence:` (commit SHA) — and `morpheus`
  follows a **resume protocol** on (re)start: if a matching plan exists it checks out the feature
  branch, reconciles each step's status against git (a `done` step must map to its `evidence`
  commit; an unconfirmed `in-progress` step is re-verified and reset to `pending` if its
  acceptance isn't met), and picks up the first unblocked step — without asking the user to
  re-explain. `agents/morpheus.md` defines the schema and protocol; `commands/feature.md` enters
  it (resume an existing plan instead of re-planning). Only a committed step is ever `done`.

## [2.5.0] - 2026-06-16

### Added
- **Configurable per-repo plan location.** A new `Plan directory` crew-config slot lets a repo
  choose where `morpheus` writes `plan-<feature>.md` — e.g. a committed `docs/plans/` — instead
  of always `.claude/`. `morpheus` resolves it the usual way (`CLAUDE.md` crew configuration →
  local memory → the `.claude/` fallback) once per project and reads/writes plans there;
  `commands/feature.md` and `commands/pr.md` reference the resolved `<plan-dir>` rather than a
  literal `.claude/` path. `/crew:init` adds the slot to its canonical catalog and only proposes
  a value when the repo has an obvious plans convention, otherwise leaving it *unset* so the
  `.claude/` fallback applies. Default behavior is unchanged for repos that don't set it.

## [2.4.0] - 2026-06-16

### Added
- **Plan checkpoint — `morpheus` confirms the plan before building.** After writing
  `.claude/plan-<feature>.md`, `morpheus` now presents the plan (scope, ordered steps with
  acceptance criteria, base branch, frontend mode, assumptions) and waits for the user's
  explicit go-ahead **before** creating the feature branch or delegating any step — background
  steps included. It's a single gate, not a prompt per step: a one-step task is a one-word
  approval, and a standing "just build it" (in the request or a remembered preference) is
  honored as the go-ahead. Corrections are folded back into the plan and re-presented as a
  delta. `plugins/crew/commands/feature.md` carries the same checkpoint step. Catches a
  misread task at the cheapest possible point — before any worker time or commits are spent.

## [2.3.0] - 2026-06-16

### Added
- **`/crew:init` — detect and write the crew configuration.** A new command that inspects the
  project (.NET / Node tooling, git default branch, frontend stack) and proposes values for
  every crew-config slot — build/test/lint commands, base branch, branch naming, frontend
  mode, run URL — then, after the user confirms, writes them to the **Crew configuration**
  block in `CLAUDE.md` (the source `morpheus` and the `crew:*` commands already read first).
  It's **idempotent**: the first run bootstraps the block; a re-run reconciles it, adding slots
  introduced by a newer plugin version and filling placeholders **without overwriting values
  the user has already set**. If the user prefers not to commit config, it reports the detected
  values and leaves resolution to `morpheus`'s existing per-session memory.
- **`morpheus` nudges toward `/crew:init` when config is missing.** When a slot it needs is
  absent from `CLAUDE.md`, `morpheus` resolves it as before (memory → ask) and adds a single
  one-line suggestion to run `/crew:init` to persist and reconcile the configuration. It never
  rewrites `CLAUDE.md` config itself mid-feature.

## [2.2.1] - 2026-06-16

### Fixed
- **`morpheus` no longer freezes the conversation while a worker runs.** The
  "delegate in the background" guidance was soft, and the dependency-ordering rule pulled
  `morpheus` toward running a worker in the *foreground* whenever the next step needed its
  output — freezing the whole turn for the worker's entire run (often minutes) and queuing the
  user's messages unheard. `plugins/crew/agents/morpheus.md` now makes `run_in_background: true` the hard
  default for every worker delegation and spells out that backgrounding is not abandoning and
  waiting is not blocking: for a dependency, background the worker, **end the turn**, and
  dispatch the dependent step on the completion notification — never hold the turn open just to
  wait.

## [2.2.0] - 2026-06-12

### Added
- **Validator verifies each agent's `skills:` list resolves.** `plugins/crew/scripts/validate-plugin.sh`
  now parses the YAML frontmatter of every `plugins/*/agents/*.md` file and verifies each entry in
  its `skills:` list resolves to some `plugins/*/skills/<name>/SKILL.md` in the repo (unqualified,
  per existing convention). A typo here previously failed silently at runtime — the skill just
  didn't load and the agent guessed. CI now fails with a clear message:
  `FAIL: plugins/<plugin>/agents/<agent>.md skills -> <name> does not resolve to any plugins/*/skills/<name>/SKILL.md`.

## [2.1.1] - 2026-06-12

### Fixed
- **MCP README no longer conflates a server's config key with its tool namespace.** The
  allowlist note listed `mcp__`-prefixed namespaces under "name your server one of these,"
  which could lead users to name the server `mcp__playwright`. It now distinguishes the *key*
  you set in `.mcp.json` (e.g. `playwright`) from the `mcp__<key>` namespace agents allowlist,
  and lists the expected keys without the prefix.

## [2.1.0] - 2026-06-12

### Added
- **More first-class MCP servers across the crew.** Agents now allowlist additional optional
  MCP servers and use them when present (degrading gracefully when absent):
  - **Browser:** `mcp__chrome-devtools` on `trinity`/`seraph` alongside `mcp__playwright` —
    either browser MCP works zero-config; Chrome DevTools is Chrome-only but adds
    performance/Lighthouse and console/network inspection.
  - **Library & framework docs:** `mcp__context7` on `tank`/`trinity`, for current,
    version-specific API docs instead of coding from memory.
  - **Issue tracking (ticket-in):** `mcp__linear` and `mcp__atlassian` on `morpheus`, to pull
    the source ticket at planning.
  - **Database:** `mcp__mssql` and `mcp__postgres` on `tank`/`oracle`, for schema-aware
    data-access work and integration test data.
  - **Error monitoring:** `mcp__sentry` on `morpheus`, to pull stack/breadcrumb context for a bug.
  `tank` and `oracle` gain `ToolSearch` to load these servers' deferred tool schemas.

### Changed
- **MCP setup in the crew README is a purpose→server table of links** instead of inline
  install/config blocks that drift from each server's own docs. It keeps only the
  crew-specific contract: which agents use each server, the `mcp__<server>` naming the
  allowlist expects, and the fallback when a server is absent.

## [2.0.0] - 2026-06-12

### Changed
- **`/crew:ship` is folded into `/crew:review`.** The crew flow is now `feature → review → pr`.
  `/crew:review` is the single pre-PR **GO / NO-GO** gate: it runs the diff-scoped executable
  checks the ship gate used to own (lane-scoped build, backend tests, frontend e2e, backend/
  frontend lint — idempotent within a session) **and** the consolidated review (code quality,
  security, design conformance via `seraph`), then emits the `## Blocking` / `## Warnings` /
  `## Passed` sections followed by GO/NO-GO. The previous read-only review is preserved as
  `/crew:review quick` (judgment only, no suites); `/crew:review full` forces every gate
  regardless of the diff. `morpheus`, `tank`, `trinity`, and `/crew:pr` now reference the
  **review gate** instead of the ship gate, and `/crew:pr` requires `/crew:review` → GO.

### Removed
- **`/crew:ship` command.** Its behavior now lives in `/crew:review` (above). **Breaking** for
  anyone scripting or invoking `/crew:ship` directly — run `/crew:review` instead.

## [1.9.0] - 2026-06-12

### Added
- **`engineering-principles` gains a "reach for new code last" ladder.** The skill listed
  YAGNI/KISS/dependency preferences as values but no procedure. It now carries an ordered,
  stop-at-first-match ladder — not needed → don't build; stdlib/runtime → use it; native
  platform feature → use it; installed dependency → use it; collapses to a line or two → do
  that; else write the minimum that works — so implementer agents have an explicit check to
  run before writing code. Kept subordinate to *match the repo*.

## [1.8.0] - 2026-06-12

### Changed
- **`morpheus` right-sizes the model per delegation.** The Agent tool's `model` override is
  now part of the delegation contract: mechanical run-and-report steps (running an existing
  suite, ship-gate build/lint runs, post-fix re-runs) go out as `haiku` for speed, while
  anything that authors or diagnoses (implementation, new tests, failure investigation,
  visual judgment) keeps the worker's default model. When in doubt, the override is omitted.
- **Parallel dispatch is the default, not a suggestion.** Plan steps in
  `.claude/plan-<feature>.md` must declare dependencies explicitly (`depends-on: <step>` or
  `independent`), and `morpheus` dispatches every currently-unblocked step in a single
  message each round instead of serializing independent work.
- **Delegations carry the planning context.** Delegation prompts must now include the exact
  file paths to touch and the relevant snippets/contracts `morpheus` already found while
  planning, so workers start editing instead of re-exploring the repo on every spawn.
- **`tank` and `trinity` get `maxTurns: 40`.** The implementers were the only workers with
  unbounded turns; a stuck retry loop is now a bounded wait that returns a partial finding
  `morpheus` can route, matching the caps already on `oracle`/`dozer`/`seraph`.

### Fixed
- **`validate-plugin.sh` marketplace check works on Windows.** Native Windows `jq` emits
  CRLF, so the marketplace source path and plugin name carried a trailing `\r` and the
  check failed locally (`source ./plugins/crew does not exist`). The 2f loop now strips
  `\r` like the manifest-path loops already did.

## [1.7.0] - 2026-06-11

### Added
- **Figma MCP support for design-driven work.** `seraph` (visual conformance) and `trinity`
  (frontend implementation) now allowlist the `mcp__figma` and `mcp__claude_ai_Figma` servers
  plus `ToolSearch` (to load their deferred tool schemas), so `seraph` pulls the canonical
  design spec from Figma instead of a pasted export and `trinity` builds to exact
  measurements/colors/type. `morpheus` passes the Figma link/node in design delegations (it
  doesn't read Figma itself — the workers do, applying `context-discipline` to fetch the
  specific node, not whole-file dumps). With no Figma MCP present, both fall back to the
  delegation's reference — nothing breaks. README documents the Dev Mode and claude.ai options.

### Changed
- **Playwright tools are server-scoped.** `seraph`/`trinity` now allowlist the whole
  `mcp__playwright` server instead of enumerating every `mcp__playwright__browser_*` tool —
  shorter, and consistent with how the git-host and Figma servers are granted.

## [1.6.0] - 2026-06-11

### Changed
- **`morpheus` stays responsive — it delegates worker steps in the background**
  (`run_in_background`) instead of blocking its turn until each worker returns. While a worker
  (e.g. `tank`) runs, the user can keep chatting — adding comments, corrections, or new fixes —
  and `morpheus` folds them into the plan and dispatches them rather than making the user wait
  to be heard; it collects each worker's result when notified, then verifies and commits.
  Backgrounded steps must be fully specified (background agents can't prompt the user), run
  concurrently only when independent, and are committed only once their result returns verified.

### Docs
- README presents `claude --agent crew:morpheus` as a first-class alternative entry point (a
  session that *is* the orchestrator), and documents the non-blocking background delegation.

## [1.5.0] - 2026-06-11

### Changed
- **Builds are a final gate, not a per-step check.** `tank` and `trinity` no longer run the
  full backend/frontend build as a routine self-check on every change; they verify their work
  with reasoning, targeted reads, and the lint/edit loop.
- `morpheus` holds the build and full test suites until the work queue is fully drained —
  every plan step accepted and any newly added review comments or fixes folded in and
  resolved — so a single pass covers all the work instead of re-running per round-trip.
- `morpheus` **delegates** the gate rather than running it (it never runs a worker's
  build/test task): backend build → `tank`, frontend build → `trinity`, tests → `oracle`/
  `dozer`, so each worker absorbs the verbose output and returns concise findings. `/crew:ship`
  now delegates the build **per lane** (backend → `crew:tank`, frontend → `crew:trinity`).
- New `CLAUDE.md` crew-config slots **Backend build command** / **Frontend build command**
  (the old single *Build command* split in two), so the frontend build gate is real and
  symmetric with the lint pair.
- The build runs **isolated from any running app/dev process** (so it can't interfere or
  contend on locked build outputs), and `morpheus` picks **one concrete build location** at
  the start and passes that exact path in every delegation — reused for the whole session, not
  per agent or per step — so incremental and package caches stay warm.
- The ship gate is **idempotent within a session**: it records the `HEAD` SHA (and a clean
  tree) when a gate passes and skips re-running that gate while `HEAD` is unchanged and the
  tree clean, so a build/suite that just ran as the final step isn't repeated.

## [1.4.1] - 2026-06-10

### Fixed
- **`/crew:feature` now actually launches `crew:morpheus`.** The command told the *current
  session* to plan and delegate to workers itself, so the orchestrator — its anti-drift
  rules, opus model, memory, and git ownership — never ran. The command now delegates the
  whole feature to the `crew:morpheus` agent and relays its consolidated status.
- **`/crew:review` and `/crew:ship` delegate with namespaced agent types** (`crew:seraph`,
  `crew:oracle`, `crew:dozer`). The bare names don't resolve for installed plugins — the
  same failure mode fixed for `morpheus` in 1.1.3.
- **`bash-safety` bypass gaps closed:** recursive+force `rm` is now caught in any flag
  spelling (`-fr`, `-rfv`, `-r -f`, `--recursive --force`), including with other flag
  tokens interleaved or a `--` separator before the target (`rm -r -v -f /`,
  `rm -rf -- /`), force-push via short `-f` is
  blocked alongside `--force` (`--force-with-lease` still allowed), and the protected-branch
  commit check now catches git global flags before the subcommand (`git -c k=v commit`,
  `git -C dir commit`).
- **`lane-guard` allow-lanes now match repo-relative paths** (e.g. `MyApp.Tests/Foo.cs`);
  previously `**/`-anchored patterns only matched absolute paths, blocking `oracle`/`dozer`
  from legitimate test files if the harness passed a relative path.

### Changed
- `validate-plugin.sh`: `agents/` and `hooks/` are now optional per plugin (a
  commands/skills-only plugin validates clean, matching the "adding a plugin is additive"
  contract), while an *existing* dir still requires its contents (`agents/*.md`,
  `hooks/hooks.json`). New check: every `marketplace.json` entry's `source` must exist and
  its `plugin.json` name must match the entry.
- `auto-release.yml` prefers a per-plugin `plugins/<name>/CHANGELOG.md` over the shared
  root one (shared changelogs risk cross-matching versions once more plugins exist).
- Docs aligned with reality: `CLAUDE.md`'s release flow no longer instructs manual
  tagging (the workflow creates the tag + release on merge to `main`), and the plugin
  README's **format** hook description matches the 1.3.0 multi-tool behavior.

## [1.4.0] - 2026-06-08

### Added
- **`morpheus` can drive a git-host MCP for PR work.** It now allowlists `ToolSearch` (to load
  deferred MCP tool schemas — without it the host MCP can't be invoked) and the `mcp__ado` /
  `mcp__github` servers (server-scoped, matching the hosts the README documents). Combined with
  its existing unrestricted `Bash` (`az` / `gh`), this lets `/crew:pr` open and manage pull
  requests from a `claude --agent crew:morpheus` session. If your host MCP is named something
  other than `ado` / `github`, add its `mcp__<server>` to morpheus's `tools`.

## [1.3.0] - 2026-06-08

### Added
- **Backend `format.sh` now runs CSharpier.** `dotnet format` doesn't invoke CSharpier, so
  when the solution configures it (`.csharpierrc`), the formatter hook also runs
  `dotnet csharpier format <file>` for `tank` — best-effort, scoped to the changed file.
- **Diff-aware ship gate.** `/crew:ship` now scopes to the branch diff vs. the base branch:
  `morpheus` classifies changed files into backend (`*.cs`/`*.csproj`/`.cshtml`) and frontend
  (`*.ts`/`*.tsx`/`*.js`/`*.scss`/`*.css`/`*.html`/`.cshtml`) lanes and runs only the gates a
  changed lane can affect — a backend-only diff no longer runs the full e2e suite. Skips are
  reported explicitly (never silent); `/crew:ship full` forces every gate.
- **Backend lint gate** added to `/crew:ship`, symmetric to the frontend one (verify mode —
  e.g. `dotnet format --verify-no-changes` plus `dotnet csharpier check`). New `CLAUDE.md`
  crew-config slots: **Backend lint command**, **Frontend lint command**.

### Changed
- **Frontend `format.sh` applies every configured tool, not just the first match.** It now
  detects and runs Biome, Prettier, ESLint, and Stylelint (each in fix mode, scoped to the
  changed file, only when installed locally) instead of stopping at the first `package.json`
  script it found — so projects using both a formatter and linters get all of them applied.
- **`morpheus` entry-point guidance.** `/crew:feature` (run from a normal session) is now the
  documented entry point; launching a terminal *as* `claude --agent crew:morpheus` is an
  optional, explicitly scoped orchestration session that won't run general/config tasks (e.g.
  statusline) — do those in a normal session. Resolves the prior contradiction between the
  launch hint and the orchestrator's delegate-only design.

## [1.2.0] - 2026-06-05

### Added
- **Git workflow.** `morpheus` now owns version control: it resolves the project's **base
  branch** and **branch-naming** convention (`CLAUDE.md` crew config → memory → ask),
  creates a feature branch off the base, and commits each *verified* step. Workers never run
  git. New `CLAUDE.md` crew-config slots: **Base branch**, **Branch naming**.
- **`/crew:pr` command** — pushes the feature branch and opens a pull request via a git-host
  MCP (GitHub / Azure DevOps), host-agnostic, with confirmation; falls back to printing the
  `git push` command + a ready-to-paste PR body when no host MCP is present. The crew still
  stops at the local ship gate by default; push/PR is this explicit step.
- **`bash-safety` refuses `git commit` on a protected base branch** (`main`/`master`/`develop`)
  for crew agents — they branch first. Scoped via `agent_type`, so a normal main session is
  never intercepted.

## [1.1.3] - 2026-06-05

### Fixed
- **`morpheus` could not delegate to workers when installed** ("Agent type 'tank' not
  found"). Installed plugin agents are namespaced, so `morpheus` now delegates to and
  allowlists `crew:tank` / `crew:trinity` / `crew:oracle` / `crew:dozer` / `crew:seraph`,
  and its launch hint is `claude --agent crew:morpheus`.
- **Hardened `morpheus` against improvising.** Planning/delegation/synthesis are its only
  outputs; if a delegation can't be launched it must stop and report rather than copy files,
  invent project conventions, or do the worker's job itself.

## [1.1.2] - 2026-06-05

Addresses findings from a review by Anthropic's `plugin-dev` agents (plugin-validator,
skill-reviewer) and a best-practice review of the agents/hooks.

### Fixed
- **`dozer` could not create new test files** — it authors Cypress specs but its tools
  listed only `Edit`, not `Write`. Added `Write` (lane-guard already confines it to
  `cypress/**`/spec paths).
- `read-guard.sh`: replaced a fragile mixed `||`/`&&` line with an explicit `if`, and
  documented that this guard intentionally fails open (it's context-hygiene, not security).
- `format.sh`: read the hook payload once (it previously risked consuming stdin twice).

### Changed
- **`format.sh` is now project-aware.** For backend it scopes `dotnet format` to the changed
  file instead of the whole solution (slow on large repos). For frontend it discovers the
  project's own format/fix script from `package.json` (e.g. `format`, `format:fix`,
  `lint:fix`, `biome:format`) by preference order rather than guessing, and skips when the
  repo only exposes check-only scripts. Added a `timeout` to the format hook in `hooks.json`.
- **`seraph` is now strictly read-only**: removed its `memory: local` and the stale
  "memory edits allowed" rule (it has no write tools), and dropped its now-unreachable
  `lane-guard` entry.
- `dozer` `color: orange` → `magenta` (orange isn't in the documented agent palette).
- Added keyword triggers to the `frontend-headless` / `frontend-server-rendered` skill
  descriptions so they trigger outside crew preload too; aligned the `engineering-principles`
  description wording ("DRY with judgment").

## [1.1.1] - 2026-06-05

### Fixed
- **Hooks no longer fail to load with "Duplicate hooks file detected."** The standard
  `hooks/hooks.json` at the plugin root is auto-loaded, but the manifest also declared
  `"hooks": "./hooks/hooks.json"`, so it was loaded twice. Removed the `hooks` field from
  `plugin.json` (the manifest's `hooks` is only for *additional* hook files).
- `validate-plugin.sh` now rejects only the auto-loaded `hooks/hooks.json` in the manifest
  (additional hook files are still allowed and existence-checked) and asserts the root
  `hooks/hooks.json` is present.

## [1.1.0] - 2026-06-05

### Changed
- **`trinity` now owns the full client/presentation layer**, not just React/Redux/SCSS:
  it explicitly covers vanilla JS, HTML, and CSS, and — in **server-rendered** mode — the
  *markup/DOM* inside Razor views (structure, classes, ARIA, presentation). The C#/
  server-side of Razor (view-model binding, `@functions`/`@code`, data access) remains
  `tank`'s; the split is by concern, coordinated between the two. In **headless** mode
  `trinity` still never touches Razor.
- `lane-guard` updated to match: `.cshtml` is no longer denied to `trinity` (Razor is now
  shared by concern, prompt-enforced), and `tank` is now denied `*.js`/`*.mjs`/`*.html` in
  addition to the TS/JSX/SCSS/CSS it already couldn't edit.
- `tank`, `frontend-server-rendered`, and `CLAUDE.md` updated to describe the concern-split
  Razor ownership.

### Added
- **`morpheus` now resolves the frontend mode** instead of requiring it pinned in `CLAUDE.md`:
  it uses a `CLAUDE.md` override if present, else its own (local) memory, else asks the user
  and remembers the answer — then passes the resolved mode into every frontend delegation.
  `trinity` takes the mode from the delegation rather than reading `CLAUDE.md` itself.
  `CLAUDE.md`'s **Frontend mode** is now optional.

## [1.0.2] - 2026-06-05

### Changed
- **Repo restructured into a monorepo marketplace.** The `crew` plugin now lives in
  `plugins/crew/` (its own plugin root) instead of the repo root, and
  `marketplace.json` points at it via `source: "./plugins/crew"`. Adding future
  plugins is now additive (`plugins/<name>/` + a marketplace entry) with no
  collision between each plugin's `agents/`/`commands/`/`skills/`/`hooks/`.
  The installed plugin's components are unchanged — same agents, commands, and hooks.
- `validate-plugin.sh` now validates every plugin under `plugins/*`, and CI globs
  were updated accordingly.

### Added
- Per-plugin `plugins/crew/README.md`; the root `README.md` is now a marketplace
  overview with a plugin index.

## [1.0.1] - 2026-06-05

### Fixed
- **Agents now actually load when installed.** Declaring `agents` in the manifest
  (string or array) passed install validation but the agents were never discovered
  (`plugin details` reported 0). Agents now live in a root `agents/` directory and
  are auto-discovered, matching the convention used by Anthropic's own plugins.
  `plugin details` now reports all six (`morpheus`, `tank`, `trinity`, `oracle`,
  `dozer`, `seraph`).
- `validate-plugin.sh` validates array-shaped manifest fields, checks the root
  `agents/` directory, and tolerates CRLF checkouts.

### Changed
- **Commands renamed** to drop the redundant `zion-` prefix, since installed
  components are already namespaced under the plugin: `/zion-feature` → `/crew:feature`,
  `/zion-review` → `/crew:review`, `/zion-ship` → `/crew:ship`. **Breaking** for anyone
  scripting the old command names.
- `CLAUDE.md` expanded from a crew-config stub into a full project memory file.
- `.github/copilot-instructions.md` aligned with the crew reviewer (engineering-principles
  checklist + code/security/design pillars) and now requires PRs that change plugin
  behavior to bump `version` and add a changelog entry.

### Added
- `.gitattributes` enforcing LF line endings for all text files, so shell hooks/scripts
  stay valid on Linux CI and as plugin hooks.
- This `CHANGELOG.md`.

## [1.0.0]

### Added
- Initial release: orchestrated crew of agents (`morpheus`, `tank`, `trinity`,
  `oracle`, `dozer`, `seraph`), commands, skills (`engineering-principles`,
  `context-discipline`, `frontend-headless`, `frontend-server-rendered`), and hooks
  (lane guard, read guard, bash safety, formatter).

[3.1.7]: https://github.com/johantor/zion/compare/crew--v3.1.6...crew--v3.1.7
[3.1.6]: https://github.com/johantor/zion/compare/crew--v3.1.5...crew--v3.1.6
[3.1.5]: https://github.com/johantor/zion/compare/crew--v3.1.4...crew--v3.1.5
[3.1.4]: https://github.com/johantor/zion/compare/crew--v3.1.3...crew--v3.1.4
[3.1.3]: https://github.com/johantor/zion/compare/crew--v3.1.2...crew--v3.1.3
[3.1.2]: https://github.com/johantor/zion/compare/crew--v3.1.1...crew--v3.1.2
[3.1.1]: https://github.com/johantor/zion/compare/crew--v3.1.0...crew--v3.1.1
[3.1.0]: https://github.com/johantor/zion/compare/crew--v3.0.0...crew--v3.1.0
[3.0.0]: https://github.com/johantor/zion/compare/crew--v2.10.0...crew--v3.0.0
[2.10.0]: https://github.com/johantor/zion/compare/crew--v2.9.0...crew--v2.10.0
[2.9.0]: https://github.com/johantor/zion/compare/crew--v2.8.1...crew--v2.9.0
[2.8.1]: https://github.com/johantor/zion/compare/crew--v2.8.0...crew--v2.8.1
[2.8.0]: https://github.com/johantor/zion/compare/crew--v2.7.1...crew--v2.8.0
[2.7.1]: https://github.com/johantor/zion/compare/crew--v2.7.0...crew--v2.7.1
[2.7.0]: https://github.com/johantor/zion/compare/crew--v2.6.1...crew--v2.7.0
[2.6.1]: https://github.com/johantor/zion/compare/crew--v2.6.0...crew--v2.6.1
[2.6.0]: https://github.com/johantor/zion/compare/crew--v2.5.0...crew--v2.6.0
[2.5.0]: https://github.com/johantor/zion/compare/crew--v2.4.0...crew--v2.5.0
[2.4.0]: https://github.com/johantor/zion/compare/crew--v2.3.0...crew--v2.4.0
[2.3.0]: https://github.com/johantor/zion/compare/crew--v2.2.1...crew--v2.3.0
[2.2.1]: https://github.com/johantor/zion/compare/crew--v2.2.0...crew--v2.2.1
[2.2.0]: https://github.com/johantor/zion/compare/crew--v2.1.1...crew--v2.2.0
[2.1.1]: https://github.com/johantor/zion/compare/crew--v2.1.0...crew--v2.1.1
[2.1.0]: https://github.com/johantor/zion/compare/crew--v2.0.0...crew--v2.1.0
[2.0.0]: https://github.com/johantor/zion/compare/crew--v1.9.0...crew--v2.0.0
[1.9.0]: https://github.com/johantor/zion/compare/crew--v1.8.0...crew--v1.9.0
[1.8.0]: https://github.com/johantor/zion/compare/crew--v1.7.0...crew--v1.8.0
[1.7.0]: https://github.com/johantor/zion/compare/crew--v1.6.0...crew--v1.7.0
[1.6.0]: https://github.com/johantor/zion/compare/crew--v1.5.0...crew--v1.6.0
[1.5.0]: https://github.com/johantor/zion/compare/crew--v1.4.1...crew--v1.5.0
[1.4.1]: https://github.com/johantor/zion/compare/crew--v1.4.0...crew--v1.4.1
[1.4.0]: https://github.com/johantor/zion/compare/crew--v1.3.0...crew--v1.4.0
[1.3.0]: https://github.com/johantor/zion/compare/crew--v1.2.0...crew--v1.3.0
[1.2.0]: https://github.com/johantor/zion/compare/crew--v1.1.3...crew--v1.2.0
[1.1.3]: https://github.com/johantor/zion/compare/crew--v1.1.2...crew--v1.1.3
[1.1.2]: https://github.com/johantor/zion/compare/crew--v1.1.1...crew--v1.1.2
[1.1.1]: https://github.com/johantor/zion/compare/crew--v1.1.0...crew--v1.1.1
[1.1.0]: https://github.com/johantor/zion/compare/crew--v1.0.2...crew--v1.1.0
[1.0.2]: https://github.com/johantor/zion/compare/crew--v1.0.1...crew--v1.0.2
[1.0.1]: https://github.com/johantor/zion/compare/crew--v1.0.0...crew--v1.0.1
[1.0.0]: https://github.com/johantor/zion/releases/tag/crew--v1.0.0
