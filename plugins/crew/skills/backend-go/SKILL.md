---
name: backend-go
description: Go backend stack conventions — modules and workspace layout, go build/vet as the gate, error-handling idiom, build tags. Load when the resolved backend stack is go.
---

# Backend: Go

You are working in a Go backend: a module (`go.mod`), the standard library first, and whatever
router/service framework the project already uses (`net/http`, chi, gin, echo — follow the
project, don't introduce a second one).

Match the project's layout rather than importing one. `cmd/<binary>/`, `internal/`, and `pkg/`
are conventions, not requirements; a flat single-package tool is a valid shape. `internal/` is
enforced by the compiler — code outside the module cannot import it, so moving a package in or
out of `internal/` is an API change, not a tidy-up.

## Idiom

- Return errors, don't panic. A `panic` in library code is a bug; reserve it for genuinely
  unrecoverable program state in `main`.
- Wrap with `fmt.Errorf("...: %w", err)` so callers can `errors.Is`/`errors.As`. Don't discard
  the cause by formatting it with `%v` when the caller may need to match on it.
- Accept interfaces, return structs. Define the interface where it is *consumed*, not beside the
  implementation.
- A `context.Context` is the first parameter of any call that does I/O, and it is passed through,
  never stored in a struct.
- `go.mod`'s `go` directive sets the language version — don't use a construct newer than it
  without raising the directive deliberately.

## Build

Use the one-shot backend build command from crew config — typically `go build ./...`, usually
with `go vet ./...` beside it. Never run a watch/dev command (`air`, `reflex`, `gow`) as the
build; those never terminate.

Run it as strict as the project configures:

- **Never narrow the package pattern.** `go build ./cmd/...` compiles less than `./...` and can
  report clean while another package is broken. If the configured command says `./...`, keep it.
- **`go build` alone is not the whole gate.** It does not run `go vet`'s checks. When the
  configured command pairs them, run both and report both.
- **A cached build proves nothing new.** Go's build cache means an unchanged tree compiles
  instantly; that is fine, but don't read a fast no-op as evidence your change compiled. Check
  that the packages you touched are in the output of the run.
- **Never pass `-tags` the project doesn't configure** to route around a broken file. Build tags
  select which files compile — adding one hides the failure rather than fixing it.

If the command **you were given** already narrows the pattern or drops `vet`, don't rewrite it and
don't report the build clean: name the weakening as your first finding.

Report failures as the compiler emits them — `file:line:col: message`, deduplicated with a count
per message — not the raw log (`context-discipline`).

## Lint and format

`gofmt -l .` / `gofumpt -l .` list unformatted files and exit 0, so read the output, not the exit
code. `golangci-lint run` is the usual verify command. Never run the `-w`/`--fix` write forms as
a gate.

## Docs

When a docs MCP (e.g. Context7) is available, consult it for current, version-specific API docs
for the router or driver you are coding against rather than relying on memory; fetch the specific
topic, not a dump (`context-discipline`).
