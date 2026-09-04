#!/usr/bin/env bash
# Behavior tests for format.sh — the PostToolUse formatter. It differs from the
# guards in two ways that shape these tests: it never blocks (every path exits 0,
# so the assertions are on what it *reports* on stderr), and it is the one hook
# that mutates the user's files, by shelling out to whatever formatters the
# project configures. Those tools are faked as scripts in node_modules/.bin, so
# the suite keeps its no-build/no-network/no-LLM contract while still exercising
# the real detect -> run -> report path.
# shellcheck source=tests/hooks/lib.sh
# shellcheck disable=SC1090,SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../../../tests/hooks/lib.sh"
HOOK="format.sh"

# Short bound for the hang case below; the fake tools elsewhere are instant.
CREW_FORMAT_TIMEOUT=2
export CREW_FORMAT_TIMEOUT

# assert_reports <label> <payload> <cwd> <substr> — exit 0 and say <substr>.
assert_reports() {
  run_hook "$HOOK" "$2" "$3"
  if [ "$_status" -ne 0 ]; then
    _fail "$1: expected exit 0, got exit $_status${_stderr:+ — stderr: $_stderr}"
  elif [[ "$_stderr" != *"$4"* ]]; then
    _fail "$1: stderr missing '$4' (got: ${_stderr:-<empty>})"
  else
    _pass
  fi
}

# assert_silent <label> <payload> [cwd] — a no-op path must exit 0 saying nothing.
assert_silent() {
  run_hook "$HOOK" "$2" "${3:-}"
  if [ "$_status" -eq 0 ] && [ -z "$_stderr" ]; then
    _pass
  else
    _fail "$1: expected exit 0 with no stderr, got exit $_status${_stderr:+ — stderr: $_stderr}"
  fi
}

# web_project <prettier-body> -> a throwaway project configured for Prettier,
# with a fake `prettier` running <prettier-body>. Prettier stands in for the
# whole web lane: Biome/ESLint/Stylelint go through the same detect/run/report
# path, so one tool covers the mechanism.
web_project() {
  local dir
  dir="$(make_tree 'package.json:{"name":"fixture"}' '.prettierrc:{}')"
  mkdir -p "$dir/node_modules/.bin"
  printf '#!/bin/sh\n%s\n' "$1" > "$dir/node_modules/.bin/prettier"
  chmod +x "$dir/node_modules/.bin/prettier"
  printf '%s' "$dir"
}

# --- Gating: who and what the hook is a no-op for ------------------------------
ok_project="$(web_project 'exit 0')"
assert_silent "a non-formatter agent is a no-op" "$(payload_file oracle src/a.ts)" "$ok_project"
assert_silent "the main session (no agent_type) is a no-op" \
  "$(jq -nc '{tool_input: {file_path: "src/a.ts"}}')" "$ok_project"
assert_silent "an extension no formatter owns is a no-op" "$(payload_file neo scripts/a.sh)" "$ok_project"
assert_silent "no file_path is a no-op" "$(jq -nc '{agent_type: "tank"}')" "$ok_project"
assert_silent "the web lane without a package.json is a no-op" "$(payload_file tank src/a.ts)"

# --- Detect, run, report -------------------------------------------------------
assert_reports "a configured, installed formatter runs and is reported" \
  "$(payload_file tank src/a.ts)" "$ok_project" "applied prettier"
assert_reports "neo gets the same extension routing as tank/trinity" \
  "$(payload_file neo src/a.ts)" "$ok_project" "applied prettier"

bare="$(make_tree 'package.json:{"name":"fixture"}')"
assert_reports "a project with no formatter configured is reported as skipped" \
  "$(payload_file tank src/a.ts)" "$bare" "no configured formatter"

# Configured but not installed: never an npx download, and nothing claimed as run.
uninstalled="$(make_tree 'package.json:{"name":"fixture"}' '.prettierrc:{}')"
assert_reports "a configured but uninstalled formatter is skipped, not fetched" \
  "$(payload_file tank src/a.ts)" "$uninstalled" "no configured formatter"

failing="$(web_project 'exit 1')"
assert_reports "a formatter that rejects the file is reported as failed" \
  "$(payload_file tank src/a.ts)" "$failing" "prettier failed"

# --- A hung formatter is bounded, not waited out -------------------------------
# Without the bound this call would block for the sleep's full duration on every
# edit. `timeout` is GNU coreutils and absent on stock macOS/BSD, where the hook
# deliberately degrades to running unbounded — so assert this only where the
# binary the hook looks for actually exists.
if command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1; then
  hanging="$(web_project 'sleep 60')"
  started=$SECONDS
  assert_reports "a hung formatter is killed and reported as a timeout" \
    "$(payload_file tank src/a.ts)" "$hanging" "prettier timed out after ${CREW_FORMAT_TIMEOUT}s"
  elapsed=$((SECONDS - started))
  if [ "$elapsed" -lt 30 ]; then
    _pass
  else
    _fail "a hung formatter must not be waited out: the call took ${elapsed}s"
  fi
else
  echo "note: no timeout/gtimeout binary — skipping the bounded-formatter case" >&2
fi

# --- The non-web lanes: tools found on PATH, not in node_modules/.bin ----------
# These ship with a toolchain rather than a project, so the hook looks them up on
# PATH.
# PATH becomes a mirror of itself minus the tools under test, so a host that has
# gofmt or rustfmt installed can't decide the result. _fake_bin is searched first.
_fake_bin="$(mktemp -d)"
_mirror_bin="$(mktemp -d)"
_real_path="$PATH"
while IFS= read -r -d ':' _d || [ -n "$_d" ]; do
  [ -d "$_d" ] || continue
  for _f in "$_d"/*; do
    [ -x "$_f" ] || continue
    case "${_f##*/}" in
      ruff|black|gofmt|gofumpt|rustfmt|google-java-format|palantir-java-format) continue ;;
    esac
    [ -e "$_mirror_bin/${_f##*/}" ] || ln -s "$_f" "$_mirror_bin/${_f##*/}" 2>/dev/null
  done
done <<<"$PATH:"
fake_bin() { printf '#!/bin/sh\n%s\n' "$2" > "$_fake_bin/$1"; chmod +x "$_fake_bin/$1"; }
PATH="$_fake_bin:$_mirror_bin"; export PATH

plain="$(make_tree 'go.mod:module fixture')"

# Absent tool: skipped and said so, never a download and never a claimed run.
assert_reports "a Python file with no formatter on PATH is skipped" \
  "$(payload_file tank pkg/svc.py)" "$plain" "no Python formatter on PATH"
assert_reports "a Go file with no formatter on PATH is skipped" \
  "$(payload_file tank pkg/svc.go)" "$plain" "no Go formatter on PATH"
assert_reports "a Rust file with no rustfmt on PATH is skipped" \
  "$(payload_file tank src/lib.rs)" "$plain" "rustfmt not on PATH"
assert_reports "a Java file with no standalone formatter on PATH is skipped" \
  "$(payload_file tank src/main/java/Svc.java)" "$plain" "no standalone Java formatter on PATH"

# Present tool: runs and is reported.
fake_bin ruff 'exit 0'
assert_reports "ruff formats a Python file" \
  "$(payload_file tank pkg/svc.py)" "$plain" "applied ruff-format"
fake_bin gofmt 'exit 0'
assert_reports "gofmt formats a Go file" \
  "$(payload_file tank pkg/svc.go)" "$plain" "applied gofmt"
# gofumpt is a strict superset, so it wins wherever it is installed.
fake_bin gofumpt 'exit 0'
assert_reports "gofumpt wins over gofmt when both are present" \
  "$(payload_file tank pkg/svc.go)" "$plain" "applied gofumpt"
fake_bin rustfmt 'exit 0'
assert_reports "rustfmt formats a Rust file" \
  "$(payload_file tank src/lib.rs)" "$plain" "applied rustfmt"
fake_bin google-java-format 'exit 0'
assert_reports "google-java-format formats a Java file" \
  "$(payload_file tank src/main/java/Svc.java)" "$plain" "applied google-java-format"

# Bare rustfmt does not read Cargo.toml, so without this a later edition's source
# is reformatted against the 2015 default.
edition_tree="$(make_tree 'Cargo.toml:[package]
edition = "2021"')"
fake_bin rustfmt 'case "$*" in *"--edition 2021"*) exit 0 ;; *) exit 1 ;; esac'
assert_reports "the manifest edition is passed to rustfmt" \
  "$(payload_file tank src/lib.rs)" "$edition_tree" "applied rustfmt"

# A rejecting tool is reported as failed, not as applied.
fake_bin rustfmt 'exit 1'
assert_reports "a rustfmt that rejects the file is reported as failed" \
  "$(payload_file tank src/lib.rs)" "$plain" "rustfmt failed"

PATH="$_real_path"; export PATH
rm -rf "$_fake_bin" "$_mirror_bin"

finish
