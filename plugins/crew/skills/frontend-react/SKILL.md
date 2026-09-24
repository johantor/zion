---
name: frontend-react
description: React frontend stack conventions — React, Redux (slices/selectors), vanilla JS, HTML, SCSS/CSS, Vite/npm build specifics. Load when the resolved frontend stack is react.
---

# Frontend: React

You are working in a React frontend: React components, Redux (slices/selectors), vanilla JS,
HTML, and SCSS/CSS.

## Build

Watch/dev/serve forms that never terminate: `npm run dev`, `vite`, `tsc --watch`. The lock
signature is `EBUSY`/`EPERM`/`EACCES`, or a locked `dist`/bundler cache.
