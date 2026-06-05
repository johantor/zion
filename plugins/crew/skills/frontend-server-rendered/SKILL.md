---
name: frontend-server-rendered
description: Conventions for server-rendered frontends — Optimizely/.NET MVC with Razor views and React used as mounted islands/widgets rather than a full SPA. Use for tasks involving Razor/.cshtml views, Optimizely/.NET MVC, display templates/IContentRenderer, or React mounted as islands/widgets. Load when the repo's frontend mode is "server-rendered".
---

# Server-rendered frontend conventions
Confirm the actual setup from the repo first; follow its patterns over these defaults.

- **Razor/CMS rendering:** render content through the CMS pipeline (display templates, `IContentRenderer`, partials), not hardcoded markup; keep logic out of views.
- **React as islands:** mount components into Razor-rendered DOM nodes; pass initial data via `data-*` attributes or an embedded JSON island — don't re-fetch data the page already has.
- **Progressive enhancement:** usable server-rendered first; React layers on top.
- **State:** keep React/Redux state scoped to its island; don't SPA-ify the whole page.
- **Styling:** SCSS via the .NET/front-end build pipeline per repo conventions.
- **Razor ownership is concern-split:** the *markup/DOM* inside views (element structure, classes, ARIA, presentation) is the frontend agent's; the C# view-model + controller side is the backend agent's. Coordinate the contract rather than crossing into each other's concern.
