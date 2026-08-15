# crew — quick reference for agents working on this plugin

Distilled repo knowledge so sessions don't re-explore. **Keep it accurate: a PR that changes
anything stated here updates this file in the same commit.** Conventions live in the root
[AGENTS.md](../../AGENTS.md); this file is the crew-specific map.

## Map

- `agents/` — `morpheus` (orchestrator, `model: opus`, sole git owner) + workers `tank`
  (backend), `trinity` (frontend), `oracle` (unit tests), `dozer` (e2e), `seraph` (visual —
  no Bash; measures computed styles/geometry through the browser MCP's script evaluation
  rather than comparing screenshots by eye), `neo` (express generalist), `sentinel` (post-merge triage; no Write/Edit/**Bash**,
  so its read-only posture is the `tools:` grant itself and needs no guard hook — history comes
  from the git-host MCP, not local git). Auto-discovered; not in the manifest.
- `commands/` — `init` (§1 slots are validator §11's source of truth; §5 is a report-only MCP
  namespace check that writes nothing; §4 also writes the fixed, slot-free `## Crew orchestration`
  prose **above** the config block — the classifier reads `CLAUDE.md`, and §11 reads from
  `## Crew configuration` to EOF, so that section must stay above it or its bullets read as
  slots), `feature`, `review` (GO/NO-GO gate), `pr` (the only push/PR path),
  `address`, `loop` (outer-loop driver: re-launches `morpheus` directly each tick — not by
  nesting `/crew:feature` — on the native `/loop` dynamic mode until the plan's exit
  conditions/iteration cap are met; wrapper owns scheduling), `triage` (launches `sentinel` on a
  production signal and relays its report; writes nothing — the write-back to the work item is
  deliberately not built, see #175 phase 2). Namespaced `crew:*` when installed.
- `skills/` — shared + synced across plugins (crew canonical): `engineering-principles`,
  `context-discipline`, `loop-engineering`, `operator-voice` (**preloaded by `morpheus`** and by
  keymaker's orchestrator — the two agents that report to the operator directly; it governs
  operator-facing messages only, never plan files, ledgers, or commit messages). Crew-only: `mid-run-direction` (the receiving half of
  steering — preloaded by all seven workers, deliberately **not** by `morpheus`, which owns the
  sending half in its own prompt) and `design-tokens` (**preloaded by `seraph`** rather than
  resolved at runtime — one skill covers every token system: CSS custom properties, Tailwind,
  SCSS, tokens JSON, Figma variables — so there is no choice to resolve and `seraph` needs no
  `Skill` tool to reach it). Frontend-mode, per-stack, and per-test-tool
  skills load dynamically once resolved. Skill = `<name>/SKILL.md`, frontmatter `name:` +
  `description:` only; the `description:` carries the trigger phrases.
- `hooks/` — `bash-safety.sh` (workers blocked from git entirely; protected-branch commit
  backstop; watch/dev commands refused), `read-guard.sh` (>64 KiB raw reads; an explicit
  `limit` ≤ 2000 lines passes), `lane-guard.sh` (Edit/Write lanes). Both guards gate on a
  hardcoded agent-name roster, each preceded by a `# crew-roster: <name>` marker whose
  following `a|b|c)` arm shape is load-bearing — validator §9 keeps those rosters in lockstep
  with the agents' `owns-git`/`lane-guarded` frontmatter, both directions. Also `format.sh`,
  `turn-budget.sh` (PostToolUse `*`: counts a crew agent's tool calls against its
  frontmatter `maxTurns` — a conservative heuristic, tool calls ≥ turns — and warns once at
  75% and once at 90% so it winds down and hands back `remaining:` instead of truncating;
  **advisory, fails open** on every can't-count path, unlike the fail-closed guards; its
  `<agent>) budget=<n> ;;` table shape is load-bearing — validator §8 keeps it in lockstep
  with agent `maxTurns`, both directions). Wiring in
  `hooks/hooks.json` must mirror the repo's `.claude/settings.json` (validator §7).
  `hooks/lib/guard-lib.sh` is the **sourced library** every entry point above loads: payload
  plumbing (`guard_read_payload`, `guard_jq2`), the command-shape patterns
  (`GUARD_RE_*`), the shared block helpers (`guard_block_destructive` /
  `_watch_commands` / `_raw_reads` / `_protected_branch_commit`), the protected-branch list,
  read-guard's limits, and the TTL-swept state-file helper. It is the one file in `hooks/`
  that must **not** be executable and must **not** be wired (validator §3/§6) — it has no
  main. Matching goes through bash's `=~` and parameter expansion, never `echo | grep`: these
  guards run before every tool call, so a fork per pattern is latency paid every time (one
  `bash-safety` call costs ~4 process ops, not ~32). Patterns stay POSIX so they behave the
  same under BSD/macOS regcomp.
  `read-guard.sh` and `lib/guard-lib.sh` are byte-identical with keymaker's copies, and
  `bash-safety.sh`'s marked shared-guard region (now just the call sequence that fixes the
  floor's order) is region-synced with keymaker's (validator §5; crew canonical — edit here
  first). Shared logic belongs in `guard-lib.sh`, not in a widened marker region.
  `format.sh` runs every formatter under a wall-clock bound (`CREW_FORMAT_TIMEOUT`,
  default 20s) via `timeout`/`gtimeout`, degrading to an unbounded run where neither
  exists (stock macOS/BSD); a hang is reported distinctly from a formatter that failed.
  `dispatch-denied.sh` (`PermissionDenied`, matcher `Agent|Task`) answers auto mode refusing a
  worker dispatch: attempt 1 emits `hookSpecificOutput.retry: true`, later attempts emit only a
  `systemMessage` naming the fixes that exist. **Advisory and stdout-based** — this event ignores
  exit codes and stderr, so the decision *is* the JSON; `retry` reaches the model,
  `systemMessage` the user. Counter per session+worker under `CREW_DISPATCH_DENIED_DIR`
  (test override); any path that can't count takes the no-retry branch, since an unbounded retry
  beats no retry only in theory. It gates on the `crew:` **namespace**, deliberately *not* a name
  roster — §9 only checks `bash-safety.sh`/`lane-guard.sh` rosters, so a third one here would
  drift unwatched. That also makes it inert under this repo's dev wiring, where nothing dispatches
  namespaced agents.
- No `scripts/` dir: the validator is repo tooling at the repo root
  (`scripts/validate-plugin.sh`) — it validates **all** plugins (manifests + marketplace
  description sync §2f, agent `skills:` resolution §2g, cross-plugin skill sync §4,
  cross-plugin hook sync §5, hooks.json wiring §6, hook mirror §7, turn-budget table ↔
  agent `maxTurns` lockstep §8, guard rosters ↔ agent `owns-git`/`lane-guarded` lockstep §9,
  namespaced prose refs resolving §10, `init.md` §1 slots ↔ the root CLAUDE.md crew-config
  block §11, per-agent always-loaded footprint report + opt-in `loaded-lines-cap` §12,
  agent `tools:` MCP grants server-scoped and paired across both install paths §13,
  an `## [Unreleased]` slot at the top of every changelog §2i) and is
  not shipped with this plugin. Two more repo scripts sit beside it:
  `scripts/check-changelog.sh` (the diff-based release-notes gate — its own `validate.yml` job,
  since it needs a base ref) and `scripts/release-notes.sh` (builds a release's notes;
  auto-release calls it).
- `tests/` — this plugin's hook test **cases**. The harness and runner are repo
  infrastructure at `tests/hooks/` (`lib.sh` derives the hooks directory from the calling
  test file's own path, so a suite needs no wiring; `run.sh` discovers every
  `plugins/*/tests/*.test.sh` and fails when a plugin ships `hooks/` with no suite beside it).
  Bash only — no build/LLM/network; needs only `jq`+`git`, already required by the
  hooks/validator — covering the hooks'
  **behavior**: each guard is a pure `stdin JSON → exit 0/2` function, fed crafted
  payloads and asserted on allow/block (+ stderr substring). Two hooks are deliberate
  exceptions to that shape: `turn-budget.sh` is stateful (per-instance counter file, driven
  via the `CREW_TURN_BUDGET_DIR` override — exit 2 there is a fed-back warning, not a block),
  and `format.sh` never blocks at all, so its cases assert on the stderr report and drive
  real formatter runs through fakes in `node_modules/.bin` (with `CREW_FORMAT_TIMEOUT`
  shortened for the hang case). `dispatch-denied.sh` is a third: its decision is JSON on
  `_stdout` (the harness captures both streams), so its cases assert with `jq` on
  `retry`/`systemMessage` — the load-bearing asymmetry being that only attempt 1 may ask for a
  retry. A change to a hook's logic **must add/adjust a case** here,
  on both the allow and block sides. Also self-tests the
  validator: **every** section (§1 · §2a–§2i · §3 · §4 · §5 · §6 · §7 · §8 · §9 · §10 · §11 · §12 · §13) has at least one
  negative fixture plus a silent control, and a new section lands with its fixture in the same
  commit (AGENTS.md, *Validating changes*). Asserts key on the guard's FAIL message, not the
  exit code. `changelog-gate.test.sh` covers the two release-notes scripts the same way, but
  builds repos with real commits and tags — history is their input, not a static tree.
  Runs in CI (`validate.yml` `hook-tests` job) and is shellchecked.
  Not shipped with the plugin — repo tooling.

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
- Always-loaded footprint: validator §12 reports every agent's agent-file + preloaded-skill line
  count, and enforces an optional `loaded-lines-cap: <n>` frontmatter key (`morpheus`: 518 —
  raised from 496 for `operator-voice`, itself raised from 480 for the steer contract, keeping
  ~10 lines of slack, since the figure counts preloaded
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
  agent (`morpheus`) owns git. These are the declarative half of what the guard hooks enforce
  — a new agent that omits them fails CI instead of silently getting unguarded git and no lane.

## Gotchas & release

- §2g/§4 index skills via `git ls-files` — **stage new/renamed skill files before running the
  validator** or they won't resolve.
- Validate = what CI runs: `bash scripts/validate-plugin.sh` + `bash scripts/check-changelog.sh` +
  `bash tests/hooks/run.sh` +
  `shellcheck plugins/*/hooks/*.sh plugins/*/hooks/lib/*.sh plugins/*/tests/*.sh scripts/*.sh tests/hooks/*.sh`
  (shellcheck may be missing locally; CI covers it). The shell's `*` does not cross directory
  separators, so `hooks/lib/*.sh` needs its own pattern; git's does, which is why the validator
  sees both from one `git ls-files`.
- `lane-guard.sh`'s `scan_markers` probe matches **hardcoded framework allowlists**
  (`node_backend_deps`/`frontend_deps`, used only when stacks are *unset* and no lane paths
  are set). They aren't exhaustive and drift as the ecosystem grows; a miss fails
  **silently** — the same-language ambiguity guard just doesn't fire, so tank/trinity fall
  back to extension lanes that can't tell them apart. Add new mainstream frameworks as they
  appear, **and a fixture in `tests/lane-guard.test.sh`** — it asserts one per allowlist
  entry, so an entry dropped from the hook fails a test instead of going silent.
  `scan_markers` collects every marker in **one** `find` walk (it runs inside a PreToolUse
  hook, so a walk per marker is latency the agent pays before its edit lands), and
  `detect_regime` caches the verdict per `session_id`, publishing it by `mv` so parallel
  workers sharing a session can't read a half-written cache.
- `sentinel`'s "calls no mutating MCP tool" rule is **prose, not a mechanism**: §13 rejects
  tool-scoped `mcp__server__tool` grants, so a tracker/git-host grant is necessarily the whole
  server, write tools included. What *is* mechanical is the rest of its posture — no Write, no
  Edit, no Bash. Don't describe the MCP half as enforced.
- Release: bump `version` in `.claude-plugin/plugin.json` + matching `## [X.Y.Z]` entry in
  this plugin's `CHANGELOG.md` (every plugin keeps its own changelog next to its manifest),
  folding in anything parked under `## [Unreleased]`. On merge to main, auto-release tags
  `crew/vX.Y.Z` and builds notes with `scripts/release-notes.sh` — that section plus the
  commits since the previous tag that have no entry of their own.
- A shipped change too small for its own release parks a bullet under `## [Unreleased]` rather
  than skipping the changelog: `scripts/check-changelog.sh` blocks a shipped change with no
  trace, and a bump that leaves bullets parked. Shipped = everything here except `tests/`,
  `CLAUDE.md`, `VERIFICATION.md`, and the changelog. Root `AGENTS.md` §"Releasing" has the rest.
