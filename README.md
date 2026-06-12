# Zion

**Ship features with a crew, not a single assistant.** Zion is a Claude Code
marketplace whose flagship plugin, **crew**, turns one prompt into an orchestrated
team: a captain that plans and delegates, specialists that build and test, and
guardrails that keep every agent in its lane.

## Why crew

- **One prompt, a whole team.** `morpheus` plans the work and delegates to specialists —
  backend, frontend, tests, and visual review — instead of one assistant juggling everything.
- **It keeps moving while you talk.** Workers run in the background, so you can add
  corrections or new asks mid-flight without waiting for a turn to finish.
- **Guardrails, not vibes.** Lane guards pin each worker to its own files, safety hooks block
  destructive commands and commits to protected branches, and formatters run after every edit.
- **Review and ship built in.** A consolidated code + security + design review and a pre-PR
  **GO / NO-GO** gate run before anything leaves your machine.
- **Your git, your rules.** The crew branches and commits each verified step, stops at the
  review gate, and opens the PR only when you say so.

## Get started

```bash
claude plugin marketplace add johantor/zion
claude plugin install crew@zion
```

Prefer the UI? Add and install from `/plugin > Discover` in Claude Code instead.

Then start a feature either way:

- **Normal session** — run `/crew:feature <task>`; keeps all your built-ins (statusline, etc.)
  available while the crew works.
- **Dedicated session** — launch `claude --agent crew:morpheus` to talk to the orchestrator
  directly, scoped to crew work. More in **[plugins/crew/README.md](plugins/crew/README.md)**.

## Plugins

### crew — orchestrated, multi-agent feature delivery

- `/crew:feature <task>` — plan and build a feature
- `/crew:review` — pre-PR **GO / NO-GO** gate: code + security + design review, plus build/test/lint
- `/crew:pr` — push the branch and open the pull request

Agents, hooks, background delegation, and optional MCP setup (Playwright, Figma, GitHub/ADO)
are documented in **[plugins/crew/README.md](plugins/crew/README.md)**.

## Staying up to date

```bash
claude plugin marketplace update zion
claude plugin update crew@zion
```

---

Contributing a plugin or hacking on the crew? See **[AGENTS.md](AGENTS.md)**.

---

<details>
<summary>Trivia — what's with the names?</summary>

Everything here is named from *The Matrix*. **Zion** is humanity's last city — the home
that houses the resistance, and a fitting name for a marketplace of crews. The agents are
the *Nebuchadnezzar*'s crew, mapped loosely to what they do:

- **morpheus** — the captain: plans and leads, writes no code himself (orchestrator).
- **tank** & **dozer** — the operators: **tank** runs the backend, **dozer** runs the e2e tests.
- **trinity** — the hacker on point: the frontend.
- **oracle** — sees what will and won't hold up: the backend tests.
- **seraph** — the guardian who knows you by testing you ("you do not truly know someone until you fight them"): visual design conformance.

</details>
