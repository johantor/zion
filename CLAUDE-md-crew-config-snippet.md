# Crew configuration (CLAUDE.md snippet)

Paste a block like this into each repository's `CLAUDE.md`. It's how the generic
crew specializes to a specific codebase without editing any agent files: the
agents read these values at runtime and adapt.

```markdown
## Crew configuration

- **Frontend mode:** headless        <!-- or: server-rendered -->
- **Backend test command:** dotnet test
- **Frontend test command:** npm run cypress:run
- **Build command:** dotnet build && npm run build
- **Run/dev URL:** http://localhost:5000
- **Notable conventions:** <link to or summarize repo-specific patterns,
  e.g. content-type registration, folder layout, naming>
```

## How the crew uses it

- **trinity (frontend):** reads **Frontend mode** and loads the matching skill —
  `frontend-headless` or `frontend-server-rendered` — via the Skill tool before
  starting. This keeps trinity a single, agnostic agent instead of one-per-paradigm.
- **oracle / dozer (tests):** use the **Backend/Frontend test command** rather than
  assuming `dotnet test` or a fixed Cypress invocation.
- **seraph (design):** uses the **Run/dev URL** as the target to screenshot.
- **morpheus (orchestrator):** treats this block as part of the plan context and
  passes the relevant values into each delegation prompt, since workers start fresh
  and only see what morpheus hands them.

If a repository has no frontend (or no design step), morpheus simply doesn't
delegate to the unused workers — the dormant-by-default design means extra agents
sitting idle cost nothing.

Version and structural differences (Optimizely 11 vs 12, .NET 8 vs 12, React 18 vs
19, folder layout, naming) are handled here plus Context7 and any per-repo
convention skills — not by adding more agents. Add a specialized agent only at a
true paradigm boundary, and even then prefer a loadable mode skill first.
