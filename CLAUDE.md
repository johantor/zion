# Zion — Claude Code notes

Zion is a Claude Code plugin marketplace (`crew`, `keymaker`):
orchestrated agents, commands, hooks, and skills. **This repository *is* the plugins** —
there is no application code to build or ship.

**Start with [AGENTS.md](AGENTS.md)** — the contributor guide (repository layout, how the
crew works, reviewing, validating, releasing, and conventions). It is tool-neutral and the
single source of truth for working in this repo.

Plugin-specific maps (schemas, file inventories, validator gotchas, release steps) live next
to each plugin and load automatically when working under it — start there instead of
re-exploring:

- [plugins/crew/CLAUDE.md](plugins/crew/CLAUDE.md)
- [plugins/keymaker/CLAUDE.md](plugins/keymaker/CLAUDE.md)

Keep them accurate: a PR that changes anything they state updates them in the same commit.

## Communication style

Use ASD-STE-100 (Simplified Technical English) when you speak to the operator: short sentences,
the active voice, one instruction per sentence, and the same word for the same thing each time.
This applies to what you say to the operator, not to what you write into the repository — files,
docs, and commit messages keep the repo's own voice.

## Engineering rules

Every change here follows the crew's own rubric,
[`engineering-principles`](plugins/crew/skills/engineering-principles/SKILL.md): match the repo,
YAGNI, KISS, minimal-scope diffs, reach for new code last. Read it before you write code, and
re-read your diff against it before you finish. Review with the `zion-review` skill.

## Brevity

- **Replies**: the result first, then what the operator must decide. No recap of work they saw,
  no option you will not take.
- **Code comments**: explain *why*, in one or two lines. A longer rationale lives once, in
  `AGENTS.md`, and the comment points there. Never the same rationale in several files.
- **Docs and PR bodies**: facts, not history. Before you add a paragraph, cut one.
- **Fixes**: prefer removing code to adding a parser. A fix that grows a new edge case each round
  is the wrong fix; stop and say so.

## Rules for every plugin

Plugin `CLAUDE.md` files hold only what differs per plugin. The `§` numbers are sections of
`scripts/validate-plugin.sh`, repo tooling that checks every plugin: marketplace sync §2f,
`skills:` resolution §2g, `[Unreleased]` slot §2i, skill sync §4, hook sync §5, wiring §6, hook
mirror §7, turn-budget §8, rosters §9, prose refs §10, `crew.md` keys §11, footprint §12, MCP
pairs §13. Beside it: `check-changelog.sh` (needs a base ref) and `release-notes.sh`.

- **Validate** as CI does: `bash scripts/validate-plugin.sh`, `bash scripts/check-changelog.sh`,
  `bash tests/hooks/run.sh`, and `shellcheck plugins/*/hooks/*.sh plugins/*/hooks/lib/*.sh
  plugins/*/tests/*.sh scripts/*.sh tests/hooks/*.sh` (CI covers it if missing locally). Stage
  new or renamed skill files first: §2g/§4 index through `git ls-files`.
- **Crew is canonical for shared files.** Shared skills (`context-discipline`,
  `loop-engineering`, `operator-voice`) are byte-identical (§4). `hooks/read-guard.sh` and
  `hooks/lib/guard-lib.sh` are byte-identical, and the marked `bash-safety.sh` region matches
  (§5). Edit crew, then mirror. Shared logic goes in `guard-lib.sh`, not a wider region.
- **Hooks**: top-level `hooks/*.sh` are executable and wired; `hooks/lib/*.sh` are neither
  (§3/§6). Match with `=~` and parameter expansion, no fork per pattern; POSIX patterns. Guard
  scope and open gaps: AGENTS.md, "The Bash guards are floors, not sandboxes".
- **Tests** live in `plugins/<name>/tests/`, run by `tests/hooks/run.sh`, which fails if a plugin
  has `hooks/` and no suite. A hook logic change adds allow and block cases. Not shipped.
- **Agents**: `skills:` is the last frontmatter key (§2g). MCP grants come in pairs,
  `mcp__<key>` and `mcp__plugin_<plugin>_<key>`, paired by server suffix (§13); hosted
  connectors are exempt via `mcp_connector_only`. `loaded-lines-cap` bounds agent file +
  preloaded skills (§12). Prompts carry instruction; rationale lives in AGENTS.md, "Prompt design
  rationale".
- **Release**: bump `.claude-plugin/plugin.json` and add a matching `## [X.Y.Z]` in the plugin's
  `CHANGELOG.md`, folding in `## [Unreleased]`. Bump by default: a changed verdict or reworded
  refusal is a patch. Only an unobservable change parks under `[Unreleased]`. Shipped = all of
  `plugins/<name>/` except `tests/`, `CLAUDE.md`, `VERIFICATION.md` and the changelog.
  Auto-release tags `<name>/vX.Y.Z` on merge. Changelog bullets: one line, two at most.
  Details: AGENTS.md, "Releasing".

## Reading and editing files

Reads and writes in this repository go through the `Read`, `Edit` and `Write` tools, not
through the shell. A guard hook enforces it, so the glance-level habit fails here:

- **Reading a file**: use `Read`. A bare `cat <file>` is refused in *every* session — a shell
  read reaches no `PreToolUse(Read)` hook, so the size bound in `read-guard.sh` never applies
  to it. Bounded shell reads stay available and are the right tool for a slice: `head`,
  `sed -n '10,40p'`, `grep`, `jq`, and any `cat` whose output is piped into a filter.
- **Changing a file**: use `Edit` or `Write`. An in-place `sed`/`perl`, a `tee`, a `cp`/`mv`,
  or a redirect into the checkout is refused in agent sessions, because such a write reaches
  no `PreToolUse(Edit|Write)` hook and would skip both the write lanes and the formatter.
  Scratch output under `/tmp` is exempt.

Both rules close the same gap: a shell that edges around the tool the hooks are wired to.
The refusal message names the tool to use instead, so a blocked command has a one-step fix.

The rest of this file describes how the orchestration works. It stays in the project-root
CLAUDE.md because its reader is anything that reads `CLAUDE.md` to understand this repo —
including auto mode's permission classifier, which otherwise has only a dispatch label to judge a
worker delegation by. The crew's **configuration** is not here: it lives in
[.claude/crew.md](.claude/crew.md), one frontmatter key per slot, written and reconciled by
`/crew:init`.

## Crew orchestration

Development in this repo is orchestrated: `morpheus` plans the work and delegates each step to a
worker subagent (`tank`, `trinity`, `oracle`, `dozer`, `seraph`, `neo`, `sentinel`). Dispatching a
worker is ordinary in-repo development — the worker reads and edits files in this working tree and
returns a summary. It is not remote execution, and it sends nothing outside the repository.

The crew's guard hooks bound what a worker can do: only `morpheus` touches git, no agent commits on
the base branch, each worker's edits are confined to its own lane — through `Edit`/`Write`, and
file-mutating Bash is refused so a write cannot route around the lane — and destructive shell
commands are refused. Nothing is pushed and no pull request is opened on its own — `/crew:pr` is the only
path out of the machine, and the user invokes it.
