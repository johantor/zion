# Changelog

All notable changes to the `crew` plugin are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0] - 2026-06-05

### Added
- **Git workflow.** `morpheus` now owns version control: it resolves the project's **base
  branch** and **branch-naming** convention (`CLAUDE.md` crew config → memory → ask),
  creates a feature branch off the base, and commits each *verified* step. Workers never run
  git. New `CLAUDE.md` crew-config slots: **Base branch**, **Branch naming**.
- **`/crew:pr` command** — pushes the feature branch and opens a pull request via a git-host
  MCP (GitHub / Azure DevOps), host-agnostic, with confirmation; falls back to printing the
  `git push` command + a ready-to-paste PR body when no host MCP is present. The crew still
  stops at the local ship gate by default; push/PR is this explicit step.
- **`bash-safety` refuses `git commit` on a protected base branch** (`main`/`master`/`develop`)
  — the crew branches first. (Applies to every Bash command, including the main session.)

## [1.1.3] - 2026-06-05

### Fixed
- **`morpheus` could not delegate to workers when installed** ("Agent type 'tank' not
  found"). Installed plugin agents are namespaced, so `morpheus` now delegates to and
  allowlists `crew:tank` / `crew:trinity` / `crew:oracle` / `crew:dozer` / `crew:seraph`,
  and its launch hint is `claude --agent crew:morpheus`.
- **Hardened `morpheus` against improvising.** Planning/delegation/synthesis are its only
  outputs; if a delegation can't be launched it must stop and report rather than copy files,
  invent project conventions, or do the worker's job itself.

## [1.1.2] - 2026-06-05

Addresses findings from a review by Anthropic's `plugin-dev` agents (plugin-validator,
skill-reviewer) and a best-practice review of the agents/hooks.

### Fixed
- **`dozer` could not create new test files** — it authors Cypress specs but its tools
  listed only `Edit`, not `Write`. Added `Write` (lane-guard already confines it to
  `cypress/**`/spec paths).
- `read-guard.sh`: replaced a fragile mixed `||`/`&&` line with an explicit `if`, and
  documented that this guard intentionally fails open (it's context-hygiene, not security).
- `format.sh`: read the hook payload once (it previously risked consuming stdin twice).

### Changed
- **`format.sh` is now project-aware.** For backend it scopes `dotnet format` to the changed
  file instead of the whole solution (slow on large repos). For frontend it discovers the
  project's own format/fix script from `package.json` (e.g. `format`, `format:fix`,
  `lint:fix`, `biome:format`) by preference order rather than guessing, and skips when the
  repo only exposes check-only scripts. Added a `timeout` to the format hook in `hooks.json`.
- **`seraph` is now strictly read-only**: removed its `memory: local` and the stale
  "memory edits allowed" rule (it has no write tools), and dropped its now-unreachable
  `lane-guard` entry.
- `dozer` `color: orange` → `magenta` (orange isn't in the documented agent palette).
- Added keyword triggers to the `frontend-headless` / `frontend-server-rendered` skill
  descriptions so they trigger outside crew preload too; aligned the `engineering-principles`
  description wording ("DRY with judgment").

## [1.1.1] - 2026-06-05

### Fixed
- **Hooks no longer fail to load with "Duplicate hooks file detected."** The standard
  `hooks/hooks.json` at the plugin root is auto-loaded, but the manifest also declared
  `"hooks": "./hooks/hooks.json"`, so it was loaded twice. Removed the `hooks` field from
  `plugin.json` (the manifest's `hooks` is only for *additional* hook files).
- `validate-plugin.sh` now rejects only the auto-loaded `hooks/hooks.json` in the manifest
  (additional hook files are still allowed and existence-checked) and asserts the root
  `hooks/hooks.json` is present.

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

[1.2.0]: https://github.com/johantor/zion-link/compare/crew--v1.1.3...crew--v1.2.0
[1.1.3]: https://github.com/johantor/zion-link/compare/crew--v1.1.2...crew--v1.1.3
[1.1.2]: https://github.com/johantor/zion-link/compare/crew--v1.1.1...crew--v1.1.2
[1.1.1]: https://github.com/johantor/zion-link/compare/crew--v1.1.0...crew--v1.1.1
[1.1.0]: https://github.com/johantor/zion-link/compare/crew--v1.0.2...crew--v1.1.0
[1.0.2]: https://github.com/johantor/zion-link/compare/crew--v1.0.1...crew--v1.0.2
[1.0.1]: https://github.com/johantor/zion-link/compare/crew--v1.0.0...crew--v1.0.1
[1.0.0]: https://github.com/johantor/zion-link/releases/tag/crew--v1.0.0
