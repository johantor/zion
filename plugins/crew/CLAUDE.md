# crew — quick reference for agents working on this plugin

Distilled repo knowledge so sessions don't re-explore. **Keep it accurate: a PR that changes
anything stated here updates this file in the same commit.** Conventions live in the root
[AGENTS.md](../../AGENTS.md); this file is the crew-specific map.

## Map

- `agents/` — auto-discovered, not in the manifest.
  - `morpheus`: orchestrator, `model: opus`, sole git owner. Its `Agent(...)` allowlist (seven
    workers plus `Explore`/`Plan`) and `ExitPlanMode` only work as the main thread of
    `claude --agent crew:morpheus`; via `/crew:feature` the harness ignores both.
  - Workers: `tank` (the stack's core: in a CLI or script pack, the commands and I/O), `trinity`
    (client-facing layer), `oracle` (unit tests), `dozer` (e2e), `seraph` (visual, no Bash;
    measures computed styles through the browser MCP), `neo` (express generalist), `sentinel`
    (post-merge triage; no Write/Edit/Bash, history via the git-host MCP).
- `commands/` — namespaced `crew:*` when installed.
  - `init` writes `.claude/crew.md`, one frontmatter key per slot. Its §1 slot keys are validator
    §11's source of truth; §3 owns what may go in `CLAUDE.md` (auto mode's classifier reads only
    that file); §5 migrates a legacy `## Crew configuration` block; §6 reports MCP namespaces.
  - `feature`, `review` (GO/NO-GO gate), `pr` (the only push/PR path), `address`.
  - `loop`: re-launches `morpheus` directly each tick on native `/loop` until exit conditions or
    the cap; the wrapper owns scheduling.
  - `triage`: launches `sentinel` and relays its report; writes nothing (#175 phase 2).
  - `notify`: peer-session messaging (#177). A command, since `morpheus` has no `ListAgents`, so
    a `--agent crew:morpheus` session needs an explicit `to=`.
- `skills/` — `<name>/SKILL.md`, frontmatter `name:` + `description:` only (the description
  carries the triggers).
  - Shared with keymaker, crew canonical: `engineering-principles`, `context-discipline`,
    `loop-engineering`, `operator-voice` (ASD-STE-100, preloaded by the two orchestrators; for
    operator messages only, never plans, ledgers or commits).
  - Crew-only preloads: `mid-run-direction` (all seven workers, not `morpheus`) and
    `design-tokens` (`seraph`).
  - Loaded once resolved: frontend mode, stack and test-tool skills. Backends `backend-dotnet`
    (+ `cms-optimizely`), `-node`, `-python`, `-go`, `-rust`, `-java`, `-shell`, each paired with
    a `tests-*` skill. Only node needs lane paths (its extensions collide with a frontend's).
    `frontendStack: none` is a stated absence: `morpheus` skips frontend, e2e and unit-tool
    resolution and dispatches only `tank`/`oracle`. That gate sits above the resolution table.
- `hooks/` — wired in `hooks/hooks.json`, mirrored by the repo's `.claude/settings.json` (§7).
  Enforcing guards fail closed; `turn-budget`, `dispatch-denied` and `plan-guard` fail open.
  Scope and open gaps of the Bash guards: AGENTS.md, "The Bash guards are floors, not sandboxes".
  - `bash-safety.sh`: workers never run git; protected-branch commit backstop; watch/dev
    commands refused; file-mutating Bash refused for agent sessions (in-place
    `sed`/`perl`/`ruby`/`awk`, `tee`, `patch`, `cp`/`mv`, a redirect to a non-exempt sink; #192).
    One carve-out: a plain `git mv`, for any agent, matched on the raw command so a later line
    counts; `-f`/`--force` stays refused. *Whose* rename it is lives below the shared region:
    the no-git arm calls `guard_block_git_mv_handback "$git_owner"` (first line only, like every
    refusal). `git_owner=morpheus` sits above the region; §9 pins it to the `owns-git` agent.
    Raw reads (`cat f`) are refused for every session: a habit redirect, not a boundary.
  - `read-guard.sh`: raw reads over 64 KiB; an explicit `limit` ≤ 2000 lines passes.
  - `lane-guard.sh`: Edit/Write lanes. The only hook that reads crew config: `.claude/crew.md`
    frontmatter by key, else the legacy `CLAUDE.md` block. Loaded once in the parent shell, since
    `config_slot` runs in `$(...)`.
  - Roster shape: `# crew-roster: <name>` then an `a|b|c)` arm, in `bash-safety.sh` and
    `lane-guard.sh`; §9 keeps both in lockstep with `owns-git`/`lane-guarded` frontmatter.
  - `turn-budget.sh` (PostToolUse `*`): counts tool calls against `maxTurns`, warns at 75% and
    90%. Its `<agent>) budget=<n> ;;` table is lockstepped with `maxTurns` by §8.
  - `format.sh`: six lanes by extension, each under `CREW_FORMAT_TIMEOUT` (default 20s,
    unbounded without `timeout`/`gtimeout`). `dotnet`/`web` use project tools and root config
    only (a nested `.prettierrc` is missed); `python`/`go`/`rust`/`java` use `PATH` tools and
    `find_up` config bounded at the project root. `.sh`/`.bats` are unowned. Single-file
    formatters only; whole-project ones belong to the review gate.
  - `dispatch-denied.sh` (`PermissionDenied`, `Agent|Task`): attempt 1 emits `retry: true`,
    later ones only a `systemMessage`. The JSON is the decision. Counter under
    `CREW_DISPATCH_DENIED_DIR`; a path that cannot count takes the no-retry branch. Gates on the
    `crew:` namespace, not a roster, so it is inert under this repo's dev wiring.
  - `plan-guard.sh` (`PreToolUse`, `Agent|Task`): in plan mode, refuses a `crew:<worker>` whose
    frontmatter grants `Edit`/`Write`/`NotebookEdit`; `owns-git: true` passes. Reads both
    `tools:` shapes; `CREW_AGENTS_DIR` is the test override. Inert under dev wiring too.
  - `lib/guard-lib.sh`: the sourced library (payload plumbing, `guard_normalize`, `GUARD_RE_*`,
    the `guard_block_*` helpers, quote masking, protected branches, read-guard limits, state
    files). Not executable, not wired (§3/§6). Match with `=~` and parameter expansion, no fork
    per pattern; POSIX patterns for BSD regcomp.
  - Sync: `read-guard.sh` and `lib/guard-lib.sh` are byte-identical with keymaker's, and the
    marked `bash-safety.sh` region matches (§5). Crew is canonical. Shared logic goes in
    `guard-lib.sh`, not a wider region.
- No `scripts/` dir. Repo-root `scripts/validate-plugin.sh` checks all plugins: marketplace sync
  §2f, `skills:` resolution §2g, `[Unreleased]` slot §2i, skill sync §4, hook sync §5, wiring §6,
  hook mirror §7, turn-budget §8, rosters §9, prose refs §10, `crew.md` keys §11, footprint §12,
  MCP pairs §13. Beside it: `check-changelog.sh` (diff-based, needs a base ref) and
  `release-notes.sh` (used by auto-release).
- `tests/` — hook test cases, not shipped. Runner and harness live in `tests/hooks/`
  (`run.sh` finds every `plugins/*/tests/*.test.sh` and fails if a plugin has `hooks/` and no
  suite). Bash, `jq` and `git` only. A guard is `stdin JSON → exit 0/2`: assert allow/block plus
  a stderr substring, and a hook logic change adds cases on both sides. Exceptions:
  `turn-budget` is stateful (`CREW_TURN_BUDGET_DIR`), `format` asserts its stderr report through
  fake tools, `dispatch-denied` asserts its stdout JSON with `jq`, and `plan-guard` uses real
  agents, then fixtures via `CREW_AGENTS_DIR`. Every validator section has a negative fixture and
  a silent control (assert on the FAIL message). `changelog-gate.test.sh` builds real git history.

## Schemas & conventions

- Durable run state: `<plan-dir>/plan-<feature>.md`, schema in `agents/morpheus.md`
  §"The plan file is durable state" — header `feature:`/`base-branch:`/`feature-branch:` +
  inner-loop fields (`loop:`, `exit-conditions:`, `gate:`) + outer-loop bookkeeping
  (`iterations: n/max`, `in-flight:`, written by the `/crew:loop` wrapper, not morpheus);
  steps carry `id:`/`status:`/`depends-on:`/`acceptance:`/`worker:`/`attempts:`/`evidence:`, plus
  `agent-id:` while in flight (cleared when the step leaves `in-progress`). The `steer-token:`
  **never** lands in the plan file, since a plan dir can be committed; a resumed run
  re-dispatches instead of steering orphans.
- Loop mode: generic contract in `skills/loop-engineering/SKILL.md` (shared byte-for-byte
  with keymaker; inner loop + a note that the outer loop is a main-session wrapper); crew
  bindings (gate GO success, second-NO-GO cap, `/crew:pr`, neo no-op) in `agents/morpheus.md`
  §"Loop-mode bindings". The outer loop is `commands/loop.md`.
- Agent frontmatter: `skills:` is the **last** key, unqualified names, `  - name` items (§2g).
  Every crew agent carries `owns-git` and `lane-guarded` before it (§9); exactly one
  (`morpheus`) owns git, and `bash-safety.sh`'s `git_owner=` names it.
- `omitClaudeMd: true` only on `sentinel` and `seraph` (read-only, fully briefed). Never on an
  implementer: the project's `CLAUDE.md` holds its conventions.
- Footprint: §12 counts agent file + preloaded skills and enforces `loaded-lines-cap`
  (`morpheus`: 575, 7 lines of slack; a keymaker edit to a shared skill counts too). Prompts
  carry instruction; rationale lives in AGENTS.md, "Prompt design rationale".
- MCP grants come in pairs, `mcp__<key>` and `mcp__plugin_<plugin>_<key>`, paired by server
  suffix (§13, both `tools:` shapes). Tool-scoped and serverless grants are rejected. Hosted
  connectors (Figma, GitHub, Linear, Atlassian, Sentry) are exempt via `mcp_connector_only`.

## Gotchas & release

- §2g/§4 index skills via `git ls-files` — **stage new/renamed skill files before running the
  validator** or they won't resolve.
- Validate = what CI runs: `bash scripts/validate-plugin.sh` + `bash scripts/check-changelog.sh` +
  `bash tests/hooks/run.sh` +
  `shellcheck plugins/*/hooks/*.sh plugins/*/hooks/lib/*.sh plugins/*/tests/*.sh scripts/*.sh tests/hooks/*.sh`
  (shellcheck may be missing locally; CI covers it). `hooks/lib/*.sh` needs its own glob.
- `lane-guard.sh`'s `scan_markers` uses hardcoded framework allowlists
  (`node_backend_deps`/`frontend_deps`, only when stacks and lane paths are unset). A miss fails
  silently, so add new frameworks **with a fixture in `tests/lane-guard.test.sh`**. One `find`
  walk for all markers; `detect_regime` caches per `session_id`, published by `mv`.
- `sentinel`'s "no mutating MCP tool" rule is prose, not a mechanism (§13 forces whole-server
  grants). Don't describe it as enforced.
- Release: bump `.claude-plugin/plugin.json` + a matching `## [X.Y.Z]` in `CHANGELOG.md`, folding
  in `## [Unreleased]`. Auto-release tags `crew/vX.Y.Z` on merge. Bump by default: a changed
  verdict or reworded refusal is a patch. Only an unobservable change parks under
  `[Unreleased]`. Shipped = all but `tests/`, `CLAUDE.md`, `VERIFICATION.md`, the changelog.
  Details: AGENTS.md, "Releasing".
- **Changelog entries: one line, two at most**, what changed. The why goes in the commit.
