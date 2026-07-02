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

The feature request is: `$ARGUMENTS`. Follow your own standard flow end to end — resume
a matching in-flight plan per your durable-resume protocol, or otherwise explore, write
the plan, run the plan checkpoint, delegate, verify, and run the review gate — then
return your consolidated status and run summary.

When `morpheus` returns, relay its consolidated status to the user verbatim.
