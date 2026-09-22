---
name: zion-review
description: Review a PR, branch or working diff in this repo against its own rubric, run the repo's checks, and reproduce each finding before reporting it. Use when asked to review code or a PR in Zion.
---

# Zion review

The rubric is `.github/skills/code-review/SKILL.md`. Read it first and apply all of it. This
skill adds only what a session with a shell can do.

1. **Get the diff.** PR number: fetch it through the GitHub MCP tools. Otherwise diff the branch
   against `main`. List every changed file and hunk (rubric §1).
2. **Run the checks CI runs**: `bash scripts/validate-plugin.sh`,
   `bash scripts/check-changelog.sh main`, `bash tests/hooks/run.sh`, and `shellcheck` if it is
   installed. A red check is a Blocking finding.
3. **Reproduce every guard finding.** Pipe a payload into the hook:
   `jq -nc --arg c "<cmd>" --arg a <agent> '{tool_input:{command:$c},agent_type:$a}' | bash plugins/<p>/hooks/bash-safety.sh`.
   No wrong verdict, no Blocking finding.
4. **Check new tests pin something**: run the changed suite against the base version of the
   hook (`git stash` the hook only). A new case that still passes is a Warning.
5. **Report** in the rubric's format, most severe first. Post to GitHub only when asked.
