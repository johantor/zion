---
name: backend-python
description: Python backend stack conventions — FastAPI/Django/Flask service conventions, packaging and virtualenv awareness, typecheck-as-build, ruff/black lint. Load when the resolved backend stack is python.
---

# Backend: Python

You are working in a Python backend: a service framework (FastAPI, Django, or Flask — follow
whichever the project already uses), a dependency manifest (`pyproject.toml`, or a legacy
`requirements*.txt`/`setup.py`), and a virtual environment.

Read the project's own layout before adding to it. A `src/<package>/` layout, a flat package at
the repo root, and a Django project with per-app directories are all valid shapes — match the one
that is there rather than importing a layout from another project.

## Packaging and the environment

The dependency manifest tells you which tool the project uses; use that one and no other:

- `[tool.poetry]` in `pyproject.toml` → Poetry (`poetry run …`, `poetry add`).
- `uv.lock`, or `[tool.uv]` → uv (`uv run …`, `uv add`).
- `[tool.pdm]`/`pdm.lock` → PDM.
- `requirements*.txt` with no `pyproject.toml` → pip against the project's venv.

Never add a dependency by editing the lockfile, and never install into the system interpreter.
When a command fails with `ModuleNotFoundError` for a package the manifest lists, that is an
**environment** problem (the venv is not active or not synced), not a code error — report it as
such rather than adding the import path by hand.

## Build

Python has no compile step, so the crew-config **backend build command** is whatever the project
uses as its static gate — typically a type checker (`mypy`, `pyright`) and often an import or
collection check beside it. Run the configured command as configured.

Never run a watch/dev/serve command as the build — those never terminate:
`uvicorn … --reload`, `flask run`, `python manage.py runserver`, `watchmedo`, `pytest-watch`.

**A zero exit code is not automatically "clean".** Several Python tools report findings and still
exit 0 depending on configuration, and `mypy` reports per-file when handed paths instead of the
project. Read the summary line, not the exit code. Report findings as id, `file:line`, and a count
per id — not the raw log (`context-discipline`).

Run it as strict as the project configures. Never pass `--ignore-missing-imports`,
`--no-strict-optional`, `--follow-imports=skip`, or a narrowed path list to make a failing
typecheck pass; those settings belong to `pyproject.toml`/`setup.cfg`, not to the invocation. If
the command **you were given** already carries one of these, don't rewrite it and don't report the
build clean — name the weakening as your first finding.

## Lint

`ruff check`, `flake8`, `black --check`, and `isort --check-only` are report/verify mode; the
`--fix`/write forms are not a gate. Use the configured verify command.

## Docs

When a docs MCP (e.g. Context7) is available, consult it for current, version-specific API docs
for the service framework or ORM before coding against them rather than relying on memory; fetch
the specific topic, not a dump (`context-discipline`).
