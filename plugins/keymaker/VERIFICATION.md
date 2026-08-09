# keymaker — verification matrix

Behavioral scenarios that gate keymaker's graduation to Stable. Referenced from
[README.md](README.md) and the repository contributor guide,
[AGENTS.md](../../AGENTS.md).

The [beta banner](README.md) stays until keymaker has been exercised — against a real project or a
purpose-built scratch repo — on every gate and exit path below. Each row is one scenario: a minimal
planted-debt setup and the behavior that counts as a pass. Check it off once you've run it. This is
the written definition of "run in a live project" that the banner refers to; the bar for dropping it
is under [Graduation to Stable](README.md#graduation-to-stable-v10).

A scratch repo for these is cheap, and `tests/fixtures/keymaker-scratch.sh` in this repo builds
one — it prints the path on stdout so it composes directly:

```bash
repo="$(bash tests/fixtures/keymaker-scratch.sh --stack ts)"   # or --stack dotnet
cd "$repo" && claude --plugin-dir /path/to/plugins/keymaker -p "/keymaker:audit src/"
```

It plants same-rule suppressions where some carry a meaningful native justification and some
don't, plus a justified-*and*-stale one and an annotated skipped test — the two documented filter
exemptions. Build it **in your own terminal, not inside a Claude agent session**: keymaker's hooks
block `git` for agents (twins especially), so the `git init` is the script's to run, not an
agent's. For rows the generator doesn't cover, plant the specific suppression, version pin, or
violation the row names and point `/keymaker:audit` or `/keymaker:open` at it.

> **Verification log — 2026-07-17.** The three read-only / early-exit rows checked below were run
> against a planted-debt TypeScript scratch repo (`package.json` + `tsconfig.json`, four suppressions
> across `src/orders/` and `src/users/`), driving the plugin headlessly
> (`claude --plugin-dir plugins/keymaker -p "/keymaker:audit …"`). Each produced the specified result
> with the working tree unchanged (verified via `git status`) and, for the 0-findings exit, no branch
> created. Two caveats on what these passes do **not** cover: the headless runs had no `AskUserQuestion`
> tool, so the audit's interactive multi-pick used its documented text fallback rather than the picker
> itself; and no edit/verify/commit path, interactive gate, or .NET-stack row has been exercised yet.
>
> Each row checked from these runs is tagged **[TS]** for the stack exercised. The row text stays
> stack-neutral on purpose — it is the scenario spec for *both* stacks — so a **[TS]** tag means the
> TypeScript instance passed and that row's .NET variant (e.g. `#pragma warning disable`, `CS8602`)
> is still pending, not that the whole row is done.

> **Verification log — 2026-08-07 (0.8.0 justification rows).** The three justification rows were
> run against a scratch repo from `tests/fixtures/keymaker-scratch.sh --stack ts`, driving the
> plugin headlessly (`claude --plugin-dir plugins/keymaker -p "/keymaker:audit …"`, sonnet). Observed:
> `/keymaker:audit src/` returned **"4 findings (1 justified) — 3 shown"**, listing `total.ts` and
> `format.ts` as unjustified and excluding `vendor.ts` as rubric class 1 while quoting its ESLint
> `--` description; `/keymaker:audit stale` listed the justified-and-stale `lookup.ts` candidate
> **tagged `justified`**, stating the filter is exempt in that scope; `/keymaker:audit skipped-tests`
> reported the annotated `it.skip` as class 4 and said in as many words that the rationale comment
> does not exclude it. The working tree was unchanged after all three (`git status` clean, one
> commit). Caveats: TypeScript only — the .NET variants of these rows are still pending, and the
> headless runs had no `AskUserQuestion`, so the audit's picker used its documented text fallback.

## Audit mode (read-only scouting)

- [x] **`path` scope** **[TS]** — `/keymaker:audit src/Foo/` over a handful of suppressions → ranked report (~12 max), each finding a ready-to-run `/keymaker:open`; nothing edited.
- [ ] **`lane` scope** — `/keymaker:audit backend` in a backend+frontend repo → report scoped to the backend file area, taxonomy chosen by marker-file detection, not the lane name.
- [ ] **rule-family scope** — `/keymaker:audit nullability` (or `eslint`) → report limited to that rule family.
- [x] **`stale` scope** **[TS]** — a tree with a stale `@ts-expect-error` and a `#pragma warning disable` over a benign line → report lists them as **candidates** (grep-only); no compile.
- [ ] **`outdated` scope** — a `package.json` / `.csproj` with an outdated pin → each `current → target` triaged SAFE/REVIEW/CAUTION; metadata only, no install/restore/build.
- [ ] **`diff` scope** — `/keymaker:audit diff` on a branch with changes → report scoped to the changed files vs base.
- [ ] **report cap** — 50+ hits for a single rule → folded into one "50+ for rule X" entry; total report stays ≤ ~12.
- [x] **justified suppressions excluded** **[TS]** — a tree where one of three same-rule suppressions carries a meaningful native justification → report lists the two unjustified ones and its totals line accounts for the third as justified; nothing edited.
- [x] **`stale` ignores justifications** **[TS]** — a justified suppression that is also a stale candidate → still listed under `/keymaker:audit stale`, tagged justified.
- [x] **skipped tests never excluded** **[TS]** — a `[Fact(Skip="…")]` / `it.skip` with a descriptive reason → still reported as needs-investigation.

## Open mode — early exits (before any edit)

- [x] **0-findings pre-count exit** **[TS]** — `/keymaker:open CS8602` where the suppression is already gone → one-line "nothing to do" status; no classification, gate, branch, or twin.
- [ ] **0-findings fallback exit** — pasted build output whose parsed rule IDs all enumerate to 0 → one-line status listing the rules.
- [ ] **idempotent re-run / resume** — re-running a completed `/keymaker:open` (matching ledger, all batches `done`) → one-line "already complete" no-op; a run interrupted mid-batch resumes its ledger instead of re-classifying.

## Open mode — blast-radius gate

- [ ] **≤ 5, single lane → proceed** — 3 sites of one rule → one twin, one commit, no slice prompt.
- [ ] **6–40 → batched** — ~20 sites → fanned into directory-cluster batches.
- [ ] **> 40 single rule → slice & stop** — 60 sites → presents natural slices, waits for your pick, edits nothing until answered.
- [ ] **Tier-2 migration → outline & stop** — a framework-major pointer → classified tier 2; offers a `.claude/plan-<slug>.md` handoff outline; does not implement.
- [ ] **Behavior-sensitive, no test command → warn + ack** — a `react-hooks/rules-of-hooks` batch with no configured test command → explicit warning, requires acknowledgement before continuing.
- [ ] **Transitive/peer conflict → stop** — an upgrade that surfaces a peer conflict → reported and stopped; never silently pinned or given `--legacy-peer-deps`.

## Open mode — delegate / verify / commit

- [ ] **Behavior-preserving → lint gate** — a type-only fix → accepted on compiler/linter-clean evidence.
- [ ] **Behavior-sensitive → tests-green gate** — a hooks refactor → accepted only on tests-green, committed one logical unit per commit.
- [ ] **Verify rejects a mechanism swap** — a twin that removes an `eslint-disable` but introduces a `@ts-ignore` → verification fails (re-sweeps every mechanism against the dispatch snapshot) and re-delegates.
- [ ] **Retry cap → blocked** — a batch that fails verify 3 times → marked `blocked` with attempt history and surfaced, not thrashed further.
- [ ] **Loop mode drains, never skips gates** — "clear all the stale ones" after an audit → the picked pointers run to completion under `loop-engineering`'s stop rules; a no-test acknowledgement (or any gate needing an answer) still stops the loop, independent batches drain first, and all blockers surface together.
- [ ] **Upgrade gates by risk** — a patch bump accepted build/lint-clean; a minor/major accepted only tests-green, with the lockfile/manifest committed in the same batch; a failed verify reverts the single offending package.
- [ ] **Commit shapes** — debt: `chore(debt): remove CS8602 suppression in src/Orders/ (4 sites)`; upgrade: `chore(deps): bump Newtonsoft.Json 12.0.3 → 13.0.3`.
