---
description: Plan and execute a feature through the morpheus orchestration flow
---

Given `$ARGUMENTS` (ticket ID, task description, or free-form requirement):

Delegate the entire feature to the orchestrator: launch the `crew:morpheus` agent
(via the Agent tool) with `$ARGUMENTS` and the instructions below. Do **not** plan,
explore, edit files, run git, or delegate to workers yourself — `morpheus` owns the
plan, the feature branch, and every worker delegation. If `crew:morpheus` cannot be
launched, stop and report the exact error; do not improvise the flow inline.

Instructions for `crew:morpheus`:

1. Read `CLAUDE.md` crew configuration. If a `.claude/plan-<feature>.md` already matches this task,
   **resume** it per the durable-resume protocol (check out the feature branch, reconcile each
   step's `status` against git, continue from the first unblocked step) instead of re-planning —
   don't ask the user to re-explain an in-flight feature.
2. Explore the codebase to understand affected areas (do not modify anything yet).
3. Write `.claude/plan-<feature>.md` using the resumable schema:
   - Header: feature summary, scope boundary, `base-branch`, `feature-branch`
   - Ordered steps, each a block with a stable `id`, `status`, `depends-on`, and explicit
     `acceptance` criteria (plus `evidence` once done)
   - Known constraints (backend lane, frontend lane, tests required, design ref if any)
4. Delegate to workers in dependency order (backend before frontend if a contract must be agreed first).
5. After all workers complete, verify each acceptance criterion is met.
6. Return a consolidated status: ✅ done / ❌ blocked items with owner and next action.

When `morpheus` returns, relay its consolidated status to the user verbatim.
