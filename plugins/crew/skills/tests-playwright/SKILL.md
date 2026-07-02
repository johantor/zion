---
name: tests-playwright
description: Playwright e2e test conventions — spec writing, fixture/mock patterns, and running. Load when the resolved frontend e2e tool is playwright.
---

# Frontend e2e tests: Playwright

Write and run frontend e2e specs using Playwright conventions and the repository's frontend test command from `CLAUDE.md`.

- Spec files typically live in `tests/` or `e2e/` (configured via `playwright.config.*`). In
  crew, keep them in a structured e2e location — `e2e/` or `tests/e2e/` — so they stay in
  dozer's lane; a bare root `tests/` is only in-lane when a **Frontend lane path** is configured
  (lane-guard confines dozer to it there).
- Use `page.route()` for network mocking; `test.use({ storageState })` for auth state reuse.
- Prefer `getByRole()`, `getByTestId()`, and `getByLabel()` locators — avoid CSS/XPath selectors.
- Run with the repo's frontend test command; on re-verify, run only the failing spec(s) (pass
  the spec file path or `--grep` flag), not the whole suite.
