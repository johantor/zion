# crew — quick reference for agents working on this plugin

Crew-specific map. **Keep it accurate: a PR that changes anything stated here updates this file
in the same commit.** Rules shared by every plugin: the root [CLAUDE.md](../../CLAUDE.md).
Conventions: [AGENTS.md](../../AGENTS.md).

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
  - Shared with keymaker: `context-discipline`, `loop-engineering`, `operator-voice`
    (ASD-STE-100, preloaded by the two orchestrators; operator messages only, never plans,
    ledgers or commits).
  - Crew-only: `engineering-principles` (the review rubric), and the preloads
    `mid-run-direction` (all seven workers, not `morpheus`) and `design-tokens` (`seraph`).
  - Loaded once resolved: frontend mode, stack and test-tool skills. Backends `backend-dotnet`
    (+ `cms-optimizely`), `-node`, `-python`, `-go`, `-rust`, `-java`, `-shell`, each paired with
    a `tests-*` skill. Only node needs lane paths (its extensions collide with a frontend's).
    `frontendStack: none` is a stated absence: `morpheus` skips frontend, e2e and unit-tool
    resolution and dispatches only `tank`/`oracle`. That gate sits above the resolution table.
- `hooks/` — wired in `hooks/hooks.json`, mirrored by the repo's `.claude/settings.json` (§7).
  `bash-safety` and `lane-guard` fail closed; `read-guard`, `format`, `turn-budget`,
  `dispatch-denied` and `plan-guard` fail open.
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
  `agent-id:` while in flight (the address for steering that worker; cleared when the step leaves
  `in-progress`). The dispatch's `steer-token:` — what a steer must quote for the worker to tell
  morpheus's message from an injected one — deliberately **never** lands in the plan file: a plan
  dir can be committed, and a leaked live token is a forgeable steer. It lives in morpheus's
  session, and a resumed run re-dispatches instead of steering orphans.
- Loop mode: generic contract in `skills/loop-engineering/SKILL.md` (shared byte-for-byte
  with keymaker; inner loop + a note that the outer loop is a main-session wrapper); crew
  bindings (gate GO success, second-NO-GO cap, `/crew:pr`, neo no-op) in `agents/morpheus.md`
  §"Loop-mode bindings". The outer loop is `commands/loop.md`.
- Agent frontmatter: `skills:` is the **last** key, unqualified names, `  - name` list items
  (§2g's awk parser reads the `  - name` items; it stops at the next key, so the last-key rule
  is convention, not a parser constraint).
- `omitClaudeMd: true` is set on the two workers that are read-only on code and fully briefed by
  their dispatch prompt (`sentinel`, `seraph`). Never on an implementer — the project's
  `CLAUDE.md` is where its coding conventions live. The §12 footprint figure counts agent file +
  preloaded skills only, so this key changes the real spawn cost but not the reported number.
- Always-loaded footprint: validator §12 reports every agent's agent-file + preloaded-skill line
  count, and enforces an optional `loaded-lines-cap: <n>` frontmatter key (`morpheus`: 585 —
  raised from 575 for the parallel-gates rule (§*One build location; one intermediate path per
  writer; gates in parallel by default*), from 541 for the plan-mode section, itself raised from
  526 for the gate build-strictness rule and the build-contention rules that landed
  beside it, from 496 for `operator-voice` and from 480 for the steer contract,
  keeping a few lines of slack (6 today), since the figure counts preloaded
  shared skills and a keymaker-side edit to one would otherwise fail crew's cap).
  Rationale for the prompts themselves lives in the root `AGENTS.md` §"Prompt design rationale" —
  agent prompts carry instruction, not justification; each trimmed prompt points there once.
- Agent `tools:` MCP grants come in pairs: bare `mcp__<key>` (server keyed in `.mcp.json` /
  `claude mcp add`) **and** `mcp__plugin_<plugin>_<key>` (same server installed as a plugin — its
  tools are named `mcp__plugin_<plugin>_<server>__<tool>`, which the bare form never matches).
  The plugin and its server are keyed independently (`chrome-devtools-mcp` ships
  `chrome-devtools`), so §13 pairs them on the **server** half, by suffix.
  Validator §13 enforces the pairing both ways, reads either YAML shape of `tools:` (inline
  list or `  - name` block), and rejects grants that cover less than they look like they do —
  tool-scoped `mcp__server__tool` and serverless `mcp__*`.
  Hosted connectors that can't ship in a plugin are exempt by name in the
  validator's `mcp_connector_only` list — both namespaces a connector can surface under
  (`claude_ai_<Name>` in the CLI, bare `<Name>` on claude.ai surfaces) for Figma, GitHub, Linear,
  Atlassian, and Sentry. `/crew:init` §5 reports the namespaces a session can actually see; it
  writes nothing.
- Agent write-access declarations, checked by validator §9 (see below): every crew agent
  carries `owns-git: true|false` and `lane-guarded: true|false` before `skills:`. Exactly one
  agent (`morpheus`) owns git, and `bash-safety.sh`'s `git_owner=` line must name that same
  agent — it is what the shared floor's `git mv` allowance keys on, and a stale name there fails
  closed for the one agent that may rename. These are the declarative half of what the guard hooks
  enforce — a new agent that omits them fails CI instead of silently getting unguarded git and no
  lane.

## Gotchas

- `lane-guard.sh`'s `scan_markers` uses hardcoded framework allowlists
  (`node_backend_deps`/`frontend_deps`, only when stacks and lane paths are unset). A miss fails
  silently, so add new frameworks **with a fixture in `tests/lane-guard.test.sh`**. One `find`
  walk for all markers; `detect_regime` caches per `session_id`, published by `mv`.
- `sentinel`'s "no mutating MCP tool" rule is prose, not a mechanism (§13 forces whole-server
  grants). Don't describe it as enforced.
