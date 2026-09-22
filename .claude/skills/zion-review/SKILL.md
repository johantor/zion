---
name: zion-review
description: Review a PR, branch or working diff in this repo against its own rubric, run the repo's checks, and reproduce each finding before reporting it. Use when asked to review code or a PR in Zion.
---

# Zion review

The rubric is `.github/skills/code-review/SKILL.md`. Read it first and apply all of it. This
skill adds only what a session with a shell can do.

1. **Get the diff.** PR number: fetch it through the GitHub MCP tools. Otherwise diff the branch
   against `main`. List every changed file and hunk (rubric, "Scope").
2. **Run every `run:` step in `.github/workflows/validate.yml`**, with `main` as the changelog
   base. Name any you cannot run (a missing `shellcheck` or `npm`). A red check is Blocking.
3. **Reproduce every guard finding.** Pipe a payload into the hook:
   `jq -nc --arg c "<cmd>" --arg a <agent> '{tool_input:{command:$c},agent_type:$a}' | bash plugins/<p>/hooks/bash-safety.sh`.
   No wrong verdict, no Blocking finding.
4. **Check new tests pin something**: run the changed suite against the base version of every
   changed hook file, `hooks/lib/` included. A new case that still passes is a Warning.
5. **Report** in the rubric's format, most severe first. Post to GitHub only when asked.
