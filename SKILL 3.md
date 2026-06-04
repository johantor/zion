---
name: frontend-server-rendered
description: Conventions for server-rendered frontends — Optimizely/.NET MVC with Razor views and React used as mounted islands/widgets rather than a full SPA. Load this when the repo's frontend mode is "server-rendered" (see the crew configuration in CLAUDE.md). Use for Razor view, display-template, and embedded-React work.
---

# Server-rendered frontend conventions

Confirm the actual setup from the repository before assuming — Razor view structure, how React is bundled and mounted, and the front-end build pipeline. Follow the repo's existing patterns over the defaults below.

## Razor and CMS rendering
Render content through the CMS rendering pipeline (display templates, `IContentRenderer`, partial views) rather than hardcoding markup. Use view models, partials, and tag/HTML helpers consistently with the existing views. Keep logic out of the views.

## React as islands
React enhances server-rendered pages; it is not a second full application. Mount components into specific DOM nodes that Razor renders. Pass initial data via `data-*` attributes or an embedded JSON island that the server already has — don't re-fetch data the page was rendered with.

## Progressive enhancement
The page should be usable server-rendered first; React layers on top. Avoid blocking the initial render on JavaScript where it can be avoided.

## State
Keep React/Redux state scoped to the island it belongs to. Don't try to turn the whole page into a SPA or hoist page-wide state into a single store unless the repo already does.

## Styling and boundaries
SCSS via the .NET / front-end build pipeline per repo conventions. The C#/Razor view-model and controller side belongs to the backend agent — coordinate the view-model/data contract with it; this skill covers the React-island and view-template glue.
