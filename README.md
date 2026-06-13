# Zion

**Ship and maintain software with a crew, not a single assistant.** Zion is a
Claude Code marketplace — a curated suite of plugins that turn one prompt into
an orchestrated team, with the guardrails, reviews, and remediation tools to
keep what you ship healthy.

## The suite

| Plugin | What it does | Start with |
|---|---|---|
| **[crew](plugins/crew/README.md)** | Orchestrated, multi-agent feature delivery — a captain that plans and delegates to backend, frontend, tests, and visual-review specialists. | `/crew:feature <task>` |
| **[keymaker](plugins/keymaker/README.md)** *(beta)* | Pointer-driven tech debt remediation and dependency upgrades — fix one suppression, rule, or package at a time, with a blast-radius gate before anything moves. | `/keymaker:open <pointer>` |
| **[engineering-principles](plugins/engineering-principles/README.md)** | The review rubric used across the suite, shipped standalone for teams who just want the standards. | Skill-only — no commands |

Pick one, mix them, or install the lot. They share conventions (the same
`CLAUDE.md` config slots, the same review rubric) so they compose without
fighting each other.

## Why Zion

- **A team, not a soloist.** `crew` plans the work and delegates to specialists
  instead of one assistant juggling everything; `keymaker` runs the same playbook
  for debt and upgrades.
- **It keeps moving while you talk.** Workers run in the background, so you can
  add corrections or new asks mid-flight without waiting for a turn to finish.
- **Guardrails, not vibes.** Lane guards pin each worker to its own files,
  safety hooks block destructive commands and commits to protected branches,
  and formatters run after every edit.
- **Review and ship built in.** A consolidated code + security + design review
  and a pre-PR **GO / NO-GO** gate run before anything leaves your machine —
  driven by the same `engineering-principles` rubric the standalone plugin ships.
- **Your git, your rules.** Plugins branch and commit each verified step, stop
  at the review gate, and open the PR only when you say so.

## Get started

Add the marketplace once, then install the plugins you want:

```bash
claude plugin marketplace add johantor/zion
claude plugin install crew@zion
claude plugin install keymaker@zion
claude plugin install engineering-principles@zion   # rubric only; optional if you have crew
```

…or do it from the UI, via `/plugin > Discover` in Claude Code.

Then drive the suite from your normal Claude Code session:

- **Build a feature** — `/crew:feature <task>` plans, delegates, builds, and stops
  at the review gate; `/crew:review` runs the GO / NO-GO; `/crew:pr` opens the PR.
- **Pay down debt or bump a package** — `/keymaker:open <pointer>` fixes one
  identified item end-to-end; `/keymaker:audit <scope>` scouts an area and hands
  back ready-to-paste pointers.
- **Talk to the captain directly (optional)** — `claude --agent crew:morpheus`
  launches a dedicated orchestration session scoped to crew work.

Each plugin's README has the full surface area — agents, hooks, MCP wiring, and
the guardrails behind every gate.

## Plugins

### crew — orchestrated, multi-agent feature delivery

- `/crew:feature <task>` — plan and build a feature
- `/crew:review` — pre-PR **GO / NO-GO** gate: code + security + design review, plus build/test/lint
- `/crew:pr` — push the branch and open the pull request

Agents, hooks, background delegation, and optional MCP setup (Playwright, Figma,
GitHub/ADO) are documented in **[plugins/crew/README.md](plugins/crew/README.md)**.

### keymaker — pointer-driven tech debt and dependency upgrades *(beta)*

- `/keymaker:open <pointer>` — fix one identified item: a suppression at a line,
  a whole rule (e.g. `CS8602`, `eslint no-explicit-any`), or a package bump
  (`Newtonsoft.Json 13.x`). Classify → enumerate blast radius → gate → fix in
  batches → verify → commit per batch → delete the suppression so the analyzer
  becomes the regression test.
- `/keymaker:audit <scope>` — read-only scout of a path, lane, rule family, or
  the current `diff`; returns a ranked, capped report where every finding is a
  ready-to-paste `/keymaker:open` invocation.

Stack-aware (.NET / C# and TypeScript / JavaScript today, additive for more) and
tier-aware: single-package bumps are handled in-plugin; platform-scale migrations
get a `morpheus`-compatible handoff outline instead of a sweeping edit. Full
details in **[plugins/keymaker/README.md](plugins/keymaker/README.md)**.

### engineering-principles — the review rubric, standalone

For teams who want the same review rubric the rest of the suite uses, without
installing `crew`. Skill-only — no commands, no agents, no hooks.

```bash
claude plugin marketplace add johantor/zion
claude plugin install engineering-principles@zion
```

Details in **[plugins/engineering-principles/README.md](plugins/engineering-principles/README.md)**.

## Staying up to date

```bash
claude plugin marketplace update zion
claude plugin update crew@zion
claude plugin update keymaker@zion
claude plugin update engineering-principles@zion
```

---

Contributing a plugin or hacking on the crew? See **[AGENTS.md](AGENTS.md)**.

---

<details>
<summary>Trivia — what's with the names?</summary>

Everything here is named from *The Matrix*. **Zion** is humanity's last city — the home
that houses the resistance, and a fitting name for a marketplace of crews. The agents are
mapped loosely to what they do:

- **morpheus** — the captain: plans and leads, writes no code himself (crew orchestrator).
- **tank** & **dozer** — the operators: **tank** runs the backend, **dozer** runs the e2e tests.
- **trinity** — the hacker on point: the frontend.
- **oracle** — sees what will and won't hold up: the backend tests.
- **seraph** — the guardian who knows you by testing you ("you do not truly know someone until you fight them"): visual design conformance.
- **keymaker** — "I make the keys": opens locked doors one at a time, with precision (tech debt and upgrades orchestrator).
- **twin** — the keymaker's mechanical fixer/runner; works in pairs, in parallel.

</details>
