---
name: engineering-principles
description: Core code-quality rules — YAGNI, KISS, DRY with judgment, small single-purpose units, clear naming, minimal-scope diffs. Preload into implementer agents and consult during any code review. Use whenever writing, refactoring, or reviewing code.
---

# Engineering principles
Defaults, not dogma — when a rule conflicts with the repo's established patterns, the repo wins.

- **Match the repo.** Follow existing conventions, structure, and idioms even over personal preference. Consistency beats local "better".
- **YAGNI.** Build only what the task needs. No speculative abstractions, config knobs, unused params, or "future-proofing". Delete dead code.
- **KISS.** Simplest solution that works; optimize for the next reader, not cleverness.
- **DRY with judgment.** Rule of three before abstracting; a little duplication beats the wrong abstraction; don't couple unrelated code that merely looks similar.
- **Small units.** One thing, one reason to change; short functions; composition over inheritance; minimal public surface.
- **Naming/comments.** Intention-revealing names; comments explain *why*, not *what*; no commented-out code; no TODO graveyards.
- **Errors.** Fail fast, handle explicitly, validate at boundaries; never silently swallow.
- **Minimal-scope diffs.** Smallest change that solves the problem; don't sprawl refactors into unrelated files; list unrelated improvements instead of doing them.
- **Dependencies.** Prefer stdlib/existing deps; don't add a package for something trivial.
- **Reach for new code last.** Before writing any, walk this in order and stop at the first that resolves it (always subordinate to *match the repo* — the house pattern wins over a shorter clever one):
  1. Is it actually needed? If not, don't build it.
  2. Does the standard library or runtime already do it? Use that.
  3. Does a native platform/framework feature cover it? Use that.
  4. Does an already-installed dependency solve it? Use that.
  5. Can it collapse to a line or two without hurting readability? Do that.
  6. Only then write new code — the minimum that works. When two equal-size options exist, take the one that handles the edge cases.
- **Performance.** Clarity first; measure before optimizing.
- **Tests.** Test behavior, not implementation; meaningful assertions; no coverage theater.
- **Before finishing.** Re-read your diff as a reviewer; remove anything unneeded; confirm it follows repo conventions.
