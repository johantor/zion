#!/usr/bin/env bash
# PostToolUse(Edit|Write) formatter, routed on `agent_type`: tank formats .NET,
# trinity formats web. Other agents and the main session are no-ops.
set -e

# Fail open: formatting is best-effort, so a missing jq is a no-op, not an error.
command -v jq >/dev/null 2>&1 || exit 0
# Read the payload once; jq from the variable (stdin can only be consumed once).
payload="$(cat)"
agent_type="$(printf '%s' "$payload" | jq -r '.agent_type // empty' 2>/dev/null || true)"
path="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null || true)"
case "$agent_type" in
  tank)    lane="dotnet" ;;
  trinity) lane="web" ;;
  *)       exit 0 ;;
esac

case "$lane" in
  dotnet)
    # Scope to the changed file so we don't reformat the whole solution on every
    # edit (slow on large repos); fall back to the project if the path is unknown.
    if command -v dotnet >/dev/null 2>&1; then
      if [ -n "$path" ]; then
        dotnet format --include "$path" >/dev/null 2>&1 || echo "format hook: dotnet format failed" >&2
      else
        dotnet format >/dev/null 2>&1 || echo "format hook: dotnet format failed" >&2
      fi
    fi
    ;;
  web)
    [ -f package.json ] || exit 0
    command -v npm >/dev/null 2>&1 || exit 0  # fail open if npm isn't available
    # The format/fix script name varies per project, so discover it from
    # package.json rather than hardcoding. Prefer write/fix scripts in order;
    # skip check-only scripts (a PostToolUse hook should fix, not just report).
    fmt=""
    for cand in format format:fix format:write fix lint:fix biome:format prettier:write prettier; do
      if jq -e --arg s "$cand" '.scripts[$s]' package.json >/dev/null 2>&1; then
        fmt="$cand"; break
      fi
    done
    if [ -n "$fmt" ]; then
      npm run -s "$fmt" >/dev/null 2>&1 \
        && echo "format hook: ran npm run -s $fmt" >&2 \
        || echo "format hook: npm run -s $fmt failed" >&2
    else
      echo "format hook: no write-mode format script in package.json; skipped" >&2
    fi
    ;;
esac
