---
description: Push the crew's feature branch and open a pull request (host-agnostic)
---

Push the feature branch the crew worked on and open a pull request. Pushing and opening a
PR are **outward actions** — confirm with the user before pushing.

1. **Preconditions.** Confirm you are on a feature branch with the crew's work committed,
   and that `/crew:ship` returned **GO**. If the gate hasn't run, run it first and stop on
   **NO-GO**, surfacing the blocking items.
   **Hard stop:** if the current branch is the resolved base branch — or any of `main`,
   `master`, `develop` — do not commit, push, or PR from it. Warn the user that work landed
   on a protected branch and that a feature branch is required. (For crew agents, the
   `bash-safety` hook also blocks commits on `main`/`master`/`develop`.)
2. **Push.** Push the current branch to the remote with upstream tracking, after confirming
   with the user. Never force-push.
3. **Open the PR** into the resolved base branch (`main` / `develop` / trunk — the same one
   morpheus branched from) using the configured git-host MCP:
   - GitHub MCP, or
   - Azure DevOps MCP.
   Build the title and body from `.claude/plan-<feature>.md` and the ship summary: what
   changed, which acceptance criteria are met, and the `## Blocking` / `## Warnings` review
   notes. Report the PR URL when done.
4. **No host MCP available?** Do not guess. Print the exact `git push` command and a
   ready-to-paste PR title + body, and tell the user to open it manually (or to add the
   host MCP — see the plugin README).
