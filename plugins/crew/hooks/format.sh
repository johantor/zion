#!/usr/bin/env bash
# PostToolUse(Edit|Write) formatter, gated to tank/trinity/neo (other agents and the
# main session are no-ops). The formatter set is chosen by the **edited file's extension**,
# not a fixed agent->lane table — so a Node-backend file tank edits still gets web
# tooling, and a .cs/.csproj file gets dotnet/CSharpier regardless of which agent
# produced it (a backend stack can be dotnet or node; lane != language).
set -e

# Fail open: formatting is best-effort, so a missing jq is a no-op, not an error.
command -v jq >/dev/null 2>&1 || exit 0
# Read the payload once; jq from the variable (stdin can only be consumed once).
payload="$(cat)"
agent_type="$(printf '%s' "$payload" | jq -r '.agent_type // empty' 2>/dev/null || true)"
case "$agent_type" in
  # neo is the cross-lane express-lane generalist, so it gets the same
  # extension-based routing as tank/trinity (below) rather than a fixed lane.
  tank|trinity|neo) : ;;
  *)                exit 0 ;;
esac
# Extension-based routing needs a path to route on; without one there's nothing
# to format. Looked up only after the agent gate, so the far more common
# no-op call (any other agent, or the main session) doesn't pay for a second jq.
path="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null || true)"
[ -n "$path" ] || exit 0

ext="${path##*.}"
case "$ext" in
  cs|csproj) lane="dotnet" ;;
  js|jsx|ts|tsx|mjs|cjs|vue|svelte|css|scss|sass|less|json|jsonc|html|md|yaml|yml) lane="web" ;;
  *) exit 0 ;;  # not a formatter-owned extension (e.g. .cshtml, .sh) -- nothing to do
esac

# True if any given path exists (config-file detection; unmatched globs pass
# through literally and simply fail the -e test).
cfg() { for _p in "$@"; do [ -e "$_p" ] && return 0; done; return 1; }

# Every formatter runs under a wall-clock bound. This fires after *every* edit,
# so a hang (stalled tool server, network-bound restore, a tool reading stdin)
# would stall the agent each time, and the harness's kill can land mid `--write`
# and truncate a source file. `timeout`/`gtimeout` is used when present and
# skipped when not (absent on stock macOS/BSD) -- same degrade-don't-fail
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

# hung <status> — true when the bound killed the tool, so a hang is reported
# distinctly from a tool that ran and rejected the file. 124 is `timeout`'s
# convention; no formatter used here exits 124 of its own accord, and without a
# timeout binary nothing can have been killed.
hung() { [ -n "$timeout_bin" ] && [ "$1" = 124 ]; }

case "$lane" in
  dotnet)
    command -v dotnet >/dev/null 2>&1 || exit 0  # fail open if dotnet isn't available
    # Per-edit formatting favors speed over full coverage: full `dotnet format`
    # (whitespace + style + analyzer fixes from .editorconfig) evaluates analyzers
    # against the containing project and can take 10-60s on real solutions — too
    # slow to pay on every edit. It's already the review gate's backend lint check
    # (`dotnet format --verify-no-changes`), run once at the gate. When the
    # solution configures CSharpier (.csharpierrc), use it here instead — it
    # formats a single file directly, without evaluating the project. Otherwise
    # fall back to `dotnet format whitespace`, which skips analyzer evaluation.
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
    # Apply every formatter/linter the solution configures (not just the first
    # match): Biome, Prettier, ESLint, Stylelint. Detect each by its config,
    # run it in fix mode scoped to the changed file, and only invoke the tool if
    # it's installed locally — so a missing tool is a no-op, never an npx download.
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
esac
