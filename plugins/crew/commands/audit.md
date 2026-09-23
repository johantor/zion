---
description: Debt scout. Enumerates and classifies suppressions, warnings, and outdated packages within a required scope and returns a capped, ranked report, then lets you pick findings to hand to /crew:debt. The scouting itself is read-only.
---

Given `$ARGUMENTS` (the scope):

Launch the `crew:morpheus` agent (via the Agent tool) with `$ARGUMENTS` and the instructions
below. Do not enumerate, classify, or edit files yourself. If `crew:morpheus` cannot be launched,
stop and report the exact error.

Instructions for `crew:morpheus`:

This is a debt audit, in **audit mode**. The scope is: `$ARGUMENTS`. Load the `debt` skill and
follow its audit-mode flow, including scope validation, ranking, the cap, and the totals line.
Return the ranked report. Edit nothing.

When `morpheus` returns:

1. Relay the report verbatim, **including its totals line** — that line accounts for
   suppressions excluded as justified or by project policy, so dropping it would report the
   scope as cleaner than it is.
2. Offer a pick with `AskUserQuestion`, `multiSelect: true`: the **first 3 findings in report
   order**, each labelled with its classification and count and keeping its `/crew:debt
   <pointer>` line, plus a final **"None — just the report"**. The tool's own free-text "Other"
   lets the user name any other pointer from the report; treat it like a selected finding.
3. **"None" wins**, even alongside findings — note that you treated a mixed pick as None.
   Otherwise run `/crew:debt <pointer>` for each pick **one at a time**, finishing one (its gates
   and branch decision included) before the next. Loop intent ("clear all the stale ones") runs
   the sequence under `loop-engineering`'s stop rules, never past a gate that needs the user. If
   the sequence is interrupted, re-run `/crew:audit` and re-pick: a finished pointer exits as a
   no-op, and a half-done one resumes from its ledger.
4. If the pick can't be shown (headless), the report is the result.
