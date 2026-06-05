# Zion Link

A Claude Code plugin pack with orchestrated agents, commands, hooks, and skills for feature delivery.

## Install

Add this marketplace repository first:

```bash
claude plugin marketplace add johantor/zion-link
```

Then install from the marketplace (`<plugin-name>@<marketplace-name>`). Use the marketplace name returned by `claude plugin marketplace add` (or confirm with `claude plugin marketplace list`) after `@`:

```bash
claude plugin install crew@zion-link
```

Here, `crew` is the plugin name from `.claude-plugin/plugin.json`, and `zion-link` is the marketplace name.

Or browse in Claude Code under `/plugin > Discover` after adding the marketplace.

## Usage

1. Start orchestrator: `claude --agent morpheus`
2. Run `/zion-feature <ticket-or-task>` to plan and execute feature work.
3. Run `/zion-review` for consolidated code + security + design review.
4. Run `/zion-ship` for pre-PR go/no-go checks.

## What is included

- `agents/`: `morpheus`, `tank`, `trinity`, `oracle`, `dozer`, `seraph`
- `skills/`: `engineering-principles`, `context-discipline`, `frontend-headless`, `frontend-server-rendered`
- `hooks/`: lane guard, read guard, bash safety, formatter entrypoint
- `commands/`: `/zion-feature`, `/zion-review`, `/zion-ship`
- `.github/copilot-instructions.md`: guided review instructions for GitHub Copilot

## Hooks & enforcement

The hooks run as `PreToolUse`/`PostToolUse` guards (registered in
`.claude/settings.json` for local dev and `.claude/hooks/hooks.json` when
installed as a plugin):

- **lane-guard** keeps each worker in its lane: `tank`/`trinity` are denied the
  other stack's files, and `oracle`/`dozer`/`seraph` may only write their test
  or memory paths. It routes on the `agent_type` in the payload, so the main
  session is unrestricted. Fails closed.
- **read-guard** blocks raw reads of files over 64 KB — grep/jq/script them
  instead (see the `context-discipline` skill).
- **bash-safety** blocks destructive commands (`rm -rf /`, force-push, writes
  into `.git/` or `.env`) and raw/streaming reads (`cat`, `less`, `tail -f`).
- **format** runs the matching formatter after an edit (`dotnet format` for
  `tank`, npm lint/format for `trinity`). Best-effort — fails open.

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

> Note: `seraph` and `trinity` already allowlist the major Playwright tools
> (`mcp__playwright__browser_*`), so adding the server above named `playwright`
> is all that's needed. If you run a different browser MCP — or name the server
> something else — grant its `mcp__<server>__*` tool names in those agents.

### Git hosting (optional, for ticket-in / PR-out)

The crew is host-agnostic and stops at the local **GO/NO-GO** ship gate — it does
not open PRs or read tickets on its own. If you want the orchestrator to fetch a
work item or open the PR with the ship summary, add the MCP for your host. These
are **not wired into the commands yet** — they just make the host tools available
when you ask for them.

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
