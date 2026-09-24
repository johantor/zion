---
description: Detect the project's crew configuration and write it to .claude/crew.md, or with --local to an uncommitted file every worktree shares (idempotent — re-run to reconcile new settings, and to migrate a legacy CLAUDE.md block)
argument-hint: "[--local]"
---

Set up (or reconcile) the **crew configuration** the orchestrator reads. This command
detects the project's build/test/lint commands, base branch, frontend mode, and backend/
frontend stack, shows you what it found, and writes the agreed values to **`.claude/crew.md`**.
It is **idempotent**: the first run bootstraps the file; a re-run reconciles it, adding any
slots introduced by a newer plugin version **without overwriting values you've already set**;
and it **migrates** a legacy **Crew configuration** block out of `CLAUDE.md` when it finds one.

Two destinations, split by **audience** — not by tool:

- **`.claude/crew.md`** — every slot in §1. Committed, so a teammate who installs the plugin
  inherits them, and reviewable in a pull request. This is machine configuration for a
  dispatcher: it is read on demand, not auto-loaded into every session.
- **`CLAUDE.md`** — the `## Crew orchestration` prose (§3, which has a reader that sees only
  `CLAUDE.md`) plus the few repo conventions a careful reader would get **wrong** (§3's bar),
  in tool-neutral wording. Slot values never go here.

**Local mode** (`$ARGUMENTS` contains `--local`, or the user picks it in §4) changes nothing in
the repo: the slots go to `crew.md` in the shared git dir (`git rev-parse --git-common-dir`,
so every worktree of the clone reads it and git never commits it), and the §3 orchestration prose
goes to `~/.claude/CLAUDE.md` once, reading "in this repo" as "in any repo where crew runs".
Propose no convention lines; report them instead. A committed `.claude/crew.md` wins over the
local file, so when one exists, say so and stop.

Do the detection read-only first, then confirm with the user before writing anything.

## 1. Canonical configuration slots

The slots the crew reads, each with its `.claude/crew.md` key. This list is the source of truth
for what "complete" means — reconcile fills any that are missing, and CI keeps it in lockstep
with this repo's own `.claude/crew.md`. Every slot marked *pin-only* is optional: `unset` lets
`morpheus` resolve it per project.

- **Frontend mode** (`frontendMode`) — `headless` or `server-rendered`. Pin-only.
- **Backend stack** (`backendStack`) — `dotnet`, `node`, `python`, `go`, `rust`, `java`, or
  `shell`. Pin-only.
- **Frontend stack** (`frontendStack`) — `react`, `nextjs`, or `none`. Pin-only, except that
  `none` is a statement: the project has no client-facing surface (a library, a headless service,
  a script pack), so `morpheus` skips frontend mode, e2e and unit-tool resolution and never
  dispatches the frontend workers. **A TUI, or a CLI whose rendered output is designed, is a
  view** in `trinity`'s lane with no supported value yet — stop and surface unsupported rather
  than writing `none` or `unset`.
- **Frontend e2e tool** (`frontendE2eTool`) — `cypress` or `playwright`. Pin-only.
- **Frontend unit test tool** (`frontendUnitTestTool`) — `vitest`, `jest`, or `cypress`. Pin-only;
  also `unset` when the project has no frontend unit tests.
- **Backend lane path(s)** (`backendLanePaths`) — comma-separated path prefixes, e.g. `apps/api/`.
  Only when backend and frontend stacks are the same language (Node backend + Next.js): by
  extension `lane-guard.sh` cannot tell `tank`'s and `trinity`'s files apart and falls back to
  these. `unset` otherwise.
- **Frontend lane path(s)** (`frontendLanePaths`) — e.g. `apps/web/`; same caveat.
- **Backend test command** (`backendTestCommand`) — e.g. `dotnet test`.
- **Frontend test command** (`frontendTestCommand`) — the **e2e** suite only (e.g. `npx playwright
  test`); `oracle` derives unit/component runs from the Frontend unit test tool instead.
- **Backend build command** (`backendBuildCommand`) — e.g. `dotnet build`.
- **Frontend build command** (`frontendBuildCommand`) — e.g. `tsc --noEmit` / `vite build`.
- **Backend lint command** (`backendLintCommand`) — verify mode, e.g. `dotnet format
  --verify-no-changes`.
- **Frontend lint command** (`frontendLintCommand`) — the lint script in report/verify mode.
- **Base branch** (`baseBranch`) — the branch `morpheus` branches off (`main` / `develop` / trunk).
- **Branch naming** (`branchNaming`) — e.g. `feature/<ticket>-<slug>`.
- **Run/dev URL** (`runUrl`) — the local dev URL, if the project serves one.
- **Plan directory** (`planDirectory`) — where `morpheus` writes `plan-<feature>.md`; `unset` uses
  the `.claude/` fallback. Set it (e.g. `docs/plans/`) for a committed location.

Free-text notes for the crew are not a slot: they go in the file's **body**, below the
frontmatter — why a slot is set the way it is, a caveat on a command, which areas of the app are
headless when the mode is mixed. The body is prose, and reconcile preserves it verbatim.

The file's shape:

```markdown
---
backendStack: dotnet
frontendStack: react
frontendMode: server-rendered
frontendE2eTool: cypress
frontendUnitTestTool: unset
backendLanePaths: unset
frontendLanePaths: unset
backendTestCommand: dotnet test
frontendTestCommand: npx playwright test
backendBuildCommand: dotnet build
frontendBuildCommand: npm run build
backendLintCommand: dotnet format --verify-no-changes
frontendLintCommand: npm run format:check
baseBranch: develop
branchNaming: feature/<ticket>-<slug>
runUrl: https://localhost:5001/
planDirectory: unset
---

Notes the crew should carry: npm scripts run from `src/Site`, not the repo root.
```

## 2. Detect (read-only)

Inspect the repo and propose a value for each slot. Cite where each came from so the user can
trust or correct it; never invent a command you can't see configured.

| Slot | Detect from |
|---|---|
| Backend stack | `*.csproj`/`*.sln` → `dotnet`; `package.json` with a server framework (NestJS/Express/Fastify) and no SPA-only bundle config → `node`; `pyproject.toml` (or `requirements*.txt`/`setup.py`/`Pipfile`) → `python`; `go.mod` → `go`; `Cargo.toml` → `rust`; `pom.xml` or `build.gradle*` **with Java sources** (`src/main/java`, or a `java`/`java-library` plugin) → `java` — the build file alone also fits Kotlin, Scala and Android, none supported, so ask; `*.sh`/`*.bats` with no other backend marker → `shell` (the scripts are the deliverable, not a repo that merely has a build script). Two backends' markers → ask, don't break the tie. |
| Backend build, test, lint | Load the detected stack's `backend-<stack>` skill and propose what its **Crew config** section says; it names the static gate for a stack with no compile step and the runner prefix a command needs. |
| Frontend stack | `next.config.*` → `nextjs`; a React/Vite SPA build without it → `react`; no client-facing surface → propose `none` and say why. A TUI or designed CLI output → stop, unsupported. |
| Frontend build, test, lint | `package.json` `scripts`: `build`/`typecheck` → build, `test`/`e2e`/a Playwright config → test, `lint` → lint. Use the scripts that exist; don't assume an `npx` download. A script that only runs from a subdirectory says so in the value: `npm run build (from src/Site)`. |
| Frontend mode | React/Vite/Next SPA build → `headless`; Razor `.cshtml` views without an SPA bundle → `server-rendered`. Mixed or unclear → `unset` with the split described in the body notes. |
| Frontend e2e tool | `cypress.config.*` or a `cypress/` directory → `cypress`; `playwright.config.*` → `playwright`. |
| Frontend unit test tool | `vitest.config.*` → `vitest`; `jest.config.*` or a `jest` key with no vitest → `jest`; a `cypress.config.*` `component` key with neither → `cypress`. Absent → `unset`; `morpheus` will not assume one exists. |
| Lane paths | Never auto-detect. Only when backend and frontend stacks are the same language, and then ask for the paths. |
| Base branch | `git symbolic-ref refs/remotes/origin/HEAD`, else an existing `main`/`develop`. Ambiguous → ask; `origin/HEAD` is often unset or stale, and a wrong base is expensive. |
| Run/dev URL, branch naming | Dev scripts, `launchSettings.json`, existing branch names; else `unset`. |
| Plan directory | Only an obvious existing convention (`docs/plans/`, tracked `plan-*.md` outside `.claude/`); else `unset`. |

When detection comes up empty, pick the placeholder by slot type — never a value that makes the
config unusable:

- **Tooling slots** (test, build and lint commands; run/dev URL): `none` when the project
  genuinely has no such tooling. Gates that need it then skip with that note.
- **Project-identity slots** (base branch, branch naming, frontend mode, backend stack): `unset`,
  never `none` — a base branch always exists. `morpheus` resolves or asks.
- **Frontend stack is the exception.** `none` is a real answer: write it when confirmed, since
  `unset` would send `morpheus` asking a question a CLI or a script pack cannot answer.

Write both placeholders as plain YAML values — `unset` and `none`, never quoted, never
backticked — so reconcile recognizes them later. Write every key, so a slot a newer plugin
version added is visibly unadopted rather than merely missing. Don't guess to fill a blank.

## 3. What belongs in `CLAUDE.md`

Two things, and no slot values.

**First, the `## Crew orchestration` prose.** Ensure that section exists. It carries no slots and
nothing detects into it — it is fixed prose, added once and left alone on reconcile if the user has
edited it. Its audience is anything that reads `CLAUDE.md` to understand this repo, including auto
mode's permission classifier: the classifier reads the same `CLAUDE.md` Claude does, and without
this it has only a dispatch label to judge a worker delegation by. That reader is why this prose
stays in `CLAUDE.md` while the configuration moves out. Keep it descriptive — it states what the
crew *is*, and never instructs the classifier to permit anything.

```markdown
## Crew orchestration

Development in this repo is orchestrated: `morpheus` plans the work and delegates each step to a
worker subagent (`tank`, `trinity`, `oracle`, `dozer`, `seraph`, `neo`, `sentinel`, `keymaker`). Dispatching a
worker is ordinary in-repo development — the worker reads files in this working tree, an
implementer edits them (`seraph`, `sentinel` and `keymaker` carry no edit tool), and each returns
a summary. It is not remote execution, and it sends nothing outside the repository.

The crew's guard hooks bound what a worker can do: only `morpheus` touches git, no agent commits on
the base branch, each worker's edits are confined to its own lane — through `Edit`/`Write`, and
file-mutating Bash is refused so a write cannot route around the lane — and destructive shell
commands are refused. Nothing is pushed and no pull request is opened on its own — `/crew:pr` is the only
path out of the machine, and the user invokes it.
```

Fix the worker list and the last line if this project's crew differs (a repo that never uses
`/crew:pr`, say). Don't add project-specific claims you haven't verified.

**Second, repo conventions — but only the ones a glance gets wrong.** Detection is cheap and
`package.json` maintains itself, so the bar for a `CLAUDE.md` line is not "is it true?" but:

> **Would a quick glance give the right answer, or a plausible wrong one?**

Propose a line only when the glance misleads. Typical earners:

- A script whose name hides what it does — a `format` script that **writes** fixes, so an agent
  asked to *check* formatting runs it and dirties the working tree. That needs saying;
  `npm run build` does not.
- A build that must be invoked a particular way to be safe (output redirected away from a running
  dev server), or whose success output can lie (a "0 warnings" build that compiled nothing).
- A unit convention that silently corrupts translated values — `html` at 62.5%, so `1rem = 10px`.
- Wiring no linter or type-check can see, so a green run doesn't mean it is connected.
- Generated files that must not be committed, where the generator isn't obvious.

Never propose: the stack, a bare build/test command, the dev URL, tool names — every one is a
glance away, and a written copy rots while the config file doesn't. Write what survives as ordinary
repository conventions in the repo's existing voice, with no crew vocabulary: their audience is
anyone working in the repo, including teammates who have never installed this plugin. If
`CLAUDE.md` already covers a point, leave it alone.

## 4. Confirm with the user

Show two tables — the §1 slots (slot · proposed value · source) and any proposed `CLAUDE.md` lines
(line · why a glance misleads) — and let the user confirm or edit each before anything is written.
Say plainly where the slots go: `.claude/crew.md` is committed and shared with the repo; in local
mode, the file in the shared git dir stays on this machine and is never committed.

If the user would rather keep crew configuration out of the repo, use local mode. It writes to
protected paths (`.git/`, `~/.claude/`), so expect a permission prompt for each write.

## 5. Write, reconcile, migrate

- **Nothing yet** → create `.claude/crew.md` with every slot from §1 and the confirmed values,
  and apply the confirmed `CLAUDE.md` additions from §3.
- **`.claude/crew.md` exists (reconcile)** → for each slot in §1: add its key if missing; fill it
  if present but still a placeholder (`unset` / `none`) and a value was detected and confirmed.
  **Never overwrite a key the user has set to a real value** — show those as "kept" rather than
  changing them. Preserve the body notes verbatim.
- **Legacy `CLAUDE.md` block (migrate)** → when `CLAUDE.md` carries a **Crew configuration**
  block (earlier versions wrote the slots there as `- **Slot:** value` bullets):
  1. Read every slot value out of it, including any it holds that §1 has no key for — carry those
     into the new file's body notes rather than dropping them. Treat italic *unset* as `unset` and
     plain none as `none`.
  2. Write `.claude/crew.md` from those values; a value the user had set wins over a freshly
     detected one.
  3. Judge whatever else that section carried (a *Notable conventions* entry, usually) against
     §3's bar: keep what earns a line — reworded tool-neutral — and name what you are dropping as
     deducible.
  4. Remove the **Crew configuration** section from `CLAUDE.md`. Leave `## Crew orchestration`
     in place — it belongs there (§3). In local mode, skip steps 3–4 and leave `CLAUDE.md`
     untouched: the local file wins over the legacy block.

In local mode, every bullet above targets the local file in place of `.claude/crew.md`, and the
§3 prose goes to `~/.claude/CLAUDE.md`; nothing is written to the project `CLAUDE.md`.

Before writing, show the exact set of additions and removals — a short diff of slots, plus the
`CLAUDE.md` lines kept, reworded, and dropped — and apply only after the user confirms. Migration
is a one-way move: get that confirmation before touching `CLAUDE.md`. Afterwards, report what was
added, filled, kept, migrated, and dropped, and note that re-running reconciles again after future
plugin updates.

## 6. MCP namespace check (report-only)

Not a configuration slot — nothing is written for this. MCP servers are configured in the user's
own session, and the crew agents reach them through an allowlisted namespace, so a mismatch
between the two is invisible at runtime: an agent sees a server it can't call exactly as it sees
one that was never installed.

Report, don't guess. From the MCP tools visible in this session, list each server's namespace and
say which crew agent grants it (the plugin README's *Optional MCP servers* table is the mapping);
tell the user to run `/mcp` for the authoritative list, since a session sees only what it loaded.
Flag these two cases:

- **A server keyed differently from the README's keys** — its tools are `mcp__<key>__…`, so the
  fix is granting `mcp__<key>` to the relevant agent(s).
- **A plugin-installed server** — its tools are `mcp__plugin_<plugin>_<server>__…`. The agents
  already grant `mcp__plugin_<key>_<key>` for a plugin that ships one server under its own name;
  any other combination needs that exact prefix added to the agent's `tools:`.

If nothing is visible and the user expected a server, say so plainly rather than reporting the
configuration as complete.
