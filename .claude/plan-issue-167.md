# Plan — issue #167: shrink always-loaded agent prompts, move rationale to AGENTS.md

feature: refactor(crew,keymaker): relocate prompt rationale to AGENTS.md; measure loaded footprint
base-branch: main
feature-branch: claude/issue-167-plan-f8tsg5 (or a fresh branch off latest main per AGENTS.md conventions)
issue: #167 (link the PR with `Closes #167`)

## Goal

`morpheus.md` (390 lines) and `keymaker.md` (258 lines) load into every crew/keymaker session,
alongside their preloaded skills. A share of those lines is *rationale* — why a rule exists —
restated at the call site. AGENTS.md already bans this for scripts ("Keep inline script/agent-prompt
comments short; put full rationale in AGENTS.md … and point to it"). Apply the same rule to the
agent prompts, **behavior-preserving only**, and add a validator section so the repo measures the
per-agent loaded footprint it preaches (`context-discipline`) instead of never checking its own.

## Baseline (measure again before starting; record before/after in the PR)

Loaded footprint = agent `.md` line count + sum of its frontmatter `skills:` SKILL.md line counts.

| Agent | Agent file | Preloaded skills | Footprint |
|---|---|---|---|
| crew:morpheus | 390 | loop-engineering 49 + context-discipline 16 | **455** |
| keymaker:keymaker | 258 | context-discipline 16 + debt-taxonomy 203 + loop-engineering 49 | **526** |
| keymaker:twin | 38 | context-discipline 16 + debt-taxonomy 203 | 257 |
| crew workers (tank/trinity/neo/oracle/dozer/seraph) | 27–63 | 16–46 | ≤ ~110 |

No numeric reduction target — the constraint is behavior preservation, not a quota. A realistic
outcome is ~15–25% off the two orchestrator files. If honest classification yields less, that is
the correct result.

## Ground rules — the classification test

For every candidate line/clause, ask: **"Would an agent that never read this text behave
differently on some input?"**

- **KEEP — operational fact.** Knowledge the agent needs at runtime to act correctly, even if
  phrased as a "why": e.g. *"watch/dev commands never terminate and hang the worker"*,
  *"background workers can't prompt — `AskUserQuestion` auto-denies"*, *"plugin agents are
  namespaced; bare names don't resolve"*, *"grep's rule IDs are parsed in step 3"*. These change
  what the agent does; they stay (compress wording where possible, don't delete).
- **KEEP — disambiguating clause.** A short motivation that resolves which of two readings of a
  rule is intended (e.g. *"faster, not sloppier"*). Keep, compressed to a clause.
- **MOVE — design rationale.** Justification aimed at a maintainer/reviewer: why the design was
  chosen, what failure it historically prevents, cost/benefit framing, re-explanations of a rule
  already stated elsewhere in the same file. These move to AGENTS.md.
- **DELETE — restatement.** A sentence that re-explains a rule the same file already states (often
  as a cross-reference plus paraphrase). Replace with the bare cross-reference that already exists.

Every removed passage must be classified in the PR self-review (a two-column moved/kept mapping in
a PR comment is enough; the diff is the record). **Any line whose classification is arguable stays
in the prompt** — a deleted edge-case rule is exactly the design bug #162–#166 exist to catch.
Apply AGENTS.md → "Reviewing a prompt change" as the self-review lens before pushing.

## Pointer convention (deviation from the issue, deliberate)

AGENTS.md is **not shipped** with an installed plugin — a runtime agent can never read it, so
per-site pointers are pure context cost with zero runtime value. Use **exactly one pointer line
per trimmed file**, at the top of the body, e.g.:

> *Design rationale for these rules lives in AGENTS.md → "Prompt design rationale" (repo, not shipped).*

Not one pointer per relocated passage. The AGENTS.md section is keyed by agent + section heading so
a contributor can find the rationale for any rule from its heading alone.

## Steps

### S1 — Add the destination section to AGENTS.md
- id: s1
- depends-on: independent
- Add `## Prompt design rationale` to AGENTS.md (after "Reviewing a prompt change" is a natural
  spot), with one subsection per agent (`### crew:morpheus`, `### keymaker:keymaker`), each entry
  keyed by the prompt's section heading it explains. Populate it as S2/S3 relocate text —
  rewritten as maintainer prose, not pasted fragments.
- acceptance: section exists; every passage S2/S3 removes as MOVE lands here under the right key;
  wording of behavioral claims matches the prompts (AGENTS.md "cross-file wording agrees" lens).

### S2 — Trim `plugins/crew/agents/morpheus.md`
- id: s2
- depends-on: s1
- Candidate inventory (line refs against current main — re-check before editing; each is a
  *candidate*, subject to the classification test, not a pre-approved cut):
  - **§Right-size the process, intro (~L36–37)** — "a one-line fix shouldn't pay for a plan, a
    checkpoint, and a full review gate" → MOVE; the triage rules themselves stay.
  - **§Plan checkpoint, intro (~L121–122)** — "The cheapest place to catch a misunderstood task is
    before any code is written" → MOVE.
  - **§Stay responsive (~L139–223)** — the densest section. The rules (always
    `run_in_background: true`; collect every result; one writer per file; pulse format; foreground
    tick exception) all stay. MOVE candidates: the freeze-duration explanation (~L142–144), the
    "Backgrounding is not abandoning" framing sentence (~L146), the explanation of *why* two blind
    workers clash (~L186–188), the long justification inside "A truncated return…" of why
    truncation arrives as an ordinary completion and how the turn-budget hook makes orderly returns
    the norm (~L198–212 — keep the *decision rules*: judge on content/required evidence, planned
    stop vs backstop, usage only corroborates; move the mechanism explanation). KEEP: "Every
    dispatch is a fresh spawn" facts (no SendMessage in reach; a second worker would race the
    first) — operational.
  - **§Right-size the model (~L227–243)** — "a wrong fast result costs more than the seconds saved"
    and the truncation cost-framing → MOVE/compress; the haiku/omit table and the
    author-vs-verify split rule stay.
  - **§Builds and full test suites (~L246–276)** — "expensive and verbose" framing, "that builds
    the same tree twice" parenthetical → MOVE/compress. KEEP all of items 3–5 (locked-output
    contention, watch-command hang, environmental-vs-code triage) — operational facts.
  - **§The plan file is durable state (~L311–317)** — "written to survive a crashed session… the
    user never re-explains a feature" → MOVE; schema and resume protocol stay verbatim.
  - **§Run summary (~L377)** — "It's the per-worker view the live agent panel loses on resume" →
    MOVE.
  - **Anti-drift rules** — mostly load-bearing; only compress obvious restatements that duplicate a
    section they already cite by name.
- acceptance: every behavioral instruction, threshold, and edge-path outcome present before is
  present after (checked against the classification test + prompt-change review lens); file
  measurably shorter; one pointer line added; §s1 AGENTS.md entries written for each MOVE.

### S3 — Trim `plugins/keymaker/agents/keymaker.md`
- id: s3
- depends-on: s1
- Smaller yield expected — the file is mostly numbered procedure. Candidates:
  - **Exit contract (~L50)** — "so re-running a successful open is a cheap no-op" → compress to a
    clause or MOVE; the pre-count/fallback-exit rules stay.
  - **§8 Verify (~L155–160)** — the *why* of the independent re-sweep ("don't rely solely on the
    twin's self-reported counts") compresses; the check itself (every mechanism, before-snapshot,
    cross-mechanism swap fails) stays verbatim.
  - **§Batch ledger intro (~L189–193)** — "a crash or context reset shouldn't lose the run" → MOVE;
    schema and resume protocol stay.
  - **Resume protocol commentary (~L230–237)** — "This is what makes a repeat /keymaker:open a
    cheap no-op", "A ledger with every batch done has no further use…" → MOVE/compress.
  - KEEP: untrusted-pointer handling (step 3), all gates, the 3-round-trip cap mechanics.
- acceptance: same bar as S2.

### S4 — Preloaded skills: audit, expect no change
- id: s4
- depends-on: independent
- `context-discipline` (16) and `loop-engineering` (49) are already tight; `debt-taxonomy` (203) is
  reference tables (rubric/gates/recipes), i.e. instruction, not rationale. Audit briefly; **do not
  edit shared byte-synced skills unless a cut is clearly worth it** — any edit to
  `context-discipline`/`loop-engineering` forces a byte-sync + version bump + changelog for every
  plugin shipping it (crew *and* keymaker; `engineering-principles` likewise ships standalone).
  Recommendation: leave skills untouched in this PR; note the audit result in the PR body.
- acceptance: audit noted; no shared-skill drift introduced (validator §4 green).

### S5 — Validator §12: per-agent loaded-footprint report + opt-in cap
- id: s5
- depends-on: s2, s3 (caps are set from post-trim numbers)
- In `scripts/validate-plugin.sh`, add **§12**:
  - For every `plugins/*/agents/*.md`: compute footprint = agent file line count + sum of line
    counts of each frontmatter `skills:` entry's resolved `SKILL.md` (reuse §2g's awk extraction;
    resolution failures are already §2g errors — skip unresolved entries here without double-reporting).
  - **Always report** the number (`ok: plugins/crew/agents/morpheus.md loaded footprint: 455 lines (agent 390 + skills 65)`).
  - **Opt-in cap** via a new agent frontmatter key (precedent: `owns-git`/`lane-guarded`), e.g.
    `loaded-lines-cap: <n>`: when present, footprint > cap → `err` with a message saying the cap is
    raised deliberately in the agent's frontmatter, never silently. Non-numeric/empty value → `err`
    (a check that can't parse its subject fails loudly — AGENTS.md).
  - Set caps on `morpheus` and `keymaker` only: post-trim footprint + ~10% slack, rounded up to a
    round number. Workers stay uncapped (reported only) until someone wants caps there.
- Same commit (hard repo rule): negative fixture + silent control in `plugins/crew/tests/`
  (fixture: an agent whose body exceeds a tiny `loaded-lines-cap`, assert on §12's FAIL message;
  control: same agent under cap → silent). Also a fixture for the unparseable-cap path.
- acceptance: `bash scripts/validate-plugin.sh` green on the real tree; new fixtures pass in
  `bash plugins/crew/tests/run.sh`; shellcheck clean; caps present on both orchestrators.

### S6 — Docs sync (same commit as what they describe)
- id: s6
- depends-on: s5
- `plugins/crew/CLAUDE.md`: validator section list (§1–§11 → §12), tests self-test list
  (`§1 · §2a–§2h · … · §11 · §12`), and the agents bullet if the frontmatter key is mentioned there.
- `plugins/keymaker/CLAUDE.md`: mention the cap key if keymaker.md carries it.
- `AGENTS.md` → "Validating changes": describe §12 (one short paragraph, matching the §8–§11 style).
- acceptance: every CLAUDE.md statement matches the new reality (both files carry the "keep
  accurate in the same commit" contract); grep for changed terms across README/AGENTS/CLAUDE
  copies (cross-file wording lens).

### S7 — Releases
- id: s7
- depends-on: s2, s3, s5
- Shipped files changed → release per plugin (AGENTS.md: "a changed shipped file is a release"):
  - crew: `3.13.0` → `3.13.1` (behavior-preserving) + `plugins/crew/CHANGELOG.md` entry under
    `### Changed` — one terse bullet (e.g. "morpheus: relocate design rationale to repo AGENTS.md;
    add `loaded-lines-cap` frontmatter — no behavioral change").
  - keymaker: `0.7.2` → `0.7.3` + matching changelog bullet.
  - `engineering-principles`: untouched (S4 recommends no shared-skill edits) — no bump.
- acceptance: §2h green (manifest version == newest changelog entry, both plugins).

### S8 — Verify and open the PR
- id: s8
- depends-on: s1–s7
- Run what CI runs: `shellcheck plugins/*/hooks/*.sh plugins/*/tests/*.sh scripts/*.sh`,
  `bash scripts/validate-plugin.sh`, `bash plugins/crew/tests/run.sh` (stage new files first —
  §2g/§4 index via `git ls-files`).
- Self-review the diff with AGENTS.md → "Reviewing a prompt change" **before** pushing; classify
  every removed passage (KEEP-compressed / MOVE / DELETE-restatement).
- PR: title `refactor(crew,keymaker): move prompt rationale to AGENTS.md (v3.13.1, v0.7.3)`, short
  body per AGENTS.md (before/after footprint table + `Closes #167`), template if present.
- acceptance: CI green; PR body carries the before/after table and the issue link.

## Out of scope

- Any change to what an agent *does* — thresholds, edge-path behaviors, gates, rosters, schemas.
- Hook scripts and their comments (already covered by the existing rule; #171 did that pass).
- Worker prompts beyond reporting their footprint (they're already ≤ ~63 lines).
- Shared-skill edits (triple release cost; see S4).
- Command files (`commands/*.md`) — they load on invocation, not always; a follow-up if wanted.

## Risks

- **Over-trimming is the failure mode.** Rationale sometimes *is* the instruction for an LLM —
  motivation clauses measurably improve compliance. Hence the classification test, the
  keep-if-arguable default, and no numeric target.
- **§12 cap set too tight** turns routine prompt fixes into cap-raise noise; +10% slack and an
  explicit "raise deliberately" error message mitigate.
- **Doc drift** — three CLAUDE/AGENTS files describe the validator and prompts; S6's grep pass and
  validator §11 (config block) cover it, but §12's description lives only in prose — review it.
