# Changelog — keymaker

All notable changes to the `keymaker` plugin are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.0] - 2026-06-16

### Added
- **First-class, package-manager-agnostic dependency upgrades.** keymaker treated an upgrade as a
  pointer but lacked the workflow depth to do it well. Now:
  - The core `debt-taxonomy` skill gains a stack-neutral **Upgrade workflow** — risk triage by
    version delta (**SAFE** patch / **REVIEW** minor / **CAUTION** major, layered onto the existing
    tiers and behavior-sensitivity), release/migration-notes lookup for non-patch bumps (Context7,
    else the per-stack release-notes URL), apply, peer/transitive **conflict → stop**, verify, and
    **targeted revert** of the single offending package on failure. It names no package manager —
    every concrete command comes from the per-stack table, so it's agnostic by construction.
  - Each per-stack skill declares the workflow's commands per manager: `debt-taxonomy-typescript`
    covers **npm / yarn / pnpm** (discover/apply/lockfile/`ERESOLVE`/release-notes URL),
    `debt-taxonomy-dotnet` covers **NuGet** (`dotnet list package --outdated`, CPM vs per-`.csproj`
    version location, `NU1605`/`NU1107`, release-notes URL). A new manager is one row; a new
    ecosystem is a new stack skill.
  - New **`/keymaker:audit outdated`** scope — runs each detected stack's discover-outdated command
    (read-only, never installs/builds), triages each package by risk, ranks SAFE→REVIEW→CAUTION, and
    emits one `/keymaker:open <pkg> <target>` per package into the interactive picker.
  - Open mode's upgrade path applies the workflow end to end: triage, notes, conflict gate,
    risk-based acceptance (patch = build-clean; minor/major = tests-green), verify, revert.

## [0.3.0] - 2026-06-16

### Added
- **`/keymaker:audit` ends in an interactive pick.** Instead of just printing a ranked report you
  then copy-paste from, audit now relays the report and presents an `AskUserQuestion` (multi-select)
  of the top-ranked findings; the ones you select are handed to `/keymaker:open` one at a time, each
  running its own blast-radius gate and branch decisions. Picking *None* keeps the report as before,
  and a non-interactive/headless run (where the prompt auto-denies) falls back to just the report —
  unchanged behavior. The picker lives in the command's main session (the read-only audit agent
  can't prompt), and is capped at the top 3 findings since `AskUserQuestion` allows ≤4 options — the
  full ranked report is still shown, and "Other" lets you name any other pointer by hand.

## [0.2.0] - 2026-06-12

### Added
- `/keymaker:audit stale` — new first-class scope that fans out across every suppression mechanism the loaded `debt-taxonomy-<stack>` skills declare, filtered to candidates that look removable. Surfaces the cheapest wins in the repo (`@ts-expect-error` removals, `#pragma warning disable` blocks over lines with no obvious trigger, `eslint-disable-next-line` over lines that no longer match the rule) without the user having to know which family to grep for. Audit stays grep-only — `stale` reports *candidates*; final proof of staleness is left to `/keymaker:open` per finding, which can compile/build via the twin. Each per-stack skill (`debt-taxonomy-dotnet`, `debt-taxonomy-typescript`) declares its grep-only stale heuristic per mechanism, and the core `debt-taxonomy` skill documents the contract. README usage section updated. Existing scopes' behavior unchanged.

### Changed
- `/keymaker:open <pointer>` 0-findings exit is now short-circuited at the earliest point: for concrete pointer forms (`file:line`, single rule ID, package+version) a cheap pre-count runs *before* classification, gating, or twin dispatch, and exits with the existing one-liner if the count is 0. Re-running a successful `/keymaker:open` for these forms (e.g. from a `.claude/plan-*.md` checklist or a wrapper script) now skips classification entirely. Pasted output still requires classification to parse rule IDs before enumeration; the post-classification fallback exit is retained for that case.

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
