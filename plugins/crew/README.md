# crew

A Claude Code plugin: orchestrated agents, commands, hooks, and skills for
feature delivery. Part of the [Zion](../../README.md) marketplace.

## Install

Via the CLI:

```bash
claude plugin marketplace add johantor/zion
claude plugin install crew@zion
```

…or in the UI, from `/plugin > Discover` in Claude Code.

## Usage

The recommended way to run the crew is a **dedicated orchestration session**: start Claude
Code *as* the orchestrator with

```bash
claude --agent crew:morpheus
```

The whole session **is** `morpheus` (its own tools, lane guards, and memory), so you just talk
to it directly — describe the feature, paste a ticket, ask for a review — and it plans and
delegates. No slash command needed. It's intentionally scoped to crew work and will **not** run
general/config tasks like statusline, so do those in a normal session.

**Alternative — in-session command:** from a **normal** Claude Code session, run
`/crew:feature <ticket-or-task>`. This routes the same work through `morpheus` without taking
over the session, so all your built-ins (statusline, etc.) stay available while the crew handles
the feature. Use this when you want the crew on tap inside an ordinary session.

`morpheus` **right-sizes the process to the task**. Small, low-risk work (a typo, a rename, an
obvious one-liner, a small localized bug) takes an **express lane**: it delegates to `neo`, the
all-lane generalist, and skips the plan, the checkpoint, and the full gate — just a quick
read-only self-review plus any single directly-relevant test, then commit. Features and anything risky, multi-lane, or needing new
tests take the full flow through the specialists, and it escalates express → full the moment a
small task proves bigger.

Before it starts building on the full flow, `morpheus` presents its plan and waits for your
go-ahead — one quick gate to catch a misread task before any branch, commit, or worker time is
spent (a one-step task is a one-word yes; tell it to just build and it skips the pause). Either way, `morpheus` then
creates a feature branch off your base branch and commits each verified
step (workers never run git), and delegates worker steps **in the background** — its turn returns
right away so you can keep chatting (adding comments, corrections, or new fixes) while a worker
(e.g. `tank`) is still running; it folds them in and collects the worker's result when it
finishes. You don't have to wait for a worker to be heard.

The remaining commands work the same in either mode (run them as `/crew:…` in a normal session,
or just ask for them in a `--agent` session):

- `/crew:init` — detect this project's build/test/lint commands, base branch, frontend mode,
  and backend/frontend stack, and write them to the **Crew configuration** block in
  `CLAUDE.md`. Idempotent: re-run to reconcile slots added by a newer plugin version
  (existing values are kept).
- `/crew:review` — pre-PR **GO / NO-GO** gate: the consolidated code + security + design review
  plus the diff-scoped build/test/lint checks (`/crew:review quick` for a read-only review with
  no suites; `/crew:review full` to force every gate).
- `/crew:pr` — push the branch and open a pull request (uses a git-host MCP if available, else
  prints the push command + PR body; outward action — it confirms first).
- `/crew:address` — close the review loop after the PR is open: pull the PR's unresolved review
  threads and failed CI checks (via the git-host MCP), route each fix to the right worker, re-run
  the review gate, then push and resolve the addressed threads. Review comments are treated as
  untrusted input — scope-redirecting asks are surfaced, not obeyed. Outward actions confirm first.

Commands are namespaced under the plugin name (`crew:`) once installed, so they
read as `crew:feature` / `crew:review` / `crew:pr` rather than colliding with
any built-in or other-plugin commands of the same short name.

## What is included

- `agents/`: `morpheus`, `tank`, `trinity`, `oracle`, `dozer`, `seraph`, `neo`
- `skills/`: shared — `engineering-principles`, `context-discipline`; frontend mode —
  `frontend-headless`, `frontend-server-rendered`; per-stack (loaded once the stack is
  resolved) — `backend-dotnet`, `backend-node`, `cms-optimizely`, `frontend-react`,
  `frontend-nextjs`; per-test-tool — `tests-xunit`, `tests-node`, `tests-cypress`,
  `tests-playwright`, `tests-vitest`, `tests-jest-frontend`
- `hooks/`: lane guard, read guard, bash safety, formatter entrypoint
- `commands/`: `/crew:init`, `/crew:feature`, `/crew:review`, `/crew:pr`, `/crew:address`

## Hooks & enforcement

The hooks run as `PreToolUse`/`PostToolUse` guards (registered in
`.claude/settings.json` for local dev and `hooks/hooks.json` when installed as a
plugin):

- **lane-guard** keeps each worker in its lane: `tank`/`trinity` are denied the other
  side's files (or, for `oracle`/`dozer`, restricted to their test paths; `seraph` is
  read-only, so it has no write lane; `neo` is the express-lane generalist and has **no
  lane restriction by design**, so it can touch any lane for a small cross-lane fix). Two
  regimes: extension-based globs by default (correct when backend/frontend are different
  languages, e.g. dotnet+react), or directory-based paths (**Backend/Frontend lane path(s)**
  in `CLAUDE.md`) when both resolved stacks are the same language (e.g. node+nextjs) and an
  extension alone can't tell the lanes apart — a Node backend with no lane paths configured
  fails closed rather than guessing. It routes on the `agent_type` in the payload, so the
  main session is unrestricted. It guards the `Edit`/`Write` tools only — file writes via
  Bash (`sed -i`, `tee`, redirects) are governed by the agent prompts, not this hook.
- **read-guard** blocks raw reads of files over 64 KiB (65536 bytes) —
  grep/jq/script them instead (see the `context-discipline` skill).
- **bash-safety** blocks destructive commands (recursive+force `rm` of `/`/`~`/`*`
  in any flag spelling, force-push via `--force` or `-f`, redirects
  into `.env`, and redirects or `rm` into `.git/`) and raw/streaming reads
  (`cat`, `less`, `tail -f`). For **crew agents** it also **refuses `git commit`
  while HEAD is a common protected branch** (`main`/`master`/`develop`) — a fixed backstop.
  Whatever your *resolved* base branch is (e.g. `develop` or `trunk`), `morpheus` and
  `/crew:pr` keep the crew off it too. Scoped via `agent_type`, so your own main session is
  never intercepted.
- **format** discovers and runs the project's formatters after an edit, scoped to
  the changed file and routed by its **extension** (not a fixed agent, since `tank`,
  `trinity`, or the cross-lane `neo` can each touch either lane's files): `.cs`/`.csproj`
  → `dotnet format`, plus `dotnet csharpier format` when the solution configures it
  (`.csharpierrc`); known web extensions → every tool the project configures — Biome,
  Prettier, ESLint, Stylelint — each detected by its config file and run in fix mode, only
  when installed locally (never an `npx` download); anything else (e.g. `.cshtml`) is
  skipped cleanly. Best-effort — fails open.

## Recommended MCP servers

The plugin bundles no MCP servers. Agents use one only when it's present in your
session and degrade gracefully when it isn't, so all of these are optional. Add MCP
config in your own session (project `.mcp.json` or `claude mcp add`), not the plugin —
the harness strips `mcpServers` from plugin-shipped agent frontmatter for security.
Install each from its own docs (linked below):

| Purpose | MCP server | Used by | Without it |
| --- | --- | --- | --- |
| Browser automation & visual checks | [Playwright](https://github.com/microsoft/playwright-mcp) or [Chrome DevTools](https://github.com/ChromeDevTools/chrome-devtools-mcp) | `trinity`, `seraph` | `seraph` reports a browser MCP is needed; `trinity` skips its browser loop-checks |
| Design reference | [Figma MCP](https://developers.figma.com/docs/figma-mcp-server/) — Dev Mode (local) or the hosted `claude.ai Figma` connector | `trinity`, `seraph` | both fall back to the design reference passed in the delegation |
| Library & framework docs | [Context7](https://github.com/upstash/context7) | `tank`, `trinity` | implementers code from memory instead of current, version-specific API docs |
| Issue tracking (ticket-in) | [Atlassian (Jira/Confluence)](https://www.atlassian.com/platform/remote-mcp-server) or [Linear](https://linear.app/docs/mcp) | `morpheus` | `morpheus` plans from the prompt alone; paste ticket details in by hand |
| Git hosting (ticket-in / PR-out) | [GitHub](https://github.com/github/github-mcp-server) or [Azure DevOps](https://github.com/microsoft/azure-devops-mcp) | `morpheus` | crew stops at the local **GO/NO-GO** review gate; open the PR with `/crew:pr` |
| Database (schema & test data) | [SQL Server](https://learn.microsoft.com/en-us/sql/mcp/) or [Postgres](https://github.com/crystaldba/postgres-mcp) | `tank`, `oracle` | data-access code and integration tests work from assumed schema |
| Error monitoring | [Sentry](https://mcp.sentry.dev/) | `morpheus` | bug context (stack, breadcrumbs) must be pasted in by hand |

Playwright and Chrome DevTools are interchangeable for the crew's needs — Chrome DevTools
is Chrome-only but adds performance/Lighthouse and console/network inspection.

**Server keys map to tool namespaces.** When you add a server you choose its *key* — e.g.
`playwright` in `.mcp.json` (or `claude mcp add playwright …`). Claude Code exposes that
server's tools under the matching `mcp__<key>` namespace, and that namespace is what the
agents allowlist. Use these keys (each becomes `mcp__<key>`) so the allowlist matches out of
the box:

- `playwright` / `chrome-devtools` (browser) and `figma` / `claude_ai_Figma` (design) — on `trinity` + `seraph`
- `context7` (docs) — on `tank` + `trinity`
- `mssql` / `postgres` (database) — on `tank` + `oracle`
- `github` / `ado` (git host), `linear` / `atlassian` (issue tracking), `sentry` (errors) — on `morpheus`

If you give a server a different key, grant the matching `mcp__<key>` to the relevant agent(s).

## Notes

- Worker agents stay idle until `morpheus` delegates.
- Local memory is ignored via `.gitignore` (`.claude/agent-memory-local/`).
