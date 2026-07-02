---
name: frontend-nextjs
description: Next.js frontend stack conventions — App Router, Server/Client Components, data fetching (e.g. Optimizely Graph), npm build specifics. Load when the resolved frontend stack is nextjs.
---

# Frontend: Next.js

You are working in a Next.js frontend: App Router, React Server Components (RSC) and Client
Components, and data fetching from the project's headless CMS/API (e.g. Optimizely Graph).

## Server/client split

- **Server Components** run on the server: data fetching, no browser APIs, no event handlers.
  Prefer them by default.
- **Client Components** (`"use client"`) are for interactivity — state, effects, browser APIs,
  event handlers. Keep the client boundary as small as possible; push data fetching to the
  server.

Route-handler ownership and other lane boundaries specific to Next.js are covered in your
lane rules, not here — this skill is framework conventions only.

## Build

A file-lock/in-use error (`EBUSY`/`EPERM`/`EACCES`, a locked `.next`/bundler cache) during the
one-shot build is **environmental** (a running dev server/watcher is locking outputs), not a
code error — report it as such. Never run a watch/dev/serve command (`npm run dev`,
`next dev`) as the build — those never terminate.

## Docs

When a docs MCP (e.g. Context7) is available, consult it for current, version-specific
Next.js API docs before coding against them; fetch the specific topic, not a dump
(`context-discipline`).
