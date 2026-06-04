---
name: frontend-headless
description: Conventions for decoupled/headless frontends — a React SPA (or Next.js) consuming Optimizely's Content Delivery API / Optimizely Graph (GraphQL) rather than Razor server rendering. Load this when the repo's frontend mode is "headless" (see the crew configuration in CLAUDE.md). Use for component and data-layer work in headless setups.
---

# Headless frontend conventions

Confirm the actual setup from the repository before assuming — framework (React SPA, Next.js, etc.), data source (Content Delivery API REST vs Optimizely Graph/GraphQL), and the data-fetching client in use. Follow the repo's existing patterns over the defaults below.

## Data layer
Fetch content from the content API; never hardcode content that should come from the CMS. Centralize API access in a typed client/layer rather than scattering fetch calls through components. Type the responses.

## Server state vs UI state
Keep fetched/server state in a data-fetching layer (e.g., RTK Query or React Query) with proper caching and loading/error handling. Put only genuine UI state in Redux. Don't dump raw API responses into the Redux store by reflex.

## Content-type → component mapping
Render CMS blocks/components by content type through a resolver or registry, with a clear, single mapping. Avoid large if/switch chains scattered across the tree.

## Preview / on-page edit
If the repo supports Optimizely preview or on-page editing, preserve it — handle preview tokens and draft content, and don't break the editor experience when changing rendering.

## Routing and states
Routing is client-side. Handle loading, empty, error, and 404 states explicitly for every content-driven view.

## SSR/SEO
If the repo uses Next.js or similar, respect the rendering strategy it already uses (SSR/SSG/ISR) — don't mix paradigms within the same app.

## Styling and boundaries
SCSS and design tokens per repo conventions. No Razor/`.cshtml` in this mode. Coordinate the API/data contract with the backend agent rather than guessing field shapes.
