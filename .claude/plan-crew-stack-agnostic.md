feature: crew-stack-agnostic (issue #46 — make crew stack-agnostic: role-only agents, per-stack skills, detection-driven lanes)
base-branch: main
feature-branch: feat/crew-stack-agnostic

## Scope

Decouple crew's *roles* (backend implementer, frontend implementer, backend test author)
from its *stacks* (currently hard-coded to C#/.NET/Optimizely and React/Redux), following
the architecture keymaker already established in PR #45: roles are agents, stacks are
skills, detection maps files → stack, lanes are file areas — never languages. Concrete
second-stack driver named in the issue: Node backend + Next.js frontend (Optimizely SaaS /
Graph), which also breaks today's extension-based lane split since both lanes can be
TypeScript.

`dozer` (e2e) and `seraph` (visual conformance) are already stack-neutral — confirmed,
no step needed. keymaker is explicitly out of scope (already agnostic).

## Assumptions (flagging the issue's open questions — correct me if these are wrong)

1. **Monorepo lane paths are free-form, not a fixed `apps/*` convention.** New `CLAUDE.md`
   slots (`Backend lane path(s)` / `Frontend lane path(s)`) accept one or more path
   prefixes/globs the user provides — not an assumed `apps/api`/`apps/web` layout.
2. **Next.js route handlers / RSC data-logic are tank's lane by concern**, mirroring the
   existing Razor split (tank = server logic, trinity = markup/JSX) — written as an explicit
   rule in both agents' Next.js-stack skill, not inferred from file globs (globs can't see
   inside a file, same reasoning as the existing Razor comment in `lane-guard.sh`).
3. **Mixed-language backends (e.g. .NET service + Node BFF) are out of scope for v3** — no
   concrete driver for it yet (YAGNI); one backend stack resolved per project, as today.
4. **`dozer` and `seraph` get no changes** (confirmed stack-neutral already).

## Steps

### wp1 — Extract stack knowledge into per-stack skills
id: wp1
status: done
evidence: 1ad66d9
depends-on: independent
worker: self (no installed crew/tank subagents in this session — see note below)
acceptance: |
  - New skills exist, all under `plugins/crew/skills/<name>/SKILL.md`: `backend-dotnet`,
    `backend-node`, `frontend-react`, `frontend-nextjs`, `tests-xunit`, `tests-node`, plus
    `cms-optimizely` (added during implementation — see note below).
  - `backend-dotnet` / `frontend-react` / `tests-xunit` carry today's tank/trinity/oracle
    content verbatim (relocated, not rewritten) so existing .NET+React behavior is unchanged.
  - **Added during implementation:** `backend-dotnet` further splits into generic
    ASP.NET/.NET conventions (MVC controllers, Razor ownership, `dotnet build`) and a
    separate `cms-optimizely` skill (content types, blocks, `IContentRepository`, scheduled
    jobs, init modules) that composes on top of it. Optimizely is self-detected by tank via
    an `EPiServer.CMS`/`Optimizely.CMS` package reference — no new morpheus-resolved config
    slot needed, unlike backend/frontend stack (which can't be cheaply auto-detected with
    the same confidence). This wasn't in the original issue's WP1 list but follows the same
    reasoning one level further: not every .NET backend is Optimizely, the same way not
    every backend is .NET.
  - `backend-node`, `frontend-nextjs` are new, scoped per the issue's WP1 notes (Node:
    NestJS/Express/Fastify + Graph client + npm/pnpm workspaces, thin-BFF caveat; Next.js:
    App Router, RSC server/client split, Graph data fetching, route-handler vs BFF boundary).
  - `tests-node` is new and **framework-detected, not hard-coded** — mirrors
    `debt-taxonomy-typescript`'s package-manager table (npm/yarn/pnpm rows keyed by
    lockfile): a `vitest.config.*` marker → Vitest conventions, a `jest.config.*` marker →
    Jest conventions, same skill, one detection row each. Avoids picking one framework
    arbitrarily where the issue itself left it open.
  - `tank.md`/`trinity.md`/`oracle.md` become role-only: scope, lane rules, git/build-gate
    discipline, `engineering-principles`/`context-discipline` — no stack-specific nouns in
    the body. **Implementation note:** stack skills are loaded *dynamically* via the Skill
    tool once morpheus resolves the stack (not statically declared in frontmatter) — this
    mirrors trinity's existing `frontend-headless`/`frontend-server-rendered` mode-skill
    pattern rather than inventing a new mechanism. Frontmatter `skills:` keeps only the
    always-relevant shared skills (`engineering-principles`, `context-discipline`).
  - `bash plugins/crew/scripts/validate-plugin.sh` passes (skills-resolve check covers the
    new entries).

### wp2 — Stack resolution in morpheus
id: wp2
status: done
evidence: 33ec303
depends-on: wp1
worker: self
acceptance: |
  - `morpheus.md` gains a stack-resolution section mirroring the existing frontend-mode
    ladder: marker-file detection (`*.csproj`/`*.sln`→dotnet, `next.config.*`→nextjs,
    `package.json` + server-framework deps/workspace layout→node) → confirm with user →
    save to local memory; `CLAUDE.md` pin takes precedence when set.
  - New `CLAUDE.md` crew-config slots: **Backend stack**, **Frontend stack**.
  - `plugins/crew/commands/init.md` updated to match: added to §1's canonical slot list, and
    §2 gains detection rows (`*.csproj`/`*.sln` → dotnet backend; `next.config.*` → nextjs
    frontend; `package.json` with a server-framework dep and no SPA bundle config → node
    backend; existing React/Vite SPA detection → react frontend) — same idempotent-reconcile
    behavior as every other slot, not just an ask-and-remember-only slot.
  - This repo's own root `CLAUDE.md` **Crew configuration** section (the self-documented
    example block) gets the two new slots added alongside the existing ones.
  - Every delegation in morpheus's standard flow explicitly names the resolved stack (so
    the worker loads the right stack skill) — morpheus never delegates without one resolved.
  - Next.js is explicitly headless in crew's *mode* vocabulary even though it server-renders
    — mode and stack stay orthogonal (documented, not just implied).

### wp4 — format.sh backend/stack routing
id: wp4
status: done
evidence: 0a19a8e
depends-on: independent
worker: self
acceptance: |
  - `format.sh` selects its formatter set by the **edited file's extension/config**, not by
    a fixed `agent_type→lane` table — so a Node-backend file edited by `tank` still gets the
    existing config-detected web tooling (Biome/Prettier/ESLint), and a `.cs`/`.csproj` file
    still gets dotnet/CSharpier regardless of which agent produced it.
  - Existing dotnet-lane and web-lane behavior is unchanged for today's .NET+React shape
    (regression check, not just a read of the diff).

### wp5 — Generalize frontend-server-rendered
id: wp5
status: done
evidence: d05af77
depends-on: wp1 (soft — sequencing choice for a coherent diff, not a hard requirement;
  could run parallel to wp1 if desired)
worker: self
acceptance: |
  - `frontend-server-rendered` skill is reframed from Razor-specific to "server templates /
    server components" with the existing Razor content preserved under its own subsection,
    plus a minimal Blade subsection and an RSC (Next.js) subsection.
  - The headless/server-rendered **mode** mechanism itself (the `CLAUDE.md` Frontend mode
    slot, morpheus's resolution ladder) is untouched — this WP only generalizes the skill
    content the mode loads.

### wp3 — Lane boundaries that survive same-language stacks
id: wp3
status: done
evidence: 1cbc45b (plus f0d1e4f — Skill-tool access fix found during review)
depends-on: wp2
worker: self
acceptance: |
  - `lane-guard.sh` supports two lane regimes: today's extension-based globs (used when the
    resolved backend/frontend stacks imply disjoint languages, e.g. dotnet+react) and a new
    directory-based mode (used when both resolved stacks are the same language, e.g.
    node+nextjs) driven by the new `Backend lane path(s)`/`Frontend lane path(s)` `CLAUDE.md`
    slots — read directly from `CLAUDE.md` by the hook, no generated intermediate file.
  - Fails **closed**: a crew agent needing a lane decision that can't be resolved (unset
    stack, or same-language stacks with no lane-path config) is blocked with a message
    pointing at the missing config slot — never guesses.
  - The Next.js RSC/route-handler concern-split rule (assumption 2 above) is written into
    `tank`'s and `trinity`'s `frontend-nextjs`/Node-stack skill guidance.
  - Existing dotnet+react lane behavior is unchanged (regression check).
  - `plugins/crew/commands/init.md` updated: §1 gains **Backend lane path(s)** / **Frontend
    lane path(s)** (optional; only meaningful for same-language stack pairs), §2 documents
    that these are user-supplied (not auto-detected — the hook can't infer workspace
    boundaries reliably, per the issue's own reasoning). Root `CLAUDE.md` gets the two slots
    added alongside the stack slots from wp2.

### wp6 — Docs and release
id: wp6
status: done
depends-on: [wp1, wp2, wp3, wp4, wp5]
worker: self
acceptance: |
  - `AGENTS.md`, `plugins/crew/README.md`, root `README.md`, and `.github/copilot-instructions.md`
    updated to describe the stack-agnostic architecture (new skills, the four new `CLAUDE.md`
    slots and their `init.md` detection — already landed in wp2/wp3 — two lane regimes).
  - Root `CHANGELOG.md` (crew's changelog — unlike keymaker, crew has no separate
    `plugins/crew/CHANGELOG.md`) gets an entry; `plugins/crew/.claude-plugin/plugin.json`
    version bumped to **3.0.0** (major — lane semantics and agent descriptions change, per
    the issue's own call).
  - `bash plugins/crew/scripts/validate-plugin.sh` passes.

## Note on "worker"

No `crew:*` subagents are installed/runnable in this session (this repo only dogfoods the
crew plugin's *hooks* for its own dev-time use, per `AGENTS.md` — the commands/agents
aren't registered here). All steps are implemented directly rather than delegated;
`worker: self` records that departure from the normal crew flow.
