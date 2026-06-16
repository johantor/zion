---
description: Read-only debt scout. Enumerates and classifies suppressions/warnings within a required scope, returns a capped ranked report where every finding is a ready-to-run /keymaker:open invocation. Never edits anything.
---

Given `$ARGUMENTS` (the scope):

Launch the `keymaker:keymaker` agent (via the Agent tool) in **audit mode** with `$ARGUMENTS` and the instructions below. Do not enumerate, classify, or edit files yourself — `keymaker:keymaker` owns all of that. If `keymaker:keymaker` cannot be launched, stop and report the exact error.

Instructions for `keymaker:keymaker`:

You are in **audit mode**. The scope is: `$ARGUMENTS`

Valid scopes:
- A path: `src/Checkout/` or `src/`
- A lane: `backend` or `frontend`
- A rule family: `nullability`, `eslint`, `skipped-tests`, `ts-suppressions`, `analyzers`
- `stale` — candidate-stale suppressions across every mechanism the loaded `debt-taxonomy-<stack>` skills declare (cheapest wins; grep-only, candidate-only — proof is left to `/keymaker:open` per finding)
- `diff` — only files changed on the current branch vs base branch

If `$ARGUMENTS` is empty or not a recognised scope, refuse with a usage hint and stop:
> Usage: `/keymaker:audit <scope>` — scope is a path, `backend`, `frontend`, a rule family, `stale`, or `diff`

1. Enumerate findings within the scope using `grep`/`rg` scripts. Count and file-list only — no file bodies (`context-discipline`). For `diff` scope: `git diff --name-only <base>...HEAD` then filter by lane. For `stale` scope: fan out across every suppression mechanism the loaded `debt-taxonomy-<stack>` skills declare, applying that skill's grep-only stale heuristic per mechanism — never compile or build to prove staleness; report candidates only.
2. Classify each finding using the `debt-taxonomy` rubric.
3. Rank: trivially-fixable → needs-real-work → needs-investigation. Within each tier, smaller blast radius ranks higher.
4. Cap at ~12 findings in the report. If a single rule exceeds 50+, surface it as one entry with the count.
5. Format each finding as:
   - Classification tag: `[trivial]` / `[needs-work]` / `[needs-investigation]`
   - Count and evidence pointer (grep command or `file:line`)
   - One-line description of the suppression mechanism
   - Ready-to-paste invocation: `/keymaker:open <pointer>`
6. Return the report. **Do not edit any files.**

When `keymaker:keymaker` returns, relay its report to the user verbatim.
