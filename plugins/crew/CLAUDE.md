# crew — quick reference for agents working on this plugin

Distilled repo knowledge so sessions don't re-explore. **Keep it accurate: a PR that changes
anything stated here updates this file in the same commit.** Conventions live in the root
[AGENTS.md](../../AGENTS.md); this file is the crew-specific map.

## Map

- `agents/` — `morpheus` (orchestrator, `model: opus`, sole git owner) + workers `tank`
  (backend), `trinity` (frontend), `oracle` (unit tests), `dozer` (e2e), `seraph` (visual,
  no Bash), `neo` (express generalist). Auto-discovered; not in the manifest.
- `commands/` — `init`, `feature`, `review` (GO/NO-GO gate), `pr` (the only push/PR path),
  `address`, `loop` (outer-loop driver: re-launches `morpheus` directly each tick — not by
  nesting `/crew:feature` — on the native `/loop` dynamic mode until the plan's exit
  conditions/iteration cap are met; wrapper owns scheduling). Namespaced `crew:*` when installed.
- `skills/` — shared + synced across plugins (crew canonical): `engineering-principles`,
  `context-discipline`, `loop-engineering`. Frontend-mode, per-stack, and per-test-tool
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
  `read-guard.sh` and `bash-safety.sh`'s marked shared-guard regions are byte-synced with
  keymaker's copies (validator §5; crew canonical — edit here first).
  `format.sh` runs every formatter under a wall-clock bound (`CREW_FORMAT_TIMEOUT`,
  default 20s) via `timeout`/`gtimeout`, degrading to an unbounded run where neither
  exists (stock macOS/BSD); a hang is reported distinctly from a formatter that failed.
- No `scripts/` dir: the validator is repo tooling at the repo root
  (`scripts/validate-plugin.sh`) — it validates **all** plugins (manifests + marketplace
  description sync §2f, agent `skills:` resolution §2g, cross-plugin skill sync §4,
  cross-plugin hook sync §5, hooks.json wiring §6, hook mirror §7, turn-budget table ↔
  agent `maxTurns` lockstep §8, guard rosters ↔ agent `owns-git`/`lane-guarded` lockstep §9,
  namespaced prose refs resolving §10, `init.md` §1 slots ↔ the root CLAUDE.md crew-config
  block §11, per-agent always-loaded footprint report + opt-in `loaded-lines-cap` §12) and is
  not shipped with this plugin.
- `tests/` — bash suite (no build/LLM/network; needs only `jq`+`git`, already required by the
  hooks/validator; `run.sh` drives `*.test.sh`, `lib.sh` is the harness) covering the hooks'
  **behavior**: each guard is a pure `stdin JSON → exit 0/2` function, fed crafted
  payloads and asserted on allow/block (+ stderr substring). Two hooks are deliberate
  exceptions to that shape: `turn-budget.sh` is stateful (per-instance counter file, driven
  via the `CREW_TURN_BUDGET_DIR` override — exit 2 there is a fed-back warning, not a block),
  and `format.sh` never blocks at all, so its cases assert on the stderr report and drive
  real formatter runs through fakes in `node_modules/.bin` (with `CREW_FORMAT_TIMEOUT`
  shortened for the hang case). A change to a hook's logic **must add/adjust a case** here,
  on both the allow and block sides. Also self-tests the
  validator: **every** section (§1 · §2a–§2h · §3 · §4 · §5 · §6 · §7 · §8 · §9 · §10 · §11 · §12) has at least one
  negative fixture plus a silent control, and a new section lands with its fixture in the same
  commit (AGENTS.md, *Validating changes*). Asserts key on the guard's FAIL message, not the
  exit code. Runs in CI (`validate.yml` `hook-tests` job) and is shellchecked.
  Not shipped with the plugin — repo tooling.

## Schemas & conventions

- Durable run state: `<plan-dir>/plan-<feature>.md`, schema in `agents/morpheus.md`
  §"The plan file is durable state" — header `feature:`/`base-branch:`/`feature-branch:` +
  inner-loop fields (`loop:`, `exit-conditions:`, `gate:`) + outer-loop bookkeeping
  (`iterations: n/max`, `in-flight:`, written by the `/crew:loop` wrapper, not morpheus);
  steps carry `id:`/`status:`/`depends-on:`/`acceptance:`/`worker:`/`attempts:`/`evidence:`.
- Loop mode: generic contract in `skills/loop-engineering/SKILL.md` (shared byte-for-byte
  with keymaker; inner loop + a note that the outer loop is a main-session wrapper); crew
  bindings (gate GO success, second-NO-GO cap, `/crew:pr`, neo no-op) in `agents/morpheus.md`
  §"Loop-mode bindings". The outer loop is `commands/loop.md`.
- Agent frontmatter: `skills:` is the **last** key, unqualified names, `  - name` list items
  (§2g's awk parser reads the `  - name` items; it stops at the next key, so the last-key rule
  is convention, not a parser constraint).
- Always-loaded footprint: validator §12 reports every agent's agent-file + preloaded-skill line
  count, and enforces an optional `loaded-lines-cap: <n>` frontmatter key (`morpheus`: 480).
  Rationale for the prompts themselves lives in the root `AGENTS.md` §"Prompt design rationale" —
  agent prompts carry instruction, not justification; each trimmed prompt points there once.
- Agent write-access declarations, checked by validator §9 (see below): every crew agent
  carries `owns-git: true|false` and `lane-guarded: true|false` before `skills:`. Exactly one
  agent (`morpheus`) owns git. These are the declarative half of what the guard hooks enforce
  — a new agent that omits them fails CI instead of silently getting unguarded git and no lane.

## Gotchas & release

- §2g/§4 index skills via `git ls-files` — **stage new/renamed skill files before running the
  validator** or they won't resolve.
- Validate = what CI runs: `bash scripts/validate-plugin.sh` + `bash plugins/crew/tests/run.sh` +
  `shellcheck plugins/*/hooks/*.sh plugins/*/tests/*.sh scripts/*.sh` (shellcheck may be missing
  locally; CI covers it).
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
- Release: bump `version` in `.claude-plugin/plugin.json` + matching `## [X.Y.Z]` entry in
  this plugin's `CHANGELOG.md` (every plugin keeps its own changelog next to its manifest).
  On merge to main, auto-release tags `crew/vX.Y.Z` from that section.
