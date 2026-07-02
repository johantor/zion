---
description: Fix one identified tech debt item — a suppression, rule, or dependency upgrade. Classifies the pointer, enumerates blast radius, gates, and delegates fixes to twin workers in batches. For platform-scale migrations, produces a morpheus-compatible handoff outline instead.
---

Given `$ARGUMENTS` (the pointer):

Launch the `keymaker:keymaker` agent (via the Agent tool) in **open mode** with `$ARGUMENTS` and the instructions below. Do not classify, enumerate, edit files, or run git yourself — `keymaker:keymaker` owns all of that. If `keymaker:keymaker` cannot be launched, stop and report the exact error.

Instructions for `keymaker:keymaker`:

You are in **open mode**. The pointer is: `$ARGUMENTS`. Follow your own open-mode flow end
to end, per your exit contract — recognise the pointer form, cheap pre-count and early exit,
classify, enumerate, the fallback 0-findings exit, gate, resolve decisions, delegate to
twins, verify, and commit (or produce a tier-2 handoff outline).

When `keymaker:keymaker` returns, relay its consolidated status to the user.
