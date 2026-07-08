---
description: Outer-loop driver — re-invoke morpheus across runs on the native /loop until the plan's exit conditions are met (dynamic, self-paced)
---

Given `$ARGUMENTS` (a feature goal — ticket ID, task, or free-form requirement):

Drive the feature to completion across multiple `morpheus` runs, so work that outlives one
run's `maxTurns` finishes without you re-asking each time. Each tick you launch the
`crew:morpheus` agent **directly** (the same agent `/crew:feature` launches) — not by nesting
`/crew:feature`, which only forwards the goal and can't tell `morpheus` a loop is driving it.
This wrapper is the **outer loop**; it lives at the **main-session** level and owns all
scheduling. `morpheus` never self-schedules — you re-invoke it, one tick at a time, on the
harness's native `/loop` in **dynamic (self-paced) mode**. The durable
`<plan-dir>/plan-<feature>.md` (the `Plan directory` crew-config slot, or `.claude/` when
unset) is the only cross-tick state — no new files, no background daemon.

Run this **foreground** so tick 1's plan checkpoint can prompt.

## Per-tick logic

**Iteration cap syntax.** `$ARGUMENTS` may end with a `max=<n>` token (e.g.
`/crew:loop add SSO login max=5`); parse and strip it — the rest is the goal handed to
`morpheus`. Absent it, `<max>` defaults to 10.

Each tick, **locate this goal's plan** — the `plan-<feature>.md` whose `feature:` /
`feature-branch:` header identifies this goal, using `morpheus`'s own durable-resume match rule
(*The plan file is durable state*): match by header, never guess; if more than one could match,
stop and ask the user rather than picking one. Then decide:

1. **No plan yet (tick 1).** Launch `crew:morpheus` (via the Agent tool) with `<goal>` plus an
   explicit note: **`/crew:loop` is driving this as an outer-loop tick and loop mode is
   authorized** — the user's `/crew:loop` invocation is the loop intent (`loop-engineering`), so
   don't wait for trigger phrases in the goal text. `morpheus` enters loop mode, explores,
   writes the plan and its `loop:`/`exit-conditions:` header, and runs the plan checkpoint
   **once** — loop intent authorizes the *run*, not the *plan*, so you never skip that gate. When
   it returns, seed the outer-loop counter you own: `iterations: 1/<max>`. Then evaluate the
   checks below.
2. **Plan exists.** Run the pre-check, then the exit checks. If none fires, launch
   `crew:morpheus` again with `<goal>` and the same outer-loop note — it resumes from the plan
   per its durable-resume protocol (a plan with `loop: on` continues in loop mode; it does
   **not** re-plan or re-checkpoint) — then bump `iterations:` **in the header** and re-evaluate.
   The count lives only in the header; a restarted wrapper reads it from there, never re-derives
   it. If a plan exists with no `iterations:` (a hand-edited or truncated file), don't reset to
   `1` — that would bypass the cap; surface it and ask rather than looping blind.

**Pre-check — in flight (re-entrancy guard, *skip*, don't end).** A prior run may still be in
flight: the header carries an `in-flight:` marker, or a step is `in-progress` with a background
worker still running. Do **not** launch another tick on the same plan — that would
double-dispatch a running step. Instead **skip**: schedule a later dynamic wakeup and re-check,
letting `morpheus`/its workers finish and the next tick collect them. Only if it stays in
flight with **no forward progress** across several checks (a crashed run, not honest work)
treat it as stuck and end, surfacing it for an explicit resume.

**Exit checks (first match ends the loop and surfaces — never auto-push or open a PR):**

- **success.** Every step `done` **and** `gate: GO` → end. Report the run summary. Pushing
  stays behind `/crew:pr`.
- **blocked.** Any step `blocked` on a human decision → end and surface every blocked step
  together (independent unblocked steps have already been drained by `morpheus`).
- **iteration cap.** `iterations:` `n >= max` → end and surface where the plan stands. The cap
  is enforced here, by you (the model) — it is not a hard runtime budget.

## Ownership

You are the sole writer of the plan file's **outer-loop** bookkeeping only — `iterations:` and
the `in-flight:` marker. `morpheus` owns the rest (steps, `loop:`, `exit-conditions:`, `gate:`)
and preserves your two fields when it rewrites the plan. Ticks are **synchronous** — launch
`crew:morpheus`, wait for it to return, then update the header and decide — so the two
writers never overlap. Set `in-flight:` before launching a tick and clear it when `morpheus`
returns.

Schedule the next tick with the native `/loop` dynamic-mode wakeup only while the loop is still
live. When an exit check fires, stop scheduling and give the user the consolidated status.
