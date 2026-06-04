---
description: Run pre-PR ship gate and return a go/no-go summary
---

Run the full ship gate in this order and return a single **GO** / **NO-GO** summary:

1. **Backend tests** — delegate to `oracle`: run the full test suite; surface any failures with file:line.
2. **Frontend e2e** — delegate to `dozer`: run the full spec suite; surface any failures with spec:line.
3. **Build** — run the backend build command from `CLAUDE.md`; surface compiler errors.
4. **Lint** — run the frontend lint command from `CLAUDE.md`; surface lint errors.
5. **Review** — run `/review` and include its `## Blocking` section.

Output format:
- **GO** — all gates passed; list each gate with ✅
- **NO-GO** — list each failing gate with ❌ and the blocking items that must be resolved before merging
