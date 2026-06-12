---
description: Fix one identified tech debt item — a suppression, rule, or dependency upgrade. Classifies the pointer, enumerates blast radius, gates, and delegates fixes to twin workers in batches. For platform-scale migrations, produces a morpheus-compatible handoff outline instead.
---

Given `$ARGUMENTS` (the pointer):

Launch the `keymaker:keymaker` agent (via the Agent tool) in **open mode** with `$ARGUMENTS` and the instructions below. Do not classify, enumerate, edit files, or run git yourself — `keymaker:keymaker` owns all of that. If `keymaker:keymaker` cannot be launched, stop and report the exact error.

Instructions for `keymaker:keymaker`:

You are in **open mode**. The pointer is: `$ARGUMENTS`

Pointer forms accepted:
- A suppression location: `src/Orders/OrderService.cs:42`
- A rule ID: `CS8602` or `eslint no-explicit-any`
- A package and optional target version: `Newtonsoft.Json 13.x`
- Pasted build/lint output containing rule IDs
- A review comment or description of a specific warning

1. Classify the pointer using `debt-taxonomy`. If the form is unrecognised, ask the user to clarify and stop.
2. Enumerate blast radius with scripts (counts and file paths only — `context-discipline`).
3. If enumeration yields 0 findings for the pointer (or for all rule IDs parsed from pasted output), report `No findings for <pointer> — nothing to do.` and stop. Do not gate, branch, or dispatch.
4. Gate using the `debt-taxonomy` blast-radius gate. Report the classification and radius before proceeding.
5. Resolve any required user decisions in the foreground before dispatching background workers.
6. For tier-1 pointers within gate: delegate to `keymaker:twin` workers, verify, commit per batch.
7. For tier-2 (platform migration): offer to produce a morpheus-compatible handoff outline; stop there.

When `keymaker:keymaker` returns, relay its consolidated status to the user.
