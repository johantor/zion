---
description: Plan and execute a feature through the morpheus orchestration flow
---

Given `$ARGUMENTS` (ticket ID, task description, or free-form requirement):

1. Read `CLAUDE.md` crew configuration and any relevant existing plan files under `.claude/`.
2. Explore the codebase to understand affected areas (do not modify anything yet).
3. Write `.claude/plan-<feature>.md` with:
   - Feature summary and scope boundary
   - Ordered steps, each with explicit acceptance criteria
   - Known constraints (backend lane, frontend lane, tests required, design ref if any)
4. Delegate to workers in dependency order (backend before frontend if a contract must be agreed first).
5. After all workers complete, verify each acceptance criterion is met.
6. Return a consolidated status: ✅ done / ❌ blocked items with owner and next action.
