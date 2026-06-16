---
description: Debt scout. Enumerates and classifies suppressions/warnings within a required scope and returns a capped ranked report, then lets you pick findings to act on — handing each to /keymaker:open. The scouting itself is read-only and never edits.
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
- `outdated` — outdated dependencies across each detected stack/package manager (optionally narrowed by a trailing lane or path, e.g. `outdated frontend`)
- `diff` — only files changed on the current branch vs base branch

If `$ARGUMENTS` is empty or not a recognised scope, refuse with a usage hint and stop:
> Usage: `/keymaker:audit <scope>` — scope is a path, `backend`, `frontend`, a rule family, `stale`, `outdated`, or `diff`

1. Enumerate findings within the scope using `grep`/`rg` scripts. Count and file-list only — no file bodies (`context-discipline`). For `diff` scope: `git diff --name-only <base>...HEAD` then filter by lane. For `stale` scope: fan out across every suppression mechanism the loaded `debt-taxonomy-<stack>` skills declare, applying that skill's grep-only stale heuristic per mechanism — never compile or build to prove staleness; report candidates only. For `outdated` scope: run each detected stack's **discover-outdated** command from its `debt-taxonomy-<stack>` package-manager table (e.g. `npm outdated`, `dotnet list package --outdated`), parse the `current → target` deltas, and triage each by the core *Upgrade workflow* risk levels (SAFE patch / REVIEW minor / CAUTION major). Read-only — never install, restore, or build in audit.
2. Classify each finding using the `debt-taxonomy` rubric. For `outdated` findings, the classification is the upgrade risk level + tier from the *Upgrade workflow*.
3. Rank: trivially-fixable → needs-real-work → needs-investigation (for `outdated`: SAFE → REVIEW → CAUTION). Within each tier, smaller blast radius ranks higher.
4. Cap at ~12 findings in the report. If a single rule exceeds 50+, surface it as one entry with the count.
5. Format each finding as:
   - Classification tag: `[trivial]` / `[needs-work]` / `[needs-investigation]`
   - Count and evidence pointer (grep command or `file:line`)
   - One-line description of the suppression mechanism
   - Ready-to-paste invocation: `/keymaker:open <pointer>`
6. Return the report. **Do not edit any files.**

When `keymaker:keymaker` returns:

1. Relay its ranked report to the user verbatim (all findings).
2. **Offer an interactive pick** (this happens in your main session — the audit agent can't prompt).
   Present an `AskUserQuestion` with `multiSelect: true`. Build its options from the **first 3
   findings in the report's existing rank order** (trivial → needs-investigation, smaller blast
   radius first); label each with its classification and count, and keep each option's
   `/keymaker:open <pointer>` line so a selection maps deterministically back to that exact pointer.
   Add a final **"None — just the report"** option (3 findings + None = the tool's 4-option max).
   `AskUserQuestion` always supplies its own free-text **"Other"** entry — it is *not* one of your
   options and does not count toward the 4 — through which the user can name any other pointer from
   the full report; treat that the same as a selected finding.
3. **"None" wins.** If "None — just the report" is among the selections — even alongside findings —
   take no action beyond the report (note you treated the mixed pick as None so the user can re-pick).
   Otherwise, for each selected finding run `/keymaker:open <pointer>` **one at a time**, finishing
   one fully (including its own gating and branch decisions) before starting the next.
4. If the picker can't be shown (non-interactive/headless run, where the prompt auto-denies), just
   leave the report as the result — same behavior as before.
