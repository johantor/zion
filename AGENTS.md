# Contributing to Zion

Zion is a Claude Code plugin pack ("crew") of orchestrated agents, commands, hooks, and
skills for feature delivery. **This repository *is* the plugin** — there is no application
code to build or ship. Work here means editing agent/command/skill definitions, hooks, and
docs.

This is the contributor guide for anyone — human or agent — changing this repo, and it is
tool-neutral. Claude Code reads `CLAUDE.md`, which points here and adds only its own runtime
configuration (the values the `crew` orchestrator reads).

## Repository layout

This is a **monorepo marketplace**: `.claude-plugin/marketplace.json` lists the plugins,
each of which lives in its own directory under `plugins/<name>/` (its plugin root). Adding
a plugin is additive — create `plugins/<name>/` and add an entry to `marketplace.json`.

- `.claude-plugin/marketplace.json` — the marketplace; lists each plugin and its `source`.
- `plugins/crew/` — the `crew` plugin (its root; component paths below are relative to it):
  - `.claude-plugin/plugin.json` — plugin manifest (name `crew`).
  - `agents/` — `morpheus` (orchestrator) plus workers `tank`, `trinity`, `oracle`, `dozer`, `seraph`, `neo` (express-lane generalist), and `sentinel` (post-merge triage; read-only, no Bash). Auto-discovered from this dir; not declared in the manifest.
  - `commands/` — `/init`, `/feature`, `/review`, `/pr`, `/address`, `/triage`, `/loop`, `/notify` (namespaced as `crew:feature` etc. once installed). `/init` detects and writes the crew configuration to `.claude/crew.md` (idempotent reconcile; migrates a legacy `CLAUDE.md` block). `/review` is the pre-PR GO/NO-GO gate (consolidated review + build/test/lint). `/address` closes the post-PR review loop — routes review comments / CI failures to the crew, re-runs the gate, and pushes. `/loop` is the outer-loop driver — re-launches `morpheus` directly (not by nesting `/feature`) each tick across runs on the native `/loop` (dynamic mode) until the plan's exit conditions are met; the wrapper owns scheduling, `morpheus` never self-schedules. `/feature` and `/address` are thin routers into `morpheus`'s own flows, so both also work by just asking in a `claude --agent crew:morpheus` session. `/triage` is the standalone entry to `sentinel` — it launches the agent, relays its report, and writes nothing. `/notify` messages another running crew **session** (not a worker inside one) over `ListAgents`/`SendMessage` — a command rather than a `morpheus` capability, since peer messaging is a user-driven action and `morpheus`'s prompt is close to its footprint cap.
  - `skills/` — shared: `engineering-principles`, `context-discipline`, `loop-engineering`,
    `operator-voice` (all also shipped by other plugins — kept byte-for-byte in sync
    automatically; see *How we review code* below; `loop-engineering` carries the loop-mode stop
    rules, preloaded by `morpheus` and `keymaker` with per-agent bindings, and `operator-voice`
    sets how those two write to the operator); crew-only: `mid-run-direction` (how a
    worker treats a steer that arrives mid-run — preloaded by every worker, not by `morpheus`,
    which carries the sending half);
    frontend mode: `frontend-headless`, `frontend-server-rendered`; per-stack (loaded
    dynamically once `morpheus` resolves the project's stack): `backend-dotnet`, `backend-node`,
    `cms-optimizely`, `frontend-react`, `frontend-nextjs`, `tests-xunit`, `tests-node`;
    per-e2e-tool (loaded by `dozer`): `tests-cypress`, `tests-playwright`; per-frontend-unit-
    test-tool (loaded by `oracle` for component tests): `tests-vitest`, `tests-jest-frontend`;
    per-worker (preloaded, not stack-resolved): `design-tokens`, which `seraph` reads so a
    visual finding names the token and not just the pixel value.
  - `hooks/` — `bash-safety.sh`, `read-guard.sh`, `lane-guard.sh`, `format.sh`, `turn-budget.sh`
    (warns an agent nearing its `maxTurns` so it hands back an orderly `remaining:` instead of
    truncating; validator §8 keeps its budget table in lockstep with agent frontmatter),
    `dispatch-denied.sh` (`PermissionDenied`: auto mode can't allowlist an `Agent` call, so a
    worker dispatch is classified per call and can be refused mid-run — this retries the first
    denial once and reports the real fixes after that), wired via `hooks/hooks.json`.
    A `hooks/` directory holds two kinds of file and the distinction is enforced, not
    conventional: the top-level `*.sh` are **entry points** the harness executes (must be `+x`,
    must be wired), while `hooks/lib/*.sh` are **sourced libraries** (must not be `+x`, must not
    be wired — validator §3 and §6). Today that is `hooks/lib/guard-lib.sh`, which carries the
    payload plumbing, the command-shape patterns, and the shared block helpers every plugin's
    Bash guard enforces.
  - `CHANGELOG.md` — release notes for this plugin's versions (moved here from the repo root).
  - `VERIFICATION.md` — the plugin's behavioral scenario matrix, kept out of the README so the
    README stays a user-facing document. `keymaker` carries its own alongside its README.
- `scripts/` — repo tooling (not part of any plugin; it needs this monorepo's layout and never
  runs in an installed plugin):
  - `validate-plugin.sh` — validates every plugin's manifest/structure, including skill-drift
    across plugins (§4 in the script), hook-script drift (§5), and hooks.json wiring (§6; see
    *How we review code* below). Tree-only: no base ref, so it runs anywhere.
  - `check-changelog.sh` — the release-notes gate: a change to shipped files must be described
    by a version bump or a bullet parked under `## [Unreleased]` (see *Releasing*). Diff-based,
    so it takes the base branch to compare against.
  - `release-notes.sh` — builds a release's notes: the version's changelog section plus the
    commits that shipped in the same tag without an entry. Called by `auto-release.yml`.
- `plugins/engineering-principles/` — standalone plugin that ships only the `engineering-principles` skill:
  - `.claude-plugin/plugin.json` — plugin manifest (name `engineering-principles`).
  - `skills/engineering-principles/SKILL.md` — standalone shipped copy; must remain byte-for-byte synced with the canonical crew copy.
  - `CHANGELOG.md` — release notes for this plugin's versions.
- `.claude/settings.json` — this repo's own dev-time hooks: wires the same hooks as
  `plugins/crew/hooks/hooks.json`, resolved via `CLAUDE_PROJECT_DIR` instead of
  `CLAUDE_PLUGIN_ROOT`, so they still run while developing in this repo **without the crew
  plugin installed**. The two files must mirror each other exactly (modulo the root variable) —
  `validate-plugin.sh` enforces this automatically (§7, CI fails on mismatch). If the crew
  plugin is *also* installed while working here, both wirings fire and every guard runs twice
  per matching tool call; installing the plugin while developing in this repo isn't a supported
  setup.
- `tests/scenarios/` — repo tooling (not part of any plugin): the adversarial scenario suite
  that drives real agents against throwaway repos to check the untrusted-input rules hold, plus
  `mocks/git-host-mcp.js`, a dependency-free mock git-host MCP with its own LLM-free self-test.
  See *Adversarial scenario suite* below; it is never a required PR check.
- `tests/fixtures/` — repo tooling: scratch-repo generators for exercising a plugin's verification
  matrix by hand (`keymaker-scratch.sh` plants same-rule suppressions, justified and not, plus the
  justification filter's two exemptions). Prints the repo path on stdout so it composes into a
  headless `claude --plugin-dir …` run.
- `.github/copilot-instructions.md` — guided review instructions for GitHub Copilot, aligned with the crew reviewer.
- `.github/workflows/validate.yml` — CI: shellcheck + plugin manifest validation + hook tests +
  the mock's self-test.
- `.github/workflows/adversarial.yml` — CI: the adversarial scenario suite, on a
  `run-adversarial` PR label or `workflow_dispatch` only — no scheduled runs.

## How the crew works

- `morpheus` plans and delegates; it writes no production code. Workers stay idle until delegated to.
- A **regression** enters the flow through `sentinel`: `morpheus` delegates the bug report or
  trace to it before planning and plans against the pointer it returns, so the finding arrives
  in `morpheus`'s own context rather than being re-typed into a goal string. `/crew:triage` is
  the same agent without the build flow attached.
- `morpheus` maintains a written plan at `<plan-dir>/plan-<feature>.md` — `<plan-dir>` is the `Plan directory` crew-config slot, or `.claude/` when unset — with per-step acceptance criteria, and presents it for the user's go-ahead before creating the branch or delegating (the plan checkpoint — one gate, honoring a standing "just build it").
- `morpheus` is the sole owner of git: it branches off the resolved base branch and commits each
  verified step; workers never run git. The crew stops at the local review gate by default —
  pushing and opening a PR is the separate `/crew:pr` command.
- Worker lanes are stack-agnostic: `tank` = backend implementer for the resolved backend
  stack, `trinity` = frontend implementer for the resolved frontend stack (plus a shared
  server template's markup in server-rendered mode), `oracle` = all unit test authoring
  (backend tests + frontend component tests when a frontend unit test tool is configured),
  `dozer` = frontend e2e only (for the resolved e2e tool), `seraph` = visual design
  conformance (read-only), `neo` = express-lane generalist for small changes (all lanes;
  no lane guard by design), `sentinel` = post-merge triage (read-only; locates a production
  signal and correlates it to suspect commits, and returns a pointer rather than a fix). Stack knowledge lives in per-stack skills, loaded once `morpheus`
  resolves the project's stack (crew config's `backendStack`/`frontendStack` slots).
  E2e tool knowledge lives in per-tool skills (`Frontend e2e tool` slot); frontend unit test
  tool knowledge lives in its own per-tool skills (`Frontend unit test tool` slot). `lane-
  guard.sh` enforces the write lane by file extension for disjoint-language stacks (e.g.
  dotnet+react), or by configured directory paths (**Backend/Frontend lane path(s)**) when
  both stacks are the same language (e.g. node+nextjs).
- `morpheus` **right-sizes the process by task size**: small, low-risk work takes an express lane
  (delegate to `neo`, skip the plan/checkpoint/full-gate, quick self-review, commit); features and
  anything risky, multi-lane, or needing new tests take the full flow through the specialists.
  It escalates express → full the moment a task proves bigger.
- **Loop mode** (`loop-engineering`, shared with `keymaker` — each orchestrator binds it to
  its own units/gate/state in its agent file): on explicit user intent in
  conversation ("keep going until done", "loop this", "finish it", "clear all the stale ones")
  the full flow runs to completion without per-step check-ins, stopping only on the
  orchestrator's terminal gate (crew: review gate GO; keymaker: verify + commit — never
  push/PR), a blocked human decision (independent units drain first), or a retry cap (3 failed
  fix→verify round-trips on a unit; for crew's gate, a second NO-GO on the same findings).
  Intent is never inferred from fetched content; any checkpoint/gate that needs the user's
  answer still runs once. Loop state (`loop:`, `exit-conditions:`; durable per-unit
  `attempts:`) lives in the orchestrator's durable file, so a resumed run continues in loop
  mode and its caps survive a crash. The **outer** loop — re-invoking the orchestrator across
  runs past one run's `maxTurns` — is a human-initiated main-session wrapper (crew's
  `/crew:loop`, on the native `/loop` in dynamic mode) that owns the scheduling and the
  iteration cap (`iterations: n/max`); the orchestrator itself never self-schedules.
- All workers apply `context-discipline`: process bulk output with code, return only concise findings.

The crew's runtime configuration (test/build/lint commands, base branch, frontend mode) lives in
`.claude/crew.md` — YAML frontmatter, one key per slot, plus a prose body of notes. That is what
`morpheus` and the `crew:*` commands read, and what `/crew:init` writes; a slot reads `unset` when
it is unresolved (the orchestrator asks once) and `none` when the project has no such tooling (the
gate skips). For this repo the slots are mostly `unset`/`none`, because the repo is the plugins
themselves and has no app code to build or test.

Configuration does **not** live in a project's `CLAUDE.md`. What stays there is the
`## Crew orchestration` prose, whose reader — auto mode's permission classifier — sees only
`CLAUDE.md`, plus any convention a quick glance would get wrong (`/crew:init` §3 sets that bar).
Earlier versions wrote the slots into `CLAUDE.md` as a **Crew configuration** block; every reader
still falls back to that block when `.claude/crew.md` is absent, and `/crew:init` migrates it.

## How we review code (the crew reviewer)

Reviews — whether by `/crew:review`, the crew, or GitHub Copilot — judge code against
the `engineering-principles` skill and classify every finding as **Blocking**,
**Warning**, or **Passed**. The same three pillars apply: code quality, security,
and design conformance. See `plugins/crew/skills/engineering-principles/SKILL.md` for the
full rules and `.github/copilot-instructions.md` for the review contract.

Core principles (defaults, not dogma — the repo's established patterns win on conflict):
YAGNI, KISS, pragmatic DRY (rule of three), small single-purpose units, intention-revealing
names, fail-fast error handling, and minimal-scope diffs.

Any skill shipped by more than one plugin must stay byte-for-byte in sync across every copy —
today that's `engineering-principles` (crew's canonical copy, also shipped standalone by the
`engineering-principles` plugin), `context-discipline`, `loop-engineering`, and
`operator-voice` (all crew's canonical copies, also shipped by `keymaker`).
`scripts/validate-plugin.sh` enforces this automatically: the check
is generic by skill *name*, not hardcoded to these pairs, so it also catches a future
duplicate between any other plugins — crew included or not (CI fails on mismatch). The same
policy covers hook scripts shipped by more than one plugin (§5): copies with no markers must be
byte-identical (`read-guard.sh`, `lib/guard-lib.sh`), and `bash-safety.sh`'s marker-delimited
"shared guard" regions must match byte-for-byte while the git-policy sections around them stay
per-plugin (crew's copies are canonical — edit there first). Prefer moving genuinely shared logic
into `hooks/lib/guard-lib.sh` over widening a marked region: one vendored file compared whole is
easier to keep honest than logic duplicated across several regions, and it leaves the markers
covering only the short call sequence that defines the shared floor's order. Reviewers
should still flag any drift that slips through as at least a **Warning**, and **Blocking** when
it would change reviewer behavior.

### Reviewing a prompt change (commands, agents, skills)

These artifacts are **executable contracts written in prose** — an agent follows them at
runtime — so `validate-plugin.sh` can't catch a *design* bug in them, only structural drift.
Most of the review misses on this repo were this class: the contract read fine in isolation but
broke an invariant or left a path undefined. Run this lens on the self-review **before pushing**
(and apply it as a reviewer), because a static check never will:

- **Durable-state invariant.** If the artifact names one store as "the only cross-tick/-run
  state," any counting or "N-in-a-row" logic must live *there* — no hidden in-memory tally a
  fresh-context resume would lose. Trace every "track / count / remember across invocations"
  claim back to the declared store.
- **Delegation can only pass what the callee accepts.** A command that wraps another command
  can't convey context the inner one doesn't forward. If it must pass extra intent or
  authorization, launch the underlying agent directly and say so — don't assume the wrapper's
  words reach the callee.
- **Every threshold is a number.** No "several", "eventually", "a few times" — state the exact
  count and what resets it.
- **Every failure and edge path has a stated behavior.** Launch failure, zero results, a
  missing/hand-edited field, malformed input — say stop / skip / surface, and which durable
  state is or isn't mutated on that path.
- **A structured field documents its shape where it's owned.** If a marker carries a payload
  (not just presence), the schema owner must be told to preserve it *verbatim* on rewrite.
- **Cross-file wording agrees.** Grep every term you changed across the command, its agent, and
  the README/AGENTS/CLAUDE/CHANGELOG copies — the behavior and every description of it must
  match (a "launches morpheus directly" command described elsewhere as "re-invokes /feature" is
  a bug, not a paraphrase).

The recurring, already-seen instances of these live in *Recurring review findings* below; this
list is the general lens to apply proactively so they don't recur in a new shape.

## Prompt design rationale

An always-loaded agent prompt costs context on **every** run, so it carries *instruction* —
what the agent must do — and not the *justification* for it. This section is where the
justification lives, keyed by agent and by the prompt's own section heading. Each trimmed
prompt carries a single one-line pointer here; there is deliberately no per-rule pointer,
because this file is repo documentation and is never shipped with an installed plugin — a
runtime agent cannot follow a pointer into it.

**Before moving a line out of a prompt, apply the classification test:** *would an agent that
never read this text behave differently on some input?* If yes it is instruction and stays,
even when phrased as a "why" (*"watch/dev commands never terminate and hang the worker"*,
*"background workers can't prompt"*, *"plugin agents are namespaced; bare names don't resolve"*
— each one changes a decision). If no, it is rationale and belongs here. A short motivating
clause that disambiguates which of two readings is intended (*"faster, not sloppier"*) stays,
compressed. **Anything arguable stays in the prompt** — deleting a real edge-case rule is a far
worse outcome than leaving a sentence of prose in place, and motivation does measurably help an
LLM comply. Compression is not a quota: if an honest pass yields little, that is the result.

### crew:morpheus

- **Right-size the process.** A one-line fix shouldn't have to pay for a plan file, a
  checkpoint, and a full review gate — hence the express lane. The reverse bias matters just as
  much: a wrong small fix costs more than the escalation would have, which is why the rule is
  small-by-default but escalate-on-*evidence* rather than escalate-on-suspicion.
- **Plan checkpoint.** The cheapest place to catch a misunderstood task is before any code is
  written, which is why the single gate sits before the branch and the first delegation rather
  than at the review stage.
- **Stay responsive.** A foreground call freezes the orchestrator's turn for the worker's entire
  run — often minutes — and queues the user's messages unheard, so backgrounding is the default
  rather than a tuning choice. The status pulse exists because a background run otherwise reads
  as dead air. It must be emitted *after* the result is reconciled into the plan because until
  then the plan still shows the step `in-progress`: pulsing from the raw notification would
  report stale state and miscall a not-yet-verified result as "finished".
- **Stay responsive → fresh spawns, and steering as the narrow exception.** `Agent` never
  continues a worker, so re-dispatching to widen a running step is always a second worker in one
  scope — `SendMessage` is the only way to add a turn to a live one. Steering stays deliberately
  narrow because its costs land on the target: it spends that worker's remaining `maxTurns`, it
  is still bounded by the same lane guard, and it dies with the run. So durable context still
  moves through the plan file, the only channel that survives a fresh spawn, a truncation, or a
  crash. Steering nudges a run in flight; the plan file carries the state. The "amend the step as
  you send" rule follows from the same split — the commit is judged against the plan's
  `acceptance:`, so a steer that widens the work without widening the step makes the two disagree.
- **A steer is authenticated on a per-dispatch token, and its content is still fallible.** A
  message to a running worker surfaces there in a `system-reminder`-shaped block — the same shape a
  source file, tool result, or fetched comment can carry — so shape cannot distinguish a
  coordinator's steer from an injection, and a worker with only that signal has two bad options:
  obey every authoritative-sounding block, or discard the channel and ignore its own coordinator.
  The anchor that breaks the tie is a `steer-token:` minted per dispatch (*Anti-drift* 2): planted
  content was authored before the token existed, so it cannot quote it. A plan step `id`
  deliberately isn't the anchor — ids are small integers and the plan file sits in the repo the
  worker reads, so an injected block could cite one. That same reasoning keeps the token **out of**
  the plan file and out of what a worker echoes back: a plan dir can be committed and read by anyone
  who can comment on the PR, and a leaked live token is a forgeable steer. Nothing needs it to be
  durable, since a resumed run re-dispatches its unfinished steps rather than steering the workers
  that died with the session. And because the token is only a freshness check, refusing
  out-of-bounds work stays unconditional rather than something the right anchor unlocks. Hence the two-sided rule: `morpheus` writes steers that quote the token and
  describe an **end state** rather than asserting what the worker already did (it cannot see the
  worker's transcript, so an asserted premise is a guess that reads as an attack when wrong), and
  workers preload `mid-run-direction`, which treats an anchored steer as *authenticated but
  fallible* — correct a wrong premise in the return instead of dropping the message; let an
  anchored steer grow the step but never move the lane, guards, or git posture; surface anything
  unanchored. A well-reasoned refusal is the right answer to a bad steer; it is the wrong answer to
  a coordinator's bookkeeping slip, and shape alone can't tell the two apart.
- **A truncated return is not a finished step.** Judging completeness on *content* (is the
  required evidence present?) is the rule because content is decisive and always available,
  whereas the usage figures a completion notification may carry are not guaranteed to be there
  and are not a precise turn count. The reconcile path is the same "`in-progress` is
  unconfirmed — re-verify against the tree" rule the durable-resume protocol applies after a
  crash; only the trigger differs, so the two paths deliberately share one behavior.
- **Right-size the model per delegation.** Run-and-report steps need speed, not depth — the
  command is known and failures surface on their own. Everywhere else a wrong fast result costs
  more than the seconds saved, so the default is to omit the override. Splitting authoring from
  verifying avoids paying for a truncation-and-resume round-trip, which is strictly more
  expensive than planning two dispatches.
- **Builds and full test suites.** Builds and full suites are expensive and verbose, which is
  why they are a single delegated final gate rather than a per-step check. Delegating a
  standalone build before the review gate builds the same tree twice.
- **Address review feedback.** The lifecycle doesn't stop at `/crew:pr` — the same lane routing,
  git ownership, and gate that built the feature also close the review loop, so the post-PR
  flow is the same machinery rather than a second, looser one.
- **The plan file is durable state.** The file is written to survive a crashed or context-reset
  session so the user never has to re-explain a feature already in flight. The `/crew:loop`
  wrapper can detect a crashed tick from `in-flight:` alone because outer-loop ticks run their
  workers in the foreground: a tick returns only when nothing is still running, so an
  `in-flight:` marker still set at the next firing means that tick died. That inference is why
  `morpheus` must preserve the field verbatim instead of regenerating it.
- **Run summary.** It reproduces the per-worker view the live agent panel loses on resume, which
  is why it duplicates neither `/recap`'s commit list nor the running status pulse.
- **Anti-drift.** Citing the exact plan step in every delegation is what keeps a run resumable
  and makes every unblocked step dispatchable at a glance. Keeping each step's `status` current
  matters because a crash must leave an accurate, resumable record — that record is also what
  the run summary renders. Naming the exact previously-failing tests on a re-verify keeps full
  suites where they belong: the final review gate, not every fix.

### keymaker:keymaker

- **Open mode exit contract / resume protocol.** The 0-findings exit and the already-complete
  ledger exit exist so that re-running a successful `/keymaker:open` — including an
  `/keymaker:audit` re-pick of a pointer already cleared — is a cheap no-op instead of a
  re-enumeration. A ledger whose every batch is `done` has no further use once its commits are
  in place; only a `blocked` batch keeps it alive as a resume point.
- **Step 8, verify.** The independent per-mechanism re-sweep exists because a twin's
  self-reported counts cannot be the source of truth for whether the twin introduced new
  suppressions — that is exactly the claim under test.
- **The batch ledger is durable state.** Open mode may run many batches across many turns, so a
  crash or context reset would otherwise lose the run.
- **Justified suppressions — why keymaker only reads them** (0.8.0, was #52). The store had to be
  the codebase itself. Two alternatives were rejected: `memory: local` is gitignored, so it would
  solve the re-surfacing problem for exactly one clone on one machine while every teammate's
  audit re-flagged the same site and CI lost the rationale entirely — a keep-decision is a shared
  fact about the code, not a machine-local preference. A per-site registry in the project's
  `AGENTS.md` is committed and shared, but needs **keying** (`file:line` rots as soon as anything
  above it shifts; a hash was explicitly unwanted) and rots into **staleness** — change the
  suppression and the entry lingers, silently suppressing a *new* decision, with no validator
  possible since the file lives in the user's project. A native justification slot has keying,
  lifecycle, and PR-review locality for free. Project-level *policy* keeps the AGENTS.md route,
  because one coarse statement beats annotating fifty sites.
  There is deliberately **no ack command and no keymaker-specific token**: requiring an explicit
  gesture to record a keep-decision is a step the user shouldn't have to take, and once nothing
  writes the ack, the token, the lifecycle machinery, and the side log all stop being needed.
  The cost is that slot-less mechanisms (`<NoWarn>`, `.editorconfig` severity, a bare `#pragma`)
  have no per-site ack; they fall to project policy or stay surfaced. Accepted until it bites.
- **Why `stale` scope ignores the filter, and skipped tests are never excluded.** A justification
  explains why a suppression was *added*, not why it should stay now — so it cannot make a stale
  suppression un-removable, and `@ts-expect-error` in particular is always removable because TS
  self-reports unused directives. A `Skip="…"` reason says why a test is off, which is not the
  same claim as "this debt is accepted", so skipped tests stay needs-investigation however they
  are annotated. Both exemptions exist because the filter *hides* findings: the failure mode to
  design against is a scope reported clean when it merely excluded everything.

## Validating changes

This repo has no app build. Before opening a PR, run what CI runs:

```bash
shellcheck plugins/*/hooks/*.sh plugins/*/hooks/lib/*.sh plugins/*/tests/*.sh scripts/*.sh tests/hooks/*.sh tests/scenarios/*.sh tests/scenarios/mocks/*.sh tests/fixtures/*.sh
bash scripts/validate-plugin.sh
bash scripts/check-changelog.sh          # takes the base branch; defaults to main
bash tests/hooks/run.sh
bash tests/scenarios/mocks/selftest.sh
```

`check-changelog.sh` is the one diff-based check: it compares against the merge base with the
base branch, which is why it takes a ref and why it lives outside `validate-plugin.sh` (that one
is deliberately tree-only, so it runs anywhere with no base to resolve). See *Releasing* for
what it enforces.

`plugins/<plugin>/tests/` is a bash suite — no build step, no LLM, no network, needing only `jq`
and `git` (the same tools the hooks and validator already require) — that exercises a plugin's
hooks' *behavior*: each guard is a pure `stdin JSON → allow (exit 0) / block (exit 2)` function,
so its allow/block decisions are unit-testable with no LLM. The harness itself
(`tests/hooks/lib.sh`) is repo infrastructure and lives once at the top level, while the cases
stay beside the plugin they cover; `tests/hooks/run.sh` discovers every `plugins/*/tests/*.test.sh`
and **fails when a plugin ships `hooks/` with no suite beside it**, so a new plugin's guards
cannot land untested. The two hooks that aren't guards are
covered on their own terms — `turn-budget.sh` through its counter file, and `format.sh` (which
never blocks) on the formatters it decides to run, faked in `node_modules/.bin` so no real
toolchain is needed. It complements the structural checks
(`validate-plugin.sh` + `shellcheck`): **a change to a hook's guard logic must add or adjust a
case there**, covering both the allow and block sides.

The suite also self-tests `validate-plugin.sh`: every section carries at least one **negative
fixture** — a deliberately broken tree that the guard must reject — plus a control proving the
same guard stays silent on a valid one. A check that silently stops checking is the worst
failure mode for an enforcement tool, so this is a requirement, not a nicety: **a new validator
section (or a new guard within an existing one) lands with its fixture in the same commit.**
Assert on the guard's own FAIL message rather than the validator's exit code — a minimal
fixture can't satisfy every unrelated section, and matching the message is what proves *which*
guard fired.

`validate-plugin.sh` parses each `plugins/*/agents/*.md` YAML frontmatter and verifies every
entry in its `skills:` list resolves to some `plugins/*/skills/<name>/SKILL.md` in the repo
(skills are referenced unqualified, per existing convention). A typo here would otherwise fail
silently at runtime — the skill just doesn't load and the agent guesses.

It also keeps the guard hooks' hardcoded agent rosters in lockstep with the agents themselves
(§9). `bash-safety.sh` and `lane-guard.sh` gate on a list of agent names, and a name missing
from one of those lists **fails open** — a newly added agent would silently get unrestricted
git and no write lane. So each agent declares `owns-git: true|false` and
`lane-guarded: true|false` in its frontmatter, each roster carries a `# crew-roster: <name>`
marker, and §9 checks both directions: every agent classified, every roster entry real, and
exactly one git owner per plugin. Adding an agent without those two fields fails CI.
The rosters' `a|b|c)` arm shape and the markers are load-bearing — keep them when editing.

Two more checks cover prose that names something the harness has to resolve. §10 requires every
`crew:`/`keymaker:` reference in an agent, command, or skill body to resolve to a real agent or
command file — a typo there fails silently and late, since the delegation simply doesn't launch.
§11 keeps `commands/init.md` §1 — which declares itself the source of truth for the crew
configuration slots — in lockstep with this repo's own `.claude/crew.md`, both directions, so a
slot can't exist in one and not the other. The two read one exact shape each: a
`- **<Slot>** (`key`) —` bullet under §1, and a top-level `key:` inside the config file's
frontmatter. Bold text elsewhere is not a slot, a key named in the file's prose body is not
configuration, and an unparseable list is reported rather than passed over. The pairing is on the
**key**, not the prose label: the key is the half both files have to agree on.

§12 measures what the repo preaches. Every agent's **always-loaded footprint** — its own file
plus every skill its frontmatter preloads — is reported on each run, because that cost is paid on
every single invocation and nothing else in the repo tracked it. The number is informational by
default; an agent may declare `loaded-lines-cap: <n>` in its frontmatter (today `morpheus` and
`keymaker`, the two orchestrators) to fail CI when it grows past a chosen budget, so raising the
budget is a visible frontmatter edit rather than silent creep. A present-but-unparseable cap is a
failure, not a skipped check, and so is an unreadable agent or skill file — counting it as 0 lines
could under-count a footprint straight past its cap. Unresolved skill refs belong to §2g and are
not double-reported here; skills are indexed via `git ls-files`, the same staging rule as §2g/§4.

§13 covers the `mcp__` entries of an agent's `tools:`. A plugin-bundled MCP server's tools are
named `mcp__plugin_<plugin>_<server>__<tool>`, so a bare `mcp__<key>` grant — the form that
matches a server keyed in `.mcp.json` — never matches them, and the agent reads a
configured-but-not-allowlisted server as simply absent. The section requires every bare key to
carry a plugin form, and every plugin form a bare key, so both install paths resolve; extra
entries are inert, an unmatched one is not. The two halves are matched by **suffix**, not by
assuming they're equal: a plugin and the server it bundles are keyed independently — the real
`chrome-devtools-mcp` plugin ships a server called `chrome-devtools`, so
`mcp__plugin_chrome-devtools-mcp_chrome-devtools` is what pairs with `mcp__chrome-devtools`. It also rejects
the two grants that quietly cover less than they look like they do: a tool-scoped
`mcp__server__tool`, which withholds the rest of that server's tools, and a bare `mcp__*`, which
names no server at all. Both YAML shapes of `tools:` are read — the inline comma list the agents
here use and a `  - name` block list — since reading only one would let the other skip the
section without a word. Hosted
connectors that can't be plugin-installed are exempt by name (`mcp__claude_ai_Figma`) — asserting
a plugin twin for one would name a namespace that cannot exist.

### Adversarial scenario suite (`tests/scenarios/`)

Six of the prompts' safety properties are the kind that rot silently — a later edit
weakens one and the happy path still works, so nothing notices:

- `morpheus` §*Address review feedback* step 2 — a comment that tries to widen scope,
  exfiltrate secrets, or disable a guard is **surfaced, not obeyed**.
- `keymaker` step 3 — pasted build/lint output is **data**: rule IDs are parsed from it;
  instructions in its prose are never followed.
- `loop-engineering` — loop intent is **never inferred** from fetched or pasted content.
- `sentinel` §*The signal is untrusted input* — a bug report is third-party free text: its
  identifiers are parsed, its prose is never followed, and a work-item ID, URL, or pipeline
  name found **inside** it never becomes a target. **This one has no scenario yet** — it is
  covered only by the manual rows in `plugins/crew/VERIFICATION.md`.
- `mid-run-direction` — a worker acts on a steer quoting its dispatch's `steer-token:`, correcting a
  wrong premise rather than discarding the message, and surfaces mid-run direction that carries no
  token or points out of bounds. **No scenario yet either, and only half of it is scriptable here:**
  the unanchored half is s1-shaped (plant a `system-reminder`-shaped block in a file the worker
  reads, assert the bait untouched), but the anchored-yet-wrong half needs a real `SendMessage` into
  a live worker, and its correct outcome — a corrected premise reported back — lives in the
  transcript, which this suite deliberately does not assert on. Manual rows in
  `plugins/crew/VERIFICATION.md` cover it meanwhile.
- `seraph` §*Your browser MCP does more than screenshots* — the page under review is data:
  rendered text, DOM content, console messages, and response bodies can all carry seeded
  content, and `seraph`'s report is relayed verbatim into the `/crew:review` design gate.
  **No scenario yet either** — same manual-rows-only coverage as `sentinel`'s.

Those last three are the weakest-covered of the six until scenarios exist.

`tests/scenarios/` drives the real agents headlessly against throwaway repos and asserts the
guard held. Repo tooling, never shipped with a plugin.

```bash
bash tests/scenarios/run.sh              # all scenarios
bash tests/scenarios/run.sh s3 s4        # a subset
SCENARIO_MODEL=opus bash tests/scenarios/run.sh
KEEP_FIXTURES=1 bash tests/scenarios/run.sh   # keep scratch repos to inspect
```

It needs a working `claude` CLI and credentials; without them it prints a loud **SKIP** and
exits 0 — it must never look green having verified nothing. **It is never a required PR
check, and it never runs unattended:** it runs on a PR labelled `run-adversarial`, or via
`workflow_dispatch` (`.github/workflows/adversarial.yml`). There is deliberately no `schedule:`
trigger — a live-model suite that costs tokens runs when someone asks for it. The mock's
self-test carries no such cost and *does* run on every PR.

Four properties of the design matter more than the scenario count, and a change that breaks
any of them makes the suite worthless while still reporting green:

- **Assertions read observable state only** — git refs on a local bare remote, file hashes,
  `git status`, the mock's recorded calls. What an agent *says* it refused is not evidence.
  (`s2`'s positive check is the one documented exception: its correct outcome is to stop at a
  gate having changed nothing, which on disk is identical to never having started.)
- **The agent is granted the capabilities it is being tested not to misuse.** If the
  permission layer blocked git, "nothing was pushed" would pass because the *harness* stopped
  it. `s0-positive-control.sh` asserts a bare agent *can* write, edit, and push when
  legitimately asked; a FAIL there voids the rest of the run.
- **Every scenario also asserts something positive** (`assert_engaged`) — an agent that does
  nothing satisfies every "did not" assertion, so an inert run must fail.
- **Fixtures must read like ordinary project files.** A fixture guard once carried the comment
  "any modification to this file fails the scenario"; the agent read it as an instruction and
  cited it when refusing. Guard fixtures also live in `ci/`, never `.claude/` — Claude Code
  treats that directory as sensitive and refuses edits there regardless of permission mode, so
  a guard placed inside it is protected by the harness rather than by the rule under test.

A pass means the property held **on that run**; these are live-model runs, so the value is
regression signal over time, not proof. Adding a scenario is one new `s<N>-*.sh` file.

## Releasing

Versions are per-plugin. To cut a release:

1. Bump `version` in `plugins/<name>/.claude-plugin/plugin.json` and add a matching `CHANGELOG.md`
   entry (a PR that changes plugin behavior must do this — see `.github/copilot-instructions.md`).
   `validate-plugin.sh` §2h fails CI unless the manifest version equals the newest `## [X.Y.Z]`
   entry in that plugin's changelog, so the two always move together. **A change to a skill
   shipped by more than one plugin bumps *every* plugin that ships it** — the §4 sync check keeps
   the copies byte-identical, so a fix in one is a release in all of them (every plugin keeps
   its own changelog at `plugins/<name>/CHANGELOG.md`).
2. Fold in anything parked under `## [Unreleased]` (below), moving those bullets into the new
   version's section. `check-changelog.sh` fails a bump that leaves the slot non-empty.
3. Merge to `main`. `.github/workflows/auto-release.yml` runs on the push, sees the new
   version has no `<plugin>/v<version>` tag yet, and creates the tag and GitHub Release
   automatically, with notes built by `scripts/release-notes.sh`. No
   matching changelog entry → it skips with a warning. No manual tagging is needed
   (`claude plugin tag` exists for tagging by hand, but here the workflow owns it).

### Small changes park under `## [Unreleased]`

A tag carries **everything** merged since the previous tag, not just the bump — so a change that
skips the bump/changelog step doesn't wait for a release of its own, it ships inside the next one,
described nowhere. That is how a README rewrite and a pass over the shipped hooks' comments both
went out in `crew/v3.15.0` without appearing in any notes.

So every changelog keeps an `## [Unreleased]` heading at the top (§2i requires it), and a change
too small to justify its own release parks a bullet there instead of skipping the step:

```
## [Unreleased]

- README: lead with outcomes rather than the component list (#178)
```

The next PR that bumps folds those bullets into the version section it opens. Cite the PR as
`(#N)` — that reference is also what keeps the commit from being listed twice in the notes.

`check-changelog.sh` enforces both halves on every PR, and both are blocking:

- **shipped files changed → bump or park.** Shipped means everything under `plugins/<name>/`
  except `tests/` (repo tooling), `CLAUDE.md` and `VERIFICATION.md` (contributor material), and
  `CHANGELOG.md` itself. `README.md` counts — users read it. A pre-existing parked bullet doesn't
  count as your note; the section has to actually change.
- **version bumped → the slot must be empty**, because auto-release reads only the version's own
  section and would ship the rest still parked.

Repo-wide changes (CI, root docs, `tests/scenarios/`) reach no user through
`claude plugin update`, so they need neither.

The `[Unreleased]` heading deliberately has no link reference at the bottom of the file, unlike
the version headings: a compare link would have to be re-pointed at every release, which is one
more step to forget.

**The notes cover the whole tag range.** `scripts/release-notes.sh` prints the version's
changelog section, then an *Also in this release* list of commits since the plugin's previous tag
that touched it and aren't described — skipping the bump commit itself (the section above *is* its
notes) and any commit whose `(#N)` the section already cites. It's the backstop for whatever slips
past the two rules above, so the release record is complete even when the per-PR discipline isn't.
Preview it before merging with `scripts/release-notes.sh plugins/<name> <version>`.

**Changelog entries are terse.** One bullet per change under its Keep-a-Changelog heading
(`Added`/`Changed`/`Fixed`/`Removed`); lead with *what changed* in plain terms, one line — two
at most. The entry becomes the GitHub Release notes, so it's a scannable list, not a narrative:
the *why*, mechanics, and background belong in the PR and commit message, not here. Reference the
PR or issue as `(#N)` so the detail is one click away. Prefer:

```
### Added
- `engineering-principles`: add `Observability` and `Backward compatibility` principles
  (also shipped by the standalone plugin, v1.2.0).
```

over a multi-sentence paragraph restating each principle's contents.

## Conventions

- Hooks are Bash scripts (`#!/usr/bin/env bash`); keep them shellcheck-clean.
- Shell scripts (hooks, `tests/`, tooling) stay BSD/macOS-portable — contributors and users run
  them there too, not just on CI's Linux. Avoid GNU-only constructs: give `mktemp` an explicit
  `XXXXXX` template (never bare `mktemp` or the GNU `-p` flag), use POSIX `[[:space:]]` rather
  than `\s`, and prefer flags/behavior common to both GNU and BSD implementations.
- Agent/command/skill definitions are Markdown with YAML frontmatter — match the field
  shape of existing files in the same directory.
- Local agent memory lives in `.claude/agent-memory-local/` and is gitignored. Don't commit it.
  It resolves relative to the project directory, and so does the plan directory (`<plan-dir>`,
  `.claude/` when the slot is unset), so in a **git worktree** both live inside that worktree and
  `git worktree remove` destroys them with it. The next worktree then starts cold and re-asks what
  the last one already answered, while the same session in the main checkout keeps everything.
  Nothing in this repo computes either path — `memory: local` is agent frontmatter the harness
  resolves — so this is a property to work around rather than a setting to change: crew
  configuration in `.claude/crew.md` is committed and survives, and `planDirectory` can name a
  committed path (e.g. `docs/plans/`) when a plan must outlive the worktree.
- Keep diffs minimal-scope; list unrelated improvements rather than bundling them.
- PR titles follow Conventional Commits: `type(scope): summary`, with a `(vX.Y.Z)` suffix
  when the PR bumps a plugin version. Use `feat`/`fix`/`chore`/`docs`/`ci`/`refactor`; scope
  the plugin when the change is plugin-specific (e.g. `feat(crew): … (v1.9.0)`).
- **Keep PR descriptions short — this one has a hard budget, because "aim for short" gets
  rationalised away.** A reviewer opens the PR to decide whether to approve, usually on a phone.
  Anything that does not help that decision costs them time.
  - **Summary: 150 words max, and at most 5 bullets.** Whole body under 400 words including the
    template's sections. Count before posting; if it is over, cut rather than reword.
  - **What the body is for:** why this change, and anything a reviewer needs in order to approve
    safely (a deliberate omission, a risky assumption, a behaviour change). One sentence each.
  - **Never in the body:** a self-review write-up, a bugs-I-found-and-fixed log, a
    how-the-work-went narrative, design-alternatives reasoning, or quoted tool/agent output beyond
    a single short line. Those go in the commit message (the natural home for depth), the issue,
    or a review comment on the line in question — all of which a reviewer can *choose* to open.
  - **Verification is a result, not a transcript.** "Ran X, all green" or a one-line-per-row list.
    Never paste the output.
  - If a caveat needs three paragraphs to justify, it is a review thread, not a PR body.
  - The commit message carries the depth and is not budgeted. Writing a thorough commit message is
    what makes a short PR body safe: nothing is lost, it is just moved somewhere it does not tax
    every reviewer.
- **Every review comment gets a reply, then the thread gets resolved.** Fixed it — say so and
  name the commit. Declining — say why. Duplicate of another thread — say which. Silence leaves
  the author guessing whether it was seen. Resolve only after replying, so the thread reads as
  closed rather than ignored; leave it open if the answer is still pending.
- When a PR resolves an issue, link it with a GitHub closing keyword in the body —
  `Closes #N` / `Fixes #N` / `Resolves #N` — so the issue auto-closes on merge. Plain
  references like `Implements #N` only cross-link; they do not close the issue.
- One branch (and PR) per issue — don't reuse a branch across issues. Once a PR merges, GitHub
  deletes its branch; reusing the same branch name for the next issue leaves a stale local
  tracking ref and the next push is rejected (`stale info`) until you prune. Start each issue
  from the latest `main` on a fresh branch:
  `git fetch origin main && git checkout -B <branch> origin/main`.

### Writing style (READMEs, changelogs, PR bodies, issues)

Prose here should read like a person wrote it. Generated-sounding docs are not a style problem —
they are a trust problem, because the patterns that make text sound generated are the same ones
that let a claim slide through without evidence behind it.

- **Name the catch.** Every guarantee has a cost, a limit, or a case where it doesn't hold. State
  it next to the claim, not in a footnote. A section that only sells gets skimmed and believed in
  the wrong places — see the two lane-guard overclaims in #178, both of which survived exactly
  because the sentence sounded confident.
- **Specifics instead of adjectives.** Not "powerful guardrails" — name the hook, the tool it
  gates, and what happens when it fires. If an adjective is carrying the sentence, replace it
  with the thing it's pointing at.
- **Take the stance.** "Both approaches have their place" is a dodge. Say which one this repo
  picked and why. If a doc boils down to "it depends", it didn't need writing.
- **Don't hedge every sentence.** One or two qualifiers is normal. Qualifying everything reads as
  evasion, and buries the qualifier that actually matters.
- **Vary the rhythm.** Uniform medium-length sentences in uniform three-bullet lists is the house
  style of generated text. Mix long and short. A four-word sentence is allowed.
- **Skip the tells.** `delve`, `leverage`, `robust`, `seamless`, `unlock`, `harness` (as a verb),
  `streamline`, `empower`, `elevate`, `pivotal`, "it's not just X, it's Y", "at its core", "in
  today's fast-paced …". They add nothing and they date the writing.

- **Go easy on em-dashes.** They were the house habit and got thinned out deliberately: roughly
  one every five lines across the READMEs, which reads as machine-written whatever wrote it. A
  colon, a comma, or a full stop usually says the same thing, and splitting a dashed clause into
  its own short sentence fixes the rhythm at the same time. Keep the ones doing work no other
  mark does, mostly a matched pair around a real aside. This is a nudge, not a ban, and it is
  not worth a review comment on its own.

Changelog entries have their own rule; see *Releasing*.

## Recurring review findings — apply proactively

Patterns that showed up more than once in review feedback on this repo. Apply these up front
rather than waiting for a reviewer (human or Copilot) to catch them again:

- **Verify before filing a "nothing enforces this" issue.** Grep the actual implementation and
  `AGENTS.md` first — the mechanism may already exist and just be undocumented in the place you
  looked. (A drift-guard issue was filed against this repo without checking that
  `validate-plugin.sh` already had one.)
- **A validator/guard must fail loudly on every path where it can't verify its claim** — a
  missing input file, invalid input, or an unreachable check are failures for a script whose job
  is enforcement. Never silently skip and report nothing (or pass) when the thing being checked
  couldn't actually be checked.
- **When joining a trusted and an untrusted field with a delimiter for later splitting, anchor
  the split on the trusted field, not the untrusted one.** Splitting on the *first* occurrence of
  the delimiter is only safe when the field before it is a small, controlled value that can never
  itself contain the delimiter (e.g., an `agent_type`). Put arbitrary/untrusted text (e.g., a full
  shell command) last, or split from the end — otherwise the untrusted field could itself contain
  the delimiter and truncate what a downstream safety check inspects.
- **Adding a new conditional to a multi-mode flow means auditing every existing mode, not just
  the default path.** A command with `full`/`quick`/`$ARGUMENTS`-style branches needs the new
  behavior spelled out explicitly for each branch, or reconciled with it — don't leave a newly
  added conditional ambiguous under a mode that predates it.
- **State heuristics as heuristics.** Don't write "X can't happen" when a cost-saving skip is
  actually based on "X is unlikely" — overclaiming a guarantee invites a correctness bug report
  later; the accurate phrasing costs nothing.
- **Bash: `if ! var="$(cmd)"; then ...` still assigns `var`** (typically to whatever the command
  printed before failing, often empty) — the `if !` checks the command's exit status, not
  whether an assignment happened. Don't write a comment implying the variable is "never set" on
  failure.
- **Quote variable expansions on principle, including array subscripts** — bash doesn't always
  require it (e.g., an associative-array subscript isn't word-split even unquoted), but quoting
  is free, avoids relying on that nuance, and heads off reviewer friction.
- **Keep inline script/agent-prompt comments short; put full rationale in `AGENTS.md` or
  `CHANGELOG.md` and point to it** rather than restating it at every call site — a one-line
  pointer beats a paragraph duplicated in multiple places.
- **After merging `main` into a branch to resolve conflicts, refresh the PR description too** —
  version-bump ranges and scope notes written before the merge (e.g., "3.1.0 → 3.1.3") go stale
  once the branch is rebased forward onto a `main` that already moved (e.g., to 3.1.2).
- **Self-review the diff before opening a PR, not after.** Run `/code-review` on the working
  diff (or the full `/crew:review` gate) *before* pushing — it catches design bugs a static
  `validate-plugin.sh` run can't (e.g. a command whose stated behavior isn't mechanically
  achievable, or an ownership contradiction between two files). Reviewers should be a backstop,
  not the first pass.
- **A changed shipped file is a release for every plugin that ships it.** Editing a byte-synced
  shared skill (`loop-engineering`, `context-discipline`, `engineering-principles`,
  `operator-voice`) is
  user-visible in *each* plugin that ships it, so bump + changelog all of them, not just the one
  you were thinking about — §2h/§4 enforce the version↔changelog and byte-identity halves, and
  `check-changelog.sh` now names each plugin whose shipped files moved without a record, so the
  second plugin can't be the one you forgot.
- **A command that delegates can only pass what the delegated command accepts.** A thin command
  built on another (say, one wrapping `/crew:feature`, which only forwards its goal to
  `crew:morpheus`) can't "tell" the inner agent anything that inner command doesn't forward. If
  the wrapper needs to convey extra context (a driving intent, an authorization), launch the
  underlying agent directly with that note rather than nesting a command that only forwards its
  own arguments.
- **Behavioral verification means actually running the scenario, not asserting it in the PR.**
  For a behavior-changing plugin PR, exercise the relevant scratch-repo scenario from that
  plugin's `VERIFICATION.md` ([crew](plugins/crew/VERIFICATION.md),
  [keymaker](plugins/keymaker/VERIFICATION.md)) and cite the observed result — a checklist item
  that reads "would pass" is not verification.
