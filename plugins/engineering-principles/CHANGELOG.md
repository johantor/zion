# Changelog

All notable changes to the `engineering-principles` plugin are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0] - 2026-07-18

### Added
- **New `Observability` principle.** Make failures diagnosable — log with enough context to
  locate the cause, surface errors where they'll be seen, match the repo's logging idiom, and
  keep the happy path quiet.
- **New `Backward compatibility` principle.** Don't break existing callers or data — preserve
  public signatures, serialized formats, and observable behavior unless changing them is the
  task; migrate or version deliberately when you must.

## [1.1.0] - 2026-07-18

### Added
- **New `Security` principle.** Treat external input as untrusted (validate/encode at trust
  boundaries, prefer the framework's safe API over hand-rolled escaping), never hardcode or log
  secrets, and default to least privilege. Closes the gap where the review model's security
  pillar had no matching rule in the skill.

## [1.0.1] - 2026-07-16

### Changed
- **Relicensed from MIT to Apache-2.0** (repo-wide; all plugins move together). No behavior
  change; the manifest's `license` field and the repo `LICENSE` are updated.

## [1.0.0] - 2026-06-12

### Added
- Initial standalone `engineering-principles` plugin.
- Plugin manifest under `.claude-plugin/plugin.json`.
- Standalone skill at `skills/engineering-principles/SKILL.md`, kept byte-for-byte
  in sync with the canonical copy in the `crew` plugin.
