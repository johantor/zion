# Changelog

All notable changes to the `crew` plugin are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
