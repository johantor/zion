# Copilot instructions for guided reviews

When asked to review changes in this repository, use this sequence:

1. Review only changed files first, then expand to impacted neighbors when needed.
2. Classify findings by severity:
   - **Blocking**: must fix before merge (bugs, security flaws, broken behavior, missing required tests).
   - **Warnings**: should fix soon (maintainability or clarity risks).
   - **Passed**: checks that were explicitly reviewed and look good.
3. Always evaluate changes against `engineering-principles`:
   - YAGNI, KISS, clear naming, focused/small diffs, and pragmatic DRY.
4. Always include a security pass:
   - Input validation, auth/authorization checks, secrets exposure, injection risks, unsafe deserialization, and dependency risk.
5. Prefer concrete, actionable feedback:
   - Point to exact files/areas and describe expected behavior.
   - Suggest minimal-scope fixes over broad rewrites.
6. Call out test coverage impact:
   - Identify missing or weak tests for behavior changes.
   - Mark test-only issues as warnings unless they hide a correctness gap.
7. Avoid noise:
   - Do not block on style-only nits unless they violate existing repository conventions.

For review responses, use this exact heading structure:

## Blocking

## Warnings

## Passed
