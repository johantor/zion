# Changelog

All notable changes to the `crew` plugin are documented here. This project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.5.0]

### Changed

- Builds are now a **final gate, not a per-step check**. `tank` and `trinity` no longer run
  the full backend/frontend build as a routine self-check on every change; they defer it to
  `morpheus` and verify their work with reasoning, targeted reads, and the lint/edit loop.
- `morpheus` holds the build (and full test suites) until the work queue is fully drained —
  every plan step accepted and any newly added review comments or fixes folded in and
  resolved — so a single build covers all the work instead of re-running per round-trip.
- `morpheus` runs that build isolated from any running app/dev process (so it can't interfere
  or contend on locked build outputs), but in one dedicated build location reused for the
  whole session — not per agent or per step — so incremental and package caches stay warm.
