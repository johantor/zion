#!/usr/bin/env bash
set -e
lane="${1:-}"

case "$lane" in
  dotnet)
    if command -v dotnet >/dev/null 2>&1; then
      if ! dotnet format >/dev/null 2>&1; then
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
  *)
    ;;
esac
