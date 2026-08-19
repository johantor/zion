# Zion — Claude Code notes

Zion is a Claude Code plugin marketplace (`crew`, `keymaker`, `engineering-principles`):
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
the base branch, each worker's edits are confined to its own lane, and destructive shell commands
are refused. Nothing is pushed and no pull request is opened on its own — `/crew:pr` is the only
path out of the machine, and the user invokes it.
