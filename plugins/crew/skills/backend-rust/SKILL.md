---
name: backend-rust
description: Rust backend stack conventions — cargo workspaces, check/build/clippy as the gate, features and editions, and the inline `#[cfg(test)]` ownership split with oracle. Load when the resolved backend stack is rust.
---

# Backend: Rust

You are working in a Rust backend: a cargo package or workspace (`Cargo.toml`), and whatever
async runtime and framework the project already uses (tokio + axum, actix-web, or a plain binary
crate — follow the project).

Read `Cargo.toml` before you add anything. The `edition`, the workspace members, and the
`[features]` table all change what compiles; a workspace's `[workspace.dependencies]` is where a
shared version lives, and adding the same crate at a member's own version is a divergence, not a
convenience.

## Idiom

- Return `Result<T, E>` and propagate with `?`. Reserve `unwrap`/`expect` for cases you can argue
  are unreachable, and say why in the `expect` message.
- Errors: `thiserror` for a library's typed errors, `anyhow` for a binary's context chain. Follow
  whichever the project already has rather than adding the other.
- Prefer borrowing to cloning, but don't contort a lifetime to avoid one `clone` in cold code.
- A public API change (visibility, signature, trait bound) is a semver event in a library crate —
  say so in your findings rather than treating it as an internal edit.

## Inline unit tests are a shared-file split

Rust puts unit tests **inside the source file** in a `#[cfg(test)] mod tests` block, while
integration tests live in `tests/`. That makes a `.rs` file shared by concern, the same way a
Razor view is:

- **`tests/**` is `oracle`'s** — integration tests, by file.
- **An inline `#[cfg(test)]` block is yours**, because it lives in a file in your lane and
  `oracle` cannot write it without touching your production code.

So write the inline unit tests for code you implement, and coordinate with `morpheus` on what
`oracle` covers from `tests/` rather than leaving a module untested because the tests would have
to live in your file.

## Build

Use the one-shot backend build command from crew config — typically `cargo check` or
`cargo build`, usually with `cargo clippy` beside it. Never run `cargo watch` as the build; it
never terminates.

Run it as strict as the project configures:

- **Warnings are the point.** `cargo build` exits 0 with warnings present unless the project sets
  `-D warnings`. Read the warning summary, not the exit code, and report every warning: the lint
  name, `file:line`, and a count per lint.
- **Never relax the lint level.** Don't pass `--cap-lints`, don't add an `#[allow(...)]` to
  silence a finding you were asked to fix, and don't drop `-D warnings` from a configured
  `RUSTFLAGS`. Lint configuration belongs to `Cargo.toml`/`clippy.toml`.
- **Never narrow the target set.** `--lib` or `-p <one-member>` compiles less than the workspace;
  `--all-targets` includes tests and benches, which is usually what the gate wants. Keep the
  configured shape.
- **`cargo check` is not `cargo build`.** It skips codegen, so it will not catch a monomorphization
  or link error. If the project gates on `check`, that is its choice — but don't substitute
  `check` for a configured `build` to finish faster.
- **Features change what compiles.** Don't add `--no-default-features` or a feature flag the
  project doesn't configure to route around a broken module.

If the command **you were given** already carries one of these weakenings, don't rewrite it and
don't report the build clean: name it as your first finding.

## `target/` is per-writer state

Cargo takes a lock on `target/`, so a second concurrent build **blocks** rather than corrupting —
you will see "Blocking waiting for file lock on build directory". That is contention, not a code
error, and not the user's dev server. If another crew build may be live against the same package,
either wait for it or set `CARGO_TARGET_DIR` to your own path before you start, and say which you
did in your findings.

## Docs

When a docs MCP (e.g. Context7) is available, consult it for current, version-specific API docs
for the runtime or framework crate rather than relying on memory; fetch the specific topic, not a
dump (`context-discipline`).
