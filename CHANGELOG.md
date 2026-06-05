# Changelog

All notable changes to the `crew` plugin are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.1] - 2026-06-05

### Fixed
- `claude plugin install` failed with `agents: Invalid input`. The `agents`
  manifest field requires an array of individual file paths, not a directory
  string; it is now declared as an explicit array of the six agent files (#14).
- `validate-plugin.sh` now validates array-shaped manifest fields (not just
  strings) and tolerates CRLF checkouts (#14).

### Added
- `.gitattributes` enforcing LF line endings for all text files, so shell
  hooks/scripts stay valid on Linux CI and as plugin hooks.

### Changed
- `CLAUDE.md` expanded from a crew-config stub into a full project memory file.
- `.github/copilot-instructions.md` aligned with the crew reviewer
  (engineering-principles checklist + code/security/design pillars) (#14).

## [1.0.0]

### Added
- Initial release: orchestrated crew of agents (`morpheus`, `tank`, `trinity`,
  `oracle`, `dozer`, `seraph`), commands (`/zion-feature`, `/zion-review`,
  `/zion-ship`), skills (`engineering-principles`, `context-discipline`,
  `frontend-headless`, `frontend-server-rendered`), and hooks (lane guard,
  read guard, bash safety, formatter).

[1.0.1]: https://github.com/johantor/zion-link/compare/crew--v1.0.0...crew--v1.0.1
[1.0.0]: https://github.com/johantor/zion-link/releases/tag/crew--v1.0.0
