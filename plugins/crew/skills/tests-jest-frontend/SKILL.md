---
name: tests-jest-frontend
description: Jest frontend component/unit test conventions — test authoring with React Testing Library, mocking patterns, and running. Load when the resolved frontend unit test tool is jest.
---

# Frontend unit tests: Jest

Write and run frontend component and unit tests using Jest conventions and the repository's
frontend test command from `CLAUDE.md`.

- Test files are typically co-located with their source file (`Button.test.tsx` next to
  `Button.tsx`) or collected under `src/__tests__/`. Check the project's `jest.config.*` (or
  the `jest` key in `package.json`) for the actual `testMatch` / `testPathPattern` before
  creating a new file.
- Use `@testing-library/react` (`render`, `screen`, `userEvent`) for component tests; use
  plain `jest.fn()` / `jest.spyOn()` for unit mocks and `jest.mock()` for module mocks.
- Prefer queries that reflect how users perceive the UI (`getByRole`, `getByLabelText`,
  `getByText`) over implementation-detail selectors (`getByTestId`, CSS class).
- Run with the repo's frontend test command; on re-verify, run only the failing test(s)
  (pass the test file path or `--testPathPattern` filter), not the whole suite.
