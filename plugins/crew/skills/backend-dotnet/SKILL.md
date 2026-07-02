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

Use the one-shot backend build command from `CLAUDE.md` (e.g. `dotnet build`), never a
watch/run command (`dotnet watch`, `dotnet run`) — those never terminate. A file-lock/in-use
error (`MSB3027`/`MSB3026`, "being used by another process") is **environmental** (a running
app/dev process is locking outputs), not a code error — report it as such.

## Docs

When a docs MCP (e.g. Context7) is available, consult it for current, version-specific .NET
API docs before coding against them rather than relying on memory; fetch the specific topic,
not a dump (`context-discipline`).
