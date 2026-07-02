---
name: tests-node
description: Node backend test conventions — Vitest or Jest, detected by config file (vitest.config.* vs jest.config.*/package.json "jest" key). Load when the resolved backend stack is node.
---

# Backend tests: Node (Vitest / Jest)

Detect the test framework from its config file before writing or running tests — don't guess:

- `vitest.config.*` present → **Vitest** conventions (`describe`/`it`/`expect`, `vi.fn()`
  mocks).
- `jest.config.*`, or a `jest` key in `package.json`, present → **Jest** conventions
  (`describe`/`it`/`expect`, `jest.fn()` mocks).
- Neither present → ask rather than guessing which the project uses.

Run tests using the repository's backend test command from `CLAUDE.md`, whichever framework
it resolves to.
