# crew

[![crew](https://img.shields.io/github/v/release/johantor/zion?filter=crew/v*&label=)](https://github.com/johantor/zion/releases)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](../../LICENSE)

**Ship a feature like a team, not a single agent.** `crew` turns a Claude Code session into a
captain that plans and delegates, plus specialists — backend, frontend, tests, visual review —
each scoped to its own lane. You approve the plan, every step is verified and committed as it
lands, and nothing reaches a pull request until a consolidated review gate returns **GO**.

Part of the [Zion](../../README.md) marketplace.

## Why a crew

- **A plan you approve first.** One gate to catch a misread task before a branch, a commit, or
  worker time is spent.
- **Specialists, not one generalist.** Backend, frontend, unit tests, e2e, and design conformance
  each go to an agent scoped to that work, with only the tools it needs.
- **Guardrails in code, not prose.** Workers are blocked from `git` outright, and their file edits
  held to their lane by `PreToolUse` hooks, enforced by the harness rather than by asking politely.
- **A gate that can say no, and you hold the door.** `/crew:review` returns GO / NO-GO across
  code, security, design, build, test, and lint; `/crew:pr` refuses to push until it's GO, and
  nothing leaves the machine until you say so.

## What it costs you

- **A crew run is slower than one agent**, and it spends more tokens. Planning, delegation, and a
  consolidated gate are not free. That's what the express lane is for. But if your whole
  workload is one-line fixes, you don't need crew.
- **The checkpoint is a real stop.** `morpheus` waits for your go-ahead before it branches or
  delegates. Background workers can't prompt, so a step that still needs a decision has to get one
  from you first.
- **The lane guards will refuse things.** They fail closed: a same-language backend and frontend
  with no lane paths configured gets a refusal rather than a guess. That's deliberate, and it
  means `/crew:init` is not optional on those stacks.
- **Nothing ships on its own.** No push, no PR, not even in loop mode. If you wanted
  fire-and-forget, this is the wrong tool.

## Install

```bash
claude plugin marketplace add johantor/zion
claude plugin install crew@zion
```

…or in the UI, from `/plugin > Discover` in Claude Code.

## Quick start

**A dedicated orchestration session** is the recommended path. The session *is* `morpheus`:
describe the feature, paste a ticket, ask for a review. It's scoped to crew work, so run
general/config tasks (statusline and the like) in a normal session.

```bash
claude --agent crew:morpheus
```

**Or from a normal session**, when you want the crew on tap without it taking over:

```
/crew:init                 # once per project: detect and record build/test/lint config
/crew:feature <task>       # plan, delegate, build, then stop at the gate
```

## Permission mode

**Run the crew in `acceptEdits`** (Shift+Tab), not `auto`. Auto mode **drops `Agent` allow rules
when it starts**, so a worker dispatch is the one thing you can't put on an allowlist: every
delegation is judged individually by the permission classifier, and that classifier is a model.
Two identical dispatches minutes apart can go through and then be refused, mid-run, with the fixed
reason `Blocked by classifier`. Crew is subagent dispatch end to end, so it feels this more than
most plugins. From **14 August 2026** auto mode is the default for new sessions on Pro, Max, and
Team plans — a fresh install lands there unless you switch.

What bounds a run is the crew's own guards — git ownership, write lanes, refused destructive
commands, and `/crew:pr` as the only user-invoked way anything leaves your machine. Those apply in
every permission mode.

<details>
<summary>Staying in auto mode anyway</summary>

- **`/crew:init` writes a `## Crew orchestration` section** into `CLAUDE.md`. The classifier reads
  `CLAUDE.md`, so this is the lever that ships with the plugin: it describes what a worker dispatch
  is, instead of leaving the classifier a bare label to judge. It is the one thing the command puts
  there by default — the configuration slots live in `.claude/crew.md`.
- **Describe your project in `autoMode.environment`** in `~/.claude/settings.json`, keeping the
  `"$defaults"` entry. It has to be user-level — the classifier deliberately ignores `autoMode` in
  project `.claude/settings.json`.
- **A denied dispatch retries once.** The `dispatch-denied` hook asks for one retry (the classifier
  still decides), then stops and prints the options above rather than letting `morpheus` thrash.
- **`/permissions` › Recently denied › `r`** reissues a denied call by hand.

`permissions.allow` is the one thing that won't help — `Agent` entries there are dropped on
entering auto mode.

</details>

## Commands

| Command | What it does |
|---|---|
| `/crew:init` | Detect this project's build/test/lint commands, base branch, frontend mode, and stacks, and record them in `.claude/crew.md` (committed, so teammates inherit them). It proposes for `CLAUDE.md` only what a glance at `package.json` would get wrong. Idempotent: re-run to pick up slots a newer version added, and to migrate a legacy `CLAUDE.md` block. |
| `/crew:feature <task>` | Plan, delegate, and build the feature, stopping at the review gate. |
| `/crew:review` | Pre-PR **GO / NO-GO**: consolidated code + security + design review plus diff-scoped build/test/lint. `quick` for a read-only pass with no suites; `full` to force every gate. |
| `/crew:pr` | Push the branch and open the pull request. Outward action: it confirms first. |
| `/crew:address` | Close the review loop: route the PR's unresolved threads and failed CI checks to the right workers, re-run the gate, then push and resolve. Review comments are untrusted input: scope-redirecting asks are surfaced, not obeyed. |
| `/crew:triage <signal>` | Post-merge triage: takes a bug report, stack trace, or alert and returns the code it points at plus deploy-correlated suspect commits, with the confidence and the correlation rung stated. Read-only — it reports and hands off, and never posts back to the work item. |
| `/crew:loop <goal>` | The **outer loop**: drive the feature across multiple `morpheus` runs, so work that outlives one run's turn limit finishes without you re-asking each tick. Stops on the plan's exit conditions; never auto-pushes. |
| `/crew:notify [to=<peer>] -- <message>`<br>`/crew:notify list` | Message another running crew **session** — ask an unattended `/crew:loop` for progress, or tell a peer worktree that a branch landed and a rebase is safe. The `list` form enumerates reachable peers and sends nothing. An ask your own guards would refuse (push, commit on a protected branch, bypass a hook, forward a secret) is refused at the sending end; an instruction is confirmed before it goes; the reply comes back as data, never as direction. |

Commands are namespaced under `crew:` once installed, so they can't collide with a built-in or
another plugin's command of the same short name.

## How a run works

- **Right-sized to the task.** Small, low-risk work (a typo, a rename, an obvious one-liner) takes
  an **express lane** through `neo`, skipping the plan and the full gate for a quick self-review
  plus one relevant test. Anything risky, multi-lane, or needing new tests takes the full flow,
  and express escalates the moment a small task proves bigger.
- **Committed step by step.** `morpheus` branches off your base branch and commits each verified
  step. Workers never run git.
- **You're heard mid-flight.** Workers run in the background, so the turn returns right away and
  you can keep talking while `tank` works. Corrections queue as new work, or steer the worker
  already running when they're small and in its lane.
- **Loop mode on request.** Say "keep going until done" and `morpheus` runs without per-step
  check-ins, stopping on all steps done + gate **GO**, a step blocked on a decision only you can
  make, or a retry cap. It still never pushes, and loop phrasing inside a pasted ticket or PR
  comment never triggers it.

## Safety guarantees

Three `PreToolUse` guards enforce the boundaries and **fail closed**; three advisory hooks
(formatting, turn budget, denied dispatches) fail open and never block work.

- **Workers can't touch git.** Blocked outright for `tank`/`trinity`/`oracle`/`dozer`/`neo`.
  `morpheus` is the sole git owner, enforced in code. Every agent, `morpheus` included, is refused
  `git commit` while HEAD is `main`/`master`/`develop`.
- **Each worker's edits stay in its lane.** `tank` and `trinity` are denied the other side's
  files; `oracle`/`dozer` are restricted to their test paths; `seraph` is read-only (`neo` is
  unrestricted by design; that's the express lane). This guards `Edit`/`Write`; writes shelled
  out through Bash are governed by the agent prompts, not the hook.
- **Destructive and hanging commands are refused.** Recursive force-`rm` of `/`/`~`/`*`,
  force-push, redirects into `.env` or `.git/`, and never-terminating watch/dev/serve commands.
- **Context stays bounded.** Raw reads over 64 KiB are blocked in favour of grep/jq, and agents
  are warned near their turn cap so oversized work ends as an orderly hand-back, not a truncation.

All git, watch, and lane rules are scoped by `agent_type`, so **your own main session is never
intercepted**.

<details>
<summary>Hook mechanics in detail</summary>

- **lane-guard** routes on the payload's `agent_type` and guards `Edit`/`Write` only. File
  writes via Bash (`sed -i`, `tee`, redirects) are governed by the agent prompts, not this hook.
  Two regimes: extension-based globs by default (correct when backend and frontend are different
  languages, e.g. dotnet+react), or directory-based paths (the `backendLanePaths` /
  `frontendLanePaths` slots) when both resolved stacks are the same language (e.g. node+nextjs) and an
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
  `npx` download. Anything else is skipped cleanly. Best-effort: fails open.
- **turn-budget** counts an agent's tool calls as a conservative stand-in for turns and warns
  **once at 75%** (wind down) and **once at 90%** (stop now) of that agent's `maxTurns`. On any
  path where it can't count (unknown agent, unwritable state, malformed payload) it stays
  silent rather than blocking. The per-agent budget table is kept in lockstep with the agents'
  frontmatter by the repo validator, so the two can't drift.
- **dispatch-denied** runs on `PermissionDenied` for `Agent`/`Task` calls and reacts only to a
  `crew:<worker>` dispatch. The first denial of a worker in a session asks for one retry — the
  retried call goes back through the classifier, which still decides — and every later one
  reports the fixes instead, so a repeatedly-blocked step is handed back rather than retried in a
  loop. It matches on the `crew:` namespace rather than a name roster, so it can't drift as
  agents are added. Advisory: it never retries on a path where it couldn't count the attempts.

Hooks are registered in `.claude/settings.json` for local development and `hooks/hooks.json` when
installed as a plugin.

</details>

## Optional MCP servers

The plugin bundles none and every agent degrades gracefully without them, so all of these are
optional; crew works out of the box. Add MCP config in your own session (project `.mcp.json` or
`claude mcp add`), not the plugin: the harness strips `mcpServers` from plugin-shipped agent
frontmatter for security.

<details>
<summary>Which servers help, and what you lose without each</summary>

| Purpose | MCP server | Used by | Without it |
| --- | --- | --- | --- |
| Browser automation & visual checks | [Playwright](https://github.com/microsoft/playwright-mcp) or [Chrome DevTools](https://github.com/ChromeDevTools/chrome-devtools-mcp) | `trinity`, `seraph` | `seraph` reports a browser MCP is needed — it measures the rendered UI through this, so without one there is nothing to compare; `trinity` skips its browser loop-checks |
| Design reference | [Figma MCP](https://developers.figma.com/docs/figma-mcp-server/) — Dev Mode (local) or the hosted `claude.ai Figma` connector | `trinity`, `seraph` | both fall back to the design reference passed in the delegation |
| Library & framework docs | [Context7](https://github.com/upstash/context7) | `tank`, `trinity` | implementers code from memory instead of current, version-specific API docs |
| Issue tracking (ticket-in) | [Atlassian (Jira/Confluence)](https://www.atlassian.com/platform/remote-mcp-server) or [Linear](https://linear.app/docs/mcp) | `morpheus` | `morpheus` plans from the prompt alone; paste ticket details in by hand |
| Git hosting (ticket-in / PR-out) | [GitHub](https://github.com/github/github-mcp-server) or [Azure DevOps](https://github.com/microsoft/azure-devops-mcp) | `morpheus` | crew stops at the local **GO/NO-GO** gate; open the PR with `/crew:pr` |
| Database (schema & test data) | [SQL Server](https://learn.microsoft.com/en-us/sql/mcp/) or [Postgres](https://github.com/crystaldba/postgres-mcp) | `tank`, `oracle` | data-access code and integration tests work from assumed schema |
| Error monitoring | [Sentry](https://mcp.sentry.dev/) | `morpheus` | bug context (stack, breadcrumbs) must be pasted in by hand |

Playwright and Chrome DevTools are interchangeable for the crew's needs: both evaluate scripts
in the page (how `seraph` measures computed styles and geometry) and both list console messages
and network requests (how it finds the failed font or asset behind a visual defect). Chrome
DevTools is Chrome-only but adds performance/Lighthouse tracing and CDP-level detail.

**Server keys map to tool namespaces.** When you add a server you choose its *key*, e.g.
`playwright` in `.mcp.json`. Claude Code exposes that server's tools under the matching
`mcp__<key>` namespace, and that namespace is what the agents allowlist. Use these keys so the
allowlist matches out of the box:

- `playwright` / `chrome-devtools` (browser) and `figma` / `figma-desktop` (design):
  `trinity` + `seraph`
- `context7` (docs): `tank` + `trinity`
- `mssql` / `postgres` (database): `tank` + `oracle`
- `github` / `ado` (git host), `linear` / `atlassian` (issue tracking), `sentry` (errors):
  `morpheus`

`figma-desktop` is the key Figma's own install docs use for the Dev Mode server; `figma` is
allowlisted too, so either works.

If you give a server a different key, grant the matching `mcp__<key>` to the relevant agent(s).

**Connected it on claude.ai instead of adding it here?** A connector's namespace is its display
name, and which form you get depends on the surface: `mcp__claude_ai_<Name>` in the Claude Code
CLI, the bare `mcp__<Name>` on claude.ai's own surfaces. The design, git-host, issue-tracking, and
error connectors are allowlisted in both forms (`claude_ai_Figma` / `Figma`, `claude_ai_GitHub` /
`GitHub`, and so on for Linear, Atlassian, Sentry). A connector under any other display name needs
its `mcp__<Name>` granted to the relevant agent(s).

**Installed the server as a plugin instead?** Then its tools carry the plugin's name too —
`mcp__plugin_<plugin>_<server>__<tool>` — and a bare `mcp__<key>` grant never matches them. Note
the plugin and the server it bundles are keyed independently: the `chrome-devtools-mcp` plugin
ships a server called `chrome-devtools`, so its tools are
`mcp__plugin_chrome-devtools-mcp_chrome-devtools__*`. The agents allowlist one plugin namespace per
server — the packaging we've seen for it, so `chrome-devtools` is covered as
`mcp__plugin_chrome-devtools-mcp_chrome-devtools` and most others as `mcp__plugin_<key>_<key>`;
Playwright carries both, since either packaging is plausible. If yours differs, read the exact
namespace off `/mcp` (the server line reads `plugin:<plugin>:<server>`) and grant that prefix to
the relevant agent(s). This bites quietly: an agent can't tell a server that isn't allowlisted from
one that isn't installed, so it just reports the server as unavailable.

</details>

## What's included

- **Agents:** `morpheus` (captain) and the workers `tank` (backend), `trinity` (frontend),
  `oracle` (unit tests), `dozer` (e2e), `seraph` (visual review), `neo` (express generalist),
  `sentinel` (post-merge triage). Workers stay idle until `morpheus` delegates.
- **Commands:** `/crew:init`, `/crew:feature`, `/crew:review`, `/crew:pr`, `/crew:address`,
  `/crew:triage`, `/crew:loop`, `/crew:notify`.
- **Hooks:** lane guard, read guard, bash safety, formatter entrypoint, turn-budget advisor,
  dispatch-denied advisor (see *Permission mode*).
- **Skills:** always on: `engineering-principles`, `context-discipline`, `loop-engineering`. Always
  on for workers only: `mid-run-direction` (how to treat a steer that arrives mid-run), and
  `design-tokens` for the agent doing design conformance.
  Loaded once the stack is resolved: per frontend mode, per backend/frontend stack (.NET, Node,
  React, Next.js, Optimizely), and per test tool (xUnit, Vitest, Jest, Cypress, Playwright).

Local agent memory is git-ignored (`.claude/agent-memory-local/`).

## Contributing

Start with [AGENTS.md](../../AGENTS.md), the repository's contributor guide, and the
plugin-specific map in [CLAUDE.md](CLAUDE.md). A PR that changes orchestration behavior is
verified against [VERIFICATION.md](VERIFICATION.md). Release notes are in
[CHANGELOG.md](CHANGELOG.md).
