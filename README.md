# Zion Link

Claude Code plugins for feature delivery — a small **crew** of orchestrated agents
that plan, build, test, and review your work, with guardrails that keep them on task.

## Get started

Add the marketplace, then install a plugin:

```bash
claude plugin marketplace add johantor/zion-link
claude plugin install crew@zion-link
```

Or browse the plugins under `/plugin > Discover` in Claude Code.

## Plugins

### crew

> `claude plugin install crew@zion-link`

Orchestrated, multi-agent feature delivery. An orchestrator (`morpheus`) plans the
work and delegates to specialist workers — backend, frontend, tests, and visual
review — then runs a consolidated review and a pre-PR ship gate.

- `/crew:feature <task>` — plan and build a feature
- `/crew:review` — consolidated code + security + design review
- `/crew:ship` — pre-PR **GO / NO-GO** gate

Agents, hooks, and optional MCP setup are documented in
**[plugins/crew/README.md](plugins/crew/README.md)**.

## Staying up to date

```bash
claude plugin marketplace update zion-link
claude plugin update crew@zion-link
```

---

Contributing a plugin or hacking on the crew? See **[CLAUDE.md](CLAUDE.md)**.

---

<details>
<summary>Trivia — what's with the names?</summary>

Everything here is named from *The Matrix*. **Zion** is humanity's last city and a
**Link** is the crew's operator/tether — together, the marketplace. The agents are the
*Nebuchadnezzar*'s crew, mapped loosely to what they do:

- **morpheus** — the captain: plans and leads, writes no code himself (orchestrator).
- **tank** & **dozer** — the operators: **tank** runs the backend, **dozer** runs the e2e tests.
- **trinity** — the hacker on point: the frontend.
- **oracle** — sees what will and won't hold up: the backend tests.
- **seraph** — the guardian who knows you by testing you ("you do not truly know someone until you fight them"): visual design conformance.

</details>

