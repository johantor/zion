---
name: backend-dotnet
description: .NET backend stack conventions — MVC controllers, Razor server-side ownership, dotnet build specifics. Load when the resolved backend stack is dotnet. If the project also uses Optimizely CMS, also load `cms-optimizely`.
---

# Backend: .NET

You are working in a .NET backend: C#, ASP.NET MVC controllers, and the server-side of Razor
views. If the project uses Optimizely CMS (detect via an `EPiServer.CMS`/`Optimizely.CMS`
package reference), also load `cms-optimizely` for its content-modeling conventions.

## Razor ownership (server-rendered mode)

Own the server-side of Razor (`.cshtml`): view-model binding, `@functions`/`@code`, control
flow over data, and data access. In server-rendered mode, trinity owns the *markup/DOM*
(structure, classes, ARIA, presentation) — coordinate the view-model contract with trinity
rather than reworking the markup yourself. In headless mode, Razor is entirely yours.

## Build

Use the one-shot backend build command from crew config (e.g. `dotnet build`), never a
watch/run command (`dotnet watch`, `dotnet run`) — those never terminate.

### `obj/` is per-writer state, not a shared cache

MSBuild writes `project.assets.json`, `*.nuget.g.props`/`*.nuget.g.targets`,
`*.csproj.nuget.dgspec.json` and the per-configuration intermediates into `obj/`. Two processes
racing over those corrupt or truncate them — you get a restore that contradicts the project file
or a nonsense compile error, not a clean lock error that names itself. And `dotnet test`,
`dotnet publish` and `dotnet format` all build, so each of them is a writer too.

- **Shareable across concurrent builds:** the NuGet package cache (`NUGET_PACKAGES`). It is
  read-mostly, and it is where the warm-cache benefit actually lives — point every build at one.
- **Never shared by concurrent builds:** `BaseIntermediateOutputPath` and `BaseOutputPath`
  (`obj/`, `bin/`). They are per-build-writer.

So if another crew build/test/lint run may be live against the same project, either wait for it or
get your own `-p:BaseIntermediateOutputPath=` / `-p:BaseOutputPath=` before you start. Say which
you did in your findings — morpheus knows the dispatch and you do not.

### A lock error is not automatically the user's environment

A file-lock/in-use error (`MSB3027`/`MSB3026`, "being used by another process"), or corrupt/
truncated `obj/` state, has two causes: a running app/dev process holding the outputs, **or** two
crew builds sharing `obj/`. Report the failure, the path it names, and whether you had the
intermediate path to yourself — and don't assert the user's dev server is at fault when you were
building against a location you were not given exclusively.

## Docs

When a docs MCP (e.g. Context7) is available, consult it for current, version-specific .NET
API docs before coding against them rather than relying on memory; fetch the specific topic,
not a dump (`context-discipline`).
