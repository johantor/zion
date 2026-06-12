# Changelog — keymaker

All notable changes to the `keymaker` plugin are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-06-12

### Added
- Initial release of the `keymaker` plugin.
- `keymaker` orchestrator agent — classifies pointers, enumerates blast radius, gates on tier/count, delegates to twins, verifies, commits per batch. Writes no production code.
- `twin` fixer/runner agent — mechanical fixer given an explicit file list and acceptance criteria; haiku model override for run-and-report verification steps.
- `/keymaker:open <pointer>` command — fix one identified suppression, rule, or dependency upgrade. Pointer forms: `file:line`, rule ID, package+version, pasted build/lint output.
- `/keymaker:audit <scope>` command — read-only scout returning a capped (~12 findings) ranked report; each finding is a ready-to-paste `/keymaker:open` invocation. Required scope: path, `backend`/`frontend`, rule family, or `diff`.
- `debt-taxonomy` skill (stack-neutral core) — stack detection, classification rubric, blast-radius gate, upgrade tiers (tier 1: single-package; tier 2: platform migration → outline only), batch commit shapes, and handoff outline format.
- `debt-taxonomy-dotnet` skill — .NET/C# suppression mechanisms, safe-removal recipes, NuGet (incl. Central Package Management) variance, and .NET upgrade-tier examples.
- `debt-taxonomy-frontend` skill — TypeScript/JS/ESLint/Biome suppression mechanisms, safe-removal recipes, npm/pnpm/yarn variance, and frontend upgrade-tier examples.
- Stack detection: the orchestrator detects the stack(s) in scope by marker file before classifying, applies the matching per-stack skill, and refuses to guess on unsupported stacks (Go, Python, Java, Rust) — asking the user instead. Adding a stack is additive: a new `debt-taxonomy-<stack>` skill plus a detection-table row.
- `context-discipline` skill — token discipline: process bulk output with scripts, surface counts and evidence pointers, never read raw output into context.
- Tier-2 handoff outline: when a pointer is a platform-scale migration, keymaker produces a morpheus-compatible `.claude/plan-<slug>.md` outline for handoff to another team or `/crew:feature`.
