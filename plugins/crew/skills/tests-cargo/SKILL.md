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

The backend test command from crew config is typically `cargo test`. If the project has
`cargo-nextest` configured, use it as the project does; nextest does **not** run doc tests, so a
project on nextest usually runs `cargo test --doc` beside it.

- **Targeted rerun:** `cargo test <substring>` (every test whose full path contains it),
  `cargo test --test <file_stem>` (one integration test crate), `cargo test --lib <substring>`
  (unit tests only), `cargo test -p <member>` (one workspace member); add `-- --exact
  <full::path>` when a substring would match more than you want.
- **Discovery:** `cargo test --test <file_stem> -- --list` prints the test names in that crate
  without running them; a test missing from the list has a `#[test]`, `cfg`, or module-path
  problem in the source.
- **Reading a run:** the summary is **per test binary** — a workspace prints one `test result:`
  line per crate, so read them all. `0 passed; 0 failed` for a target is the zero-tests gap.
  Output from passing tests is captured by default; `-- --nocapture` shows it. `cargo test`
  builds first, so a compile error is a build failure, not a test failure.
- **Skip mechanism:** `#[ignore]`.
