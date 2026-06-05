#!/usr/bin/env bash
# PostToolUse(Edit|Write) formatter, routed on `agent_type`: tank formats .NET,
# trinity formats web. Other agents and the main session are no-ops.
set -e

# Fail open: formatting is best-effort, so a missing jq is a no-op, not an error.
command -v jq >/dev/null 2>&1 || exit 0
agent_type="$(jq -r '.agent_type // empty' 2>/dev/null || true)"
case "$agent_type" in
  tank)    lane="dotnet" ;;
  trinity) lane="web" ;;
  *)       exit 0 ;;
esac

case "$lane" in
  dotnet)
    if command -v dotnet >/dev/null 2>&1; then
      if ! dotnet format >/dev/null; then
        echo "format hook: dotnet format failed" >&2
      fi
    fi
    ;;
  web)
    if [ -f package.json ]; then
      if npm run -s lint:fix >/dev/null 2>&1; then
        echo "format hook: ran npm run -s lint:fix" >&2
      elif npm run -s format >/dev/null 2>&1; then
        echo "format hook: ran npm run -s format" >&2
      elif npm run -s lint >/dev/null 2>&1; then
        echo "format hook: ran npm run -s lint" >&2
      else
        echo "format hook: no runnable npm format/lint script found" >&2
      fi
    fi
    ;;
esac
