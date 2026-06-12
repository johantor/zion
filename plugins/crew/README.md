# crew

A Claude Code plugin: orchestrated agents, commands, hooks, and skills for
feature delivery. Part of the [Zion](../../README.md) marketplace.

## Install

```bash
claude plugin marketplace add johantor/zion
claude plugin install crew@zion
```

Or browse in Claude Code under `/plugin > Discover` after adding the marketplace.

## Usage

1. Run `/crew:feature <ticket-or-task>` to plan and execute feature work. `morpheus` creates
   a feature branch off your base branch and commits each verified step (workers never run git).
   Run it from a **normal** Claude Code session — that keeps all your built-ins (statusline, etc.)
   available while the crew handles the feature.
2. Run `/crew:review` for the pre-PR **GO / NO-GO** gate — the consolidated code + security +
   design review plus the diff-scoped build/test/lint checks (`/crew:review quick` for a
   read-only review with no suites; `/crew:review full` to force every gate).
3. Run `/crew:pr` to push the branch and open a pull request (uses a git-host MCP if
   available, else prints the push command + PR body; outward action — it confirms first).

> **Alternative — dedicated orchestration session:** start Claude Code *as* the orchestrator
> with `claude --agent crew:morpheus`. The whole session is `morpheus` (its own tools, lane
> guards, and memory), so you talk to it directly instead of going through `/crew:feature`. It's
> intentionally scoped to crew work and will **not** run general/config tasks like statusline —
> do those in a normal session.
>
> Either way, `morpheus` delegates worker steps **in the background**, so its turn returns right
> away and you can keep chatting — adding comments, corrections, or new fixes — while a worker
> (e.g. `tank`) is still running; it folds them in and collects the worker's result when it
> finishes. You don't have to wait for a worker to be heard.

Commands are namespaced under the plugin name (`crew:`) once installed, so they
read as `crew:feature` / `crew:review` / `crew:pr` rather than colliding with
any built-in or other-plugin commands of the same short name.

## What is included

- `agents/`: `morpheus`, `tank`, `trinity`, `oracle`, `dozer`, `seraph`
- `skills/`: `engineering-principles`, `context-discipline`, `frontend-headless`, `frontend-server-rendered`
- `hooks/`: lane guard, read guard, bash safety, formatter entrypoint
- `commands/`: `/crew:feature`, `/crew:review`, `/crew:pr`

## Hooks & enforcement

The hooks run as `PreToolUse`/`PostToolUse` guards (registered in
`.claude/settings.json` for local dev and `hooks/hooks.json` when installed as a
plugin):

- **lane-guard** keeps each worker in its lane: `tank`/`trinity` are denied the
  other stack's files, and `oracle`/`dozer` may only write their test paths
  (`seraph` is read-only, so it has no write lane). It routes on the `agent_type`
  in the payload, so the main session is unrestricted. Fails closed. It guards the
  `Edit`/`Write` tools only — file writes via Bash (`sed -i`, `tee`, redirects) are
  governed by the agent prompts, not this hook.
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
  the changed file. For `tank`: `dotnet format`, plus `dotnet csharpier format`
  when the solution configures it (`.csharpierrc`). For `trinity`: every tool the
  project configures — Biome, Prettier, ESLint, Stylelint — each detected by its
  config file and run in fix mode, only when installed locally (never an `npx`
  download). Best-effort — fails open.

## Recommended MCP servers

The plugin bundles no MCP servers — agents use one only when it's present in
your session, and degrade gracefully when it isn't. MCP config lives in your own
session (project `.mcp.json` or `claude mcp add`) rather than the plugin, because
the harness strips `mcpServers` from plugin-shipped agent frontmatter for
security. All of the below are optional.

### Browser automation (Playwright)

For full visual capability, add the
[Playwright MCP](https://github.com/microsoft/playwright-mcp) so `trinity`
(implementation loop-checks) and `seraph` (visual conformance) can drive a real
browser:

```json
{
  "mcpServers": {
    "playwright": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@playwright/mcp@latest"]
    }
  }
}
```

Without it, `seraph` reports that visual checks need a browser MCP and `trinity`
skips its browser loop-checks — nothing breaks.

> Note: `seraph` and `trinity` allowlist the whole `mcp__playwright` server, so
> adding the server above named `playwright` is all that's needed. If you run a
> different browser MCP — or name the server something else — grant its
> `mcp__<server>` to those agents.

### Design reference (Figma)

For design-driven work, add a Figma MCP so `seraph` (visual conformance) can pull
the canonical design spec instead of relying on a pasted export, and `trinity`
(frontend implementation) can build to exact measurements/colors/type. Pass the
Figma link or node id in the delegation.

`seraph` and `trinity` already allowlist the `mcp__figma` and `mcp__claude_ai_Figma`
servers (plus `ToolSearch`, which loads their deferred tool schemas), so adding one
of these is all that's needed:

- **Figma Dev Mode MCP** (official, local) — enable it in the Figma desktop app
  (Preferences → *Enable Dev Mode MCP Server*), then point Claude Code at it:

  ```bash
  claude mcp add-json figma '{"type":"http","url":"http://127.0.0.1:3845/mcp"}'
  ```

- **claude.ai Figma connector** — the hosted `claude.ai Figma` server (named
  `claude_ai_Figma`), authorized via OAuth on first use.

If you name your Figma server something other than `figma` / `claude_ai_Figma`, add
its `mcp__<server>` to `seraph` and `trinity`. Without any Figma MCP, both agents
fall back to the design reference provided in the delegation — nothing breaks.

### Git hosting (optional, for ticket-in / PR-out)

The crew is host-agnostic and stops at the local **GO/NO-GO** review gate — opening
the PR is the explicit `/crew:pr` step. If you want the orchestrator to fetch a
work item or open the PR with the review-gate summary, add the MCP for your host.

`morpheus` already allowlists the `mcp__ado` and `mcp__github` servers (plus
`ToolSearch`, which loads their deferred tool schemas, and `Bash` for `az` / `gh`),
so once you add one of the servers below (GitHub or ADO) it can drive PR work —
including from a `claude --agent crew:morpheus` session. If you name your host server something
other than `ado` / `github`, add its `mcp__<server>` to `morpheus`'s `tools`.

GitHub — official [github/github-mcp-server](https://github.com/github/github-mcp-server)
(remote, needs a GitHub PAT):

```bash
claude mcp add-json github '{"type":"http","url":"https://api.githubcopilot.com/mcp/","headers":{"Authorization":"Bearer YOUR_GITHUB_PAT"}}'
```

Azure DevOps — official [microsoft/azure-devops-mcp](https://github.com/microsoft/azure-devops-mcp)
(stdio, uses your `az login`; pass your org name):

```json
{
  "mcpServers": {
    "ado": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@azure-devops/mcp", "YOUR_ADO_ORG"]
    }
  }
}
```

## Notes

- Worker agents stay idle until `morpheus` delegates.
- Local memory is ignored via `.gitignore` (`.claude/agent-memory-local/`).
