# crew — quick reference for agents working on this plugin

Distilled repo knowledge so sessions don't re-explore. **Keep it accurate: a PR that changes
anything stated here updates this file in the same commit.** Conventions live in the root
[AGENTS.md](../../AGENTS.md); this file is the crew-specific map.

## Map

- `agents/` — `morpheus` (orchestrator, `model: opus`, sole git owner) + workers `tank`
  (backend), `trinity` (frontend), `oracle` (unit tests), `dozer` (e2e), `seraph` (visual,
  no Bash), `neo` (express generalist). Auto-discovered; not in the manifest.
- `commands/` — `init`, `feature`, `review` (GO/NO-GO gate), `pr` (the only push/PR path),
  `address`. Namespaced `crew:*` when installed.
- `skills/` — shared + synced across plugins (crew canonical): `engineering-principles`,
  `context-discipline`, `loop-engineering`. Frontend-mode, per-stack, and per-test-tool
  skills load dynamically once resolved. Skill = `<name>/SKILL.md`, frontmatter `name:` +
  `description:` only; the `description:` carries the trigger phrases.
- `hooks/` — `bash-safety.sh` (workers blocked from git entirely; protected-branch commit
  backstop; watch/dev commands refused), `read-guard.sh` (>64 KiB raw reads), `lane-guard.sh`
  (Edit/Write lanes), `format.sh`. Wiring in `hooks/hooks.json` must mirror the repo's
  `.claude/settings.json` (validator §5).
- `scripts/validate-plugin.sh` — validates **all** plugins (manifests, agent `skills:`
  resolution §2g, cross-plugin skill sync §4, hook mirror §5).

## Schemas & conventions

- Durable run state: `<plan-dir>/plan-<feature>.md`, schema in `agents/morpheus.md`
  §"The plan file is durable state" — header `feature:`/`base-branch:`/`feature-branch:` +
  loop fields (`loop:`, `exit-conditions:`, `gate:`); steps carry
  `id:`/`status:`/`depends-on:`/`acceptance:`/`worker:`/`attempts:`/`evidence:`.
- Loop mode: generic contract in `skills/loop-engineering/SKILL.md` (shared byte-for-byte
  with keymaker); crew bindings (gate GO success, second-NO-GO cap, `/crew:pr`, neo no-op)
  in `agents/morpheus.md` §"Loop-mode bindings".
- Agent frontmatter: `skills:` is the **last** key, unqualified names, `  - name` list items
  (§2g's awk parser depends on that shape).

## Gotchas & release

- §2g/§4 index skills via `git ls-files` — **stage new/renamed skill files before running the
  validator** or they won't resolve.
- Validate = what CI runs: `bash plugins/crew/scripts/validate-plugin.sh` +
  `shellcheck plugins/*/hooks/*.sh plugins/*/scripts/*.sh` (shellcheck may be missing
  locally; CI covers it).
- Release: bump `version` in `.claude-plugin/plugin.json` + matching `## [X.Y.Z]` entry in
  the **root** `CHANGELOG.md` (crew's changelog lives at repo root; other plugins keep their
  own). On merge to main, auto-release tags `crew--vX.Y.Z` from that section.
