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
  `limit` ≤ 2000 lines passes), `lane-guard.sh` (Edit/Write lanes), `format.sh`. Wiring in
  `hooks/hooks.json` must mirror the repo's `.claude/settings.json` (validator §7).
  `read-guard.sh` and `bash-safety.sh`'s marked shared-guard regions are byte-synced with
  keymaker's copies (validator §5; crew canonical — edit here first).
- No `scripts/` dir: the validator is repo tooling at the repo root
  (`scripts/validate-plugin.sh`) — it validates **all** plugins (manifests + marketplace
  description sync §2f, agent `skills:` resolution §2g, cross-plugin skill sync §4,
  cross-plugin hook sync §5, hooks.json wiring §6, hook mirror §7) and is not shipped
  with this plugin.
- `tests/` — bash suite (no build/LLM/network; needs only `jq`+`git`, already required by the
  hooks/validator; `run.sh` drives `*.test.sh`, `lib.sh` is the harness) covering the hooks'
  **behavior**: each is a pure `stdin JSON → exit 0/2` guard, fed crafted
  payloads and asserted on allow/block (+ stderr substring). A change to a hook's guard logic
  **must add/adjust a case** here, on both the allow and block sides. Also self-tests the
  validator (§2h/§2g/§4 bite). Runs in CI (`validate.yml` `hook-tests` job) and is shellchecked.
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
  (§2g's awk parser depends on that shape).

## Gotchas & release

- §2g/§4 index skills via `git ls-files` — **stage new/renamed skill files before running the
  validator** or they won't resolve.
- Validate = what CI runs: `bash scripts/validate-plugin.sh` +
  `shellcheck plugins/*/hooks/*.sh scripts/*.sh` (shellcheck may be missing
  locally; CI covers it).
- `lane-guard.sh`'s `has_node_backend`/`has_frontend` probes match **hardcoded framework
  allowlists** (used only when stacks are *unset* and no lane paths are set). They aren't
  exhaustive and drift as the ecosystem grows; a miss fails **silently** — the same-language
  ambiguity guard just doesn't fire, so tank/trinity fall back to extension lanes that can't
  tell them apart. Add new mainstream frameworks as they appear. Once #128's hook test suite
  lands, add a fixture per framework so a missing entry becomes a failing test, not a silent gap.
- Release: bump `version` in `.claude-plugin/plugin.json` + matching `## [X.Y.Z]` entry in
  this plugin's `CHANGELOG.md` (every plugin keeps its own changelog next to its manifest).
  On merge to main, auto-release tags `crew/vX.Y.Z` from that section.
