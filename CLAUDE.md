# Zion — Claude Code notes

Zion is the `crew` Claude Code plugin pack: orchestrated agents, commands, hooks, and skills
for feature delivery. **This repository *is* the plugin** — there is no application code to
build or ship.

**Start with [AGENTS.md](AGENTS.md)** — the contributor guide (repository layout, how the
crew works, reviewing, validating, releasing, and conventions). It is tool-neutral and the
single source of truth for working in this repo.

This file adds only what is specific to Claude Code: the crew runtime configuration that
`morpheus` and the `crew:*` commands read.

## Crew configuration

These values are read by the `morpheus` orchestrator and the backend/frontend stack skills.
Keep them accurate; update them if this repo ever gains app code.

- **Frontend mode:** *unset* — optional here. Pin it (`headless` or `server-rendered`)
  only to force a choice; otherwise `morpheus` resolves it per project (its memory, or by
  asking you and then remembering). This repo is the plugin itself and has no frontend.
- **Backend stack:** *unset* — optional here. Pin it (`dotnet` or `node`) only to force a
  choice; otherwise `morpheus` resolves it per project. This repo has no backend.
- **Frontend stack:** *unset* — optional here. Pin it (`react` or `nextjs`) only to force a
  choice; otherwise `morpheus` resolves it per project. This repo has no frontend.
- **Backend lane path(s):** *unset* — only meaningful when backend/frontend stacks are the
  same language. This repo has no backend.
- **Frontend lane path(s):** *unset* — same same-language caveat. This repo has no frontend.
- **Backend test command:** none (no backend test project detected)
- **Frontend test command:** none (no frontend e2e suite detected)
- **Backend build command:** none (no build manifest detected) — e.g. `dotnet build`.
- **Frontend build command:** none (no build manifest detected) — e.g. the project's
  `build` / `typecheck` script (`tsc --noEmit`, `vite build`, etc.).
- **Backend lint command:** none (no backend project detected) — e.g. `dotnet format --verify-no-changes`,
  plus `dotnet csharpier check` when a `.csharpierrc` is present.
- **Frontend lint command:** none (no frontend project detected) — e.g. the project's
  `lint` script (`eslint`, `biome check`, `stylelint`, etc.) in report/verify mode.
- **Base branch:** *unset* — the branch `morpheus` branches off (e.g. `main` / `develop` /
  trunk). If unset, `morpheus` resolves it per project (its memory, or by asking you).
- **Branch naming:** *unset* — convention for crew feature branches (e.g. `feature/<ticket>-<slug>`).
- **Run/dev URL:** none configured
- **Plan directory:** *unset* — where `morpheus` writes `plan-<feature>.md`. Falls back to
  `.claude/` when unset; set it (e.g. `docs/plans/`) to keep plans in a committed location.
- **Notable conventions:** Repository currently contains Claude crew/plugin configuration only.
