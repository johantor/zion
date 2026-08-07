# keymaker — quick reference for agents working on this plugin

Distilled repo knowledge so sessions don't re-explore. **Keep it accurate: a PR that changes
anything stated here updates this file in the same commit.** Conventions live in the root
[AGENTS.md](../../AGENTS.md); this file is the keymaker-specific map.

## Map

- `agents/` — `keymaker` (orchestrator, `model: opus`, owns classify→gate→delegate→verify→
  commit; writes no production code) + `twin` (mechanical fixer/verifier, `model: sonnet`,
  never runs git).
- `commands/` — `audit` (read-only scout, required scope, ranked report + interactive
  multi-pick that hands each pick to open) and `open` (fix one pointer; runs foreground so
  gates can prompt). There is **no push/PR command — the flow ends at commit.**
- `skills/` — `debt-taxonomy` (stack-neutral core: rubric, blast-radius gate, commit shapes)
  + `debt-taxonomy-dotnet`/`-typescript` (per-stack), plus shared synced copies of
  `context-discipline` and `loop-engineering` (crew's copies are canonical — edit there and
  copy byte-for-byte, or CI's drift check fails).
- `hooks/` — `bash-safety.sh`, `read-guard.sh`, `write-guard.sh` (keymaker's Write/Edit are
  confined to `.claude/` — ledger/outlines/notes only). `read-guard.sh` (byte-identical) and
  `bash-safety.sh`'s marked shared-guard regions are synced with crew's copies (crew is
  canonical — edit there and mirror here, or validator §5 fails CI). No `scripts/` dir: the
  validator is repo tooling at `scripts/validate-plugin.sh` and covers this plugin too.

## Schemas & conventions

- Durable run state: `.claude/debt-<slug>.md` batch ledger, schema in `agents/keymaker.md`
  §"The batch ledger is durable state" — header `pointer:`/`base-branch:`/`work-branch:` +
  loop fields (`loop:`, `exit-conditions:`); batches carry
  `id:`/`status:`/`lane:`/`acceptance:`/`attempts:`/`evidence:`. Distinct from the one-shot
  tier-2 handoff outline `.claude/plan-<slug>.md`.
- Retry cap: 3 fix→verify round-trips per batch (keymaker.md step 8), recorded in `attempts:`
  as each rejection happens; third failure → `status: blocked` with attempt history in
  `evidence:`.
- Loop mode: generic contract in the shared `loop-engineering` skill; keymaker bindings
  (unit = batch/pointer, terminal gate = verify + commit, gates that stop the loop) in
  `agents/keymaker.md` §"Loop-mode bindings".
- Acknowledgement gates (stop-and-ask): no-test warning on behavior-sensitive/upgrade
  batches, >40-findings slice choice, tier-2 offer, transitive/peer package conflicts.
- Justified suppressions (0.8.0, was #52): keymaker **reads** the mechanism's native
  justification slot and excludes those sites from the audit report (counted in totals) and from
  `open`'s working set / blast radius; `--force` overrides. No ack command, no custom token — the
  slots are declared per mechanism in each `debt-taxonomy-<stack>` skill, the rules in core
  `debt-taxonomy` §"Justified suppressions". Exemptions that are load-bearing: `stale` scope
  ignores the filter, and skipped tests are never excluded. Twins must never *add* a
  justification (it would hide the finding) — keymaker.md step 8 checks for it against the
  dispatch snapshot.
- Always-loaded footprint: `keymaker` declares `loaded-lines-cap: 670` (validator §12 reports
  every agent's agent-file + preloaded-skill lines and fails CI past the cap; `debt-taxonomy`'s
  203 lines dominate it). Rationale for the prompt's rules lives in the root `AGENTS.md`
  §"Prompt design rationale" — the prompt carries instruction and points there once.

## Gotchas & release

- Stage new/renamed skill files before running the validator (`git ls-files`-based indexes).
- Status: **Beta** until v1.0. Graduation criteria live in the README's *Graduation to Stable*
  section — v1.0 = the verification matrix green end-to-end for **one** supported stack (TS is in
  flight; .NET follows post-v1.0), covering the full pipeline, not just the read-only rows.
  Flipping to Stable is the `1.0.0` release.
- Release: bump `version` in `.claude-plugin/plugin.json` + matching `## [X.Y.Z]` entry in
  `plugins/keymaker/CHANGELOG.md` (every plugin keeps its own changelog next to its
  manifest). Auto-release tags `keymaker/vX.Y.Z` on merge.
