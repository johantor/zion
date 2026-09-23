# crew — quick reference for agents working on this plugin

Crew-specific map. **Keep it accurate: a PR that changes anything stated here updates this file
in the same commit.** Rules shared by every plugin: [AGENTS.md](../../AGENTS.md).

## Map

- `agents/` — auto-discovered, not in the manifest.
  - `morpheus`: orchestrator, `model: opus`, sole git owner. Its `Agent(...)` allowlist (seven
    workers plus `Explore`/`Plan`) and `ExitPlanMode` only work as the main thread of
    `claude --agent crew:morpheus`; via `/crew:feature` the harness ignores both. It also has
    `AskUserQuestion` (operator choices), `TaskStop`, `Skill`, `WebFetch` and `WebSearch`;
    workers get no web tools.
  - Workers: `tank` (the stack's core: in a CLI or script pack, the commands and I/O), `trinity`
    (client-facing layer), `oracle` (unit tests), `dozer` (e2e), `seraph` (visual, no Bash;
    measures computed styles through the browser MCP), `neo` (express generalist), `sentinel`
    (post-merge triage; no Write/Edit/Bash, history via the git-host MCP).
- `commands/` — namespaced `crew:*` when installed.
  - `init` writes `.claude/crew.md`, one frontmatter key per slot; `--local` writes the same
    file to the shared git dir and the orchestration prose to `~/.claude/CLAUDE.md`. Its §1 slot keys are validator
    §11's source of truth; §3 owns what may go in `CLAUDE.md` (auto mode's classifier reads only
    that file); §5 migrates a legacy `## Crew configuration` block; §6 reports MCP namespaces.
  - `feature`, `review` (GO/NO-GO gate), `pr` (the only push/PR path), `address`.
  - `debt`, `audit`: route into `morpheus`'s debt lane (the `debt-lane` skill). `debt` runs in
    the foreground so its gates can prompt. The skill must not share a command's name: a
    command is also listed as a skill, so `morpheus` would load the command and relaunch itself.
  - `loop`: re-launches `morpheus` directly each tick on native `/loop` until exit conditions or
    the cap; the wrapper owns scheduling.
  - `triage`: launches `sentinel` and relays its report; writes nothing (#175 phase 2).
  - `notify`: peer-session messaging (#177). A command, since `morpheus` has no `ListAgents`, so
    a `--agent crew:morpheus` session needs an explicit `to=`.
- `skills/` — `<name>/SKILL.md`, frontmatter `name:` + `description:` only (the description
  carries the triggers).
  - `morpheus`'s preloads: `context-discipline`, `loop-engineering`, `operator-voice`
    (ASD-STE-100; operator messages only, never plans, ledgers or commits).
  - Debt lane, loaded on demand: `debt-lane` (the flow, the fixer rules each handoff carries, the
    `<plan-dir>/debt-<slug>.md` ledger), `debt-taxonomy` (rubric, gate, tiers), and
    `debt-taxonomy-dotnet`/`-typescript` (mechanisms, justification slots, recipes).
  - Also: `engineering-principles` (the code rules `/crew:review` grades a user's project
    against; this repo's own review rubric is `.github/skills/code-review`), and the preloads
    `mid-run-direction` (all seven workers, not `morpheus`) and `design-tokens` (`seraph`).
  - Loaded once resolved: frontend mode, stack and test-tool skills. Backends `backend-dotnet`
    (+ `cms-optimizely`), `-node`, `-python`, `-go`, `-rust`, `-java`, `-shell`, each paired with
    a `tests-*` skill. Only node needs lane paths (its extensions collide with a frontend's).
    `frontendStack: none` is a stated absence: `morpheus` skips frontend, e2e and unit-tool
    resolution and dispatches only `tank`/`oracle`. That gate sits above the resolution table.
- `hooks/` — wired in `hooks/hooks.json`, mirrored by the repo's `.claude/settings.json` (§7).
  `bash-safety` and `lane-guard` fail closed; `read-guard`, `format`, `turn-budget`,
  `dispatch-denied` and `plan-guard` fail open.
  - `bash-safety.sh`: workers never run git; protected-branch commit backstop (reads the
    payload's `cwd`, not the hook's directory; AGENTS.md has the shapes); watch/dev
    commands refused; file-mutating Bash refused for agent sessions (in-place
    `sed`/`perl`/`ruby`/`awk`, `tee`, `patch`, `cp`/`mv`, a redirect to a non-exempt sink; #192).
    One carve-out: a plain `git mv`, for any agent, matched on the raw command so a later line
    counts; `-f`/`--force` stays refused. *Whose* rename it is comes after the floor:
    the no-git arm calls `guard_block_git_mv_handback "$git_owner"` (first line only, like every
    refusal). `git_owner=morpheus` sits above the floor; §9 pins it to the `owns-git` agent.
    Raw reads (`cat f`) are refused for every session: a habit redirect, not a boundary.
  - `read-guard.sh`: raw reads over 64 KiB; an explicit `limit` ≤ 2000 lines passes.
  - `lane-guard.sh`: Edit/Write lanes. The only hook that reads crew config: `.claude/crew.md`
    frontmatter by key, else `crew.md` in the shared git dir (`/crew:init --local`; found by
    reading `.git` and `commondir`, no fork), else the legacy `CLAUDE.md` block. Loaded once in the parent shell, since
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
  - `lib/guard-lib.sh`: payload plumbing, `guard_normalize`, `GUARD_RE_*`, the `guard_block_*`
    helpers, quote masking, protected branches, read-guard limits, state files.
- `tests/` — a guard is `stdin JSON → exit 0/2`: assert allow/block plus a stderr substring.
  Exceptions: `turn-budget` is stateful (`CREW_TURN_BUDGET_DIR`), `format` asserts its stderr
  report through fake tools, `dispatch-denied` asserts its stdout JSON with `jq`, and
  `plan-guard` uses real agents, then fixtures via `CREW_AGENTS_DIR`. Every validator section has
  a negative fixture and a silent control (assert on the FAIL message).
  `changelog-gate.test.sh` builds real git history.

## Schemas & conventions

- Durable run state: `<plan-dir>/plan-<feature>.md`, schema in `agents/morpheus.md`
  §"The plan file is durable state" — header `feature:`/`base-branch:`/`feature-branch:` +
  inner-loop fields (`loop:`, `exit-conditions:`, `gate:`) + outer-loop bookkeeping
  (`iterations: n/max`, `in-flight:`, written by the `/crew:loop` wrapper, not morpheus);
  steps carry `id:`/`status:`/`depends-on:`/`acceptance:`/`worker:`/`attempts:`/`evidence:`, plus
  `agent-id:` while in flight (cleared when the step leaves `in-progress`). The `steer-token:`
  **never** lands in the plan file, since a plan dir can be committed; a resumed run
  re-dispatches instead of steering orphans.
- Loop mode: generic contract in the shared `loop-engineering` skill; crew bindings (gate GO
  success, second-NO-GO cap, `/crew:pr`, neo no-op) in `agents/morpheus.md` §"Loop-mode
  bindings". The outer loop is `commands/loop.md`.
- Every crew agent carries `owns-git` and `lane-guarded` before `skills:` (§9); exactly one
  (`morpheus`) owns git, and `bash-safety.sh`'s `git_owner=` names it.
- `omitClaudeMd: true` only on `sentinel` and `seraph` (read-only, fully briefed). Never on an
  implementer: the project's `CLAUDE.md` holds its conventions.
- `morpheus` has `loaded-lines-cap: 590`, 1 line of slack. Skills it loads on demand (`debt-lane`)
  do not count.

## Gotchas

- `lane-guard.sh`'s `scan_markers` uses hardcoded framework allowlists
  (`node_backend_deps`/`frontend_deps`, only when stacks and lane paths are unset). A miss fails
  silently, so add new frameworks **with a fixture in `tests/lane-guard.test.sh`**. One `find`
  walk for all markers; `detect_regime` caches per `session_id`, published by `mv`.
- `sentinel`'s "no mutating MCP tool" rule is prose, not a mechanism (§13 forces whole-server
  grants). Don't describe it as enforced.
