---
name: tests-pytest
description: Python backend test conventions — pytest layout and naming, conftest fixtures, parametrize, targeted reruns, unittest fallback. Load when the resolved backend stack is python.
---

# Backend tests: pytest (Python)

Detect the test framework from the project before writing anything — don't guess:

- `pytest.ini`, a `[tool.pytest.ini_options]` table in `pyproject.toml`, a `[pytest]` section in
  `setup.cfg`/`tox.ini`, or a `conftest.py` → **pytest**.
- Only `unittest.TestCase` subclasses and no pytest configuration → the project is on stdlib
  `unittest`. Write `unittest` tests; pytest can still run them, but don't introduce pytest-only
  constructs into a suite that doesn't use it.
- Neither present → ask rather than picking one.

## Naming and layout

pytest collects `test_*.py` and `*_test.py`, and within them `test_*` functions and `Test*`
classes (which must have no `__init__`). Follow the project's existing choice between the two file
spellings rather than mixing them.

Both a `tests/` directory beside the package and tests colocated in the package are valid; match
what is there. When `tests/` has no `__init__.py`, two test modules of the same basename in
different directories collide under the default import mode — give them distinct names rather than
adding `__init__.py` to a project that deliberately has none.

## Fixtures

`conftest.py` is where shared fixtures live, and it applies to its directory and below — a fixture
in the root `conftest.py` reaches every test. Prefer a narrow scope: put a fixture in the closest
`conftest.py` that needs it.

Fixture `scope=` (`function` by default, then `class`/`module`/`package`/`session`) decides how
often setup runs, and a wider scope shares mutable state between tests. Widen it only for
genuinely expensive, genuinely read-only setup, and never to make an order-dependent test pass.

Use `pytest.mark.parametrize` for the same assertion over several inputs rather than a loop inside
one test — a loop reports one failure and hides the rest.

## Running

Run tests using the repository's backend test command from crew config.

A **targeted rerun** is a node id or a `-k` expression, not the whole suite:

- `pytest path/to/test_mod.py::test_name` — one test.
- `pytest path/to/test_mod.py::TestClass::test_name` — one method.
- `pytest -k 'expression'` — by substring/boolean match on the name.

Read the summary line, not just the exit code: pytest exits non-zero on failures, but a run that
collected **zero** tests is also a failure to report (exit code 5), not a pass. `xfail`/`xpass` and
`skip` counts in the summary are results too — report them rather than folding them into "green".

Never make a test pass by marking it `skip` or `xfail`, and never widen an assertion to match
whatever the code currently returns. If the production code is wrong, say so and hand it back.
