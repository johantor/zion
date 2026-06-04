---
name: engineering-principles
description: Core code-quality rules — YAGNI, KISS, DRY-in-moderation, small single-purpose units, clear naming, and minimal-scope diffs. Preload into implementer agents (tank, trinity) and consult during any code review. Use this whenever writing, refactoring, or reviewing code so output stays simple, readable, and free of speculative complexity.
---

# Engineering principles

Apply these to all implementation and review work. They are defaults, not dogma — when a rule conflicts with the repository's established patterns, the repository wins.

## Prime directive: match the repo
Follow the existing conventions, structure, and idioms of the codebase you are in, even where they differ from personal preference or the suggestions below. Consistency across the codebase is worth more than any single "better" local choice. Detect the conventions before writing (naming, file layout, error handling, test style) and conform.

## YAGNI — you aren't gonna need it
Build only what the current task requires. No speculative abstractions, configuration knobs, extension points, or "future-proofing" for requirements that don't exist yet. No unused parameters or dead branches kept "just in case." If it isn't needed now, don't add it now.

## KISS — keep it simple
Choose the simplest solution that fully solves the problem. Optimize for the next person who reads the code, not for cleverness. If a reviewer would need the author to explain it, simplify it.

## DRY, with judgment
Remove real duplication, but don't abstract prematurely. Wait for the rule of three before extracting shared code, and never couple unrelated things just because they currently look similar. A little duplication is cheaper than the wrong abstraction.

## Small, single-purpose units
Functions and classes should do one thing and have one reason to change. Keep them short and focused; prefer composition over inheritance; keep public surface area minimal.

## Naming and comments
Use intention-revealing names that make most comments unnecessary. Comments explain *why*, not *what*. No commented-out code and no TODO graveyards — use the issue tracker for deferred work.

## Errors
Fail fast and handle errors explicitly. Validate at boundaries. Never silently swallow exceptions or return ambiguous nulls where the caller can't tell success from failure.

## Minimal-scope diffs
Make the smallest change that solves the problem. Do not sprawl refactors into unrelated files. If you notice unrelated improvements, list them for the orchestrator instead of doing them — keep the change reviewable.

## Dependencies
Prefer the standard library and existing project dependencies. Don't add a package for something trivial.

## Performance
Clarity first; measure before optimizing. No premature optimization that hurts readability without evidence of a real bottleneck.

## Tests
Test behavior and contracts, not implementation details. Write meaningful assertions; avoid coverage theater. A test that can't fail for a real reason isn't pulling its weight.

## Before you finish
Re-read your own diff as if reviewing someone else's PR. Remove anything not needed, confirm it reads top-to-bottom, and check it follows the repo's conventions.
