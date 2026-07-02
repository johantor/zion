---
name: tests-cypress
description: Cypress e2e test conventions — spec writing, fixture/intercept patterns, and running. Load when the resolved frontend e2e tool is cypress.
---

# Frontend e2e tests: Cypress

Write and run frontend e2e specs using Cypress conventions and the repository's frontend test command from `CLAUDE.md`.

- Spec files live in `cypress/e2e/` (Cypress ≥ 10) or `cypress/integration/` (Cypress < 10).
- Use `cy.intercept()` for network stubbing and `cy.fixture()` for test data.
- Prefer `data-cy` / `data-testid` selectors over CSS or text selectors for test stability.
- Run with the repo's frontend test command; on re-verify, run only the failing spec(s) (pass
  the spec file path or `--spec` flag), not the whole suite.
