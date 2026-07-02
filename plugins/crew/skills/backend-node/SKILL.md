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

## Build

Use the one-shot backend build command from `CLAUDE.md`, never a watch/dev command
(`nodemon`, a framework's dev server) — those never terminate. A file-lock/in-use error
(`EBUSY`/`EPERM`/`EACCES`, a locked `dist`/build output) is **environmental** (a running dev
process is locking outputs), not a code error — report it as such.

## Docs

When a docs MCP (e.g. Context7) is available, consult it for current, version-specific API
docs for the service framework or Graph client before coding against them rather than relying
on memory; fetch the specific topic, not a dump (`context-discipline`).
