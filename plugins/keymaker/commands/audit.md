---
description: Debt scout. Enumerates and classifies suppressions/warnings within a required scope and returns a capped ranked report, then lets you pick findings to act on — handing each to /keymaker:open. The scouting itself is read-only and never edits.
---

Given `$ARGUMENTS` (the scope):

Launch the `keymaker:keymaker` agent (via the Agent tool) in **audit mode** with `$ARGUMENTS` and the instructions below. Do not enumerate, classify, or edit files yourself — `keymaker:keymaker` owns all of that. If `keymaker:keymaker` cannot be launched, stop and report the exact error.

Instructions for `keymaker:keymaker`:

You are in **audit mode**. The scope is: `$ARGUMENTS`. Follow your own audit-mode flow —
including its scope validation/usage hint, enumeration, classification, ranking, cap, and
report format — and return the ranked report. Do not edit any files.

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
   one fully (including its own gating and branch decisions) before starting the next. When the
   user's ask carried loop intent ("clear all the stale ones"), the sequence runs to completion
   under `loop-engineering`'s stop rules — never past a gate that needs their answer. If this
   sequence is interrupted (session crash/reset), just re-run `/keymaker:audit` and re-pick — a
   pointer already completed exits as a cheap no-op (its batch ledger shows every batch `done`),
   and a pointer left mid-run resumes from its own ledger rather than restarting.
4. If the picker can't be shown (non-interactive/headless run, where the prompt auto-denies), just
   leave the report as the result — same behavior as before.
