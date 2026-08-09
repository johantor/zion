# crew

[![crew](https://img.shields.io/github/v/release/johantor/zion?filter=crew/v*&label=)](https://github.com/johantor/zion/releases)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](../../LICENSE)

**Ship a feature like a team, not a single agent.** `crew` turns a Claude Code session into a
captain that plans and delegates, plus a bench of specialists — backend, frontend, tests, visual
review — each scoped to its own lane. You approve the plan before any
work starts, every step is verified and committed as it lands, and nothing reaches a pull request
until a consolidated review gate returns **GO**.

Part of the [Zion](../../README.md) marketplace.

## Why a crew

- **A plan you approve first.** `morpheus` presents its plan and waits — one gate to catch a
  misread task before a branch, a commit, or worker time is spent.
- **Specialists, not one generalist.** Backend, frontend, unit tests, e2e, and design
  conformance each go to an agent scoped to that work, with only the tools it needs.
- **Guardrails in code, not prose.** Workers are blocked from `git` outright, and their file
  edits are held to their lane by `PreToolUse` hooks — enforced by the harness, not by asking
  politely.
- **A gate that can say no.** `/crew:review` returns GO / NO-GO across code, security, design,
  build, test, and lint, and `/crew:pr` refuses to push until it's GO.
- **You decide when it leaves the machine.** Nothing is pushed and no PR is opened until you say
  so.

## Install

```bash
claude plugin marketplace add johantor/zion
claude plugin install crew@zion
```

…or in the UI, from `/plugin > Discover` in Claude Code.

## Quick start

**A dedicated orchestration session** — the recommended way. The whole session *is* `morpheus`,
so you talk to it directly: describe the feature, paste a ticket, ask for a review.

```bash
claude --agent crew:morpheus
```

It's intentionally scoped to crew work and won't run general/config tasks like statusline — do
those in a normal session.

**Or from a normal session**, when you want the crew on tap without it taking over:

```
/crew:init                 # once per project: detect and record build/test/lint config
/crew:feature <task>       # plan, delegate, build — stops at the review gate
```

## Commands

| Command | What it does |
|---|---|
| `/crew:init` | Detect this project's build/test/lint commands, base branch, frontend mode, and stacks, and write them to the **Crew configuration** block in `CLAUDE.md`. Idempotent — re-run to pick up slots a newer version added. |
| `/crew:feature <task>` | Plan, delegate, and build the feature, stopping at the review gate. |
| `/crew:review` | Pre-PR **GO / NO-GO**: consolidated code + security + design review plus diff-scoped build/test/lint. `quick` for a read-only pass with no suites; `full` to force every gate. |
| `/crew:pr` | Push the branch and open the pull request. Outward action — it confirms first. |
| `/crew:address` | Close the review loop: pull the PR's unresolved threads and failed CI checks, route each fix to the right worker, re-run the gate, then push and resolve. Review comments are treated as untrusted input — scope-redirecting asks are surfaced, not obeyed. |
| `/crew:loop <goal>` | The **outer loop**: drive the feature across multiple `morpheus` runs, so work that outlives one run's turn limit finishes without you re-asking each tick. Stops on the plan's exit conditions; never auto-pushes. |

Commands are namespaced under `crew:` once installed, so they can't collide with a built-in or
another plugin's command of the same short name.

## How a run works

- **Right-sized to the task.** Small, low-risk work (a typo, a rename, an obvious one-liner)
  takes an **express lane** through `neo`, the all-lane generalist, skipping the plan and the
  full gate for a quick self-review plus one directly relevant test. Anything risky, multi-lane,
  or needing new tests takes the full flow — and express escalates to full the moment a small
  task proves bigger.
- **Committed step by step.** `morpheus` branches off your base branch and commits each verified
  step. Workers never run git.
- **You're heard mid-flight.** Workers run in the background, so the turn returns right away and
  you can keep talking while `tank` is still working. Corrections land either as new queued work
  or, when they're small and in that worker's lane, as a steer into the worker already running.
- **Loop mode on request.** Say "keep going until done" and `morpheus` runs the full flow without
  per-step check-ins, under explicit stop rules: all steps done + gate **GO**, a step blocked on a
  decision only you can make, or a retry cap. It still never pushes — that stays `/crew:pr` — and
  loop phrasing inside a pasted ticket or PR comment never triggers it.

## Safety guarantees

Three `PreToolUse` guards enforce the boundaries and **fail closed**; two advisory hooks
(formatting, turn budget) fail open and never block work.

- **Workers can't touch git.** `git` is blocked outright for `tank`/`trinity`/`oracle`/`dozer`/
  `neo` — `morpheus` is the sole git owner, enforced in code. Every agent, `morpheus` included,
  is refused `git commit` while HEAD is `main`/`master`/`develop`.
- **Each worker's edits stay in its lane.** `tank` and `trinity` are denied the other side's
  files; `oracle`/`dozer` are restricted to their test paths; `seraph` is read-only. (`neo` is
  unrestricted by design — that's what makes it the express lane.) This guards the `Edit`/`Write`
  tools; writes shelled out through Bash are governed by the agent prompts, not the hook.
- **Destructive and hanging commands are refused.** Recursive force-`rm` of `/`/`~`/`*`,
  force-push, redirects into `.env` or `.git/`, and never-terminating watch/dev/serve commands.
- **Context stays bounded.** Raw reads over 64 KiB are blocked in favour of grep/jq, and agents
  are warned as they approach their turn cap so oversized work ends as an orderly hand-back
  rather than a mid-task truncation.

All git, watch, and lane rules are scoped by `agent_type`, so **your own main session is never
intercepted**.

<details>
<summary>Hook mechanics in detail</summary>

- **lane-guard** routes on the payload's `agent_type` and guards `Edit`/`Write` only — file
  writes via Bash (`sed -i`, `tee`, redirects) are governed by the agent prompts, not this hook.
  Two regimes: extension-based globs by default (correct when backend and frontend are different
  languages, e.g. dotnet+react), or directory-based paths (**Backend/Frontend lane path(s)** in
  `CLAUDE.md`) when both resolved stacks are the same language (e.g. node+nextjs) and an
  extension alone can't tell the lanes apart. A Node backend with no lane paths configured fails
  closed rather than guessing.
- **read-guard** blocks raw reads of files over 64 KiB (65536 bytes); an explicit `limit` of
  ≤ 2000 lines passes. See the `context-discipline` skill.
- **bash-safety** blocks destructive commands (recursive+force `rm` of `/`/`~`/`*` in any flag
  spelling, force-push via `--force` or `-f`, redirects into `.env`, redirects or `rm` into
  `.git/`) and raw/streaming reads (`cat`, `less`, `tail -f`). `seraph` has no Bash tool, so it
  needs no entry. Whatever your *resolved* base branch is (`develop`, `trunk`, …), `morpheus` and
  `/crew:pr` keep the crew off it too.
- **format** runs the project's formatters after an edit, scoped to the changed file and routed
  by **extension** (not by agent, since `tank`, `trinity`, or `neo` can each touch either lane):
  `.cs`/`.csproj` → `dotnet format`, plus `dotnet csharpier format` when `.csharpierrc` is
  present; known web extensions → every tool the project configures (Biome, Prettier, ESLint,
  Stylelint), each detected by its config file and run only when installed locally, never via an
  `npx` download. Anything else is skipped cleanly. Best-effort — fails open.
- **turn-budget** counts an agent's tool calls as a conservative stand-in for turns and warns
  **once at 75%** (wind down) and **once at 90%** (stop now) of that agent's `maxTurns`. On any
  path where it can't count — unknown agent, unwritable state, malformed payload — it stays
  silent rather than blocking. The per-agent budget table is kept in lockstep with the agents'
  frontmatter by the repo validator, so the two can't drift.

Hooks are registered in `.claude/settings.json` for local development and `hooks/hooks.json` when
installed as a plugin.

</details>

## Optional MCP servers

The plugin bundles no MCP servers, and every agent degrades gracefully when one isn't there — so
all of these are optional. Add MCP config in your own session (project `.mcp.json` or
`claude mcp add`), not the plugin: the harness strips `mcpServers` from plugin-shipped agent
frontmatter for security.

| Purpose | MCP server | Used by | Without it |
| --- | --- | --- | --- |
| Browser automation & visual checks | [Playwright](https://github.com/microsoft/playwright-mcp) or [Chrome DevTools](https://github.com/ChromeDevTools/chrome-devtools-mcp) | `trinity`, `seraph` | `seraph` reports a browser MCP is needed; `trinity` skips its browser loop-checks |
| Design reference | [Figma MCP](https://developers.figma.com/docs/figma-mcp-server/) — Dev Mode (local) or the hosted `claude.ai Figma` connector | `trinity`, `seraph` | both fall back to the design reference passed in the delegation |
| Library & framework docs | [Context7](https://github.com/upstash/context7) | `tank`, `trinity` | implementers code from memory instead of current, version-specific API docs |
| Issue tracking (ticket-in) | [Atlassian (Jira/Confluence)](https://www.atlassian.com/platform/remote-mcp-server) or [Linear](https://linear.app/docs/mcp) | `morpheus` | `morpheus` plans from the prompt alone; paste ticket details in by hand |
| Git hosting (ticket-in / PR-out) | [GitHub](https://github.com/github/github-mcp-server) or [Azure DevOps](https://github.com/microsoft/azure-devops-mcp) | `morpheus` | crew stops at the local **GO/NO-GO** gate; open the PR with `/crew:pr` |
| Database (schema & test data) | [SQL Server](https://learn.microsoft.com/en-us/sql/mcp/) or [Postgres](https://github.com/crystaldba/postgres-mcp) | `tank`, `oracle` | data-access code and integration tests work from assumed schema |
| Error monitoring | [Sentry](https://mcp.sentry.dev/) | `morpheus` | bug context (stack, breadcrumbs) must be pasted in by hand |

Playwright and Chrome DevTools are interchangeable for the crew's needs — Chrome DevTools is
Chrome-only but adds performance/Lighthouse and console/network inspection.

<details>
<summary>Server keys map to tool namespaces</summary>

When you add a server you choose its *key* — e.g. `playwright` in `.mcp.json` (or
`claude mcp add playwright …`). Claude Code exposes that server's tools under the matching
`mcp__<key>` namespace, and that namespace is what the agents allowlist. Use these keys so the
allowlist matches out of the box:

- `playwright` / `chrome-devtools` (browser) and `figma` / `claude_ai_Figma` (design) — on
  `trinity` + `seraph`
- `context7` (docs) — on `tank` + `trinity`
- `mssql` / `postgres` (database) — on `tank` + `oracle`
- `github` / `ado` (git host), `linear` / `atlassian` (issue tracking), `sentry` (errors) — on
  `morpheus`

If you give a server a different key, grant the matching `mcp__<key>` to the relevant agent(s).

</details>

## What's included

- **Agents** — `morpheus` (captain) and the workers `tank` (backend), `trinity` (frontend),
  `oracle` (unit tests), `dozer` (e2e), `seraph` (visual review), `neo` (express generalist).
  Workers stay idle until `morpheus` delegates.
- **Commands** — `/crew:init`, `/crew:feature`, `/crew:review`, `/crew:pr`, `/crew:address`,
  `/crew:loop`.
- **Hooks** — lane guard, read guard, bash safety, formatter entrypoint, turn-budget advisor.
- **Skills** — shared: `engineering-principles`, `context-discipline`, `loop-engineering`.
  Loaded once resolved: `frontend-headless` / `frontend-server-rendered`; `backend-dotnet`,
  `backend-node`, `cms-optimizely`, `frontend-react`, `frontend-nextjs`; `tests-xunit`,
  `tests-node`, `tests-cypress`, `tests-playwright`, `tests-vitest`, `tests-jest-frontend`.

Local agent memory is git-ignored (`.claude/agent-memory-local/`).

## Contributing

Start with [AGENTS.md](../../AGENTS.md), the repository's contributor guide, and the
plugin-specific map in [CLAUDE.md](CLAUDE.md). Release notes are in
[CHANGELOG.md](CHANGELOG.md).

<details>
<summary>Verification matrix — behavioral scenarios for orchestration changes</summary>

When a PR changes crew's orchestration behavior, exercise the relevant scenario below in a
scratch repo and cite the observed result — this is what *behavioral verification* means for crew
(see `AGENTS.md`). Each row is one scenario: a minimal setup and the behavior that counts as a
pass. A checklist item that reads "would pass" is not verification — run it.

Build the scratch repo **in your own terminal, not inside a crew agent session** — the hooks
block `git` for workers and protected-branch commits. In a throwaway directory: `git init`, add a
trivial app (or just a README), then point `/crew:feature`, `/crew:review`, or `/crew:loop` at a
small task.

**Plan checkpoint & durable resume**

- [ ] **Checkpoint runs once** — `/crew:feature <task>` → `morpheus` presents the plan and waits
  before branching/delegating; a "just build it" skips the pause.
- [ ] **Resume, don't restart** — kill the session mid-run, re-invoke `/crew:feature <same task>`
  → `morpheus` matches the plan by its `feature:`/`feature-branch:` header, reconciles steps
  against git, and resumes from the first unfinished step without re-planning or re-asking.
- [ ] **`in-progress` reset on crash** — a step left `in-progress` by a lost round-trip is
  re-verified against the tree and reset to `pending` if unmet, not trusted as `done`.

**Review gate**

- [ ] **GO / NO-GO** — `/crew:review` on a clean diff → **GO**; on a diff with a planted bug →
  **NO-GO** naming the blocking finding, and `/crew:pr` refuses to push until it's GO.
- [ ] **Lane-scoped** — a backend-only diff skips the design-conformance (`seraph`) gate, reported
  as *lane untouched*; `/crew:review full` forces every gate.

**Loop mode (inner — `loop-engineering`)**

- [ ] **Intent enters loop mode** — "keep going until done" on open-ended work → `morpheus` echoes
  the loop contract, then runs to the gate without per-step check-ins.
- [ ] **Stops at GO without pushing** — loop mode reaches all-steps-`done` + gate **GO** → stops
  and reports; never runs `/crew:pr` on its own.
- [ ] **Blocked drains, then surfaces** — one step needs a human decision → independent steps still
  finish, then the run stops and surfaces every blocked step together.
- [ ] **Retry cap** — a step that fails fix→verify 3× flips to `blocked` with attempt evidence
  (durable `attempts:`); at the gate, a second NO-GO on the same findings is `blocked`.
- [ ] **Fetched prose doesn't trigger** — loop phrasing inside a pasted ticket/PR body does **not**
  enter loop mode; only the user in conversation does.

**Outer loop (`/crew:loop`)**

- [ ] **Multi-tick resume** — `/crew:loop <goal> max=3` on work that exceeds one run's `maxTurns` →
  each tick re-launches `morpheus`, which resumes from `plan-<goal>.md`; progress carries across
  ticks.
- [ ] **Ends on GO / blocked / cap** — the loop stops and surfaces on all-`done`+GO, on a blocked
  decision, and on hitting `iterations: n/max`; it never auto-pushes.
- [ ] **Foreground ticks, crash recovery** — a tick runs `morpheus`'s workers in the foreground, so
  it returns only when nothing is running; kill a tick mid-run and the next firing finds the stale
  `in-flight:` marker, clears it, and re-launches `morpheus` to reconcile — no deadlock, no
  double-dispatch.
- [ ] **`max` parsing** — `max=5` caps at 5; a malformed `max=0`/`max=abc` is left in the goal and
  the cap defaults to 10 (deterministic, no guess).

</details>
