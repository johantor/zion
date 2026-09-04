---
name: tests-cargo
description: Rust backend test conventions — the inline unit test vs tests/ integration split and who owns which, cargo test filters for targeted reruns, nextest. Load when the resolved backend stack is rust.
---

# Backend tests: cargo (Rust)

Rust's test framework is built into the toolchain; there is no framework to detect. Check whether
the project uses `rstest`, `proptest`, `insta` or `cargo-nextest` before writing — follow what is
there rather than adding another.

## Two kinds of test, and only one of them is yours

- **`tests/*.rs` — integration tests. Your lane.** Each file is compiled as its own crate and can
  use only the package's **public** API, which is exactly what an integration test should exercise.
  Shared helpers go in `tests/common/mod.rs` (a subdirectory module, not `tests/common.rs`, which
  would itself be collected as a test crate).
- **Inline `#[cfg(test)] mod tests` — unit tests. Not your lane.** They live *inside* the
  production source file, so writing one means editing a file `tank` owns. A `.rs` file is shared
  by concern the way a Razor view is, and a file glob cannot see inside it.

So: write the integration tests, and when a module needs unit-level coverage that only an inline
test can reach (a private function, an internal invariant), **report that to `morpheus`** so it
goes back to `tank` — don't restructure production code to make the test reachable from `tests/`,
and don't make a private item public just so you can test it.

Doc tests are a third kind: examples in `///` comments compile and run under `cargo test`. They
live in the production file too, so the same split applies.

## Writing

- `#[test]` functions return `()` or `Result<_, E>`; returning `Result` lets you use `?` instead of
  a chain of `unwrap`s, and a returned `Err` fails the test with the error.
- `#[should_panic(expected = "…")]` needs the `expected` string — a bare `should_panic` passes on
  *any* panic, including one from a bug unrelated to what you meant to assert.
- Async tests need the runtime's attribute (`#[tokio::test]`), not `#[test]`.
- `assert_eq!`/`assert!` take a trailing message; use it when the values alone won't say what
  broke.

## Running

Run tests using the repository's backend test command from crew config — typically `cargo test`.
If the project has `cargo-nextest` configured, use it as the project does; note that nextest does
**not** run doc tests, so a project on nextest usually runs `cargo test --doc` beside it.

A **targeted rerun** is a filter, not a full run:

- `cargo test <substring>` — every test whose full path contains the substring.
- `cargo test --test <file_stem>` — one integration test crate.
- `cargo test --lib <substring>` — unit tests only.
- `cargo test -p <member>` — one workspace member.
- Add `-- --exact <full::path>` when a substring would match more than you want.

Notes on reading a run:

- The summary is **per test binary**. A workspace prints one `test result:` line per crate, so
  read them all — an early `ok` says nothing about the next binary.
- `0 passed; 0 failed` for a target means it has no tests, not that it is green. Report it as a gap.
- Output from passing tests is captured by default; `-- --nocapture` shows it when you are
  diagnosing.
- `cargo test` builds first, so a compile error is a build failure, not a test failure — report it
  as one.

Never make a test pass with `#[ignore]`, and never weaken an assertion to whatever the code
currently returns. If the production code is wrong, say so and hand it back.
