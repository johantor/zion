# engineering-principles

A Claude Code plugin: the engineering-principles review rubric as a standalone
skill, for users who want the rubric without the full `crew` orchestration. Part
of the [Zion](../../README.md) marketplace.

## Install

Via the CLI:

```bash
claude plugin marketplace add johantor/zion
claude plugin install engineering-principles@zion
```

…or in the UI, from `/plugin > Discover` in Claude Code.

## Usage

Once installed, Claude Code auto-loads the skill and consults it when you write,
refactor, or review code. No commands or agents are added.

## What is included

- `skills/engineering-principles` — core code-quality rules (YAGNI, KISS, DRY
  with judgment, small single-purpose units, clear naming, minimal-scope diffs).

## Notes

- Contributing or hacking on this plugin? See **[AGENTS.md](../../AGENTS.md)**.
