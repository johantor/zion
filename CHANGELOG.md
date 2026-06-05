# Changelog

All notable changes to the `crew` plugin are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2026-06-05

### Changed
- **`trinity` now owns the full client/presentation layer**, not just React/Redux/SCSS:
  it explicitly covers vanilla JS, HTML, and CSS, and — in **server-rendered** mode — the
  *markup/DOM* inside Razor views (structure, classes, ARIA, presentation). The C#/
  server-side of Razor (view-model binding, `@functions`/`@code`, data access) remains
  `tank`'s; the split is by concern, coordinated between the two. In **headless** mode
  `trinity` still never touches Razor.
- `lane-guard` updated to match: `.cshtml` is no longer denied to `trinity` (Razor is now
  shared by concern, prompt-enforced), and `tank` is now denied `*.js`/`*.mjs`/`*.html` in
  addition to the TS/JSX/SCSS/CSS it already couldn't edit.
- `tank`, `frontend-server-rendered`, and `CLAUDE.md` updated to describe the concern-split
  Razor ownership.

### Added
- **`morpheus` now resolves the frontend mode** instead of requiring it pinned in `CLAUDE.md`:
  it uses a `CLAUDE.md` override if present, else its own (local) memory, else asks the user
  and remembers the answer — then passes the resolved mode into every frontend delegation.
  `trinity` takes the mode from the delegation rather than reading `CLAUDE.md` itself.
  `CLAUDE.md`'s **Frontend mode** is now optional.

## [1.0.2] - 2026-06-05

### Changed
- **Repo restructured into a monorepo marketplace.** The `crew` plugin now lives in
  `plugins/crew/` (its own plugin root) instead of the repo root, and
  `marketplace.json` points at it via `source: "./plugins/crew"`. Adding future
  plugins is now additive (`plugins/<name>/` + a marketplace entry) with no
  collision between each plugin's `agents/`/`commands/`/`skills/`/`hooks/`.
  The installed plugin's components are unchanged — same agents, commands, and hooks.
- `validate-plugin.sh` now validates every plugin under `plugins/*`, and CI globs
  were updated accordingly.

### Added
- Per-plugin `plugins/crew/README.md`; the root `README.md` is now a marketplace
  overview with a plugin index.

## [1.0.1] - 2026-06-05

### Fixed
- **Agents now actually load when installed.** Declaring `agents` in the manifest
  (string or array) passed install validation but the agents were never discovered
  (`plugin details` reported 0). Agents now live in a root `agents/` directory and
  are auto-discovered, matching the convention used by Anthropic's own plugins.
  `plugin details` now reports all six (`morpheus`, `tank`, `trinity`, `oracle`,
  `dozer`, `seraph`).
- `validate-plugin.sh` validates array-shaped manifest fields, checks the root
  `agents/` directory, and tolerates CRLF checkouts.

### Changed
- **Commands renamed** to drop the redundant `zion-` prefix, since installed
  components are already namespaced under the plugin: `/zion-feature` → `/crew:feature`,
  `/zion-review` → `/crew:review`, `/zion-ship` → `/crew:ship`. **Breaking** for anyone
  scripting the old command names.
- `CLAUDE.md` expanded from a crew-config stub into a full project memory file.
- `.github/copilot-instructions.md` aligned with the crew reviewer (engineering-principles
  checklist + code/security/design pillars) and now requires PRs that change plugin
  behavior to bump `version` and add a changelog entry.

### Added
- `.gitattributes` enforcing LF line endings for all text files, so shell hooks/scripts
  stay valid on Linux CI and as plugin hooks.
- This `CHANGELOG.md`.

## [1.0.0]

### Added
- Initial release: orchestrated crew of agents (`morpheus`, `tank`, `trinity`,
  `oracle`, `dozer`, `seraph`), commands, skills (`engineering-principles`,
  `context-discipline`, `frontend-headless`, `frontend-server-rendered`), and hooks
  (lane guard, read guard, bash safety, formatter).

[1.1.0]: https://github.com/johantor/zion-link/compare/crew--v1.0.2...crew--v1.1.0
[1.0.2]: https://github.com/johantor/zion-link/compare/crew--v1.0.1...crew--v1.0.2
[1.0.1]: https://github.com/johantor/zion-link/compare/crew--v1.0.0...crew--v1.0.1
[1.0.0]: https://github.com/johantor/zion-link/releases/tag/crew--v1.0.0
