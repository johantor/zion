---
name: engineering-principles
description: Core code-quality rules — YAGNI, KISS, DRY-in-moderation, small single-purpose units, clear naming, minimal-scope diffs. Preload into implementer agents and consult during any code review. Use whenever writing, refactoring, or reviewing code.
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
- **Performance.** Clarity first; measure before optimizing.
- **Tests.** Test behavior, not implementation; meaningful assertions; no coverage theater.
- **Before finishing.** Re-read your diff as a reviewer; remove anything unneeded; confirm it follows repo conventions.
