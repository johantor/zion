# Copilot instructions for guided reviews

These instructions mirror how the Zion Link crew reviews code (`/zion-review` plus the
`engineering-principles` skill). Reviews look at three pillars — **code quality**,
**security**, and **design conformance** — and classify every finding by severity.

When asked to review changes in this repository, use this sequence:

1. Review only changed files first, then expand to impacted neighbors when needed.
2. Classify findings by severity:
   - **Blocking**: must fix before merge (bugs, security flaws, broken behavior, missing required tests).
   - **Warnings**: should fix soon (maintainability or clarity risks).
   - **Passed**: checks that were explicitly reviewed and look good.
3. Evaluate code quality against the `engineering-principles` skill
   (`.claude/skills/engineering-principles/`). These are defaults, not dogma —
   when a rule conflicts with the repo's established patterns, the repo wins:
   - **Match the repo**: follow existing conventions, structure, and idioms.
   - **YAGNI**: no speculative abstractions, unused params, or future-proofing; flag dead code.
   - **KISS**: simplest solution that works; optimize for the next reader.
   - **DRY with judgment**: rule of three before abstracting; don't couple unrelated lookalikes.
   - **Small units & clear naming**: one reason to change; intention-revealing names; comments explain *why*.
   - **Errors**: fail fast, validate at boundaries, never silently swallow.
   - **Minimal-scope diffs**: smallest change that solves the problem; no unrelated sprawl.
4. Always include a security pass:
   - Input validation, auth/authorization checks, secrets exposure, injection risks,
     unsafe deserialization, open redirects, and dependency risk.
5. Cover design conformance when UI changes are involved:
   - Layout, spacing, color, typography, and component states versus the design reference.
6. Prefer concrete, actionable feedback:
   - Point to exact files/areas and describe expected behavior.
   - Suggest minimal-scope fixes over broad rewrites.
7. Call out test coverage impact:
   - Identify missing or weak tests for behavior changes; test behavior, not implementation.
   - Mark test-only issues as warnings unless they hide a correctness gap.
8. Avoid noise:
   - Do not block on style-only nits unless they violate existing repository conventions.

Repo-specific note: this repository is a Claude Code plugin (shell hooks, Markdown
agent/command/skill definitions, JSON manifests) with no application build. Hold shell
hooks to shellcheck-clean standards, and check that `.claude-plugin` manifests stay
valid (`bash .claude/scripts/validate-plugin.sh`).

Versioning: when a PR changes plugin behavior — agents, commands, skills, hooks, or the
manifest — it must bump `version` in `.claude-plugin/plugin.json` (semver: patch for fixes,
minor for additive features, major for breaking changes) and add a matching `CHANGELOG.md`
entry. Users only receive changes via `claude plugin update`, which keys on `version`, so an
unbumped version ships silently. Flag a missing bump/changelog entry as a **Warning**
(or **Blocking** if it would prevent users from receiving a fix). Pure docs/CI/test-only
changes that don't affect installed behavior do not require a bump.

For review responses, use this exact heading structure:

## Blocking

## Warnings

## Passed

If an observation is informational-only and not actionable, place it in `## Passed` with a short rationale.
