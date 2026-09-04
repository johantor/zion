---
name: tests-shell
description: Shell test conventions — bats where the project uses it, a plain-bash harness otherwise, asserting on both the allow and the block side. Load when the resolved backend stack is shell.
---

# Backend tests: shell (bats / plain-bash harness)

Detect the shape before writing — shell projects use one of two, and they are not interchangeable:

- **`*.bats` files, or `bats` in CI** → [bats-core]. `@test "name" { … }`, `run <cmd>` then assert
  on `$status` and `$output`, `setup`/`teardown` per test, `setup_file`/`teardown_file` per file.
- **A plain-bash harness** (a `tests/` directory of `*.test.sh` plus a `lib.sh` of assertions, run
  by a `run.sh`) → follow the harness that is there. Read its assertion helpers first and use
  them; do not introduce bats beside it.
- Neither → ask rather than choosing a framework for the project.

## What a shell test asserts

A script's observable behavior is its **exit code**, its **stdout/stderr**, and the **files it
touched**. Assert on the ones that matter and say which:

- Exit code for a script whose job is to pass or fail (a guard, a check, a validator).
- Output for a script whose job is to produce something — match a substring, not the whole stream,
  so unrelated wording changes don't fail the test.
- Filesystem state for a script that writes: build the fixture, run, then assert on what is there.

**Test both directions.** A guard tested only on what it blocks will pass while blocking
everything; one tested only on what it allows will pass while blocking nothing. Every rule needs
an allow case and a block case, and a new rule lands with both.

## Fixtures

Build a throwaway tree per case rather than sharing mutable state between tests. Use the harness's
own helper if it has one; otherwise `mktemp -d "${TMPDIR:-/tmp}/name.XXXXXX"` — bare `mktemp -d`
is not portable — and clean up in a trap so a failing test still tidies.

Stub an external tool by putting a fake executable earlier on `PATH` than the real one. When a
case depends on a tool being **absent**, do not assume the host lacks it: mirror `PATH` without
that tool, or the test passes or fails by accident of the machine.

## Running

Run tests using the repository's backend test command from crew config — the harness's `run.sh`,
or `bats tests/`.

A targeted rerun:

- bats: `bats tests/foo.bats -f 'name filter'`, or the single file.
- A plain harness: the single `*.test.sh` file, if its runner takes one; read the runner rather
  than assuming.

Notes on reading a run:

- **A harness that reports "0 tests" is a failure to report**, not a pass — usually a discovery
  glob that no longer matches.
- A test that runs the shell under test through `bash -c` loses `set -e` semantics from the outer
  script; assert on the child's exit code, not the parent's.
- Keep the suite offline and build-free: no network, no package install, no LLM. A shell suite
  that needs any of those has stopped being a unit test.

Never make a test pass by deleting its assertion or narrowing it to what the code currently
prints. If the script is wrong, say so and hand it back.

[bats-core]: https://github.com/bats-core/bats-core
