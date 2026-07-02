---
name: tests-cypress
description: Cypress test conventions — e2e spec writing and component testing. Load when the resolved frontend e2e tool is cypress, or when cypress is the resolved frontend unit test tool.
---

# Frontend tests: Cypress

Cypress can be used for two distinct test types; apply only the sections relevant to the delegation scope.

## E2e tests

Write and run frontend e2e specs using Cypress conventions and the repository's frontend test command from `CLAUDE.md`.

- Spec files live in `cypress/e2e/` (Cypress ≥ 10) or `cypress/integration/` (Cypress < 10).
- Use `cy.intercept()` for network stubbing and `cy.fixture()` for test data.
- Prefer `data-cy` / `data-testid` selectors over CSS or text selectors for test stability.
- Run with the repo's frontend test command; on re-verify, run only the failing spec(s) (pass
  the spec file path or `--spec` flag), not the whole suite.

## Component tests

Write and run component/unit tests using Cypress Component Testing. Run them with the project's
own component-test script if it defines one; otherwise invoke Cypress component mode directly
(`npx cypress run --component`). The `Frontend test command` slot is the **e2e** command — don't
use it for component tests.

- Component test files live alongside source files or in `cypress/component/`; they use the
  `.cy.ts` / `.cy.tsx` / `.cy.js` / `.cy.jsx` extension.
- Mount components with `cy.mount()` (provided by the framework adapter — e.g.
  `@cypress/react` or `@cypress/vue`); import and configure the adapter in
  `cypress/support/component.ts` if not already done.
- Use `cy.intercept()` for network stubbing; keep assertions on rendered output, not
  implementation details.
- Prefer `data-cy` / `data-testid` selectors over CSS or text selectors.
- On re-verify, run only the failing spec(s) via `--spec` (in component mode, i.e.
  `--component`), not the whole suite.
