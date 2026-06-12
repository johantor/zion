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

**Exit contract:** pointer parsed → enumeration → if 0, exit one-liner; only then classify/gate/dispatch. The 0-findings exit must run as early as possible — before any classification, gating, or twin dispatch — so re-running a successful `/keymaker:open` (e.g. from a `.claude/plan-*.md` checklist) is a cheap no-op.

1. Recognise the pointer form (`file:line`, rule ID, package+version, pasted output, or unrecognised). If unrecognised, ask the user to clarify and stop.
2. Pre-count when cheap, before classification:
   - `file:line` → grep the suppression token at that location.
   - Single rule ID → grep-count the rule's suppression form across the relevant tree.
   - Package + target version → read the current pinned version from `*.csproj` / `Directory.Packages.props` / `package.json`; compare to target.
   If the pre-count is 0 (suppression already removed, rule already silent, package already at target), report a single one-line status that names what was checked — e.g. `No findings for CS8602 — nothing to do (grep count 0).` or `No findings for Newtonsoft.Json 13.x — nothing to do (already pinned at 13.0.3).` — and stop. Do not classify, gate, branch, or dispatch.
3. Classify the pointer using `debt-taxonomy`. (Pasted output with multiple rule IDs is parsed here; per-rule enumeration happens in step 4.)
4. Enumerate blast radius with scripts (counts and file paths only — `context-discipline`).
5. Fallback 0-findings exit (for pointer forms where pre-count in step 2 was not possible, e.g. pasted output that parsed to multiple rule IDs): if enumeration yields 0 findings for the pointer, or for all rule IDs parsed from pasted output, report the same one-line status and stop.
6. Gate using the `debt-taxonomy` blast-radius gate. Report the classification and radius before proceeding.
7. Resolve any required user decisions in the foreground before dispatching background workers.
8. For tier-1 pointers within gate: delegate to `keymaker:twin` workers, verify, commit per batch.
9. For tier-2 (platform migration): offer to produce a morpheus-compatible handoff outline; stop there.

When `keymaker:keymaker` returns, relay its consolidated status to the user.
