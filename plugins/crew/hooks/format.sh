#!/usr/bin/env bash
# PostToolUse(Edit|Write) formatter, gated to tank/trinity/neo (other agents and
# the main session are no-ops). The formatter set is chosen by the edited file's
# extension, not a fixed agent->lane table: a backend stack can be dotnet or node,
# so lane != language. A Node-backend file tank edits still gets web tooling, and
# a .cs/.csproj file gets dotnet/CSharpier whichever agent produced it.
set -e

# Fail open: formatting is best-effort, so a missing library or jq is a no-op,
# not an error.
_lib="${BASH_SOURCE[0]%/*}/lib/guard-lib.sh"
# shellcheck source=plugins/crew/hooks/lib/guard-lib.sh
# shellcheck disable=SC1090,SC1091
. "$_lib" 2>/dev/null || exit 0
command -v jq >/dev/null 2>&1 || exit 0

guard_read_payload
# Both fields in one jq pass, and the path is only computed for an agent this
# hook formats for, so the far more common no-op call doesn't pay to look it up.
# neo is the cross-lane express-lane generalist, so it gets the same
# extension-based routing as tank/trinity rather than a fixed lane.
guard_jq2 \
  '(if ((.agent_type // "") | test("^(tank|trinity|neo)$")) then ((.tool_input.file_path // .tool_input.path) // "") else "" end)' \
  '.agent_type // ""' || exit 0
agent_type="$guard_trusted"
path="$guard_untrusted"

case "$agent_type" in
  tank|trinity|neo) : ;;
  *)                exit 0 ;;
esac
# Extension-based routing needs a path to route on.
[ -n "$path" ] || exit 0

ext="${path##*.}"
case "$ext" in
  cs|csproj) lane="dotnet" ;;
  js|jsx|ts|tsx|mjs|cjs|vue|svelte|css|scss|sass|less|json|jsonc|html|md|yaml|yml) lane="web" ;;
  py|pyi) lane="python" ;;
  go) lane="go" ;;
  rs) lane="rust" ;;
  java) lane="java" ;;
  *) exit 0 ;;  # not a formatter-owned extension (e.g. .cshtml, .sh) -- nothing to do
esac

# True if any given path exists (config-file detection; unmatched globs pass
# through literally and simply fail the -e test).
cfg() { for _p in "$@"; do [ -e "$_p" ] && return 0; done; return 1; }

# Every formatter runs under a wall-clock bound. This fires after *every* edit, so
# a hang would stall the agent each time, and the harness's kill can land mid
# `--write` and truncate a source file. `timeout`/`gtimeout` is used when present
# and skipped when not (absent on stock macOS/BSD) -- the same degrade-don't-fail
# posture as the missing-jq path above. Plain SIGTERM, no `-k`: not every
# `timeout` build accepts it, and every formatter routed here dies on a signal.
FORMAT_TIMEOUT="${CREW_FORMAT_TIMEOUT:-20}"
timeout_bin=""
for _t in timeout gtimeout; do
  if command -v "$_t" >/dev/null 2>&1; then timeout_bin="$_t"; break; fi
done

# run_bounded <cmd...> — run a formatter quietly under that bound, returning its
# exit status (124 when the bound killed it).
run_bounded() {
  local _st=0
  if [ -n "$timeout_bin" ]; then
    "$timeout_bin" "$FORMAT_TIMEOUT" "$@" >/dev/null 2>&1 || _st=$?
  else
    "$@" >/dev/null 2>&1 || _st=$?
  fi
  return "$_st"
}

# hung <status> — true when the bound killed the tool, so a hang reads
# differently from a tool that ran and rejected the file. 124 is `timeout`'s
# convention, no formatter here exits it of its own accord, and without a timeout
# binary nothing can have been killed.
hung() { [ -n "$timeout_bin" ] && [ "$1" = 124 ]; }

case "$lane" in
  dotnet)
    command -v dotnet >/dev/null 2>&1 || exit 0  # fail open if dotnet isn't available
    # Per-edit formatting favors speed over full coverage: full `dotnet format`
    # evaluates analyzers against the containing project and can take 10-60s on
    # real solutions, so it stays at the review gate
    # (`dotnet format --verify-no-changes`). When the solution configures
    # CSharpier (.csharpierrc) use it here instead — it formats a single file
    # without evaluating the project — else `dotnet format whitespace`, which
    # skips analyzer evaluation.
    if cfg .csharpierrc .csharpierrc.* ; then
      st=0; run_bounded dotnet csharpier format "$path" || st=$?
      if [ "$st" = 0 ]; then
        echo "format hook: ran csharpier on $path" >&2
      elif hung "$st"; then
        echo "format hook: csharpier timed out after ${FORMAT_TIMEOUT}s on $path" >&2
      else
        echo "format hook: csharpier configured but failed (is it restored? 'dotnet tool restore')" >&2
      fi
    else
      st=0; run_bounded dotnet format whitespace --include "$path" || st=$?
      if hung "$st"; then
        echo "format hook: dotnet format whitespace timed out after ${FORMAT_TIMEOUT}s on $path" >&2
      elif [ "$st" != 0 ]; then
        echo "format hook: dotnet format whitespace failed" >&2
      fi
    fi
    ;;
  web)
    [ -f package.json ] || exit 0
    # Apply every formatter/linter the solution configures, not just the first
    # match. Each is detected by its config, run in fix mode scoped to the changed
    # file, and only invoked when installed locally — so a missing tool is a
    # no-op, never an npx download.
    bin="node_modules/.bin"
    ran=""
    # Run a locally-installed tool in fix mode; record it, report failures.
    runfix() {
      _tool="$1"; shift
      [ -x "$bin/$_tool" ] || return 0
      st=0; run_bounded "$bin/$_tool" "$@" || st=$?
      if [ "$st" = 0 ]; then ran="$ran $_tool"
      elif hung "$st"; then echo "format hook: $_tool timed out after ${FORMAT_TIMEOUT}s on $path" >&2
      else echo "format hook: $_tool failed on $path" >&2; fi
    }

    # Biome formats + lints JS/TS/JSON/CSS in one pass when configured.
    cfg biome.json biome.jsonc && runfix biome check --write "$path"

    # Prettier — formatter for most file types.
    { cfg .prettierrc .prettierrc.* prettier.config.* \
      || jq -e '.prettier' package.json >/dev/null 2>&1; } \
      && runfix prettier --write "$path"

    # ESLint — JS/TS autofix.
    case "$ext" in
      js|jsx|ts|tsx|mjs|cjs|vue|svelte)
        { cfg .eslintrc .eslintrc.* eslint.config.* \
          || jq -e '.eslintConfig' package.json >/dev/null 2>&1; } \
          && runfix eslint --fix --cache "$path" ;;
    esac

    # Stylelint — CSS/SCSS/LESS autofix.
    case "$ext" in
      css|scss|sass|less)
        { cfg .stylelintrc .stylelintrc.* stylelint.config.* \
          || jq -e '.stylelint' package.json >/dev/null 2>&1; } \
          && runfix stylelint --fix "$path" ;;
    esac

    if [ -n "$ran" ]; then echo "format hook: applied$ran on $path" >&2
    else echo "format hook: no configured formatter/linter for $path; skipped" >&2; fi
    ;;
  python)
    # Config-gated like the web lane: a tool merely present on the developer's
    # PATH is not the project's choice, and running it would make the file's
    # contents depend on the machine. Run directly rather than through
    # poetry/uv/pdm, which resolve the environment on every call.
    ran=""
    # runpy <label> <cmd...> — run a tool, record it, report failure or a hang.
    runpy() {
      _label="$1"; shift
      st=0; run_bounded "$@" || st=$?
      if [ "$st" = 0 ]; then ran="$ran $_label"
      elif hung "$st"; then echo "format hook: $_label timed out after ${FORMAT_TIMEOUT}s on $path" >&2
      else echo "format hook: $_label failed on $path" >&2; fi
    }
    # `tool_cfg <tool>` — true when the project configures that tool.
    tool_cfg() {
      cfg "$1.toml" ".$1.toml" && return 0
      [ -f pyproject.toml ] && grep -q "^\[tool\.$1" pyproject.toml && return 0
      grep -q "^\[$1\]" setup.cfg tox.ini 2>/dev/null && return 0
      return 1
    }
    if tool_cfg ruff && command -v ruff >/dev/null 2>&1; then
      runpy ruff-format ruff format "$path"
      # --fix applies only ruff's safe fixes; the rest stay for the gate.
      runpy ruff-check ruff check --fix "$path"
    fi
    if tool_cfg black && command -v black >/dev/null 2>&1; then
      runpy black black -q "$path"
    fi
    if [ -n "$ran" ]; then echo "format hook: applied$ran on $path" >&2
    else echo "format hook: no configured Python formatter for $path; skipped" >&2; fi
    ;;
  go)
    # gofumpt is a strict superset of gofmt, so it wins where installed.
    tool=""
    command -v gofmt >/dev/null 2>&1 && tool="gofmt"
    command -v gofumpt >/dev/null 2>&1 && tool="gofumpt"
    [ -n "$tool" ] || { echo "format hook: no Go formatter on PATH for $path; skipped" >&2; exit 0; }
    st=0; run_bounded "$tool" -w "$path" || st=$?
    if [ "$st" = 0 ]; then echo "format hook: applied $tool on $path" >&2
    elif hung "$st"; then echo "format hook: $tool timed out after ${FORMAT_TIMEOUT}s on $path" >&2
    else echo "format hook: $tool failed on $path" >&2; fi
    ;;
  rust)
    # rustfmt, not `cargo fmt`, which formats the whole package. Bare rustfmt does
    # not read Cargo.toml, so pass the edition when it is declared.
    command -v rustfmt >/dev/null 2>&1 || { echo "format hook: rustfmt not on PATH for $path; skipped" >&2; exit 0; }
    # The edition comes from the manifest that OWNS the file, not the one in the
    # working directory: in a workspace those differ, and the wrong edition makes
    # rustfmt reject or misformat valid source.
    _edition_in() { sed -n 's/^[[:space:]]*edition[[:space:]]*=[[:space:]]*"\([0-9]*\)".*/\1/p' "$1" 2>/dev/null | head -1; }
    # Walk up until a manifest states a literal edition. A member that inherits
    # (`edition.workspace = true`) has no such line, so the walk continues to the
    # workspace root's [workspace.package]; absent everywhere, rustfmt defaults.
    edition=""
    _d="${path%/*}"; [ "$_d" = "$path" ] && _d="."
    _n=0
    while [ "$_n" -lt 32 ]; do
      if [ -f "$_d/Cargo.toml" ]; then
        edition="$(_edition_in "$_d/Cargo.toml")"
        [ -n "$edition" ] && break
      fi
      case "$_d" in .|/|"") break ;; esac
      _p="${_d%/*}"; [ "$_p" = "$_d" ] && _p="."
      _d="$_p"; _n=$((_n + 1))
    done
    st=0
    if [ -n "$edition" ]; then
      run_bounded rustfmt --edition "$edition" "$path" || st=$?
    else
      run_bounded rustfmt "$path" || st=$?
    fi
    if [ "$st" = 0 ]; then echo "format hook: applied rustfmt on $path" >&2
    elif hung "$st"; then echo "format hook: rustfmt timed out after ${FORMAT_TIMEOUT}s on $path" >&2
    else echo "format hook: rustfmt failed on $path" >&2; fi
    ;;
  java)
    # Standalone formatters only: Spotless and the Maven plugins format through the
    # build, so they stay at the review gate.
    tool=""
    for _t in google-java-format palantir-java-format; do
      command -v "$_t" >/dev/null 2>&1 && { tool="$_t"; break; }
    done
    [ -n "$tool" ] || { echo "format hook: no standalone Java formatter on PATH for $path; skipped" >&2; exit 0; }
    st=0; run_bounded "$tool" --replace "$path" || st=$?
    if [ "$st" = 0 ]; then echo "format hook: applied $tool on $path" >&2
    elif hung "$st"; then echo "format hook: $tool timed out after ${FORMAT_TIMEOUT}s on $path" >&2
    else echo "format hook: $tool failed on $path" >&2; fi
    ;;
esac
