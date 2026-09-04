---
description: Detect the project's crew configuration and write it to .claude/crew.md (idempotent — re-run to reconcile new settings, and to migrate a legacy CLAUDE.md block)
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

Do the detection read-only first, then confirm with the user before writing anything.

## 1. Canonical configuration slots

These are the slots the crew reads, each with the `.claude/crew.md` key that carries it. This
list is the source of truth for what "complete" means — reconcile fills any of these that are
missing, and CI keeps it in lockstep with this repo's own `.claude/crew.md`:

- **Frontend mode** (`frontendMode`) — `headless` or `server-rendered`. Optional/pin-only; leave
  `unset` to let `morpheus` resolve it per project.
- **Backend stack** (`backendStack`) — `dotnet`, `node`, `python`, `go`, `rust`, `java`, or
  `shell`. Optional/pin-only; leave `unset` to let `morpheus` resolve it per project.
- **Frontend stack** (`frontendStack`) — `react` or `nextjs`. Optional/pin-only; leave `unset` to
  let `morpheus` resolve it per project.
- **Frontend e2e tool** (`frontendE2eTool`) — `cypress` or `playwright`. Optional/pin-only; leave
  `unset` to let `morpheus` resolve it per project.
- **Frontend unit test tool** (`frontendUnitTestTool`) — `vitest`, `jest`, or `cypress`.
  Optional/pin-only; leave `unset` to let `morpheus` resolve it per project (or if the project has
  no frontend unit tests).
- **Backend lane path(s)** (`backendLanePaths`) — one or more path prefixes (comma-separated), e.g.
  `apps/api/`. Only meaningful when backend and frontend stacks are the same language (e.g. Node
  backend + Next.js frontend) — `lane-guard.sh` can't tell `tank`'s and `trinity`'s files apart by
  extension in that case and falls back to these paths. Leave `unset` otherwise.
- **Frontend lane path(s)** (`frontendLanePaths`) — one or more path prefixes (comma-separated),
  e.g. `apps/web/`. Same same-language caveat as Backend lane path(s).
- **Backend test command** (`backendTestCommand`) — e.g. `dotnet test`.
- **Frontend test command** (`frontendTestCommand`) — the **e2e** suite only (e.g.
  `npx playwright test`). Unit/component runs are not driven by this slot: `oracle` derives them
  from the resolved **Frontend unit test tool** (a project `test`/`test:unit` script if present,
  else the tool directly — `vitest run`, `jest`, `cypress run --component`).
- **Backend build command** (`backendBuildCommand`) — e.g. `dotnet build`.
- **Frontend build command** (`frontendBuildCommand`) — e.g. `tsc --noEmit` / `vite build`.
- **Backend lint command** (`backendLintCommand`) — verify mode (e.g.
  `dotnet format --verify-no-changes`, plus `dotnet csharpier check` when a `.csharpierrc` is
  present).
- **Frontend lint command** (`frontendLintCommand`) — the project's lint script in report/verify
  mode (`eslint`, `biome check`, `stylelint`, …).
- **Base branch** (`baseBranch`) — the branch `morpheus` branches off (`main` / `develop` / trunk).
- **Branch naming** (`branchNaming`) — convention for feature branches (e.g.
  `feature/<ticket>-<slug>`).
- **Run/dev URL** (`runUrl`) — the local dev URL, if the project serves one.
- **Plan directory** (`planDirectory`) — where `morpheus` writes `plan-<feature>.md`. Optional;
  leave `unset` to use the `.claude/` fallback. Set it (e.g. `docs/plans/`) to keep plans in a
  repo-specific, committed location.

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

- **Backend (.NET):** a `*.sln`/`*.csproj` implies build `dotnet build`, test `dotnet test`,
  lint `dotnet format --verify-no-changes` (add `dotnet csharpier check` if a `.csharpierrc`
  exists).
- **Backend (Python):** there is no compile step, so the build slot is the project's static gate —
  a `[tool.mypy]`/`mypy.ini` implies `mypy .`, a `[tool.pyright]`/`pyrightconfig.json` implies
  `pyright`. Test `pytest` when the project has it (a `[tool.pytest.ini_options]` table, a
  `pytest.ini`, or pytest in the dependencies) — a `unittest`-only project need not have pytest
  installed, so propose `python -m unittest discover` there instead, and leave the slot `unset`
  when neither is present. Lint
  `ruff check .` / `flake8` plus `black --check .` where configured. Prefix every command with
  the project's runner when it has one (`poetry run`, `uv run`, `pdm run`) — a bare `pytest`
  resolves against whatever interpreter is active. If no type checker is configured, say so and
  leave the build slot `unset` rather than inventing one.
- **Backend (shell):** there is no build, so the build slot is the project's static gate —
  `shellcheck <globs>` (take the globs from CI, since the shell's `*` does not cross directory
  separators and a single pattern usually misses a subdirectory), optionally `bash -n`. Test the
  project's own runner (`bash tests/run.sh`, `bats tests/`); lint `shellcheck` plus `shfmt -d`
  where shfmt is configured.
- **Backend (Go):** build `go build ./...` (add `go vet ./...` when the repo runs it), test
  `go test ./...` (keep `-race` if a CI workflow uses it), lint `golangci-lint run` when a
  `.golangci.yml` exists, else `gofmt -l .`.
- **Backend (Rust):** build `cargo check --all-targets` or `cargo build` — read which the repo's
  CI runs rather than picking; add `cargo clippy --all-targets -- -D warnings` where clippy is
  configured. Test `cargo test` (`cargo nextest run` when `nextest.toml`/the tool is configured);
  lint `cargo fmt --check`.
- **Backend (JVM):** prefer the committed wrapper. Maven (`pom.xml`) implies build `./mvnw -B
  verify -DskipTests`, lint `./mvnw -B checkstyle:check` where the plugin is configured, and test
  `./mvnw -B verify` — **not** `./mvnw -B test`, which stops before the `integration-test`/`verify`
  phases where Failsafe runs, so every `*IT` class would be skipped by both gates. Gradle
  (`build.gradle*`) implies build `./gradlew build -x test`, lint `./gradlew check -x test`, and
  test `./gradlew test` plus any separate integration-test task the build script declares — Gradle
  has no Failsafe equivalent by default, so read the source sets rather than assuming one task
  covers both. Read the actual plugin/task set rather than assuming these exist.
- **Frontend (Node):** read `package.json` `scripts` — map `build`/`typecheck` → frontend
  build, `test`/`e2e`/a Playwright config → frontend test, `lint` → frontend lint. Use the
  scripts that exist; don't assume an `npx` download.
- **Monorepo / nested app:** when a script only runs from a subdirectory, say so in the slot
  value (e.g. `npm run build (from src/Site)`). The command alone is deducible from
  `package.json`; the working directory is the part that isn't.
- **Base branch:** the remote's default (`git symbolic-ref refs/remotes/origin/HEAD`), falling
  back to an existing `main`/`develop`. If ambiguous, ask — `origin/HEAD` is often unset or
  stale, and a wrong base branch is expensive.
- **Frontend mode:** infer from the stack — a React/Vite/Next SPA build → `headless`; Razor
  `.cshtml` views without an SPA bundle → `server-rendered`. If it's genuinely mixed or
  unclear, leave `unset` and note that `morpheus` will resolve it, or ask. A genuinely mixed repo
  stays `unset` with the split described in the body notes, so `morpheus` resolves per feature.
- **Backend stack:** a `*.csproj`/`*.sln` → `dotnet`; a `package.json` with a server-framework
  dependency (NestJS/Express/Fastify) and no SPA-only bundle config → `node`; a `pyproject.toml`
  (or `requirements*.txt`/`setup.py`) → `python`; a `go.mod` → `go`; a `Cargo.toml` → `rust`; a
  `pom.xml` or `build.gradle`/`build.gradle.kts` → `java`; `*.sh`/`*.bats` with no other
  backend marker → `shell` (a repo whose deliverable is the scripts themselves — not any repo
  that merely has a build script). If ambiguous or absent, leave `unset`
  for `morpheus` to resolve. A repo with markers for two backends is ambiguous, not a tie to
  break — ask which one the crew should treat as the backend.
- **Frontend stack:** a `next.config.*` → `nextjs`; a React/Vite SPA build with no
  `next.config.*` → `react`. If ambiguous or absent, leave `unset` for `morpheus` to resolve.
- **Frontend e2e tool:** a `cypress.config.*` (or a `cypress/` directory) → `cypress`; a
  `playwright.config.*` → `playwright`. If ambiguous or absent, leave `unset` for `morpheus` to
  resolve.
- **Frontend unit test tool:** a `vitest.config.*` → `vitest`; a `jest.config.*` (or a `jest`
  key in `package.json`) with no `vitest.config.*` → `jest`; a `cypress.config.*` with a
  `component` key and no `vitest.config.*` or `jest.config.*` → `cypress`. If absent, leave
  `unset` — the project may have no frontend unit tests, and `morpheus` will not assume one exists.
- **Backend lane path(s) / Frontend lane path(s):** never auto-detect — workspace boundaries
  (which directory is the backend app vs. the frontend app) aren't reliably inferable from
  marker files alone. Only propose these when the detected backend and frontend stacks are
  the same language (e.g. Node + Next.js) — ask the user for the paths rather than guessing;
  otherwise leave `unset`.
- **Run/dev URL, branch naming:** propose from dev scripts / `launchSettings.json` / existing
  branch names where visible; otherwise leave `unset`.
- **Plan directory:** only propose a value if the repo has an obvious plans convention (an
  existing `docs/plans/`, `plan-*.md` already tracked outside `.claude/`); otherwise leave
  `unset` so the `.claude/` fallback applies. Don't invent a directory.

When detection comes up empty, pick the placeholder by slot type — never write a value that
makes the config unusable:

- **Tooling slots** (backend/frontend test, build, and lint commands; run/dev URL): if the
  project genuinely has no such tooling, use `none`. Gates that need it then skip with that
  note, and nobody is asked again.
- **Project-identity slots** (base branch, branch naming, frontend mode, backend stack,
  frontend stack): never `none` — a base branch always exists, so `none` would be wrong. Leave
  these `unset` so `morpheus` resolves or asks (for base branch, prefer asking — see above).

Write both placeholders as plain YAML values — `unset` and `none`, never quoted, never
backticked — so reconcile recognizes them later. A key that is absent altogether reads as
`unset`; write every key anyway, so a slot a newer plugin version added is visibly unadopted
rather than merely missing. Don't guess to fill a blank.

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
worker subagent (`tank`, `trinity`, `oracle`, `dozer`, `seraph`, `neo`, `sentinel`). Dispatching a
worker is ordinary in-repo development — the worker reads and edits files in this working tree and
returns a summary. It is not remote execution, and it sends nothing outside the repository.

The crew's guard hooks bound what a worker can do: only `morpheus` touches git, no agent commits on
the base branch, each worker's edits are confined to its own lane, and destructive shell commands
are refused. Nothing is pushed and no pull request is opened on its own — `/crew:pr` is the only
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
Say plainly that `.claude/crew.md` is committed and shared with the repo.

If the user would rather keep crew configuration out of the repo, write no config file:
`morpheus` already resolves any unset slot per session (its memory → ask) and remembers the answer
locally. Report the detected values for reference, still ensure the `## Crew orchestration` prose
(§3) is present, and stop.

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
     in place — it belongs there (§3).

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
