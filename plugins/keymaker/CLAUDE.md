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
  `context-discipline`, `loop-engineering` and `operator-voice` (crew's copies are canonical —
  edit there and copy byte-for-byte, or CI's drift check fails). `operator-voice` is preloaded by
  the `keymaker` agent, not by `twin`, which reports to `keymaker` rather than to the operator.
- `hooks/` — `bash-safety.sh`, `read-guard.sh`, `write-guard.sh` (keymaker's Write/Edit confined
  to `.claude/`), and the sourced `lib/guard-lib.sh` (not executable, not wired, §3/§6), vendored
  so a standalone install enforces the same floor.
  - Sync: `read-guard.sh` and `lib/guard-lib.sh` are byte-identical with crew's, and the marked
    `bash-safety.sh` region matches (§5). Crew is canonical: edit there, mirror here.
  - The floor lets any agent run a plain `git mv` (a later line counts; `-f` and bare `mv`/`cp`
    stay refused). Below the region, the twin block calls
    `guard_block_git_mv_handback "$git_owner"` (`git_owner=keymaker`, first line only), so crew's
    `morpheus` is not refused when both plugins are installed.
- `tests/` — `bash-safety`, `read-guard`, `write-guard` cases, run by `tests/hooks/run.sh`. They
  test keymaker's own copies, so a vendored library that stops loading fails here. Not shipped.
- No `scripts/` dir: the repo-root validator covers this plugin too.

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
- Justified suppressions (0.8.0, #52): sites with a native justification are excluded from the
  audit report (still counted) and from `open`'s working set; `--force` overrides. Slots are
  declared per stack in `debt-taxonomy-<stack>`, rules in core `debt-taxonomy`. `stale` scope
  ignores the filter; skipped tests are never excluded. Twins must never *add* a justification
  (keymaker.md step 8 checks against the dispatch snapshot).
- MCP grants come in pairs: `mcp__context7` and `mcp__plugin_context7_context7` (§13).
- Footprint: `keymaker` has `loaded-lines-cap: 670` (§12; `debt-taxonomy`'s 203 lines dominate).
  Prompt rationale lives in AGENTS.md, "Prompt design rationale".

## Gotchas & release

- Stage new/renamed skill files before running the validator (`git ls-files`-based indexes).
- Status: **Beta**. `1.0.0` = the `VERIFICATION.md` matrix green end-to-end for one stack (TS in
  flight), full pipeline included. Criteria: README, "Graduation to Stable".
- Release: bump `.claude-plugin/plugin.json` + a matching `## [X.Y.Z]` in `CHANGELOG.md`, folding
  in `## [Unreleased]`. Auto-release tags `keymaker/vX.Y.Z` on merge. Bump by default: a changed
  verdict or reworded refusal is a patch. Only an unobservable change parks under
  `[Unreleased]`. Shipped = all but `tests/`, `CLAUDE.md`, `VERIFICATION.md`, the changelog.
  Details: AGENTS.md, "Releasing".
- **Changelog entries: one line, two at most**, what changed. The why goes in the commit.
