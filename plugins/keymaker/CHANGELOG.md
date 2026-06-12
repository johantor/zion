# Changelog — keymaker

All notable changes to the `keymaker` plugin are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.3] - 2026-06-12

### Changed
- `/keymaker:open <pointer>` 0-findings exit is now short-circuited at the earliest point: for concrete pointer forms (`file:line`, single rule ID, package+version) a cheap pre-count runs *before* classification, gating, or twin dispatch, and exits with the existing one-liner if the count is 0. Re-running a successful `/keymaker:open` (e.g. from a `.claude/plan-*.md` checklist, a wrapper script, or pasted build output that's already been resolved) now skips classification entirely. The exit contract — pointer parsed → enumeration → if 0, exit one-liner; only then classify/gate/dispatch — is documented explicitly in `commands/open.md` and mirrored in `agents/keymaker.md`. The post-classification fallback exit is retained for pointer forms where pre-count isn't possible (pasted output that parses to multiple rule IDs and requires per-rule enumeration).

## [0.1.2] - 2026-06-12

### Changed
- `/keymaker:open <pointer>` 0-findings exit is now a single one-line status that folds "what was checked" into the same line (e.g. `No findings for CS8602 — nothing to do (grep count 0).`), instead of a two-sentence message. Keeps the idempotent re-run path truly one-line in both the orchestrator agent (`agents/keymaker.md`) and the command (`commands/open.md`).

## [0.1.1] - 2026-06-12

### Changed
- `/keymaker:open <pointer>` is now idempotent: when blast-radius enumeration finds 0 findings (suppression already removed, rule already silent, package already at target version), the orchestrator exits with a one-line "nothing to do" message before gating, branching, or dispatching twins. Re-running a successful `open` is now a safe no-op, making the command safe to script-wrap and safe to leave in checklists.

## [0.1.0] - 2026-06-12

### Added
- Initial release of the `keymaker` plugin.
- `keymaker` orchestrator agent — classifies pointers, enumerates blast radius, gates on tier/count, delegates to twins, verifies, commits per batch. Writes no production code.
- `twin` fixer/runner agent — mechanical fixer given an explicit file list and acceptance criteria; haiku model override for run-and-report verification steps.
- `/keymaker:open <pointer>` command — fix one identified suppression, rule, or dependency upgrade. Pointer forms: `file:line`, rule ID, package+version, pasted build/lint output.
- `/keymaker:audit <scope>` command — read-only scout returning a capped (~12 findings) ranked report; each finding is a ready-to-paste `/keymaker:open` invocation. Required scope: path, `backend`/`frontend`, rule family, or `diff`.
- `debt-taxonomy` skill (stack-neutral core) — stack detection, classification rubric, blast-radius gate, upgrade tiers (tier 1: single-package; tier 2: platform migration → outline only), batch commit shapes, and handoff outline format.
- `debt-taxonomy-dotnet` skill — .NET/C# suppression mechanisms, safe-removal recipes, NuGet (incl. Central Package Management) variance, and .NET upgrade-tier examples.
- `debt-taxonomy-typescript` skill — TypeScript/JS/ESLint/Biome suppression mechanisms, safe-removal recipes, npm/pnpm/yarn variance, and upgrade-tier examples. Covers any JS/TS project (React frontend or Node backend/CLI), not just frontend.
- Stack detection: the orchestrator detects the stack(s) in scope by marker file before classifying, applies the matching per-stack skill, and refuses to guess on unsupported stacks (Go, Python, Java, Rust) — asking the user instead. Adding a stack is additive: a new `debt-taxonomy-<stack>` skill plus a detection-table row.
- `context-discipline` skill — token discipline: process bulk output with scripts, surface counts and evidence pointers, never read raw output into context.
- Tier-2 handoff outline: when a pointer is a platform-scale migration, keymaker produces a morpheus-compatible `.claude/plan-<slug>.md` outline for handoff to another team or `/crew:feature`.
- Behavior-sensitivity tagging: every finding is tagged behavior-preserving (lint/compile-clean is sufficient) or behavior-sensitive (acceptance gate must be tests-green). Behavior-sensitive rules — React `rules-of-hooks`/`exhaustive-deps`, C# null-guard fixes — are listed per stack. Behavior-sensitive batches commit one logical unit at a time, and the no-test-suite warning fires for them (not just upgrades). Twins do the structural refactor when delegated and report the behavioral change for the orchestrator to judge.
- Stack skills are named by ecosystem/language (`debt-taxonomy-dotnet`, `debt-taxonomy-typescript`), separate from the `backend`/`frontend` lane vocabulary — so the TypeScript taxonomy applies to a Node backend/CLI, not just a React frontend.
- README "Adding a stack" section documents the authoring contract for a new per-stack taxonomy skill: required sections (suppression mechanisms + safe-removal recipes, behavior sensitivity, package-manager variance, upgrade tiers), the detection-table row, the two agent wirings, and validation — no orchestrator/twin logic changes needed.
