---
name: backend-node
description: Node backend stack conventions — service framework conventions (NestJS/Express/Fastify), headless CMS/Graph client usage, npm/pnpm/yarn workspace awareness. Load when the resolved backend stack is node.
---

# Backend: Node

You are working in a Node backend: a service framework (NestJS, Express, or Fastify — follow
whichever the project already uses), a headless-CMS/Graph client (e.g. Optimizely Graph), and
an npm/pnpm/yarn workspace.

In a SaaS-headless project shape, the "backend" may be thin — a BFF layer or a handful of API
routes wrapping Graph queries. Don't invent backend surface area the project doesn't have; a
thin backend is a valid shape, not a gap to fill.

## Route-handler ownership (Next.js frontend)

When the frontend stack is Next.js, its route handlers (`app/**/route.ts`) physically live
inside the frontend app directory but are **your lane by concern** — the same way Razor's
`@functions`/`@code` blocks are yours inside a `.cshtml` file trinity otherwise owns the
markup of. Implement route-handler business logic there rather than leaving it to trinity;
coordinate the markup/data contract instead of avoiding the file. `lane-guard.sh` exempts
these paths from your directory-based deny for this reason.

## Build

Watch/dev forms that never terminate: `nodemon`, a framework's dev server. The lock signature is
`EBUSY`/`EPERM`/`EACCES`, or a locked `dist`/build output.
