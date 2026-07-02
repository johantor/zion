---
name: frontend-react
description: React frontend stack conventions — React, Redux (slices/selectors), vanilla JS, HTML, SCSS/CSS, Vite/npm build specifics. Load when the resolved frontend stack is react.
---

# Frontend: React

You are working in a React frontend: React components, Redux (slices/selectors), vanilla JS,
HTML, and SCSS/CSS.

## Build

A file-lock/in-use error (`EBUSY`/`EPERM`/`EACCES`, a locked `dist`/bundler cache) during the
one-shot build is **environmental** (a running dev server/watcher is locking outputs), not a
code error — report it as such. Never run a watch/dev/serve command (`npm run dev`, `vite`,
`tsc --watch`) as the build — those never terminate.

## Docs

When a docs MCP (e.g. Context7) is available, consult it for current, version-specific API
docs for React, Redux, or a component library before coding against them; fetch the specific
topic, not a dump (`context-discipline`).
