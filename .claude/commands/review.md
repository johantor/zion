---
description: Run consolidated review across code quality, security, and design conformance
---

Run a read-only review of the current diff and return one consolidated report:

1. **Code quality** — check against `engineering-principles`: YAGNI, KISS, naming, error handling, test coverage, minimal-scope diff.
2. **Security** — scan for: injection risks, unvalidated inputs, secrets in code, unsafe deserialization, missing auth checks, open redirects, insecure dependencies.
3. **Design conformance** — delegate to `seraph` with the running URL and any available design reference; include its mismatch report verbatim.

Output format (use these headings):
- `## Blocking` — must fix before merge
- `## Warnings` — should fix, not blocking
- `## Passed` — explicitly confirmed clean areas
