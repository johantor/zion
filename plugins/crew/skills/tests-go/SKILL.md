---
name: tests-go
description: Go backend test conventions — _test.go beside the source, table-driven subtests, targeted reruns with -run, the race detector. Load when the resolved backend stack is go.
---

# Backend tests: Go (`go test`)

Go's test framework is the standard library's `testing` package; there is no framework to detect.
Check whether the project uses an assertion library (`testify`, `gotest.tools`) before writing —
if it does, follow it; if it doesn't, don't introduce one.

## Layout

Tests live **beside the code they test**, as `<file>_test.go` in the same directory. Two package
choices, and the project's existing one is the answer:

- `package foo` — an internal test, with access to unexported identifiers.
- `package foo_test` — an external test, restricted to the exported API. Prefer this for anything
  that is really testing the package's contract; it catches an API that is awkward to use.

`testdata/` is ignored by the toolchain and is where fixtures belong. A test that needs a helper
binary or a golden file puts it there rather than in the package directory.

## Writing

- **Table-driven with subtests** is the idiom: a slice of cases, then `t.Run(tc.name, func(t
  *testing.T) { … })`. Subtests give each case its own name in the output and let a rerun target
  one of them.
- `t.Helper()` in any assertion helper, so a failure reports the caller's line rather than the
  helper's.
- `t.Cleanup(...)` over `defer` for teardown that must run even when a subtest fails early.
- Use `t.Fatalf` when continuing would panic (a nil result), `t.Errorf` when the test can usefully
  report more failures.
- Never call `t.Parallel()` on subtests that share mutable state through the loop variable or a
  package-level fixture — that is how a suite becomes intermittently red.

## Running

Run tests using the repository's backend test command from crew config — typically
`go test ./...`.

A **targeted rerun** uses `-run`, anchored so it matches one test and not its prefixes:

- `go test ./pkg/foo -run '^TestName$'` — one test.
- `go test ./pkg/foo -run '^TestName$/^case_name$'` — one subtest (spaces in a subtest name become
  underscores in the `-run` path).

Notes on reading a run:

- `go test` **caches** passing results. A rerun that prints `(cached)` did not execute the test;
  when you need a real run, `-count=1` defeats the cache.
- `ok … [no test files]` is not a pass — it means the package has no tests at all. Report it as a
  gap rather than as green.
- `-race` is a different build. If the project's command carries it, keep it: a race the detector
  finds does not reproduce without it. Never drop `-race` to make a run finish faster.

Never make a test pass with `t.Skip`, and never loosen an assertion to whatever the code currently
returns. If the production code is wrong, say so and hand it back.
